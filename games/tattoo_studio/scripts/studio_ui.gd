class_name TattooStudioUI
extends CanvasLayer
## Tattoo Studio's on-screen tools. Left: model picker and model size.
## Right: Draw / Rotate, Needle / Eraser, Undo (greyed when there is nothing
## to take back), ink colours, needle size, Clear all (asks first). The game asks is_over() so touches here never paint.
## Portrait: the model panel is a strip under the platform's top bar and the
## tool panel a three-column bar along the bottom, leaving the middle of the
## screen to the (tall) model. layout() follows the screen shape.

signal model_picked(id: StringName)
signal model_scale_changed(value: float)
signal mode_picked(mode: int)
signal tool_picked(tool: int)
signal colour_picked(index: int)
signal brush_picked(index: int)
signal clear_confirmed()
signal focus_pressed()
signal undo_pressed()

const PANEL_TOP: float = 110.0
## Portrait: the model strip sits under the (two-line) host status line.
const PANEL_TOP_PORTRAIT: float = 130.0
## Portrait: room kept free below the tool bar.
const BOTTOM_INSET_PORTRAIT: float = 24.0
const MARGIN: float = 16.0
const FONT: int = 20

var left_panel: PanelContainer
var right_panel: PanelContainer
var confirm_panel: PanelContainer
var model_buttons: Dictionary = {}
var mode_buttons: Array[Button] = []
var tool_buttons: Array[Button] = []
var colour_buttons: Array[Button] = []
var brush_buttons: Array[Button] = []
var scale_slider: HSlider
var scale_label: Label
var clear_button: Button
var focus_button: Button
var undo_button: Button
var confirm_label: Label
var confirm_yes: Button
var confirm_no: Button
## The layout applied last (true = portrait).
var portrait: bool = false
## Platform UI at the screen bottom (LGGame.ui_bottom_inset()): the portrait
## tool bar sits above it.
var bottom_inset: float = 0.0
var _left_box: BoxContainer
var _model_row: BoxContainer
var _size_row: BoxContainer
var _model_caption: Label
var _right_box: BoxContainer


func build(models: Array[TattooModelEntry], palette: Array, brushes: Array) -> void:
	layer = 3
	left_panel = _panel("ModelPanel")
	var left := BoxContainer.new()
	left.vertical = true
	left.add_theme_constant_override("separation", 8)
	left_panel.add_child(left)
	_left_box = left
	_model_caption = _caption("Model")
	left.add_child(_model_caption)
	_model_row = BoxContainer.new()
	_model_row.vertical = true
	_model_row.add_theme_constant_override("separation", 8)
	left.add_child(_model_row)
	var model_group := ButtonGroup.new()
	for entry: TattooModelEntry in models:
		var b: Button = _button(entry.display_name, Vector2(170, 52), model_group)
		var id: StringName = entry.id
		b.pressed.connect(func() -> void: model_picked.emit(id))
		model_buttons[id] = b
		_model_row.add_child(b)
	_size_row = BoxContainer.new()
	_size_row.vertical = true
	_size_row.add_theme_constant_override("separation", 8)
	left.add_child(_size_row)
	scale_label = _caption("Size 100%")
	scale_label.custom_minimum_size = Vector2(170, 0)
	_size_row.add_child(scale_label)
	scale_slider = HSlider.new()
	scale_slider.name = "ScaleSlider"
	scale_slider.custom_minimum_size = Vector2(170, 48)
	scale_slider.min_value = 0.1
	scale_slider.max_value = 1.0
	scale_slider.step = 0.01
	scale_slider.focus_mode = Control.FOCUS_NONE
	scale_slider.value_changed.connect(func(v: float) -> void: model_scale_changed.emit(v))
	scale_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_size_row.add_child(scale_slider)
	focus_button = _button("Focus", Vector2(170, 56), null)
	focus_button.name = "FocusButton"
	focus_button.tooltip_text = "Close-up: tap a spot to magnify it, pinch to zoom"
	focus_button.pressed.connect(func() -> void: focus_pressed.emit())
	_size_row.add_child(focus_button)

	right_panel = _panel("ToolPanel")
	# Three columns: modes / tools / Undo, ink, needle size / Clear all.
	# Stacked in landscape, side by side in portrait.
	_right_box = BoxContainer.new()
	_right_box.vertical = true
	_right_box.add_theme_constant_override("separation", 8)
	right_panel.add_child(_right_box)
	var right := _column()
	var mode_row := HBoxContainer.new()
	var mode_group := ButtonGroup.new()
	for i: int in 2:
		var b: Button = _button(["Draw", "Rotate"][i], Vector2(96, 52), mode_group)
		var m: int = i
		b.pressed.connect(func() -> void: mode_picked.emit(m))
		mode_buttons.append(b)
		mode_row.add_child(b)
	right.add_child(mode_row)
	var tool_row := HBoxContainer.new()
	var tool_group := ButtonGroup.new()
	for i: int in 2:
		var b: Button = _button(["Needle", "Eraser"][i], Vector2(96, 52), tool_group)
		var t: int = i
		b.pressed.connect(func() -> void: tool_picked.emit(t))
		tool_buttons.append(b)
		tool_row.add_child(b)
	right.add_child(tool_row)
	undo_button = _button("↶ Undo", Vector2(196, 52), null)
	undo_button.name = "UndoButton"
	undo_button.tooltip_text = "Take back the last stroke (or Clear all)"
	undo_button.pressed.connect(func() -> void: undo_pressed.emit())
	right.add_child(undo_button)
	show_undo(0)
	right = _column()
	right.add_child(_caption("Ink"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var colour_group := ButtonGroup.new()
	for i: int in palette.size():
		var entry: Array = palette[i]
		var b: Button = _swatch(entry[1] as Color, colour_group)
		b.tooltip_text = String(entry[0])
		var c: int = i
		b.pressed.connect(func() -> void: colour_picked.emit(c))
		colour_buttons.append(b)
		grid.add_child(b)
	right.add_child(grid)
	right = _column()
	right.add_child(_caption("Needle size"))
	var brush_row := HBoxContainer.new()
	var brush_group := ButtonGroup.new()
	for i: int in brushes.size():
		var b: Button = _button(String((brushes[i] as Array)[0]), Vector2(46, 48), brush_group)
		b.add_theme_font_size_override("font_size", 18)
		var k: int = i
		b.pressed.connect(func() -> void: brush_picked.emit(k))
		brush_buttons.append(b)
		brush_row.add_child(b)
	right.add_child(brush_row)
	clear_button = _button("Clear all…", Vector2(196, 52), null)
	clear_button.pressed.connect(show_confirm)
	right.add_child(clear_button)

	confirm_panel = _panel("ConfirmPanel")
	var confirm := VBoxContainer.new()
	confirm.add_theme_constant_override("separation", 12)
	confirm_panel.add_child(confirm)
	confirm_label = _caption("Clear every tattoo on this model?")
	confirm_label.add_theme_font_size_override("font_size", 24)
	confirm.add_child(confirm_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	confirm_yes = _button("Clear", Vector2(150, 60), null)
	confirm_yes.pressed.connect(func() -> void:
		hide_confirm()
		clear_confirmed.emit())
	confirm_no = _button("Keep", Vector2(150, 60), null)
	confirm_no.pressed.connect(hide_confirm)
	row.add_child(confirm_yes)
	row.add_child(confirm_no)
	confirm.add_child(row)
	confirm_panel.visible = false
	if is_inside_tree():
		_ready()


func _ready() -> void:
	if left_panel == null or get_viewport() == null:
		return
	if not get_viewport().size_changed.is_connected(layout):
		get_viewport().size_changed.connect(layout)
	layout()


func layout() -> void:
	if left_panel == null or not is_inside_tree():
		return
	var view: Vector2 = get_viewport().get_visible_rect().size
	_apply_shape(LGOrientation.is_portrait_size(view))
	left_panel.reset_size()
	right_panel.reset_size()
	confirm_panel.reset_size()
	if portrait:
		left_panel.position = Vector2((view.x - left_panel.size.x) * 0.5, PANEL_TOP_PORTRAIT)
		right_panel.position = Vector2((view.x - right_panel.size.x) * 0.5,
				view.y - right_panel.size.y - maxf(BOTTOM_INSET_PORTRAIT, bottom_inset + 12.0))
	else:
		left_panel.position = Vector2(MARGIN, 170.0)
		right_panel.position = Vector2(view.x - right_panel.size.x - MARGIN, PANEL_TOP)
	confirm_panel.position = (view - confirm_panel.size) * 0.5


## Landscape: two side columns. Portrait: a top strip (models, then size and
## Focus) and a bottom bar (the three tool columns side by side).
func _apply_shape(p_portrait: bool) -> void:
	portrait = p_portrait
	_model_caption.visible = not portrait
	_model_row.vertical = not portrait
	_size_row.vertical = not portrait
	_right_box.vertical = not portrait
	_right_box.add_theme_constant_override("separation", 14 if portrait else 8)
	var model_size: Vector2 = Vector2(140, 52) if portrait else Vector2(170, 52)
	for b: Variant in model_buttons.values():
		(b as Button).custom_minimum_size = model_size
	focus_button.custom_minimum_size = Vector2(130, 52) if portrait else Vector2(170, 56)
	scale_slider.custom_minimum_size = Vector2(190, 48) if portrait else Vector2(170, 48)


func show_confirm() -> void:
	confirm_panel.visible = true
	layout()


func hide_confirm() -> void:
	confirm_panel.visible = false


func set_shown(on: bool) -> void:
	visible = on
	if not on:
		hide_confirm()


func is_over(screen: Vector2) -> bool:
	if not visible:
		return false
	for panel: Control in [left_panel, right_panel, confirm_panel]:
		if panel != null and panel.visible and panel.get_global_rect().has_point(screen):
			return true
	return false


func show_state(model_id: StringName, mode: int, tool: int, colour: int, brush: int) -> void:
	for id: Variant in model_buttons:
		(model_buttons[id] as Button).set_pressed_no_signal(id == model_id)
	_press(mode_buttons, mode)
	_press(tool_buttons, tool)
	_press(colour_buttons, colour)
	_press(brush_buttons, brush)


## Undo button: "Undo (n)" while there are steps, greyed out when none.
func show_undo(count: int) -> void:
	if undo_button == null:
		return
	undo_button.disabled = count <= 0
	undo_button.text = "↶ Undo (%d)" % count if count > 0 else "↶ Undo"
	undo_button.modulate = Color(1, 1, 1, 1.0 if count > 0 else 0.45)


## Focus button label: picking a spot / magnified / off.
func show_focus(picking: bool, focused: bool) -> void:
	if focus_button == null:
		return
	focus_button.text = "Cancel focus" if picking else ("True size" if focused else "Focus")


func show_scale(value: float, lo: float, hi: float, life_height: float) -> void:
	scale_slider.set_block_signals(true)
	scale_slider.min_value = lo
	scale_slider.max_value = maxf(hi, lo + 0.001)
	scale_slider.value = value
	scale_slider.set_block_signals(false)
	scale_label.text = "Size %d%% · %.2f m" % [roundi(value * 100.0), life_height * value]


## Select one button of a group without emitting (set_pressed_no_signal
## does not release the group's other buttons, so do it here).
func _press(buttons: Array[Button], index: int) -> void:
	for i: int in buttons.size():
		buttons[i].set_pressed_no_signal(i == index)


func _column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_right_box.add_child(column)
	return column


func _panel(panel_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = panel_name
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.08, 0.78)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(12.0)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	return panel


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.8, 0.86, 0.92))
	return label


func _button(text: String, min_size: Vector2, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", FONT)
	if group != null:
		b.toggle_mode = true
		b.button_group = group
	return b


func _swatch(colour: Color, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(60, 46)
	b.toggle_mode = true
	b.button_group = group
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = colour
		style.set_corner_radius_all(10)
		var selected: bool = state == "pressed" or state == "hover_pressed"
		style.set_border_width_all(4 if selected else 1)
		style.border_color = Color.WHITE if selected else Color(1, 1, 1, 0.25)
		b.add_theme_stylebox_override(state, style)
	return b
