class_name Launcher
extends Control
## The Looking Glass catalog: one card per registered game. Picking a game
## opens it in GameHost, which runs AR calibration and then loads it onto the
## locked board.

## Emitted when a card is chosen (before the scene changes).
signal game_chosen(id: StringName)

const CARD_SIZE: Vector2 = Vector2(360.0, 300.0)

## Optional override (tests); defaults to the LookingGlass catalog.
var catalog: GameCatalog
## Launch handler; defaults to LookingGlass.launch(id).
var launch_handler: Callable = Callable()
var cards: Dictionary = {}

var _grid: HFlowContainer
var _empty_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0.04, 0.05, 0.08)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 36)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	var title := Label.new()
	title.text = "Looking Glass"
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Tabletop AR games. Pick one, then place its board on a table."
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88))
	column.add_child(subtitle)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 24)
	_grid.add_theme_constant_override("v_separation", 24)
	scroll.add_child(_grid)
	_empty_label = Label.new()
	_empty_label.text = "No games installed."
	_empty_label.add_theme_font_size_override("font_size", 26)
	column.add_child(_empty_label)
	refresh()


func _catalog() -> GameCatalog:
	if catalog != null:
		return catalog
	var looking_glass: Node = get_node_or_null(^"/root/LookingGlass")
	if looking_glass != null:
		return looking_glass.get("catalog") as GameCatalog
	catalog = GameCatalog.new()
	catalog.scan()
	return catalog


## Rebuild the cards from the catalog.
func refresh() -> void:
	for child: Node in _grid.get_children():
		child.queue_free()
	cards.clear()
	var games: Array[LGGameManifest] = _catalog().list()
	for manifest: LGGameManifest in games:
		var card: Button = _make_card(manifest)
		_grid.add_child(card)
		cards[manifest.id] = card
	_empty_label.visible = games.is_empty()


func choose(id: StringName) -> void:
	game_chosen.emit(id)
	if launch_handler.is_valid():
		launch_handler.call(id)
		return
	var looking_glass: Node = get_node_or_null(^"/root/LookingGlass")
	if looking_glass != null:
		looking_glass.call("launch", id)


func _make_card(manifest: LGGameManifest) -> Button:
	var card := Button.new()
	card.name = "Card_%s" % manifest.id
	card.custom_minimum_size = CARD_SIZE
	card.focus_mode = Control.FOCUS_NONE
	card.clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.14, 0.95)
	style.border_color = Color(0.55, 0.95, 1.0, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(22)
	var pressed := style.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.1, 0.4, 0.55, 0.95)
	card.add_theme_stylebox_override("normal", style)
	card.add_theme_stylebox_override("hover", style)
	card.add_theme_stylebox_override("pressed", pressed)
	card.add_theme_stylebox_override("hover_pressed", pressed)
	var id: StringName = manifest.id
	card.pressed.connect(func() -> void: choose(id))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 20.0
	box.offset_right = -20.0
	box.offset_top = 18.0
	box.offset_bottom = -18.0
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	var art: Control
	if manifest.icon != null:
		var icon := TextureRect.new()
		icon.texture = manifest.icon
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art = icon
	else:
		var placeholder := Label.new()
		placeholder.text = manifest.display_name.substr(0, 1).to_upper()
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		placeholder.add_theme_font_size_override("font_size", 64)
		art = placeholder
	art.custom_minimum_size = Vector2(0.0, 110.0)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(art)
	var name_label := Label.new()
	name_label.text = manifest.display_name
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)
	var meta := Label.new()
	meta.text = "%s  ·  %d×%d cm board" % [manifest.players_label(), roundi(manifest.board_size.x * 100.0), roundi(manifest.board_size.y * 100.0)]
	meta.add_theme_font_size_override("font_size", 18)
	meta.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(meta)
	var description := Label.new()
	description.text = manifest.description
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description.add_theme_font_size_override("font_size", 17)
	description.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88))
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(description)
	return card
