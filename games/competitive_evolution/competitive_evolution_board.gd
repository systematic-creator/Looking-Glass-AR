class_name CompetitiveEvolutionBoard
extends LGGame
## Placeholder adapter for Competitive Evolution (Systematic-creator/
## Competitive-evolution-AGR), which is on hiatus while the platform is
## built. It reserves the catalog slot and shows the intended board: the
## orbit globe resting on the table at its real size (0.42 m across).
##
## The real adapter will import the AGR deterministic simulation and views
## (OrbitGlobe, FlatDiorama, RtsController...) and render them under this
## node in board space; the platform already provides what AGR's
## ARSessionController did (calibration, anchoring, lock/pause).

const GLOBE_RADIUS: float = 0.21
const SPIN_RADIANS_PER_SECOND: float = 0.25

var globe: MeshInstance3D
var _label: Label3D


func _on_board_ready() -> void:
	globe = MeshInstance3D.new()
	globe.name = "Globe"
	var sphere := SphereMesh.new()
	sphere.radius = GLOBE_RADIUS
	sphere.height = GLOBE_RADIUS * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.45, 0.35)
	material.roughness = 0.8
	sphere.material = material
	globe.mesh = sphere
	# Rest on the surface: board space y = 0 is the table top.
	globe.position.y = GLOBE_RADIUS
	add_child(globe)
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	var torus := TorusMesh.new()
	torus.inner_radius = GLOBE_RADIUS * 0.98
	torus.outer_radius = GLOBE_RADIUS * 1.04
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = Color(0.55, 0.95, 1.0)
	torus.material = ring_material
	ring.mesh = torus
	ring.position.y = 0.004
	ring.scale = Vector3(1.0, 0.2, 1.0)
	add_child(ring)
	_label = Label3D.new()
	_label.name = "ComingSoon"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.0007
	_label.font_size = 48
	_label.outline_size = 12
	_label.text = "Competitive Evolution\ncoming soon"
	add_child(_label)
	_on_box_changed(get_box())
	set_status("Competitive Evolution is on hiatus. This board is a placeholder.")


## Keep the "coming soon" label inside the (tall) play box.
func _on_box_changed(box: PlayBox) -> void:
	_label.position = Vector3(0.0, minf(GLOBE_RADIUS * 2.0 + 0.1, box.height() - 0.03), 0.0)


func _process(delta: float) -> void:
	if is_playing() and globe != null:
		globe.rotate_y(SPIN_RADIANS_PER_SECOND * delta)


func _on_board_tap(_point: Vector3) -> void:
	set_status("The full game will be imported from AGR later.")
