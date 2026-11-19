extends "res://tests/surface_tests.gd"
## The play volume ("simulation box"): PlayBox maths and caps, manifest
## limits, the game API (get_box / contains / clamp / _on_box_changed /
## _on_box_ray), the Airspace slider, persistence (pause / resume, re-place,
## a new session), the outline (bright while adjusting, the game's level
## while playing) and the games' boxes.
## Run: godot --headless --path . res://tests/box_tests.tscn

const TTT_SAVE: String = "user://lg_placement_tic_tac_toe.cfg"
const CE_SAVE: String = "user://lg_placement_competitive_evolution.cfg"


func run_tests() -> void:
	_clear_saves()
	ARSession.clear_saved_area()
	_test_box_maths()
	_test_manifest_limits()
	await _test_game_api_fallback()
	await _test_airspace_slider_and_hook()
	await _test_persistence()
	await _test_outline_levels()
	await _test_box_rays()
	await _test_games_use_their_box()
	_clear_saves()
	ARSession.clear_saved_area()


func _clear_saves() -> void:
	for path: String in [TTT_SAVE, CE_SAVE, "user://lg_placement_probe.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _manifest(size: Vector2, height: float = 0.0, lo: float = 0.0, hi: float = 0.0) -> LGGameManifest:
	var m := LGGameManifest.new()
	m.id = &"probe"
	m.display_name = "Probe"
	m.board_size = size
	m.board_height = 0.1
	m.box_height = height
	m.box_min_height = lo
	m.box_max_height = hi
	m.entry = "res://tests/probe_game.gd"
	return m


func _probe_host(fake: FakeARBridge = null, level: float = 0.0, manifest: LGGameManifest = null) -> GameHost:
	var host := GameHost.new()
	host.game_id = &"probe"
	host.exit_handler = func() -> void: pass
	host.catalog = GameCatalog.new()
	host.catalog.register(manifest if manifest != null else _manifest(Vector2(0.3, 0.2), 0.2, 0.1, 0.35))
	host.game_loaded.connect(func(g: LGGame) -> void: (g as ProbeGame).outline_level = level)
	if fake != null:
		host.bridge_factory = func() -> ARCoreBridge: return fake
	add_child(host)
	await frames(2)
	return host


func _fake() -> FakeARBridge:
	var fake := FakeARBridge.new()
	fake.hit_callback = _model_hit
	fake.planes = _model_planes()
	return fake


## AR host on the plywood model, placed and adjusting (not locked).
func _placed(host: GameHost) -> ARSession:
	_session = host.session
	_look(Vector3(0.0, 0.6, 0.35), Vector3(0.0, PLY_HEIGHT, -0.6))
	await frames(3)
	host.session.place_at_reticle()
	host.session.finish_fit()
	await frames(1)
	return host.session


func _top_y(outline: PlayBoxOutline) -> float:
	var top: float = -1.0
	for child: Node in outline.get_children():
		if (child.name as String).begins_with("Top"):
			top = maxf(top, (child as Node3D).position.y)
	return top


# --- PlayBox ------------------------------------------------------------------

func _test_box_maths() -> void:
	var box: PlayBox = PlayBox.from_manifest(_manifest(Vector2(0.3, 0.2), 0.2))
	check("box: footprint = the manifest board size, floor at y = 0", (
		box.footprint().is_equal_approx(Vector2(0.3, 0.2)) and is_equal_approx(box.bounds().position.y, 0.0)
		and box.bounds().position.is_equal_approx(Vector3(-0.15, 0.0, -0.1))
	))
	check("box: height = the game's preferred height", is_equal_approx(box.height(), 0.2) and box.center().is_equal_approx(Vector3(0, 0.1, 0)))
	check("box: the cap is 1.5x the long side", is_equal_approx(PlayBox.height_cap(Vector2(0.3, 0.2)), 0.45))
	check("box: and never above 0.6 m", is_equal_approx(PlayBox.height_cap(Vector2(1.0, 0.8)), PlayBox.ABSOLUTE_MAX_HEIGHT))
	check("box: contains points inside, not outside or below the floor", (
		box.contains(Vector3(0.1, 0.1, 0.05)) and not box.contains(Vector3(0.2, 0.1, 0.0))
		and not box.contains(Vector3(0.0, -0.01, 0.0)) and not box.contains(Vector3(0.0, 0.21, 0.0))
	))
	check("box: margin shrinks contains", not box.contains(Vector3(0.14, 0.1, 0.0), 0.02))
	check("box: clamp_point moves a point to the nearest inside point", (
		box.clamp_point(Vector3(0.5, 0.9, -0.5)).is_equal_approx(Vector3(0.15, 0.2, -0.1))
		and box.clamp_point(Vector3(0.05, 0.05, 0.0)).is_equal_approx(Vector3(0.05, 0.05, 0.0))
		and box.clamp_point(Vector3(1, -1, 0), 0.01).is_equal_approx(Vector3(0.14, 0.01, 0.0))
	))
	var hit: Variant = box.intersect_ray(Vector3(0.0, 1.0, 0.0), Vector3.DOWN)
	check("box: a ray from above enters through the top", hit != null and (hit as Vector3).is_equal_approx(Vector3(0, 0.2, 0)))
	check("box: a ray that misses returns null", box.intersect_ray(Vector3(1.0, 1.0, 0.0), Vector3.DOWN) == null)
	var at: Variant = box.ray_at_height(Vector3(0.0, 1.0, 0.0), Vector3(0.05, -1.0, 0.0).normalized(), 0.5)
	check("box: ray_at_height clamps the height into the box", at != null and is_equal_approx((at as Vector3).y, 0.2))
	check("box: set_height clamps to the game's range", (
		is_equal_approx(PlayBox.from_manifest(_manifest(Vector2(0.3, 0.2), 0.2, 0.1, 0.3)).set_height(0.9), 0.3)
		and is_equal_approx(PlayBox.from_manifest(_manifest(Vector2(0.3, 0.2), 0.2, 0.1, 0.3)).set_height(0.01), 0.1)
	))
	var copy: PlayBox = box.duplicate_box()
	copy.set_height(0.1)
	check("box: duplicate_box is independent", is_equal_approx(box.height(), 0.2) and is_equal_approx(copy.height(), 0.1))


func _test_manifest_limits() -> void:
	var greedy: PlayBox = PlayBox.from_manifest(_manifest(Vector2(0.3, 0.2), 2.0, 0.0, 3.0))
	check("limits: a game asking for 2 m on a 30 cm board gets the 45 cm cap", (
		is_equal_approx(greedy.height(), 0.45) and is_equal_approx(greedy.max_height, 0.45)
	))
	var big: PlayBox = PlayBox.from_manifest(_manifest(Vector2(1.2, 1.0), 0.0, 0.0, 5.0))
	check("limits: no box is taller than 0.6 m", is_equal_approx(big.max_height, 0.6))
	var plain: PlayBox = PlayBox.from_manifest(_manifest(Vector2(0.3, 0.3)))
	check("limits: no box_height -> board_height, adjustable from 2 cm to the cap", (
		is_equal_approx(plain.height(), 0.1) and is_equal_approx(plain.min_height, PlayBox.MIN_HEIGHT)
		and is_equal_approx(plain.max_height, 0.45) and plain.is_adjustable()
	))
	var fixed: PlayBox = PlayBox.from_manifest(_manifest(Vector2(0.3, 0.3), 0.2, 0.2, 0.2))
	check("limits: min == max is a fixed (non-adjustable) box", not fixed.is_adjustable() and is_equal_approx(fixed.height(), 0.2))
	check("limits: a saved height is clamped on load", is_equal_approx(PlayBox.from_manifest(_manifest(Vector2(0.3, 0.2), 0.2, 0.1, 0.3), 0.8).height(), 0.3))
	var bad: LGGameManifest = _manifest(Vector2(0.3, 0.2), 0.2, 0.3, 0.1)
	check("limits: min > max fails validation", not bad.validate().is_empty())
	var negative: LGGameManifest = _manifest(Vector2(0.3, 0.2), -0.1)
	check("limits: a negative height fails validation", not negative.validate().is_empty())
	check("limits: the shipped manifests validate", (
		load("res://games/tic_tac_toe/manifest.tres").validate().is_empty()
		and load("res://games/competitive_evolution/manifest.tres").validate().is_empty()
	))


func _test_game_api_fallback() -> void:
	var host: GameHost = await _probe_host()
	var probe: ProbeGame = host.game as ProbeGame
	check("api: the game has its box before _on_board_ready, same as the host's", (
		probe.get_box() == host.box and is_equal_approx(probe.get_box().height(), 0.2)
		and probe.events.has("ready") and probe.box_changes.is_empty()
	))
	check("api: box_contains / clamp_to_box use the box", (
		probe.box_contains(Vector3(0.0, 0.1, 0.0)) and not probe.box_contains(Vector3(0.0, 0.3, 0.0))
		and probe.clamp_to_box(Vector3(0.0, 0.3, 0.0)).is_equal_approx(Vector3(0.0, 0.2, 0.0))
	))
	host.set_box_height(0.3)
	check("api: a height change fires _on_box_changed and box_changed", probe.box_changes.size() == 1 and is_equal_approx(probe.box_changes[0], 0.3))
	host.set_box_height(0.3)
	check("api: setting the same height again does not fire", probe.box_changes.size() == 1)
	host.set_box_height(5.0)
	check("api: requests above the game's max are clamped", is_equal_approx(probe.get_box().height(), 0.35) and probe.box_changes.size() == 2)
	check("api: the outline top follows the box", is_equal_approx(_top_y(host.box_outline), 0.35))
	host.session.set_box_height(-1.0)
	check("api: -1 returns to the game's preferred height", is_equal_approx(probe.get_box().height(), 0.2))
	check("api: fallback outline stays hidden for a game that does not opt in", not host.board_frame.visible)
	await free_host(host)
	_clear_saves()


func _test_airspace_slider_and_hook() -> void:
	var host: GameHost = await _probe_host(_fake())
	var ar: ARSession = await _placed(host)
	var probe: ProbeGame = host.game as ProbeGame
	var slider: VSlider = ar.hud.airspace_slider
	check("slider: shown while adjusting, with the game's range", (
		ar.flow.step == CalibrationFlow.Step.ADJUSTING and ar.hud.airspace_panel.visible
		and is_equal_approx(slider.min_value, 0.1) and is_equal_approx(slider.max_value, 0.35)
		and is_equal_approx(slider.value, 0.2)
	))
	var middle: Vector2 = ar.hud.airspace_panel.get_global_rect().get_center()
	check("slider: the panel counts as UI (no board touches under it)", ar.hud.is_over_ui(middle) and host.is_over_platform_ui(middle))
	slider.value = 0.28
	check("slider: moving it resizes the box and fires the hook", (
		is_equal_approx(probe.get_box().height(), 0.28) and probe.box_changes.size() == 1 and is_equal_approx(probe.box_changes[0], 0.28)
		and is_equal_approx(_top_y(host.box_outline), 0.28) and ar.hud.airspace_value_label.text == "28 cm"
	))
	check("slider: the height is saved with the placement", is_equal_approx(ar.placement.box_height, 0.28))
	ar.set_locked(true)
	await frames(1)
	check("slider: hidden once locked", not ar.hud.airspace_panel.visible)
	ar.set_locked(false)
	await frames(1)
	check("slider: back when unlocked, at the current height", ar.hud.airspace_panel.visible and is_equal_approx(slider.value, 0.28))
	await free_host(host)

	var fixed: GameHost = await _probe_host(_fake(), 0.0, _manifest(Vector2(0.3, 0.2), 0.2, 0.2, 0.2))
	var fixed_ar: ARSession = await _placed(fixed)
	check("slider: hidden for a game with a fixed height", (
		fixed_ar.flow.step == CalibrationFlow.Step.ADJUSTING and not fixed_ar.hud.airspace_panel.visible
	))
	await free_host(fixed)
	_clear_saves()


func _test_persistence() -> void:
	var host: GameHost = await _probe_host(_fake())
	var ar: ARSession = await _placed(host)
	var probe: ProbeGame = host.game as ProbeGame
	ar.hud.airspace_slider.value = 0.15
	ar.set_locked(true)
	await frames(1)
	host.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	await frames(1)
	host.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await frames(2)
	check("persist: pause / resume keeps the box", is_equal_approx(probe.get_box().height(), 0.15) and probe.is_playing())
	ar.begin_replace()
	await frames(1)
	ar.place_at_reticle()
	await frames(1)
	check("persist: re-placing keeps the box and the slider value", (
		is_equal_approx(probe.get_box().height(), 0.15) and is_equal_approx(ar.hud.airspace_slider.value, 0.15)
		and is_equal_approx(ar.placement.box_height, 0.15)
	))
	var scale_before: float = ar.placement.scale
	ar.placement.scale = scale_before * 1.5
	ar._apply_transforms()
	await frames(1)
	var floor0: Node3D = host.box_outline.get_node(^"Floor0") as Node3D
	var world_width: float = host.box_outline.to_global(Vector3(-0.15, 0, -0.1)).distance_to(host.box_outline.to_global(Vector3(0.15, 0, -0.1)))
	check("persist: resizing the board scales the box with it (board units stay fixed)", (
		floor0 != null and is_equal_approx(probe.get_box().footprint().x, 0.3)
		and absf(world_width - 0.3 * ar.placement.scale) < 0.001
	))
	await free_host(host)
	var again: GameHost = await _probe_host(_fake())
	check("persist: a new session starts with the saved height", is_equal_approx(again.game.get_box().height(), 0.15))
	await free_host(again)
	var before: BoardPlacement = BoardPlacement.new()
	before.load_from("user://lg_placement_probe.cfg")
	before.scale = 1.37
	before.save("user://lg_placement_probe.cfg")
	var desk: GameHost = await _probe_host()
	check("persist: the desktop fallback uses the saved height too", is_equal_approx(desk.game.get_box().height(), 0.15))
	desk.set_box_height(0.25)
	desk.session.set_box_height(0.25)
	await free_host(desk)
	var after: BoardPlacement = BoardPlacement.new()
	after.load_from("user://lg_placement_probe.cfg")
	check("persist: fallback saves only the height (AR scale kept)", (
		is_equal_approx(after.box_height, 0.25) and is_equal_approx(after.scale, 1.37)
	))
	_clear_saves()


func _test_outline_levels() -> void:
	var host: GameHost = await _probe_host(_fake())
	var ar: ARSession = await _placed(host)
	check("outline: bright while adjusting (floor, 4 fading pillars, top frame)", (
		host.board_frame == host.box_outline and host.box_outline.visible and is_equal_approx(host.box_outline.level, 1.0)
		and host.box_outline.get_child_count() == 4 * (2 + PlayBoxOutline.PILLAR_INTENSITY.size())
		and PlayBoxOutline.PILLAR_INTENSITY[0] > PlayBoxOutline.PILLAR_INTENSITY[2]
	))
	ar.set_locked(true)
	await frames(1)
	check("outline: hidden while playing by default", not host.box_outline.visible)
	await free_host(host)
	_clear_saves()
	var dim: GameHost = await _probe_host(_fake(), 0.3)
	var dim_ar: ARSession = await _placed(dim)
	check("outline: an opted-in game is bright while adjusting", dim.box_outline.visible and is_equal_approx(dim.box_outline.level, 1.0))
	dim_ar.set_locked(true)
	await frames(1)
	check("outline: and dim at its level while playing", dim.box_outline.visible and is_equal_approx(dim.box_outline.level, 0.3))
	await free_host(dim)
	_clear_saves()


func _test_box_rays() -> void:
	var host: GameHost = await _probe_host()
	var probe: ProbeGame = host.game as ProbeGame
	var camera: Camera3D = host.active_camera()
	var target: Vector3 = Vector3(0.05, 0.1, -0.02)
	var screen: Vector2 = camera.unproject_position(probe.to_global(target))
	host.route_gesture({"kind": &"tap", "position": screen})
	check("ray: a tap gives the game a board-space ray", probe.box_rays.size() == 1)
	if probe.box_rays.size() == 1:
		var origin: Vector3 = probe.box_rays[0][0]
		var dir: Vector3 = probe.box_rays[0][1]
		var closest: Vector3 = origin + dir * dir.dot(target - origin)
		check("ray: it passes through the tapped point in the airspace", closest.distance_to(target) < 0.002 and is_equal_approx(dir.length(), 1.0))
		var enter: Variant = probe.get_box().intersect_ray(origin, dir)
		check("ray: it can be hit-tested against the box", enter != null and probe.box_contains(enter as Vector3, -0.0001))
	check("ray: the floor tap still arrives after the ray", probe.taps.size() == 1)
	await free_host(host)


func _test_games_use_their_box() -> void:
	var host: GameHost = await make_host(&"tic_tac_toe")
	var game: TicTacToeGame = host.game as TicTacToeGame
	check("ttt: a small airspace (20 cm, 12-30 cm)", (
		is_equal_approx(game.get_box().height(), 0.2) and is_equal_approx(game.get_box().min_height, 0.12)
		and is_equal_approx(game.get_box().max_height, 0.3)
	))
	check("ttt: the tap surface (slab top) is inside the box", host.pick_height() == TicTacToeGame.SLAB_TOP)
	var rest: float = TicTacToeGame.SLAB_TOP + TicTacToeGame.PIECE_LIFT
	check("ttt: pieces drop from inside the box top", (
		rest + game.drop_height() <= game.get_box().height() - TicTacToeGame.DROP_TOP_MARGIN + 0.0001
	))
	host.set_box_height(0.12)
	check("ttt: a shorter box means a shorter drop, still inside", (
		game.drop_height() < TicTacToeGame.DROP_HEIGHT and rest + game.drop_height() <= 0.12
	))
	var camera: Camera3D = host.active_camera()
	_tap(camera.unproject_position(game.to_global(TicTacToeGame.cell_top(4))))
	var body: Node3D = game.piece_body(4)
	check("ttt: a new piece starts below the box top", (
		body != null and game.pieces[4].position.y + body.position.y <= 0.12 + 0.0001
	))
	check("ttt: the outline stays dim while playing", host.box_outline.visible and host.box_outline.level < 0.5)
	await free_host(host)
	_clear_saves()
	var ce: GameHost = await make_host(&"competitive_evolution")
	var board: LGGame = ce.game
	var label: Node3D = board.get_node(^"ComingSoon") as Node3D
	check("ce: a tall box for the globe (58 cm, up to the 60 cm cap)", (
		is_equal_approx(board.get_box().height(), 0.58) and is_equal_approx(board.get_box().max_height, 0.6)
		and board.get_box().height() > 0.42
	))
	check("ce: its label sits inside the box", board.box_contains(label.position))
	ce.set_box_height(0.5)
	check("ce: and follows a lower box", board.box_contains(label.position) and label.position.y < 0.5)
	check("ce: its outline is hidden while playing", not ce.box_outline.visible)
	await free_host(ce)
	_clear_saves()
