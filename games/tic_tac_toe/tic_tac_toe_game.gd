class_name TicTacToeGame
extends LGGame
## Sample Looking Glass game: two-player hot-seat tic-tac-toe on a 30 cm
## hologram board. Shows the whole contract in a few lines: build in
## _on_board_ready, take taps in board space, only accept moves while
## playing, and use the platform's hologram kit (Holo, HoloDrop) for the look:
## a glowing slab floating over a projector glow, 3D X and O pieces that drop
## in with a bounce and a flash, and a glowing line through a win.
##
## Board sizes 3x3 / 4x4 / 5x5 (win 3 / 4 / 4 in a row, see
## TicTacToeRules.win_length_for) are picked on a hologram options strip at
## the player's edge of the board, between rounds; the grid always fills
## the same 27 cm, so the cells (and pieces, ripples, drops) shrink with the
## size and the board footprint / play box stay the same. A hologram
## scoreboard (X wins / O wins / draws) floats at the far edge; the score
## lasts for the app session (across rounds, sizes and re-launches of the
## game) until "Reset score" on the strip is tapped.

## Width of the whole grid (m, board space); a cell is GRID / size.
const GRID: float = 0.27
## Cell size of the classic 3x3 board.
const CELL: float = 0.09
## The slab floats over the table: its underside and its top (the surface
## players tap, see board_surface_height()).
const SLAB_BOTTOM: float = 0.014
const SLAB_TOP: float = 0.026
## Piece centre above the slab top.
const PIECE_LIFT: float = 0.013
## Pieces drop in from the TOP of the play box (its current height, less
## DROP_TOP_MARGIN), so a taller airspace means a longer fall; the fall is
## gravity-timed and capped (HoloDrop.MAX_FALL_TIME). On landing a dust
## splash (HoloSplash) in the piece's colour puffs across the slab.
## Room kept between a falling piece's start and the box top.
const DROP_TOP_MARGIN: float = 0.03
## Shortest drop (a box barely taller than the slab).
const MIN_DROP: float = 0.02
## Splash reach as a fraction of the cell size.
const SPLASH_REACH: float = 0.75
## Box outline brightness while playing (see LGGame.box_outline_while_playing).
const OUTLINE_WHILE_PLAYING: float = 0.35
## Taps this far past the grid's edge (metres) still pick the edge cell, so
## a slightly-off fingertip on a phone still counts.
const TAP_TOLERANCE: float = 0.03
## The turn token floats just outside the board edge, on the far side.
const TOKEN_GAP: float = 0.035
const TOKEN_HEIGHT: float = 0.05
const TOKEN_SCALE: float = 0.38
## Options strip: centred this far past the grid edge on the player's side.
const MENU_GAP: float = 0.055
const MENU_BUTTON: Vector2 = Vector2(0.06, 0.036)
const MENU_SPACING: float = 0.068
## Scoreboard: at the far edge, beside the turn token.
const SCORE_SIDE: float = 0.12
const SCORE_HEIGHT: float = 0.012

## Options strip buttons: board sizes, then reset.
const MENU_ITEMS: Array[String] = ["3", "4", "5", "reset"]

## The score and chosen size for this app session (kept across rounds and
## across leaving / re-entering the game).
static var session_score: Dictionary = {"x": 0, "o": 0, "draw": 0}
static var session_size: int = 3

var rules: TicTacToeRules = TicTacToeRules.new(session_size)
var tiles: Array[MeshInstance3D] = []
## Placed pieces by cell (null = empty).
var pieces: Array[Node3D] = []
var _marks: Node3D
var _token: Node3D
var _token_piece: Node3D
var _token_mark: int = -1
var _label: Label3D
var _win_line: MeshInstance3D
var _clock: float = 0.0
var _grid: Node3D
var _tiles_root: Node3D
var _menu: Node3D
var _menu_buttons: Array[MeshInstance3D] = []
var _menu_labels: Array[Label3D] = []
## Which board side (0 +z, 1 +x, 2 -z, 3 -x) the strip is on.
var _menu_side: int = 0
var _scoreboard: Node3D
var _score_labels: Dictionary = {}
var _round_scored: bool = false
var _hint: String = ""
var _hint_seconds: float = 0.0


func board_surface_height() -> float:
	return SLAB_TOP


func describe_point(point: Vector3) -> String:
	var item: int = menu_item_at(point)
	if item >= 0:
		return "menu %s" % MENU_ITEMS[item]
	var index: int = index_at(point)
	return "cell %d" % index if index >= 0 else "off-grid"


## Board size (cells per side) of the current round.
func board_cells() -> int:
	return rules.size


## Cell size (m, board space) of the current board.
func cell_size() -> float:
	return GRID / float(rules.size)


func box_outline_while_playing() -> float:
	return OUTLINE_WHILE_PLAYING


## How far pieces fall: from just under the box top to their rest height.
func drop_height() -> float:
	var rest: float = SLAB_TOP + piece_lift()
	return maxf(get_box().height() - rest - DROP_TOP_MARGIN, MIN_DROP)


## Colour of a mark (X cyan, O magenta): pieces, ripples, splashes.
static func mark_color(mark: int) -> Color:
	return Holo.CYAN if mark == TicTacToeRules.Mark.X else Holo.MAGENTA


func _on_board_ready() -> void:
	var size: Vector2 = get_board_size()
	add_child(Holo.glow_base(size))
	_build_slab(size)
	_tiles_root = Node3D.new()
	_tiles_root.name = "Tiles"
	add_child(_tiles_root)
	_marks = Node3D.new()
	_marks.name = "Marks"
	add_child(_marks)
	_build_cells()
	_build_token()
	_place_token(Vector3(0.0, 0.0, 1.0))
	_build_scoreboard()
	_build_menu()
	_place_menu(Vector3(0.0, 0.0, 1.0))
	_refresh_status()


## Tiles and grid lines for the current size.
func _build_cells() -> void:
	for tile: MeshInstance3D in tiles:
		tile.free()
	tiles.clear()
	var n: int = rules.size
	var cell: float = cell_size()
	var inset: float = cell * 0.13
	for index: int in n * n:
		var tile := MeshInstance3D.new()
		tile.name = "Tile%d" % index
		var mesh := BoxMesh.new()
		mesh.size = Vector3(cell - inset, 0.0015, cell - inset)
		tile.mesh = mesh
		tile.material_override = Holo.material(Holo.CYAN, 0.04, 0.0, 1.0)
		tile.position = cell_center(index, n) + Vector3(0.0, SLAB_TOP + 0.0008, 0.0)
		_tiles_root.add_child(tile)
		tiles.append(tile)
	pieces.clear()
	pieces.resize(n * n)
	if _grid != null:
		_grid.free()
	_grid = Node3D.new()
	_grid.name = "Grid"
	add_child(_grid)
	var line := Holo.line_material(Holo.CYAN, 1.5)
	var reach: float = GRID * 0.5 - 0.006
	var y: float = SLAB_TOP + 0.0016
	var thickness: float = 0.0035 if n == 3 else 0.003
	for k: int in range(1, n):
		var at: float = -GRID * 0.5 + float(k) * cell
		_grid.add_child(Holo.bar(Vector3(at, y, -reach), Vector3(at, y, reach), thickness, line))
		_grid.add_child(Holo.bar(Vector3(-reach, y, at), Vector3(reach, y, at), thickness, line))


func _build_slab(size: Vector2) -> void:
	var slab := MeshInstance3D.new()
	slab.name = "Slab"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, SLAB_TOP - SLAB_BOTTOM, size.y)
	slab.mesh = mesh
	slab.material_override = Holo.material(Holo.CYAN, 0.07, 0.75, 1.0)
	slab.position.y = (SLAB_TOP + SLAB_BOTTOM) * 0.5
	add_child(slab)
	var frame := Node3D.new()
	frame.name = "Frame"
	add_child(frame)
	var edge := Holo.line_material(Holo.CYAN, 1.2)
	var pillar := Holo.line_material(Holo.CYAN, 0.6)
	var hx: float = size.x * 0.5
	var hz: float = size.y * 0.5
	var corners: Array[Vector3] = [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	for i: int in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		frame.add_child(Holo.bar(a + Vector3(0, SLAB_TOP, 0), b + Vector3(0, SLAB_TOP, 0), 0.004, edge))
		# Projector "pillars" from the glow up to the floating slab.
		frame.add_child(Holo.bar(a + Vector3(0, 0.001, 0), a + Vector3(0, SLAB_BOTTOM, 0), 0.003, pillar))


func _build_token() -> void:
	_token = Node3D.new()
	_token.name = "TurnToken"
	add_child(_token)
	_label = Label3D.new()
	_label.name = "Banner"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.00042
	_label.font_size = 34
	_label.outline_size = 6
	_label.outline_modulate = Color(0.0, 0.05, 0.1, 0.8)
	_label.position.y = 0.034
	_label.shaded = false
	_token.add_child(_label)


func _on_paused() -> void:
	_refresh_status()


func _on_resumed() -> void:
	_refresh_status()


func _on_board_tap(point: Vector3) -> void:
	var item: int = menu_item_at(point)
	if item >= 0:
		press_menu(item)
		return
	if rules.is_over():
		new_round()
		return
	var index: int = index_at(point)
	if index >= 0 and rules.play(index):
		var drop: HoloDrop = _add_mark(index, rules.cells[index])
		if rules.winner != TicTacToeRules.Mark.NONE:
			# Light the win when the winning piece lands.
			drop.landed.connect(_show_win, CONNECT_ONE_SHOT)
		_score_round()
	_refresh_status()


func new_round() -> void:
	rules.reset()
	_round_scored = false
	for child: Node in _marks.get_children():
		child.queue_free()
	pieces.clear()
	pieces.resize(rules.cell_count())
	for tile: MeshInstance3D in tiles:
		tile.material_override = Holo.material(Holo.CYAN, 0.04, 0.0, 1.0)
	if _win_line != null:
		_win_line.queue_free()
		_win_line = null
	_refresh_status()


## Switch to a 3x3 / 4x4 / 5x5 board (starts a new round). Only between
## rounds: refused (false) while a round is under way.
func set_board_cells(n: int) -> bool:
	if n not in TicTacToeRules.SIZES:
		return false
	if not rules.is_empty() and not rules.is_over():
		_flash_hint("Finish this round first (or tap the board when it ends) to change the size.")
		return false
	session_size = n
	if n != rules.size:
		for child: Node in _marks.get_children():
			child.free()
		if _win_line != null:
			_win_line.free()
			_win_line = null
		rules.configure(n)
		_round_scored = false
		_build_cells()
	else:
		new_round()
	_refresh_menu()
	_refresh_status()
	return true


func reset_score() -> void:
	session_score = {"x": 0, "o": 0, "draw": 0}
	_refresh_scoreboard()
	_flash_hint("Score reset.")
	_refresh_status()


func score() -> Dictionary:
	return session_score.duplicate()


func press_menu(item: int) -> void:
	if item < 0 or item >= MENU_ITEMS.size():
		return
	if MENU_ITEMS[item] == "reset":
		reset_score()
	else:
		set_board_cells(int(MENU_ITEMS[item]))


## Count a finished round once (on the move that ends it).
func _score_round() -> void:
	if _round_scored or not rules.is_over():
		return
	_round_scored = true
	var key: String = "draw"
	if rules.winner == TicTacToeRules.Mark.X:
		key = "x"
	elif rules.winner == TicTacToeRules.Mark.O:
		key = "o"
	var next: Dictionary = session_score.duplicate()
	next[key] = int(next.get(key, 0)) + 1
	session_score = next
	_refresh_scoreboard()


func _flash_hint(text: String) -> void:
	_hint = text
	_hint_seconds = 2.5
	_refresh_status()


## Board-space centre of a cell on the board plane (index 0 = back-left,
## row-major) on an n x n board.
static func cell_center(index: int, n: int = 3) -> Vector3:
	var cell: float = GRID / float(n)
	var col: int = index % n
	@warning_ignore("integer_division")
	var row: int = index / n
	var first: float = -GRID * 0.5 + cell * 0.5
	return Vector3(first + col * cell, 0.0, first + row * cell)


## Centre of a cell on the slab top, where the player sees (and taps) it.
static func cell_top(index: int, n: int = 3) -> Vector3:
	return cell_center(index, n) + Vector3(0.0, SLAB_TOP, 0.0)


## Cell under a board-space point on an n x n board (edge cells extend
## TAP_TOLERANCE past the grid), or -1 off the grid.
static func cell_at(point: Vector3, n: int = 3) -> int:
	var half: float = GRID * 0.5
	if absf(point.x) >= half + TAP_TOLERANCE or absf(point.z) >= half + TAP_TOLERANCE:
		return -1
	var cell: float = GRID / float(n)
	var col: int = clampi(floori((point.x + half) / cell), 0, n - 1)
	var row: int = clampi(floori((point.z + half) / cell), 0, n - 1)
	return row * n + col


## The same, for the current board size.
func center_of(index: int) -> Vector3:
	return cell_center(index, rules.size)


func top_of(index: int) -> Vector3:
	return cell_top(index, rules.size)


func index_at(point: Vector3) -> int:
	return cell_at(point, rules.size)


## A hologram X (two crossed bars) or O (a torus) sized for a `cell`-wide
## tile, centred on its origin.
static func make_piece(mark: int, cell: float = CELL) -> Node3D:
	var body := Node3D.new()
	body.name = "Body"
	var k: float = cell / CELL
	if mark == TicTacToeRules.Mark.X:
		var mat := Holo.material(Holo.CYAN, 0.32, 1.3, 1.25)
		for angle: float in [PI * 0.25, -PI * 0.25]:
			var bar := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(cell * 0.7, 0.018 * k, 0.018 * k)
			bar.mesh = mesh
			bar.material_override = mat
			bar.rotation.y = angle
			body.add_child(bar)
	else:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = cell * 0.19
		torus.outer_radius = cell * 0.31
		torus.rings = 28
		torus.ring_segments = 10
		ring.mesh = torus
		ring.material_override = Holo.material(Holo.MAGENTA, 0.3, 1.3, 1.25)
		body.add_child(ring)
	return body


func _add_mark(index: int, mark: int) -> HoloDrop:
	var root := Node3D.new()
	root.name = "Mark%d" % index
	root.position = top_of(index) + Vector3(0.0, piece_lift(), 0.0)
	var bob := Node3D.new()
	bob.name = "Bob"
	root.add_child(bob)
	var body: Node3D = make_piece(mark, cell_size())
	bob.add_child(body)
	_marks.add_child(root)
	pieces[index] = root
	var ripple: MeshInstance3D = Holo.ripple(mark_color(mark), cell_size() * 0.75)
	ripple.position = top_of(index) + Vector3(0.0, 0.002, 0.0)
	_marks.add_child(ripple)
	var drop: HoloDrop = HoloDrop.start(body, drop_height(), ripple)
	var at: Vector3 = top_of(index) + Vector3(0.0, 0.004, 0.0)
	var color: Color = mark_color(mark)
	drop.landed.connect(func() -> void: splash_at(index, at, color), CONNECT_ONE_SHOT)
	return drop


## The landing dust cloud for the piece in `index` (its colour).
func splash_at(index: int, at: Vector3, color: Color) -> HoloSplash:
	if _marks == null or not is_instance_valid(_marks):
		return null
	var splash: HoloSplash = HoloSplash.spawn(_marks, at, color, cell_size() * SPLASH_REACH)
	splash.name = "Splash%d" % index
	return splash


## The splash of the piece in `index` while it lasts, or null.
func splash_of(index: int) -> HoloSplash:
	return null if _marks == null else _marks.get_node_or_null(NodePath("Splash%d" % index)) as HoloSplash


## Piece centre above the slab top (thinner pieces on smaller cells sit lower).
func piece_lift() -> float:
	return PIECE_LIFT * clampf(cell_size() / CELL, 0.6, 1.0)


## The drop animation of the piece in `index`, or null once it has landed.
func drop_of(index: int) -> HoloDrop:
	var body: Node3D = piece_body(index)
	return null if body == null else body.get_node_or_null(^"HoloDrop") as HoloDrop


## The visible piece body of `index` (null if empty).
func piece_body(index: int) -> Node3D:
	var root: Node3D = pieces[index] if index >= 0 and index < pieces.size() else null
	return null if root == null else root.get_node_or_null(^"Bob/Body") as Node3D


func _show_win() -> void:
	if rules.winner == TicTacToeRules.Mark.NONE or _win_line != null:
		return
	for cell: Variant in rules.winning_line:
		tiles[int(cell)].material_override = Holo.material(Holo.GOLD, 0.35, 0.6, 1.2)
	var a: Vector3 = top_of(int(rules.winning_line[0]))
	var b: Vector3 = top_of(int(rules.winning_line[rules.winning_line.size() - 1]))
	var dir: Vector3 = (b - a).normalized()
	var lift := Vector3(0.0, piece_lift() + 0.012, 0.0)
	var cell: float = cell_size()
	_win_line = Holo.bar(a - dir * cell * 0.4 + lift, b + dir * cell * 0.4 + lift, 0.009 if rules.size == 3 else 0.007, Holo.line_material(Holo.GOLD, 1.6))
	_win_line.name = "WinLine"
	add_child(_win_line)


func win_line() -> MeshInstance3D:
	return _win_line


func _refresh_status() -> void:
	var text: String
	var token_mark: int = rules.turn
	if rules.winner != TicTacToeRules.Mark.NONE:
		text = "%s wins! Tap the board for a new round." % TicTacToeRules.mark_name(rules.winner)
		token_mark = rules.winner
	elif rules.is_draw():
		text = "Draw. Tap the board for a new round."
	else:
		text = "%s to play" % TicTacToeRules.mark_name(rules.turn)
	if not _hint.is_empty():
		text = _hint
	set_status(text)
	if _label == null:
		return
	if rules.winner != TicTacToeRules.Mark.NONE:
		_label.text = "%s wins!" % TicTacToeRules.mark_name(rules.winner)
	elif rules.is_draw():
		_label.text = "Draw"
	else:
		_label.text = "%s's turn" % TicTacToeRules.mark_name(rules.turn)
	_label.modulate = Holo.CYAN if token_mark == TicTacToeRules.Mark.X else Holo.MAGENTA
	if rules.is_draw():
		_label.modulate = Holo.GOLD
	if token_mark != _token_mark:
		_token_mark = token_mark
		if _token_piece != null:
			_token_piece.queue_free()
		_token_piece = make_piece(token_mark)
		_token_piece.scale = Vector3.ONE * TOKEN_SCALE
		_token.add_child(_token_piece)


func _process(delta: float) -> void:
	_clock += delta
	if _hint_seconds > 0.0:
		_hint_seconds -= delta
		if _hint_seconds <= 0.0:
			_hint = ""
			_refresh_status()
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null and _token != null:
		var viewer: Vector3 = to_local(camera.global_position)
		_place_token(viewer)
		_place_menu(viewer)
		_face_scoreboard(viewer)
	if _token_piece != null:
		_token_piece.rotation.y = _clock * 1.4
		_token_piece.position.y = 0.004 * sin(_clock * 2.4)
	for i: int in pieces.size():
		var root: Node3D = pieces[i]
		if root != null:
			(root.get_child(0) as Node3D).position.y = 0.0015 * sin(_clock * 2.0 + float(i))
	if _win_line != null:
		(_win_line.material_override as ShaderMaterial).set_shader_parameter("intensity", 1.3 + 0.5 * sin(_clock * 6.0))


## Keep the turn token just outside the board edge on the far side from the
## viewer, so it never covers a cell.
func _place_token(viewer_local: Vector3) -> void:
	var toward := Vector2(viewer_local.x, viewer_local.z)
	if toward.length() < 0.001:
		toward = Vector2(0.0, 1.0)
	toward = toward.normalized()
	var half: float = maxf(get_board_size().x, get_board_size().y) * 0.5 + TOKEN_GAP
	# Onto the square around the board (its edge, not a circle's diagonal).
	var edge: Vector2 = -toward * half / maxf(absf(toward.x), absf(toward.y))
	_token.position = Vector3(edge.x, SLAB_TOP + TOKEN_HEIGHT * 0.5, edge.y)


func label_position() -> Vector3:
	return _token.position


# --- Scoreboard ---------------------------------------------------------------------

## A small hologram panel at the far edge: "SCORE", X wins, O wins, draws.
func _build_scoreboard() -> void:
	_scoreboard = Node3D.new()
	_scoreboard.name = "Scoreboard"
	add_child(_scoreboard)
	var panel := MeshInstance3D.new()
	panel.name = "Panel"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.115, 0.09)
	panel.mesh = quad
	panel.material_override = Holo.material(Holo.CYAN, 0.06, 0.9, 0.8)
	panel.position = Vector3(0.0, 0.045, -0.002)
	_scoreboard.add_child(panel)
	var rows: Array = [["title", "SCORE", Holo.CYAN, 0.077], ["x", "", Holo.CYAN, 0.056], ["o", "", Holo.MAGENTA, 0.035], ["draw", "", Holo.GOLD, 0.014]]
	for row: Array in rows:
		var label := Label3D.new()
		label.name = "Score_%s" % row[0]
		label.pixel_size = 0.0005 if row[0] != "title" else 0.0004
		label.font_size = 36
		label.outline_size = 6
		label.outline_modulate = Color(0.0, 0.05, 0.1, 0.8)
		label.modulate = row[2]
		label.shaded = false
		label.text = row[1]
		label.position = Vector3(0.0, float(row[3]), 0.0)
		_scoreboard.add_child(label)
		_score_labels[row[0]] = label
	_refresh_scoreboard()


func _refresh_scoreboard() -> void:
	if _score_labels.is_empty():
		return
	(_score_labels["x"] as Label3D).text = "X wins   %d" % int(session_score.get("x", 0))
	(_score_labels["o"] as Label3D).text = "O wins   %d" % int(session_score.get("o", 0))
	(_score_labels["draw"] as Label3D).text = "Draws   %d" % int(session_score.get("draw", 0))


## Text of the scoreboard rows (for tests / the debug readout).
func scoreboard_text() -> String:
	if _score_labels.is_empty():
		return ""
	return "%s | %s | %s" % [(_score_labels["x"] as Label3D).text, (_score_labels["o"] as Label3D).text, (_score_labels["draw"] as Label3D).text]


func scoreboard() -> Node3D:
	return _scoreboard


## At the far edge (beside the turn token), turned to face the viewer.
func _face_scoreboard(viewer_local: Vector3) -> void:
	if _scoreboard == null:
		return
	var toward := Vector2(viewer_local.x, viewer_local.z)
	if toward.length() < 0.001:
		toward = Vector2(0.0, 1.0)
	toward = toward.normalized()
	var half: float = maxf(get_board_size().x, get_board_size().y) * 0.5 + TOKEN_GAP
	var edge: Vector2 = -toward * half / maxf(absf(toward.x), absf(toward.y))
	# Beside the token, to the viewer's left along the far edge.
	var side: Vector2 = Vector2(-toward.y, toward.x)
	var at: Vector2 = edge + side * SCORE_SIDE
	_scoreboard.position = Vector3(at.x, SLAB_TOP + SCORE_HEIGHT, at.y)
	var face := Vector3(viewer_local.x - at.x, 0.0, viewer_local.z - at.y)
	if face.length() > 0.001:
		_scoreboard.basis = Basis.looking_at(-face.normalized(), Vector3.UP)


# --- Options strip -----------------------------------------------------------------

## Four flat hologram buttons on the table at the player's edge of the
## board: 3x3, 4x4, 5x5, Reset score.
func _build_menu() -> void:
	_menu = Node3D.new()
	_menu.name = "Options"
	add_child(_menu)
	_menu_buttons.clear()
	_menu_labels.clear()
	for i: int in MENU_ITEMS.size():
		var button := MeshInstance3D.new()
		button.name = "Option_%s" % MENU_ITEMS[i]
		var mesh := BoxMesh.new()
		mesh.size = Vector3(MENU_BUTTON.x, 0.003, MENU_BUTTON.y)
		button.mesh = mesh
		button.position = Vector3(_menu_x(i), SLAB_TOP - 0.0015, 0.0)
		_menu.add_child(button)
		_menu_buttons.append(button)
		var label := Label3D.new()
		label.name = "Label"
		label.text = "Reset\nscore" if MENU_ITEMS[i] == "reset" else "%s×%s" % [MENU_ITEMS[i], MENU_ITEMS[i]]
		label.pixel_size = 0.0003 if MENU_ITEMS[i] == "reset" else 0.00042
		label.font_size = 36
		label.outline_size = 5
		label.outline_modulate = Color(0.0, 0.05, 0.1, 0.8)
		label.shaded = false
		# Lying on the button, upright for the player on this side.
		label.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		label.position = Vector3(0.0, 0.003, 0.0)
		button.add_child(label)
		_menu_labels.append(label)
	_refresh_menu()


static func _menu_x(i: int) -> float:
	return (float(i) - float(MENU_ITEMS.size() - 1) * 0.5) * MENU_SPACING


func _refresh_menu() -> void:
	var can_resize: bool = rules.is_empty() or rules.is_over()
	for i: int in _menu_buttons.size():
		var item: String = MENU_ITEMS[i]
		var color: Color = Holo.CYAN
		var fill: float = 0.08
		if item == "reset":
			color = Holo.MAGENTA
		elif int(item) == rules.size:
			color = Holo.GOLD
			fill = 0.3
		var intensity: float = 1.0 if (item == "reset" or can_resize or int(item) == rules.size) else 0.45
		_menu_buttons[i].material_override = Holo.material(color, fill, 1.0, intensity)
		_menu_labels[i].modulate = Color(color, 1.0 if intensity > 0.5 else 0.5)


## Strip side: the board edge facing the viewer (sticky, so it does not
## flip around while the player moves a little).
func _place_menu(viewer_local: Vector3) -> void:
	if _menu == null:
		return
	var toward := Vector2(viewer_local.x, viewer_local.z)
	if toward.length() > 0.001:
		var side: int = _side_of(toward)
		if side != _menu_side:
			var current: Vector2 = _side_dir(_menu_side)
			if toward.normalized().dot(current) < 0.6:
				_menu_side = side
	var dir: Vector2 = _side_dir(_menu_side)
	var reach: float = menu_distance()
	_menu.position = Vector3(dir.x * reach, 0.0, dir.y * reach)
	_menu.rotation = Vector3(0.0, atan2(dir.x, dir.y), 0.0)
	_refresh_menu_state()


var _menu_can_resize: bool = true


func _refresh_menu_state() -> void:
	var can_resize: bool = rules.is_empty() or rules.is_over()
	if can_resize != _menu_can_resize:
		_menu_can_resize = can_resize
		_refresh_menu()


## Distance from the board centre to the strip's centre line.
func menu_distance() -> float:
	return GRID * 0.5 + TAP_TOLERANCE + MENU_GAP * 0.5 + MENU_BUTTON.y * 0.5


static func _side_of(toward: Vector2) -> int:
	if absf(toward.y) >= absf(toward.x):
		return 0 if toward.y > 0.0 else 2
	return 1 if toward.x > 0.0 else 3


static func _side_dir(side: int) -> Vector2:
	match side:
		1: return Vector2(1.0, 0.0)
		2: return Vector2(0.0, -1.0)
		3: return Vector2(-1.0, 0.0)
		_: return Vector2(0.0, 1.0)


## Options button under a board-space point, or -1.
func menu_item_at(point: Vector3) -> int:
	if _menu == null:
		return -1
	var local: Vector3 = _menu.transform.affine_inverse() * Vector3(point.x, 0.0, point.z)
	var pad: float = 0.006
	if absf(local.z) > MENU_BUTTON.y * 0.5 + pad:
		return -1
	for i: int in MENU_ITEMS.size():
		if absf(local.x - _menu_x(i)) <= MENU_BUTTON.x * 0.5 + pad:
			return i
	return -1


## Board-space centre of an options button (on the slab-top tap plane).
func menu_button_point(item: int) -> Vector3:
	var p: Vector3 = _menu.transform * Vector3(_menu_x(item), 0.0, 0.0)
	return Vector3(p.x, SLAB_TOP, p.z)


func menu_side() -> int:
	return _menu_side
