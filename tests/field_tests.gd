extends "res://tests/surface_tests.gd"
## Field-test regressions from the Samsung run of lg-test-170ac5f:
##   - phone-style touch sequences (emulated mouse alongside touches, OS-
##     cancelled touches, second fingers, taps at a low viewing angle on the
##     raised board, no UI covering the board),
##   - tracing robustness (stray points, jumps, rays that miss, separate
##     strokes, no default points, height refinement, real touch events),
##   - the board staying world-locked (lock-time re-anchoring, camera motion,
##     plane refinement, anchor tracking loss / correction, camera tracking
##     loss, drift readout),
##   - the hologram board (materials, drop animation, win line, status line).
## Reuses the plywood scene model of surface_tests.gd.
## Run: godot --headless --path . res://tests/field_tests.tscn


func run_tests() -> void:
	ARSession.clear_saved_area()
	await _test_android_touch_sequences()
	await _test_low_angle_taps_hit_the_slab_top()
	await _test_no_ui_over_the_board()
	await _test_trace_robustness()
	await _test_trace_with_touch_events()
	await _test_world_lock()
	await _test_tracking_loss()
	await _test_hologram_board()
	await _test_status_line()
	ARSession.clear_saved_area()


func _marks(game: TicTacToeGame) -> int:
	return 9 - game.rules.cells.count(TicTacToeRules.Mark.NONE)


func _mouse(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.device = InputEvent.DEVICE_ID_EMULATION
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	event.global_position = position
	return event


# --- Touch ------------------------------------------------------------------------

func _test_android_touch_sequences() -> void:
	var host: GameHost = await make_host(&"tic_tac_toe")
	var game: TicTacToeGame = host.game as TicTacToeGame
	var camera: Camera3D = host.active_camera()
	var cell := func(index: int) -> Vector2: return camera.unproject_position(game.to_global(TicTacToeGame.cell_top(index)))
	var vp: Viewport = get_viewport()
	# Android sends a touch plus an emulated mouse click for every tap.
	var c4: Vector2 = cell.call(4) as Vector2
	vp.push_input(touch(0, c4, true), true)
	vp.push_input(_mouse(c4, true), true)
	vp.push_input(touch(0, c4, false), true)
	vp.push_input(_mouse(c4, false), true)
	check("android: touch + emulated mouse is one tap, not two", _marks(game) == 1 and host.taps_seen == 1 and game.rules.cells[4] == TicTacToeRules.Mark.X)
	# Through Godot's real input pipeline (touch -> emulated mouse, as on a phone).
	# parse_input_event takes window pixels (the phone screen), not viewport units.
	var c0: Vector2 = cell.call(0) as Vector2
	var c0_window: Vector2 = get_tree().root.get_final_transform() * c0
	Input.parse_input_event(touch(0, c0_window, true))
	Input.parse_input_event(touch(0, c0_window, false))
	Input.flush_buffered_events()
	await frames(2)
	check("android: a tap through Input.parse_input_event places a mark", game.rules.cells[0] == TicTacToeRules.Mark.O and _marks(game) == 2)
	# The finger rolls while lifting: the mark goes where it went down.
	var c8: Vector2 = cell.call(8) as Vector2
	var c5: Vector2 = cell.call(5) as Vector2
	var roll: Vector2 = (c5 - c8).normalized() * minf(host._gestures.tap_slop_px * 0.9, c8.distance_to(c5) * 0.8)
	vp.push_input(touch(0, c8, true), true)
	vp.push_input(drag(0, c8 + roll, roll), true)
	vp.push_input(touch(0, c8 + roll, false), true)
	check("android: a tap lands where the finger went down, not where it lifted", game.rules.cells[8] != TicTacToeRules.Mark.NONE and game.rules.cells[5] == TicTacToeRules.Mark.NONE)
	var c2: Vector2 = cell.call(2) as Vector2
	var cancelled := touch(0, c2, false)
	cancelled.canceled = true
	vp.push_input(touch(0, c2, true), true)
	vp.push_input(cancelled, true)
	check("android: a touch the OS cancels is not a tap", game.rules.cells[2] == TicTacToeRules.Mark.NONE)
	vp.push_input(touch(0, c2, true), true)
	vp.push_input(touch(1, c5, true), true)
	vp.push_input(touch(1, c5, false), true)
	vp.push_input(touch(0, c2, false), true)
	check("android: two fingers down is never a tap", game.rules.cells[2] == TicTacToeRules.Mark.NONE and game.rules.cells[5] == TicTacToeRules.Mark.NONE)
	vp.push_input(drag(3, c5, Vector2(4, 4)), true)
	vp.push_input(touch(3, c5, false), true)
	_tap(c2)
	check("android: stray drags / releases of unknown fingers do not block the next tap", game.rules.cells[2] != TicTacToeRules.Mark.NONE)
	var before: int = _marks(game)
	for index: int in [1, 3, 6]:
		_tap(cell.call(index) as Vector2)
	check("android: quick taps in a row all register", _marks(game) == before + 3)
	await free_host(host)


func _test_low_angle_taps_hit_the_slab_top() -> void:
	var host: GameHost = await _ar_host(&"tic_tac_toe")
	var ar: ARSession = host.session
	ar.place_at_reticle()
	ar.set_locked(true)
	var game: TicTacToeGame = host.game as TicTacToeGame
	var centre: Vector3 = game.global_position
	# Phone held low: ~24 degrees above the table, 50 cm away.
	_look(centre + Vector3(0.0, 0.2, 0.45), centre)
	await frames(2)
	var aim: Vector3 = game.to_global(TicTacToeGame.cell_top(4) + Vector3(0.0, 0.0, -0.03))
	var screen: Vector2 = _screen(aim)
	var on_floor: Variant = GameHost.screen_to_board(ar.xr_camera, game, screen, 0.0)
	check("raised board: projecting a low-angle tap on the table plane would pick the wrong cell", (
		on_floor != null and TicTacToeGame.cell_at(on_floor as Vector3) != 4
	))
	_tap(screen)
	check("raised board: the same tap on the slab top picks the cell the player sees", game.rules.cells[4] == TicTacToeRules.Mark.X)
	check("raised board: the tap ring shows on the slab top", (
		host._tap_marker != null and absf(host._tap_marker.position.y - (TicTacToeGame.SLAB_TOP + 0.004)) < 0.0001
	))
	await free_host(host)


func _blocking_controls(root: Node, point: Vector2) -> Array[String]:
	var out: Array[String] = []
	for node: Node in root.find_children("*", "Control", true, false):
		var control: Control = node as Control
		if control.is_visible_in_tree() and control.mouse_filter != Control.MOUSE_FILTER_IGNORE and control.get_global_rect().has_point(point):
			out.append(String(control.get_path()))
	return out


func _test_no_ui_over_the_board() -> void:
	var host: GameHost = await _ar_host(&"tic_tac_toe")
	var ar: ARSession = host.session
	ar.place_at_reticle()
	ar.set_locked(true)
	await frames(2)
	var game: TicTacToeGame = host.game as TicTacToeGame
	var blocked: Array[String] = []
	for index: int in 9:
		blocked.append_array(_blocking_controls(host, _screen(game.to_global(TicTacToeGame.cell_top(index)))))
	check("ui: no visible control covers any cell of the locked board %s" % str(blocked), blocked.is_empty())
	ar.set_locked(false)
	ar.begin_replace()
	await frames(2)
	ar.begin_trace()
	await frames(1)
	var size: Vector2 = get_viewport().get_visible_rect().size
	var mid_blocked: Array[String] = []
	for p: Vector2 in [size * 0.5, size * Vector2(0.25, 0.6), size * Vector2(0.75, 0.6), size * Vector2(0.5, 0.75)]:
		mid_blocked.append_array(_blocking_controls(host, p))
	check("ui: while tracing, the middle of the screen is free to draw on %s" % str(mid_blocked), mid_blocked.is_empty())
	await free_host(host)


# --- Tracing ----------------------------------------------------------------------

func _test_trace_robustness() -> void:
	var host: GameHost = await _ar_host(&"tic_tac_toe")
	var ar: ARSession = host.session
	var fake: FakeARBridge = ar.bridge as FakeARBridge
	ar.begin_trace()
	ar._update_overlay()
	check("trace: feature-point dots are hidden while tracing (they looked like traced points)", not ar._overlay_points.visible)
	var y: float = PLY_HEIGHT
	check("trace: a stroke starts on the plywood", ar.trace_begin(_screen(Vector3(-0.4, y, -0.85))))
	for k: int in range(1, 6):
		ar.trace_add(_screen(Vector3(-0.4 + 0.04 * k, y, -0.85)))
	var count: int = ar.trace_point_count()
	check("trace: a single stray point a metre away is dropped", (
		not ar.trace_add(_screen(Vector3(0.6, y, -1.6))) and ar.trace_point_count() == count
	))
	ar.trace_add(_screen(Vector3(-0.16, y, -0.85)))
	check("trace: the stroke carries on after a stray point", ar.trace_point_count() == count + 1)
	var far := Vector3(0.3, y, -0.85)
	ar.trace_add(_screen(far))
	ar.trace_add(_screen(far + Vector3(0.012, 0, 0)))
	var third: bool = ar.trace_add(_screen(far + Vector3(0.024, 0, 0)))
	check("trace: a finger that really jumped is followed after a few events", third)
	var last: Vector3 = ar._trace_points[ar.trace_point_count() - 1]
	fake.hit_callback = func(_n: Vector2) -> Dictionary: return {"hit": false}
	var near_miss: bool = ar.trace_add(_screen(last + Vector3(0.05, 0, 0)))
	var far_miss: bool = ar.trace_add(_screen(last + Vector3(0.25, 0, 0)))
	check("trace: a point whose ray misses every surface is kept only next to the last supported point", near_miss and not far_miss)
	fake.hit_callback = func(_n: Vector2) -> Dictionary: return {"hit": true, "kind": "plane"}
	var no_pose: bool = ar.trace_add(_screen(last + Vector3(0.2, 0, 0)))
	var zero_free: bool = true
	for p: Vector3 in ar._trace_points:
		zero_free = zero_free and not p.is_zero_approx() and absf(p.y - y) < 0.001
	check("trace: a hit without a pose is treated as a miss; no default (0,0,0) point ever enters", (
		ARSession.hit_pose({"hit": true}) == null and zero_free and not no_pose
	))
	fake.hit_callback = _model_hit
	var points_before: int = ar.trace_point_count()
	ar.trace_end()
	var resumed: bool = ar.trace_begin(_screen(last + Vector3(0.06, 0, 0.0)))
	check("trace: a new stroke next to the end continues the outline", resumed and ar.trace_point_count() == points_before + 1)
	ar.trace_end()
	ar.trace_begin(_screen(Vector3(-0.5, y, -0.6)))
	check("trace: a new stroke far from the end starts over (no joining line)", ar.trace_point_count() == 1)
	ar.clear_trace()
	# First hit reads 2 cm high (a noisy plane estimate); later hits are right.
	var calls: Array[int] = [0]
	fake.hit_callback = func(n: Vector2) -> Dictionary:
		calls[0] += 1
		var hit: Dictionary = _model_hit(n)
		if calls[0] <= 2 and bool(hit.get("hit", false)):
			var pose: Transform3D = hit["pose"] as Transform3D
			hit["pose"] = Transform3D(pose.basis, pose.origin + Vector3(0.0, 0.02, 0.0))
		return hit
	var traced := Rect2(ply_real.position + Vector2(0.01, 0.01), ply_real.size - Vector2(0.02, 0.02))
	var placed: bool = _trace_rect(ar, traced, PLY_HEIGHT)
	check("trace: the outline height is refined from all stroke hits (one noisy start does not lift the board)", (
		placed and absf(host.world_anchor.global_position.y - PLY_HEIGHT) < 0.003
	))
	check("trace: the traced board is anchored to the detected surface (plane anchor)", (
		ar.anchor_kind == "plane" and fake.anchor_calls.size() > 0 and fake.anchor_calls[fake.anchor_calls.size() - 1] == "screen"
	))
	await frames(1)
	check("trace: the refined outline still keeps the board on the real plywood", _inside(_corners_world(host.game), ply_real, PLY_HEIGHT))
	fake.hit_callback = _model_hit
	await free_host(host)


func _test_trace_with_touch_events() -> void:
	var host: GameHost = await _ar_host(&"tic_tac_toe")
	var ar: ARSession = host.session
	ar.begin_trace()
	await frames(1)
	var vp: Viewport = get_viewport()
	var r := Rect2(ply_real.position + Vector2(0.02, 0.02), ply_real.size - Vector2(0.04, 0.04))
	var corners: Array[Vector2] = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var at := func(p: Vector2) -> Vector2: return _screen(Vector3(p.x, PLY_HEIGHT, p.y))
	var previous: Vector2 = at.call(corners[0]) as Vector2
	vp.push_input(touch(0, previous, true), true)
	for side: int in 4:
		for k: int in range(1, 13):
			var screen: Vector2 = at.call((corners[side] as Vector2).lerp(corners[(side + 1) % 4], float(k) / 12.0)) as Vector2
			vp.push_input(drag(0, screen, screen - previous), true)
			if k % 4 == 0:
				vp.push_input(_mouse(screen, true), true)
			previous = screen
	vp.push_input(touch(0, previous, false), true)
	await frames(1)
	check("trace: a one-finger outline drawn with real touch events places the board", ar.is_placed() and ar.region != null and ar.region.source == SurfaceRegion.Source.TRACED)
	await free_host(host)


# --- World lock -------------------------------------------------------------------

func _test_world_lock() -> void:
	var host: GameHost = await _ar_host(&"tic_tac_toe")
	var ar: ARSession = host.session
	var fake: FakeARBridge = ar.bridge as FakeARBridge
	ar.place_at_reticle()
	await frames(1)
	var centre: Vector2 = _screen(host.game.global_position)
	ar.drag_board(centre, _screen(host.game.to_global(Vector3(0.12, 0.0, 0.0))))
	await frames(1)
	var before_lock: Transform3D = host.game.global_transform
	check("lock: the board was dragged off its anchor", ar.placement.offset.length() > 0.05)
	ar.set_locked(true)
	await frames(1)
	check("lock: locking re-anchors at the board's final spot without moving it", (
		xform_near(host.game.global_transform, before_lock, 0.0002) and ar.placement.offset.is_zero_approx()
		and near(ar.anchors.pose.origin, before_lock.origin, 0.0002) and fake.anchor_calls[fake.anchor_calls.size() - 1] == "pose"
	))
	var locked: Transform3D = host.game.global_transform
	var still: bool = true
	for from: Vector3 in [Vector3(0.9, 0.5, -0.1), Vector3(-0.8, 0.3, -0.4), Vector3(0.05, 1.2, -0.55), Vector3(0.1, 0.4, 0.6)]:
		_look(from, Vector3(0.0, PLY_HEIGHT, -0.7))
		await frames(2)
		still = still and xform_near(host.game.global_transform, locked, 0.0001)
	check("world lock: walking around the board does not move it", still)
	var grown: Array = _model_planes()
	grown[0] = {"pose": Transform3D(Basis(Vector3.UP, 0.3), Vector3(0.2, PLY_HEIGHT + 0.01, -0.5)), "polygon": _rect_poly(Rect2(-0.9, -0.5, 1.8, 1.0))}
	fake.planes = grown
	await frames(8)
	check("world lock: ARCore re-estimating the plane (new centre / extent) does not move a locked board", xform_near(host.game.global_transform, locked, 0.0001))
	fake.planes = _model_planes()
	fake.anchor_state = 1
	fake.pose_shift = Transform3D(Basis(Vector3.UP, 1.0), Vector3(0.6, -0.3, 0.2))
	await frames(4)
	check("world lock: while the anchor is not tracking, the board holds its last pose", xform_near(host.game.global_transform, locked, 0.0001))
	fake.pose_shift = Transform3D(Basis(), Vector3(0.008, 0.0, 0.0))
	fake.anchor_state = 0
	ar.anchors.poll()
	ar._apply_transforms(0.016)
	check("world lock: small ARCore corrections apply at once", near(host.world_anchor.global_position, ar.anchors.pose.origin, 0.00001))
	fake.pose_shift = Transform3D(Basis(), Vector3(0.12, 0.0, 0.0))
	ar.anchors.poll()
	ar._apply_transforms(0.016)
	var first_step: float = host.world_anchor.global_position.distance_to(ar.anchors.pose.origin)
	for i: int in 40:
		ar._apply_transforms(0.016)
	var settled: float = host.world_anchor.global_position.distance_to(ar.anchors.pose.origin)
	check("world lock: a big correction after tracking returns eases in instead of snapping", first_step > 0.05 and settled < 0.002)
	fake.pose_shift = Transform3D.IDENTITY
	ar.anchors.poll()
	ar._apply_transforms()
	ar._process(0.25)
	var debug: String = ar.debug_suffix()
	check("debug: the AR line shows anchor state, drift, lock drift, board position and height over the surface (%s)" % debug, (
		debug.contains("anc T free") and debug.contains("mm") and debug.contains("lock ") and debug.contains("board ") and debug.contains("surf +0.0cm")
	))
	fake.pose_shift = Transform3D(Basis(), Vector3(0.0, 0.05, 0.0))
	ar.anchors.poll()
	ar._apply_transforms()
	await frames(1)
	check("debug: a board floating 5 cm over the surface shows as surf +5cm", absf(ar.measure_surface_gap() - 0.05) < 0.002)
	fake.pose_shift = Transform3D.IDENTITY
	await free_host(host)


func _test_tracking_loss() -> void:
	var host: GameHost = await _ar_host(&"tic_tac_toe")
	var ar: ARSession = host.session
	var fake: FakeARBridge = ar.bridge as FakeARBridge
	ar.place_at_reticle()
	ar.set_locked(true)
	await frames(1)
	var good: Dictionary = fake.info.duplicate()
	var lost: Dictionary = fake.info.duplicate()
	lost["camera_state"] = 1
	fake.info = lost
	ar._process(0.3)
	var brief: bool = host.world_anchor.visible
	ar._process(0.3)
	check("tracking loss: a brief glitch keeps the board, a real loss hides it (no board sliding with the frozen camera)", (
		brief and not host.world_anchor.visible and ar.board_hidden_by_loss and ar.hud.status_label.text.contains("Tracking lost")
	))
	fake.info = good
	ar._process(0.3)
	check("tracking loss: the board comes back when tracking does, and the loss is counted", (
		host.world_anchor.visible and not ar.board_hidden_by_loss and ar.tracking_losses == 1 and ar.debug_suffix().contains("lost 1")
	))
	await free_host(host)


# --- Hologram board --------------------------------------------------------------

func _test_hologram_board() -> void:
	var host: GameHost = await make_host(&"tic_tac_toe")
	var game: TicTacToeGame = host.game as TicTacToeGame
	var slab: MeshInstance3D = game.get_node(^"Slab") as MeshInstance3D
	var mat: ShaderMaterial = slab.material_override as ShaderMaterial
	check("holo: the board is drawn with the platform hologram shader", (
		mat != null and mat.shader == Holo.SURFACE_SHADER and Holo.SURFACE_SHADER.code.contains("depth_draw_never")
		and Holo.SURFACE_SHADER.code.contains("unshaded") and game.get_node_or_null(^"HoloGlowBase") != null
	))
	check("holo: the slab floats above the table and taps use its top", (
		game.board_surface_height() == TicTacToeGame.SLAB_TOP and TicTacToeGame.SLAB_BOTTOM > 0.0
	))
	var camera: Camera3D = host.active_camera()
	_tap(camera.unproject_position(game.to_global(TicTacToeGame.cell_top(4))))
	var body: Node3D = game.piece_body(4)
	var drop: HoloDrop = game.drop_of(4)
	check("drop: a new piece starts high above its cell", body != null and drop != null and body.position.y > TicTacToeGame.DROP_HEIGHT * 0.8)
	var mid: Dictionary = HoloDrop.curve(HoloDrop.FALL_TIME * 0.5, 0.16)
	var impact: Dictionary = HoloDrop.curve(HoloDrop.FALL_TIME + 0.01, 0.16)
	var done: Dictionary = HoloDrop.curve(HoloDrop.total_time(), 0.16)
	check("drop: it falls, squashes and flashes on landing, then rests at normal size", (
		float(mid["y"]) > 0.0 and float(mid["y"]) < 0.16 and (impact["scale"] as Vector3).y < 0.75
		and (impact["scale"] as Vector3).x > 1.1 and float(impact["flash"]) > 0.8
		and is_zero_approx(float(done["y"])) and (done["scale"] as Vector3).is_equal_approx(Vector3.ONE) and is_zero_approx(float(done["flash"]))
	))
	var landed: Array[int] = [0]
	drop.landed.connect(func() -> void: landed[0] += 1)
	drop.advance(HoloDrop.FALL_TIME + 0.01)
	var ripple: MeshInstance3D = drop.ripple
	check("drop: landing sends a ripple across the board", landed[0] == 1 and ripple != null and ripple.visible)
	drop.advance(HoloDrop.total_time())
	await frames(1)
	check("drop: the piece ends at rest on its cell and the animation cleans up", (
		is_zero_approx(body.position.y) and body.scale.is_equal_approx(Vector3.ONE) and game.drop_of(4) == null and not is_instance_valid(ripple)
	))
	for index: int in [0, 1, 3, 7]:
		_tap(camera.unproject_position(game.to_global(TicTacToeGame.cell_top(index))))
	check("win: X down the middle column wins", game.rules.winner == TicTacToeRules.Mark.X and game.rules.winning_line == [1, 4, 7])
	check("win: the win lights up only when the winning piece lands", game.win_line() == null and game.drop_of(7) != null)
	game.drop_of(7).advance(HoloDrop.FALL_TIME + 0.01)
	var line: MeshInstance3D = game.win_line()
	check("win: a glowing gold line runs through the winning cells", (
		line != null and line.global_position.distance_to(game.to_global(TicTacToeGame.cell_top(4))) < 0.05
		and (line.material_override as ShaderMaterial).get_shader_parameter("color") == Holo.GOLD
	))
	_tap(camera.unproject_position(game.to_global(TicTacToeGame.cell_top(4))))
	await frames(1)
	check("win: tapping after a win starts a new round and clears the line", game.rules.cells.count(TicTacToeRules.Mark.NONE) == 9 and game.win_line() == null)
	var token: Vector3 = game.label_position()
	check("token: the turn hologram is small and sits just outside the board edge", (
		game._token_piece != null and game._token_piece.scale.x < 0.5
		and maxf(absf(token.x), absf(token.z)) < game.get_board_size().x * 0.5 + 0.06
		and maxf(absf(token.x), absf(token.z)) > TicTacToeGame.CELL * 1.5 + 0.03
	))
	await free_host(host)


func _test_status_line() -> void:
	var host: GameHost = await _ar_host(&"tic_tac_toe")
	var ar: ARSession = host.session
	ar.place_at_reticle()
	await frames(1)
	check("status: while adjusting, the game line is hidden (no misleading 'Paused')", not host._status_label.visible)
	ar.set_locked(true)
	await frames(1)
	check("status: locked, the game line shows the turn without 'Paused'", (
		host._status_label.visible and host.get_status_text() == "X to play"
	))
	await free_host(host)
