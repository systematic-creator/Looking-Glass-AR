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
## The player picked another airspace height (board units, saved).
signal box_height_changed(height: float)

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
## A traced point may be at most this far from the outline's start (m).
const TRACE_MAX_RADIUS: float = 2.0
## ... and its ray at most this long (near-horizon touches are unreliable).
const TRACE_MAX_DISTANCE: float = 2.5
## One stroke step longer than this is a glitch (a stray touch, a jumpy
## frame) and is dropped; TRACE_JUMP_STRIKES in a row mean the finger
## really is there, so the point is then accepted.
const TRACE_MAX_JUMP: float = 0.3
const TRACE_JUMP_STRIKES: int = 3
## Points whose ray hits no surface at all are kept only this close to the
## last point that did (tracing just past an undetected edge).
const TRACE_MISS_ALLOWANCE: float = 0.15
## A new stroke this close to the end of the last one continues the
## outline; farther away it starts a fresh outline (never a joining line).
const TRACE_RESUME_RADIUS: float = 0.15
## A first touch that hits no surface may use the reticle's surface height
## if it is this close to the reticle's last hit.
const TRACE_START_REACH: float = 0.6
## Anchor corrections bigger than this (m) are eased in instead of snapped.
const ANCHOR_SMOOTH_THRESHOLD: float = 0.03
const ANCHOR_SMOOTH_TIME: float = 0.12
## Camera tracking lost this long (s) hides the board instead of letting it
## slide with the frozen camera.
const LOST_HIDE_SECONDS: float = 0.5
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
## Play-box outline under the pivot; visible while the AR board is unlocked.
var board_frame: Node3D
## Outline brightness while playing (the game's opt-in; 0 = hidden).
var board_frame_play_level: float = 0.0
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
## "Fit edges" stage: the editable outline, the grabbed handle and the last
## finger point on the surface (anchor space).
var fitter: EdgeFitter = EdgeFitter.new()
var _fit_handle: Dictionary = {}
var _fit_last: Variant = null
var _fit_source: SurfaceRegion.Source = SurfaceRegion.Source.PLANE
## Bumped whenever the play area changes (the host re-clips the glow).
var region_version: int = 0
## How close (viewport px, ~1.3 cm on a phone) a touch must be to grab a handle.
const FIT_GRAB_PX: float = 64.0
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
## Per accepted trace point: the finger's ray (XROrigin3D space) and the
## height its hit test reported (NAN = no surface hit), so the outline can be
## re-projected at the refined surface height when it is closed.
var _trace_rays: Array[Dictionary] = []
var _trace_last_supported: Vector3 = Vector3.ZERO
var _trace_jump_strikes: int = 0
var _region_refresh: float = 0.0
## Last surface height seen under the reticle (XROrigin3D space).
var _reticle_point: Vector3 = Vector3.ZERO
var _have_reticle_point: bool = false
## How the current anchor was made: "plane" (attached to a detected surface),
## "free" (a world pose), "held" (camera-relative, not anchored yet).
var anchor_kind: String = ""
## The anchor pose actually shown (eases toward anchors.pose on big jumps).
var shown_pose: Transform3D = Transform3D.IDENTITY
## Drift diagnostics (see drift_debug()).
var drift_last_mm: float = 0.0
var drift_max_mm: float = 0.0
var drift_since_lock_mm: float = 0.0
var surface_gap: float = NAN
var tracking_losses: int = 0
var board_hidden_by_loss: bool = false
var _drift_prev: Vector3 = Vector3.ZERO
var _drift_have_prev: bool = false
var _drift_window: float = 0.0
var _lock_origin: Vector3 = Vector3.ZERO
var _has_lock_origin: bool = false
var _lost_seconds: float = 0.0


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
	var saved := BoardPlacement.new()
	if saved.load_from(placement_path):
		placement.box_height = saved.box_height
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
	# The ARCore plugin's projection always uses near = 0.1 m; match it so
	# nothing that reads camera.near disagrees with the rendered frame.
	xr_camera.near = 0.1
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
	hud.airspace_changed.connect(set_box_height)
	hud.fit_done_pressed.connect(func() -> void: finish_fit())
	hud.fit_reset_pressed.connect(reset_fit)
	hud.fit_edges_pressed.connect(func() -> void: begin_fit())
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
	anchor_kind = "plane"
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
		anchor_kind = "free"
		front_follow = false
		flow.anchor_pending = false
	else:
		anchors.clear()
		anchors.pose = AnchorService.upright(pose)
		anchor_kind = "held"
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
		anchor_kind = "free"
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
	var fit: bool = region != null and region.is_valid()
	flow.placed(fit)
	if fit:
		_start_fit()
	_reset_drift()
	_has_lock_origin = false
	board_hidden_by_loss = false
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
	anchor_kind = ""
	phase = Phase.SEARCHING
	placement.locked = false
	flow.restart()
	fitter = EdgeFitter.new()
	_fit_handle = {}
	_reset_drift()
	_has_lock_origin = false
	board_hidden_by_loss = false
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
	if locked and flow.step == CalibrationFlow.Step.FITTING:
		_commit_fit()
	if locked and not placement.locked:
		rebase_anchor()
		_lock_origin = anchors.pose.origin
		_has_lock_origin = true
		drift_since_lock_mm = 0.0
	placement.locked = locked
	placement.save(placement_path)
	gestures.reset()
	flow.set_locked(locked)
	if hud != null:
		hud.apply_flow(flow)
	_sync_play()


## The player's airspace height (board units). Saved with the placement
## (in fallback only the height is written, so the AR placement is kept).
func set_box_height(height: float) -> void:
	if placement == null:
		return
	placement.box_height = height
	if is_ar():
		placement.save(placement_path)
	else:
		var saved := BoardPlacement.new()
		saved.load_from(placement_path)
		saved.box_height = height
		saved.save(placement_path)
	box_height_changed.emit(height)


## Range and value for the HUD airspace slider.
func configure_box(box: PlayBox) -> void:
	if hud != null:
		hud.configure_airspace(box.min_height, box.max_height, box.height())


func _sync_play() -> void:
	var locked: bool = is_board_locked()
	if board_frame != null:
		var adjusting: bool = is_ar() and phase == Phase.PLACED and not locked
		var playing: bool = phase == Phase.PLACED and locked and board_frame_play_level > 0.0
		board_frame.visible = adjusting or playing
		if board_frame.has_method("set_level"):
			board_frame.call("set_level", 1.0 if adjusting else board_frame_play_level)
	if _region_node != null:
		_region_node.visible = is_ar() and phase == Phase.PLACED and not locked
	if locked != _last_locked:
		_last_locked = locked
		board_lock_changed.emit(locked)


## Lock-time re-anchoring: move the anchor to the board's final spot (the
## player's drag offset baked in), so the ARCore anchor sits exactly under
## the board and small anchor rotations cannot swing it around. The board
## does not move. Keeps the old anchor if ARCore cannot make a new one.
func rebase_anchor() -> bool:
	if front_follow or not anchors.has_anchor() or placement.offset.length() < 0.01:
		return false
	var offset: Vector3 = placement.offset
	var target: Transform3D = anchors.pose * Transform3D(Basis(), offset)
	if not anchors.place_at_pose(target):
		return false
	anchor_kind = "free"
	placement.offset = Vector3.ZERO
	if region != null:
		var moved := PackedVector2Array()
		for p: Vector2 in region.polygon:
			moved.append(p - Vector2(offset.x, offset.z))
		_set_region(SurfaceRegion.make(moved, region.source))
	_apply_transforms()
	return true


## Put the world anchor at `anchor_pose` (XROrigin3D space, made upright).
func apply_anchor_pose(anchor_pose: Transform3D) -> void:
	if world_anchor == null:
		return
	var origin_xform: Transform3D = xr_origin.global_transform if xr_origin != null else Transform3D.IDENTITY
	world_anchor.global_transform = origin_xform * AnchorService.upright(anchor_pose)


## Re-apply the anchor pose and the placement to the scene. With `delta`
## (per-frame polling), large anchor corrections are eased in; otherwise the
## shown pose snaps to the anchor.
func _apply_transforms(delta: float = -1.0) -> void:
	if delta < 0.0:
		shown_pose = anchors.pose
	else:
		shown_pose = ease_pose(shown_pose, anchors.pose, delta)
	apply_anchor_pose(shown_pose)
	if pivot != null:
		pivot.transform = placement.pivot_transform()


## Follow an anchor correction: small ones (ARCore refining) snap, big
## ones (tracking regained after a loss) ease in over ~ANCHOR_SMOOTH_TIME.
static func ease_pose(shown: Transform3D, target: Transform3D, delta: float) -> Transform3D:
	var jump: float = shown.origin.distance_to(target.origin)
	var turn: float = absf(shown.basis.get_rotation_quaternion().angle_to(target.basis.get_rotation_quaternion()))
	if jump <= ANCHOR_SMOOTH_THRESHOLD and turn <= deg_to_rad(3.0):
		return target
	var k: float = 1.0 - exp(-maxf(delta, 0.0) / ANCHOR_SMOOTH_TIME)
	var q: Quaternion = shown.basis.get_rotation_quaternion().slerp(target.basis.get_rotation_quaternion(), k)
	return Transform3D(Basis(q), shown.origin.lerp(target.origin, k))


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
		_apply_transforms(delta)
	_track_drift(delta)
	_update_tracking_loss(delta)
	if refresh:
		surface_gap = measure_surface_gap()
	if flow.step == CalibrationFlow.Step.FITTING and hud != null:
		hud.fit_handles.set_handles(fit_handle_screens(), _active_handle_slot())
	if region != null and region.source == SurfaceRegion.Source.PLANE and not placement.locked and flow.step != CalibrationFlow.Step.FITTING:
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
	var pose: Variant = hit_pose(hit)
	var found: bool = pose != null
	reticle.visible = found
	if found:
		var origin_xform: Transform3D = xr_origin.global_transform
		reticle.global_transform = origin_xform * AnchorService.upright(pose as Transform3D)
		_reticle_point = (pose as Transform3D).origin
		_have_reticle_point = true
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
	# Yellow feature dots look like traced points; hide them while tracing.
	_overlay_points.visible = flow.step != CalibrationFlow.Step.TRACING
	var points: PackedVector3Array = bridge.point_cloud(MAX_OVERLAY_POINTS) if _overlay_points.visible else PackedVector3Array()
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
	if flow.step == CalibrationFlow.Step.FITTING:
		_fit_input(event, gesture)
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
	var ray: Array[Vector3] = ScreenRay.ray(camera, screen)
	var origin: Vector3 = ray[0]
	var direction: Vector3 = ray[1]
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


# --- Fit edges -------------------------------------------------------------------

## "Fit edges" again from Adjust. False if there is no play area.
func begin_fit() -> bool:
	if not is_ar() or phase != Phase.PLACED or placement.locked or region == null or not region.is_valid():
		return false
	if not flow.begin_fit():
		return false
	_start_fit()
	if hud != null:
		hud.apply_flow(flow)
	return true


func _start_fit() -> void:
	_fit_source = region.source
	fitter.begin(region.polygon)
	_fit_handle = {}
	_set_region(SurfaceRegion.make(fitter.polygon, _fit_source))


## Commit the fitted outline and go on to Adjust.
func finish_fit() -> bool:
	if flow.step != CalibrationFlow.Step.FITTING:
		return false
	_commit_fit()
	flow.finish_fit()
	if hud != null:
		hud.apply_flow(flow)
	_sync_play()
	return true


## Back to the outline the stage started with.
func reset_fit() -> void:
	if flow.step != CalibrationFlow.Step.FITTING:
		return
	fitter.reset()
	_set_region(SurfaceRegion.make(fitter.polygon, _fit_source))
	_constrain_board()


## The fitted outline becomes the play area (it clamps the board and clips
## the glow), and the session's reusable area.
func _commit_fit() -> void:
	if not fitter.is_active():
		return
	_set_region(SurfaceRegion.make(fitter.polygon, SurfaceRegion.Source.FITTED))
	var world := PackedVector3Array()
	for p: Vector2 in fitter.polygon:
		world.append(AnchorService.upright(anchors.pose) * Vector3(p.x, 0.0, p.y))
	saved_area_world = world
	flow.has_saved_area = true
	_fit_handle = {}
	_constrain_board()


## Keep the board inside the (new) play area: slide it in, or fit a smaller
## board if it no longer fits.
func _constrain_board() -> void:
	if region == null or not region.is_valid():
		return
	var half: Vector2 = board_size * 0.5 * placement.scale
	var center: Variant = region.clamp_center(Vector2(placement.offset.x, placement.offset.z), half, placement.yaw)
	if center == null:
		var fit: Dictionary = region.fit_board(board_size, BoardPlacement.MIN_SCALE, placement.scale)
		if fit.is_empty():
			return
		center = fit["center"]
		placement.yaw = float(fit["yaw"])
		placement.scale = float(fit["scale"])
	placement.offset = Vector3((center as Vector2).x, 0.0, (center as Vector2).y)
	_apply_transforms()
	placement.save(placement_path)


## Screen positions of every handle (skips ones behind the camera):
## [{"kind", "index", "screen", "along"}].
func fit_handle_screens() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if xr_camera == null or world_anchor == null or not fitter.is_active():
		return out
	for h: Dictionary in fitter.handles():
		var p: Vector2 = h["point"] as Vector2
		var world: Vector3 = world_anchor.to_global(Vector3(p.x, 0.0, p.y))
		if xr_camera.is_position_behind(world):
			continue
		var along := Vector2.RIGHT
		if int(h["kind"]) == EdgeFitter.Handle.EDGE:
			var i: int = int(h["index"])
			var a: Vector2 = fitter.polygon[i]
			var b: Vector2 = fitter.polygon[(i + 1) % fitter.polygon.size()]
			var wa: Vector3 = world_anchor.to_global(Vector3(a.x, 0.0, a.y))
			var wb: Vector3 = world_anchor.to_global(Vector3(b.x, 0.0, b.y))
			if not xr_camera.is_position_behind(wa) and not xr_camera.is_position_behind(wb):
				along = xr_camera.unproject_position(wb) - xr_camera.unproject_position(wa)
		out.append({"kind": h["kind"], "index": h["index"], "screen": xr_camera.unproject_position(world), "along": along})
	return out


## The handle a touch at `screen` grabs (corners win ties), or {}.
func pick_fit_handle(screen: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = FIT_GRAB_PX
	for h: Dictionary in fit_handle_screens():
		var d: float = (h["screen"] as Vector2).distance_to(screen)
		if int(h["kind"]) == EdgeFitter.Handle.EDGE:
			d += 12.0
		if d <= best_d:
			best_d = d
			best = h
	return best


func _active_handle_slot() -> int:
	if _fit_handle.is_empty():
		return -1
	var list: Array[Dictionary] = fit_handle_screens()
	for i: int in list.size():
		if int(list[i]["kind"]) == int(_fit_handle["kind"]) and int(list[i]["index"]) == int(_fit_handle["index"]):
			return i
	return -1


## Fit-edges touches: press on a handle grabs it, one-finger drags move it
## by the finger's motion on the surface (relative, so the finger never has
## to cover the edge it is lining up), release lets go.
func _fit_input(event: InputEvent, gesture: Dictionary) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed and gestures.touch_count() == 1:
			_fit_handle = pick_fit_handle(touch.position)
			_fit_last = _anchor_point(touch.position) if not _fit_handle.is_empty() else null
		elif not touch.pressed and gestures.touch_count() == 0:
			if not _fit_handle.is_empty():
				_constrain_board()
			_fit_handle = {}
			_fit_last = null
		return
	if gesture.get("kind", &"") != &"drag" or _fit_handle.is_empty():
		return
	var at: Variant = _anchor_point(gesture["to"] as Vector2)
	if at == null:
		return
	if _fit_last != null:
		var d: Vector3 = (at as Vector3) - (_fit_last as Vector3)
		if fitter.move_handle(int(_fit_handle["kind"]) as EdgeFitter.Handle, int(_fit_handle["index"]), Vector2(d.x, d.z)):
			_set_region(SurfaceRegion.make(fitter.polygon, _fit_source))
	_fit_last = at


## The play area's outline in world x/z (empty if none), for glow clipping.
func play_area_world() -> PackedVector2Array:
	var out := PackedVector2Array()
	if region == null or not region.is_valid() or world_anchor == null or not is_ar():
		return out
	for p: Vector2 in region.polygon:
		var w: Vector3 = world_anchor.to_global(Vector3(p.x, 0.0, p.y))
		out.append(Vector2(w.x, w.z))
	return out


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
	region_version += 1
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
	material.albedo_color = Color(0.35, 0.95, 1.0, 0.6)
	if region.source == SurfaceRegion.Source.TRACED or region.source == SurfaceRegion.Source.FITTED:
		material.albedo_color = Color(1.0, 0.85, 0.3, 0.95)
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
	_trace_rays.clear()
	_trace_touch = -1
	_trace_jump_strikes = 0
	flow.trace_points = 0
	if _trace_node != null:
		_trace_node.queue_free()
		_trace_node = null
	if hud != null:
		hud.apply_flow(flow)


func trace_point_count() -> int:
	return _trace_points.size()


## Begin (or continue) the outline at a screen point. The first point must
## land on a detected surface (or, if ARCore has no plane there yet, near the
## surface under the reticle); it fixes the traced height. A new stroke near
## the end of the last one continues it; far away it starts a new outline,
## so two strokes are never joined by a straight line across the screen.
func trace_begin(screen: Vector2) -> bool:
	if flow.step != CalibrationFlow.Step.TRACING:
		return false
	if not _trace_points.is_empty():
		var p: Variant = _project_to_height(screen, _trace_height, TRACE_MAX_DISTANCE)
		var last: Vector3 = _trace_points[_trace_points.size() - 1]
		if p != null and _flat_distance(p as Vector3, last) <= TRACE_RESUME_RADIUS:
			_trace_jump_strikes = 0
			return trace_add(screen)
		clear_trace()
	var pose: Variant = hit_pose(hit_at(screen))
	if pose != null:
		_trace_height = (pose as Transform3D).origin.y
	elif _have_reticle_point:
		var guess: Variant = _project_to_height(screen, _reticle_point.y, TRACE_MAX_DISTANCE)
		if guess == null or _flat_distance(guess as Vector3, _reticle_point) > TRACE_START_REACH:
			return _trace_start_failed()
		_trace_height = _reticle_point.y
	else:
		return _trace_start_failed()
	flow.trace_error = ""
	_trace_jump_strikes = 0
	var first: Variant = _project_to_height(screen, _trace_height, TRACE_MAX_DISTANCE)
	if first == null:
		return _trace_start_failed()
	_trace_last_supported = first as Vector3
	return trace_add(screen)


func _trace_start_failed() -> bool:
	flow.trace_error = "Start your outline on the surface (where the teal area is)."
	if hud != null:
		hud.apply_flow(flow)
	return false


## Add a stroke point: the finger's ray meets the traced surface's own height
## (an infinite plane), so tracing just past a real edge never drops to the
## floor. Rejected: points over a clearly higher surface (an object on the
## area), rays that are too flat / long, single glitchy jumps, and points
## whose ray misses every surface far from the last supported point.
func trace_add(screen: Vector2) -> bool:
	var ray: Variant = _origin_ray(screen)
	if ray == null:
		return false
	var point: Variant = _project_to_height(screen, _trace_height, TRACE_MAX_DISTANCE)
	if point == null:
		return false
	var p: Vector3 = point as Vector3
	var pose: Variant = hit_pose(hit_at(screen))
	var hit_height: float = NAN
	if pose != null:
		hit_height = (pose as Transform3D).origin.y
		if hit_height - _trace_height > TRACE_HEIGHT_TOLERANCE:
			return false
	if not _trace_points.is_empty():
		if _flat_distance(p, _trace_points[0]) > TRACE_MAX_RADIUS:
			return false
		var last: Vector3 = _trace_points[_trace_points.size() - 1]
		var step: float = _flat_distance(p, last)
		if step < TRACE_MIN_SPACING:
			return false
		if step > TRACE_MAX_JUMP:
			_trace_jump_strikes += 1
			if _trace_jump_strikes < TRACE_JUMP_STRIKES:
				return false
		if is_nan(hit_height) and _flat_distance(p, _trace_last_supported) > TRACE_MISS_ALLOWANCE:
			return false
	_trace_jump_strikes = 0
	if not is_nan(hit_height):
		_trace_last_supported = p
	_trace_points.append(p)
	_trace_rays.append({"origin": (ray as Array)[0], "dir": (ray as Array)[1], "hit": hit_height})
	flow.trace_points = _trace_points.size()
	_update_trace_preview()
	return true


## The traced surface's height, refined from every stroke point that hit it:
## the median of hit heights within TRACE_HEIGHT_TOLERANCE of the start.
func refined_trace_height() -> float:
	var heights: Array[float] = []
	for ray: Dictionary in _trace_rays:
		var h: float = float(ray["hit"])
		if not is_nan(h) and absf(h - _trace_height) <= TRACE_HEIGHT_TOLERANCE:
			heights.append(h)
	if heights.is_empty():
		return _trace_height
	heights.sort()
	@warning_ignore("integer_division")
	return heights[heights.size() / 2]


## Stroke points re-projected onto `height` along their original rays.
func _trace_points_at(height: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i: int in _trace_rays.size():
		var ray: Dictionary = _trace_rays[i]
		var hit: Variant = Plane(Vector3.UP, height).intersects_ray(ray["origin"] as Vector3, ray["dir"] as Vector3)
		out.append(hit as Vector3 if hit != null else Vector3(_trace_points[i].x, height, _trace_points[i].z))
	return out


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


## A hit's pose, or null if the hit failed or carries no usable pose (never
## a default / zero pose).
static func hit_pose(hit: Dictionary) -> Variant:
	if not bool(hit.get("hit", false)):
		return null
	var pose: Variant = hit.get("pose", null)
	if not (pose is Transform3D):
		return null
	var origin: Vector3 = (pose as Transform3D).origin
	if not origin.is_finite():
		return null
	return pose


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
	var height: float = refined_trace_height()
	var flat := PackedVector2Array()
	for p: Vector3 in _trace_points_at(height):
		flat.append(Vector2(p.x, p.z))
	var outline: PackedVector2Array = SurfaceRegion.clean_outline(flat)
	if outline.is_empty():
		_trace_failed("That outline was too small or unclear. Draw all the way around the area.")
		return false
	var world := PackedVector3Array()
	for p: Vector2 in outline:
		world.append(Vector3(p.x, height, p.y))
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
	if _anchor_on_surface_at(pose.origin):
		anchor_kind = "plane"
	elif anchors.place_at_pose(pose):
		anchor_kind = "free"
	else:
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


## Anchor on the detected surface under `origin_point` (XROrigin3D space)
## if one is right there (same height, a few cm), so ARCore keeps the anchor
## glued to that surface as it refines it. False if none is.
func _anchor_on_surface_at(origin_point: Vector3) -> bool:
	if xr_camera == null:
		return false
	var origin_xform: Transform3D = xr_origin.global_transform if xr_origin != null else Transform3D.IDENTITY
	var world: Vector3 = origin_xform * origin_point
	if xr_camera.is_position_behind(world):
		return false
	var screen: Vector2 = xr_camera.unproject_position(world)
	var size: Vector2 = get_viewport().get_visible_rect().size
	if not Rect2(Vector2.ZERO, size).has_point(screen):
		return false
	var pose: Variant = hit_pose(hit_at(screen))
	if pose == null:
		return false
	var at: Vector3 = (pose as Transform3D).origin
	if absf(at.y - origin_point.y) > PLANE_HEIGHT_TOLERANCE or _flat_distance(at, origin_point) > 0.05:
		return false
	return anchors.place_at_screen(Vector2(screen.x / maxf(1.0, size.x), screen.y / maxf(1.0, size.y)))


## The finger's ray in XROrigin3D space: [origin, direction], or null.
func _origin_ray(screen: Vector2) -> Variant:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return null
	var to_origin: Transform3D = (xr_origin.global_transform if xr_origin != null else Transform3D.IDENTITY).affine_inverse()
	var ray: Array[Vector3] = ScreenRay.ray(camera, screen)
	var origin: Vector3 = ray[0]
	var direction: Vector3 = ray[1]
	return [to_origin * origin, (to_origin.basis * direction).normalized()]


## Ray from a screen point to the horizontal plane at `height` (XROrigin3D
## space); null for flat or distant rays.
func _project_to_height(screen: Vector2, height: float, max_distance: float = MAX_RAY_DISTANCE) -> Variant:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return null
	var origin_xform: Transform3D = xr_origin.global_transform if xr_origin != null else Transform3D.IDENTITY
	var up: Vector3 = origin_xform.basis.y.normalized()
	var ray: Array[Vector3] = ScreenRay.ray(camera, screen)
	var origin: Vector3 = ray[0]
	var direction: Vector3 = ray[1]
	if absf(direction.dot(up)) < MIN_RAY_ELEVATION:
		return null
	var plane := Plane(up, origin_xform * Vector3(0.0, height, 0.0))
	var hit: Variant = plane.intersects_ray(origin, direction)
	if hit == null or origin.distance_to(hit as Vector3) > max_distance:
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
			if not touch.canceled:
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
	_trace_node.mesh = SurfaceRegion.outline_mesh(flat, false, 0.012, _trace_height + 0.003)


## Update the debug line on the next frame (e.g. right after it is shown).
func refresh_debug() -> void:
	_diag_elapsed = DIAG_INTERVAL


func debug_suffix() -> String:
	var parts: PackedStringArray = []
	var drift: String = drift_debug()
	if not drift.is_empty():
		parts.append(drift)
	if region != null:
		var names: Dictionary = {SurfaceRegion.Source.TRACED: "traced", SurfaceRegion.Source.FITTED: "fitted"}
		parts.append("area %s %.2fm²" % [names.get(region.source, "plane"), region.area()])
	if not extra_debug.is_empty():
		parts.append(extra_debug)
	return "" if parts.is_empty() else " · " + " · ".join(parts)


# --- Drift diagnostics / tracking loss --------------------------------------------

func _reset_drift() -> void:
	drift_last_mm = 0.0
	drift_max_mm = 0.0
	drift_since_lock_mm = 0.0
	_drift_have_prev = false
	_drift_window = 0.0
	_lost_seconds = 0.0


## Per frame: how far the anchor pose moved since the last frame, the most
## in the last 3 s, and since Lock (all in mm, world space).
func _track_drift(delta: float) -> void:
	var at: Vector3 = anchors.pose.origin
	if _drift_have_prev:
		drift_last_mm = at.distance_to(_drift_prev) * 1000.0
		_drift_window += delta
		if _drift_window > 3.0:
			_drift_window = 0.0
			drift_max_mm = 0.0
		drift_max_mm = maxf(drift_max_mm, drift_last_mm)
	_drift_prev = at
	_drift_have_prev = true
	if _has_lock_origin:
		drift_since_lock_mm = at.distance_to(_lock_origin) * 1000.0


## Camera tracking lost: ARCore freezes the camera pose, so a visible board
## would stick to the screen and slide over the real table. Hide it after
## LOST_HIDE_SECONDS and say why; show it again when tracking is back.
func _update_tracking_loss(delta: float) -> void:
	var state: int = int(tracking_info.get("camera_state", 0))
	if state != CalibrationFlow.CAMERA_TRACKING:
		_lost_seconds += delta
		if _lost_seconds >= LOST_HIDE_SECONDS and not board_hidden_by_loss:
			board_hidden_by_loss = true
			tracking_losses += 1
			world_anchor.visible = false
			if hud != null:
				hud.set_status("Tracking lost. Point the phone back at the board and hold still.")
	else:
		_lost_seconds = 0.0
		if board_hidden_by_loss:
			board_hidden_by_loss = false
			world_anchor.visible = true
			if hud != null:
				hud.apply_flow(flow)


## Board height minus the height of the detected surface under the board's
## centre (m), NAN if no surface is under it. Near 0 means the board sits on
## the real surface; a few cm means it floats above / sinks below it (which
## looks like "drifting" as the camera moves).
func measure_surface_gap() -> float:
	if bridge == null or pivot == null or not pivot.is_inside_tree():
		return NAN
	var origin_xform: Transform3D = xr_origin.global_transform if xr_origin != null else Transform3D.IDENTITY
	var board: Vector3 = origin_xform.affine_inverse() * pivot.global_position
	var best: float = NAN
	for entry: Variant in bridge.horizontal_planes():
		var plane: Dictionary = entry as Dictionary
		var pose: Transform3D = plane.get("pose", Transform3D.IDENTITY) as Transform3D
		var polygon: PackedVector2Array = plane.get("polygon", PackedVector2Array()) as PackedVector2Array
		if polygon.size() < 3:
			continue
		var local: Vector3 = pose.affine_inverse() * board
		if not Geometry2D.is_point_in_polygon(Vector2(local.x, local.z), polygon):
			continue
		var gap: float = board.y - pose.origin.y
		if is_nan(best) or absf(gap) < absf(best):
			best = gap
	return best


## "anc T plane · d 0.2/3.1mm · lock 4mm · board 0.12,0.12,-0.70 · surf +0.3cm"
## anchor tracking (T tracking, P paused, S stopped) and kind, anchor motion
## this frame / max in 3 s, anchor motion since Lock, board centre (world m),
## board height over the detected surface under it.
func drift_debug() -> String:
	if not is_ar() or phase != Phase.PLACED or pivot == null or not pivot.is_inside_tree():
		return ""
	var state: String = "?"
	match anchors.tracking:
		AnchorBackend.Tracking.TRACKING: state = "T"
		AnchorBackend.Tracking.PAUSED: state = "P"
		AnchorBackend.Tracking.STOPPED: state = "S"
	var board: Vector3 = pivot.global_position
	var parts: PackedStringArray = [
		"anc %s %s" % [state, anchor_kind],
		"d %.1f/%.1fmm" % [drift_last_mm, drift_max_mm],
	]
	if _has_lock_origin:
		parts.append("lock %.0fmm" % drift_since_lock_mm)
	parts.append("board %.2f,%.2f,%.2f" % [board.x, board.y, board.z])
	parts.append("surf %s" % ("none" if is_nan(surface_gap) else "%+.1fcm" % (surface_gap * 100.0)))
	if tracking_losses > 0:
		parts.append("lost %d" % tracking_losses)
	return " ".join(parts)


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
