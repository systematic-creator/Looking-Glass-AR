class_name TicTacToeGame
extends LGGame
## Sample Looking Glass game: two-player hot-seat tic-tac-toe on a 30 cm
## hologram board. Shows the whole contract in a few lines: build in
## _on_board_ready, take taps in board space, only accept moves while
## playing, and use the platform's hologram kit (Holo, HoloDrop) for the look:
## a glowing slab floating over a projector glow, 3D X and O pieces that drop
## in with a bounce and a flash, and a glowing line through a win.

const CELL: float = 0.09
## The slab floats over the table: its underside and its top (the surface
## players tap, see board_surface_height()).
const SLAB_BOTTOM: float = 0.014
const SLAB_TOP: float = 0.026
## Piece centre above the slab top.
const PIECE_LIFT: float = 0.013
## Pieces drop in from this high above their cell (lower if the play box
## is shorter: they always start inside it).
const DROP_HEIGHT: float = 0.16
## Room kept between a falling piece's start and the box top.
const DROP_TOP_MARGIN: float = 0.03
## Box outline brightness while playing (see LGGame.box_outline_while_playing).
const OUTLINE_WHILE_PLAYING: float = 0.35
## Taps this far past the grid's edge (metres) still pick the edge cell, so
## a slightly-off fingertip on a phone still counts.
const TAP_TOLERANCE: float = 0.03
## The turn token floats just outside the board edge, on the far side.
const TOKEN_GAP: float = 0.035
const TOKEN_HEIGHT: float = 0.05
const TOKEN_SCALE: float = 0.38

var rules: TicTacToeRules = TicTacToeRules.new()
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


func board_surface_height() -> float:
	return SLAB_TOP


func box_outline_while_playing() -> float:
	return OUTLINE_WHILE_PLAYING


## How far pieces fall: DROP_HEIGHT, or less so they start inside the box.
func drop_height() -> float:
	var rest: float = SLAB_TOP + PIECE_LIFT
	return clampf(get_box().height() - rest - DROP_TOP_MARGIN, 0.02, DROP_HEIGHT)


func _on_board_ready() -> void:
	var size: Vector2 = get_board_size()
	add_child(Holo.glow_base(size))
	_build_slab(size)
	for index: int in 9:
		var tile := MeshInstance3D.new()
		tile.name = "Tile%d" % index
		var mesh := BoxMesh.new()
		mesh.size = Vector3(CELL - 0.012, 0.0015, CELL - 0.012)
		tile.mesh = mesh
		tile.material_override = Holo.material(Holo.CYAN, 0.04, 0.0, 1.0)
		tile.position = cell_center(index) + Vector3(0.0, SLAB_TOP + 0.0008, 0.0)
		add_child(tile)
		tiles.append(tile)
	_marks = Node3D.new()
	_marks.name = "Marks"
	add_child(_marks)
	pieces.resize(9)
	_build_token()
	_place_token(Vector3(0.0, 0.0, 1.0))
	_refresh_status()


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
	var grid := Node3D.new()
	grid.name = "Grid"
	add_child(grid)
	var line := Holo.line_material(Holo.CYAN, 1.5)
	var reach: float = CELL * 1.5 - 0.006
	var y: float = SLAB_TOP + 0.0016
	for k: float in [-0.5, 0.5]:
		grid.add_child(Holo.bar(Vector3(k * CELL, y, -reach), Vector3(k * CELL, y, reach), 0.0035, line))
		grid.add_child(Holo.bar(Vector3(-reach, y, k * CELL), Vector3(reach, y, k * CELL), 0.0035, line))


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
	if rules.is_over():
		new_round()
		return
	var index: int = cell_at(point)
	if index >= 0 and rules.play(index):
		var drop: HoloDrop = _add_mark(index, rules.cells[index])
		if rules.winner != TicTacToeRules.Mark.NONE:
			# Light the win when the winning piece lands.
			drop.landed.connect(_show_win, CONNECT_ONE_SHOT)
	_refresh_status()


func new_round() -> void:
	rules.reset()
	for child: Node in _marks.get_children():
		child.queue_free()
	pieces.clear()
	pieces.resize(9)
	for tile: MeshInstance3D in tiles:
		tile.material_override = Holo.material(Holo.CYAN, 0.04, 0.0, 1.0)
	if _win_line != null:
		_win_line.queue_free()
		_win_line = null
	_refresh_status()


## Board-space centre of a cell on the board plane (index 0 = back-left,
## row-major).
static func cell_center(index: int) -> Vector3:
	var col: int = index % 3
	@warning_ignore("integer_division")
	var row: int = index / 3
	return Vector3((col - 1) * CELL, 0.0, (row - 1) * CELL)


## Centre of a cell on the slab top, where the player sees (and taps) it.
static func cell_top(index: int) -> Vector3:
	return cell_center(index) + Vector3(0.0, SLAB_TOP, 0.0)


## Cell under a board-space point (edge cells extend TAP_TOLERANCE past the
## grid), or -1 off the grid.
static func cell_at(point: Vector3) -> int:
	var half: float = CELL * 1.5
	if absf(point.x) >= half + TAP_TOLERANCE or absf(point.z) >= half + TAP_TOLERANCE:
		return -1
	var col: int = clampi(floori((point.x + half) / CELL), 0, 2)
	var row: int = clampi(floori((point.z + half) / CELL), 0, 2)
	return row * 3 + col


## A hologram X (two crossed bars) or O (a torus), centred on its origin.
static func make_piece(mark: int) -> Node3D:
	var body := Node3D.new()
	body.name = "Body"
	if mark == TicTacToeRules.Mark.X:
		var mat := Holo.material(Holo.CYAN, 0.32, 1.3, 1.25)
		for angle: float in [PI * 0.25, -PI * 0.25]:
			var bar := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(CELL * 0.7, 0.018, 0.018)
			bar.mesh = mesh
			bar.material_override = mat
			bar.rotation.y = angle
			body.add_child(bar)
	else:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = CELL * 0.19
		torus.outer_radius = CELL * 0.31
		torus.rings = 28
		torus.ring_segments = 10
		ring.mesh = torus
		ring.material_override = Holo.material(Holo.MAGENTA, 0.3, 1.3, 1.25)
		body.add_child(ring)
	return body


func _add_mark(index: int, mark: int) -> HoloDrop:
	var root := Node3D.new()
	root.name = "Mark%d" % index
	root.position = cell_top(index) + Vector3(0.0, PIECE_LIFT, 0.0)
	var bob := Node3D.new()
	bob.name = "Bob"
	root.add_child(bob)
	var body: Node3D = make_piece(mark)
	bob.add_child(body)
	_marks.add_child(root)
	pieces[index] = root
	var ripple: MeshInstance3D = Holo.ripple(Holo.CYAN if mark == TicTacToeRules.Mark.X else Holo.MAGENTA, CELL * 0.75)
	ripple.position = cell_top(index) + Vector3(0.0, 0.002, 0.0)
	_marks.add_child(ripple)
	return HoloDrop.start(body, drop_height(), ripple)


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
	var a: Vector3 = cell_top(int(rules.winning_line[0]))
	var b: Vector3 = cell_top(int(rules.winning_line[2]))
	var dir: Vector3 = (b - a).normalized()
	var lift := Vector3(0.0, PIECE_LIFT + 0.012, 0.0)
	_win_line = Holo.bar(a - dir * CELL * 0.4 + lift, b + dir * CELL * 0.4 + lift, 0.009, Holo.line_material(Holo.GOLD, 1.6))
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
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null and _token != null:
		_place_token(to_local(camera.global_position))
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
