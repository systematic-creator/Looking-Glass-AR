class_name CDMeshes
extends RefCounted
## Procedural low-poly meshes for Crystal Defense, in the storybook-diorama
## look: vertex-coloured primitives merged into one mesh per object (one draw
## call each). Sizes are in CELLS (1 = one board cell); the game scales the
## nodes by the cell size in metres.

const STONE := Color(0.56, 0.58, 0.62)
const STONE_DARK := Color(0.38, 0.4, 0.45)
const WOOD := Color(0.45, 0.3, 0.18)
const WOOD_DARK := Color(0.3, 0.2, 0.12)
const ROOF_BLUE := Color(0.18, 0.3, 0.62)
const GOLD := Color(0.95, 0.78, 0.3)
const IRON := Color(0.2, 0.21, 0.24)
const CYAN := Color(0.45, 0.95, 1.0)
const CHALK := Color(0.93, 0.92, 0.88)
const CLAW := Color(0.08, 0.07, 0.08)
const MOSS := Color(0.2, 0.3, 0.26)
const BARK := Color(0.72, 0.7, 0.66)

static var _cache: Dictionary = {}


static func lit_material() -> StandardMaterial3D:
	if _cache.has("lit"):
		return _cache["lit"]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	m.metallic_specular = 0.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache["lit"] = m
	return m


# --- Primitive builders (append to a SurfaceTool) ------------------------------------

static func box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color, basis: Basis = Basis()) -> void:
	var h: Vector3 = size * 0.5
	var faces: Array = [
		[Vector3(1, 0, 0), [Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(1, -1, 1)]],
		[Vector3(-1, 0, 0), [Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1), Vector3(-1, -1, -1)]],
		[Vector3(0, 1, 0), [Vector3(-1, 1, -1), Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1)]],
		[Vector3(0, -1, 0), [Vector3(-1, -1, 1), Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1)]],
		[Vector3(0, 0, 1), [Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1), Vector3(-1, -1, 1)]],
		[Vector3(0, 0, -1), [Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, -1, -1)]],
	]
	for f: Array in faces:
		var n: Vector3 = basis * (f[0] as Vector3)
		var q: Array = f[1]
		var shade: float = 0.82 + 0.18 * maxf(0.0, n.y) - 0.06 * absf(n.x)
		var col := Color(color.r * shade, color.g * shade, color.b * shade, color.a)
		var v: Array[Vector3] = []
		for corner: Vector3 in q:
			v.append(center + basis * (corner * h))
		for idx: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_normal(n)
			st.add_vertex(v[idx])


## A (possibly tapered) prism along +Y from `base`, `sides` sided.
static func cylinder(st: SurfaceTool, base: Vector3, radius: float, height: float, color: Color, sides: int = 8, top_radius: float = -1.0, basis: Basis = Basis(), cap: bool = true) -> void:
	var tr: float = radius if top_radius < 0.0 else top_radius
	for i: int in sides:
		var a0: float = TAU * i / sides
		var a1: float = TAU * (i + 1) / sides
		var b0 := Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var b1 := Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		var t0 := Vector3(cos(a0) * tr, height, sin(a0) * tr)
		var t1 := Vector3(cos(a1) * tr, height, sin(a1) * tr)
		var n: Vector3 = basis * Vector3(cos((a0 + a1) * 0.5), (radius - tr) / maxf(0.001, height), sin((a0 + a1) * 0.5)).normalized()
		var shade: float = 0.8 + 0.2 * (0.5 + 0.5 * cos((a0 + a1) * 0.5 - 0.8))
		var col := Color(color.r * shade, color.g * shade, color.b * shade, color.a)
		for v: Vector3 in [b0, t1, t0, b0, b1, t1]:
			st.set_color(col)
			st.set_normal(n)
			st.add_vertex(base + basis * v)
		if cap and tr > 0.0001:
			for v: Vector3 in [Vector3(0, height, 0), t0, t1]:
				st.set_color(color)
				st.set_normal(basis * Vector3.UP)
				st.add_vertex(base + basis * v)


static func cone(st: SurfaceTool, base: Vector3, radius: float, height: float, color: Color, sides: int = 8, basis: Basis = Basis()) -> void:
	cylinder(st, base, radius, height, color, sides, 0.0, basis, false)


## Low-poly ellipsoid (UV sphere, `rings` x `segs`).
static func ellipsoid(st: SurfaceTool, center: Vector3, radii: Vector3, color: Color, rings: int = 5, segs: int = 8) -> void:
	for r: int in rings:
		var p0: float = PI * r / rings
		var p1: float = PI * (r + 1) / rings
		for s: int in segs:
			var a0: float = TAU * s / segs
			var a1: float = TAU * (s + 1) / segs
			var pts: Array[Vector3] = [
				Vector3(sin(p0) * cos(a0), cos(p0), sin(p0) * sin(a0)),
				Vector3(sin(p0) * cos(a1), cos(p0), sin(p0) * sin(a1)),
				Vector3(sin(p1) * cos(a1), cos(p1), sin(p1) * sin(a1)),
				Vector3(sin(p1) * cos(a0), cos(p1), sin(p1) * sin(a0)),
			]
			for idx: int in [0, 2, 1, 0, 3, 2]:
				var u: Vector3 = pts[idx]
				var shade: float = 0.78 + 0.22 * (0.5 + 0.5 * u.y)
				st.set_color(Color(color.r * shade, color.g * shade, color.b * shade, color.a))
				st.set_normal(u)
				st.add_vertex(center + u * radii)


## A limb: a thin prism from a to b.
static func limb(st: SurfaceTool, a: Vector3, b: Vector3, radius: float, color: Color, sides: int = 5, end_radius: float = -1.0) -> void:
	var dir: Vector3 = b - a
	var length: float = dir.length()
	if length < 0.00001:
		return
	var y: Vector3 = dir / length
	var x: Vector3 = y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z: Vector3 = x.cross(y)
	cylinder(st, a, radius, length, color, sides, end_radius, Basis(x, y, z), true)


static func commit(st: SurfaceTool) -> ArrayMesh:
	var mesh: ArrayMesh = st.commit()
	return mesh


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


# --- Structures ---------------------------------------------------------------------

static func structure_mesh(type: StringName, level: int) -> ArrayMesh:
	var key: String = "%s_%d" % [type, level]
	if _cache.has(key):
		return _cache[key]
	var st: SurfaceTool = _begin()
	match type:
		&"arrow":
			_arrow_tower(st, level)
		&"bombard":
			_bombard(st, level)
		&"palisade":
			_palisade(st, level)
		&"stone_wall":
			_stone_wall(st, level)
		_:
			box(st, Vector3(0, 0.3, 0), Vector3(0.6, 0.6, 0.6), STONE)
	var mesh: ArrayMesh = commit(st)
	mesh.surface_set_material(0, lit_material())
	_cache[key] = mesh
	return mesh


static func _arrow_tower(st: SurfaceTool, level: int) -> void:
	var h: float = 0.95 + 0.12 * (level - 1)
	cylinder(st, Vector3.ZERO, 0.34, 0.12, STONE_DARK, 8)
	cylinder(st, Vector3(0, 0.12, 0), 0.28, h - 0.12, STONE, 8, 0.25)
	# Battlement platform with merlons.
	cylinder(st, Vector3(0, h, 0), 0.34, 0.08, STONE_DARK, 8)
	for i: int in 6:
		var a: float = TAU * i / 6.0
		box(st, Vector3(cos(a) * 0.29, h + 0.13, sin(a) * 0.29), Vector3(0.1, 0.1, 0.1), STONE)
	# Pointed roof.
	cylinder(st, Vector3(0, h + 0.08, 0), 0.03, 0.12, WOOD_DARK, 4)
	cone(st, Vector3(0, h + 0.2, 0), 0.36, 0.42, ROOF_BLUE, 8)
	# Arrow slit.
	box(st, Vector3(0, h * 0.62, 0.255), Vector3(0.05, 0.16, 0.03), IRON)
	if level >= 2:
		box(st, Vector3(0.0, h * 0.45, 0.27), Vector3(0.16, 0.24, 0.02), ROOF_BLUE)
		box(st, Vector3(0.0, h * 0.45 - 0.13, 0.272), Vector3(0.16, 0.03, 0.02), GOLD)
	if level >= 3:
		var tip := Vector3(0, h + 0.62, 0)
		cone(st, tip, 0.07, 0.18, CYAN, 6)
		cone(st, tip, 0.07, -0.08, CYAN, 6)


static func _bombard(st: SurfaceTool, level: int) -> void:
	cylinder(st, Vector3.ZERO, 0.4, 0.1, STONE_DARK, 10)
	cylinder(st, Vector3(0, 0.1, 0), 0.36, 0.3, STONE, 10, 0.33)
	cylinder(st, Vector3(0, 0.4, 0), 0.38, 0.05, STONE_DARK, 10)
	var r: float = 0.13 + 0.02 * (level - 1)
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(-55.0))
	cylinder(st, Vector3(0, 0.42, 0.06), r, 0.42, IRON, 8, r * 1.15, tilt)
	cylinder(st, Vector3(0, 0.42, 0.06) + tilt * Vector3(0, 0.42, 0), r * 1.25, 0.05, IRON, 8, r * 1.25, tilt)
	box(st, Vector3(0, 0.47, -0.12), Vector3(0.36, 0.1, 0.22), WOOD)
	if level >= 2:
		cylinder(st, Vector3(0, 0.2, 0), 0.37, 0.04, IRON, 10)
	if level >= 3:
		cylinder(st, Vector3(0, 0.32, 0), 0.355, 0.04, GOLD, 10)
		ellipsoid(st, Vector3(0.24, 0.5, -0.2), Vector3(0.07, 0.07, 0.07), IRON, 3, 6)


static func _palisade(st: SurfaceTool, level: int) -> void:
	var h: float = [0.55, 0.72, 0.78][clampi(level - 1, 0, 2)]
	box(st, Vector3(0, 0.03, 0), Vector3(0.94, 0.06, 0.94), WOOD_DARK)
	for row: int in 2:
		var z: float = -0.2 + 0.4 * row
		for k: int in 5:
			var x: float = -0.38 + 0.19 * k
			var hh: float = h * (0.9 + 0.1 * ((k + row) % 2))
			cylinder(st, Vector3(x, 0.05, z), 0.075, hh, WOOD, 5)
			cone(st, Vector3(x, 0.05 + hh, z), 0.075, 0.12, WOOD_DARK, 5)
	box(st, Vector3(0, h * 0.55, -0.2), Vector3(0.92, 0.06, 0.06), WOOD_DARK)
	box(st, Vector3(0, h * 0.55, 0.2), Vector3(0.92, 0.06, 0.06), WOOD_DARK)
	if level >= 3:
		for x: float in [-0.4, 0.4]:
			limb(st, Vector3(x, 0.05, 0.42), Vector3(x, h * 0.75, 0.2), 0.04, WOOD_DARK)
			limb(st, Vector3(x, 0.05, -0.42), Vector3(x, h * 0.75, -0.2), 0.04, WOOD_DARK)


static func _stone_wall(st: SurfaceTool, level: int) -> void:
	var h: float = [0.5, 0.65, 0.8][clampi(level - 1, 0, 2)]
	box(st, Vector3(0, h * 0.5, 0), Vector3(0.94, h, 0.94), STONE)
	# Courses of darker stone.
	for k: int in int(h / 0.18):
		box(st, Vector3(0, 0.12 + k * 0.18, 0), Vector3(0.955, 0.025, 0.955), STONE_DARK)
	for i: int in 3:
		for j: int in 3:
			if (i + j) % 2 == 0:
				box(st, Vector3(-0.31 + 0.31 * i, h + 0.06, -0.31 + 0.31 * j), Vector3(0.22, 0.12, 0.22), STONE)
	if level >= 3:
		for x: float in [-0.5, 0.5]:
			box(st, Vector3(x * 0.92, h * 0.35, 0), Vector3(0.12, h * 0.7, 0.4), STONE_DARK)


# --- Enemies and units --------------------------------------------------------------

## Pale Stalker: gaunt chalk-white Cryptid with a blank egg head, ribbed torso,
## very long arms ending in black hooked claws, long thin legs. ~0.7 cells.
static func stalker_mesh() -> ArrayMesh:
	if _cache.has("stalker"):
		return _cache["stalker"]
	var st: SurfaceTool = _begin()
	var hip := Vector3(0, 0.3, 0)
	var chest := Vector3(0, 0.52, -0.06)
	# Legs (long, thin, slightly bent).
	for sx: float in [-1.0, 1.0]:
		var knee := Vector3(0.06 * sx, 0.16, -0.03)
		limb(st, Vector3(0.05 * sx, 0.3, 0), knee, 0.022, CHALK)
		limb(st, knee, Vector3(0.07 * sx, 0.0, 0.02), 0.018, CHALK)
		box(st, Vector3(0.07 * sx, 0.008, 0.035), Vector3(0.04, 0.016, 0.07), CHALK)
	# Torso: narrow, hunched forward, with ribs.
	limb(st, hip, chest, 0.06, CHALK, 6, 0.075)
	for k: int in 3:
		var y: float = 0.4 + 0.04 * k
		box(st, Vector3(0, y, -0.03 - 0.012 * k), Vector3(0.15, 0.012, 0.12), Color(0.8, 0.79, 0.76))
	# Neck + big blank egg head (no face).
	limb(st, chest, chest + Vector3(0, 0.07, -0.05), 0.022, CHALK)
	ellipsoid(st, chest + Vector3(0, 0.14, -0.09), Vector3(0.075, 0.1, 0.085), CHALK, 6, 10)
	# Arms: very long, hanging to the ankles, with hooked claws.
	for sx: float in [-1.0, 1.0]:
		var sh := chest + Vector3(0.09 * sx, 0.02, 0)
		var el := Vector3(0.15 * sx, 0.3, -0.08)
		var wr := Vector3(0.14 * sx, 0.08, -0.1)
		limb(st, sh, el, 0.02, CHALK)
		limb(st, el, wr, 0.016, CHALK)
		for f: int in 3:
			var off := Vector3((f - 1) * 0.018, 0, 0)
			limb(st, wr + off, wr + off + Vector3(0.0, -0.06, -0.04), 0.008, CLAW, 4, 0.002)
	var mesh: ArrayMesh = commit(st)
	mesh.surface_set_material(0, lit_material())
	_cache["stalker"] = mesh
	return mesh


## Knight / Paladin / Lightguard miniature (~0.45 cells).
static func knight_mesh(rank: int) -> ArrayMesh:
	var key: String = "knight_%d" % rank
	if _cache.has(key):
		return _cache[key]
	var armor: Color = [Color(0.66, 0.69, 0.75), GOLD, Color(0.96, 0.95, 0.88)][clampi(rank, 0, 2)]
	var trim: Color = [ROOF_BLUE, Color(0.95, 0.95, 1.0), CYAN][clampi(rank, 0, 2)]
	var s: float = [1.0, 1.25, 1.45][clampi(rank, 0, 2)]
	var st: SurfaceTool = _begin()
	for sx: float in [-1.0, 1.0]:
		cylinder(st, Vector3(0.05 * sx, 0, 0) * s, 0.035 * s, 0.17 * s, armor, 6)
	cylinder(st, Vector3(0, 0.16, 0) * s, 0.085 * s, 0.17 * s, armor, 8, 0.075 * s)
	box(st, Vector3(0, 0.25, -0.075) * s, Vector3(0.1, 0.14, 0.02) * s, trim)
	ellipsoid(st, Vector3(0, 0.39, 0) * s, Vector3(0.065, 0.07, 0.065) * s, armor, 4, 8)
	box(st, Vector3(0, 0.395, -0.06) * s, Vector3(0.08, 0.015, 0.02) * s, IRON)
	cone(st, Vector3(0, 0.45, 0) * s, 0.02 * s, 0.06 * s, trim, 4)
	# Shield (left) and sword (right, forward = -Z).
	box(st, Vector3(-0.1, 0.24, -0.03) * s, Vector3(0.02, 0.14, 0.11) * s, trim)
	limb(st, Vector3(0.1, 0.2, -0.02) * s, Vector3(0.12, 0.42, -0.12) * s, 0.01 * s, Color(0.85, 0.88, 0.95), 4)
	box(st, Vector3(0.1, 0.21, -0.02) * s, Vector3(0.07, 0.015, 0.02) * s, GOLD)
	var mesh: ArrayMesh = commit(st)
	mesh.surface_set_material(0, lit_material())
	_cache[key] = mesh
	return mesh


# --- World ---------------------------------------------------------------------------

## Dead pale tree for terrain cells (~1.1 cells tall).
static func dead_tree(st: SurfaceTool, at: Vector3, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var top := at + Vector3(rng.randf_range(-0.05, 0.05), 0.75, rng.randf_range(-0.05, 0.05))
	limb(st, at, top, 0.09, BARK, 6, 0.05)
	for k: int in 4:
		var a: float = TAU * k / 4.0 + rng.randf() * 0.8
		var from: Vector3 = at.lerp(top, 0.45 + 0.15 * k)
		var to: Vector3 = from + Vector3(cos(a) * 0.3, 0.25 + rng.randf() * 0.15, sin(a) * 0.3)
		limb(st, from, to, 0.035, BARK, 4, 0.01)
		limb(st, to, to + Vector3(cos(a + 0.7) * 0.12, 0.12, sin(a + 0.7) * 0.12), 0.015, BARK, 3, 0.004)
	cylinder(st, at, 0.16, 0.05, MOSS, 6, 0.1)


static func standing_stone(st: SurfaceTool, at: Vector3, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.03, 0.12))
	box(st, at + Vector3(0, 0.38, 0), Vector3(0.36, 0.76, 0.24), Color(0.5, 0.52, 0.56), tilt)
	box(st, at + Vector3(0, 0.03, 0), Vector3(0.5, 0.06, 0.4), MOSS)


## Crystal gem (purple, faceted, elongated bipyramid + 2 shards), in cells.
static func crystal_mesh(height: float, radius: float) -> ArrayMesh:
	var st: SurfaceTool = _begin()
	_gem(st, Vector3.ZERO, height, radius, 8, Basis())
	_gem(st, Vector3(radius * 0.9, 0.0, radius * 0.2), height * 0.45, radius * 0.4, 6, Basis(Vector3.FORWARD, deg_to_rad(-24)))
	_gem(st, Vector3(-radius * 0.8, 0.0, -radius * 0.35), height * 0.38, radius * 0.35, 6, Basis(Vector3(1, 0, 0.6).normalized(), deg_to_rad(22)))
	return st.commit()


static func _gem(st: SurfaceTool, base: Vector3, height: float, radius: float, sides: int, basis: Basis) -> void:
	var waist: float = height * 0.3
	var bottom := Vector3(0, 0, 0)
	var top := Vector3(0, height, 0)
	for i: int in sides:
		var a0: float = TAU * i / sides
		var a1: float = TAU * (i + 1) / sides
		var w0 := Vector3(cos(a0) * radius, waist, sin(a0) * radius)
		var w1 := Vector3(cos(a1) * radius, waist, sin(a1) * radius)
		var s0 := Vector3(cos(a0) * radius * 0.82, height * 0.72, sin(a0) * radius * 0.82)
		var s1 := Vector3(cos(a1) * radius * 0.82, height * 0.72, sin(a1) * radius * 0.82)
		for tri: Array in [[bottom, w1, w0], [w0, w1, s1], [w0, s1, s0], [s0, s1, top]]:
			var p0: Vector3 = base + basis * (tri[0] as Vector3)
			var p1: Vector3 = base + basis * (tri[1] as Vector3)
			var p2: Vector3 = base + basis * (tri[2] as Vector3)
			var n: Vector3 = (p2 - p0).cross(p1 - p0).normalized()
			var facet: float = 0.75 + 0.25 * float((i * 7) % 3) / 2.0
			for p: Vector3 in [p0, p1, p2]:
				st.set_color(Color(facet, facet, facet, 1.0))
				st.set_normal(n)
				st.add_vertex(p)


## The diorama ground: 12x12 cells of mossy night grass with slight variation.
static func ground_mesh(grid: BoardGrid) -> ArrayMesh:
	var st: SurfaceTool = _begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for j: int in grid.ny:
		for i: int in grid.nx:
			var v: float = rng.randf_range(-0.03, 0.03)
			var col := Color(0.2 + v, 0.29 + v * 1.4, 0.25 + v)
			if (i + j) % 2 == 0:
				col = col.lightened(0.04)
			var a := Vector3(i, 0, j)
			for p: Vector3 in [a, a + Vector3(1, 0, 0), a + Vector3(1, 0, 1), a, a + Vector3(1, 0, 1), a + Vector3(0, 0, 1)]:
				st.set_color(col)
				st.set_normal(Vector3.UP)
				st.add_vertex(p)
	var mesh: ArrayMesh = st.commit()
	mesh.surface_set_material(0, lit_material())
	return mesh
