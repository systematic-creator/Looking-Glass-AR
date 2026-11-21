class_name FlowField
extends RefCounted
## A weighted flow field on a BoardGrid: a Dijkstra fill outward from goal
## cells, so every reachable cell knows its travel cost to the nearest goal
## and which neighbour to step to next. Agents simply walk "downhill".
##
## costs: one float per cell = the cost of ENTERING that cell (1 = open
## ground, 2 = slow ground, INF or <= 0 = impassable). Diagonal steps cost
## sqrt(2) x and never cut a blocked corner. Goal cells need a passable cost
## too (the agent arrives by entering one). At most a few hundred cells on a
## Looking Glass board, so a rebuild is well under a millisecond; rebuild it
## whenever something is built, sold or destroyed.

const UNREACHABLE: float = INF
const SQRT2: float = 1.41421356

var grid: BoardGrid
var dist: PackedFloat32Array = PackedFloat32Array()
## Index of the next cell toward the goal (-1 = goal or unreachable).
var next_index: PackedInt32Array = PackedInt32Array()
var costs: PackedFloat32Array = PackedFloat32Array()
var goals: Array[Vector2i] = []
## Bumped on every rebuild, so agents can notice a change.
var version: int = 0


func _init(p_grid: BoardGrid = null) -> void:
	grid = p_grid


static func is_passable_cost(c: float) -> bool:
	return c > 0.0 and c < INF


func build(p_costs: PackedFloat32Array, p_goals: Array[Vector2i]) -> void:
	costs = p_costs
	goals = p_goals
	var n: int = grid.cell_count()
	dist.resize(n)
	dist.fill(UNREACHABLE)
	next_index.resize(n)
	next_index.fill(-1)
	# Binary heap of [dist, index] pairs.
	var heap_d := PackedFloat32Array()
	var heap_i := PackedInt32Array()
	for g: Vector2i in goals:
		if grid.in_bounds(g):
			var gi: int = grid.index(g)
			dist[gi] = 0.0
			_push(heap_d, heap_i, 0.0, gi)
	while heap_i.size() > 0:
		var d: float = heap_d[0]
		var ci: int = heap_i[0]
		_pop(heap_d, heap_i)
		if d > dist[ci]:
			continue
		var c: Vector2i = grid.cell_of_index(ci)
		for k: int in 8:
			var dir: Vector2i = BoardGrid.DIRS8[k]
			var nb: Vector2i = c + dir
			if not grid.in_bounds(nb):
				continue
			var ni: int = grid.index(nb)
			# We walk the field backwards: an agent at nb steps INTO c, so the
			# step costs c's entry cost; nb itself must be standable.
			if not is_passable_cost(costs[ni]):
				continue
			var step: float = costs[ci]
			if not is_passable_cost(step):
				step = 1.0
			if k >= 4:
				# Diagonal: both corner cells beside the move must be standable.
				if not is_passable_cost(costs[grid.index(Vector2i(c.x + dir.x, c.y))]):
					continue
				if not is_passable_cost(costs[grid.index(Vector2i(c.x, c.y + dir.y))]):
					continue
				step *= SQRT2
			var nd: float = d + step
			if nd < dist[ni] - 0.00001:
				dist[ni] = nd
				next_index[ni] = ci
				_push(heap_d, heap_i, nd, ni)
	version += 1


func reachable(cell: Vector2i) -> bool:
	return grid.in_bounds(cell) and dist[grid.index(cell)] < UNREACHABLE


func distance(cell: Vector2i) -> float:
	return dist[grid.index(cell)] if grid.in_bounds(cell) else UNREACHABLE


## The next cell on the way to the goal (the cell itself at a goal or when
## unreachable).
func next_cell(cell: Vector2i) -> Vector2i:
	if not grid.in_bounds(cell):
		return cell
	var ni: int = next_index[grid.index(cell)]
	return cell if ni < 0 else grid.cell_of_index(ni)


## Unit direction (cell coordinates) to steer along from a continuous
## position: toward the centre of the next cell. Zero at a goal / unreachable.
func direction_at(pos: Vector2) -> Vector2:
	var cell := Vector2i(floori(pos.x), floori(pos.y))
	var nxt: Vector2i = next_cell(cell)
	if nxt == cell:
		return Vector2.ZERO
	var to: Vector2 = BoardGrid.center_of(nxt) - pos
	return to.normalized() if to.length_squared() > 0.000001 else Vector2.ZERO


## Cells from `cell` to a goal along the field (inclusive), for previews.
func path_from(cell: Vector2i, max_steps: int = 4096) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not reachable(cell):
		return out
	var c: Vector2i = cell
	out.append(c)
	for _i: int in max_steps:
		var n: Vector2i = next_cell(c)
		if n == c:
			break
		out.append(n)
		c = n
	return out


static func _push(hd: PackedFloat32Array, hi: PackedInt32Array, d: float, i: int) -> void:
	hd.append(d)
	hi.append(i)
	var k: int = hd.size() - 1
	while k > 0:
		var p: int = (k - 1) >> 1
		if hd[p] <= hd[k]:
			break
		var td: float = hd[p]
		hd[p] = hd[k]
		hd[k] = td
		var ti: int = hi[p]
		hi[p] = hi[k]
		hi[k] = ti
		k = p


static func _pop(hd: PackedFloat32Array, hi: PackedInt32Array) -> void:
	var last: int = hd.size() - 1
	hd[0] = hd[last]
	hi[0] = hi[last]
	hd.resize(last)
	hi.resize(last)
	var k: int = 0
	var n: int = last
	while true:
		var l: int = 2 * k + 1
		var r: int = l + 1
		var m: int = k
		if l < n and hd[l] < hd[m]:
			m = l
		if r < n and hd[r] < hd[m]:
			m = r
		if m == k:
			break
		var td: float = hd[m]
		hd[m] = hd[k]
		hd[k] = td
		var ti: int = hi[m]
		hi[m] = hi[k]
		hi[k] = ti
		k = m
