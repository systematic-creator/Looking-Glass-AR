class_name EdgeFitter
extends RefCounted
## "Fit edges" calibration stage (pure maths, unit-tested): the play-area
## outline (anchor space, x/z on the surface) simplified to a few corners the
## player drags onto the real table edges. Corner handles move one corner;
## edge handles slide a whole edge along its outward normal (keeps it
## straight, the quick way to fix one wrong side). Moves that would make the
## outline self-intersect, collapse an edge or shrink it below MIN_AREA are
## refused. Reset returns to the outline the stage started with.

const MAX_CORNERS: int = 8
## Shortest allowed edge (m) and smallest area (m²).
const MIN_EDGE: float = 0.03
const MIN_AREA: float = 0.02

enum Handle { CORNER, EDGE }

var polygon: PackedVector2Array = PackedVector2Array()
var original: PackedVector2Array = PackedVector2Array()


func begin(outline: PackedVector2Array) -> void:
	original = simplify(outline, MAX_CORNERS)
	polygon = original.duplicate()


func reset() -> void:
	polygon = original.duplicate()


func is_active() -> bool:
	return polygon.size() >= 3


func is_changed() -> bool:
	if polygon.size() != original.size():
		return true
	for i: int in polygon.size():
		if polygon[i].distance_to(original[i]) > 0.0005:
			return true
	return false


## Every handle: {"kind": Handle, "index": int, "point": Vector2}. Edge i
## runs from corner i to corner i + 1; its handle is the midpoint.
func handles() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in polygon.size():
		out.append({"kind": Handle.CORNER, "index": i, "point": polygon[i]})
	for i: int in polygon.size():
		out.append({"kind": Handle.EDGE, "index": i, "point": (polygon[i] + polygon[(i + 1) % polygon.size()]) * 0.5})
	return out


## Move corner `index` by `delta`. False (and unchanged) if refused.
func move_corner(index: int, delta: Vector2) -> bool:
	if index < 0 or index >= polygon.size():
		return false
	var moved: PackedVector2Array = polygon.duplicate()
	moved[index] = moved[index] + delta
	return _accept(moved)


## Slide edge `index` outward (positive) / inward by the part of `delta`
## along its outward normal.
func move_edge(index: int, delta: Vector2) -> bool:
	if index < 0 or index >= polygon.size():
		return false
	var n: Vector2 = outward_normal(index)
	var step: Vector2 = n * delta.dot(n)
	var moved: PackedVector2Array = polygon.duplicate()
	var j: int = (index + 1) % polygon.size()
	moved[index] = moved[index] + step
	moved[j] = moved[j] + step
	return _accept(moved)


## Move a handle (see handles()) by `delta`.
func move_handle(kind: Handle, index: int, delta: Vector2) -> bool:
	return move_corner(index, delta) if kind == Handle.CORNER else move_edge(index, delta)


func outward_normal(index: int) -> Vector2:
	var a: Vector2 = polygon[index]
	var b: Vector2 = polygon[(index + 1) % polygon.size()]
	var n: Vector2 = Vector2(b.y - a.y, a.x - b.x).normalized()
	# Point away from the interior: flip for the other winding.
	if SurfaceRegion.signed_area(polygon) < 0.0:
		n = -n
	return n


func _accept(moved: PackedVector2Array) -> bool:
	var area: float = SurfaceRegion.signed_area(moved)
	# Too small, or turned inside out (a corner pulled across the outline).
	if absf(area) < MIN_AREA or signf(area) != signf(SurfaceRegion.signed_area(polygon)):
		return false
	for i: int in moved.size():
		if moved[i].distance_to(moved[(i + 1) % moved.size()]) < MIN_EDGE:
			return false
	if SurfaceRegion._self_intersects(moved):
		return false
	polygon = moved
	return true


## Closed-outline Douglas-Peucker down to at most `max_corners` corners
## (tolerance grows from 1 cm until it fits).
static func simplify(outline: PackedVector2Array, max_corners: int) -> PackedVector2Array:
	if outline.size() <= max_corners:
		return outline.duplicate()
	var tolerance: float = 0.01
	var best: PackedVector2Array = outline.duplicate()
	while tolerance < 1.0:
		best = _simplify_closed(outline, tolerance)
		if best.size() <= max_corners and best.size() >= 3:
			return best
		tolerance *= 1.5
	return best


static func _simplify_closed(outline: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	# Split at the two points farthest apart, simplify both chains.
	var a: int = 0
	var b: int = 0
	var far: float = -1.0
	for i: int in outline.size():
		var d: float = outline[i].distance_squared_to(outline[0])
		if d > far:
			far = d
			a = i
	far = -1.0
	for i: int in outline.size():
		var d: float = outline[i].distance_squared_to(outline[a])
		if d > far:
			far = d
			b = i
	var lo: int = mini(a, b)
	var hi: int = maxi(a, b)
	var first := PackedVector2Array()
	for i: int in range(lo, hi + 1):
		first.append(outline[i])
	var second := PackedVector2Array()
	for i: int in range(hi, outline.size()):
		second.append(outline[i])
	for i: int in range(0, lo + 1):
		second.append(outline[i])
	var out := PackedVector2Array()
	var s1: PackedVector2Array = _dp(first, tolerance)
	var s2: PackedVector2Array = _dp(second, tolerance)
	for i: int in s1.size() - 1:
		out.append(s1[i])
	for i: int in s2.size() - 1:
		out.append(s2[i])
	return out


static func _dp(chain: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	if chain.size() <= 2:
		return chain.duplicate()
	var a: Vector2 = chain[0]
	var b: Vector2 = chain[chain.size() - 1]
	var worst: float = -1.0
	var at: int = 0
	for i: int in range(1, chain.size() - 1):
		var d: float = Geometry2D.get_closest_point_to_segment(chain[i], a, b).distance_to(chain[i])
		if d > worst:
			worst = d
			at = i
	if worst <= tolerance:
		return PackedVector2Array([a, b])
	var left: PackedVector2Array = _dp(chain.slice(0, at + 1), tolerance)
	var right: PackedVector2Array = _dp(chain.slice(at), tolerance)
	var out := PackedVector2Array()
	for i: int in left.size() - 1:
		out.append(left[i])
	out.append_array(right)
	return out
