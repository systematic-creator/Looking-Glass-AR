class_name AnchorPopup
extends PanelContainer
## A small context menu that floats next to something on the board (a tower,
## a unit): a title, a detail line and a column of action buttons. show_at()
## places it beside a screen point and keeps it fully on screen (and above
## `bottom_inset` px of platform UI).

signal action_chosen(id: StringName)
signal dismissed()

var _title: Label
var _detail: Label
var _actions: VBoxContainer
var _buttons: Dictionary = {}
var anchor_screen: Vector2 = Vector2.ZERO


func _init() -> void:
	name = "AnchorPopup"
	add_theme_stylebox_override("panel", LGUI.panel_style(Color(0.03, 0.05, 0.13, 0.9), 16, 12))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_title = LGUI.label(26, Color(1.0, 0.86, 0.45))
	box.add_child(_title)
	_detail = LGUI.label(20)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(300, 0)
	box.add_child(_detail)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	box.add_child(_actions)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP


## actions: [{"id", "label", "enabled", "accent"}]
func show_at(screen: Vector2, title: String, detail: String, actions: Array[Dictionary], view: Vector2, bottom_inset: float = 0.0) -> void:
	_title.text = title
	_detail.text = detail
	for c: Node in _actions.get_children():
		_actions.remove_child(c)
		c.queue_free()
	_buttons.clear()
	for a: Dictionary in actions:
		var b := LGUI.button(str(a["label"]), a.get("accent", Color(0.3, 0.92, 1.0)), 24, Vector2(300, 68))
		b.name = "Action_%s" % a["id"]
		b.disabled = not bool(a.get("enabled", true))
		var id: StringName = a["id"]
		b.pressed.connect(func() -> void: action_chosen.emit(id))
		_actions.add_child(b)
		_buttons[id] = b
	anchor_screen = screen
	visible = true
	reset_size()
	place(view, bottom_inset)


func place(view: Vector2, bottom_inset: float = 0.0) -> void:
	var sz: Vector2 = get_combined_minimum_size()
	size = sz
	var pos := Vector2(anchor_screen.x + 40.0, anchor_screen.y - sz.y * 0.5)
	if pos.x + sz.x > view.x - 12.0:
		pos.x = anchor_screen.x - 40.0 - sz.x
	pos.x = clampf(pos.x, 12.0, maxf(12.0, view.x - sz.x - 12.0))
	pos.y = clampf(pos.y, 110.0, maxf(110.0, view.y - bottom_inset - 12.0 - sz.y))
	position = pos


func button(id: StringName) -> Button:
	return _buttons.get(id)


func dismiss() -> void:
	if visible:
		visible = false
		dismissed.emit()
