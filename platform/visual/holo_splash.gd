class_name HoloSplash
extends Node3D
## Hologram "dust cloud" for a landing piece: a one-shot puff of glowing
## motes (CPUParticles3D, which runs under gl_compatibility on Android)
## that bursts out along the board plane with a slight rise and fades.
## Additive, unshaded, no depth writes: the Holo look. Frees itself after
## LIFETIME (+ a margin); advance() steps that clock by hand in tests.
##
##   HoloSplash.spawn(parent, position, Holo.CYAN, radius)

const LIFETIME: float = 0.75
const AMOUNT: int = 56
## Motes rise to about this fraction of the radius.
const RISE: float = 0.35

var particles: CPUParticles3D
var color: Color = Holo.CYAN
var radius: float = 0.05
var age: float = 0.0


## A splash at `position` (parent's space) reaching about `p_radius` metres.
static func spawn(parent: Node, position_in_parent: Vector3, p_color: Color, p_radius: float) -> HoloSplash:
	var splash := HoloSplash.new()
	splash.name = "HoloSplash"
	splash.color = p_color
	splash.radius = maxf(p_radius, 0.005)
	splash.position = position_in_parent
	splash._build()
	parent.add_child(splash)
	splash.particles.emitting = true
	return splash


func _build() -> void:
	particles = CPUParticles3D.new()
	particles.name = "Motes"
	particles.amount = AMOUNT
	particles.lifetime = LIFETIME
	particles.one_shot = true
	particles.explosiveness = 0.92
	particles.randomness = 0.5
	particles.local_coords = true
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = radius * 0.15
	# Spread all round in the board plane (flatness 1 = the XZ plane).
	particles.direction = Vector3(1.0, 0.0, 0.0)
	particles.spread = 180.0
	particles.flatness = 1.0
	# Out to ~radius and stop: v0 = a r / L decelerated by b r / L^2 travels
	# a^2 / (2 b) r (a 1.8-3.0, b ~3: 0.5-1.5 r), stopping near the end.
	particles.initial_velocity_min = radius * 1.8 / LIFETIME
	particles.initial_velocity_max = radius * 3.0 / LIFETIME
	particles.damping_min = radius * 2.8 / (LIFETIME * LIFETIME)
	particles.damping_max = radius * 3.4 / (LIFETIME * LIFETIME)
	# The slight rise of a dust cloud.
	particles.gravity = Vector3(0.0, radius * RISE * 2.0 / (LIFETIME * LIFETIME), 0.0)
	particles.scale_amount_min = 0.7
	particles.scale_amount_max = 1.3
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(0.3, 1.0))
	grow.add_point(Vector2(1.0, 1.4))
	particles.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.r, color.g, color.b, 1.0))
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	ramp.add_point(0.45, Color(color.r, color.g, color.b, 0.7))
	particles.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * radius * 0.42
	quad.material = mote_material()
	particles.mesh = quad
	add_child(particles)


## Additive, unshaded, billboarded soft dot tinted by the particle colour.
static func mote_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.no_depth_test = false
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dot := GradientTexture2D.new()
	dot.width = 64
	dot.height = 64
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.4, Color(1, 1, 1, 0.55))
	dot.gradient = g
	mat.albedo_texture = dot
	return mat


func _process(delta: float) -> void:
	advance(delta)


## Step the splash clock; frees the node once the motes have faded.
func advance(delta: float) -> void:
	age += delta
	if age >= LIFETIME + 0.15:
		set_process(false)
		if is_inside_tree():
			queue_free()


func is_running() -> bool:
	return age < LIFETIME
