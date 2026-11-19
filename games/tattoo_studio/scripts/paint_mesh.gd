class_name TattooPaintMesh
extends RefCounted
## CPU copy of a model's triangles for painting: ray casts against the real
## mesh (not collision capsules) and finds the triangles near a brush.
##
## Per triangle it keeps the affine map between UV and model space:
##   P(u, v) = p0 + a * (u - u0) + b * (v - v0)      (a = dP/du, b = dP/dv)
## plus the inverse metric G^-1 (a, b Gram matrix), so a brush sphere in
## model space can be turned into a UV-space box per triangle. Painting by
## 3D distance through this map is what makes strokes cross UV seams: the
## triangles on both sides of a seam are near the brush in 3D, wherever
## their islands sit in the atlas.
##
## Triangles are grouped into small chunks (sorted by a coarse 3D grid) with
## AABBs, so a ray or a brush only tests the few chunks it can touch.

const CHUNK_SIZE: int = 32
## Minimum 3D area (m^2) for a triangle to be paintable (pole slivers skip).
const MIN_AREA: float = 1e-10

var positions: PackedVector3Array
var uvs: PackedVector2Array
var indices: PackedInt32Array
var tri_count: int = 0
var aabb: AABB

var p0: PackedVector3Array = PackedVector3Array()
var e1: PackedVector3Array = PackedVector3Array()
var e2: PackedVector3Array = PackedVector3Array()
var normal: PackedVector3Array = PackedVector3Array()
var centroid: PackedVector3Array = PackedVector3Array()
var radius: PackedFloat32Array = PackedFloat32Array()
var dpdu: PackedVector3Array = PackedVector3Array()
var dpdv: PackedVector3Array = PackedVector3Array()
var uv0: PackedVector2Array = PackedVector2Array()
var uv_min: PackedVector2Array = PackedVector2Array()
var uv_max: PackedVector2Array = PackedVector2Array()
## G^-1 per triangle: g00, g01, g11.
var ginv: PackedFloat32Array = PackedFloat32Array()
## UV -> barycentric (l1, l2) per triangle: m00, m01, m10, m11.
var bary: PackedFloat32Array = PackedFloat32Array()
## Smallest UV altitude (for a texel-sized edge dilation).
var uv_altitude: PackedFloat32Array = PackedFloat32Array()
var paintable: PackedByteArray = PackedByteArray()

var chunk_min: PackedVector3Array = PackedVector3Array()
var chunk_max: PackedVector3Array = PackedVector3Array()
var chunk_tris: Array[PackedInt32Array] = []


static func from_arrays(vertex_array: PackedVector3Array, uv_array: PackedVector2Array, index_array: PackedInt32Array) -> TattooPaintMesh:
	var mesh := TattooPaintMesh.new()
	mesh._build(vertex_array, uv_array, index_array)
	return mesh


static func from_mesh(source: Mesh) -> TattooPaintMesh:
	var verts := PackedVector3Array()
	var tex := PackedVector2Array()
	var idx := PackedInt32Array()
	for s: int in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(s)
		var sv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var su: Variant = arrays[Mesh.ARRAY_TEX_UV]
		var si: Variant = arrays[Mesh.ARRAY_INDEX]
		var offset: int = verts.size()
		verts.append_array(sv)
		if su is PackedVector2Array and (su as PackedVector2Array).size() == sv.size():
			tex.append_array(su as PackedVector2Array)
		else:
			for _i: int in sv.size():
				tex.append(Vector2.ZERO)
		if si is PackedInt32Array and (si as PackedInt32Array).size() > 0:
			for k: int in si as PackedInt32Array:
				idx.append(k + offset)
		else:
			for k: int in sv.size():
				idx.append(k + offset)
	return from_arrays(verts, tex, idx)


func _build(vertex_array: PackedVector3Array, uv_array: PackedVector2Array, index_array: PackedInt32Array) -> void:
	positions = vertex_array
	uvs = uv_array
	indices = index_array
	tri_count = index_array.size() / 3
	aabb = AABB(vertex_array[0], Vector3.ZERO) if vertex_array.size() > 0 else AABB()
	for v: Vector3 in vertex_array:
		aabb = aabb.expand(v)
	for t: int in tri_count:
		var ia: int = index_array[t * 3]
		var ib: int = index_array[t * 3 + 1]
		var ic: int = index_array[t * 3 + 2]
		var a: Vector3 = vertex_array[ia]
		var b: Vector3 = vertex_array[ib]
		var c: Vector3 = vertex_array[ic]
		var ta: Vector2 = uv_array[ia]
		var tb: Vector2 = uv_array[ib]
		var tc: Vector2 = uv_array[ic]
		var ab: Vector3 = b - a
		var ac: Vector3 = c - a
		p0.append(a)
		e1.append(ab)
		e2.append(ac)
		var cr: Vector3 = ab.cross(ac)
		var area: float = cr.length() * 0.5
		# Godot front faces wind clockwise seen from outside: e1 x e2 points
		# inward, so the outward normal is its negation.
		normal.append(-cr.normalized() if area > 0.0 else Vector3.UP)
		var cen: Vector3 = (a + b + c) / 3.0
		centroid.append(cen)
		radius.append(maxf(cen.distance_to(a), maxf(cen.distance_to(b), cen.distance_to(c))))
		uv0.append(ta)
		uv_min.append(Vector2(minf(ta.x, minf(tb.x, tc.x)), minf(ta.y, minf(tb.y, tc.y))))
		uv_max.append(Vector2(maxf(ta.x, maxf(tb.x, tc.x)), maxf(ta.y, maxf(tb.y, tc.y))))
		var d1: Vector2 = tb - ta
		var d2: Vector2 = tc - ta
		var det: float = d1.x * d2.y - d2.x * d1.y
		var ok: bool = area > MIN_AREA and absf(det) > 1e-12
		var du: Vector3 = Vector3.ZERO
		var dv: Vector3 = Vector3.ZERO
		if ok:
			du = (ab * d2.y - ac * d1.y) / det
			dv = (ac * d1.x - ab * d2.x) / det
		var g00: float = du.dot(du)
		var g01: float = du.dot(dv)
		var g11: float = dv.dot(dv)
		var gdet: float = g00 * g11 - g01 * g01
		if ok and gdet <= 1e-20:
			ok = false
		dpdu.append(du)
		dpdv.append(dv)
		if ok:
			ginv.append_array([g11 / gdet, -g01 / gdet, g00 / gdet])
			# (l1, l2) solves q = l1 * d1 + l2 * d2.
			bary.append_array([d2.y / det, -d2.x / det, -d1.y / det, d1.x / det])
			var longest: float = maxf(d1.length(), maxf(d2.length(), (tc - tb).length()))
			uv_altitude.append(absf(det) / maxf(longest, 1e-12))
		else:
			ginv.append_array([0.0, 0.0, 0.0])
			bary.append_array([0.0, 0.0, 0.0, 0.0])
			uv_altitude.append(0.0)
		paintable.append(1 if ok else 0)
	_build_chunks()


func _build_chunks() -> void:
	var cell: float = 0.05
	var keys: Array[int] = []
	keys.resize(tri_count)
	for t: int in tri_count:
		var rel: Vector3 = (centroid[t] - aabb.position) / cell
		var key: int = ((clampi(int(rel.y), 0, 1023) * 1024 + clampi(int(rel.z), 0, 1023)) * 1024 + clampi(int(rel.x), 0, 1023))
		keys[t] = key * 1048576 + t
	keys.sort()
	var start: int = 0
	while start < tri_count:
		var end: int = mini(start + CHUNK_SIZE, tri_count)
		var tris := PackedInt32Array()
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for k: int in range(start, end):
			var t: int = keys[k] % 1048576
			tris.append(t)
			var a: Vector3 = p0[t]
			for v: Vector3 in [a, a + e1[t], a + e2[t]]:
				lo = lo.min(v)
				hi = hi.max(v)
		chunk_tris.append(tris)
		chunk_min.append(lo)
		chunk_max.append(hi)
		start = end


## Nearest hit of a model-space ray: {position, normal, uv, tri, t} or {}.
## `direction` need not be unit (t is in its units).
func raycast(origin: Vector3, direction: Vector3) -> Dictionary:
	var inv := Vector3(
		1.0 / direction.x if absf(direction.x) > 1e-12 else 1e12,
		1.0 / direction.y if absf(direction.y) > 1e-12 else 1e12,
		1.0 / direction.z if absf(direction.z) > 1e-12 else 1e12)
	var best_t: float = INF
	var best_tri: int = -1
	var best_u: float = 0.0
	var best_v: float = 0.0
	for c: int in chunk_tris.size():
		var t1: Vector3 = (chunk_min[c] - origin) * inv
		var t2: Vector3 = (chunk_max[c] - origin) * inv
		var tmin: float = maxf(maxf(minf(t1.x, t2.x), minf(t1.y, t2.y)), minf(t1.z, t2.z))
		var tmax: float = minf(minf(maxf(t1.x, t2.x), maxf(t1.y, t2.y)), maxf(t1.z, t2.z))
		if tmax < maxf(tmin, 0.0) or tmin > best_t:
			continue
		for t: int in chunk_tris[c]:
			# Moller-Trumbore, two-sided.
			var a1: Vector3 = e1[t]
			var a2: Vector3 = e2[t]
			var pv: Vector3 = direction.cross(a2)
			var det: float = a1.dot(pv)
			if absf(det) < 1e-14:
				continue
			var inv_det: float = 1.0 / det
			var tv: Vector3 = origin - p0[t]
			var u: float = tv.dot(pv) * inv_det
			if u < 0.0 or u > 1.0:
				continue
			var qv: Vector3 = tv.cross(a1)
			var v: float = direction.dot(qv) * inv_det
			if v < 0.0 or u + v > 1.0:
				continue
			var dist: float = a2.dot(qv) * inv_det
			if dist > 1e-7 and dist < best_t:
				best_t = dist
				best_tri = t
				best_u = u
				best_v = v
	if best_tri < 0:
		return {}
	return hit_on(best_tri, best_u, best_v, best_t, direction)


## Hit record for barycentric (u, v) on triangle `tri`.
func hit_on(tri: int, u: float, v: float, t: float = 0.0, direction: Vector3 = Vector3.ZERO) -> Dictionary:
	var ia: int = indices[tri * 3]
	var ib: int = indices[tri * 3 + 1]
	var ic: int = indices[tri * 3 + 2]
	var n: Vector3 = normal[tri]
	if direction != Vector3.ZERO and n.dot(direction) > 0.0:
		n = -n
	return {
		"position": p0[tri] + e1[tri] * u + e2[tri] * v,
		"normal": n,
		"uv": uvs[ia] * (1.0 - u - v) + uvs[ib] * u + uvs[ic] * v,
		"tri": tri,
		"t": t,
	}


## Chunks whose box comes within `r` of the box lo..hi (a stroke segment),
## to narrow later triangles_near() calls.
func chunks_near(lo: Vector3, hi: Vector3, r: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	for c: int in chunk_tris.size():
		var a: Vector3 = chunk_min[c]
		var b: Vector3 = chunk_max[c]
		if a.x - r > hi.x or a.y - r > hi.y or a.z - r > hi.z or b.x + r < lo.x or b.y + r < lo.y or b.z + r < lo.z:
			continue
		out.append(c)
	return out


## Triangles whose bounding sphere comes within `r` of `point` (searching
## only `chunks` if given).
func triangles_near(point: Vector3, r: float, chunks: PackedInt32Array = PackedInt32Array()) -> PackedInt32Array:
	var out := PackedInt32Array()
	var grow := Vector3(r, r, r)
	var search: PackedInt32Array = chunks
	if search.is_empty():
		search = PackedInt32Array(range(chunk_tris.size()))
	for c: int in search:
		var lo: Vector3 = chunk_min[c] - grow
		var hi: Vector3 = chunk_max[c] + grow
		if point.x < lo.x or point.y < lo.y or point.z < lo.z or point.x > hi.x or point.y > hi.y or point.z > hi.z:
			continue
		for t: int in chunk_tris[c]:
			var reach: float = radius[t] + r
			if centroid[t].distance_squared_to(point) <= reach * reach:
				out.append(t)
	return out


## Model-space position of a UV point on triangle `tri` (affine map).
func position_at_uv(tri: int, uv: Vector2) -> Vector3:
	var q: Vector2 = uv - uv0[tri]
	return p0[tri] + dpdu[tri] * q.x + dpdv[tri] * q.y


## Barycentric (l1, l2) of a UV point on triangle `tri`.
func uv_barycentric(tri: int, uv: Vector2) -> Vector2:
	var q: Vector2 = uv - uv0[tri]
	var m: int = tri * 4
	return Vector2(bary[m] * q.x + bary[m + 1] * q.y, bary[m + 2] * q.x + bary[m + 3] * q.y)


## Largest distance of a model-space point's projection... (for tests):
## the triangle containing a UV point, or -1 (linear scan).
func triangle_at_uv(uv: Vector2) -> int:
	for t: int in tri_count:
		if paintable[t] == 0:
			continue
		if uv.x < uv_min[t].x or uv.y < uv_min[t].y or uv.x > uv_max[t].x or uv.y > uv_max[t].y:
			continue
		var l: Vector2 = uv_barycentric(t, uv)
		if l.x >= -1e-6 and l.y >= -1e-6 and l.x + l.y <= 1.0 + 1e-6:
			return t
	return -1
