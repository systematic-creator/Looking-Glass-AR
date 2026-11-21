class_name TattooBodyBuilder
extends RefCounted
## Procedural default models for Tattoo Studio: male, female and lizard man.
## Own work (no external assets), so no third-party licence applies.
##
## Each model is a set of smooth lofted tubes ("parts": body+neck+head as
## one tube, arms, hands, legs, feet, plus snout and tail for the lizard).
## A part is a Catmull-Rom spine through cross-sections (super-ellipses with
## optional soft front bumps), sampled into rings at even arc length. The
## crotch is the closed, rounded bottom of the body tube: a smooth,
## featureless region by construction (no anatomical detail anywhere).
##
## UVs: every part gets its own island in a shared [0,1] atlas (u around the
## tube, seam at the back / inside, v along it), packed by surface size so
## texel density is roughly even, with gutters between islands. Islands
## never overlap, so each texel belongs to one place on the body.
##
## Output follows the model contract (see games/tattoo_studio/MODELS.md):
## metres, origin between the feet on the floor (min y = 0), +Y up, the
## model faces +Z.

const KINDS: PackedStringArray = ["male", "female", "lizard"]
## Ring spacing along a part (metres at scale 1).
const RING_SPACING: float = 0.012
## Gap between UV islands (fraction of the atlas; ~6 texels at 1024).
const UV_GUTTER: float = 0.006


## A tube: sections are [centre: Vector3, rx: float, rz: float, n: float, bump: float].
class Part:
	var name: String
	var sections: Array = []
	var segments: int = 24
	## Initial "front" direction for the ring frame (rz axis).
	var front: Vector3 = Vector3.BACK
	# Built data.
	var rings: Array = []          # Array of PackedVector3Array (segments + 1 each)
	var centres: PackedVector3Array = PackedVector3Array()
	var length: float = 0.0
	var mean_circumference: float = 0.0
	var island: Rect2 = Rect2()

	func _init(part_name: String, part_segments: int, part_front: Vector3 = Vector3.BACK) -> void:
		name = part_name
		segments = part_segments
		front = part_front


## Arrays for an ArrayMesh plus per-part metadata:
## {vertices, normals, uvs, indices, parts: [{name, island: Rect2}], height}.
static func build(kind: String) -> Dictionary:
	var parts: Array = parts_for(kind)
	for part: Part in parts:
		_loft(part)
	pack_islands(parts)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var meta: Array = []
	for part: Part in parts:
		_emit(part, vertices, normals, uvs, indices)
		meta.append({"name": part.name, "island": part.island})
	# Origin on the floor between the feet.
	var min_y: float = INF
	var max_y: float = -INF
	for v: Vector3 in vertices:
		min_y = minf(min_y, v.y)
		max_y = maxf(max_y, v.y)
	for i: int in vertices.size():
		vertices[i].y -= min_y
	return {
		"vertices": vertices, "normals": normals, "uvs": uvs, "indices": indices,
		"parts": meta, "height": max_y - min_y,
	}


static func build_mesh(kind: String) -> ArrayMesh:
	return arrays_to_mesh(build(kind))


static func arrays_to_mesh(data: Dictionary) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = data["normals"]
	arrays[Mesh.ARRAY_TEX_UV] = data["uvs"]
	arrays[Mesh.ARRAY_INDEX] = data["indices"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- Model definitions ------------------------------------------------------------

## Body tube rows: [y, rx, rz, cz, n, bump] for an adult male, 1.75 m.
const MALE_BODY: Array = [
	[0.800, 0.015, 0.015, 0.000, 2.0, 0.0],
	[0.835, 0.100, 0.075, 0.000, 2.2, 0.0],
	[0.880, 0.155, 0.105, -0.005, 2.4, 0.0],
	[0.950, 0.172, 0.115, -0.010, 2.5, 0.0],
	[1.030, 0.160, 0.105, -0.005, 2.5, 0.0],
	[1.100, 0.148, 0.100, 0.000, 2.5, 0.0],
	[1.190, 0.155, 0.105, 0.005, 2.5, 0.0],
	[1.280, 0.168, 0.112, 0.010, 2.6, 0.0],
	[1.360, 0.180, 0.110, 0.005, 2.6, 0.0],
	[1.420, 0.172, 0.095, -0.005, 2.6, 0.0],
	[1.465, 0.110, 0.070, -0.010, 2.4, 0.0],
	[1.500, 0.062, 0.058, 0.000, 2.0, 0.0],
	[1.545, 0.058, 0.060, 0.005, 2.0, 0.0],
	[1.580, 0.070, 0.080, 0.015, 2.0, 0.0],
	[1.625, 0.080, 0.097, 0.012, 2.0, 0.0],
	[1.675, 0.080, 0.095, 0.005, 2.0, 0.0],
	[1.720, 0.066, 0.078, 0.000, 2.0, 0.0],
	[1.745, 0.035, 0.040, 0.000, 2.0, 0.0],
	[1.752, 0.004, 0.004, 0.000, 2.0, 0.0],
]
## Right arm: [centre, rx, rz] (mirrored for the left).
const MALE_ARM: Array = [
	[Vector3(0.130, 1.400, 0.000), 0.050, 0.050],
	[Vector3(0.190, 1.380, -0.005), 0.052, 0.054],
	[Vector3(0.228, 1.280, -0.008), 0.043, 0.046],
	[Vector3(0.255, 1.150, -0.010), 0.036, 0.038],
	[Vector3(0.280, 1.030, 0.000), 0.037, 0.036],
	[Vector3(0.305, 0.905, 0.010), 0.026, 0.022],
	[Vector3(0.310, 0.875, 0.012), 0.024, 0.020],
]
## Hand (a smooth mitten, palm towards the thigh).
const MALE_HAND: Array = [
	[Vector3(0.305, 0.895, 0.012), 0.020, 0.022],
	[Vector3(0.315, 0.840, 0.015), 0.016, 0.042],
	[Vector3(0.322, 0.770, 0.018), 0.013, 0.040],
	[Vector3(0.327, 0.715, 0.020), 0.010, 0.030],
	[Vector3(0.329, 0.690, 0.020), 0.003, 0.008],
]
const MALE_LEG: Array = [
	[Vector3(0.090, 1.000, 0.000), 0.080, 0.080],
	[Vector3(0.092, 0.880, 0.000), 0.085, 0.088],
	[Vector3(0.095, 0.740, 0.005), 0.070, 0.072],
	[Vector3(0.098, 0.530, 0.010), 0.050, 0.054],
	[Vector3(0.100, 0.410, 0.000), 0.050, 0.058],
	[Vector3(0.102, 0.240, -0.005), 0.038, 0.042],
	[Vector3(0.104, 0.100, -0.010), 0.031, 0.034],
	[Vector3(0.105, 0.070, -0.010), 0.030, 0.033],
]
## Foot along +Z (rz is the vertical half-height here).
const MALE_FOOT: Array = [
	[Vector3(0.105, 0.045, -0.070), 0.010, 0.010],
	[Vector3(0.105, 0.050, -0.055), 0.032, 0.038],
	[Vector3(0.106, 0.052, -0.010), 0.038, 0.045],
	[Vector3(0.108, 0.036, 0.060), 0.044, 0.032],
	[Vector3(0.110, 0.022, 0.130), 0.043, 0.020],
	[Vector3(0.110, 0.018, 0.170), 0.030, 0.014],
	[Vector3(0.110, 0.016, 0.188), 0.005, 0.004],
]
const LIZARD_SNOUT: Array = [
	[Vector3(0.0, 1.630, 0.020), 0.060, 0.070],
	[Vector3(0.0, 1.620, 0.100), 0.056, 0.052],
	[Vector3(0.0, 1.605, 0.170), 0.042, 0.036],
	[Vector3(0.0, 1.598, 0.210), 0.020, 0.018],
	[Vector3(0.0, 1.597, 0.224), 0.003, 0.003],
]
## Tail: from the lower back, back and out behind the right leg, curling
## forward on the floor beside the right foot (never between the legs).
const LIZARD_TAIL: Array = [
	[Vector3(0.00, 1.000, -0.070), 0.085, 0.080],
	[Vector3(0.05, 0.900, -0.240), 0.072, 0.068],
	[Vector3(0.16, 0.660, -0.340), 0.058, 0.056],
	[Vector3(0.26, 0.380, -0.380), 0.046, 0.044],
	[Vector3(0.34, 0.150, -0.320), 0.034, 0.032],
	[Vector3(0.42, 0.055, -0.180), 0.020, 0.019],
	[Vector3(0.45, 0.045, -0.080), 0.004, 0.004],
]

## The parts of one default model (unbuilt).
static func parts_for(kind: String) -> Array:
	var h: float = 1.0
	var body_rows: Array = []
	var limb: float = 1.0
	var leg: float = 1.0
	var arm_x: float = 1.0
	var foot_len: float = 1.0
	match kind:
		"female":
			h = 0.95
			limb = 0.88
			leg = 0.97
			arm_x = 0.93
		"lizard":
			h = 1.06
			limb = 1.15
			leg = 1.15
			foot_len = 1.25
	for row: Array in MALE_BODY:
		var r: Array = row.duplicate()
		var y: float = float(r[0])
		if kind == "female":
			if y >= 1.34 and y <= 1.43:
				r[1] = float(r[1]) * 0.86
			elif is_equal_approx(y, 1.28):
				r[1] = float(r[1]) * 0.88
				r[5] = 0.044
			elif is_equal_approx(y, 1.19):
				r[1] = float(r[1]) * 0.84
			elif is_equal_approx(y, 1.10):
				r[1] = float(r[1]) * 0.83
			elif is_equal_approx(y, 1.03):
				r[1] = float(r[1]) * 0.93
			elif y >= 0.87 and y <= 0.96:
				r[1] = float(r[1]) * 0.95
			elif y >= 1.46:
				r[1] = float(r[1]) * 0.9
				r[2] = float(r[2]) * 0.93
			if is_equal_approx(y, 1.36):
				r[5] = 0.016
				r[2] = float(r[2]) * 1.02
		elif kind == "lizard":
			r[1] = float(r[1]) * 1.08
			r[2] = float(r[2]) * 1.12
			if y >= 1.46 and y <= 1.6:
				r[1] = float(r[1]) * 1.35
				r[2] = float(r[2]) * 1.3
			elif y > 1.6 and y < 1.75:
				r[2] = float(r[2]) * 1.05
				r[1] = float(r[1]) * 1.06
		body_rows.append(r)
	var parts: Array = []
	var body := Part.new("body", 44)
	for r: Array in body_rows:
		body.sections.append([Vector3(0.0, float(r[0]) * h, float(r[3]) * h), float(r[1]) * h, float(r[2]) * h, float(r[4]), float(r[5]) * h])
	parts.append(body)
	for side: float in [1.0, -1.0]:
		var tag: String = "right" if side > 0.0 else "left"
		parts.append(_limb("arm_" + tag, MALE_ARM, 24, side, h, limb, Vector3(arm_x, 1.0, 1.0), Vector3.BACK))
		parts.append(_limb("hand_" + tag, MALE_HAND, 16, side, h, limb, Vector3(arm_x, 1.0, 1.0), Vector3.BACK))
		parts.append(_limb("leg_" + tag, MALE_LEG, 28, side, h, leg, Vector3.ONE, Vector3.BACK))
		var foot: Part = _limb("foot_" + tag, MALE_FOOT, 20, side, h, minf(leg, limb * 1.05), Vector3.ONE, Vector3.UP)
		for s: Array in foot.sections:
			var c: Vector3 = s[0] as Vector3
			c.z *= foot_len
			s[0] = c
		parts.append(foot)
	if kind == "lizard":
		parts.append(_limb("snout", LIZARD_SNOUT, 20, 1.0, h, 1.0, Vector3.ONE, Vector3.UP))
		parts.append(_limb("tail", LIZARD_TAIL, 24, 1.0, h, 1.0, Vector3.ONE, Vector3.UP))
	return parts


static func _limb(part_name: String, rows: Array, segments: int, side: float, h: float, thick: float, stretch: Vector3, front: Vector3) -> Part:
	var part := Part.new(part_name, segments, front)
	for row: Array in rows:
		var c: Vector3 = (row[0] as Vector3) * stretch * h
		c.x *= side
		part.sections.append([c, float(row[1]) * h * thick, float(row[2]) * h * thick, 2.0, 0.0])
	return part


# --- Lofting ----------------------------------------------------------------------

static func _catmull(p0: Variant, p1: Variant, p2: Variant, p3: Variant, t: float) -> Variant:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## Section field `field` at spline parameter t in [0, count - 1].
static func _eval(sections: Array, field: int, t: float) -> Variant:
	var n: int = sections.size()
	var i: int = clampi(int(floor(t)), 0, n - 2)
	var f: float = t - float(i)
	var a: Variant = sections[maxi(i - 1, 0)][field]
	var b: Variant = sections[i][field]
	var c: Variant = sections[i + 1][field]
	var d: Variant = sections[mini(i + 2, n - 1)][field]
	if i == 0:
		a = b + (b - c) if field == 0 else b
	if i + 2 > n - 1:
		d = c + (c - b) if field == 0 else c
	return _catmull(a, b, c, d, f)


static func _loft(part: Part) -> void:
	var n: int = part.sections.size()
	var sub: int = 12
	var ts := PackedFloat32Array()
	var lengths := PackedFloat32Array()
	var prev: Vector3 = _eval(part.sections, 0, 0.0) as Vector3
	var total: float = 0.0
	for k: int in (n - 1) * sub + 1:
		var t: float = float(k) / float(sub)
		var p: Vector3 = _eval(part.sections, 0, t) as Vector3
		total += p.distance_to(prev)
		prev = p
		ts.append(t)
		lengths.append(total)
	part.length = total
	var ring_count: int = maxi(6, int(ceil(total / RING_SPACING)) + 1)
	var normal_ref: Vector3 = part.front
	var circumference_sum: float = 0.0
	var k_idx: int = 0
	for r: int in ring_count:
		var target: float = total * float(r) / float(ring_count - 1)
		while k_idx < lengths.size() - 2 and lengths[k_idx + 1] < target:
			k_idx += 1
		var span: float = maxf(lengths[k_idx + 1] - lengths[k_idx], 1e-9)
		var t: float = lerpf(ts[k_idx], ts[k_idx + 1], clampf((target - lengths[k_idx]) / span, 0.0, 1.0))
		var centre: Vector3 = _eval(part.sections, 0, t) as Vector3
		var ahead: Vector3 = _eval(part.sections, 0, minf(t + 0.02, float(n - 1))) as Vector3
		var behind: Vector3 = _eval(part.sections, 0, maxf(t - 0.02, 0.0)) as Vector3
		var tangent: Vector3 = (ahead - behind).normalized()
		# Parallel transport of the front axis.
		var nrm: Vector3 = (normal_ref - tangent * normal_ref.dot(tangent))
		if nrm.length() < 1e-5:
			nrm = Vector3.UP.cross(tangent) if absf(tangent.y) < 0.9 else Vector3.BACK
		nrm = nrm.normalized()
		normal_ref = nrm
		var side: Vector3 = tangent.cross(nrm).normalized()
		var rx: float = maxf(float(_eval(part.sections, 1, t)), 0.0)
		var rz: float = maxf(float(_eval(part.sections, 2, t)), 0.0)
		var exponent: float = maxf(float(_eval(part.sections, 3, t)), 1.5)
		var bump: float = maxf(float(_eval(part.sections, 4, t)), 0.0)
		var ring := PackedVector3Array()
		var perimeter: float = 0.0
		for j: int in part.segments + 1:
			var theta: float = -PI * 0.5 + TAU * float(j) / float(part.segments)
			var c: float = cos(theta)
			var s: float = sin(theta)
			var x: float = signf(c) * pow(absf(c), 2.0 / exponent) * rx
			var z: float = signf(s) * pow(absf(s), 2.0 / exponent) * rz
			if bump > 0.0:
				var push: float = bump * (exp(-pow((theta - (PI * 0.5 - 0.55)) / 0.38, 2.0)) + exp(-pow((theta - (PI * 0.5 + 0.55)) / 0.38, 2.0)))
				var dir := Vector2(x, z)
				if dir.length() > 1e-6:
					dir = dir.normalized() * push
					x += dir.x
					z += dir.y
			var point: Vector3 = centre + side * x + nrm * z
			if j > 0:
				perimeter += point.distance_to(ring[j - 1])
			ring.append(point)
		circumference_sum += perimeter
		part.rings.append(ring)
		part.centres.append(centre)
	part.mean_circumference = circumference_sum / float(ring_count)


## Shelf-pack every part's island (width = mean circumference, height =
## length, uniform scale) into [0,1] with UV_GUTTER between islands.
static func pack_islands(parts: Array) -> void:
	var sizes: Array[Vector2] = []
	for part: Part in parts:
		sizes.append(Vector2(maxf(part.mean_circumference, 0.01), maxf(part.length, 0.01)))
	var rects: Array[Rect2] = pack_rects(sizes, UV_GUTTER)
	for i: int in parts.size():
		(parts[i] as Part).island = rects[i]


## Largest uniform scale at which `sizes` shelf-pack into the unit square.
static func pack_rects(sizes: Array[Vector2], gutter: float) -> Array[Rect2]:
	var lo: float = 0.0
	var hi: float = 4.0
	var best: Array[Rect2] = []
	for _i: int in 40:
		var mid: float = (lo + hi) * 0.5
		var trial: Array[Rect2] = _shelf(sizes, mid, gutter)
		if trial.is_empty():
			hi = mid
		else:
			lo = mid
			best = trial
	return best


static func _shelf(sizes: Array[Vector2], scale: float, gutter: float) -> Array[Rect2]:
	var order: Array = range(sizes.size())
	order.sort_custom(func(a: int, b: int) -> bool: return sizes[a].y > sizes[b].y)
	var out: Array[Rect2] = []
	out.resize(sizes.size())
	var x: float = gutter
	var y: float = gutter
	var row_h: float = 0.0
	for idx: int in order:
		var s: Vector2 = sizes[idx] * scale
		if s.x + 2.0 * gutter > 1.0:
			return []
		if x + s.x + gutter > 1.0:
			x = gutter
			y += row_h + gutter
			row_h = 0.0
		if y + s.y + gutter > 1.0:
			return []
		out[idx] = Rect2(Vector2(x, y), s)
		x += s.x + gutter
		row_h = maxf(row_h, s.y)
	return out


static func _emit(part: Part, vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array) -> void:
	var base: int = vertices.size()
	var cols: int = part.segments + 1
	var ring_count: int = part.rings.size()
	var acc: float = 0.0
	for r: int in ring_count:
		var ring: PackedVector3Array = part.rings[r]
		if r > 0:
			acc += part.centres[r].distance_to(part.centres[r - 1])
		var v: float = acc / maxf(part.length, 1e-6)
		for j: int in cols:
			vertices.append(ring[j])
			var u: float = float(j) / float(part.segments)
			uvs.append(part.island.position + Vector2(u, v) * part.island.size)
			normals.append(Vector3.ZERO)
	# Winding: outward normals (checked on a middle quad).
	var mid: int = ring_count / 2
	var a0: Vector3 = vertices[base + mid * cols]
	var c0: Vector3 = vertices[base + (mid + 1) * cols]
	var b0: Vector3 = vertices[base + mid * cols + 1]
	var outward: Vector3 = a0 - part.centres[mid]
	var flip: bool = (c0 - a0).cross(b0 - a0).dot(outward) < 0.0
	var tris := PackedInt32Array()
	for r: int in ring_count - 1:
		for j: int in part.segments:
			var a: int = base + r * cols + j
			var b: int = a + 1
			var c: int = a + cols
			var d: int = c + 1
			# Godot front faces wind clockwise seen from outside.
			if flip:
				tris.append_array([a, c, b, b, c, d])
			else:
				tris.append_array([a, b, c, b, d, c])
	# Smooth normals (sign fixed below), the seam column shared with column 0.
	var i: int = 0
	while i < tris.size():
		var p0: Vector3 = vertices[tris[i]]
		var p1: Vector3 = vertices[tris[i + 1]]
		var p2: Vector3 = vertices[tris[i + 2]]
		var fn: Vector3 = (p1 - p0).cross(p2 - p0)
		for k: int in 3:
			normals[tris[i + k]] += fn
		i += 3
	for r: int in ring_count:
		var first: int = base + r * cols
		var last: int = first + part.segments
		var sum: Vector3 = normals[first] + normals[last]
		normals[first] = sum
		normals[last] = sum
	for idx: int in range(base, vertices.size()):
		var nv: Vector3 = normals[idx]
		normals[idx] = nv.normalized() if nv.length() > 1e-12 else Vector3.UP
	# Pole rings (all one point): use the tube direction.
	for r: int in [0, ring_count - 1]:
		var ring: PackedVector3Array = part.rings[r]
		if ring[0].distance_to(ring[part.segments / 2]) < 0.002:
			var along: Vector3 = (part.centres[r] - part.centres[1 if r == 0 else ring_count - 2]).normalized()
			for j: int in cols:
				normals[base + r * cols + j] = along
	# Normals point away from the tube's centre line.
	var probe: int = base + mid * cols
	if normals[probe].dot(vertices[probe] - part.centres[mid]) < 0.0:
		for idx: int in range(base, vertices.size()):
			normals[idx] = -normals[idx]
	indices.append_array(tris)
