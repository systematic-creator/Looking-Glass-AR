extends LGTestSuite
## Camera-image registration: is virtual content drawn exactly where the
## camera image shows the same world point, from every viewpoint? If not,
## world-correct content "swims" over the table as the phone moves.
##
## Models what the phone does (see tools/arcore_plugin/lg-arcore.patch):
##   - the camera texture (sensor intrinsics: focal f, principal point c)
##     is drawn by Godot 4.4.1's feed shader (drivers/gles3/shaders/feed.glsl)
##     over the WHOLE screen, stretched, with no UV transform;
##   - the plugin gives ARCore a "display" with the texture's aspect
##     (height = window height), so ARCore's projection covers the full
##     image; Godot renders with that projection as is (XRCamera3D).
## Then a world point's rendered pixel must equal its pixel in the
## stretched video. The same check with the display set to the real screen
## aspect (what ARCore assumes by default: a centre crop) shows the swim the
## plugin fix removes, so the test can tell the two apart.
## Run: godot --headless --path . res://tests/view_tests.tscn

const SCREEN := Vector2(2340.0, 1080.0)
var xr: FakeXRInterface
var _view: SubViewport
var _camera: XRCamera3D


func run_tests() -> void:
	xr = FakeXRInterface.new()
	xr.install()
	_view = SubViewport.new()
	_view.size = Vector2i(SCREEN)
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_view)
	var origin := XROrigin3D.new()
	_view.add_child(origin)
	_camera = XRCamera3D.new()
	_camera.near = 0.1
	origin.add_child(_camera)
	await frames(1)
	for texture: Vector2 in [Vector2(640, 480), Vector2(1920, 1080), Vector2(1440, 1080)]:
		_test_registration(texture)
	_test_screen_ray_matches_video()
	_view.queue_free()
	xr.uninstall()
	await frames(1)


## Pixel of a camera-space point in the camera texture (image y down).
static func _texture_pixel(local: Vector3, focal: float, principal: Vector2) -> Vector2:
	var depth: float = -local.z
	return Vector2(principal.x + focal * local.x / depth, principal.y - focal * local.y / depth)


## Where Godot's feed shader shows that texture pixel on the screen.
static func _video_pixel(texture_px: Vector2, texture: Vector2) -> Vector2:
	return texture_px / texture * SCREEN


## The plugin's display (texture aspect, window height) and ARCore's
## projection for it.
static func _fixed_projection(texture: Vector2, focal: float, principal: Vector2) -> Projection:
	var scale: float = SCREEN.y / texture.y
	var display := Vector2(roundf(SCREEN.y * texture.x / texture.y), SCREEN.y)
	return FakeXRInterface.arcore_projection(display, focal * scale, principal * scale)


## ARCore's default for the real screen aspect: it crops the image to the
## screen (here: top and bottom cut off), so its projection covers less of
## the image than the stretched video shows.
static func _cropped_projection(texture: Vector2, focal: float, principal: Vector2) -> Projection:
	var scale: float = SCREEN.x / texture.x
	var crop: float = (texture.y * scale - SCREEN.y) * 0.5
	return FakeXRInterface.arcore_projection(SCREEN, focal * scale, principal * scale - Vector2(0.0, crop))


func _max_error(texture: Vector2, focal: float, principal: Vector2, poses: Array, points: Array) -> float:
	var worst: float = 0.0
	for pose: Variant in poses:
		_camera.global_transform = pose as Transform3D
		for point: Variant in points:
			var world: Vector3 = point as Vector3
			if _camera.is_position_behind(world):
				continue
			var local: Vector3 = _camera.global_transform.affine_inverse() * world
			var video: Vector2 = _video_pixel(_texture_pixel(local, focal, principal), texture)
			if not Rect2(Vector2.ZERO, SCREEN).has_point(video):
				continue
			worst = maxf(worst, _camera.unproject_position(world).distance_to(video))
	return worst


func _poses() -> Array:
	var out: Array = []
	for from: Vector3 in [Vector3(0.0, 0.6, 0.35), Vector3(0.7, 0.35, -0.2), Vector3(-0.6, 0.25, -0.9), Vector3(0.1, 0.15, -1.4), Vector3(0.0, 1.1, -0.65)]:
		out.append(Transform3D(Basis.looking_at(Vector3(0.05, 0.0, -0.6) - from, Vector3.UP), from))
	return out


## The corners and edge midpoints of a 0.6 x 0.5 m table top, and its centre.
func _table_points() -> Array:
	var out: Array = []
	for x: float in [-0.3, 0.0, 0.3]:
		for z: float in [-0.85, -0.6, -0.35]:
			out.append(Vector3(x, 0.0, z))
	return out


func _test_registration(texture: Vector2) -> void:
	var focal: float = texture.x * 0.78
	var principal: Vector2 = texture * 0.5 + Vector2(texture.x * 0.012, -texture.y * 0.009)
	xr.projection = _fixed_projection(texture, focal, principal)
	var fixed: float = _max_error(texture, focal, principal, _poses(), _table_points())
	check("registration %dx%d texture on a 2340x1080 screen: content lands on the video pixel from every viewpoint (max %.2f px)" % [texture.x, texture.y, fixed], fixed < 1.0)
	xr.projection = _cropped_projection(texture, focal, principal)
	var cropped: float = _max_error(texture, focal, principal, _poses(), _table_points())
	check("registration %dx%d: with ARCore's default (screen-aspect crop) display it would swim by %.0f px (so the test can see a mismatch)" % [texture.x, texture.y, cropped], cropped > 40.0)


## Taps use ScreenRay with the same projection: a touch on the video pixel
## of a table point hits that point.
func _test_screen_ray_matches_video() -> void:
	var texture := Vector2(640, 480)
	var focal: float = 499.0
	var principal := Vector2(323.0, 238.0)
	xr.projection = _fixed_projection(texture, focal, principal)
	var worst: float = 0.0
	for pose: Variant in _poses():
		_camera.global_transform = pose as Transform3D
		for point: Variant in _table_points():
			var world: Vector3 = point as Vector3
			if _camera.is_position_behind(world):
				continue
			var local: Vector3 = _camera.global_transform.affine_inverse() * world
			var video: Vector2 = _video_pixel(_texture_pixel(local, focal, principal), texture)
			if not Rect2(Vector2.ZERO, SCREEN).has_point(video):
				continue
			var hit: Variant = ScreenRay.hit_plane(_camera, video, Plane(Vector3.UP, 0.0))
			worst = maxf(worst, INF if hit == null else (hit as Vector3).distance_to(world))
	check("registration: a touch on a table point's video pixel hits that point (max %.1f mm)" % (worst * 1000.0), worst < 0.002)
