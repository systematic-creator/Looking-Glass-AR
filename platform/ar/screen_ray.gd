class_name ScreenRay
## Screen point (viewport coordinates) -> world ray, the exact inverse of how
## the frame is drawn.
##
## Why not Camera3D.project_ray_normal(): for an XRCamera3D, Godot 4.4 builds
## the ray from the XR projection's half-extents *at that matrix's near
## plane* but uses `-camera.near` as the ray's depth. The ARCore plugin's
## projection always has near = 0.1 m while our XR camera had near = 0.01 m,
## so every off-centre ray was ~10x too wide (49 degrees off at a board
## corner): taps landed far from the finger or missed the board entirely.
## It also assumes a symmetric frustum (ARCore's principal point is off-centre,
## ~0.6 degrees). Here the projection the frame is rendered with is inverted
## directly, so ray(unproject_position(p)) passes through p exactly.


## The projection the camera's frame is rendered with.
static func projection_of(camera: Camera3D) -> Projection:
	var size: Vector2 = viewport_size(camera)
	if camera is XRCamera3D:
		var xr: XRInterface = XRServer.primary_interface
		if xr != null:
			return xr.get_projection_for_view(0, size.x / maxf(1.0, size.y), camera.near, camera.far)
	return camera.get_camera_projection()


static func uses_xr_projection(camera: Camera3D) -> bool:
	return camera is XRCamera3D and XRServer.primary_interface != null


## Viewport size the screen coordinates refer to (content-scaled).
static func viewport_size(camera: Camera3D) -> Vector2:
	return camera.get_viewport().get_visible_rect().size


## [origin, unit direction] in world space.
static func ray(camera: Camera3D, screen: Vector2) -> Array[Vector3]:
	if not uses_xr_projection(camera):
		return [camera.project_ray_origin(screen), camera.project_ray_normal(screen)]
	var size: Vector2 = viewport_size(camera)
	var ndc := Vector2(screen.x / maxf(1.0, size.x) * 2.0 - 1.0, 1.0 - screen.y / maxf(1.0, size.y) * 2.0)
	var inverse: Projection = projection_of(camera).inverse()
	var near: Vector4 = inverse * Vector4(ndc.x, ndc.y, -1.0, 1.0)
	var far: Vector4 = inverse * Vector4(ndc.x, ndc.y, 1.0, 1.0)
	var a := Vector3(near.x, near.y, near.z) / near.w
	var b := Vector3(far.x, far.y, far.z) / far.w
	var xform: Transform3D = camera.global_transform
	return [xform.origin, (xform.basis * (b - a)).normalized()]


## Where a world ray (from ray()) meets a plane, or null.
static func hit_plane(camera: Camera3D, screen: Vector2, plane: Plane) -> Variant:
	var r: Array[Vector3] = ray(camera, screen)
	return plane.intersects_ray(r[0], r[1])
