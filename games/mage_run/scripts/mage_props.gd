class_name MageProps
extends RefCounted
## Mage Run's models, all built in code (no imported or copyrighted assets):
## low-poly vertex-coloured meshes merged into one ArrayMesh per prop, so a
## prop is one draw call. Sizes in board metres at placement scale 1; every
## prop stands on y = 0, is centred on x = 0 and spans z from -depth/2 (far)
## to +depth/2 (near).

const WOOD := Color(0.66, 0.44, 0.24)
const WOOD_DARK := Color(0.42, 0.27, 0.14)
const WOOD_LIGHT := Color(0.8, 0.6, 0.36)
const ROPE := Color(0.78, 0.68, 0.45)
const IRON := Color(0.25, 0.25, 0.28)
const ROYAL_BLUE := Color(0.14, 0.27, 0.72)
const GOLD := Color(0.95, 0.76, 0.28)
const WHITE := Color(0.95, 0.94, 0.9)
const CRYSTAL := Color(0.35, 0.7, 1.0)
const STONE := Color(0.78, 0.78, 0.76)
const STONE_DARK := Color(0.6, 0.6, 0.6)
const SLATE := Color(0.28, 0.38, 0.62)
const MOSS := Color(0.36, 0.56, 0.24)
const GRASS := Color(0.44, 0.66, 0.3)
const ROBE := Color(0.2, 0.34, 0.85)
const ROBE_DARK := Color(0.12, 0.2, 0.55)
const HAT := Color(0.1, 0.15, 0.45)
const SKIN := Color(0.96, 0.8, 0.66)
const BEARD := Color(0.96, 0.96, 0.96)
const BARRIER_RED := Color(0.82, 0.18, 0.14)


## Collects coloured, flat-shaded triangles.
class Builder:
	extends RefCounted
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
		var n: Vector3 = (b - a).cross(c - a)
		if n.length_squared() < 1e-14:
			return
		n = n.normalized()
		verts.append_array([a, b, c])
		normals.append_array([n, n, n])
		colors.append_array([col, col, col])

	## Quad a-b-c-d (any winding: materials are double-sided).
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		tri(a, b, c, col)
		tri(a, c, d, col)

	func box(center: Vector3, size: Vector3, col: Color, basis: Basis = Basis(), top_col: Color = Color(0, 0, 0, 0)) -> void:
		var h: Vector3 = size * 0.5
		var c: Array[Vector3] = []
		for i: int in 8:
			var p := Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z)
			c.append(center + basis * p)
		var top: Color = col if top_col.a == 0.0 else top_col
		quad(c[0], c[1], c[3], c[2], col.darkened(0.1))  # -z
		quad(c[4], c[6], c[7], c[5], col)  # +z
		quad(c[0], c[4], c[5], c[1], col.darkened(0.25))  # -y
		quad(c[2], c[3], c[7], c[6], top)  # +y
		quad(c[0], c[2], c[6], c[4], col.darkened(0.05))  # -x
		quad(c[1], c[5], c[7], c[3], col.darkened(0.05))  # +x

	## Cylinder / cone / frustum along `axis` from `base` (radii r0 -> r1).
	func cylinder(base: Vector3, axis: Vector3, height: float, r0: float, r1: float, segments: int, col: Color, caps: bool = true, cap_col: Color = Color(0, 0, 0, 0)) -> void:
		var up: Vector3 = axis.normalized()
		var side: Vector3 = up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var side2: Vector3 = up.cross(side)
		var top: Vector3 = base + up * height
		var cc: Color = col if cap_col.a == 0.0 else cap_col
		for i: int in segments:
			var a0: float = TAU * float(i) / float(segments)
			var a1: float = TAU * float(i + 1) / float(segments)
			var d0: Vector3 = side * cos(a0) + side2 * sin(a0)
			var d1: Vector3 = side * cos(a1) + side2 * sin(a1)
			var shade: Color = col.darkened(0.12 * (0.5 + 0.5 * sin(a0)))
			if r1 > 0.0:
				quad(base + d0 * r0, base + d1 * r0, top + d1 * r1, top + d0 * r1, shade)
			else:
				tri(base + d0 * r0, base + d1 * r0, top, shade)
			if caps:
				tri(base, base + d1 * r0, base + d0 * r0, cc.darkened(0.2))
				if r1 > 0.0:
					tri(top, top + d0 * r1, top + d1 * r1, cc)

	## Low-poly sphere.
	func sphere(center: Vector3, radius: float, col: Color, rings: int = 4, segments: int = 8, squash: Vector3 = Vector3.ONE) -> void:
		for r: int in rings:
			var t0: float = PI * float(r) / float(rings)
			var t1: float = PI * float(r + 1) / float(rings)
			for s: int in segments:
				var p0: float = TAU * float(s) / float(segments)
				var p1: float = TAU * float(s + 1) / float(segments)
				var a: Vector3 = _sph(t0, p0) * radius * squash
				var b: Vector3 = _sph(t0, p1) * radius * squash
				var c: Vector3 = _sph(t1, p1) * radius * squash
				var d: Vector3 = _sph(t1, p0) * radius * squash
				quad(center + a, center + b, center + c, center + d, col.darkened(0.15 * float(r) / float(rings)))

	func _sph(theta: float, phi: float) -> Vector3:
		return Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))

	## Flat 5-point star facing +z (thickness along z).
	func star(center: Vector3, r_out: float, r_in: float, depth: float, col: Color, basis: Basis = Basis()) -> void:
		var front: Array[Vector3] = []
		var back: Array[Vector3] = []
		for i: int in 10:
			var a: float = PI * 0.5 + TAU * float(i) / 10.0
			var r: float = r_out if i % 2 == 0 else r_in
			var p := Vector3(cos(a) * r, sin(a) * r, 0.0)
			front.append(center + basis * (p + Vector3(0, 0, depth * 0.5)))
			back.append(center + basis * (p - Vector3(0, 0, depth * 0.5)))
		var cf: Vector3 = center + basis * Vector3(0, 0, depth * 0.5)
		var cb: Vector3 = center - basis * Vector3(0, 0, depth * 0.5)
		for i: int in 10:
			var j: int = (i + 1) % 10
			tri(cf, front[i], front[j], col)
			tri(cb, back[j], back[i], col.darkened(0.1))
			quad(front[i], back[i], back[j], front[j], col.darkened(0.2))

	func commit() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh := ArrayMesh.new()
		if not verts.is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh

	func triangle_count() -> int:
		return verts.size() / 3


static var _solid: ShaderMaterial
static var _glow: ShaderMaterial
## Every material that clips at the road's cut (set_cut updates them all).
static var _cut_materials: Array[ShaderMaterial] = []
static var cut_near := Plane(Vector3(0, 0, 1), 1.0e6)
static var cut_far := Plane(Vector3(0, 0, -1), 1.0e6)

const SOLID_SHADER: Shader = preload("res://games/mage_run/shaders/solid_cut.gdshader")
const GLOW_SHADER: Shader = preload("res://games/mage_run/shaders/glow_cut.gdshader")


## A material on `shader` that clips at the road's cut (registered for set_cut).
static func cut_material(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	_cut_materials.append(m)
	_apply_cut(m)
	return m


## Move the cut planes (world space; a point p is cut away where
## plane.is_point_over(p)). Called every frame by MageRunGame.
static func set_cut(near: Plane, far: Plane) -> void:
	cut_near = near
	cut_far = far
	for m: ShaderMaterial in _cut_materials:
		_apply_cut(m)


static func _apply_cut(m: ShaderMaterial) -> void:
	m.set_shader_parameter("cut_near", Vector4(cut_near.normal.x, cut_near.normal.y, cut_near.normal.z, cut_near.d))
	m.set_shader_parameter("cut_far", Vector4(cut_far.normal.x, cut_far.normal.y, cut_far.normal.z, cut_far.d))


static func cut_materials() -> Array[ShaderMaterial]:
	return _cut_materials


## The shared solid material: vertex colours, softly lit, double-sided,
## clipped at the road's cut.
static func solid_material() -> ShaderMaterial:
	if _solid == null:
		_solid = cut_material(SOLID_SHADER)
	return _solid


## Unshaded vertex-colour glow (staff tip, crystals), clipped at the cut.
static func glow_material() -> ShaderMaterial:
	if _glow == null:
		_glow = cut_material(GLOW_SHADER)
	return _glow


# --- Obstacles ----------------------------------------------------------------------

## A wooden fence across one lane (jump it).
static func fence(depth: float) -> ArrayMesh:
	var b := Builder.new()
	var w: float = MageTrack.LANE_PITCH * 0.84
	var hz: float = clampf(depth * 0.3, 0.002, 0.004)
	for side: float in [-1.0, 1.0]:
		b.box(Vector3(side * (w * 0.5 - 0.003), MageTrack.FENCE_TOP * 0.5, 0.0), Vector3(0.006, MageTrack.FENCE_TOP, 0.006), WOOD_DARK)
	b.box(Vector3(0, MageTrack.FENCE_TOP * 0.82, 0), Vector3(w, 0.006, hz * 2.0), WOOD_LIGHT)
	b.box(Vector3(0, MageTrack.FENCE_TOP * 0.42, 0), Vector3(w, 0.006, hz * 2.0), WOOD)
	b.box(Vector3(0, MageTrack.FENCE_TOP * 0.62, 0), Vector3(w * 0.95, 0.005, hz), WOOD.darkened(0.1), Basis(Vector3.FORWARD, 0.35))
	return b.commit()


## A beam on two posts with a hanging royal-blue banner (slide under it).
static func beam(depth: float) -> ArrayMesh:
	var b := Builder.new()
	var w: float = MageTrack.LANE_PITCH * 0.84
	var d: float = clampf(depth * 0.6, 0.004, 0.012)
	for side: float in [-1.0, 1.0]:
		b.box(Vector3(side * (w * 0.5 - 0.003), MageTrack.BEAM_TOP * 0.5, 0.0), Vector3(0.006, MageTrack.BEAM_TOP, 0.006), WOOD_DARK)
	b.box(Vector3(0, MageTrack.BEAM_TOP - 0.006, 0), Vector3(w + 0.006, 0.012, d), WOOD)
	var top: float = MageTrack.BEAM_TOP - 0.012
	var bottom: float = MageTrack.BEAM_BASE + 0.006
	b.box(Vector3(0, (top + bottom) * 0.5, 0.0), Vector3(w * 0.72, top - bottom, 0.002), ROYAL_BLUE)
	b.box(Vector3(0, bottom + 0.002, 0.0), Vector3(w * 0.72, 0.004, 0.003), GOLD)
	# Banner tails and a gold crest.
	for side: float in [-1.0, 1.0]:
		b.tri(Vector3(side * w * 0.36, bottom, 0.0), Vector3(side * w * 0.12, bottom, 0.0), Vector3(side * w * 0.24, bottom - 0.007, 0.0), ROYAL_BLUE.darkened(0.15))
	b.star(Vector3(0, (top + bottom) * 0.5 + 0.004, 0.0015), 0.009, 0.004, 0.0015, GOLD)
	return b.commit()


## A fallen log across one lane, bark and pale cut ends (JUMP it). Low and
## solid to the ground, like the fence.
static func log_mesh(depth: float) -> ArrayMesh:
	var b := Builder.new()
	var w: float = MageTrack.LANE_PITCH * 0.86
	var r: float = MageTrack.LOG_TOP * 0.5
	var rz: float = minf(r, depth * 0.5)
	b.cylinder(Vector3(-w * 0.5, r, 0.0), Vector3.RIGHT, w, rz, rz, 9, WOOD_DARK, true, WOOD_LIGHT)
	# Bark ridges and a stub branch.
	for i: int in 3:
		var x: float = -w * 0.3 + w * 0.3 * float(i)
		b.cylinder(Vector3(x, r, 0.0), Vector3.RIGHT, 0.004, rz * 1.06, rz * 1.06, 9, WOOD_DARK.darkened(0.2), false)
	b.cylinder(Vector3(w * 0.18, r * 1.6, 0.0), Vector3(0.4, 1.0, 0.0), 0.008, 0.003, 0.0015, 5, WOOD_DARK)
	b.sphere(Vector3(-w * 0.25, r * 1.85, 0.0), 0.004, MOSS, 2, 5)
	return b.commit()


## A red-and-white striped barrier plank on two legs with a clear gap
## underneath (EITHER: jump over it or slide under it).
static func barrier(depth: float) -> ArrayMesh:
	var b := Builder.new()
	var w: float = MageTrack.LANE_PITCH * 0.88
	var d: float = clampf(depth * 0.5, 0.004, 0.008)
	var lo: float = MageTrack.BARRIER_BASE
	var hi: float = MageTrack.BARRIER_TOP
	# A-frame legs at the lane edges (outside the wizard's body).
	for side: float in [-1.0, 1.0]:
		var x: float = side * (w * 0.5 - 0.003)
		b.box(Vector3(x, hi * 0.5, -d * 0.8), Vector3(0.005, hi, 0.004), WOOD_DARK, Basis(Vector3.RIGHT, 0.25))
		b.box(Vector3(x, hi * 0.5, d * 0.8), Vector3(0.005, hi, 0.004), WOOD_DARK, Basis(Vector3.RIGHT, -0.25))
		b.box(Vector3(x, 0.002, 0.0), Vector3(0.007, 0.004, d * 3.0), IRON)
	# The striped plank (red / white diagonal blocks) and a lantern.
	var stripes: int = 6
	var sw: float = w / float(stripes)
	for i: int in stripes:
		var col: Color = BARRIER_RED if i % 2 == 0 else WHITE
		b.box(Vector3(-w * 0.5 + sw * (float(i) + 0.5), (lo + hi) * 0.5, 0.0), Vector3(sw * 1.01, hi - lo, d), col)
	b.box(Vector3(0, hi + 0.0015, 0.0), Vector3(w * 1.02, 0.003, d * 1.1), WOOD_DARK)
	b.sphere(Vector3(0, hi + 0.006, 0.0), 0.004, GOLD.lightened(0.2), 2, 6)
	return b.commit()


## A tall stone wall block with battlements (DODGE: too high to jump, nothing
## to slide under).
static func wall(depth: float) -> ArrayMesh:
	var b := Builder.new()
	var w: float = MageTrack.LANE_PITCH * 0.9
	var top: float = MageTrack.WALL_TOP
	var h: float = top - 0.012
	b.box(Vector3(0, h * 0.5, 0), Vector3(w, h, depth), STONE, Basis(), STONE.lightened(0.05))
	# Mortar courses and offset stones on the faces.
	var courses: int = 5
	for c: int in courses:
		var y: float = h * (float(c) + 0.5) / float(courses)
		b.box(Vector3(0, y + h / float(courses) * 0.5, 0), Vector3(w * 1.01, 0.0012, depth * 1.01), STONE_DARK)
		var off: float = 0.25 if c % 2 == 0 else -0.25
		b.box(Vector3(w * off * 0.5, y, 0), Vector3(0.0012, h / float(courses) * 0.9, depth * 1.012), STONE_DARK)
	# Battlements.
	for i: int in 3:
		var x: float = -w * 0.36 + w * 0.36 * float(i)
		b.box(Vector3(x, h + 0.006, 0), Vector3(w * 0.2, 0.012, depth * 0.9), STONE, Basis(), STONE.lightened(0.08))
	# A blue banner hanging on the front face.
	b.box(Vector3(0, h * 0.62, depth * 0.5 + 0.0012), Vector3(w * 0.34, h * 0.5, 0.0015), ROYAL_BLUE)
	b.star(Vector3(0, h * 0.7, depth * 0.5 + 0.0025), 0.007, 0.003, 0.001, GOLD)
	b.box(Vector3(0, h * 0.62, -depth * 0.5 - 0.0012), Vector3(w * 0.34, h * 0.5, 0.0015), ROYAL_BLUE)
	return b.commit()


## A rope-bound stack of crates filling `lanes` lanes and `depth` (change lane).
static func crates(depth: float, lane_count: int = 1) -> ArrayMesh:
	var b := Builder.new()
	var w: float = MageTrack.LANE_PITCH * (float(lane_count) - 0.16)
	var cols: int = maxi(1, roundi(w / 0.032))
	var rows: int = maxi(1, roundi(depth / 0.034))
	var cw: float = w / float(cols)
	var cd: float = depth / float(rows)
	var ch: float = MageTrack.CRATE_TOP * 0.5
	for r: int in rows:
		for c: int in cols:
			var levels: int = 2 if (r + c) % 3 != 2 else 1
			if r == 0 or r == rows - 1:
				levels = 2
			for l: int in levels:
				var center := Vector3(-w * 0.5 + cw * (float(c) + 0.5), ch * (float(l) + 0.5), -depth * 0.5 + cd * (float(r) + 0.5))
				var tint: Color = WOOD.lerp(WOOD_LIGHT, float((r * 7 + c * 3 + l * 5) % 4) / 6.0)
				b.box(center, Vector3(cw * 0.94, ch * 0.96, cd * 0.94), tint)
				# Plank bands on the faces.
				b.box(center, Vector3(cw * 0.97, ch * 0.14, cd * 0.97), WOOD_DARK)
	# Ropes over the stack.
	for side: float in [-0.25, 0.25]:
		b.box(Vector3(0, MageTrack.CRATE_TOP * 0.995, depth * side), Vector3(w * 1.01, 0.002, 0.003), ROPE)
	return b.commit()


## A barrel mine-cart on a short rail stretch (change lane; it rolls at you).
static func cart(depth: float) -> ArrayMesh:
	var b := Builder.new()
	var w: float = MageTrack.LANE_PITCH * 0.78
	# Rails.
	for side: float in [-1.0, 1.0]:
		b.box(Vector3(side * w * 0.36, 0.0015, 0.0), Vector3(0.003, 0.003, depth), IRON)
	# Body.
	var body_bottom: float = 0.014
	var body_h: float = 0.03
	b.box(Vector3(0, body_bottom + body_h * 0.5, 0), Vector3(w, body_h, depth * 0.92), WOOD_DARK, Basis(), WOOD)
	b.box(Vector3(0, body_bottom + body_h * 0.95, 0), Vector3(w * 1.04, 0.004, depth * 0.95), IRON)
	b.box(Vector3(0, body_bottom + body_h * 0.2, 0), Vector3(w * 1.03, 0.004, depth * 0.94), IRON)
	# Wheels.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-0.32, 0.32]:
			b.cylinder(Vector3(sx * w * 0.52, 0.009, depth * sz), Vector3(sx, 0, 0), 0.004, 0.009, 0.009, 8, IRON)
	# Barrels standing in the cart, up to CART_TOP.
	var bh: float = MageTrack.CART_TOP - (body_bottom + body_h * 0.6)
	var n: int = clampi(roundi(depth / 0.03), 2, 3)
	for i: int in n:
		var z: float = -depth * 0.42 + depth * 0.84 * (float(i) + 0.5) / float(n)
		for sx: float in [-0.22, 0.22]:
			var base := Vector3(sx * w, body_bottom + body_h * 0.6, z)
			b.cylinder(base, Vector3.UP, bh * 0.5, 0.010, 0.0125, 8, WOOD.lerp(WOOD_LIGHT, 0.3 * float(i % 2)), true)
			b.cylinder(base + Vector3(0, bh * 0.5, 0), Vector3.UP, bh * 0.5, 0.0125, 0.010, 8, WOOD.lerp(WOOD_LIGHT, 0.3 * float(i % 2)), true, WOOD_LIGHT)
			b.cylinder(base + Vector3(0, bh * 0.48, 0), Vector3.UP, 0.003, 0.0128, 0.0128, 8, IRON, false)
	return b.commit()


## A gold and white royal carriage over two lanes; its flat gold roof is
## walkable (jump onto it) at CARRIAGE_ROOF.
static func carriage(depth: float) -> ArrayMesh:
	var b := Builder.new()
	var w: float = MageTrack.LANE_PITCH * 1.84
	var roof: float = MageTrack.CARRIAGE_ROOF
	var bottom: float = 0.018
	b.box(Vector3(0, (roof + bottom) * 0.5 - 0.002, 0), Vector3(w * 0.9, roof - bottom - 0.004, depth * 0.86), WHITE)
	b.box(Vector3(0, roof - 0.003, 0), Vector3(w * 0.96, 0.006, depth * 0.92), GOLD)
	b.box(Vector3(0, bottom + 0.003, 0), Vector3(w * 0.94, 0.006, depth * 0.9), GOLD)
	# Windows and gold trim stripes on the sides.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-0.2, 0.2]:
			b.box(Vector3(sx * w * 0.451, (roof + bottom) * 0.52, depth * sz), Vector3(0.002, 0.022, depth * 0.22), Color(0.3, 0.45, 0.7))
		b.box(Vector3(sx * w * 0.452, bottom + 0.02, 0), Vector3(0.002, 0.003, depth * 0.84), GOLD)
	# Wheels.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-0.34, 0.34]:
			b.cylinder(Vector3(sx * w * 0.46, 0.013, depth * sz), Vector3(sx, 0, 0), 0.004, 0.013, 0.013, 10, GOLD.darkened(0.2), true, WOOD_DARK)
	# Blue crystals at the roof corners.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var c := Vector3(sx * w * 0.43, roof + 0.004, sz * depth * 0.41)
			b.cylinder(c, Vector3.UP, 0.007, 0.004, 0.0, 5, CRYSTAL)
			b.cylinder(c, Vector3.DOWN, 0.003, 0.004, 0.0, 5, CRYSTAL.darkened(0.2))
	return b.commit()


# --- Scenery ------------------------------------------------------------------------

## The diorama base: a rounded stone slab (below y = 0 in the world node,
## which sits BASE_HEIGHT up) with moss edges and grass beside the road.
static func base(width: float, length: float, base_height: float, road_width: float) -> ArrayMesh:
	var b := Builder.new()
	var hw: float = width * 0.5
	b.box(Vector3(0, -base_height * 0.5 - 0.0005, 0), Vector3(width - 0.008, base_height - 0.001, length - 0.008), STONE_DARK, Basis(), STONE)
	b.box(Vector3(0, -base_height * 0.5, 0), Vector3(width - 0.016, base_height, length), STONE_DARK, Basis(), STONE)
	b.box(Vector3(0, -base_height * 0.5, 0), Vector3(width, base_height * 0.7, length - 0.016), STONE_DARK, Basis(), STONE)
	# Grass strips beside the road, with a moss lip.
	for sx: float in [-1.0, 1.0]:
		var gx: float = sx * (road_width * 0.5 + (hw - road_width * 0.5) * 0.5)
		b.box(Vector3(gx, 0.0008, 0.0), Vector3(hw - road_width * 0.5 - 0.006, 0.0016, length - 0.01), GRASS)
		b.box(Vector3(sx * (hw - 0.004), -0.001, 0.0), Vector3(0.006, 0.003, length - 0.012), MOSS)
		# Little stones and tufts along the verge.
		for i: int in 20:
			var z: float = -length * 0.5 + 0.02 + (length - 0.04) * float(i) / 19.0
			var off: float = 0.004 * sin(float(i) * 2.3)
			if i % 3 == 0:
				b.box(Vector3(gx + off, 0.0025, z), Vector3(0.006, 0.003, 0.005), STONE.darkened(0.1))
			else:
				b.cylinder(Vector3(gx - off, 0.001, z + 0.01), Vector3.UP, 0.006, 0.0025, 0.0, 4, MOSS.lightened(0.15), false)
	return b.commit()


# --- The wizard ---------------------------------------------------------------------

## The wizard: blue robe, dark blue pointy hat with gold stars, white beard,
## staff. About 0.06 m tall to the hat brim (0.074 to the tip), facing -z.
## Returns {"body": mesh, "tip": mesh (the staff's glowing tip)}.
static func wizard() -> Dictionary:
	var b := Builder.new()
	# Robe (a cone frustum) with a darker hem, sleeves.
	b.cylinder(Vector3(0, 0.0, 0), Vector3.UP, 0.004, 0.0165, 0.016, 10, ROBE_DARK, true)
	b.cylinder(Vector3(0, 0.004, 0), Vector3.UP, 0.036, 0.016, 0.0065, 10, ROBE, false)
	b.box(Vector3(0, 0.022, 0.0), Vector3(0.026, 0.003, 0.02), GOLD.darkened(0.1))
	for sx: float in [-1.0, 1.0]:
		b.cylinder(Vector3(sx * 0.006, 0.036, 0), Vector3(sx * 0.6, -0.8, -0.2), 0.016, 0.0035, 0.005, 6, ROBE.darkened(0.05))
		b.sphere(Vector3(sx * 0.0155, 0.0225, -0.004), 0.0028, SKIN, 3, 6)
	# Head and beard.
	b.sphere(Vector3(0, 0.0455, 0), 0.0072, SKIN, 4, 8)
	b.cylinder(Vector3(0, 0.044, -0.004), Vector3(0, -1.0, -0.25), 0.017, 0.0068, 0.0, 8, BEARD, false)
	for sx: float in [-1.0, 1.0]:
		b.sphere(Vector3(sx * 0.0058, 0.043, 0.0), 0.0035, BEARD, 3, 6)
	# Hat: brim, cone (tip bent back a little), gold stars.
	b.cylinder(Vector3(0, 0.0505, 0), Vector3.UP, 0.0018, 0.0135, 0.0135, 12, HAT)
	b.cylinder(Vector3(0, 0.052, 0), Vector3(0, 1.0, 0.18), 0.022, 0.0088, 0.0, 10, HAT, false)
	var stars: Array[Vector3] = [Vector3(0.0, 0.058, 0.0078), Vector3(-0.0055, 0.0545, 0.0062), Vector3(0.0058, 0.061, 0.005), Vector3(0.0, 0.066, 0.0065), Vector3(-0.004, 0.06, -0.0068), Vector3(0.006, 0.055, -0.006)]
	for p: Vector3 in stars:
		var n := Vector3(p.x, 0.0, p.z).normalized()
		var basis := Basis.looking_at(-n, Vector3.UP)
		b.star(p + n * 0.0008, 0.0022, 0.001, 0.0006, GOLD, basis)
	b.star(Vector3(0, 0.0512, 0.0136), 0.0018, 0.0008, 0.0005, GOLD)
	# Staff in the right hand.
	b.cylinder(Vector3(0.0165, 0.003, -0.006), Vector3(0.05, 1.0, 0.0), 0.06, 0.0012, 0.0011, 5, WOOD_DARK)
	b.cylinder(Vector3(0.0195, 0.06, -0.006), Vector3.UP, 0.003, 0.0022, 0.0028, 5, GOLD)
	var tip := Builder.new()
	tip.sphere(Vector3(0.0197, 0.0655, -0.006), 0.0036, Color(0.55, 0.9, 1.0), 4, 8)
	return {"body": b.commit(), "tip": tip.commit(), "triangles": b.triangle_count() + tip.triangle_count()}


# --- Coins, tiles, ramps --------------------------------------------------------------

## A gold star coin, about 0.02 m across, standing up (faces +z).
static func coin() -> ArrayMesh:
	var b := Builder.new()
	b.star(Vector3.ZERO, MageTrack.COIN_RADIUS, MageTrack.COIN_RADIUS * 0.48, 0.003, GOLD)
	b.star(Vector3(0, 0, 0.0016), MageTrack.COIN_RADIUS * 0.5, MageTrack.COIN_RADIUS * 0.24, 0.0005, GOLD.lightened(0.35))
	b.star(Vector3(0, 0, -0.0016), MageTrack.COIN_RADIUS * 0.5, MageTrack.COIN_RADIUS * 0.24, 0.0005, GOLD.lightened(0.35))
	return b.commit()


## A unit tile slab: x, z in [-0.5, 0.5], y in [-1, 0] (top at 0). Scaled per
## instance to (tile width, TILE_THICKNESS, length).
static func tile_unit() -> ArrayMesh:
	var b := Builder.new()
	b.box(Vector3(0, -0.5, 0), Vector3(1, 1, 1), Color.WHITE)
	return b.commit()


## A unit ramp: rises from y = 0 at z = +0.5 (near, start) to y = 1 at
## z = -0.5 (far, top), TILE_THICKNESS / ROW_HEIGHT thick. Scaled per
## instance to (width, ROW_HEIGHT, length).
static func ramp_unit() -> ArrayMesh:
	var b := Builder.new()
	var t: float = MageTrack.TILE_THICKNESS / MageTrack.ROW_HEIGHT
	var a := Vector3(-0.5, 0.0, 0.5)
	var c := Vector3(0.5, 0.0, 0.5)
	var e := Vector3(-0.5, 1.0, -0.5)
	var g := Vector3(0.5, 1.0, -0.5)
	var dn := Vector3(0, -t, 0)
	b.quad(a, c, g, e, Color.WHITE)
	b.quad(a + dn, e + dn, g + dn, c + dn, Color.WHITE)
	b.quad(a, a + dn, e + dn, e, Color.WHITE)
	b.quad(c, g, g + dn, c + dn, Color.WHITE)
	b.quad(a, c, c + dn, a + dn, Color.WHITE)
	b.quad(e, e + dn, g + dn, g, Color.WHITE)
	return b.commit()
