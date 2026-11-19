extends LGTestSuite
## Headless tests for the game contract, the catalog, the launcher and
## launching games onto the board (fallback and AR).
## Run: godot --headless --path . res://tests/platform_tests.tscn


func run_tests() -> void:
	_test_manifest_validation()
	_test_catalog()
	_test_game_contract()
	_test_tic_tac_toe_rules()
	await _test_launcher()
	await _test_fallback_launch()
	await _test_tap_routing()
	await _test_drag_routing()
	await _test_ar_launch_lifecycle()
	await _test_competitive_evolution_stub()
	await _test_bad_game_id()


func _probe_manifest(id: StringName = &"probe") -> LGGameManifest:
	var manifest := LGGameManifest.new()
	manifest.id = id
	manifest.display_name = "Probe"
	manifest.board_size = Vector2(0.3, 0.2)
	manifest.entry = "res://tests/probe_game.gd"
	return manifest


func _probe_catalog() -> GameCatalog:
	var catalog := GameCatalog.new()
	catalog.register(_probe_manifest())
	return catalog


# --- Manifests and catalog ------------------------------------------------------

func _test_manifest_validation() -> void:
	var good: LGGameManifest = _probe_manifest()
	check("manifest: a complete manifest validates", good.is_valid())
	var bad := LGGameManifest.new()
	var problems: PackedStringArray = bad.validate()
	check("manifest: an empty manifest lists every problem", (
		problems.size() >= 3 and "\n".join(problems).contains("id is empty")
		and "\n".join(problems).contains("display_name") and "\n".join(problems).contains("entry")
	))
	var upper: LGGameManifest = _probe_manifest(&"Bad Id")
	check("manifest: ids must be lower-case identifiers", not upper.is_valid())
	var players: LGGameManifest = _probe_manifest()
	players.min_players = 3
	players.max_players = 2
	check("manifest: max_players below min_players is rejected", not players.is_valid())
	var huge: LGGameManifest = _probe_manifest()
	huge.board_size = Vector2(10.0, 0.3)
	check("manifest: a non table-sized board is rejected", not huge.is_valid())
	var missing: LGGameManifest = _probe_manifest()
	missing.entry = "res://nowhere/game.tscn"
	check("manifest: a missing entry file is rejected", not missing.is_valid())
	check("manifest: player labels read naturally", (
		good.players_label() == "1 player" and _with_players(1, 4).players_label() == "1-4 players"
		and _with_players(2, 2).players_label() == "2 players"
	))
	var game: LGGame = good.instantiate_game()
	check("manifest: a .gd entry instantiates an LGGame with its manifest", (
		game is ProbeGame and game.manifest == good and game.get_board_size() == Vector2(0.3, 0.2)
	))
	game.free()
	var not_a_game: LGGameManifest = _probe_manifest()
	not_a_game.entry = "res://tests/fake_ar_bridge.gd"
	check("manifest: an entry that is not an LGGame instantiates to null", not_a_game.instantiate_game() == null)


func _with_players(lo: int, hi: int) -> LGGameManifest:
	var manifest: LGGameManifest = _probe_manifest()
	manifest.min_players = lo
	manifest.max_players = hi
	return manifest


func _test_catalog() -> void:
	var catalog := GameCatalog.new()
	var added: int = catalog.scan()
	check("catalog: scanning res://games registers every bundled game", (
		added == 3 and catalog.has_game(&"tic_tac_toe") and catalog.has_game(&"competitive_evolution") and catalog.has_game(&"tattoo_studio")
		and catalog.errors.is_empty()
	))
	var names: Array[String] = []
	for manifest: LGGameManifest in catalog.list():
		names.append(manifest.display_name)
	check("catalog: list() is sorted by display name", names == ["Competitive Evolution", "Tattoo Studio", "Tic-Tac-Toe"])
	check("catalog: bundled manifests carry their metadata", (
		catalog.get_manifest(&"tic_tac_toe").max_players == 2
		and catalog.get_manifest(&"tic_tac_toe").icon != null
		and catalog.get_manifest(&"competitive_evolution").max_players == 4
		and is_equal_approx(catalog.get_manifest(&"competitive_evolution").board_size.x, 0.42)
	))
	check("catalog: duplicate ids are rejected", (
		not catalog.register(catalog.get_manifest(&"tic_tac_toe")) and catalog.errors.size() == 1
	))
	check("catalog: invalid manifests are rejected with a reason", (
		not catalog.register(LGGameManifest.new()) and catalog.errors.size() == 2 and catalog.size() == 3
	))
	check("catalog: a new game registers at runtime (future creator uploads)", (
		catalog.register(_probe_manifest()) and catalog.size() == 4
	))
	var game: LGGame = catalog.instantiate(&"tic_tac_toe")
	check("catalog: instantiate() builds the game from its scene entry", game is TicTacToeGame and game.manifest != null)
	game.free()
	check("catalog: instantiate() of an unknown id is null", catalog.instantiate(&"nope") == null)
	catalog.unregister(&"probe")
	check("catalog: unregister removes a game", not catalog.has_game(&"probe"))
	var autoload: Node = get_node_or_null(^"/root/LookingGlass")
	check("catalog: the LookingGlass autoload scanned the bundled games", (
		autoload != null and (autoload.get("catalog") as GameCatalog).size() == 3
	))


# --- LGGame contract ------------------------------------------------------------

func _test_game_contract() -> void:
	var game := ProbeGame.new()
	game.manifest = _probe_manifest()
	game.lg_board_ready()
	game.lg_board_ready()
	check("contract: _on_board_ready runs once", game.events == ["ready"])
	check("contract: a new game is not playing and ignores taps", (
		not game.is_playing() and not game.lg_tap(Vector3.ZERO) and game.taps.is_empty()
	))
	game.lg_set_locked(true)
	check("contract: locking the board fires locked then resumed", game.events == ["ready", "locked", "resumed"] and game.is_playing())
	check("contract: taps reach the game while playing", game.lg_tap(Vector3(0.1, 0.0, 0.05)) and game.taps.size() == 1)
	check("contract: drags are not delivered unless the game captures them", not game.lg_drag(Vector3.ZERO, Vector3.ONE))
	game.lg_set_app_paused(true)
	check("contract: backgrounding the app pauses without unlocking", (
		game.events.back() == "paused" and not game.is_playing() and game.is_board_locked()
	))
	game.lg_set_locked(false)
	game.lg_set_app_paused(false)
	check("contract: unlocking while paused does not resume", not game.is_playing() and game.events.back() == "unlocked")
	game.lg_set_locked(true)
	check("contract: re-locking in the foreground resumes", game.is_playing() and game.events.back() == "resumed")
	game.lg_set_locked(true)
	check("contract: repeated lock calls are ignored", game.events.count("locked") == 2)
	var exits: Array[int] = []
	game.exit_requested.connect(func() -> void: exits.append(1))
	game.request_exit()
	check("contract: request_exit emits exit_requested", exits.size() == 1)
	game.lg_exit()
	check("contract: lg_exit pauses then calls _on_exit", game.events.slice(-2) == ["paused", "exit"] and not game.is_playing())
	check("contract: is_on_board uses the manifest footprint", (
		game.is_on_board(Vector3(0.14, 0.0, 0.09)) and not game.is_on_board(Vector3(0.16, 0.0, 0.0))
		and not game.is_on_board(Vector3(0.0, 0.0, 0.11))
	))
	game.free()


func _test_tic_tac_toe_rules() -> void:
	var rules := TicTacToeRules.new()
	check("tic-tac-toe: X moves first", rules.turn == TicTacToeRules.Mark.X)
	for index: int in [0, 3, 1, 4]:
		rules.play(index)
	check("tic-tac-toe: occupied cells are illegal", not rules.play(0))
	rules.play(2)
	check("tic-tac-toe: three in a row wins", (
		rules.winner == TicTacToeRules.Mark.X and rules.winning_line == [0, 1, 2] and rules.is_over()
	))
	check("tic-tac-toe: no moves after the game is over", not rules.play(8))
	rules.reset()
	for index: int in [0, 1, 2, 4, 3, 5, 7, 6, 8]:
		rules.play(index)
	check("tic-tac-toe: a full board without a line is a draw", rules.is_draw() and rules.winner == TicTacToeRules.Mark.NONE)
	check("tic-tac-toe: board points map to cells", (
		TicTacToeGame.cell_at(TicTacToeGame.cell_center(0)) == 0
		and TicTacToeGame.cell_at(TicTacToeGame.cell_center(4)) == 4
		and TicTacToeGame.cell_at(TicTacToeGame.cell_center(8)) == 8
		and TicTacToeGame.cell_at(Vector3(0.2, 0.0, 0.0)) == -1
	))


# --- Launcher -------------------------------------------------------------------

func _test_launcher() -> void:
	var launcher: Launcher = (load("res://platform/launcher/launcher.tscn") as PackedScene).instantiate() as Launcher
	var launched: Array[StringName] = []
	launcher.launch_handler = func(id: StringName) -> void: launched.append(id)
	add_child(launcher)
	await frames(2)
	check("launcher: one card per registered game", (
		launcher.cards.size() == 3 and launcher.cards.has(&"tic_tac_toe") and launcher.cards.has(&"competitive_evolution") and launcher.cards.has(&"tattoo_studio")
	))
	var card: Button = launcher.cards[&"tic_tac_toe"] as Button
	card.pressed.emit()
	check("launcher: choosing a card launches that game", launched == [&"tic_tac_toe"])
	launcher.queue_free()
	await frames(1)
	check("launcher: is the project's main scene", (
		ProjectSettings.get_setting("application/run/main_scene") == "res://platform/launcher/launcher.tscn"
	))


# --- Launching onto the board -----------------------------------------------------

func _test_fallback_launch() -> void:
	var host: GameHost = await make_host(&"tic_tac_toe")
	var game: TicTacToeGame = host.game as TicTacToeGame
	check("launch: the selected game is loaded into the board pivot", (
		game != null and game.get_parent() == host.pivot and game.manifest.id == &"tic_tac_toe"
	))
	check("launch: without AR the game plays at once on the touch camera", game.is_playing() and game.is_board_locked())
	check("launch: the game's status line reaches the host HUD", host.get_status_text() == "X to play")
	check("launch: the touch camera frames the board", (
		host.orbit_camera.distance > 0.3 and host.orbit_camera.distance < 1.0
	))
	var exits: Array[int] = []
	host.exited.connect(func() -> void: exits.append(1))
	game.request_exit()
	check("launch: a game's request_exit closes it through the host", exits.size() == 1 and not game.is_playing())
	await free_host(host)


func _test_tap_routing() -> void:
	var host: GameHost = await make_host(&"tic_tac_toe")
	var game: TicTacToeGame = host.game as TicTacToeGame
	var camera: Camera3D = host.active_camera()
	var centre_screen: Vector2 = camera.unproject_position(game.to_global(TicTacToeGame.cell_top(4)))
	var point: Variant = GameHost.screen_to_board(camera, game, centre_screen, game.board_surface_height())
	check("input: a screen point maps to the board point under it", (
		point != null and near(point as Vector3, TicTacToeGame.cell_center(4), 0.002)
	))
	host.route_gesture({"kind": &"tap", "position": centre_screen})
	check("input: a tap on the centre tile places X there", game.rules.cells[4] == TicTacToeRules.Mark.X)
	host.session.placement.scale = 2.0
	host.pivot.transform = host.session.placement.pivot_transform()
	await frames(1)
	var corner_screen: Vector2 = camera.unproject_position(game.to_global(TicTacToeGame.cell_top(0)))
	host.route_gesture({"kind": &"tap", "position": corner_screen})
	check("input: taps stay in board space when the board is resized", game.rules.cells[0] == TicTacToeRules.Mark.O)
	host.pivot.transform = Transform3D.IDENTITY
	await frames(1)
	host.orbit_camera.orbit(Vector2(120.0, 0.0))
	var screen: Vector2 = camera.unproject_position(game.to_global(TicTacToeGame.cell_top(8)))
	host.route_gesture({"kind": &"tap", "position": screen})
	check("input: taps still land after orbiting the camera", game.rules.cells[8] == TicTacToeRules.Mark.X)
	game.lg_set_app_paused(true)
	var screen_2: Vector2 = camera.unproject_position(game.to_global(TicTacToeGame.cell_top(2)))
	host.route_gesture({"kind": &"tap", "position": screen_2})
	check("input: a paused game ignores taps", game.rules.cells[2] == TicTacToeRules.Mark.NONE and host.get_status_text().begins_with("Paused"))
	game.lg_set_app_paused(false)
	host._input(touch(0, screen_2, true))
	host._input(touch(0, screen_2, false))
	check("input: raw touch events become board taps", game.rules.cells[2] == TicTacToeRules.Mark.O)
	await free_host(host)


func _test_drag_routing() -> void:
	var host := GameHost.new()
	host.catalog = _probe_catalog()
	host.game_id = &"probe"
	host.exit_handler = func() -> void: pass
	add_child(host)
	await frames(2)
	var probe: ProbeGame = host.game as ProbeGame
	check("drag: a .gd game loads and plays in the fallback", probe != null and probe.is_playing())
	var yaw_before: float = host.orbit_camera.yaw
	host.route_gesture({"kind": &"drag", "from": Vector2(600, 360), "to": Vector2(700, 360)})
	check("drag: without captures_drag a drag orbits the touch camera", probe.drags.is_empty() and host.orbit_camera.yaw != yaw_before)
	probe.wants_drag = true
	var camera: Camera3D = host.active_camera()
	var a: Vector2 = camera.unproject_position(probe.to_global(Vector3(-0.05, 0.0, 0.0)))
	var b: Vector2 = camera.unproject_position(probe.to_global(Vector3(0.05, 0.0, 0.0)))
	host.route_gesture({"kind": &"drag", "from": a, "to": b})
	check("drag: with captures_drag the game gets the drag in board space", (
		probe.drags.size() == 1 and near((probe.drags[0] as Array)[0] as Vector3, Vector3(-0.05, 0.0, 0.0), 0.002)
		and near((probe.drags[0] as Array)[1] as Vector3, Vector3(0.05, 0.0, 0.0), 0.002)
	))
	await free_host(host)


func _test_ar_launch_lifecycle() -> void:
	var fake := FakeARBridge.new()
	var host := GameHost.new()
	host.catalog = _probe_catalog()
	host.game_id = &"probe"
	host.exit_handler = func() -> void: pass
	host.bridge_factory = func() -> ARCoreBridge: return fake
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://lg_placement_probe.cfg"))
	add_child(host)
	await frames(2)
	var ar: ARSession = host.session
	var probe: ProbeGame = host.game as ProbeGame
	check("ar launch: calibration runs first; the game is ready but not playing", (
		ar.is_ar() and probe.events == ["ready"] and not probe.is_playing()
	))
	check("ar launch: the placement is saved per game", ar.placement_path == "user://lg_placement_probe.cfg")
	var screen_centre: Vector2 = get_viewport().get_visible_rect().size * 0.5
	host.route_gesture({"kind": &"tap", "position": screen_centre})
	check("ar launch: taps never reach the game during calibration", probe.taps.is_empty())
	fake.surface_found = true
	await frames(2)
	host._input(touch(0, screen_centre, true))
	ar._unhandled_input(touch(0, screen_centre, true))
	host._input(touch(0, screen_centre, false))
	ar._unhandled_input(touch(0, screen_centre, false))
	check("ar launch: tapping the screen on a found surface places the board (not a game tap)", (
		ar.is_placed() and probe.taps.is_empty() and not probe.is_playing()
	))
	check("ar launch: the outline matches the game's footprint", (
		host.board_frame.visible and _frame_extent(host.board_frame).is_equal_approx(Vector2(0.3, 0.2))
	))
	ar.set_locked(true)
	check("ar launch: locking loads the game onto the locked board (locked, resumed)", (
		probe.events == ["ready", "locked", "resumed"] and probe.is_playing()
	))
	var game_pose: Transform3D = probe.global_transform
	ar.xr_camera.transform = Transform3D(Basis(Vector3.UP, -0.7), Vector3(-0.3, 0.1, 0.5))
	await frames(3)
	check("ar launch: the locked board does not follow the camera", xform_near(probe.global_transform, game_pose, 0.0001))
	var target: Vector3 = Vector3(0.05, 0.0, -0.04)
	ar.xr_camera.look_at(probe.to_global(target))
	var screen: Vector2 = ar.xr_camera.unproject_position(probe.to_global(target))
	host.route_gesture({"kind": &"tap", "position": screen})
	check("ar launch: once locked, taps reach the game in board space through the AR camera", (
		probe.taps.size() == 1 and near(probe.taps[0], target, 0.002)
	))
	ar.set_locked(false)
	check("ar launch: unlocking to adjust pauses the game", probe.events.slice(-2) == ["unlocked", "paused"] and not probe.is_playing())
	ar.set_locked(true)
	host.exit_game()
	check("ar launch: leaving the game calls _on_exit and hands the AR session back", (
		probe.events.back() == "exit" and not ar.is_ar() and fake.release_count == 1 and not get_viewport().use_xr
	))
	await free_host(host)


func _frame_extent(frame: Node3D) -> Vector2:
	var max_x: float = 0.0
	var max_z: float = 0.0
	for child: Node in frame.get_children():
		var p: Vector3 = (child as Node3D).position
		max_x = maxf(max_x, absf(p.x))
		max_z = maxf(max_z, absf(p.z))
	return Vector2(max_x * 2.0, max_z * 2.0)


func _test_competitive_evolution_stub() -> void:
	var host: GameHost = await make_host(&"competitive_evolution")
	var board: CompetitiveEvolutionBoard = host.game as CompetitiveEvolutionBoard
	check("competitive evolution: the placeholder board loads from the catalog", board != null and board.is_playing())
	var bottom: float = board.globe.position.y - CompetitiveEvolutionBoard.GLOBE_RADIUS
	check("competitive evolution: the globe rests on the board surface at 0.42 m across", (
		is_zero_approx(bottom) and is_equal_approx(CompetitiveEvolutionBoard.GLOBE_RADIUS * 2.0, board.get_board_size().x)
	))
	var spin_before: float = board.globe.rotation.y
	await get_tree().create_timer(0.1).timeout
	var spun: bool = not is_equal_approx(board.globe.rotation.y, spin_before)
	board.lg_set_app_paused(true)
	var paused_at: float = board.globe.rotation.y
	await get_tree().create_timer(0.1).timeout
	check("competitive evolution: the globe spins while playing and stops when paused", (
		spun and is_equal_approx(board.globe.rotation.y, paused_at)
	))
	check("competitive evolution: the host shows the hiatus note", host.get_status_text().contains("hiatus"))
	await free_host(host)


func _test_bad_game_id() -> void:
	var host: GameHost = await make_host(&"does_not_exist")
	check("launch: an unknown game id shows an error instead of crashing", (
		host.game == null and host.session == null and host.get_status_text().contains("not in the catalog")
	))
	await free_host(host)
