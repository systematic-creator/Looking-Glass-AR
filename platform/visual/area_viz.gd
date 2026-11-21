class_name AreaViz
extends RefCounted
## Hologram overlays for ranges and areas of effect, lying flat on the board:
## ring (a range edge), disc (a filled area: splash, aura), sector (a cone /
## wedge: breath, melee arc) and strip (a line along an edge: spawn warnings).
## Built in board units at the size you ask for (a game converts cells to
## metres first). One shared material per colour keeps draw state cheap; the
## meshes are flat (y = 0) so place them just above the ground.

const SEGMENTS: int = 48

static var _materials: Dictionary = {}


## Unshaded, alpha-blended, double-sided, no depth writes; tinted by vertex
## colour (and MultiMesh instance colour).
static func material(color: Color = Holo.CYAN) -> StandardMaterial3D:
	var key: String = color.to_html()
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.no_depth_test = false
	m.render_priority = 1
	_materials[key] = m
	return m


## A flat annulus from `radius - width` to `radius`.
static func ring_mesh(radius: float, width: float, color: Color = Color.WHITE, segments: int = SEGMENTS) -> ArrayMesh:
	return sector_mesh(radius, TAU, color, maxf(0.0, radius - width), segments, color)


## A filled disc, brighter at the edge (`edge` colour) than the centre.
static func disc_mesh(radius: float, center_color: Color, edge_color: Color, segments: int = SEGMENTS) -> ArrayMesh:
	return sector_mesh(radius, TAU, edge_color, 0.0, segments, center_color)


## A wedge of `angle` radians centred on board -Z (rotate the node to aim),
## from `inner` to `radius`. Colour fades from `inner_color` to `color`.
static func sector_mesh(radius: float, angle: float, color: Color = Color.WHITE, inner: float = 0.0, segments: int = SEGMENTS, inner_color: Variant = null) -> ArrayMesh:
	var ic: Color = inner_color if inner_color is Color else Color(color, color.a * 0.35)
	var steps: int = maxi(2, int(ceil(segments * angle / TAU)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var full: bool = angle >= TAU - 0.0001
	for i: int in steps:
		var a0: float = -angle * 0.5 + angle * float(i) / steps
		var a1: float = -angle * 0.5 + angle * float(i + 1) / steps
		var d0 := Vector3(sin(a0), 0.0, -cos(a0))
		var d1 := Vector3(sin(a1), 0.0, -cos(a1))
		if inner <= 0.00001:
			st.set_color(ic)
			st.add_vertex(Vector3.ZERO)
			st.set_color(color)
			st.add_vertex(d1 * radius)
			st.set_color(color)
			st.add_vertex(d0 * radius)
		else:
			st.set_color(ic)
			st.add_vertex(d0 * inner)
			st.set_color(color)
			st.add_vertex(d1 * radius)
			st.set_color(color)
			st.add_vertex(d0 * radius)
			st.set_color(ic)
			st.add_vertex(d0 * inner)
			st.set_color(ic)
			st.add_vertex(d1 * inner)
			st.set_color(color)
			st.add_vertex(d1 * radius)
	if not full and inner <= 0.00001:
		pass
	return st.commit()


## A flat strip from `a` to `b` (board space, y ignored), `width` wide.
static func strip_mesh(a: Vector3, b: Vector3, width: float, color: Color = Color.WHITE) -> ArrayMesh:
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var side := Vector3(-dir.z, 0.0, dir.x).normalized() * width * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(color)
	for v: Vector3 in [a - side, b - side, b + side, a - side, b + side, a + side]:
		st.add_vertex(Vector3(v.x, 0.0, v.z))
	return st.commit()


## Ready-made overlay nodes.
static func ring(radius: float, color: Color = Holo.CYAN, width: float = -1.0) -> MeshInstance3D:
	var w: float = width if width > 0.0 else radius * 0.06
	return _node(ring_mesh(radius, w), color)


static func disc(radius: float, color: Color = Holo.CYAN) -> MeshInstance3D:
	return _node(disc_mesh(radius, Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.45)), color)


static func sector(radius: float, angle: float, color: Color = Holo.CYAN) -> MeshInstance3D:
	return _node(sector_mesh(radius, angle, Color(1, 1, 1, 0.5), 0.0, SEGMENTS, Color(1, 1, 1, 0.12)), color)


static func _node(mesh: Mesh, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
