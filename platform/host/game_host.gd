class_name GameHost
extends Node3D
## Runs one game on the AR board: builds the board scene, runs the AR
## calibration (ARSession), loads the game into board space and routes the
## player's taps and drags to it once the board is locked.
##
##   GameHost
##     WorldEnvironment, Sun
##     WorldAnchor            <- the anchor in the room (ARSession)
##       BoardPivot           <- player's offset / rotation / size
##         Game (LGGame)      <- the game, in board space
##         BoardFrame         <- footprint outline while adjusting
##     OrbitCamera            <- fallback (non-AR) camera
##     ARSession              <- AR camera, calibration HUD
##     HostHud                <- "Games" button + game status line
##
## Orientation: on load the game's manifest orientation is applied through
## the app's OrientationService ("either" by default) and "either" is
## restored on exit. On a rotation the host re-lays out its HUD, the AR HUD
## and the touch camera, recomputes the tap slop / swipe threshold for the
## new screen, tells ARCore (ARSession) and then the game
## (LGGame._on_orientation_changed). The anchor and the board never move.
##
## Swipes: while the game captures_swipes(), one-finger strokes also go
## through a SwipeDetector (screen space) to LGGame._on_swipe, and never
## orbit the touch camera.

signal game_loaded(game: LGGame)
signal exited()

## Which game to load; empty uses LookingGlass.selected_game_id.
@export var game_id: StringName = &""
## Optional catalog override (tests); defaults to the LookingGlass catalog.
var catalog: GameCatalog
## Tests inject a fake ARCore bridge (forwarded to ARSession).
var bridge_factory: Callable = Callable()
## Back-to-catalog handler; defaults to LookingGlass.return_to_launcher().
var exit_handler: Callable = Callable()

var game: LGGame
var manifest: LGGameManifest
var session: ARSession
var world_anchor: Node3D
var pivot: Node3D
## The adjust-mode outline: the game's play box (a PlayBoxOutline).
var board_frame: Node3D
## The game's play volume (board space); also on game.get_box().
var box: PlayBox
var box_outline: PlayBoxOutline
var orbit_camera: OrbitCamera
var environment: Environment
var load_error: String = ""

var _gestures: GestureTracker = GestureTracker.new()
var _swipes: SwipeDetector = SwipeDetector.new()
## The app's orientation service (the LookingGlass autoload's, or our own).
var orientation: OrientationService
## True while the screen is portrait.
var portrait: bool = false
var swipes_seen: int = 0
var _hud: CanvasLayer
var _back_button: Button
var _status_label: Label
var _dragging_board: bool = false
var _exiting: bool = false
var _tap_marker: MeshInstance3D
var _tap_marker_time: float = 0.0
## Tap diagnostics for the AR debug line: taps seen / taps on the board plane.
var taps_seen: int = 0
var taps_on_board: int = 0
var last_tap_point: Variant = null
## Last tap, for the debug line / tap probe: screen px, viewport, window,
## content scale, board hit, reprojection error, the game's description.
var last_tap_info: Dictionary = {}
## Draw the tap probe (touch dot + reprojected hit) on every tap. On while
## the AR debug line is shown.
var tap_probe_enabled: bool = false
var tap_probe: TapProbe
## Small corner toggle for the AR debug line (always reachable in game).
var debug_button: Button

const TAP_SLOP_INCHES: float = 0.35
const MAX_TAP_SLOP_PX: float = 120.0
## Hold the status line (top right) this long to toggle the debug line.
const DEBUG_LONG_PRESS_SECONDS: float = 1.5
## How fast the touch camera follows a game's focus height (1/s).
const VIEW_FOCUS_EASE: float = 4.0
var _status_press_time: float = -1.0
## Glow clipping state: the play-area version / anchor pose last applied.
var _clip_version: int = -1
var _clip_anchor: Transform3D = Transform3D()
var _status_press_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	orientation = OrientationService.of(self)
	if orientation == null:
		orientation = OrientationService.new()
		add_child(orientation)
	orientation.orientation_changed.connect(_on_orientation_changed)
	portrait = LGOrientation.is_portrait_size(get_viewport().get_visible_rect().size)
	_setup_environment()
	world_anchor = Node3D.new()
	world_anchor.name = "WorldAnchor"
	add_child(world_anchor)
	pivot = Node3D.new()
	pivot.name = "BoardPivot"
	world_anchor.add_child(pivot)
	orbit_camera = OrbitCamera.new()
	add_child(orbit_camera)
	orbit_camera.set_portrait(portrait)
	_build_hud()
	_apply_hud_layout()
	Holo.set_clip(null, PackedVector2Array())
	if not _load_game():
		_status_label.text = load_error
		orbit_camera.camera.current = true
		return
	box_outline = PlayBoxOutline.new()
	box_outline.build(box)
	box_outline.visible = false
	board_frame = box_outline
	pivot.add_child(board_frame)
	orbit_camera.frame_board(manifest.board_size, manifest.board_height)
	session = ARSession.new()
	session.name = "ARSession"
	session.bridge_factory = bridge_factory
	session.board_frame = board_frame
	session.placement_path = "user://lg_placement_%s.cfg" % manifest.id
	session.board_size = manifest.board_size
	session.board_frame_play_level = clampf(game.box_outline_while_playing(), 0.0, 1.0)
	session.box_height_changed.connect(set_box_height)
	session.board_lock_changed.connect(_on_board_lock_changed)
	add_child(session)
	session.setup(world_anchor, pivot, orbit_camera.camera, environment)
	if session.hud != null:
		session.hud.debug_toggled.connect(_on_debug_toggled)
	set_box_height(session.placement.box_height)
	_on_board_lock_changed(session.is_board_locked())
	_gestures.tap_slop_px = tap_slop_for_screen()
	_swipes.threshold_px = swipe_threshold_for_screen()
	if session.hud != null:
		session.hud.apply_layout(portrait)


func _exit_tree() -> void:
	if orientation != null and orientation.orientation_changed.is_connected(_on_orientation_changed):
		orientation.orientation_changed.disconnect(_on_orientation_changed)


func _load_game() -> bool:
	var id: StringName = game_id
	var looking_glass: Node = get_node_or_null(^"/root/LookingGlass")
	if id == &"" and looking_glass != null:
		id = looking_glass.get("selected_game_id") as StringName
	if catalog == null and looking_glass != null:
		catalog = looking_glass.get("catalog") as GameCatalog
	if catalog == null:
		catalog = GameCatalog.new()
		catalog.scan()
	manifest = catalog.get_manifest(id)
	if manifest == null:
		load_error = "Game '%s' is not in the catalog." % id
		push_warning(load_error)
		return false
	game = manifest.instantiate_game()
	if game == null:
		load_error = "Game '%s' failed to load (its entry must extend LGGame)." % id
		push_warning(load_error)
		return false
	game_id = id
	game.name = "Game"
	orientation.request(manifest.orientation)
	game.lg_set_portrait(portrait)
	box = PlayBox.from_manifest(manifest)
	game.lg_set_box(box)
	pivot.add_child(game)
	game.status_changed.connect(func(_text: String) -> void: refresh_status())
	game.playing_changed.connect(func(_playing: bool) -> void: refresh_status())
	game.exit_requested.connect(exit_game)
	game.lg_board_ready()
	refresh_status()
	game_loaded.emit(game)
	return true


func _on_board_lock_changed(locked: bool) -> void:
	if game != null:
		game.lg_set_locked(locked)
	_dragging_board = false
	_gestures.reset()
	refresh_status()


## Set the airspace height (board units; < 0 = the game's preferred height),
## clamped to the game's limits. Rebuilds the outline and tells the game.
func set_box_height(height: float) -> void:
	if box == null:
		return
	var before: float = box.height()
	box.set_height(height if height >= 0.0 else box.preferred_height)
	if box_outline != null:
		box_outline.build(box)
	if session != null:
		session.configure_box(box)
	if not is_equal_approx(before, box.height()):
		game.lg_set_box(box)


## Pickable height for taps: the game's surface, kept inside the box.
func pick_height() -> float:
	if box == null:
		return game.board_surface_height()
	return clampf(game.board_surface_height(), 0.0, box.height())


## The board-space ray under a screen point: [origin, unit direction].
static func screen_ray_in_board(camera: Camera3D, board: Node3D, screen: Vector2) -> Array[Vector3]:
	var inverse: Transform3D = board.global_transform.affine_inverse()
	var ray: Array[Vector3] = ScreenRay.ray(camera, screen)
	var origin: Vector3 = inverse * ray[0]
	var direction: Vector3 = (inverse.basis * ray[1]).normalized()
	return [origin, direction]


## The game's status line. While the AR board is being placed / adjusted the
## calibration banner does the talking, so the line is hidden (no misleading
## "Paused"); a game paused for another reason (app in background, waiting
## for the camera) says "Paused".
func refresh_status() -> void:
	if game == null or _status_label == null:
		return
	var text: String = game.get_status()
	var calibrating: bool = session != null and session.is_ar() and not session.is_board_locked()
	_status_label.visible = not calibrating
	if not game.is_playing() and not calibrating and not text.is_empty():
		text = "Paused · " + text
	_status_label.text = text


## Close the game and give the AR session back, then go to the catalog.
func exit_game() -> void:
	if _exiting:
		return
	_exiting = true
	if orientation != null:
		orientation.restore_default()
	if game != null:
		game.lg_exit()
	if session != null:
		session.shutdown()
	exited.emit()
	if exit_handler.is_valid():
		exit_handler.call()
		return
	var looking_glass: Node = get_node_or_null(^"/root/LookingGlass")
	if looking_glass != null:
		looking_glass.call("return_to_launcher")


func _notification(what: int) -> void:
	if game == null:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED:
		game.lg_set_app_paused(true)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		game.lg_set_app_paused(false)
	refresh_status()


# --- Input routing --------------------------------------------------------------

## Screen point -> board-space point (returned with y = 0) where the finger's
## ray meets the board's tap surface, the plane y = `surface_height` in board
## space (LGGame.board_surface_height(): the top of a raised board), or null.
static func screen_to_board(camera: Camera3D, board: Node3D, screen: Vector2, surface_height: float = 0.0) -> Variant:
	if camera == null or board == null:
		return null
	var up: Vector3 = board.global_transform.basis.y.normalized()
	var ground := Plane(up, board.to_global(Vector3(0.0, surface_height, 0.0)))
	var hit: Variant = ScreenRay.hit_plane(camera, screen, ground)
	if hit == null:
		return null
	var local: Vector3 = board.to_local(hit as Vector3)
	local.y = 0.0
	return local


func active_camera() -> Camera3D:
	if session != null:
		return session.active_camera()
	return orbit_camera.camera


## Tap slop in viewport pixels for this screen: about 9 mm of finger roll
## (a fingertip contact patch is ~8-10 mm; 4 mm turned real taps into
## drags). Phones have ~400+ dpi, and the viewport is scaled from 720p.
func tap_slop_for_screen() -> float:
	return tap_slop_px_for(float(DisplayServer.screen_get_dpi()), float(DisplayServer.window_get_size().y),
		get_viewport().get_visible_rect().size.y)


## Swipe threshold in viewport pixels for this screen (SwipeDetector).
func swipe_threshold_for_screen() -> float:
	return SwipeDetector.threshold_for(float(DisplayServer.screen_get_dpi()), float(DisplayServer.window_get_size().y),
		get_viewport().get_visible_rect().size.y)


static func tap_slop_px_for(dpi: float, window_height: float, view_height: float) -> float:
	if dpi <= 0.0 or window_height <= 0.0 or view_height <= 0.0:
		return GestureTracker.TAP_SLOP_PX
	var physical_px: float = dpi * TAP_SLOP_INCHES
	return clampf(physical_px * view_height / window_height, GestureTracker.TAP_SLOP_PX, MAX_TAP_SLOP_PX)


## True if a screen point is on platform UI (back button, AR buttons, the
## calibration banner), so the touch is not a board touch.
func is_over_platform_ui(screen: Vector2) -> bool:
	if _back_button != null and _back_button.visible and _back_button.get_global_rect().has_point(screen):
		return true
	if debug_button != null and debug_button.visible and debug_button.get_global_rect().has_point(screen):
		return true
	if game != null and game.is_over_game_ui(screen):
		return true
	return session != null and session.hud != null and session.hud.is_over_ui(screen)


## Board input is read in _input (before the GUI) so no full-screen Control
## can swallow phone touches; platform buttons are skipped explicitly.
func _input(event: InputEvent) -> void:
	if game == null or session == null:
		return
	if event is InputEventMouseButton and not session.is_ar():
		var button: InputEventMouseButton = event
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_camera.zoom(1.1)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_camera.zoom(1.0 / 1.1)
		return
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	_track_status_press(event)
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		if is_over_platform_ui((event as InputEventScreenTouch).position):
			return
	var gesture: Dictionary = _gestures.handle(event)
	var swipe: Dictionary = {}
	if game.captures_swipes():
		swipe = _swipes.handle(event, Time.get_ticks_usec() / 1000000.0)
	if session.captures_touch():
		return
	if not swipe.is_empty():
		route_swipe(swipe)
	if gesture.is_empty():
		return
	route_gesture(gesture)


## Send one swipe (from SwipeDetector) to the game.
func route_swipe(swipe: Dictionary) -> void:
	swipes_seen += 1
	game.lg_swipe(swipe["direction"] as Vector2i, swipe)


## Send one gesture (from GestureTracker) to the game or the camera.
func route_gesture(gesture: Dictionary) -> void:
	var camera: Camera3D = active_camera()
	match gesture.get("kind", &"") as StringName:
		&"tap":
			_dragging_board = false
			taps_seen += 1
			var ray: Array[Vector3] = screen_ray_in_board(camera, game, gesture["position"] as Vector2)
			game.lg_box_ray(ray[0], ray[1])
			var screen: Vector2 = gesture["position"] as Vector2
			var point: Variant = screen_to_board(camera, game, screen, pick_height())
			last_tap_point = point
			_record_tap(camera, screen, point)
			if point != null:
				taps_on_board += 1
				_show_tap_marker(point as Vector3)
				game.lg_tap(point as Vector3)
			_update_tap_debug()
		&"drag":
			if game.captures_drag() and game.is_playing():
				var from: Variant = screen_to_board(camera, game, gesture["from"] as Vector2, pick_height())
				var to: Variant = screen_to_board(camera, game, gesture["to"] as Vector2, pick_height())
				if from != null and to != null:
					game.lg_drag(from as Vector3, to as Vector3)
			elif not session.is_ar() and not game.captures_swipes():
				orbit_camera.orbit((gesture["to"] as Vector2) - (gesture["from"] as Vector2))
		&"pinch":
			if not session.is_ar():
				orbit_camera.zoom(float(gesture["scale"]))


func _process(delta: float) -> void:
	_update_glow_clip()
	_update_view_focus(delta)
	if _status_press_time >= 0.0:
		_status_press_time += delta
		if _status_press_time >= DEBUG_LONG_PRESS_SECONDS:
			_status_press_time = -1.0
			_gestures.reset()
			toggle_debug()
	if debug_button != null:
		debug_button.visible = session != null and session.is_ar() and session.hud != null
	if _tap_marker != null and _tap_marker.visible:
		_tap_marker_time -= delta
		var t: float = clampf(_tap_marker_time / 0.5, 0.0, 1.0)
		_tap_marker.scale = Vector3.ONE * (1.6 - 0.6 * t)
		(_tap_marker.material_override as StandardMaterial3D).albedo_color.a = t
		if _tap_marker_time <= 0.0:
			_tap_marker.visible = false


## Outside AR, ease the orbit camera's centre to the game's focus height
## (LGGame.view_focus_height(); < 0 keeps the fixed framing).
func _update_view_focus(delta: float) -> void:
	if game == null or session == null or session.is_ar():
		return
	var target: Variant = view_focus_point()
	if target == null:
		return
	orbit_camera.position = orbit_camera.position.lerp(target as Vector3, 1.0 - exp(-VIEW_FOCUS_EASE * delta))


## The orbit centre (host space) for the game's focus height, or null.
func view_focus_point() -> Variant:
	if game == null:
		return null
	var h: float = game.view_focus_height()
	if h < 0.0:
		return null
	return to_local(game.to_global(Vector3(0.0, h, 0.0)))


## Brief ring where a tap met the board plane, so players see taps land.
func _show_tap_marker(point: Vector3) -> void:
	if _tap_marker == null:
		_tap_marker = MeshInstance3D.new()
		_tap_marker.name = "TapMarker"
		var torus := TorusMesh.new()
		torus.inner_radius = 0.012
		torus.outer_radius = 0.016
		_tap_marker.mesh = torus
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
		material.no_depth_test = true
		_tap_marker.material_override = material
		game.add_sibling(_tap_marker)
	_tap_marker.position = point + Vector3(0.0, pick_height() + 0.004, 0.0)
	_tap_marker.visible = true
	_tap_marker_time = 0.5


func _record_tap(camera: Camera3D, screen: Vector2, point: Variant) -> void:
	var info: Dictionary = {
		"screen": screen,
		"viewport": get_viewport().get_visible_rect().size,
		"window": Vector2(get_window().size),
		"content_scale": get_tree().root.get_final_transform().x.x,
		"xr_ray": ScreenRay.uses_xr_projection(camera),
	}
	var reprojected: Variant = null
	if point is Vector3:
		var world: Vector3 = game.to_global((point as Vector3) + Vector3(0.0, pick_height(), 0.0))
		if not camera.is_position_behind(world):
			reprojected = camera.unproject_position(world)
			info["error_px"] = (reprojected as Vector2).distance_to(screen)
		info["hit"] = point
		info["what"] = game.describe_point(point as Vector3)
	last_tap_info = info
	if tap_probe_enabled and tap_probe != null:
		tap_probe.show_tap(screen, reprojected)


## One debug-line fragment for the last tap.
static func tap_debug_text(info: Dictionary) -> String:
	if info.is_empty():
		return ""
	var s: Vector2 = info["screen"] as Vector2
	var vp: Vector2 = info["viewport"] as Vector2
	var win: Vector2 = info["window"] as Vector2
	var text: String = "tap px %d,%d vp %dx%d win %dx%d cs %.2f %s" % [
		roundi(s.x), roundi(s.y), roundi(vp.x), roundi(vp.y), roundi(win.x), roundi(win.y),
		float(info["content_scale"]), "xr-ray" if bool(info["xr_ray"]) else "cam-ray"]
	if info.has("hit"):
		var p: Vector3 = info["hit"] as Vector3
		text += " hit %.3f,%.3f" % [p.x, p.z]
		if info.has("error_px"):
			text += " err %.1fpx" % float(info["error_px"])
		if not String(info.get("what", "")).is_empty():
			text += " " + String(info["what"])
	else:
		text += " miss"
	return text


func _update_tap_debug() -> void:
	if session == null:
		return
	session.extra_debug = "taps %d/%d · %s" % [taps_on_board, taps_seen, tap_debug_text(last_tap_info)]


func set_tap_probe(enabled: bool) -> void:
	tap_probe_enabled = enabled
	if tap_probe != null and not enabled:
		tap_probe.clear()


## Show / hide the AR debug line (and the tap probe with it).
func toggle_debug() -> void:
	if session == null or session.hud == null:
		return
	session.hud.toggle_debug()


func _on_debug_toggled(on: bool) -> void:
	set_tap_probe(on)
	session.refresh_debug()


## Keep the game's glows (Holo disc materials) inside the play area's real
## edges: re-clip when the area changes or the anchor moves (> 1 mm).
func _update_glow_clip() -> void:
	if session == null or game == null:
		return
	var anchor: Transform3D = world_anchor.global_transform
	var moved: bool = anchor.origin.distance_to(_clip_anchor.origin) > 0.001 or not anchor.basis.is_equal_approx(_clip_anchor.basis)
	if session.region_version == _clip_version and not moved:
		return
	_clip_version = session.region_version
	_clip_anchor = anchor
	Holo.set_clip(game, session.play_area_world())


## Long-press on the status line: a press inside it that stays put for
## DEBUG_LONG_PRESS_SECONDS toggles the debug line.
func _track_status_press(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed and t.index == 0 and _status_label.visible and _status_hit_rect().has_point(t.position):
			_status_press_time = 0.0
			_status_press_pos = t.position
		elif not t.pressed:
			_status_press_time = -1.0
	elif event is InputEventScreenDrag and _status_press_time >= 0.0:
		if (event as InputEventScreenDrag).position.distance_to(_status_press_pos) > _gestures.tap_slop_px:
			_status_press_time = -1.0


## The status line's touch area (at least 64 px tall, the text's width).
func _status_hit_rect() -> Rect2:
	var rect: Rect2 = _status_label.get_global_rect()
	var text_width: float = _status_label.get_theme_font("font").get_string_size(
		_status_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _status_label.get_theme_font_size("font_size")).x
	var width: float = clampf(text_width + 32.0, 120.0, rect.size.x)
	return Rect2(Vector2(rect.end.x - width, rect.position.y - 12.0), Vector2(width, maxf(rect.size.y, 40.0) + 24.0))


# --- Orientation --------------------------------------------------------------------

## The screen turned (OrientationService): re-lay out, refresh the touch
## thresholds (same inches, new pixels), tell the AR session (HUD + ARCore
## display rotation) and then the game. Nothing in the world moves.
func _on_orientation_changed(p_portrait: bool) -> void:
	portrait = p_portrait
	_apply_hud_layout()
	if orbit_camera != null:
		orbit_camera.set_portrait(portrait)
	_gestures.reset()
	_swipes.reset()
	_dragging_board = false
	_status_press_time = -1.0
	_gestures.tap_slop_px = tap_slop_for_screen()
	_swipes.threshold_px = swipe_threshold_for_screen()
	if session != null:
		session.on_orientation_changed(portrait)
	if game != null:
		game.lg_set_portrait(portrait)
	refresh_status()


## Host HUD: landscape keeps the status line top right; portrait spreads it
## across the top beside "‹ Games" (the right edge alone is too narrow).
func _apply_hud_layout() -> void:
	if _status_label == null:
		return
	if portrait:
		_status_label.anchor_left = 0.0
		_status_label.anchor_right = 1.0
		_status_label.offset_left = 180.0
		_status_label.offset_right = -24.0
	else:
		_status_label.anchor_left = 1.0
		_status_label.anchor_right = 1.0
		_status_label.offset_left = -520.0
		_status_label.offset_right = -24.0
	_status_label.offset_top = 24.0


# --- Scene ------------------------------------------------------------------------

func _setup_environment() -> void:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.05, 0.06, 0.09)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.45, 0.5, 0.55)
	environment.ambient_light_energy = 0.7
	world_env.environment = environment
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, 40.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = false
	add_child(sun)


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "HostHud"
	_hud.layer = 5
	add_child(_hud)
	_back_button = Button.new()
	_back_button.name = "BackButton"
	_back_button.text = "‹ Games"
	_back_button.focus_mode = Control.FOCUS_NONE
	_back_button.add_theme_font_size_override("font_size", 24)
	_back_button.position = Vector2(20.0, 20.0)
	_back_button.custom_minimum_size = Vector2(140.0, 64.0)
	_back_button.pressed.connect(exit_game)
	_hud.add_child(_back_button)
	_status_label = Label.new()
	_status_label.name = "GameStatus"
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_status_label.offset_left = -520.0
	_status_label.offset_right = -24.0
	_status_label.offset_top = 24.0
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 24)
	_status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_status_label.add_theme_constant_override("outline_size", 6)
	_hud.add_child(_status_label)
	debug_button = Button.new()
	debug_button.name = "DebugButton"
	debug_button.text = "dbg"
	debug_button.focus_mode = Control.FOCUS_NONE
	debug_button.add_theme_font_size_override("font_size", 16)
	debug_button.modulate = Color(1, 1, 1, 0.45)
	debug_button.position = Vector2(20.0, 96.0)
	debug_button.custom_minimum_size = Vector2(64.0, 48.0)
	debug_button.visible = false
	debug_button.pressed.connect(toggle_debug)
	_hud.add_child(debug_button)
	tap_probe = TapProbe.new()
	_hud.add_child(tap_probe)


func get_status_text() -> String:
	return _status_label.text


## Thin footprint outline (board space), shown while the AR board is adjusted.
static func make_board_frame(size: Vector2) -> Node3D:
	var root := Node3D.new()
	root.name = "BoardFrame"
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.35, 0.95, 1.0, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var bar: float = 0.006
	var sides: Array = [
		[Vector3(size.x + bar, bar, bar), Vector3(0.0, bar * 0.5, -size.y * 0.5)],
		[Vector3(size.x + bar, bar, bar), Vector3(0.0, bar * 0.5, size.y * 0.5)],
		[Vector3(bar, bar, size.y + bar), Vector3(-size.x * 0.5, bar * 0.5, 0.0)],
		[Vector3(bar, bar, size.y + bar), Vector3(size.x * 0.5, bar * 0.5, 0.0)],
	]
	for side: Array in sides:
		var mesh := BoxMesh.new()
		mesh.size = side[0] as Vector3
		mesh.material = material
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.position = side[1] as Vector3
		root.add_child(instance)
	return root
