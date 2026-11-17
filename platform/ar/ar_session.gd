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
## A plane counts as "the same surface" within this height difference (m).
const PLANE_HEIGHT_TOLERANCE: float = 0.03
## Traced points over a surface this much higher than the traced one are
## rejected (the finger is on an object standing on the play area).
const TRACE_HEIGHT_TOLERANCE: float = 0.04
const TRACE_MIN_SPACING: float = 0.01
const TRACE_MAX_RADIUS: float = 3.0
## Drag rays flatter than this (|dot(ray, up)|) are ignored: near the horizon
## a finger's pixel moves the board metres.
const MIN_RAY_ELEVATION: float = 0.12
const MAX_RAY_DISTANCE: float = 4.0
const MAX_DRAG_STEP: float = 0.15

## The outline traced most recently in this app session (XROrigin3D space,
## closed polygon at one height), offered as "Use traced area" next time.
static var saved_area_world: PackedVector3Array = PackedVector3Array()

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
## The game's footprint at scale 1 (metres), for fitting and clamping.
var board_size: Vector2 = Vector2(0.4, 0.4)
## Where the board must stay (anchor space): the traced outline or the
## placed-on plane's polygon. Null when unknown (no plane, camera-held).
var region: SurfaceRegion
## Appended to the AR debug line (e.g. GameHost's tap diagnostics).
var extra_debug: String = ""

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
var _region_node: MeshInstance3D
var _trace_node: MeshInstance3D
var _trace_points: PackedVector3Array = PackedVector3Array()
var _trace_height: float = 0.0
var _trace_touch: int = -1
var _region_refresh: float = 0.0


static func clear_saved_area() -> void:
	saved_area_world = PackedVector3Array()


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
	flow.has_saved_area = saved_area_world.size() >= 3
	region = null
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
	hud.trace_pressed.connect(func() -> void: begin_trace())
	hud.use_area_pressed.connect(func() -> void: use_saved_area())
	hud.trace_done_pressed.connect(func() -> void: finish_trace())
	hud.trace_clear_pressed.connect(clear_trace)
	hud.trace_cancel_pressed.connect(cancel_trace)
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
	_clear_region()
	clear_trace()
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
	placement.offset = Vector3.ZERO
	placement.magnify = 1.0
	_set_region(select_plane_region(anchors.pose.origin))
	_fit_into_region()
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
	_clear_region()
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
	_clear_region()
	clear_trace()
	flow.has_saved_area = saved_area_world.size() >= 3
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
	placement.offset = constrain_offset(placement.offset)
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
	if _region_node != null:
		_region_node.visible = is_ar() and phase == Phase.PLACED and not locked
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
			var line: String = CalibrationFlow.debug_line(tracking_info) + debug_suffix()
			hud.set_debug_text(line, forced)
	if phase != Phase.PLACED:
		if flow.step == CalibrationFlow.Step.TRACING:
			reticle.visible = false
			flow.update(delta, tracking_info, true)
			if refresh:
				_update_overlay()
			if hud != null:
				hud.apply_flow(flow)
			return
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
	if region != null and region.source == SurfaceRegion.Source.PLANE and not placement.locked:
		_region_refresh += delta
		if _region_refresh >= 1.0:
			_region_refresh = 0.0
			var grown: SurfaceRegion = select_plane_region(anchors.pose.origin)
			if grown != null:
				_set_region(grown)


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
	if flow.step == CalibrationFlow.Step.TRACING:
		_trace_input(event)
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
			_adjusting = drag_board(gesture["from"] as Vector2, gesture["to"] as Vector2)
		&"pinch":
			# Screen clockwise twist turns the table clockwise seen from above.
			resize_board(float(gesture["scale"]), -float(gesture["twist"]))
			_adjusting = true
	if _adjusting and gestures.touch_count() == 0:
		_adjusting = false
		placement.save(placement_path)


## Screen point -> point on the anchor's own (selected) surface plane, in
## anchor space. Never re-hit-tests other planes, so a drag cannot jump to
## the floor; flat rays near the horizon are ignored.
func _anchor_point(screen: Vector2) -> Variant:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or world_anchor == null:
		return null
	var up: Vector3 = world_anchor.global_transform.basis.y.normalized()
	var origin: Vector3 = camera.project_ray_origin(screen)
	var direction: Vector3 = camera.project_ray_normal(screen)
	if absf(direction.dot(up)) < MIN_RAY_ELEVATION:
		return null
	var ground := Plane(up, world_anchor.global_position)
	var hit: Variant = ground.intersects_ray(origin, direction)
	if hit == null or origin.distance_to(hit as Vector3) > MAX_RAY_DISTANCE:
		return null
	return world_anchor.to_local(hit as Vector3)


## Move the unlocked board by a screen drag, on its own surface, kept inside
## the play area. Returns true if it moved.
func drag_board(from_screen: Vector2, to_screen: Vector2) -> bool:
	if placement.locked:
		return false
	var before: Variant = _anchor_point(from_screen)
	var after: Variant = _anchor_point(to_screen)
	if before == null or after == null:
		return false
	var delta: Vector3 = ((after as Vector3) - (before as Vector3)) / placement.magnify
	delta.y = 0.0
	if delta.length() > MAX_DRAG_STEP:
		delta = delta.normalized() * MAX_DRAG_STEP
	var target: Vector3 = constrain_offset(placement.offset + delta)
	if target.is_equal_approx(placement.offset):
		return false
	placement.offset = target
	return true


## Pinch / twist the unlocked board; refused if it would not fit the area.
func resize_board(factor: float, delta_yaw: float) -> bool:
	if placement.locked or factor <= 0.0:
		return false
	var scale: float = clampf(placement.scale * factor, BoardPlacement.MIN_SCALE, BoardPlacement.MAX_SCALE)
	var yaw: float = wrapf(placement.yaw + delta_yaw, -PI, PI)
	if region == null or not region.is_valid():
		placement.scale = scale
		placement.yaw = yaw
		return true
	var center: Variant = region.clamp_center(Vector2(placement.offset.x, placement.offset.z), board_size * 0.5 * scale, yaw)
	if center == null:
		# Too big for the area at this angle: try just the rotation.
		center = region.clamp_center(Vector2(placement.offset.x, placement.offset.z), board_size * 0.5 * placement.scale, yaw)
		if center == null:
			return false
		scale = placement.scale
	placement.scale = scale
	placement.yaw = yaw
	placement.offset = Vector3((center as Vector2).x, 0.0, (center as Vector2).y)
	return true


## The nearest anchor-space offset where the whole footprint stays inside
## the play area (unchanged if there is no area, or nothing fits).
func constrain_offset(proposed: Vector3) -> Vector3:
	if region == null or not region.is_valid():
		return Vector3(proposed.x, 0.0, proposed.z)
	var half: Vector2 = board_size * 0.5 * placement.scale
	var current := Vector2(placement.offset.x, placement.offset.z)
	var center: Variant = region.clamp_center(Vector2(proposed.x, proposed.z), half, placement.yaw, current)
	if center == null:
		return placement.offset
	return Vector3((center as Vector2).x, 0.0, (center as Vector2).y)


# --- Play area: selected plane / traced outline ------------------------------------

## Normalized-screen hit test for a screen position (viewport coordinates).
func hit_at(screen: Vector2) -> Dictionary:
	if bridge == null:
		return {"hit": false}
	var size: Vector2 = get_viewport().get_visible_rect().size
	return bridge.hit_test(Vector2(screen.x / maxf(1.0, size.x), screen.y / maxf(1.0, size.y)))


## The tracked plane under `origin_point` (XROrigin3D space) at its height,
## as a SurfaceRegion in the current anchor's space; null if none matches.
func select_plane_region(origin_point: Vector3) -> SurfaceRegion:
	if bridge == null:
		return null
	var best: Dictionary = {}
	var best_gap: float = INF
	for entry: Variant in bridge.horizontal_planes():
		var plane: Dictionary = entry as Dictionary
		var pose: Transform3D = plane.get("pose", Transform3D.IDENTITY) as Transform3D
		var polygon: PackedVector2Array = plane.get("polygon", PackedVector2Array()) as PackedVector2Array
		var gap: float = absf(pose.origin.y - origin_point.y)
		if polygon.size() < 3 or gap > PLANE_HEIGHT_TOLERANCE:
			continue
		var local: Vector3 = pose.affine_inverse() * origin_point
		if not Geometry2D.is_point_in_polygon(Vector2(local.x, local.z), polygon):
			continue
		if gap < best_gap:
			best_gap = gap
			best = plane
	if best.is_empty():
		return null
	var to_anchor: Transform3D = anchors.pose.affine_inverse() * (best["pose"] as Transform3D)
	var points := PackedVector2Array()
	for p: Vector2 in best["polygon"] as PackedVector2Array:
		var a: Vector3 = to_anchor * Vector3(p.x, 0.0, p.y)
		points.append(Vector2(a.x, a.z))
	return SurfaceRegion.make(points, SurfaceRegion.Source.PLANE)


## Keep the just-placed board inside the region: slide it in, or shrink it
## (never below MIN_SCALE). Gives up on the region if nothing fits.
func _fit_into_region() -> void:
	if region == null or not region.is_valid():
		return
	var center: Variant = region.clamp_center(Vector2.ZERO, board_size * 0.5 * placement.scale, placement.yaw)
	if center == null:
		var fit: Dictionary = region.fit_board(board_size, BoardPlacement.MIN_SCALE, placement.scale)
		if fit.is_empty():
			_clear_region()
			return
		placement.scale = float(fit["scale"])
		placement.yaw = float(fit["yaw"])
		center = fit["center"]
	placement.offset = Vector3((center as Vector2).x, 0.0, (center as Vector2).y)


func _set_region(p_region: SurfaceRegion) -> void:
	region = p_region
	if _region_node != null:
		_region_node.queue_free()
		_region_node = null
	if region == null or world_anchor == null:
		return
	_region_node = MeshInstance3D.new()
	_region_node.name = "PlayArea"
	_region_node.mesh = SurfaceRegion.outline_mesh(region.polygon, true, 0.01 if region.source == SurfaceRegion.Source.TRACED else 0.006)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(1.0, 0.85, 0.3, 0.95) if region.source == SurfaceRegion.Source.TRACED else Color(0.35, 0.95, 1.0, 0.6)
	_region_node.material_override = material
	world_anchor.add_child(_region_node)
	_region_node.visible = is_ar() and phase == Phase.PLACED and not placement.locked


func _clear_region() -> void:
	_set_region(null)


## "Trace play area": draw around the area with one finger.
func begin_trace() -> bool:
	if not is_ar() or phase == Phase.PLACED or not flow.begin_trace():
		return false
	clear_trace()
	reticle.visible = false
	if hud != null:
		hud.apply_flow(flow)
	return true


func cancel_trace() -> void:
	clear_trace()
	flow.cancel_trace()
	if hud != null:
		hud.apply_flow(flow)


func clear_trace() -> void:
	_trace_points = PackedVector3Array()
	_trace_touch = -1
	flow.trace_points = 0
	if _trace_node != null:
		_trace_node.queue_free()
		_trace_node = null
	if hud != null:
		hud.apply_flow(flow)


func trace_point_count() -> int:
	return _trace_points.size()


## Begin (or continue) the outline at a screen point. The first point must
## land on a detected surface; it fixes the traced height.
func trace_begin(screen: Vector2) -> bool:
	if flow.step != CalibrationFlow.Step.TRACING:
		return false
	if _trace_points.is_empty():
		var hit: Dictionary = hit_at(screen)
		if not bool(hit.get("hit", false)):
			flow.trace_error = "Start your outline on the surface (where the teal area is)."
			if hud != null:
				hud.apply_flow(flow)
			return false
		_trace_height = (hit["pose"] as Transform3D).origin.y
		flow.trace_error = ""
	return trace_add(screen)


## Add a stroke point: the finger's ray meets the traced surface's own height
## (an infinite plane), so tracing past a real edge never drops to the floor.
## Points over a clearly higher surface (an object on the area) are rejected.
func trace_add(screen: Vector2) -> bool:
	var point: Variant = _project_to_height(screen, _trace_height)
	if point == null:
		return false
	var p: Vector3 = point as Vector3
	var hit: Dictionary = hit_at(screen)
	if bool(hit.get("hit", false)) and (hit["pose"] as Transform3D).origin.y - _trace_height > TRACE_HEIGHT_TOLERANCE:
		return false
	if not _trace_points.is_empty():
		if Vector2(p.x, p.z).distance_to(Vector2(_trace_points[0].x, _trace_points[0].z)) > TRACE_MAX_RADIUS:
			return false
		var last: Vector3 = _trace_points[_trace_points.size() - 1]
		if Vector2(p.x, p.z).distance_to(Vector2(last.x, last.z)) < TRACE_MIN_SPACING:
			return false
	_trace_points.append(p)
	flow.trace_points = _trace_points.size()
	_update_trace_preview()
	return true


## Finger lifted: close the outline if it came back near its start.
## Returns true if the board was placed.
func trace_end() -> bool:
	if _trace_points.size() < 3:
		if hud != null:
			hud.apply_flow(flow)
		return false
	var first := Vector2(_trace_points[0].x, _trace_points[0].z)
	var last := Vector2(_trace_points[_trace_points.size() - 1].x, _trace_points[_trace_points.size() - 1].z)
	var lo := first
	var hi := first
	for p: Vector3 in _trace_points:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	if first.distance_to(last) <= maxf(0.08, (hi - lo).length() * 0.25):
		return finish_trace()
	if hud != null:
		hud.apply_flow(flow)
		hud.set_status("Keep drawing to close the outline, or tap Done.")
	return false


## Close the traced outline, anchor the board on it and auto-fit the board.
func finish_trace() -> bool:
	if flow.step != CalibrationFlow.Step.TRACING:
		return false
	var flat := PackedVector2Array()
	for p: Vector3 in _trace_points:
		flat.append(Vector2(p.x, p.z))
	var outline: PackedVector2Array = SurfaceRegion.clean_outline(flat)
	if outline.is_empty():
		_trace_failed("That outline was too small or unclear. Draw all the way around the area.")
		return false
	var world := PackedVector3Array()
	for p: Vector2 in outline:
		world.append(Vector3(p.x, _trace_height, p.y))
	if not _place_on_outline(world):
		return false
	saved_area_world = world
	flow.has_saved_area = true
	return true


## "Use traced area": reuse this session's last outline (e.g. another game).
func use_saved_area() -> bool:
	if not is_ar() or phase == Phase.PLACED or saved_area_world.size() < 3:
		return false
	return _place_on_outline(saved_area_world)


func _trace_failed(reason: String) -> void:
	clear_trace()
	flow.trace_error = reason
	if hud != null:
		hud.apply_flow(flow)


## Anchor the board on a closed outline (XROrigin3D space, one height) and
## fit the biggest board that stays inside it.
func _place_on_outline(world: PackedVector3Array) -> bool:
	var flat := PackedVector2Array()
	var height: float = 0.0
	for p: Vector3 in world:
		flat.append(Vector2(p.x, p.z))
		height += p.y
	height /= float(world.size())
	var probe := SurfaceRegion.make(flat, SurfaceRegion.Source.TRACED)
	var c: Vector2 = probe.centroid()
	var forward := Vector3.FORWARD
	if xr_camera != null:
		var origin_xform: Transform3D = xr_origin.global_transform if xr_origin != null else Transform3D.IDENTITY
		var cam: Vector3 = origin_xform.affine_inverse() * xr_camera.global_position
		forward = Vector3(c.x - cam.x, 0.0, c.y - cam.z)
		if forward.length() < 0.01:
			forward = Vector3.FORWARD
	var pose := Transform3D(Basis.looking_at(forward.normalized(), Vector3.UP), Vector3(c.x, height, c.y))
	if not anchors.place_at_pose(pose):
		_trace_failed("AR tracking is not steady yet. Hold still a moment and trace again.")
		return false
	var to_anchor: Transform3D = anchors.pose.affine_inverse()
	var points := PackedVector2Array()
	for p: Vector3 in world:
		var a: Vector3 = to_anchor * p
		points.append(Vector2(a.x, a.z))
	var area := SurfaceRegion.make(points, SurfaceRegion.Source.TRACED)
	var fit: Dictionary = area.fit_board(board_size, BoardPlacement.MIN_SCALE)
	if fit.is_empty():
		anchors.clear()
		_trace_failed("That area is too small for this board. Trace a bigger area, or tap Cancel.")
		return false
	clear_trace()
	front_follow = false
	flow.anchor_pending = false
	placement.offset = Vector3((fit["center"] as Vector2).x, 0.0, (fit["center"] as Vector2).y)
	placement.yaw = float(fit["yaw"])
	placement.scale = float(fit["scale"])
	placement.magnify = 1.0
	_set_region(area)
	_after_placed()
	return true


## Ray from a screen point to the horizontal plane at `height` (XROrigin3D
## space); null for flat or distant rays.
func _project_to_height(screen: Vector2, height: float) -> Variant:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return null
	var origin_xform: Transform3D = xr_origin.global_transform if xr_origin != null else Transform3D.IDENTITY
	var up: Vector3 = origin_xform.basis.y.normalized()
	var origin: Vector3 = camera.project_ray_origin(screen)
	var direction: Vector3 = camera.project_ray_normal(screen)
	if absf(direction.dot(up)) < MIN_RAY_ELEVATION:
		return null
	var plane := Plane(up, origin_xform * Vector3(0.0, height, 0.0))
	var hit: Variant = plane.intersects_ray(origin, direction)
	if hit == null or origin.distance_to(hit as Vector3) > MAX_RAY_DISTANCE:
		return null
	return origin_xform.affine_inverse() * (hit as Vector3)


func _trace_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed and _trace_touch < 0:
			if trace_begin(touch.position):
				_trace_touch = touch.index
			elif not _trace_points.is_empty():
				_trace_touch = touch.index
		elif not touch.pressed and touch.index == _trace_touch:
			_trace_touch = -1
			trace_end()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == _trace_touch:
			trace_add(drag.position)
		elif _trace_touch < 0 and _trace_points.is_empty() and trace_begin(drag.position):
			_trace_touch = drag.index


func _update_trace_preview() -> void:
	if _trace_node == null:
		_trace_node = MeshInstance3D.new()
		_trace_node.name = "TraceStroke"
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = Color(1.0, 0.85, 0.3)
		_trace_node.material_override = material
		if xr_origin != null:
			xr_origin.add_child(_trace_node)
		else:
			add_child(_trace_node)
	var flat := PackedVector2Array()
	for p: Vector3 in _trace_points:
		flat.append(Vector2(p.x, p.z))
	_trace_node.mesh = SurfaceRegion.outline_mesh(flat, false, 0.01, _trace_height + 0.003)


func debug_suffix() -> String:
	var parts: PackedStringArray = []
	if region != null:
		parts.append("area %s %.2fm²" % ["traced" if region.source == SurfaceRegion.Source.TRACED else "plane", region.area()])
	if not extra_debug.is_empty():
		parts.append(extra_debug)
	return "" if parts.is_empty() else " · " + " · ".join(parts)


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
