class_name SurfaceRegion
extends RefCounted
## The play area the board must stay inside: a polygon on one surface, in
## ANCHOR space (x, z; the surface is y = 0). It comes from the player's
## traced outline, or from the ARCore plane the board was placed on.
##
## Pure geometry (no nodes), unit-tested headless: footprint-in-polygon
## tests, clamping a board offset inside, and auto-fitting a board.

enum Source { NONE, PLANE, TRACED }

## Keep the board this far inside the edge (metres).
const EDGE_MARGIN: float = 0.01
## Largest auto-fit size, as a multiple of the game's own board size.
const MAX_FIT_SCALE: float = 1.0
const MAX_POINTS: int = 48
const SEARCH_GRID: int = 9

var source: Source = Source.NONE
## Anchor-space outline (x, z), counter-clockwise or clockwise.
var polygon: PackedVector2Array = PackedVector2Array()


static func make(points: PackedVector2Array, p_source: Source) -> SurfaceRegion:
	var region := SurfaceRegion.new()
	region.polygon = points
	region.source = p_source
	return region


func is_valid() -> bool:
	return polygon.size() >= 3 and area() > 0.0001


func area() -> float:
	return absf(signed_area(polygon))


static func signed_area(points: PackedVector2Array) -> float:
	var total: float = 0.0
	for i: int in points.size():
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		total += a.x * b.y - b.x * a.y
	return total * 0.5


func centroid() -> Vector2:
	var a: float = signed_area(polygon)
	if absf(a) < 0.000001:
		var sum := Vector2.ZERO
		for p: Vector2 in polygon:
			sum += p
		return sum / maxf(1.0, float(polygon.size()))
	var c := Vector2.ZERO
	for i: int in polygon.size():
		var p: Vector2 = polygon[i]
		var q: Vector2 = polygon[(i + 1) % polygon.size()]
		var cross: float = p.x * q.y - q.x * p.y
		c += (p + q) * cross
	return c / (6.0 * a)


func contains(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point, polygon)


## Corners of a board footprint in anchor space (x, z).
## `half` = half the board size times its scale; yaw as in BoardPlacement.
static func footprint(center: Vector2, half: Vector2, yaw: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for corner: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		# Basis(UP, yaw) maps local (x, z) to anchor (x cos + z sin, -x sin + z cos).
		var rotated := Vector2(corner.x * cos(yaw) + corner.y * sin(yaw), -corner.x * sin(yaw) + corner.y * cos(yaw))
		out.append(center + rotated)
	return out


## True if the footprint (grown by EDGE_MARGIN) lies inside the polygon.
func fits(center: Vector2, half: Vector2, yaw: float) -> bool:
	if not is_valid():
		return true
	var rect: PackedVector2Array = footprint(center, half + Vector2.ONE * EDGE_MARGIN, yaw)
	for corner: Vector2 in rect:
		if not contains(corner):
			return false
	for i: int in 4:
		var a: Vector2 = rect[i]
		var b: Vector2 = rect[(i + 1) % 4]
		for j: int in polygon.size():
			if Geometry2D.segment_intersects_segment(a, b, polygon[j], polygon[(j + 1) % polygon.size()]) != null:
				return false
	return true


## A board centre that fits, as close to `desired` as possible, or null.
## `fallback` is a centre known to fit (e.g. the last valid offset).
func clamp_center(desired: Vector2, half: Vector2, yaw: float, fallback: Variant = null) -> Variant:
	if fits(desired, half, yaw):
		return desired
	var inner: Variant = fallback if fallback != null and fits(fallback as Vector2, half, yaw) else best_center(desired, half, yaw)
	if inner == null:
		return null
	var good: Vector2 = inner as Vector2
	# Slide from the fitting centre toward the desired one as far as it fits.
	var lo: float = 0.0
	var hi: float = 1.0
	for _i: int in 16:
		var mid: float = (lo + hi) * 0.5
		if fits(good.lerp(desired, mid), half, yaw):
			lo = mid
		else:
			hi = mid
	return good.lerp(desired, lo)


## Any fitting centre (centroid first, then a grid), nearest to `near`.
func best_center(near: Vector2, half: Vector2, yaw: float) -> Variant:
	var c: Vector2 = centroid()
	if fits(c, half, yaw):
		return c
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector2 in polygon:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var best: Variant = null
	var best_distance: float = INF
	for i: int in SEARCH_GRID:
		for j: int in SEARCH_GRID:
			var candidate := Vector2(
				lerpf(lo.x, hi.x, (float(i) + 0.5) / SEARCH_GRID),
				lerpf(lo.y, hi.y, (float(j) + 0.5) / SEARCH_GRID))
			var d: float = candidate.distance_squared_to(near)
			if d < best_distance and fits(candidate, half, yaw):
				best = candidate
				best_distance = d
	return best


## Main direction of the outline (radians, as a BoardPlacement yaw that
## lines the board's x axis up with the long side of the area).
func principal_yaw() -> float:
	var c: Vector2 = centroid()
	var xx: float = 0.0
	var zz: float = 0.0
	var xz: float = 0.0
	for p: Vector2 in polygon:
		var d: Vector2 = p - c
		xx += d.x * d.x
		zz += d.y * d.y
		xz += d.x * d.y
	var angle: float = 0.5 * atan2(2.0 * xz, xx - zz)
	# Direction (cos a, sin a) in (x, z) is local +x rotated by yaw = -a.
	return wrapf(-angle, -PI, PI)


## Biggest board that fits: {"center": Vector2, "yaw": float, "scale": float},
## or {} if even `min_scale` does not fit. `board_size` is at scale 1.
func fit_board(board_size: Vector2, min_scale: float, max_scale: float = MAX_FIT_SCALE) -> Dictionary:
	if not is_valid():
		return {}
	var best: Dictionary = {}
	var base_yaw: float = principal_yaw()
	for yaw: float in [base_yaw, wrapf(base_yaw + PI * 0.5, -PI, PI)]:
		var c: Vector2 = centroid()
		if best_center(c, board_size * 0.5 * min_scale, yaw) == null:
			continue
		var lo: float = min_scale
		var hi: float = max_scale
		if best_center(c, board_size * 0.5 * hi, yaw) != null:
			lo = hi
		else:
			for _i: int in 10:
				var mid: float = (lo + hi) * 0.5
				if best_center(c, board_size * 0.5 * mid, yaw) != null:
					lo = mid
				else:
					hi = mid
		if best.is_empty() or lo > float(best["scale"]):
			best = {"center": best_center(c, board_size * 0.5 * lo, yaw), "yaw": yaw, "scale": lo}
	return best


## Clean up a traced stroke: drop near-duplicate points, thin to MAX_POINTS,
## and fall back to the convex hull if the outline crosses itself.
## Returns an empty array if it does not enclose a usable area.
static func clean_outline(points: PackedVector2Array, min_spacing: float = 0.01) -> PackedVector2Array:
	var spaced := PackedVector2Array()
	for p: Vector2 in points:
		if spaced.is_empty() or spaced[spaced.size() - 1].distance_to(p) >= min_spacing:
			spaced.append(p)
	if spaced.size() > 3 and spaced[0].distance_to(spaced[spaced.size() - 1]) < min_spacing:
		spaced.remove_at(spaced.size() - 1)
	if spaced.size() > MAX_POINTS:
		var thinned := PackedVector2Array()
		var step: float = float(spaced.size()) / float(MAX_POINTS)
		for i: int in MAX_POINTS:
			thinned.append(spaced[int(i * step)])
		spaced = thinned
	if spaced.size() < 3:
		return PackedVector2Array()
	if Geometry2D.triangulate_polygon(spaced).is_empty() or _self_intersects(spaced):
		spaced = Geometry2D.convex_hull(spaced)
		if spaced.size() > 1 and spaced[0] == spaced[spaced.size() - 1]:
			spaced.remove_at(spaced.size() - 1)
	if spaced.size() < 3 or absf(signed_area(spaced)) < 0.0025:
		return PackedVector2Array()
	return spaced


static func _self_intersects(points: PackedVector2Array) -> bool:
	var n: int = points.size()
	for i: int in n:
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % n]
		for j: int in range(i + 2, n):
			if i == 0 and j == n - 1:
				continue
			if Geometry2D.segment_intersects_segment(a, b, points[j], points[(j + 1) % n]) != null:
				return true
	return false


## Ribbon mesh along an outline (x, z) at height `y`, `width` metres wide.
static func outline_mesh(points: PackedVector2Array, closed: bool, width: float = 0.008, y: float = 0.003) -> ArrayMesh:
	var count: int = points.size()
	if count < 2:
		return null
	var vertices := PackedVector3Array()
	var segments: int = count if closed else count - 1
	for i: int in segments:
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % count]
		var dir: Vector2 = b - a
		if dir.length() < 0.0001:
			continue
		var side: Vector2 = Vector2(-dir.y, dir.x).normalized() * width * 0.5
		var a0 := Vector3(a.x - side.x, y, a.y - side.y)
		var a1 := Vector3(a.x + side.x, y, a.y + side.y)
		var b0 := Vector3(b.x - side.x, y, b.y - side.y)
		var b1 := Vector3(b.x + side.x, y, b.y + side.y)
		vertices.append_array([a0, b0, b1, a0, b1, a1])
	if vertices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
