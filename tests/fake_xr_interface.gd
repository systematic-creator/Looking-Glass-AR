class_name FakeXRInterface
extends XRInterfaceExtension
## Test-only XR interface that hands Godot an ARCore-style projection, so
## XRCamera3D behaves as on the phone: the projection comes from the
## interface (near fixed at 0.1 m whatever the camera says, off-centre
## principal point, the camera texture's 16:9 aspect stretched over a wider
## screen), not from the camera's fov / near.

var projection: Projection = Projection.IDENTITY
var _initialized: bool = false


## ARCore's GL projection for a `display` (px) with focal length `focal` (px)
## and principal point `principal` (px from the top-left).
static func arcore_projection(display: Vector2, focal: float, principal: Vector2, near: float = 0.1, far: float = 1000.0) -> Projection:
	return Projection.create_frustum(
		-principal.x / focal * near, (display.x - principal.x) / focal * near,
		-(display.y - principal.y) / focal * near, principal.y / focal * near, near, far)


## Make this the primary XR interface. Call uninstall() before the suite ends.
func install() -> void:
	XRServer.add_interface(self)
	initialize()
	XRServer.primary_interface = self


func uninstall() -> void:
	if XRServer.primary_interface == self:
		XRServer.primary_interface = null
	uninitialize()
	XRServer.remove_interface(self)


func _get_name() -> StringName:
	return &"FakeARCore"


func _get_capabilities() -> int:
	return XR_MONO + XR_AR


func _initialize() -> bool:
	_initialized = true
	return true


func _uninitialize() -> void:
	_initialized = false


func _is_initialized() -> bool:
	return _initialized


func _get_view_count() -> int:
	return 1


func _get_render_target_size() -> Vector2:
	return Vector2(1920, 1080)


func _get_camera_transform() -> Transform3D:
	return Transform3D.IDENTITY


func _get_transform_for_view(_view: int, cam_transform: Transform3D) -> Transform3D:
	return cam_transform


func _get_projection_for_view(_view: int, _aspect: float, _near: float, _far: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for column: int in 4:
		for row: int in 4:
			out.append(projection[column][row])
	return out
