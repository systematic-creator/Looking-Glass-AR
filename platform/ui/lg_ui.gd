class_name LGUI
extends RefCounted
## Shared look for game HUDs built in code (dark glass panels with a cyan rim,
## outlined labels, rimmed buttons), so every Looking Glass game reads alike.

static func panel_style(bg: Color = Color(0.03, 0.05, 0.13, 0.82), radius: int = 16, margin: int = 14, rim: Color = Color(0.3, 0.92, 1.0, 0.8)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = rim
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style


static func label(font_size: int, color: Color = Color(0.95, 0.97, 1.0), align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.08, 0.95))
	l.add_theme_constant_override("outline_size", 8)
	return l


static func style_button(button: Button, accent: Color, fill: Color = Color(0.03, 0.06, 0.16, 0.8)) -> void:
	for state_name: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = fill if state_name != "pressed" else Color(accent, 0.35)
		if state_name == "disabled":
			s.bg_color = Color(0.03, 0.05, 0.1, 0.55)
		if state_name == "focus":
			s.bg_color = Color(0, 0, 0, 0)
			s.draw_center = false
		s.border_color = accent if state_name != "disabled" else Color(accent, 0.35)
		s.set_border_width_all(2 if state_name != "focus" else 0)
		s.set_corner_radius_all(14)
		s.set_content_margin_all(8)
		button.add_theme_stylebox_override(state_name, s)
	button.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	button.add_theme_color_override("font_disabled_color", Color(0.75, 0.8, 0.9, 0.6))


static func button(text: String, accent: Color, font_size: int = 26, min_size: Vector2 = Vector2(120, 72)) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	style_button(b, accent)
	return b


## True if `screen` is on a visible control.
static func hit(control: Control, screen: Vector2) -> bool:
	return control != null and control.is_visible_in_tree() and control.get_global_rect().has_point(screen)
