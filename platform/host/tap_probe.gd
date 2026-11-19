class_name TapProbe
extends Control
## Debug overlay for taps: a magenta dot where the finger touched (viewport
## coordinates, as the game received it) and a cyan ring where the board hit
## point projects back to the screen. If they do not coincide, the
## screen <-> world mapping is off; a screenshot shows it at once.

const SHOW_SECONDS: float = 2.5

var touch: Vector2 = Vector2.ZERO
## Reprojected board hit (null = the ray missed the board).
var hit: Variant = null
var _time: float = 0.0


func _init() -> void:
	name = "TapProbe"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func show_tap(p_touch: Vector2, p_hit: Variant) -> void:
	touch = p_touch
	hit = p_hit
	_time = SHOW_SECONDS
	queue_redraw()


func clear() -> void:
	_time = 0.0
	hit = null
	queue_redraw()


func is_showing() -> bool:
	return _time > 0.0


func _process(delta: float) -> void:
	if _time > 0.0:
		_time -= delta
		queue_redraw()


func _draw() -> void:
	if _time <= 0.0:
		return
	var a: float = clampf(_time / 0.6, 0.0, 1.0)
	if hit is Vector2:
		var h: Vector2 = hit as Vector2
		draw_line(touch, h, Color(1, 1, 1, 0.6 * a), 2.0)
		draw_arc(h, 18.0, 0.0, TAU, 32, Color(0.3, 0.95, 1.0, a), 3.0)
	else:
		draw_arc(touch, 22.0, 0.0, TAU, 32, Color(1.0, 0.3, 0.2, a), 3.0)
	draw_circle(touch, 9.0, Color(1.0, 0.2, 0.85, a))
