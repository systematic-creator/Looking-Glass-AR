class_name CatalogSheet
extends PanelContainer
## A tabbed catalog for build / summon / shop menus. In portrait it is a
## bottom sheet over the lower part of the screen (cards scroll sideways); in
## landscape a drawer on the right (cards in a 2-column grid). Call
## layout(portrait, view_size, bottom_inset) after a rotation or inset change.
##
## Items: {"id", "title", "cost" (int, -1 = none), "lines" (String),
##         "enabled" (bool), "note" (String shown when disabled), "accent"}.
## item_chosen(id) fires when an enabled card is tapped; the sheet stays open
## (the game usually closes it and starts placing).

signal item_chosen(id: StringName)
signal tab_changed(tab: StringName)
signal closed()

const CARD_PORTRAIT := Vector2(300, 220)
const CARD_LANDSCAPE := Vector2(280, 190)

var current_tab: StringName = &""
var portrait: bool = true
var _tabs: Array[Dictionary] = []
var _items: Dictionary = {}
var _title: Label
var _tab_row: HBoxContainer
var _scroll: ScrollContainer
var _cards: Container
var _close: Button
var _tab_buttons: Dictionary = {}
var _card_buttons: Dictionary = {}
var _cost_formatter: Callable


func _init() -> void:
	name = "CatalogSheet"
	add_theme_stylebox_override("panel", LGUI.panel_style(Color(0.03, 0.05, 0.13, 0.9), 22, 16))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	_title = LGUI.label(30, Color(1.0, 0.86, 0.45), HORIZONTAL_ALIGNMENT_LEFT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_close = LGUI.button("✕", Color(0.9, 0.95, 1.0), 28, Vector2(72, 64))
	_close.name = "Close"
	_close.pressed.connect(close)
	head.add_child(_close)
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 8)
	box.add_child(_tab_row)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_scroll)
	visible = false


## Optional: format a cost (e.g. apply a markup) -> text.
func set_cost_formatter(f: Callable) -> void:
	_cost_formatter = f


func set_title(text: String) -> void:
	_title.text = text


func set_tabs(tabs: Array[Dictionary]) -> void:
	_tabs = tabs
	for c: Node in _tab_row.get_children():
		c.queue_free()
	_tab_buttons.clear()
	for t: Dictionary in tabs:
		var b := LGUI.button(str(t["title"]), Color(0.3, 0.92, 1.0), 22, Vector2(130, 56))
		b.toggle_mode = true
		b.name = "Tab_%s" % t["id"]
		var tid: StringName = t["id"]
		b.pressed.connect(func() -> void: show_tab(tid))
		_tab_row.add_child(b)
		_tab_buttons[tid] = b
	_tab_row.visible = tabs.size() > 1


func set_items(tab: StringName, items: Array[Dictionary]) -> void:
	_items[tab] = items
	if tab == current_tab and visible:
		_rebuild_cards()


func open(tab: StringName = &"") -> void:
	visible = true
	show_tab(tab if tab != &"" else (_tabs[0]["id"] if not _tabs.is_empty() else &""))


func show_tab(tab: StringName) -> void:
	current_tab = tab
	for id: StringName in _tab_buttons:
		(_tab_buttons[id] as Button).button_pressed = id == tab
	_rebuild_cards()
	tab_changed.emit(tab)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func card(id: StringName) -> Button:
	return _card_buttons.get(id)


func layout(p_portrait: bool, view: Vector2, bottom_inset: float) -> void:
	portrait = p_portrait
	var bottom: float = maxf(16.0, bottom_inset + 12.0)
	if portrait:
		anchor_left = 0.0
		anchor_right = 1.0
		anchor_top = 1.0
		anchor_bottom = 1.0
		offset_left = 16.0
		offset_right = -16.0
		offset_bottom = -bottom
		offset_top = -bottom - clampf(view.y * 0.36, 360.0, 560.0)
	else:
		anchor_left = 1.0
		anchor_right = 1.0
		anchor_top = 0.0
		anchor_bottom = 1.0
		offset_right = -16.0
		# Two card columns + margins; grows leftward if the cards need more.
		offset_left = -clampf(view.x * 0.4, 2.0 * CARD_LANDSCAPE.x + 76.0, 760.0)
		grow_horizontal = Control.GROW_DIRECTION_BEGIN
		offset_top = 96.0
		offset_bottom = -bottom
	_rebuild_cards()


func _rebuild_cards() -> void:
	if _cards != null:
		_scroll.remove_child(_cards)
		_cards.queue_free()
	_card_buttons.clear()
	if portrait:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_cards = row
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	else:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		_cards = grid
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_cards.name = "Cards"
	_scroll.add_child(_cards)
	for item: Dictionary in _items.get(current_tab, []):
		_cards.add_child(_make_card(item))


func _make_card(item: Dictionary) -> Button:
	var accent: Color = item.get("accent", Color(0.3, 0.92, 1.0))
	var b := Button.new()
	b.name = "Card_%s" % item["id"]
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = CARD_PORTRAIT if portrait else CARD_LANDSCAPE
	b.clip_text = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.add_theme_font_size_override("font_size", 21)
	LGUI.style_button(b, accent)
	var enabled: bool = bool(item.get("enabled", true))
	var cost: int = int(item.get("cost", -1))
	var cost_text: String = ""
	if cost >= 0:
		cost_text = _cost_formatter.call(cost) if _cost_formatter.is_valid() else "◆ %d" % cost
	var text: String = "%s   %s\n%s" % [item.get("title", ""), cost_text, item.get("lines", "")]
	if not enabled and str(item.get("note", "")) != "":
		text += "\n(%s)" % item["note"]
	b.text = text
	b.disabled = not enabled
	var id: StringName = item["id"]
	b.pressed.connect(func() -> void: item_chosen.emit(id))
	_card_buttons[id] = b
	return b
