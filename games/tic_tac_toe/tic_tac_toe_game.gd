class_name TicTacToeGame
extends LGGame
## Sample Looking Glass game: two-player hot-seat tic-tac-toe on a 30 cm
## board. Shows the whole contract in a few lines: build in _on_board_ready,
## take taps in board space, and only accept moves while playing.

const CELL: float = 0.09
const GAP: float = 0.006
const TILE_HEIGHT: float = 0.012
## Taps this far past the grid's edge (metres) still pick the edge cell, so
## a slightly-off fingertip on a phone still counts.
const TAP_TOLERANCE: float = 0.03
## The floating banner sits this far beyond the board's far edge.
const LABEL_GAP: float = 0.05

var rules: TicTacToeRules = TicTacToeRules.new()
var tiles: Array[MeshInstance3D] = []
var _marks: Node3D
var _label: Label3D
var _tile_material: StandardMaterial3D
var _win_material: StandardMaterial3D
var _x_material: StandardMaterial3D
var _o_material: StandardMaterial3D


func _on_board_ready() -> void:
	_tile_material = _material(Color(0.12, 0.16, 0.22))
	_win_material = _material(Color(0.95, 0.8, 0.25))
	_x_material = _material(Color(0.35, 0.95, 1.0))
	_o_material = _material(Color(1.0, 0.45, 0.55))
	var base := MeshInstance3D.new()
	base.name = "Base"
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(get_board_size().x, 0.006, get_board_size().y)
	base_mesh.material = _material(Color(0.05, 0.07, 0.1))
	base.mesh = base_mesh
	base.position.y = 0.003
	add_child(base)
	for index: int in 9:
		var tile := MeshInstance3D.new()
		tile.name = "Tile%d" % index
		var mesh := BoxMesh.new()
		mesh.size = Vector3(CELL - GAP, TILE_HEIGHT, CELL - GAP)
		tile.mesh = mesh
		tile.material_override = _tile_material
		tile.position = cell_center(index) + Vector3(0.0, 0.006 + TILE_HEIGHT * 0.5, 0.0)
		add_child(tile)
		tiles.append(tile)
	_marks = Node3D.new()
	_marks.name = "Marks"
	add_child(_marks)
	_label = Label3D.new()
	_label.name = "Banner"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.0006
	_label.font_size = 48
	_label.outline_size = 12
	add_child(_label)
	_place_label(Vector3(0.0, 0.0, 1.0))
	_refresh_status()


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
		_add_mark(index, rules.cells[index])
		if rules.winner != TicTacToeRules.Mark.NONE:
			for cell: Variant in rules.winning_line:
				tiles[int(cell)].material_override = _win_material
	_refresh_status()


func new_round() -> void:
	rules.reset()
	for child: Node in _marks.get_children():
		child.queue_free()
	for tile: MeshInstance3D in tiles:
		tile.material_override = _tile_material
	_refresh_status()


## Board-space centre of a cell (index 0 = back-left, row-major).
static func cell_center(index: int) -> Vector3:
	var col: int = index % 3
	@warning_ignore("integer_division")
	var row: int = index / 3
	return Vector3((col - 1) * CELL, 0.0, (row - 1) * CELL)


## Cell under a board-space point (edge cells extend TAP_TOLERANCE past the
## grid), or -1 off the grid.
static func cell_at(point: Vector3) -> int:
	var half: float = CELL * 1.5
	if absf(point.x) >= half + TAP_TOLERANCE or absf(point.z) >= half + TAP_TOLERANCE:
		return -1
	var col: int = clampi(floori((point.x + half) / CELL), 0, 2)
	var row: int = clampi(floori((point.z + half) / CELL), 0, 2)
	return row * 3 + col


func _add_mark(index: int, mark: int) -> void:
	var node := Node3D.new()
	node.name = "Mark%d" % index
	node.position = cell_center(index) + Vector3(0.0, 0.006 + TILE_HEIGHT + 0.008, 0.0)
	if mark == TicTacToeRules.Mark.X:
		for angle: float in [PI * 0.25, -PI * 0.25]:
			var bar := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(CELL * 0.75, 0.014, 0.014)
			mesh.material = _x_material
			bar.mesh = mesh
			bar.rotation.y = angle
			node.add_child(bar)
	else:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = CELL * 0.22
		torus.outer_radius = CELL * 0.32
		torus.material = _o_material
		ring.mesh = torus
		node.add_child(ring)
	_marks.add_child(node)


func _refresh_status() -> void:
	var text: String
	if rules.winner != TicTacToeRules.Mark.NONE:
		text = "%s wins! Tap the board for a new round." % TicTacToeRules.mark_name(rules.winner)
	elif rules.is_draw():
		text = "Draw. Tap the board for a new round."
	else:
		text = "%s to play" % TicTacToeRules.mark_name(rules.turn)
	if not is_playing():
		text = "Paused · " + text
	set_status(text)
	if _label != null:
		_label.text = text


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null and _label != null:
		_place_label(to_local(camera.global_position))


## Keep the banner just beyond the board's far side as seen from the viewer,
## low over the surface, so it never covers a cell.
func _place_label(viewer_local: Vector3) -> void:
	var toward := Vector2(viewer_local.x, viewer_local.z)
	if toward.length() < 0.001:
		toward = Vector2(0.0, 1.0)
	toward = toward.normalized()
	var reach: float = maxf(get_board_size().x, get_board_size().y) * 0.5 * 1.42 + LABEL_GAP
	_label.position = Vector3(-toward.x * reach, 0.03, -toward.y * reach)


func label_position() -> Vector3:
	return _label.position


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.6
	return material
