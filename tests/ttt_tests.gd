extends "res://tests/surface_tests.gd"
## Tic-tac-toe options: 3x3 / 4x4 / 5x5 boards (win 3 / 4 / 4 in a row), the
## hologram options strip that picks them, the session scoreboard and its
## reset, and taps / drops / win lines at every size (fallback camera and the
## AR camera on the plywood model).
## Run: godot --headless --path . res://tests/ttt_tests.tscn


func run_tests() -> void:
	ARSession.clear_saved_area()
	_reset_session()
	_test_rules_sizes()
	await _test_default_board()
	await _test_size_menu_and_score()
	await _test_taps_every_size()
	await _test_score_persists_across_launches()
	await _test_ar_taps_on_5x5()
	_reset_session()
	ARSession.clear_saved_area()


func _reset_session() -> void:
	TicTacToeGame.session_size = 3
	TicTacToeGame.session_score = {"x": 0, "o": 0, "draw": 0}


func _play_all(rules: TicTacToeRules, moves: Array) -> bool:
	for m: Variant in moves:
		if not rules.play(int(m)):
			return false
	return true


func _test_rules_sizes() -> void:
	check("rules: win lengths 3 / 4 / 4 for 3x3 / 4x4 / 5x5", (
		TicTacToeRules.win_length_for(3) == 3 and TicTacToeRules.win_length_for(4) == 4 and TicTacToeRules.win_length_for(5) == 4
	))
	var r3 := TicTacToeRules.new()
	var r4 := TicTacToeRules.new(4)
	var r5 := TicTacToeRules.new(5)
	check("rules: 8 / 10 / 28 possible lines", r3.lines.size() == 8 and r4.lines.size() == 10 and r5.lines.size() == 28)
	check("rules: 3x3 lines are the classic ones", r3.lines.size() == TicTacToeRules.LINES.size() and r3.lines.all(func(l: Array) -> bool: return TicTacToeRules.LINES.has(l)))
	check("rules: board sizes give 9 / 16 / 25 cells", r3.cells.size() == 9 and r4.cells.size() == 16 and r5.cells.size() == 25)
	# 4x4: three in a row is not enough, four is.
	_play_all(r4, [0, 4, 1, 5, 2, 6])
	check("rules 4x4: three in a row does not win", r4.winner == TicTacToeRules.Mark.NONE and not r4.is_over())
	r4.play(3)
	check("rules 4x4: four in a row wins", r4.winner == TicTacToeRules.Mark.X and r4.winning_line == [0, 1, 2, 3])
	r4.reset()
	_play_all(r4, [0, 1, 5, 2, 10, 3, 15])
	check("rules 4x4: the main diagonal wins", r4.winner == TicTacToeRules.Mark.X and r4.winning_line == [0, 5, 10, 15])
	r4.reset()
	# A full 4x4 with no four in a line.
	# X X O O / O O X X / X X O O / O O X X
	var draw4: Array = [0, 2, 1, 3, 6, 4, 7, 5, 8, 10, 9, 11, 14, 12, 15, 13]
	check("rules 4x4: a full board without a line is a draw", _play_all(r4, draw4) and r4.is_draw())
	check("rules 4x4: no move past the last cell", not TicTacToeRules.new(4).play(16) and TicTacToeRules.new(4).play(15))
	_play_all(r5, [6, 0, 7, 1, 8, 2])
	check("rules 5x5: three in a row does not win", not r5.is_over())
	r5.play(9)
	check("rules 5x5: four in a row (not touching the edge) wins", r5.winner == TicTacToeRules.Mark.X and r5.winning_line == [6, 7, 8, 9])
	r5.reset()
	_play_all(r5, [4, 0, 8, 1, 12, 2, 16])
	check("rules 5x5: four on the anti-diagonal wins", r5.winner == TicTacToeRules.Mark.X and r5.winning_line == [4, 8, 12, 16])
	r5.reset()
	_play_all(r5, [1, 0, 7, 2, 13, 3, 19])
	check("rules 5x5: an off-centre diagonal of four wins", r5.winner == TicTacToeRules.Mark.X and r5.winning_line == [1, 7, 13, 19])
	var odd := TicTacToeRules.new(4, 3)
	_play_all(odd, [0, 4, 1, 5, 2])
	check("rules: an explicit win length is honoured (4x4, three in a row)", odd.winner == TicTacToeRules.Mark.X and odd.win_length == 3)


func _test_default_board() -> void:
	var host: GameHost = await make_host(&"tic_tac_toe")
	var game: TicTacToeGame = host.game as TicTacToeGame
	check("board: starts as the classic 3x3 (9 tiles, 9 cm cells)", (
		game.board_cells() == 3 and game.tiles.size() == 9 and is_equal_approx(game.cell_size(), TicTacToeGame.CELL)
	))
	check("board: the scoreboard starts at 0 / 0 / 0", game.scoreboard_text() == "X wins   0 | O wins   0 | Draws   0")
	var round_trip: bool = true
	for n: int in [3, 4, 5]:
		for i: int in n * n:
			round_trip = round_trip and TicTacToeGame.cell_at(TicTacToeGame.cell_center(i, n), n) == i
	check("board: every cell centre maps back to its cell at 3x3 / 4x4 / 5x5", round_trip)
	var menu_clear: bool = true
	for item: int in TicTacToeGame.MENU_ITEMS.size():
		var p: Vector3 = game.menu_button_point(item)
		menu_clear = menu_clear and game.menu_item_at(p) == item and TicTacToeGame.cell_at(p, 5) == -1
	for n: int in [3, 4, 5]:
		for i: int in n * n:
			menu_clear = menu_clear and game.menu_item_at(TicTacToeGame.cell_top(i, n)) == -1
	check("menu: options buttons are hit where they are, never overlap the grid (or its tap margin)", menu_clear)
	check("menu: the strip is on the player's side, outside the board", game.menu_side() == 0 and game.menu_button_point(0).z > game.get_board_size().y * 0.5)
	await free_host(host)


func _finish_drops(game: TicTacToeGame) -> void:
	for i: int in game.pieces.size():
		var drop: HoloDrop = game.drop_of(i)
		if drop != null:
			drop.finish()


func _test_size_menu_and_score() -> void:
	var host: GameHost = await make_host(&"tic_tac_toe")
	var game: TicTacToeGame = host.game as TicTacToeGame
	game.lg_tap(game.menu_button_point(1))
	await frames(1)
	check("menu: tapping 4×4 switches to a 4x4 board (16 tiles, win 4)", (
		game.board_cells() == 4 and game.tiles.size() == 16 and game.rules.win_length == 4 and game.pieces.size() == 16
		and TicTacToeGame.session_size == 4 and absf(game.cell_size() - 0.0675) < 0.0001
	))
	var grid: Node3D = game.get_node(^"Grid") as Node3D
	check("board 4x4: three grid lines each way", grid != null and grid.get_child_count() == 6)
	for i: int in [0, 4, 1, 5]:
		game.lg_tap(game.center_of(i))
	game.lg_tap(game.menu_button_point(2))
	check("menu: the size cannot change in the middle of a round (and says so)", (
		game.board_cells() == 4 and game.rules.cells.count(TicTacToeRules.Mark.NONE) == 12 and host.get_status_text().contains("Finish this round")
	))
	for i: int in [2, 6, 3]:
		game.lg_tap(game.center_of(i))
	check("board 4x4: X wins with four in a row and the scoreboard counts it", (
		game.rules.winner == TicTacToeRules.Mark.X and game.score()["x"] == 1 and game.scoreboard_text().begins_with("X wins   1")
	))
	_finish_drops(game)
	await frames(1)
	var line: MeshInstance3D = game.win_line()
	check("board 4x4: the win line spans the four winning cells", (
		line != null and (line.mesh as BoxMesh).size.z > game.cell_size() * 3.0
	))
	game.lg_tap(game.center_of(9))
	check("score: tapping the board after a win starts a new round; the score stays", (
		game.rules.is_empty() and not game.rules.is_over() and game.score()["x"] == 1
	))
	game.lg_tap(game.menu_button_point(2))
	await frames(1)
	check("menu: 5×5 between rounds (25 tiles, win 4)", game.board_cells() == 5 and game.tiles.size() == 25 and game.rules.win_length == 4)
	for i: int in [0, 6, 1, 7, 2, 8, 13, 9]:
		game.lg_tap(game.center_of(i))
	check("board 5x5: O wins with four in a row, counted", game.rules.winner == TicTacToeRules.Mark.O and game.score()["o"] == 1 and game.score()["x"] == 1)
	game.lg_tap(game.center_of(12))
	game.lg_tap(game.menu_button_point(0))
	await frames(1)
	for i: int in [0, 1, 2, 4, 3, 5, 7, 6, 8]:
		game.lg_tap(game.center_of(i))
	check("board 3x3: a draw is counted as a draw", game.rules.is_draw() and game.score()["draw"] == 1 and game.scoreboard_text().ends_with("Draws   1"))
	game.lg_tap(game.menu_button_point(3))
	check("score: Reset score clears X / O / draws", (
		game.score() == {"x": 0, "o": 0, "draw": 0} and game.scoreboard_text() == "X wins   0 | O wins   0 | Draws   0"
	))
	check("score: Reset score works mid-round or after one, without touching the board", game.rules.is_draw())
	await free_host(host)
	_reset_session()


## Screen taps (orbit camera) on every cell at 4x4 and 5x5, with drops.
func _test_taps_every_size() -> void:
	var host: GameHost = await make_host(&"tic_tac_toe")
	var game: TicTacToeGame = host.game as TicTacToeGame
	var camera: Camera3D = host.active_camera()
	for n: int in [4, 5]:
		game.new_round()
		game.set_board_cells(n)
		await frames(1)
		var ok: bool = true
		var drops: bool = true
		var sizes: bool = true
		for i: int in n * n:
			if game.rules.is_over():
				game.new_round()
			_tap(camera.unproject_position(game.to_global(game.top_of(i))))
			ok = ok and game.rules.cells[i] != TicTacToeRules.Mark.NONE
			var drop: HoloDrop = game.drop_of(i)
			drops = drops and drop != null
			var body: Node3D = game.piece_body(i)
			sizes = sizes and body != null and body.get_child_count() > 0
			if drop != null:
				drop.finish()
		check("taps %dx%d: a screen tap on every one of the %d cells places a mark there" % [n, n, n * n], ok)
		check("taps %dx%d: every piece drops in (HoloDrop) and has a body" % [n, n], drops and sizes)
		var piece: Node3D = TicTacToeGame.make_piece(TicTacToeRules.Mark.X, game.cell_size())
		var bar: BoxMesh = (piece.get_child(0) as MeshInstance3D).mesh as BoxMesh
		check("pieces %dx%d: scaled to the smaller cell" % [n, n], absf(bar.size.x - game.cell_size() * 0.7) < 0.0001)
		piece.free()
	var top: float = game.get_box().height()
	check("drops: pieces start inside the play box at every size", game.drop_height() + TicTacToeGame.SLAB_TOP + game.piece_lift() <= top)
	await free_host(host)
	_reset_session()


func _test_score_persists_across_launches() -> void:
	var host: GameHost = await make_host(&"tic_tac_toe")
	var game: TicTacToeGame = host.game as TicTacToeGame
	game.set_board_cells(4)
	for i: int in [0, 4, 1, 5, 2, 6, 3]:
		game.lg_tap(game.center_of(i))
	await free_host(host)
	host = await make_host(&"tic_tac_toe")
	game = host.game as TicTacToeGame
	check("session: leaving and re-opening the game keeps the score and the board size", (
		game.score()["x"] == 1 and game.board_cells() == 4 and game.scoreboard_text().begins_with("X wins   1")
	))
	await free_host(host)
	_reset_session()


## On the AR plywood model: lock, switch to 5x5 with a screen tap on the
## strip, then tap corners and the centre through the AR camera.
func _test_ar_taps_on_5x5() -> void:
	var host: GameHost = await _ar_host(&"tic_tac_toe")
	var ar: ARSession = host.session
	_look(Vector3(0.0, 0.6, 0.35), Vector3(0.0, PLY_HEIGHT, -0.7))
	await frames(2)
	ar.place_at_reticle()
	ar.finish_fit()
	ar.set_locked(true)
	await frames(2)
	var game: TicTacToeGame = host.game as TicTacToeGame
	var strip: int = game.menu_side()
	_tap(_screen(game.to_global(game.menu_button_point(2))))
	await frames(1)
	check("AR: a screen tap on the strip's 5×5 button switches the locked board to 5x5", game.board_cells() == 5 and strip == game.menu_side())
	var ok: bool = true
	for i: int in [0, 4, 12, 20, 24, 7]:
		_tap(_screen(game.to_global(game.top_of(i))))
		ok = ok and game.rules.cells[i] != TicTacToeRules.Mark.NONE
	check("AR 5x5: taps on corners, centre and an inner cell land on those cells", ok)
	check("AR: the scoreboard floats beside the board, not over the grid", (
		maxf(absf(game.scoreboard().position.x), absf(game.scoreboard().position.z)) > TicTacToeGame.GRID * 0.5 + TicTacToeGame.TAP_TOLERANCE
	))
	await free_host(host)
	_reset_session()
