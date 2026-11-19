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


static var _solid: StandardMaterial3D
static var _glow: StandardMaterial3D


## The shared solid material: vertex colours, softly lit, double-sided.
static func solid_material() -> StandardMaterial3D:
	if _solid == null:
		_solid = StandardMaterial3D.new()
		_solid.vertex_color_use_as_albedo = true
		_solid.roughness = 0.85
		_solid.cull_mode = BaseMaterial3D.CULL_DISABLED
		_solid.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	return _solid


## Unshaded vertex-colour glow (staff tip, crystals, coins' sparkle).
static func glow_material() -> StandardMaterial3D:
	if _glow == null:
		_glow = StandardMaterial3D.new()
		_glow.vertex_color_use_as_albedo = true
		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow.cull_mode = BaseMaterial3D.CULL_DISABLED
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
	var n: int = maxi(2, roundi(depth / 0.03))
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

## The castle gatehouse at the far end: walls, two towers with blue-slate
## roofs, battlements; the gate opening itself is the portal (separate).
## Spans x +-0.15, z from FAR_Z to GATE_Z, y 0..~0.375.
static func castle() -> ArrayMesh:
	var b := Builder.new()
	var z0: float = MageTrack.FAR_Z + 0.002
	var z1: float = MageTrack.GATE_Z
	var depth: float = z1 - z0
	var zc: float = (z0 + z1) * 0.5
	var wall_h: float = 0.255
	var half_w: float = 0.13
	var gate_w: float = 0.118
	var gate_h: float = 0.238
	# Walls left / right of the gate and the lintel above it.
	b.box(Vector3(-(half_w + gate_w) * 0.5, wall_h * 0.5, zc), Vector3(half_w - gate_w, wall_h, depth), STONE)
	b.box(Vector3((half_w + gate_w) * 0.5, wall_h * 0.5, zc), Vector3(half_w - gate_w, wall_h, depth), STONE)
	b.box(Vector3(0, (wall_h + gate_h) * 0.5, zc), Vector3(gate_w * 2.0, wall_h - gate_h, depth), STONE)
	# The back of the gatehouse (closes the box so nothing inside shows).
	b.box(Vector3(0, gate_h * 0.5, z0 + 0.004), Vector3(gate_w * 2.0, gate_h, 0.008), STONE_DARK)
	b.box(Vector3(0, 0.002, zc), Vector3(gate_w * 2.0, 0.004, depth), STONE_DARK)
	# Battlements.
	var n: int = 9
	for i: int in n:
		var x: float = -half_w + (float(i) + 0.5) * (2.0 * half_w / float(n))
		if i % 2 == 0:
			b.box(Vector3(x, wall_h + 0.007, z1 - 0.008), Vector3(2.0 * half_w / float(n), 0.014, 0.014), STONE_DARK)
	# Stone courses on the front face.
	for k: int in 5:
		var y: float = 0.03 + float(k) * 0.05
		b.box(Vector3(-(half_w + gate_w) * 0.5, y, z1 + 0.0006), Vector3(half_w - gate_w, 0.002, 0.001), STONE_DARK)
		b.box(Vector3((half_w + gate_w) * 0.5, y, z1 + 0.0006), Vector3(half_w - gate_w, 0.002, 0.001), STONE_DARK)
	# Gate arch frame.
	b.box(Vector3(0, gate_h + 0.004, z1 + 0.002), Vector3(gate_w * 2.0 + 0.008, 0.008, 0.004), STONE_DARK)
	# Towers.
	for sx: float in [-1.0, 1.0]:
		var base := Vector3(sx * 0.126, 0.0, zc)
		b.cylinder(base, Vector3.UP, 0.29, 0.021, 0.019, 10, STONE, false)
		b.cylinder(base + Vector3(0, 0.29, 0), Vector3.UP, 0.012, 0.0225, 0.0225, 10, STONE_DARK)
		b.cylinder(base + Vector3(0, 0.302, 0), Vector3.UP, 0.058, 0.0225, 0.0, 10, SLATE)
		# Windows.
		for wy: float in [0.12, 0.2]:
			b.box(base + Vector3(0, wy, 0.021), Vector3(0.007, 0.014, 0.002), Color(0.15, 0.13, 0.2))
		# A pennant on the spire.
		var tip: Vector3 = base + Vector3(0, 0.36, 0)
		b.box(tip + Vector3(0, 0.006, 0), Vector3(0.0015, 0.012, 0.0015), WOOD_DARK)
		b.tri(tip + Vector3(0, 0.012, 0), tip + Vector3(0, 0.006, 0), tip + Vector3(sx * -0.014, 0.009, 0), ROYAL_BLUE if sx < 0 else Color(0.85, 0.2, 0.25))
	# Keep behind the gate.
	b.box(Vector3(0, 0.29, zc - 0.01), Vector3(0.09, 0.07, depth * 0.6), STONE)
	b.cylinder(Vector3(0, 0.325, zc - 0.01), Vector3.UP, 0.04, 0.045, 0.0, 4, SLATE)
	return b.commit()


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
		for i: int in 14:
			var z: float = -length * 0.5 + 0.02 + (length - 0.04) * float(i) / 13.0
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
