extends "res://tests/surface_tests.gd"
## Phone touch path end to end (lg-test-17890b7 field report: taps "doing
## nothing" or landing at random spots). Reproduces the Android setup:
##   - an ARCore-style projection from the XR interface (near 0.1 m, off-
##     centre principal point, 16:9 camera-texture display),
##   - a 2340x1080 window (19.5:9 Samsung) with the 1280x720 canvas_items /
##     expand stretch: viewport 1560x720, content scale 1.5,
##   - touches injected as window pixels through Input.parse_input_event,
## then checks every tic-tac-toe cell is hit from several phone poses.
## Also: tap slop, the tap probe and in-game debug access.
## Run: godot --headless --path . res://tests/touch_tests.tscn

const PHONE_WINDOW := Vector2i(2340, 1080)
var xr: FakeXRInterface
var _saved_window: Vector2i


func run_tests() -> void:
	ARSession.clear_saved_area()
	_saved_window = get_tree().root.size
	get_tree().root.size = PHONE_WINDOW
	await frames(2)
	xr = FakeXRInterface.new()
	xr.projection = FakeXRInterface.arcore_projection(Vector2(1920, 1080), 1460.0, Vector2(972.0, 531.0))
	xr.install()
	await _test_ray_maths()
	await _test_cells_through_the_phone_path()
	_test_tap_slop()
	await _test_debug_access_and_probe()
	xr.uninstall()
	get_tree().root.size = _saved_window
	await frames(1)
	ARSession.clear_saved_area()


func _window_pos(viewport_pos: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * viewport_pos


func _phone_tap(viewport_pos: Vector2) -> void:
	var at: Vector2 = _window_pos(viewport_pos)
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.position = at
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = at
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()


## Screen points spread over the whole view, incl. near the edges.
func _grid(size: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for fx: float in [0.05, 0.3, 0.5, 0.7, 0.95]:
		for fy: float in [0.08, 0.5, 0.92]:
			out.append(Vector2(fx * size.x, fy * size.y))
	return out


func _test_ray_maths() -> void:
	var origin := XROrigin3D.new()
	add_child(origin)
	var camera := XRCamera3D.new()
	origin.add_child(camera)
	camera.transform = Transform3D(Basis.looking_at(Vector3(0.2, -0.5, -1.0)), Vector3(0.1, 0.5, 0.3))
	await frames(1)
	var size: Vector2 = get_viewport().get_visible_rect().size
	check("phone: the viewport is 1560x720 at content scale 1.5 (19.5:9 window)", (
		size.is_equal_approx(Vector2(1560, 720)) and is_equal_approx(get_tree().root.get_final_transform().x.x, 1.5)
	))
	var targets: Array[Vector3] = []
	for s: Vector2 in _grid(size):
		targets.append(camera.global_position + ScreenRay.ray(camera, s)[1] * 0.7)
	var worst_godot_old: float = 0.0
	var worst_godot_near: float = 0.0
	var worst_ours: float = 0.0
	var worst_reproject: float = 0.0
	for target: Vector3 in targets:
		var screen: Vector2 = camera.unproject_position(target)
		var want: Vector3 = (target - camera.global_position).normalized()
		camera.near = 0.01
		worst_godot_old = maxf(worst_godot_old, rad_to_deg(camera.project_ray_normal(screen).angle_to(want)))
		camera.near = 0.1
		worst_godot_near = maxf(worst_godot_near, rad_to_deg(camera.project_ray_normal(screen).angle_to(want)))
		var ours: Array[Vector3] = ScreenRay.ray(camera, screen)
		worst_ours = maxf(worst_ours, rad_to_deg(ours[1].angle_to(want)))
		worst_reproject = maxf(worst_reproject, camera.unproject_position(ours[0] + ours[1] * 0.5).distance_to(screen))
	print("ray error (deg): Godot XRCamera3D near 0.01 = %.2f, near 0.1 = %.3f, ScreenRay = %.5f; reprojection %.4f px" % [
		worst_godot_old, worst_godot_near, worst_ours, worst_reproject])
	check("repro: Godot's XRCamera3D ray with the old near 0.01 is off by > 20 degrees", worst_godot_old > 20.0)
	check("repro: even with near 0.1 it ignores ARCore's off-centre principal point (> 0.2 degrees)", worst_godot_near > 0.2)
	check("fix: ScreenRay is the exact inverse of the rendered projection (< 0.01 degrees)", worst_ours < 0.01)
	check("fix: a ScreenRay point projects back onto the touch (< 0.05 px)", worst_reproject < 0.05)
	origin.queue_free()
	await frames(1)


func _test_cells_through_the_phone_path() -> void:
	var host: GameHost = await _ar_host(&"tic_tac_toe")
	var ar: ARSession = host.session
	check("phone: the AR camera near matches the ARCore projection (0.1 m)", is_equal_approx(ar.xr_camera.near, 0.1))
	check("phone: Place here works through the XR projection", ar.place_at_reticle())
	ar.set_locked(true)
	await frames(1)
	var game: TicTacToeGame = host.game as TicTacToeGame
	var centre: Vector3 = game.global_position
	var poses: Array = [
		["above", centre + Vector3(0.0, 0.45, 0.3), centre],
		["low angle", centre + Vector3(0.0, 0.2, 0.45), centre],
		["off to the side", centre + Vector3(-0.35, 0.3, 0.3), centre + Vector3(0.08, 0.0, -0.05)],
		["board at the screen edge", centre + Vector3(0.25, 0.35, 0.35), centre + Vector3(0.3, 0.0, -0.1)],
	]
	for pose: Array in poses:
		_look(pose[1] as Vector3, pose[2] as Vector3)
		await frames(1)
		var hits: int = 0
		var old_hits: int = 0
		var worst_err: float = 0.0
		for index: int in 9:
			var world: Vector3 = game.to_global(TicTacToeGame.cell_top(index))
			var screen: Vector2 = ar.xr_camera.unproject_position(world)
			_phone_tap(screen)
			await frames(1)
			var info: Dictionary = host.last_tap_info
			if String(info.get("what", "")) == "cell %d" % index:
				hits += 1
			worst_err = maxf(worst_err, float(info.get("error_px", 999.0)))
			# What the pre-fix code (Godot's XR ray, camera near 0.01) would have hit.
			ar.xr_camera.near = 0.01
			var old: Variant = Plane(Vector3.UP, game.to_global(Vector3(0, TicTacToeGame.SLAB_TOP, 0))).intersects_ray(
				ar.xr_camera.project_ray_origin(screen), ar.xr_camera.project_ray_normal(screen))
			ar.xr_camera.near = 0.1
			if old != null and TicTacToeGame.cell_at(game.to_local(old as Vector3)) == index:
				old_hits += 1
		print("%s: %d/9 cells hit (pre-fix ray: %d/9), worst reprojection %.2f px" % [pose[0], hits, old_hits, worst_err])
		check("phone %s: every cell tap lands on that cell" % pose[0], hits == 9)
		check("phone %s: the hit projects back under the finger (< 1 px)" % pose[0], worst_err < 1.0)
		check("repro %s: the pre-fix ray misses cells" % pose[0], old_hits < 9)
	await free_host(host)


func _test_tap_slop() -> void:
	# 420 dpi phone, 1080 px tall window, 720 px viewport.
	var slop: float = GameHost.tap_slop_px_for(420.0, 1080.0, 720.0)
	var mm: float = slop * 1080.0 / 720.0 / 420.0 * 25.4
	check("slop: about 9 mm of finger roll still counts as a tap", mm > 8.0 and mm < 10.0)
	check("slop: capped for huge dpi, never below the default", (
		GameHost.tap_slop_px_for(2000.0, 1080.0, 720.0) <= GameHost.MAX_TAP_SLOP_PX
		and GameHost.tap_slop_px_for(0.0, 0.0, 0.0) == GestureTracker.TAP_SLOP_PX
	))


func _test_debug_access_and_probe() -> void:
	var host: GameHost = await _ar_host(&"tic_tac_toe")
	var ar: ARSession = host.session
	ar.place_at_reticle()
	ar.set_locked(true)
	await frames(2)
	var game: TicTacToeGame = host.game as TicTacToeGame
	check("debug: while locked the step panel is gone, the dbg button is there", (
		not ar.hud._banner.visible and host.debug_button.visible and not ar.hud.debug_requested
	))
	var button_centre: Vector2 = host.debug_button.get_global_rect().get_center()
	check("debug: the dbg button counts as UI (no board tap under it)", host.is_over_platform_ui(button_centre))
	host.debug_button.pressed.emit()
	await frames(2)
	check("debug: the dbg button shows the debug line and turns on the tap probe", (
		ar.hud.debug_requested and host.tap_probe_enabled
	))
	_look(game.global_position + Vector3(0.0, 0.3, 0.35), game.global_position)
	await frames(1)
	var screen: Vector2 = ar.xr_camera.unproject_position(game.to_global(TicTacToeGame.cell_top(2)))
	_phone_tap(screen)
	ar.refresh_debug()
	await frames(2)
	var line: String = ar.hud.debug_label.text
	check("debug: the line has the tap probe fields (px, viewport, window, scale, hit, cell)", (
		ar.hud.debug_label.visible and line.contains("tap px") and line.contains("vp 1560x720")
		and line.contains("win 2340x1080") and line.contains("cs 1.50") and line.contains("hit ")
		and line.contains("cell 2") and line.contains("xr-ray")
	))
	check("debug: and still the lock / drift fields", line.contains("lock ") and line.contains("anc "))
	check("debug: the probe draws the touch and the reprojected hit together", (
		host.tap_probe.is_showing() and host.tap_probe.hit is Vector2
		and (host.tap_probe.hit as Vector2).distance_to(screen) < 1.0
	))
	host.debug_button.pressed.emit()
	await frames(1)
	check("debug: pressing dbg again hides it (and the probe)", not ar.hud.debug_requested and not host.tap_probe_enabled)
	# Long-press the status line ("O to play").
	var status: Vector2 = host._status_hit_rect().get_center()
	var marks: int = 9 - game.rules.cells.count(TicTacToeRules.Mark.NONE)
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.position = _window_pos(status)
	down.pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	await get_tree().create_timer(GameHost.DEBUG_LONG_PRESS_SECONDS + 0.3).timeout
	check("debug: holding the status line for 1.5 s shows the debug line", ar.hud.debug_requested)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = down.position
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await frames(1)
	check("debug: the long-press is not also a game tap", 9 - game.rules.cells.count(TicTacToeRules.Mark.NONE) == marks)
	_phone_tap(status)
	await frames(1)
	check("debug: a short tap on the status line does not toggle it", ar.hud.debug_requested)
	for i: int in CalibrationHud.DEBUG_TAPS:
		ar.hud.register_panel_tap(float(i) * 0.1)
	check("debug: the 5-tap gesture still toggles it", not ar.hud.debug_requested)
	await free_host(host)
