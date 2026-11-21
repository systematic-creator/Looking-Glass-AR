class_name PassthroughBackground
extends CanvasLayer
## Camera passthrough for portrait / reverse-landscape AR.
##
## In landscape (Surface.ROTATION_90) the ARCore plugin keeps its original
## path: Environment.BG_CAMERA_FEED, where Godot 4.4's feed shader
## (drivers/gles3/shaders/feed.glsl) stretches the camera texture over the
## screen with NO UV transform. That cannot show a rotated image, so for any
## other rotation the plugin tells ARCore the real rotation and window size
## and reports, per frame, the camera-texture UVs of the four screen corners
## (ArFrame_transformCoordinates2d: rotation + centre crop). This layer draws
## the camera texture (an external OES texture, read through a CameraTexture)
## over the whole screen with those UVs, as the environment's background
## canvas (Environment.BG_CANVAS, max layer LAYER), so 3D renders on top.
## ARCore's projection matrix, view matrix and hit tests use the same
## display geometry, so content stays registered with the video.

const LAYER: int = -100

const SHADER_CODE: String = """
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform samplerExternalOES camera_feed : filter_linear;
// Camera-texture UVs of the screen corners (bottom-left, bottom-right,
// top-left, top-right: OpenGL NDC order, as ARCore reports them).
uniform vec2 uv_bl = vec2(0.0, 1.0);
uniform vec2 uv_br = vec2(1.0, 1.0);
uniform vec2 uv_tl = vec2(0.0, 0.0);
uniform vec2 uv_tr = vec2(1.0, 0.0);

void fragment() {
	vec2 top = mix(uv_tl, uv_tr, UV.x);
	vec2 bottom = mix(uv_bl, uv_br, UV.x);
	COLOR = vec4(texture(camera_feed, mix(top, bottom, UV.y)).rgb, 1.0);
}
"""

var rect: ColorRect
var material: ShaderMaterial
var feed_texture: CameraTexture
var feed_id: int = -1
## The corner UVs last applied (NDC order), for tests and the debug line.
var corners: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	name = "Passthrough"
	layer = LAYER
	add_to_group(OrientationService.NO_FADE_GROUP)
	rect = ColorRect.new()
	rect.name = "CameraImage"
	rect.color = Color.BLACK
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = SHADER_CODE
	material = ShaderMaterial.new()
	material.shader = shader
	rect.material = material
	add_child(rect)
	visible = false


## Show the camera feed `id` with ARCore's corner UVs (NDC order). Returns
## false (and stays hidden) until the plugin has reported four corners.
func show_feed(id: int, uvs: PackedVector2Array) -> bool:
	if uvs.size() != 4 or id < 0:
		visible = false
		return false
	if feed_texture == null or id != feed_id:
		feed_id = id
		feed_texture = CameraTexture.new()
		feed_texture.camera_feed_id = id
		feed_texture.which_feed = CameraServer.FEED_YCBCR_IMAGE
		material.set_shader_parameter("camera_feed", feed_texture)
	if uvs != corners:
		corners = uvs
		material.set_shader_parameter("uv_bl", uvs[0])
		material.set_shader_parameter("uv_br", uvs[1])
		material.set_shader_parameter("uv_tl", uvs[2])
		material.set_shader_parameter("uv_tr", uvs[3])
	visible = true
	return true


func hide_feed() -> void:
	visible = false


## Camera-texture UV under a normalized screen point (0..1, y down), exactly
## as the shader samples it.
static func texture_uv(corners_ndc: PackedVector2Array, screen_uv: Vector2) -> Vector2:
	var top: Vector2 = corners_ndc[2].lerp(corners_ndc[3], screen_uv.x)
	var bottom: Vector2 = corners_ndc[0].lerp(corners_ndc[1], screen_uv.x)
	return top.lerp(bottom, screen_uv.y)


## Point an environment at this layer as its background (or back to the
## plugin's camera feed when `custom` is false).
static func apply_background(environment: Environment, custom: bool) -> void:
	if environment == null:
		return
	if custom:
		environment.background_mode = Environment.BG_CANVAS
		environment.background_canvas_max_layer = LAYER
	else:
		environment.background_mode = Environment.BG_CAMERA_FEED
