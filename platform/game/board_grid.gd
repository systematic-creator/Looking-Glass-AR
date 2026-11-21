class_name BoardGrid
extends RefCounted
## A cell grid laid over a board, in BOARD SPACE (LGGame local space: origin at
## the board centre, XZ plane, metres at placement scale 1).
##
## Cells are addressed as Vector2i(x, y): x grows along board +X, y along board
## +Z (toward the player at the default lock). Each cell has a TAG (what the
## ground is: open, path, terrain, a goal such as the Crystal) and an OCCUPANT
## id (what was built there, 0 = nothing). Games decide what tags mean for
## building and walking; BoardGrid only stores and answers.
##
## Continuous "cell coordinates" (Vector2, in cells, origin at the grid's
## -X/-Z corner) are what simulations use: cell (i, j) spans [i, i+1) x [j, j+1)
## and its centre is (i + 0.5, j + 0.5). to_board() / from_board() convert to
## board space, so a game's simulation never depends on the board's size in
## metres: scale the cell size and everything follows (scalable boards).

enum Tag { OPEN = 0, PATH = 1, TERRAIN = 2, GOAL = 3 }

## The four sides of the grid (border rows / columns).
enum Side { WEST = 0, EAST = 1, NORTH = 2, SOUTH = 3 }
const SIDE_NAMES: PackedStringArray = ["W", "E", "N", "S"]

const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIRS8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var nx: int = 12
var ny: int = 12
## Edge length of one cell in board metres (at placement scale 1).
var cell_size: float = 0.04
## Board-space position of the grid's -X/-Z corner (y is ignored).
var origin: Vector3 = Vector3.ZERO
var tags: PackedByteArray = PackedByteArray()
var occupant: PackedInt32Array = PackedInt32Array()


func _init(p_nx: int = 12, p_ny: int = 12, p_cell_size: float = 0.04, p_origin: Variant = null) -> void:
	nx = maxi(1, p_nx)
	ny = maxi(1, p_ny)
	cell_size = maxf(0.0001, p_cell_size)
	origin = p_origin if p_origin is Vector3 else Vector3(-nx * cell_size * 0.5, 0.0, -ny * cell_size * 0.5)
	tags.resize(nx * ny)
	tags.fill(Tag.OPEN)
	occupant.resize(nx * ny)
	occupant.fill(0)


## A grid of `cells_x` x `cells_y` centred on a footprint of `size` metres,
## leaving `margin` metres of rim on every side.
static func fit(size: Vector2, cells_x: int, cells_y: int, margin: float = 0.0) -> BoardGrid:
	var usable := Vector2(maxf(0.001, size.x - 2.0 * margin), maxf(0.001, size.y - 2.0 * margin))
	var c: float = minf(usable.x / cells_x, usable.y / cells_y)
	return BoardGrid.new(cells_x, cells_y, c)


func cell_count() -> int:
	return nx * ny


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < nx and cell.y < ny


func index(cell: Vector2i) -> int:
	return cell.y * nx + cell.x


func cell_of_index(i: int) -> Vector2i:
	return Vector2i(i % nx, i / nx)


func get_tag(cell: Vector2i) -> int:
	return tags[index(cell)] if in_bounds(cell) else Tag.TERRAIN


func set_tag(cell: Vector2i, tag: int) -> void:
	if in_bounds(cell):
		tags[index(cell)] = tag


func get_occupant(cell: Vector2i) -> int:
	return occupant[index(cell)] if in_bounds(cell) else -1


func set_occupant(cell: Vector2i, id: int) -> void:
	if in_bounds(cell):
		occupant[index(cell)] = id


func is_free(cell: Vector2i) -> bool:
	return in_bounds(cell) and occupant[index(cell)] == 0


## Size of the whole grid in board metres.
func size_metres() -> Vector2:
	return Vector2(nx * cell_size, ny * cell_size)


## Continuous cell coordinates -> board space (y = `height`).
func to_board(cells: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(origin.x + cells.x * cell_size, height, origin.z + cells.y * cell_size)


## Board space -> continuous cell coordinates.
func from_board(point: Vector3) -> Vector2:
	return Vector2((point.x - origin.x) / cell_size, (point.z - origin.z) / cell_size)


## The cell under a board-space point (may be out of bounds: check in_bounds).
func cell_at(point: Vector3) -> Vector2i:
	var c: Vector2 = from_board(point)
	return Vector2i(floori(c.x), floori(c.y))


static func center_of(cell: Vector2i) -> Vector2:
	return Vector2(cell.x + 0.5, cell.y + 0.5)


func cell_center_board(cell: Vector2i, height: float = 0.0) -> Vector3:
	return to_board(center_of(cell), height)


func neighbours(cell: Vector2i, diagonal: bool = false) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d: Vector2i in (DIRS8 if diagonal else DIRS4):
		var n: Vector2i = cell + d
		if in_bounds(n):
			out.append(n)
	return out


func is_border(cell: Vector2i) -> bool:
	return in_bounds(cell) and (cell.x == 0 or cell.y == 0 or cell.x == nx - 1 or cell.y == ny - 1)


## Cells along one side, in order (west / east: by y; north / south: by x).
func side_cells(side: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	match side:
		Side.WEST:
			for y: int in ny:
				out.append(Vector2i(0, y))
		Side.EAST:
			for y: int in ny:
				out.append(Vector2i(nx - 1, y))
		Side.NORTH:
			for x: int in nx:
				out.append(Vector2i(x, 0))
		Side.SOUTH:
			for x: int in nx:
				out.append(Vector2i(x, ny - 1))
	return out


## Every border cell once.
func border_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i: int in cell_count():
		var c: Vector2i = cell_of_index(i)
		if is_border(c):
			out.append(c)
	return out


## Outward unit normal of a side, in cell coordinates.
static func side_normal(side: int) -> Vector2:
	match side:
		Side.WEST:
			return Vector2(-1, 0)
		Side.EAST:
			return Vector2(1, 0)
		Side.NORTH:
			return Vector2(0, -1)
	return Vector2(0, 1)


## Cells with a given tag.
func cells_with_tag(tag: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i: int in cell_count():
		if tags[i] == tag:
			out.append(cell_of_index(i))
	return out


## Breadth-first flood from `starts` over cells where `passable[index]` != 0
## (8-neighbour moves never cut a blocked corner). Returns a byte mask of the
## reached cells. The starts are always reached.
func flood(starts: Array[Vector2i], passable: PackedByteArray, diagonal: bool = true) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(cell_count())
	var queue: Array[Vector2i] = []
	for s: Vector2i in starts:
		if in_bounds(s) and seen[index(s)] == 0:
			seen[index(s)] = 1
			queue.append(s)
	var head: int = 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d: Vector2i in (DIRS8 if diagonal else DIRS4):
			var n: Vector2i = c + d
			if not in_bounds(n):
				continue
			var ni: int = index(n)
			if seen[ni] != 0 or passable[ni] == 0:
				continue
			if d.x != 0 and d.y != 0:
				if passable[index(Vector2i(c.x + d.x, c.y))] == 0 or passable[index(Vector2i(c.x, c.y + d.y))] == 0:
					continue
			seen[ni] = 1
			queue.append(n)
	return seen
