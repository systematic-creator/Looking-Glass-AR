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
var board_frame: Node3D
var orbit_camera: OrbitCamera
var environment: Environment
var load_error: String = ""

var _gestures: GestureTracker = GestureTracker.new()
var _hud: CanvasLayer
var _back_button: Button
var _status_label: Label
var _dragging_board: bool = false
var _exiting: bool = false


func _ready() -> void:
	_setup_environment()
	world_anchor = Node3D.new()
	world_anchor.name = "WorldAnchor"
	add_child(world_anchor)
	pivot = Node3D.new()
	pivot.name = "BoardPivot"
	world_anchor.add_child(pivot)
	orbit_camera = OrbitCamera.new()
	add_child(orbit_camera)
	_build_hud()
	if not _load_game():
		_status_label.text = load_error
		orbit_camera.camera.current = true
		return
	board_frame = make_board_frame(manifest.board_size)
	board_frame.visible = false
	pivot.add_child(board_frame)
	orbit_camera.frame_board(manifest.board_size, manifest.board_height)
	session = ARSession.new()
	session.name = "ARSession"
	session.bridge_factory = bridge_factory
	session.board_frame = board_frame
	session.placement_path = "user://lg_placement_%s.cfg" % manifest.id
	session.board_lock_changed.connect(_on_board_lock_changed)
	add_child(session)
	session.setup(world_anchor, pivot, orbit_camera.camera, environment)
	_on_board_lock_changed(session.is_board_locked())


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
	pivot.add_child(game)
	game.status_changed.connect(func(text: String) -> void: _status_label.text = text)
	game.exit_requested.connect(exit_game)
	game.lg_board_ready()
	_status_label.text = game.get_status()
	game_loaded.emit(game)
	return true


func _on_board_lock_changed(locked: bool) -> void:
	if game != null:
		game.lg_set_locked(locked)
	_dragging_board = false
	_gestures.reset()


## Close the game and give the AR session back, then go to the catalog.
func exit_game() -> void:
	if _exiting:
		return
	_exiting = true
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


# --- Input routing --------------------------------------------------------------

## Screen point -> board-space point on the board plane (y = 0), or null.
static func screen_to_board(camera: Camera3D, board: Node3D, screen: Vector2) -> Variant:
	if camera == null or board == null:
		return null
	var up: Vector3 = board.global_transform.basis.y.normalized()
	var ground := Plane(up, board.global_position)
	var hit: Variant = ground.intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if hit == null:
		return null
	var local: Vector3 = board.to_local(hit as Vector3)
	local.y = 0.0
	return local


func active_camera() -> Camera3D:
	if session != null:
		return session.active_camera()
	return orbit_camera.camera


func _unhandled_input(event: InputEvent) -> void:
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
	var gesture: Dictionary = _gestures.handle(event)
	if session.captures_touch() or gesture.is_empty():
		return
	route_gesture(gesture)


## Send one gesture (from GestureTracker) to the game or the camera.
func route_gesture(gesture: Dictionary) -> void:
	var camera: Camera3D = active_camera()
	match gesture.get("kind", &"") as StringName:
		&"tap":
			_dragging_board = false
			var point: Variant = screen_to_board(camera, game, gesture["position"] as Vector2)
			if point != null:
				game.lg_tap(point as Vector3)
		&"drag":
			if game.captures_drag() and game.is_playing():
				var from: Variant = screen_to_board(camera, game, gesture["from"] as Vector2)
				var to: Variant = screen_to_board(camera, game, gesture["to"] as Vector2)
				if from != null and to != null:
					game.lg_drag(from as Vector3, to as Vector3)
			elif not session.is_ar():
				orbit_camera.orbit((gesture["to"] as Vector2) - (gesture["from"] as Vector2))
		&"pinch":
			if not session.is_ar():
				orbit_camera.zoom(float(gesture["scale"]))


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
