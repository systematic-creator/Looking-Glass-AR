class_name Launcher
extends Control
## The Looking Glass catalog: one card per registered game. Picking a game
## opens it in GameHost, which runs AR calibration and then loads it onto the
## locked board.

## Emitted when a card is chosen (before the scene changes).
signal game_chosen(id: StringName)

const CARD_SIZE: Vector2 = Vector2(360.0, 300.0)
## Landscape cards shrink to this before the grid wraps to a second row.
const CARD_MIN_WIDTH: float = 200.0
## Landscape cards: room for a 5-line description.
const CARD_HEIGHT_LANDSCAPE: float = 340.0
## Portrait: one full-width card per row (capped), art on the left. Cards
## get shorter (down to CARD_MIN_HEIGHT_PORTRAIT) so the whole catalog fits.
const CARD_HEIGHT_PORTRAIT: float = 300.0
const CARD_MIN_HEIGHT_PORTRAIT: float = 140.0
const CARD_MAX_WIDTH_PORTRAIT: float = 640.0
const CARD_GAP: float = 24.0
## Description font: shrinks from the first size to the last to fit its card;
## past that the text ends with an ellipsis.
const DESCRIPTION_FONT_SIZES: Array[int] = [17, 16, 15, 14, 13]
const MARGIN: float = 36.0
const MARGIN_PORTRAIT: float = 28.0

## Optional override (tests); defaults to the LookingGlass catalog.
var catalog: GameCatalog
## Launch handler; defaults to LookingGlass.launch(id).
var launch_handler: Callable = Callable()
var cards: Dictionary = {}

var _grid: HFlowContainer
var _empty_label: Label
var _margin: MarginContainer
var _title: Label
var _subtitle: Label
## The layout applied last (follows the screen shape).
var portrait: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0.04, 0.05, 0.08)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	_margin = margin
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	var title := Label.new()
	title.text = "Looking Glass"
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	column.add_child(title)
	_title = title
	var subtitle := Label.new()
	subtitle.text = "Tabletop AR games. Pick one, then place its board on a table."
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(subtitle)
	_subtitle = subtitle
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", int(CARD_GAP))
	_grid.add_theme_constant_override("v_separation", int(CARD_GAP))
	_grid.alignment = FlowContainer.ALIGNMENT_BEGIN
	scroll.add_child(_grid)
	_empty_label = Label.new()
	_empty_label.text = "No games installed."
	_empty_label.add_theme_font_size_override("font_size", 26)
	column.add_child(_empty_label)
	refresh()
	get_viewport().size_changed.connect(_on_viewport_resized)
	apply_layout(LGOrientation.is_portrait_size(get_viewport().get_visible_rect().size))


func _on_viewport_resized() -> void:
	apply_layout(LGOrientation.is_portrait_size(get_viewport().get_visible_rect().size))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and cards.size() > 0:
		_fit_text.call_deferred()


## Landscape: a flowing grid of cards. Portrait: one centred column of wide
## cards, smaller title and margins.
func apply_layout(p_portrait: bool) -> void:
	portrait = p_portrait
	var margin: float = MARGIN_PORTRAIT if portrait else MARGIN
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		_margin.add_theme_constant_override(side, int(margin))
	_title.add_theme_font_size_override("font_size", 46 if portrait else 54)
	_grid.alignment = FlowContainer.ALIGNMENT_CENTER if portrait else FlowContainer.ALIGNMENT_BEGIN
	_apply_card_layout()


func _apply_card_layout() -> void:
	var size: Vector2 = card_size()
	for card: Variant in cards.values():
		var control := card as Control
		control.custom_minimum_size = size
		var box := control.get_node_or_null(^"Box") as BoxContainer
		if box != null:
			box.vertical = not portrait
			var art := box.get_node(^"Art") as Control
			art.custom_minimum_size = Vector2(minf(150.0, size.y - 36.0), 0.0) if portrait else Vector2(0.0, 110.0 if size.x >= 260.0 else 80.0)
			var name_label := box.get_node(^"Text/Name") as Label
			name_label.add_theme_font_size_override("font_size", 28 if portrait or size.x >= 300.0 else 22)
	_fit_text.call_deferred()


## Height left for the cards under the title and subtitle (an estimate from
## the font sizes, so it is known before the first layout pass).
func _cards_area_height() -> float:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var margin: float = MARGIN_PORTRAIT if portrait else MARGIN
	var title_h: float = (46.0 if portrait else 54.0) * 1.4
	var subtitle_lines: float = 2.0 if portrait else 1.0
	var header: float = title_h + subtitle_lines * 24.0 * 1.45 + 2.0 * 18.0 + 8.0
	return view.y - 2.0 * margin - header


## Shrink each description until it fits its card; ellipsis as a last resort.
func _fit_text() -> void:
	if not is_inside_tree():
		return
	for card: Variant in cards.values():
		var description := (card as Control).get_node_or_null(^"Box/Text/Description") as Label
		if description != null:
			fit_description(description)


## One description: the largest font size whose wrapped lines fit the label's
## laid-out height (clip_text keeps that height independent of the text).
static func fit_description(description: Label) -> void:
	var room: float = description.size.y
	if room < 1.0:
		return
	description.max_lines_visible = -1
	for font_size: int in DESCRIPTION_FONT_SIZES:
		description.add_theme_font_size_override("font_size", font_size)
		if _text_height(description) <= room + 0.5:
			return
	var line: float = maxf(1.0, _text_height(description) / float(maxi(1, description.get_line_count())))
	description.max_lines_visible = maxi(1, int(room / line))


static func _text_height(label: Label) -> float:
	var lines: int = label.get_line_count()
	return float(lines * label.get_line_height() + maxi(lines - 1, 0) * label.get_theme_constant("line_spacing"))


## True if every description shows in full (tests).
func descriptions_fit() -> bool:
	for card: Variant in cards.values():
		var description := (card as Control).get_node_or_null(^"Box/Text/Description") as Label
		if description != null and description.max_lines_visible > 0:
			return false
	return true


## The card size for the current layout and viewport.
func card_size() -> Vector2:
	if not portrait:
		# Narrower cards (down to CARD_MIN_WIDTH) so the catalog stays one row;
		# past that, two rows of shorter cards so it still fits the screen.
		var n: int = maxi(cards.size(), 1)
		var avail: float = get_viewport().get_visible_rect().size.x - 2.0 * MARGIN - 12.0
		var w: float = (avail - CARD_GAP * float(n - 1)) / float(n)
		if w >= CARD_MIN_WIDTH:
			w = minf(w, CARD_SIZE.x)
			# Narrow cards get taller so the description still shows, but never
			# taller than the screen leaves.
			var h: float = CARD_HEIGHT_LANDSCAPE + (CARD_SIZE.x - w) * 1.4
			return Vector2(w, minf(h, maxf(CARD_SIZE.y * 0.8, _cards_area_height())))
		var per_row: int = int(ceil(n / 2.0))
		w = clampf((avail - CARD_GAP * float(per_row - 1)) / float(per_row), CARD_MIN_WIDTH, CARD_SIZE.x)
		var h2: float = (_cards_area_height() - CARD_GAP) * 0.5
		return Vector2(w, clampf(h2, 150.0, CARD_HEIGHT_LANDSCAPE))
	var width: float = get_viewport().get_visible_rect().size.x - 2.0 * MARGIN_PORTRAIT - 12.0
	var count: int = maxi(cards.size(), 1)
	var fit_h: float = (_cards_area_height() - CARD_GAP * float(count - 1)) / float(count)
	return Vector2(clampf(width, CARD_SIZE.x, CARD_MAX_WIDTH_PORTRAIT), clampf(fit_h, CARD_MIN_HEIGHT_PORTRAIT, CARD_HEIGHT_PORTRAIT))


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
	_apply_card_layout()


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
	card.custom_minimum_size = card_size() if _margin != null else CARD_SIZE
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
	var box := BoxContainer.new()
	box.name = "Box"
	box.vertical = not portrait
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 20.0
	box.offset_right = -20.0
	box.offset_top = 18.0
	box.offset_bottom = -18.0
	box.add_theme_constant_override("separation", 12)
	card.add_child(box)
	var text := VBoxContainer.new()
	text.name = "Text"
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 6)
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
	art.name = "Art"
	art.custom_minimum_size = Vector2(0.0, 110.0)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(art)
	box.add_child(text)
	var name_label := Label.new()
	name_label.name = "Name"
	name_label.text = manifest.display_name
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(name_label)
	var meta := Label.new()
	meta.text = "%s  ·  %d×%d cm board" % [manifest.players_label(), roundi(manifest.board_size.x * 100.0), roundi(manifest.board_size.y * 100.0)]
	meta.add_theme_font_size_override("font_size", 18)
	meta.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta.custom_minimum_size = Vector2(1.0, 0.0)
	text.add_child(meta)
	var description := Label.new()
	description.name = "Description"
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# Its height comes from the card, not the text (_fit_text sizes the font).
	description.clip_text = true
	description.resized.connect(func() -> void: fit_description(description))
	description.text = manifest.description
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description.add_theme_font_size_override("font_size", 17)
	description.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88))
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(description)
	return card
