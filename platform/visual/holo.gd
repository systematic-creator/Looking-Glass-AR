class_name Holo
extends RefCounted
## Hologram look for Looking Glass games ("Card Wars" style: glowing,
## see-through pieces standing on a projected board). Everything here is
## unlit and alpha-blended without depth writes: it keeps its colour over a
## bright daylight camera image, needs no lights, and stays cheap on a
## mid-range phone (two small shaders, no textures, no post-processing).
## Compatibility-renderer safe.
##
##   Holo.material(Holo.CYAN)              see-through body with a glowing rim
##   Holo.line_material(Holo.CYAN)         solid glowing line / edge
##   Holo.glow_base(Vector2(0.4, 0.4))     projector glow on the table
##   Holo.ripple(Holo.CYAN, 0.1)           landing ring (animate via HoloDrop)
##   Holo.bar(from, to, 0.004, material)   a glowing bar between two points
##   HoloDrop.start(piece, ...)            drop-in with bounce, squash, flash
##
## Materials are new instances, so animating one (flash, intensity) never
## touches another piece.

const CYAN := Color(0.3, 0.92, 1.0)
const MAGENTA := Color(1.0, 0.36, 0.78)
const GOLD := Color(1.0, 0.8, 0.3)
const GREEN := Color(0.45, 1.0, 0.6)

const SURFACE_SHADER: Shader = preload("res://platform/visual/holo.gdshader")
const DISC_SHADER: Shader = preload("res://platform/visual/holo_disc.gdshader")


## See-through hologram body: faint fill facing you, bright rim at the edges.
static func material(color: Color, fill: float = 0.18, rim: float = 1.1, intensity: float = 1.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SURFACE_SHADER
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("fill", fill)
	mat.set_shader_parameter("rim", rim)
	mat.set_shader_parameter("intensity", intensity)
	return mat


## Solid glowing line (grid lines, frame edges, win line).
static func line_material(color: Color, intensity: float = 1.0) -> ShaderMaterial:
	var mat := material(color, 0.85, 0.3, intensity)
	mat.set_shader_parameter("scan_strength", 0.1)
	mat.set_shader_parameter("sweep_strength", 0.15)
	mat.set_shader_parameter("flicker", 0.03)
	return mat


## Flat glow for a PlaneMesh (see holo_disc.gdshader for the parameters).
static func disc_material(color: Color, core: float = 0.45, ring_radius: float = 0.9, ring: float = 0.7, grid: float = 0.0, square: float = 0.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = DISC_SHADER
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("core", core)
	mat.set_shader_parameter("ring_radius", ring_radius)
	mat.set_shader_parameter("ring", ring)
	mat.set_shader_parameter("grid", grid)
	mat.set_shader_parameter("square", square)
	return mat


## Soft projector glow lying on the table under a board of `size` (board
## space, y = 0). `margin` widens it past the footprint.
static func glow_base(size: Vector2, color: Color = CYAN, margin: float = 0.08) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = size + Vector2(margin, margin) * 2.0
	var node := MeshInstance3D.new()
	node.name = "HoloGlowBase"
	node.mesh = mesh
	node.material_override = disc_material(color, 0.38, 0.84, 0.55, 0.22, 0.75)
	node.position.y = 0.001
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Expanding landing ring, `radius` metres at full size. Hidden until a
## HoloDrop animates it.
static func ripple(color: Color, radius: float) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(radius, radius) * 2.0
	var node := MeshInstance3D.new()
	node.name = "HoloRipple"
	node.mesh = mesh
	var mat := disc_material(color, 0.0, 0.2, 1.2)
	mat.set_shader_parameter("ring_width", 0.06)
	mat.set_shader_parameter("pulse", 0.0)
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	return node


## A box bar from `from` to `to` (local space of its parent), `thickness`
## square, with `mat`. Used for grid lines, frame edges and win lines.
static func bar(from: Vector3, to: Vector3, thickness: float, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	var length: float = from.distance_to(to)
	mesh.size = Vector3(thickness, thickness, maxf(length, 0.0001))
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mid: Vector3 = (from + to) * 0.5
	var dir: Vector3 = to - from
	if dir.length() > 0.00001:
		var up: Vector3 = Vector3.UP if absf(dir.normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		node.transform = Transform3D(Basis.looking_at(dir.normalized(), up), mid)
	else:
		node.position = mid
	return node


## Set a shader parameter on every ShaderMaterial override under `root`.
static func set_param(root: Node, param: StringName, value: Variant) -> void:
	if root is GeometryInstance3D:
		var mat: Material = (root as GeometryInstance3D).material_override
		if mat is ShaderMaterial:
			(mat as ShaderMaterial).set_shader_parameter(param, value)
	for child: Node in root.get_children():
		set_param(child, param, value)
