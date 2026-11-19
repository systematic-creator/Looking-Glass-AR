class_name OrbitCamera
extends Node3D
## Touch / desktop camera for the fallback (non-AR) view: orbits the board
## centre. Drag to orbit, pinch or mouse wheel to zoom.

const MIN_PITCH: float = deg_to_rad(-85.0)
const MAX_PITCH: float = deg_to_rad(-10.0)
const ORBIT_RADIANS_PER_PIXEL: float = 0.008

var camera: Camera3D
var yaw: float = 0.0
var pitch: float = deg_to_rad(-50.0)
var distance: float = 0.8
var min_distance: float = 0.15
var max_distance: float = 4.0


func _init() -> void:
	name = "OrbitCamera"
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.near = 0.01
	camera.far = 50.0
	camera.fov = 50.0
	add_child(camera)
	_apply()


## Fit a board footprint (metres) in view.
func frame_board(board_size: Vector2, board_height: float) -> void:
	var extent: float = maxf(maxf(board_size.x, board_size.y), board_height * 2.0)
	min_distance = extent * 0.35
	max_distance = extent * 8.0
	distance = clampf(extent * 1.8, min_distance, max_distance)
	position = Vector3(0.0, board_height * 0.3, 0.0)
	_apply()


## Portrait keeps the horizontal field of view (KEEP_WIDTH) so the board
## that fits a landscape screen's height also fits a portrait screen's width.
func set_portrait(portrait: bool) -> void:
	camera.keep_aspect = Camera3D.KEEP_WIDTH if portrait else Camera3D.KEEP_HEIGHT


func orbit(screen_delta: Vector2) -> void:
	yaw = wrapf(yaw - screen_delta.x * ORBIT_RADIANS_PER_PIXEL, -PI, PI)
	pitch = clampf(pitch - screen_delta.y * ORBIT_RADIANS_PER_PIXEL, MIN_PITCH, MAX_PITCH)
	_apply()


## factor > 1 zooms in.
func zoom(factor: float) -> void:
	if factor <= 0.0:
		return
	distance = clampf(distance / factor, min_distance, max_distance)
	_apply()


func _apply() -> void:
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	camera.transform = Transform3D(basis, basis * Vector3(0.0, 0.0, distance))
