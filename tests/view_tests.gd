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
##
## Portrait (and any rotation but landscape) works differently: the plugin
## gives ARCore the real rotation and window size, ARCore crops the rotated
## image to the screen, and PassthroughBackground draws the texture with the
## corner UVs ARCore reports. The portrait cases model that: a phone whose
## sensor is mounted for landscape (texture u runs down the portrait screen,
## v runs right-to-left), ARCore's centre-crop projection for a 1080x2340
## display, and the shader's UV interpolation (PassthroughBackground.
## texture_uv). Content must land on the video pixel and taps must hit.
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
	await _test_portrait()
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


# --- Portrait ---------------------------------------------------------------------

const PORTRAIT_SCREEN := Vector2(1080.0, 2340.0)


## ARCore's fill crop of the rotated image (texture.y wide, texture.x tall)
## onto the portrait screen: scale and the cropped offset (screen px).
static func _portrait_crop(texture: Vector2) -> Array:
	var s: float = maxf(PORTRAIT_SCREEN.x / texture.y, PORTRAIT_SCREEN.y / texture.x)
	var offset := Vector2((texture.y * s - PORTRAIT_SCREEN.x) * 0.5, (texture.x * s - PORTRAIT_SCREEN.y) * 0.5)
	return [s, offset]


## Texture pixel (sensor frame) -> portrait screen pixel, as ARCore crops it.
static func _portrait_screen_of_texture(px: Vector2, texture: Vector2) -> Vector2:
	var crop: Array = _portrait_crop(texture)
	var s: float = crop[0]
	var offset: Vector2 = crop[1]
	return Vector2((texture.y - px.y) * s - offset.x, px.x * s - offset.y)


## The corner UVs the plugin would report (ArFrame_transformCoordinates2d,
## NDC order: bottom-left, bottom-right, top-left, top-right).
static func _portrait_corner_uvs(texture: Vector2) -> PackedVector2Array:
	var crop: Array = _portrait_crop(texture)
	var s: float = crop[0]
	var offset: Vector2 = crop[1]
	var out := PackedVector2Array()
	for screen: Vector2 in [Vector2(0.0, PORTRAIT_SCREEN.y), PORTRAIT_SCREEN, Vector2.ZERO, Vector2(PORTRAIT_SCREEN.x, 0.0)]:
		var u: float = (screen.y + offset.y) / s
		var v: float = texture.y - (screen.x + offset.x) / s
		out.append(Vector2(u / texture.x, v / texture.y))
	return out


## Display-oriented camera point (portrait: x right, y up on the screen) in
## the sensor's landscape camera frame.
static func _sensor_local(portrait_local: Vector3) -> Vector3:
	return Vector3(-portrait_local.y, portrait_local.x, portrait_local.z)


## ARCore's projection for the portrait display with that crop.
static func _portrait_projection(texture: Vector2, focal: float, principal: Vector2) -> Projection:
	var crop: Array = _portrait_crop(texture)
	var s: float = crop[0]
	var offset: Vector2 = crop[1]
	var pp := Vector2((texture.y - principal.y) * s - offset.x, principal.x * s - offset.y)
	return FakeXRInterface.arcore_projection(PORTRAIT_SCREEN, focal * s, pp)


func _test_portrait() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(PORTRAIT_SCREEN)
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(view)
	var origin := XROrigin3D.new()
	view.add_child(origin)
	var camera := XRCamera3D.new()
	camera.near = 0.1
	origin.add_child(camera)
	await frames(1)
	for texture: Vector2 in [Vector2(640, 480), Vector2(1920, 1080)]:
		var focal: float = texture.x * 0.78
		var principal: Vector2 = texture * 0.5 + Vector2(texture.x * 0.012, -texture.y * 0.009)
		var corners: PackedVector2Array = _portrait_corner_uvs(texture)
		xr.projection = _portrait_projection(texture, focal, principal)
		var worst: float = 0.0
		var stretched: float = 0.0
		var ray_worst: float = 0.0
		var seen: int = 0
		for pose: Variant in _poses():
			camera.global_transform = pose as Transform3D
			for point: Variant in _table_points():
				var world: Vector3 = point as Vector3
				if camera.is_position_behind(world):
					continue
				var local: Vector3 = camera.global_transform.affine_inverse() * world
				var tex_px: Vector2 = _texture_pixel(_sensor_local(local), focal, principal)
				var video: Vector2 = _portrait_screen_of_texture(tex_px, texture)
				if not Rect2(Vector2.ZERO, PORTRAIT_SCREEN).has_point(video):
					continue
				seen += 1
				var rendered: Vector2 = camera.unproject_position(world)
				# What the passthrough shader samples at the rendered pixel.
				var sampled: Vector2 = PassthroughBackground.texture_uv(corners, rendered / PORTRAIT_SCREEN) * texture
				var crop: Array = _portrait_crop(texture)
				worst = maxf(worst, sampled.distance_to(tex_px) * float(crop[0]))
				# Godot's own feed shader (landscape path) would stretch the
				# unrotated texture over the portrait screen instead.
				stretched = maxf(stretched, rendered.distance_to(tex_px / texture * PORTRAIT_SCREEN))
				var hit: Variant = ScreenRay.hit_plane(camera, video, Plane(Vector3.UP, 0.0))
				ray_worst = maxf(ray_worst, INF if hit == null else (hit as Vector3).distance_to(world))
		check("portrait %dx%d: table points are on screen from the test poses (%d)" % [texture.x, texture.y, seen], seen >= 20)
		check("portrait %dx%d texture on a 1080x2340 screen: content lands on the passthrough pixel (max %.2f px)" % [texture.x, texture.y, worst], worst < 1.0)
		check("portrait %dx%d: the landscape feed path would be off by %.0f px (so the test can see a mismatch)" % [texture.x, texture.y, stretched], stretched > 100.0)
		check("portrait %dx%d: a touch on a table point's video pixel hits it (max %.1f mm)" % [texture.x, texture.y, ray_worst * 1000.0], ray_worst < 0.002)
	# Corner order: the shader's top-left corner shows the texture's u = 0
	# edge (portrait top) and its right edge the v = 0 edge.
	var c: PackedVector2Array = _portrait_corner_uvs(Vector2(640, 480))
	var tl: Vector2 = PassthroughBackground.texture_uv(c, Vector2(0.0, 0.0))
	var br: Vector2 = PassthroughBackground.texture_uv(c, Vector2(1.0, 1.0))
	check("portrait: screen top-left samples the corner ARCore reports for NDC (-1, 1)", tl.is_equal_approx(c[2]))
	check("portrait: screen bottom-right samples the corner for NDC (1, -1)", br.is_equal_approx(c[1]))
	view.queue_free()
	await frames(1)
