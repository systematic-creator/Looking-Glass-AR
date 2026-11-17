class_name ARSession
extends Node
## World-locked phone-camera AR for one game board (view layer only).
##
## Scene shape (built by GameHost):
##   WorldAnchor (Node3D)      <- AnchorService pose (yaw-only, world space)
##     BoardPivot (Node3D)     <- BoardPlacement: magnify, offset, yaw, scale
##       Game (LGGame)         <- everything the game draws, in board space
##       BoardFrame            <- footprint outline, shown while adjusting
##   XROrigin3D / XRCamera3D   <- created here in AR mode only
##
## AR mode: ARCore session + camera passthrough, driven by a CalibrationFlow:
## scan (live tracking status, feature points and found surfaces drawn on the
## video) -> a reticle on a surface + "Place board" -> adjust (drag / pinch /
## twist) -> Lock. If no surface turns up, "Place in front of me" anchors the
## board ~0.6 m ahead and "Play without AR" drops to the touch camera, so the
## player is never stuck. The game is paused (LGGame.is_playing() false)
## until the board is locked. Locked, touches go to the game (GameHost routes
## them in board space) and pinch magnifies if Magnify is on.
##
## Fallback mode (no ARCore: desktop, headless, unsupported phone, or the
## player chose "Play without AR"): the host's orbit camera, an identity
## anchor and an identity pivot. The board counts as locked at once.

## The board's locked state changed (fallback counts as locked).
signal board_lock_changed(locked: bool)
## The board was placed on a surface (or in front of the camera).
signal board_placed()
## AR stopped and the touch camera took over.
signal fell_back(reason: String)

enum Mode { FALLBACK, AR }
enum Phase { SEARCHING, READY, PLACED }

const RETICLE_RADIUS: float = 0.06
## "Place in front of me": metres ahead of and below the phone.
const FRONT_PLACE_DISTANCE: float = 0.6
const FRONT_PLACE_DROP: float = 0.35
## Seconds between diagnostics / surface overlay refreshes.
const DIAG_INTERVAL: float = 0.2
const MAX_OVERLAY_POINTS: int = 400
## Seconds to wait for ARCore to report an initialized session before falling back.
const START_GRACE_SECONDS: float = 6.0

var mode: Mode = Mode.FALLBACK
var phase: Phase = Phase.SEARCHING
var magnify_enabled: bool = false
var fallback_reason: String = ""

var world_anchor: Node3D
var pivot: Node3D
## The touch / desktop camera used outside AR.
var fallback_camera: Camera3D
var environment: Environment
## Footprint outline under the pivot; visible while the AR board is unlocked.
var board_frame: Node3D
## Where this game's placement (size, rotation) is saved.
var placement_path: String = BoardPlacement.SAVE_PATH

var bridge: ARCoreBridge
var anchors: AnchorService
var placement: BoardPlacement = BoardPlacement.new()
var gestures: GestureTracker = GestureTracker.new()
var hud: CalibrationHud
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var reticle: Node3D
var flow: CalibrationFlow = CalibrationFlow.new()
## Tests inject a fake bridge here; returns an ARCoreBridge.
var bridge_factory: Callable = Callable()
var tracking_info: Dictionary = {}
## True while a "Place in front of me" board is held camera-relative because
## ARCore was not tracking yet; it becomes a world anchor once tracking holds.
var front_follow: bool = false

var _adjusting: bool = false
var _start_elapsed: float = 0.0
var _saved_background: int = Environment.BG_COLOR
var _awaiting_camera: bool = false
var _camera_denied: bool = false
var _permission_poll: float = 0.0
var _diag_elapsed: float = 0.0
var _overlay: Node3D
var _overlay_points: MultiMeshInstance3D
var _overlay_planes: Node3D
var _last_locked: bool = false


## Pick a mode from what the runtime offers (pure, unit-tested).
static func choose_mode(plugin_present: bool, xr_interface: XRInterface) -> Mode:
	if plugin_present and xr_interface != null:
		return Mode.AR
	return Mode.FALLBACK


## Wire up references, then start AR if possible (else the fallback).
func setup(p_world_anchor: Node3D, p_pivot: Node3D, p_fallback_camera: Camera3D, p_environment: Environment) -> void:
	world_anchor = p_world_anchor
	pivot = p_pivot
	fallback_camera = p_fallback_camera
	environment = p_environment
	if bridge_factory.is_valid():
		if try_start_ar():
			return
	elif ARCoreBridge.plugin_present():
		if not ARCoreBridge.camera_permission_granted():
			# Hold the board in the fallback view until the camera is allowed,
			# then switch to AR (polled in _process; see _poll_camera_permission).
			fallback_reason = "Waiting for camera permission."
			_awaiting_camera = true
			if not get_tree().on_request_permissions_result.is_connected(_on_permission_result):
				get_tree().on_request_permissions_result.connect(_on_permission_result)
			OS.request_permission(ARCoreBridge.CAMERA_PERMISSION)
			_enter_fallback()
			return
		if try_start_ar():
			return
	elif fallback_reason.is_empty():
		fallback_reason = "No AR interface (desktop, headless, or a non-AR build)."
	_enter_fallback()


## Start (or resume) ARCore and enter AR mode; on failure keep the fallback.
func try_start_ar() -> bool:
	if bridge_factory.is_valid():
		bridge = bridge_factory.call() as ARCoreBridge
		if bridge != null and not bridge.start(get_viewport()):
			fallback_reason = bridge.failure_reason
			bridge = null
	else:
		var reason: Array = []
		bridge = ARCoreBridge.acquire(get_viewport(), reason)
		if bridge == null and not reason.is_empty():
			fallback_reason = str(reason[0])
	if bridge != null:
		_enter_ar()
		return true
	push_warning("AR disabled: %s" % fallback_reason)
	_sync_play()
	return false


## The camera was refused: play in the fallback view (keep polling in case
## the player grants it later from a second prompt or the settings).
func _on_permission_result(permission: String, granted: bool) -> void:
	if permission == ARCoreBridge.CAMERA_PERMISSION and not granted and mode == Mode.FALLBACK:
		_camera_denied = true
		fallback_reason = "Camera permission denied."
		_sync_play()


func is_ar() -> bool:
	return mode == Mode.AR


func is_placed() -> bool:
	return phase == Phase.PLACED


## True once the board is locked in AR, or in the fallback view (unless we
## are still waiting for the camera permission).
func is_board_locked() -> bool:
	if mode == Mode.AR:
		return flow.should_run_game()
	return not _awaiting_camera or _camera_denied


## True while AR owns touch input (placement, or adjusting while unlocked).
func captures_touch() -> bool:
	return is_ar() and (phase != Phase.PLACED or not placement.locked)


## The camera the player currently sees through.
func active_camera() -> Camera3D:
	if is_ar() and xr_camera != null:
		return xr_camera
	return fallback_camera


# --- Modes ------------------------------------------------------------------

func _enter_fallback() -> void:
	mode = Mode.FALLBACK
	anchors = AnchorService.new(LocalAnchorBackend.new())
	anchors.place_at_pose(Transform3D.IDENTITY)
	placement = BoardPlacement.new()
	placement.scale = 1.0
	phase = Phase.PLACED
	if fallback_camera != null:
		fallback_camera.current = true
	apply_anchor_pose(Transform3D.IDENTITY)
	if pivot != null:
		pivot.transform = Transform3D.IDENTITY
	if world_anchor != null:
		world_anchor.visible = true
	_sync_play()


func _enter_ar() -> void:
	mode = Mode.AR
	phase = Phase.SEARCHING
	anchors = AnchorService.new(ARCoreAnchorBackend.new(bridge))
	anchors.tracking_changed.connect(_on_anchor_tracking_changed)
	placement = BoardPlacement.new()
	placement.load_from(placement_path)
	# Keep the saved size / rotation, but every session starts unlocked: the
	# board has to be placed again in this room.
	placement.locked = false
	flow.restart()
	tracking_info = {}
	xr_origin = XROrigin3D.new()
	xr_origin.name = "XROrigin3D"
	add_child(xr_origin)
	xr_camera = XRCamera3D.new()
	xr_camera.name = "XRCamera3D"
	xr_camera.near = 0.01
	xr_camera.far = 50.0
	xr_origin.add_child(xr_camera)
	xr_camera.current = true
	if environment != null:
		_saved_background = environment.background_mode
		# Let the ARCore background renderer's camera image show through.
		environment.background_mode = Environment.BG_CAMERA_FEED
	if fallback_camera != null:
		fallback_camera.current = false
	reticle = _make_reticle()
	add_child(reticle)
	reticle.visible = false
	_overlay = _make_overlay()
	add_child(_overlay)
	if world_anchor != null:
		world_anchor.visible = false
	hud = CalibrationHud.new()
	add_child(hud)
	hud.lock_toggled.connect(set_locked)
	hud.magnify_toggled.connect(func(on: bool) -> void: magnify_enabled = on)
	hud.recenter_pressed.connect(recenter)
	hud.replace_pressed.connect(begin_replace)
	hud.place_pressed.connect(func() -> void: place_at_reticle())
	hud.place_in_front_pressed.connect(func() -> void: place_in_front())
	hud.play_without_ar_pressed.connect(func() -> void: fall_back("Player chose to play without AR."))
	hud.apply_flow(flow)
	_sync_play()


## Leave AR for the touch camera (ARCore failed, or the player asked).
func fall_back(reason: String) -> void:
	if mode != Mode.AR:
		return
	fallback_reason = reason
	_teardown_ar()
	_enter_fallback()
	push_warning("AR disabled: %s" % reason)
	fell_back.emit(reason)


## Give the AR session back (the game is closing). Safe in any mode.
func shutdown() -> void:
	if mode == Mode.AR:
		_teardown_ar()
	mode = Mode.FALLBACK


func _teardown_ar() -> void:
	front_follow = false
	if anchors != null:
		anchors.clear()
	if bridge != null:
		bridge.release(get_viewport())
		bridge = null
	get_viewport().use_xr = false
	if xr_origin != null:
		xr_origin.queue_free()
		xr_origin = null
		xr_camera = null
	if reticle != null:
		reticle.queue_free()
		reticle = null
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
		_overlay_points = null
		_overlay_planes = null
	if hud != null:
		hud.queue_free()
		hud = null
	if environment != null:
		environment.background_mode = _saved_background as Environment.BGMode
	if fallback_camera != null:
		fallback_camera.current = true


# --- Placement / adjustment ---------------------------------------------------

## Place (or re-place) the board on the surface under the reticle.
func place_at_reticle() -> bool:
	if not is_ar() or phase == Phase.PLACED:
		return false
	if not anchors.place_at_screen(Vector2(0.5, 0.5)):
		return false
	front_follow = false
	flow.anchor_pending = false
	_after_placed()
	return true


## Fallback when no surface is found: put the board ~0.6 m in front of and
## below the phone, level and facing the player. With stable ARCore tracking
## it is world-anchored at once; otherwise it is held camera-relative (so it
## never slides away on a bad camera pose) and anchored once tracking holds.
func place_in_front() -> bool:
	if not is_ar() or phase == Phase.PLACED or xr_camera == null:
		return false
	var pose: Transform3D = _front_local_pose()
	if flow.tracking_stable() and anchors.place_at_pose(pose):
		front_follow = false
		flow.anchor_pending = false
	else:
		anchors.clear()
		anchors.pose = AnchorService.upright(pose)
		front_follow = true
		flow.anchor_pending = true
	_after_placed()
	return true


## front_pose() of the XR camera, in XROrigin3D space (what anchors use).
func _front_local_pose() -> Transform3D:
	var pose: Transform3D = front_pose(xr_camera.global_transform)
	var origin_xform: Transform3D = xr_origin.global_transform if xr_origin != null else Transform3D.IDENTITY
	return origin_xform.affine_inverse() * pose


## Keep a camera-held board in front of the camera; anchor it in the world
## as soon as ARCore has tracked continuously for a moment.
func _update_front_follow() -> void:
	anchors.pose = AnchorService.upright(_front_local_pose())
	if flow.tracking_stable() and anchors.place_at_pose(anchors.pose):
		front_follow = false
		flow.anchor_pending = false
		if hud != null:
			hud.apply_flow(flow)
	_apply_transforms()


## World pose FRONT_PLACE_DISTANCE ahead of (and FRONT_PLACE_DROP below) a
## camera, level, with -Z pointing away from the player. Pure; unit-tested.
static func front_pose(camera: Transform3D) -> Transform3D:
	var forward: Vector3 = -camera.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		forward = -camera.basis.y if absf(camera.basis.z.y) > 0.5 else Vector3.FORWARD
		forward.y = 0.0
		if forward.length() < 0.001:
			forward = Vector3.FORWARD
	forward = forward.normalized()
	var origin: Vector3 = camera.origin + forward * FRONT_PLACE_DISTANCE + Vector3.DOWN * FRONT_PLACE_DROP
	return Transform3D(Basis.looking_at(forward, Vector3.UP), origin)


func _after_placed() -> void:
	phase = Phase.PLACED
	flow.placed()
	if reticle != null:
		reticle.visible = false
	if _overlay != null:
		_overlay.visible = false
	world_anchor.visible = true
	_apply_transforms()
	if hud != null:
		hud.apply_flow(flow)
	board_placed.emit()
	_sync_play()


func begin_replace() -> void:
	if not is_ar():
		return
	front_follow = false
	anchors.clear()
	phase = Phase.SEARCHING
	placement.locked = false
	flow.restart()
	world_anchor.visible = false
	if _overlay != null:
		_overlay.visible = true
	if hud != null:
		hud.apply_flow(flow)
	_sync_play()


func recenter() -> void:
	placement.recenter()
	placement.save(placement_path)
	_apply_transforms()


func set_locked(locked: bool) -> void:
	if not is_ar() or phase != Phase.PLACED:
		return
	placement.locked = locked
	placement.save(placement_path)
	gestures.reset()
	flow.set_locked(locked)
	if hud != null:
		hud.apply_flow(flow)
	_sync_play()


func _sync_play() -> void:
	var locked: bool = is_board_locked()
	if board_frame != null:
		board_frame.visible = is_ar() and phase == Phase.PLACED and not locked
	if locked != _last_locked:
		_last_locked = locked
		board_lock_changed.emit(locked)


## Put the world anchor at `anchor_pose` (XROrigin3D space, made upright).
func apply_anchor_pose(anchor_pose: Transform3D) -> void:
	if world_anchor == null:
		return
	var origin_xform: Transform3D = xr_origin.global_transform if xr_origin != null else Transform3D.IDENTITY
	world_anchor.global_transform = origin_xform * AnchorService.upright(anchor_pose)


## Re-apply the anchor pose and the placement to the scene.
func _apply_transforms() -> void:
	apply_anchor_pose(anchors.pose)
	if pivot != null:
		pivot.transform = placement.pivot_transform()


# --- Per frame ----------------------------------------------------------------

func _process(delta: float) -> void:
	if mode != Mode.AR:
		if _awaiting_camera:
			_poll_camera_permission(delta)
		return
	if not bridge.is_running():
		_start_elapsed += delta
		if _start_elapsed > START_GRACE_SECONDS:
			fall_back("ARCore session did not start.")
		return
	_start_elapsed = 0.0
	_diag_elapsed += delta
	var refresh: bool = _diag_elapsed >= DIAG_INTERVAL
	if refresh:
		_diag_elapsed = 0.0
		tracking_info = bridge.diagnostics()
		if hud != null:
			var forced: bool = bool(tracking_info.get("debuggable", false)) or flow.offers_fallback() or front_follow
			hud.set_debug_text(CalibrationFlow.debug_line(tracking_info), forced)
	if phase != Phase.PLACED:
		var found: bool = _update_reticle()
		flow.update(delta, tracking_info, found)
		if refresh:
			_update_overlay()
		if hud != null:
			hud.apply_flow(flow)
		return
	flow.observe(delta, tracking_info)
	if front_follow:
		_update_front_follow()
	else:
		anchors.poll()
		_apply_transforms()


func _poll_camera_permission(delta: float) -> void:
	_permission_poll += delta
	if _permission_poll < 0.5:
		return
	_permission_poll = 0.0
	if not ARCoreBridge.camera_permission_granted():
		return
	_awaiting_camera = false
	_camera_denied = false
	if not try_start_ar():
		_sync_play()


func _update_reticle() -> bool:
	var hit: Dictionary = bridge.hit_test(Vector2(0.5, 0.5))
	var found: bool = bool(hit.get("hit", false))
	reticle.visible = found
	if found:
		var origin_xform: Transform3D = xr_origin.global_transform
		reticle.global_transform = origin_xform * AnchorService.upright(hit["pose"] as Transform3D)
		phase = Phase.READY
	else:
		phase = Phase.SEARCHING
	return found


## Draw what ARCore sees: feature points and found surfaces, so the player
## can tell scanning is making progress.
func _update_overlay() -> void:
	if _overlay == null:
		return
	var origin_xform: Transform3D = xr_origin.global_transform if xr_origin != null else Transform3D.IDENTITY
	_overlay.global_transform = origin_xform
	var points: PackedVector3Array = bridge.point_cloud(MAX_OVERLAY_POINTS)
	var multimesh: MultiMesh = _overlay_points.multimesh
	multimesh.instance_count = points.size()
	for i: int in points.size():
		multimesh.set_instance_transform(i, Transform3D(Basis(), points[i]))
	for child: Node in _overlay_planes.get_children():
		child.queue_free()
	for entry: Variant in bridge.horizontal_planes():
		var plane: Dictionary = entry as Dictionary
		var mesh: ArrayMesh = plane_mesh(plane.get("polygon", PackedVector2Array()) as PackedVector2Array)
		if mesh == null:
			continue
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = _surface_material()
		instance.transform = plane.get("pose", Transform3D.IDENTITY) as Transform3D
		_overlay_planes.add_child(instance)


## Triangle fan for a plane polygon in plane-local (x, z). Null if degenerate.
static func plane_mesh(polygon: PackedVector2Array) -> ArrayMesh:
	if polygon.size() < 3:
		return null
	var vertices := PackedVector3Array()
	var center := Vector2.ZERO
	for p: Vector2 in polygon:
		center += p
	center /= float(polygon.size())
	for i: int in polygon.size():
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		vertices.append(Vector3(center.x, 0.002, center.y))
		vertices.append(Vector3(b.x, 0.002, b.y))
		vertices.append(Vector3(a.x, 0.002, a.y))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


var _surface_mat: StandardMaterial3D
func _surface_material() -> StandardMaterial3D:
	if _surface_mat == null:
		_surface_mat = StandardMaterial3D.new()
		_surface_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_surface_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_surface_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_surface_mat.albedo_color = Color(0.35, 0.95, 1.0, 0.28)
	return _surface_mat


func _make_overlay() -> Node3D:
	var root := Node3D.new()
	root.name = "ScanOverlay"
	_overlay_points = MultiMeshInstance3D.new()
	_overlay_points.name = "FeaturePoints"
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var dot := SphereMesh.new()
	dot.radius = 0.004
	dot.height = 0.008
	dot.radial_segments = 6
	dot.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.92, 0.35)
	dot.material = material
	multimesh.mesh = dot
	_overlay_points.multimesh = multimesh
	root.add_child(_overlay_points)
	_overlay_planes = Node3D.new()
	_overlay_planes.name = "Surfaces"
	root.add_child(_overlay_planes)
	return root


## Android lifecycle -> ARCore session (the plugin does not hook it itself).
func _notification(what: int) -> void:
	if bridge == null or mode != Mode.AR:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED:
		bridge.pause()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		bridge.resume()


# --- Input --------------------------------------------------------------------

## Calibration input: tap to place, drag / pinch / twist to adjust, and pinch
## to magnify once locked (if Magnify is on). Everything else is the game's,
## routed by GameHost.
func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.AR or not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed and hud != null:
		if hud.is_over_ui((event as InputEventScreenTouch).position):
			return
	var gesture: Dictionary = gestures.handle(event)
	if phase != Phase.PLACED:
		if gesture.get("kind", &"") == &"tap" and phase == Phase.READY:
			place_at_reticle()
		return
	if placement.locked:
		if magnify_enabled and gesture.get("kind", &"") == &"pinch":
			placement.magnify_by(float(gesture["scale"]))
		return
	match gesture.get("kind", &"") as StringName:
		&"drag":
			var before: Variant = _anchor_point(gesture["from"] as Vector2)
			var after: Variant = _anchor_point(gesture["to"] as Vector2)
			if before != null and after != null:
				_adjusting = placement.drag((after as Vector3) - (before as Vector3))
		&"pinch":
			placement.pinch(float(gesture["scale"]))
			# Screen clockwise twist turns the table clockwise seen from above.
			placement.twist(-float(gesture["twist"]))
			_adjusting = true
	if _adjusting and gestures.touch_count() == 0:
		_adjusting = false
		placement.save(placement_path)


## Screen point -> point on the anchor's ground plane, in anchor space.
func _anchor_point(screen: Vector2) -> Variant:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or world_anchor == null:
		return null
	var ground := Plane(world_anchor.global_transform.basis.y.normalized(), world_anchor.global_position)
	var hit: Variant = ground.intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if hit == null:
		return null
	return world_anchor.to_local(hit as Vector3)


func _on_anchor_tracking_changed(state: int) -> void:
	if hud == null or phase != Phase.PLACED:
		return
	if state == AnchorBackend.Tracking.TRACKING:
		hud.apply_flow(flow)
	else:
		hud.set_status("Tracking lost. Point the phone back at the board and hold still.")


func _make_reticle() -> Node3D:
	var root := Node3D.new()
	root.name = "PlacementReticle"
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RETICLE_RADIUS * 0.82
	torus.outer_radius = RETICLE_RADIUS
	torus.rings = 32
	torus.ring_segments = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.35, 0.95, 1.0, 0.9)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	torus.material = material
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.15, 1.0)
	root.add_child(ring)
	return root
