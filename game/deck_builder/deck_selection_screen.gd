class_name DeckSelectionScreen
extends CanvasLayer


signal deck_selected(deck: DeckDefinition)


const SAVE_PATH: String = "user://custom_decks.cfg"
const SAVE_META_SECTION: String = "custom_decks"
const SAVE_COUNT_KEY: String = "count"
const SAVE_SECTION_PREFIX: String = "custom_deck_"
const SAVE_CARDS_KEY: String = "cards"
const SAVE_NAME_KEY: String = "name"

const COLLECTION_CARD_MIN_WIDTH: float = 238.0
const COLLECTION_CARD_GAP: float = 12.0
const COLLECTION_SCROLLBAR_ALLOWANCE: float = 30.0
const DECK_TILE_MIN_WIDTH: float = 360.0
const DECK_TILE_MAX_COLUMNS: int = 4
const CARD_DRAG_DATA_TYPE: String = "deck_builder_card"
const DECK_ROW_SWIPE_THRESHOLD: float = 96.0
const DECK_ROW_SWIPE_MAX_OFFSET: float = 180.0
const DECK_ROW_SWIPE_START_META: StringName = &"deck_swipe_start"
const DECK_ROW_SWIPE_ACTIVE_META: StringName = &"deck_swipe_active"
const DECK_ROW_SWIPE_ANIMATING_META: StringName = &"deck_swipe_animating"

const COLLECTION_GESTURE_START_META: StringName = &"collection_gesture_start"
const COLLECTION_SCROLL_INTENT_META: StringName = &"collection_scroll_intent"
const DECK_DROP_BLOCK_META: StringName = &"deck_drop_block"

const MOBILE_SCROLL_DEADZONE: int = 4
const MOBILE_PRIMARY_BUTTON_HEIGHT: float = 68.0
const MOBILE_SECONDARY_BUTTON_HEIGHT: float = 58.0
const MOBILE_SMALL_BUTTON_SIZE: float = 54.0

const PRESET_NAMES: Array[String] = [
	"Starter Deck",
	"Rock Deck",
	"Killer Deck"
]

const COLOR_BACKGROUND := Color(0.025, 0.035, 0.075, 0.98)
const COLOR_PANEL := Color(0.075, 0.095, 0.16, 0.98)
const COLOR_PANEL_LIGHT := Color(0.11, 0.135, 0.22, 1.0)
const COLOR_GOLD := Color(0.94, 0.69, 0.22, 1.0)
const COLOR_GOLD_DARK := Color(0.45, 0.28, 0.075, 1.0)
const COLOR_TEXT := Color(0.95, 0.97, 1.0, 1.0)
const COLOR_MUTED := Color(0.63, 0.70, 0.82, 1.0)
const COLOR_RARE := Color(0.40, 0.66, 1.0, 1.0)
const COLOR_COMMON := Color(0.72, 0.76, 0.83, 1.0)
const COLOR_ERROR := Color(1.0, 0.42, 0.38, 1.0)
const COLOR_SUCCESS := Color(0.45, 0.90, 0.62, 1.0)


var settings: DeckBuilderSettings
var preset_decks: Array[DeckDefinition] = []
var preset_previews: Array[CardDefinition] = []

var selected_counts: Dictionary = {}
var card_by_path: Dictionary = {}
var custom_decks: Array[Dictionary] = []
var active_custom_deck_index: int = -1
var custom_deck_name: String = "Custom Deck"
var custom_deck_saved: bool = false

var root_control: Control
var page_title: Label
var page_subtitle: Label
var content_host: Control

var card_grid: GridContainer
var card_scroll: ScrollContainer
var deck_list: VBoxContainer
var deck_count_label: Label
var deck_progress: ProgressBar
var save_button: Button
var status_label: Label
var search_edit: LineEdit
var rarity_filter: OptionButton
var deck_name_edit: LineEdit


func _is_mobile_ui() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios")


func _configure_mobile_scroll(scroll: ScrollContainer) -> void:
	if scroll == null:
		return

	if not _is_mobile_ui():
		return

	# Start vertical scrolling with a much smaller finger movement.
	scroll.scroll_deadzone = MOBILE_SCROLL_DEADZONE
	scroll.follow_focus = false


func configure(
	new_settings: DeckBuilderSettings,
	new_preset_decks: Array[DeckDefinition],
	new_preset_previews: Array[CardDefinition]
) -> void:
	settings = new_settings

	preset_decks.clear()
	for deck: DeckDefinition in new_preset_decks:
		preset_decks.append(deck)

	preset_previews.clear()
	for preview: CardDefinition in new_preset_previews:
		preset_previews.append(preview)


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS

	if settings == null:
		push_error("DeckSelectionScreen needs DeckBuilderSettings.")
		queue_free()
		return

	_index_available_cards()
	_load_custom_decks()
	_build_shell()
	_show_selection_page()
	_play_open_animation()


func _index_available_cards() -> void:
	card_by_path.clear()

	for card: CardDefinition in settings.available_cards:
		if card == null:
			continue

		if card.resource_path.is_empty():
			continue

		card_by_path[card.resource_path] = card


func _build_shell() -> void:
	root_control = Control.new()
	root_control.name = "DeckSelectionRoot"
	root_control.mouse_filter = Control.MOUSE_FILTER_STOP
	root_control.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	add_child(root_control)

	var background := ColorRect.new()
	background.color = COLOR_BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	background.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	root_control.add_child(background)

	var vignette := Panel.new()
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	vignette.add_theme_stylebox_override(
		"panel",
		_make_style(
			Color(0.01, 0.015, 0.04, 0.18),
			0,
			2,
			Color(0.25, 0.35, 0.65, 0.30)
		)
	)
	root_control.add_child(vignette)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	var horizontal_margin: int = 24 if _is_mobile_ui() else 82
	var top_margin: int = 22 if _is_mobile_ui() else 42
	var bottom_margin: int = 24 if _is_mobile_ui() else 44
	margin.add_theme_constant_override("margin_left", horizontal_margin)
	margin.add_theme_constant_override("margin_right", horizontal_margin)
	margin.add_theme_constant_override("margin_top", top_margin)
	margin.add_theme_constant_override("margin_bottom", bottom_margin)
	root_control.add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 18)
	margin.add_child(page)

	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0.0, 102.0)
	header.add_theme_constant_override("separation", 24)
	page.add_child(header)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 4)
	header.add_child(title_box)

	page_title = Label.new()
	page_title.add_theme_font_size_override("font_size", 38)
	page_title.add_theme_color_override("font_color", COLOR_TEXT)
	title_box.add_child(page_title)

	page_subtitle = Label.new()
	page_subtitle.add_theme_font_size_override("font_size", 19)
	page_subtitle.add_theme_color_override("font_color", COLOR_MUTED)
	title_box.add_child(page_subtitle)

	var rules_badge := PanelContainer.new()
	rules_badge.custom_minimum_size = Vector2(
		320.0 if _is_mobile_ui() else 420.0,
		74.0
	)
	rules_badge.add_theme_stylebox_override(
		"panel",
		_make_style(
			Color(0.09, 0.115, 0.19, 1.0),
			14,
			2,
			COLOR_GOLD_DARK
		)
	)
	header.add_child(rules_badge)

	var rules_label := Label.new()
	rules_label.text = (
		"DECK  %d     COMMON ×%d     RARE ×%d"
		% [
			settings.deck_size,
			settings.common_copy_limit,
			settings.rare_copy_limit
		]
	)
	rules_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rules_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rules_label.add_theme_font_size_override("font_size", 17)
	rules_label.add_theme_color_override("font_color", COLOR_GOLD)
	rules_badge.add_child(rules_label)

	content_host = Control.new()
	content_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_host.mouse_filter = Control.MOUSE_FILTER_PASS
	page.add_child(content_host)


func _show_selection_page() -> void:
	_clear_content_host()

	page_title.text = "CHOOSE YOUR DECK"
	page_subtitle.text = (
		"Select a ready deck or build your own collection."
	)

	var deck_scroll := ScrollContainer.new()
	deck_scroll.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	deck_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_configure_mobile_scroll(deck_scroll)
	content_host.add_child(deck_scroll)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_scroll.add_child(center)

	var deck_grid := GridContainer.new()
	deck_grid.columns = DECK_TILE_MAX_COLUMNS
	deck_grid.add_theme_constant_override(
		"h_separation",
		18 if _is_mobile_ui() else 24
	)
	deck_grid.add_theme_constant_override(
		"v_separation",
		18 if _is_mobile_ui() else 24
	)
	center.add_child(deck_grid)

	for index: int in range(preset_decks.size()):
		_add_preset_tile(deck_grid, index)

	for index: int in range(custom_decks.size()):
		_add_saved_custom_deck_tile(deck_grid, index)

	_add_new_custom_deck_tile(deck_grid)

	deck_scroll.resized.connect(
		Callable(self, "_update_deck_selection_columns").bind(
			deck_grid,
			deck_scroll
		)
	)
	Callable(self, "_update_deck_selection_columns").call_deferred(
		deck_grid,
		deck_scroll
	)


func _update_deck_selection_columns(
	deck_grid: GridContainer,
	deck_scroll: ScrollContainer
) -> void:
	if not is_instance_valid(deck_grid):
		return
	if not is_instance_valid(deck_scroll):
		return

	var gap: float = 18.0 if _is_mobile_ui() else 24.0
	var tile_count: int = deck_grid.get_child_count()
	var maximum_columns: int = mini(
		DECK_TILE_MAX_COLUMNS,
		maxi(1, tile_count)
	)
	var available_width: float = maxf(
		DECK_TILE_MIN_WIDTH,
		deck_scroll.size.x
	)
	var column_width: float = DECK_TILE_MIN_WIDTH + gap
	var column_count: int = clampi(
		floori((available_width + gap) / column_width),
		1,
		maximum_columns
	)

	deck_grid.columns = column_count


func _add_preset_tile(parent: Container, index: int) -> void:
	var deck: DeckDefinition = preset_decks[index]
	var preview: CardDefinition = null

	if index < preset_previews.size():
		preview = preset_previews[index]

	if preview == null:
		preview = _get_deck_preview(deck)

	var deck_name: String = "Deck %d" % (index + 1)
	if index < PRESET_NAMES.size():
		deck_name = PRESET_NAMES[index]

	var tile := _create_deck_tile(
		deck_name,
		"READY TO PLAY",
		preview,
		"SELECT DECK"
	)
	parent.add_child(tile)

	var select_button := tile.get_node(
		"Content/SelectButton"
	) as Button

	select_button.disabled = deck == null
	select_button.pressed.connect(
		Callable(self, "_on_preset_selected").bind(index)
	)


func _add_saved_custom_deck_tile(
	parent: Container,
	index: int
) -> void:
	if index < 0 or index >= custom_decks.size():
		return

	var saved_deck: Dictionary = custom_decks[index]
	var counts: Dictionary = _get_saved_deck_counts(saved_deck)
	var deck_name: String = str(
		saved_deck.get("name", "Custom Deck")
	)
	var deck_is_ready: bool = _is_counts_complete(counts)
	var subtitle: String = (
		"%d CARDS • SAVED" % settings.deck_size
		if deck_is_ready
		else "NEEDS UPDATE"
	)

	var tile := _create_deck_tile(
		deck_name,
		subtitle,
		_get_custom_preview(counts),
		"SELECT DECK",
		true
	)
	parent.add_child(tile)

	var select_button := tile.get_node(
		"Content/SelectButton"
	) as Button
	select_button.disabled = not deck_is_ready
	select_button.pressed.connect(
		Callable(self, "_on_custom_deck_selected").bind(index)
	)

	var edit_button := tile.get_node(
		"Content/EditButton"
	) as Button
	edit_button.visible = true
	edit_button.pressed.connect(
		Callable(self, "_edit_custom_deck").bind(index)
	)


func _add_new_custom_deck_tile(parent: Container) -> void:
	var tile := _create_deck_tile(
		"New Deck",
		"BUILD A NEW DECK",
		null,
		"CREATE DECK",
		true
	)
	parent.add_child(tile)

	var select_button := tile.get_node(
		"Content/SelectButton"
	) as Button
	select_button.pressed.connect(
		Callable(self, "_start_new_custom_deck")
	)

	var edit_button := tile.get_node(
		"Content/EditButton"
	) as Button
	edit_button.visible = false


func _start_new_custom_deck() -> void:
	active_custom_deck_index = -1
	selected_counts.clear()
	custom_deck_name = "Custom Deck %d" % (custom_decks.size() + 1)
	custom_deck_saved = false
	_show_builder_page()


func _edit_custom_deck(index: int) -> void:
	if index < 0 or index >= custom_decks.size():
		return

	var saved_deck: Dictionary = custom_decks[index]
	active_custom_deck_index = index
	custom_deck_name = str(
		saved_deck.get("name", "Custom Deck")
	).strip_edges()

	if custom_deck_name.is_empty():
		custom_deck_name = "Custom Deck %d" % (index + 1)

	var counts: Dictionary = _get_saved_deck_counts(saved_deck)
	selected_counts = counts.duplicate(true)
	custom_deck_saved = _is_custom_deck_complete()
	_show_builder_page()


func _create_deck_tile(
	title: String,
	subtitle: String,
	preview: CardDefinition,
	action_text: String,
	is_custom: bool = false
) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360.0, 650.0)
	panel.add_theme_stylebox_override(
		"panel",
		_make_style(
			COLOR_PANEL,
			20,
			2,
			COLOR_GOLD_DARK if not is_custom else COLOR_RARE
		)
	)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)

	var top_label := Label.new()
	top_label.text = "CUSTOM" if is_custom else "PRESET"
	top_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_label.add_theme_font_size_override("font_size", 15)
	top_label.add_theme_color_override(
		"font_color",
		COLOR_RARE if is_custom else COLOR_GOLD
	)
	content.add_child(top_label)

	var image_frame := PanelContainer.new()
	image_frame.custom_minimum_size = Vector2(316.0, 410.0)
	image_frame.add_theme_stylebox_override(
		"panel",
		_make_style(
			Color(0.025, 0.035, 0.07, 1.0),
			14,
			1,
			Color(0.25, 0.31, 0.47, 1.0)
		)
	)
	content.add_child(image_frame)

	if preview != null and preview.front_texture != null:
		var image := TextureRect.new()
		image.texture = preview.front_texture
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image_frame.add_child(image)
	else:
		var plus_label := Label.new()
		plus_label.text = "+"
		plus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plus_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		plus_label.add_theme_font_size_override("font_size", 92)
		plus_label.add_theme_color_override("font_color", COLOR_RARE)
		image_frame.add_child(plus_label)

	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", COLOR_TEXT)
	content.add_child(title_label)

	var subtitle_label := Label.new()
	subtitle_label.text = subtitle
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_size_override("font_size", 14)
	subtitle_label.add_theme_color_override("font_color", COLOR_MUTED)
	content.add_child(subtitle_label)

	var select_button := Button.new()
	select_button.name = "SelectButton"
	select_button.text = action_text
	select_button.custom_minimum_size = Vector2(
		0.0,
		MOBILE_PRIMARY_BUTTON_HEIGHT if _is_mobile_ui() else 52.0
	)
	_apply_primary_button_style(select_button)
	if _is_mobile_ui():
		select_button.add_theme_font_size_override("font_size", 20)
	content.add_child(select_button)

	var edit_button := Button.new()
	edit_button.name = "EditButton"
	edit_button.text = "EDIT DECK"
	edit_button.visible = is_custom
	edit_button.custom_minimum_size = Vector2(
		0.0,
		MOBILE_SECONDARY_BUTTON_HEIGHT if _is_mobile_ui() else 42.0
	)
	_apply_secondary_button_style(edit_button)
	if _is_mobile_ui():
		edit_button.add_theme_font_size_override("font_size", 18)
	content.add_child(edit_button)

	return panel


func _show_builder_page() -> void:
	_clear_content_host()

	page_title.text = "BUILD YOUR DECK"
	page_subtitle.text = (
		"Swipe vertically to scroll. Drag a card toward YOUR DECK to add it."
		if _is_mobile_ui()
		else "Drag cards into your deck, or use the existing + and − controls."
	)

	var body := HBoxContainer.new()
	body.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	body.add_theme_constant_override("separation", 22)
	content_host.add_child(body)

	var library_panel := PanelContainer.new()
	library_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_panel.size_flags_stretch_ratio = 2.65
	library_panel.add_theme_stylebox_override(
		"panel",
		_make_style(COLOR_PANEL, 18, 1, Color(0.20, 0.26, 0.42, 1.0))
	)
	body.add_child(library_panel)

	var library_content := VBoxContainer.new()
	library_content.add_theme_constant_override("separation", 14)
	library_panel.add_child(library_content)

	var library_header := HBoxContainer.new()
	library_header.custom_minimum_size = Vector2(0.0, 58.0)
	library_header.add_theme_constant_override("separation", 12)
	library_content.add_child(library_header)

	var library_title := Label.new()
	library_title.text = "CARD COLLECTION"
	library_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	library_title.add_theme_font_size_override("font_size", 22)
	library_title.add_theme_color_override("font_color", COLOR_TEXT)
	library_header.add_child(library_title)

	search_edit = LineEdit.new()
	search_edit.placeholder_text = "Search cards"
	search_edit.clear_button_enabled = true
	search_edit.custom_minimum_size = Vector2(
		280.0,
		56.0 if _is_mobile_ui() else 46.0
	)
	search_edit.text_changed.connect(
		Callable(self, "_on_card_filter_changed")
	)
	library_header.add_child(search_edit)

	rarity_filter = OptionButton.new()
	rarity_filter.custom_minimum_size = Vector2(
		180.0,
		56.0 if _is_mobile_ui() else 46.0
	)
	rarity_filter.add_item("All Cards")
	rarity_filter.add_item("Common")
	rarity_filter.add_item("Rare")
	rarity_filter.item_selected.connect(
		Callable(self, "_on_rarity_filter_changed")
	)
	library_header.add_child(rarity_filter)

	card_scroll = ScrollContainer.new()
	card_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_configure_mobile_scroll(card_scroll)
	library_content.add_child(card_scroll)

	card_grid = GridContainer.new()
	card_grid.columns = 6
	card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_grid.add_theme_constant_override(
		"h_separation",
		int(COLLECTION_CARD_GAP)
	)
	card_grid.add_theme_constant_override("v_separation", 16)
	card_scroll.add_child(card_grid)
	card_scroll.resized.connect(
		Callable(self, "_update_collection_columns")
	)

	var deck_panel := PanelContainer.new()
	deck_panel.custom_minimum_size = Vector2(525.0, 0.0)
	deck_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_panel.size_flags_stretch_ratio = 1.0
	deck_panel.add_theme_stylebox_override(
		"panel",
		_make_style(
			Color(0.055, 0.075, 0.14, 1.0),
			18,
			2,
			COLOR_GOLD_DARK
		)
	)
	body.add_child(deck_panel)

	var deck_content := VBoxContainer.new()
	deck_content.add_theme_constant_override("separation", 12)
	deck_panel.add_child(deck_content)

	var deck_heading := Label.new()
	deck_heading.text = "YOUR DECK"
	deck_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	deck_heading.add_theme_font_size_override("font_size", 24)
	deck_heading.add_theme_color_override("font_color", COLOR_GOLD)
	deck_content.add_child(deck_heading)

	deck_name_edit = LineEdit.new()
	deck_name_edit.text = custom_deck_name
	deck_name_edit.placeholder_text = "Deck name"
	deck_name_edit.max_length = 28
	deck_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	deck_name_edit.custom_minimum_size = Vector2(0.0, 46.0)
	deck_name_edit.text_changed.connect(
		Callable(self, "_on_deck_name_changed")
	)
	deck_content.add_child(deck_name_edit)

	var progress_row := HBoxContainer.new()
	progress_row.add_theme_constant_override("separation", 12)
	deck_content.add_child(progress_row)

	deck_count_label = Label.new()
	deck_count_label.custom_minimum_size = Vector2(100.0, 36.0)
	deck_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	deck_count_label.add_theme_font_size_override("font_size", 20)
	progress_row.add_child(deck_count_label)

	deck_progress = ProgressBar.new()
	deck_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_progress.max_value = settings.deck_size
	deck_progress.show_percentage = false
	deck_progress.custom_minimum_size = Vector2(0.0, 22.0)
	progress_row.add_child(deck_progress)

	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_configure_mobile_scroll(list_scroll)
	deck_content.add_child(list_scroll)

	deck_list = VBoxContainer.new()
	deck_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_list.add_theme_constant_override("separation", 6)
	list_scroll.add_child(deck_list)

	status_label = Label.new()
	status_label.custom_minimum_size = Vector2(0.0, 34.0)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.add_theme_color_override("font_color", COLOR_MUTED)
	deck_content.add_child(status_label)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	action_row.set_meta(DECK_DROP_BLOCK_META, true)
	deck_content.add_child(action_row)

	var back_button := Button.new()
	back_button.text = "BACK"
	back_button.custom_minimum_size = Vector2(
		132.0 if _is_mobile_ui() else 118.0,
		MOBILE_PRIMARY_BUTTON_HEIGHT if _is_mobile_ui() else 52.0
	)
	back_button.mouse_filter = Control.MOUSE_FILTER_STOP
	back_button.focus_mode = Control.FOCUS_NONE
	_apply_secondary_button_style(back_button)
	back_button.pressed.connect(
		Callable(self, "_on_builder_back_pressed")
	)
	action_row.add_child(back_button)

	var clear_button := Button.new()
	clear_button.text = "CLEAR"
	clear_button.custom_minimum_size = Vector2(
		118.0,
		MOBILE_PRIMARY_BUTTON_HEIGHT if _is_mobile_ui() else 52.0
	)
	_apply_secondary_button_style(clear_button)
	clear_button.pressed.connect(
		Callable(self, "_on_clear_deck_pressed")
	)
	action_row.add_child(clear_button)

	save_button = Button.new()
	save_button.text = "SAVE DECK"
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.custom_minimum_size = Vector2(
		0.0,
		MOBILE_PRIMARY_BUTTON_HEIGHT if _is_mobile_ui() else 52.0
	)
	_apply_primary_button_style(save_button)
	save_button.pressed.connect(
		Callable(self, "_on_save_deck_pressed")
	)
	action_row.add_child(save_button)

	_configure_deck_drop_target(deck_panel)
	_refresh_card_library()
	_refresh_deck_list()
	call_deferred("_update_collection_columns")


func _update_collection_columns() -> void:
	if card_grid == null or card_scroll == null:
		return

	var available_width: float = maxf(
		COLLECTION_CARD_MIN_WIDTH,
		card_scroll.size.x - COLLECTION_SCROLLBAR_ALLOWANCE
	)
	var column_width: float = (
		COLLECTION_CARD_MIN_WIDTH + COLLECTION_CARD_GAP
	)
	var column_count: int = maxi(
		1,
		floori(
			(available_width + COLLECTION_CARD_GAP) / column_width
		)
	)

	card_grid.columns = column_count


func _refresh_card_library() -> void:
	if card_grid == null:
		return

	_clear_children(card_grid)

	var query: String = ""
	if search_edit != null:
		query = search_edit.text.strip_edges().to_lower()

	var rarity_index: int = 0
	if rarity_filter != null:
		rarity_index = rarity_filter.selected

	var visible_cards: Array[CardDefinition] = []

	for card: CardDefinition in _get_sorted_available_cards():
		if card == null:
			continue

		if not query.is_empty():
			var searchable := (
				card.display_name + " " + str(card.card_id)
			).to_lower()

			if not searchable.contains(query):
				continue

		if (
			rarity_index == 1
			and card.rarity != CardDefinition.Rarity.COMMON
		):
			continue

		if (
			rarity_index == 2
			and card.rarity != CardDefinition.Rarity.RARE
		):
			continue

		visible_cards.append(card)

	for card: CardDefinition in visible_cards:
		card_grid.add_child(_create_collection_card(card))

	if visible_cards.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No cards match this filter."
		empty_label.custom_minimum_size = Vector2(900.0, 100.0)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 20)
		empty_label.add_theme_color_override("font_color", COLOR_MUTED)
		card_grid.add_child(empty_label)


func _create_collection_card(card: CardDefinition) -> PanelContainer:
	var path: String = card.resource_path
	var count: int = int(selected_counts.get(path, 0))
	var copy_limit: int = settings.get_copy_limit(card)
	var at_limit: bool = count >= copy_limit

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(238.0, 350.0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _is_mobile_ui():
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override(
		"panel",
		_make_style(
			COLOR_PANEL_LIGHT,
			13,
			2 if count > 0 else 1,
			COLOR_GOLD if count > 0 else Color(0.22, 0.28, 0.43, 1.0)
		)
	)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	if _is_mobile_ui():
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(content)

	var image_button := TextureButton.new()
	image_button.custom_minimum_size = Vector2(210.0, 265.0)
	image_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image_button.ignore_texture_size = true
	image_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	image_button.texture_normal = card.front_texture
	image_button.tooltip_text = _get_card_tooltip(card)
	image_button.modulate = (
		Color(0.62, 0.65, 0.72, 1.0)
		if at_limit
		else Color.WHITE
	)
	image_button.pressed.connect(
		Callable(self, "_on_collection_card_pressed").bind(card)
	)
	# Keep drag-to-deck on every platform.
	# On mobile, vertical gestures are classified as scroll before drag data
	# is allowed to start, so scrolling the collection remains easy.
	image_button.mouse_filter = Control.MOUSE_FILTER_PASS
	if _is_mobile_ui():
		image_button.gui_input.connect(
			Callable(self, "_on_collection_card_gui_input").bind(
				image_button
			)
		)

	image_button.set_drag_forwarding(
		Callable(self, "_get_collection_drag_data").bind(
			card,
			image_button
		),
		Callable(),
		Callable()
	)
	content.add_child(image_button)

	var count_badge := Label.new()
	count_badge.text = "%d/%d" % [count, copy_limit]
	count_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_badge.anchor_left = 1.0
	count_badge.anchor_right = 1.0
	count_badge.offset_left = -78.0
	count_badge.offset_right = -8.0
	count_badge.offset_top = 8.0
	count_badge.offset_bottom = 42.0
	count_badge.add_theme_font_size_override("font_size", 16)
	count_badge.add_theme_color_override("font_color", COLOR_TEXT)
	count_badge.add_theme_stylebox_override(
		"normal",
		_make_style(
			Color(0.02, 0.03, 0.07, 0.92),
			10,
			1,
			COLOR_GOLD if count > 0 else Color(0.3, 0.35, 0.48, 1.0)
		)
	)
	count_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image_button.add_child(count_badge)

	var card_name := Label.new()
	card_name.text = card.display_name
	card_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card_name.add_theme_font_size_override("font_size", 17)
	card_name.add_theme_color_override("font_color", COLOR_TEXT)
	card_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(card_name)

	var meta := Label.new()
	meta.text = "%d MANA  •  %s" % [
		card.mana_cost,
		_get_rarity_name(card)
	]
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.add_theme_font_size_override("font_size", 13)
	meta.add_theme_color_override(
		"font_color",
		COLOR_RARE
		if card.rarity == CardDefinition.Rarity.RARE
		else COLOR_COMMON
	)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(meta)

	return panel


func _refresh_deck_list() -> void:
	if deck_list == null:
		return

	_clear_children(deck_list)

	var total: int = _get_selected_total()

	deck_count_label.text = "%d / %d" % [
		total,
		settings.deck_size
	]
	deck_count_label.add_theme_color_override(
		"font_color",
		COLOR_SUCCESS if total == settings.deck_size else COLOR_TEXT
	)

	deck_progress.value = total
	save_button.disabled = total != settings.deck_size

	var selected_cards: Array[CardDefinition] = []
	for card: CardDefinition in _get_sorted_available_cards():
		if int(selected_counts.get(card.resource_path, 0)) > 0:
			selected_cards.append(card)

	for card: CardDefinition in selected_cards:
		deck_list.add_child(_create_deck_row(card))

	if selected_cards.is_empty():
		var empty_label := Label.new()
		empty_label.text = (
			"Your deck is empty.\n"
			+ "Drag a card here or tap it to add it."
		)
		empty_label.custom_minimum_size = Vector2(0.0, 150.0)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.add_theme_font_size_override("font_size", 17)
		empty_label.add_theme_color_override("font_color", COLOR_MUTED)
		_configure_deck_drop_target(empty_label)
		deck_list.add_child(empty_label)

	if total == settings.deck_size:
		_set_status("Deck complete — ready to save.", false)
	elif total < settings.deck_size:
		_set_status(
			"Add %d more card%s."
			% [
				settings.deck_size - total,
				"" if settings.deck_size - total == 1 else "s"
			],
			false
		)


func _create_deck_row(card: CardDefinition) -> PanelContainer:
	var count: int = int(
		selected_counts.get(card.resource_path, 0)
	)
	var limit: int = settings.get_copy_limit(card)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(
		0.0,
		82.0 if _is_mobile_ui() else 70.0
	)
	if _is_mobile_ui():
		panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.tooltip_text = "Swipe right to remove one copy."
	panel.gui_input.connect(
		Callable(self, "_on_deck_row_gui_input").bind(card, panel)
	)
	panel.add_theme_stylebox_override(
		"panel",
		_make_style(
			Color(0.09, 0.115, 0.19, 1.0),
			10,
			1,
			COLOR_RARE
			if card.rarity == CardDefinition.Rarity.RARE
			else Color(0.28, 0.33, 0.45, 1.0)
		)
	)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(row)

	var mana_badge := Label.new()
	mana_badge.text = str(card.mana_cost)
	mana_badge.custom_minimum_size = Vector2(42.0, 42.0)
	mana_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mana_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mana_badge.add_theme_font_size_override("font_size", 18)
	mana_badge.add_theme_color_override("font_color", Color.WHITE)
	mana_badge.add_theme_stylebox_override(
		"normal",
		_make_style(Color(0.16, 0.38, 0.76, 1.0), 21)
	)
	mana_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mana_badge)

	var name_label := Label.new()
	name_label.text = card.display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", COLOR_TEXT)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)

	var minus_button := Button.new()
	minus_button.text = "−"
	minus_button.custom_minimum_size = Vector2(
		MOBILE_SMALL_BUTTON_SIZE if _is_mobile_ui() else 42.0,
		MOBILE_SMALL_BUTTON_SIZE if _is_mobile_ui() else 42.0
	)
	_apply_small_button_style(minus_button)
	minus_button.pressed.connect(
		Callable(self, "_remove_card_from_deck").bind(card)
	)
	row.add_child(minus_button)

	var count_label := Label.new()
	count_label.text = "%d/%d" % [count, limit]
	count_label.custom_minimum_size = Vector2(58.0, 42.0)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", 16)
	count_label.add_theme_color_override("font_color", COLOR_GOLD)
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(count_label)

	var plus_button := Button.new()
	plus_button.text = "+"
	plus_button.custom_minimum_size = Vector2(
		MOBILE_SMALL_BUTTON_SIZE if _is_mobile_ui() else 42.0,
		MOBILE_SMALL_BUTTON_SIZE if _is_mobile_ui() else 42.0
	)
	plus_button.disabled = (
		count >= limit
		or _get_selected_total() >= settings.deck_size
	)
	_apply_small_button_style(plus_button)
	plus_button.pressed.connect(
		Callable(self, "_add_card_to_deck").bind(card)
	)
	row.add_child(plus_button)

	_configure_deck_drop_target(panel)
	return panel


func _on_collection_card_gui_input(
	event: InputEvent,
	source: Control
) -> void:
	if not _is_mobile_ui():
		return

	if source == null:
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch

		if touch.pressed:
			source.set_meta(
				COLLECTION_GESTURE_START_META,
				touch.position
			)
			source.set_meta(
				COLLECTION_SCROLL_INTENT_META,
				false
			)
		else:
			source.remove_meta(COLLECTION_GESTURE_START_META)
			source.remove_meta(COLLECTION_SCROLL_INTENT_META)

		return

	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton

		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return

		if mouse_button.pressed:
			source.set_meta(
				COLLECTION_GESTURE_START_META,
				mouse_button.position
			)
			source.set_meta(
				COLLECTION_SCROLL_INTENT_META,
				false
			)
		else:
			source.remove_meta(COLLECTION_GESTURE_START_META)
			source.remove_meta(COLLECTION_SCROLL_INTENT_META)

		return

	var current_position: Vector2
	var has_position: bool = false

	if event is InputEventScreenDrag:
		current_position = (event as InputEventScreenDrag).position
		has_position = true
	elif event is InputEventMouseMotion:
		current_position = (event as InputEventMouseMotion).position
		has_position = true

	if not has_position:
		return

	var start_variant: Variant = source.get_meta(
		COLLECTION_GESTURE_START_META,
		current_position
	)
	var start_position: Vector2 = start_variant as Vector2
	var movement: Vector2 = current_position - start_position

	# Clear vertical intent only after a clearly horizontal/rightward gesture.
	# This means normal up/down swipes remain owned by ScrollContainer.
	if absf(movement.y) > absf(movement.x) * 1.15:
		source.set_meta(
			COLLECTION_SCROLL_INTENT_META,
			true
		)


func _collection_drag_should_scroll(
	at_position: Vector2,
	source: Control
) -> bool:
	if not _is_mobile_ui():
		return false

	if source == null:
		return false

	if bool(
		source.get_meta(
			COLLECTION_SCROLL_INTENT_META,
			false
		)
	):
		return true

	if not source.has_meta(COLLECTION_GESTURE_START_META):
		return false

	var start_position: Vector2 = source.get_meta(
		COLLECTION_GESTURE_START_META
	) as Vector2
	var movement: Vector2 = at_position - start_position

	return absf(movement.y) > absf(movement.x) * 1.15


func _get_collection_drag_data(
	at_position: Vector2,
	card: CardDefinition,
	source: Control
) -> Variant:
	if _collection_drag_should_scroll(at_position, source):
		return null

	if not _can_add_card_to_deck(card):
		return null

	var preview_frame := PanelContainer.new()
	preview_frame.custom_minimum_size = Vector2(160.0, 220.0)
	preview_frame.modulate = Color(1.0, 1.0, 1.0, 0.92)
	preview_frame.add_theme_stylebox_override(
		"panel",
		_make_style(
			Color(0.04, 0.055, 0.11, 0.94),
			12,
			2,
			COLOR_GOLD
		)
	)

	var preview := TextureRect.new()
	preview.texture = card.front_texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_frame.add_child(preview)
	source.set_drag_preview(preview_frame)

	return {
		"type": CARD_DRAG_DATA_TYPE,
		"card_path": card.resource_path
	}


func _configure_deck_drop_target(control: Control) -> void:
	if control == null:
		return

	if bool(control.get_meta(DECK_DROP_BLOCK_META, false)):
		return

	# Interactive controls must keep their own touch/click handling.
	# Applying drag forwarding recursively to BACK / CLEAR / SAVE / +/- could
	# interfere with their button input, especially on touch devices.
	if (
		control is BaseButton
		or control is LineEdit
		or control is ScrollBar
	):
		return

	control.set_drag_forwarding(
		Callable(),
		Callable(self, "_can_drop_card_on_deck"),
		Callable(self, "_drop_card_on_deck")
	)

	for child: Node in control.get_children():
		if child is Control:
			_configure_deck_drop_target(child as Control)


func _can_drop_card_on_deck(
	_at_position: Vector2,
	data: Variant
) -> bool:
	var card: CardDefinition = _get_dragged_card(data)
	return _can_add_card_to_deck(card)


func _drop_card_on_deck(
	_at_position: Vector2,
	data: Variant
) -> void:
	var card: CardDefinition = _get_dragged_card(data)
	if card != null:
		_add_card_to_deck(card)


func _get_dragged_card(data: Variant) -> CardDefinition:
	if data is not Dictionary:
		return null

	var drag_data: Dictionary = data
	if str(drag_data.get("type", "")) != CARD_DRAG_DATA_TYPE:
		return null

	var path: String = str(drag_data.get("card_path", ""))
	return card_by_path.get(path, null) as CardDefinition


func _can_add_card_to_deck(card: CardDefinition) -> bool:
	if card == null or not settings.is_card_available(card):
		return false

	if _get_selected_total() >= settings.deck_size:
		return false

	var copies: int = int(
		selected_counts.get(card.resource_path, 0)
	)
	return copies < settings.get_copy_limit(card)


func _on_deck_row_gui_input(
	event: InputEvent,
	card: CardDefinition,
	panel: PanelContainer
) -> void:
	if not is_instance_valid(panel):
		return

	if bool(panel.get_meta(DECK_ROW_SWIPE_ANIMATING_META, false)):
		return

	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return

		if mouse_button.pressed:
			_begin_deck_row_swipe(panel, mouse_button.global_position)
		else:
			_finish_deck_row_swipe(
				panel,
				card,
				mouse_button.global_position
			)
		return

	if event is InputEventMouseMotion:
		var mouse_motion := event as InputEventMouseMotion
		if (
			mouse_motion.button_mask & MOUSE_BUTTON_MASK_LEFT
		) != 0:
			_update_deck_row_swipe(panel, mouse_motion.global_position)
		return

	if event is InputEventScreenTouch:
		var screen_touch := event as InputEventScreenTouch
		if screen_touch.pressed:
			_begin_deck_row_swipe(panel, screen_touch.position)
		else:
			_finish_deck_row_swipe(
				panel,
				card,
				screen_touch.position
			)
		return

	if event is InputEventScreenDrag:
		var screen_drag := event as InputEventScreenDrag
		_update_deck_row_swipe(panel, screen_drag.position)


func _begin_deck_row_swipe(
	panel: PanelContainer,
	pointer_position: Vector2
) -> void:
	panel.set_meta(DECK_ROW_SWIPE_START_META, pointer_position)
	panel.set_meta(DECK_ROW_SWIPE_ACTIVE_META, true)


func _update_deck_row_swipe(
	panel: PanelContainer,
	pointer_position: Vector2
) -> void:
	if not bool(panel.get_meta(DECK_ROW_SWIPE_ACTIVE_META, false)):
		return

	var start_position: Vector2 = _get_deck_row_swipe_start(
		panel,
		pointer_position
	)
	var movement: Vector2 = pointer_position - start_position
	var abs_x: float = absf(movement.x)
	var abs_y: float = absf(movement.y)

	# Mobile priority: if the gesture is mainly vertical, immediately give it
	# to the parent ScrollContainer instead of keeping the row in swipe mode.
	if _is_mobile_ui() and abs_y > abs_x * 0.85:
		panel.set_meta(DECK_ROW_SWIPE_ACTIVE_META, false)
		panel.position.x = 0.0
		return

	# Do not visually drag a deck row until the user has clearly intended
	# a horizontal right-swipe. This prevents tiny finger wobble while scrolling.
	if movement.x <= 12.0 or abs_x <= abs_y * 1.15:
		panel.position.x = 0.0
		return

	panel.position.x = minf(
		movement.x,
		DECK_ROW_SWIPE_MAX_OFFSET
	)


func _finish_deck_row_swipe(
	panel: PanelContainer,
	card: CardDefinition,
	pointer_position: Vector2
) -> void:
	if not bool(panel.get_meta(DECK_ROW_SWIPE_ACTIVE_META, false)):
		return

	panel.set_meta(DECK_ROW_SWIPE_ACTIVE_META, false)

	var start_position: Vector2 = _get_deck_row_swipe_start(
		panel,
		pointer_position
	)
	var movement: Vector2 = pointer_position - start_position
	var is_right_swipe: bool = (
		movement.x >= DECK_ROW_SWIPE_THRESHOLD
		and movement.x >= absf(movement.y)
	)

	if is_right_swipe:
		panel.set_meta(DECK_ROW_SWIPE_ANIMATING_META, true)
		var remove_tween := panel.create_tween()
		remove_tween.set_parallel(true)
		remove_tween.set_trans(Tween.TRANS_QUAD)
		remove_tween.set_ease(Tween.EASE_IN)
		remove_tween.tween_property(
			panel,
			"position:x",
			DECK_ROW_SWIPE_MAX_OFFSET + 100.0,
			0.12
		)
		remove_tween.tween_property(
			panel,
			"modulate:a",
			0.0,
			0.12
		)
		remove_tween.chain().tween_callback(
			Callable(self, "_remove_card_from_deck").bind(card)
		)
		return

	var reset_tween := panel.create_tween()
	reset_tween.set_trans(Tween.TRANS_QUAD)
	reset_tween.set_ease(Tween.EASE_OUT)
	reset_tween.tween_property(panel, "position:x", 0.0, 0.12)


func _get_deck_row_swipe_start(
	panel: PanelContainer,
	fallback: Vector2
) -> Vector2:
	var raw_start: Variant = panel.get_meta(
		DECK_ROW_SWIPE_START_META,
		fallback
	)
	if raw_start is Vector2:
		return raw_start

	return fallback


func _on_collection_card_pressed(card: CardDefinition) -> void:
	_add_card_to_deck(card)


func _add_card_to_deck(card: CardDefinition) -> void:
	if card == null:
		return

	var total: int = _get_selected_total()
	if total >= settings.deck_size:
		_set_status("The deck is already full.", true)
		return

	var path: String = card.resource_path
	var current_count: int = int(
		selected_counts.get(path, 0)
	)
	var limit: int = settings.get_copy_limit(card)

	if current_count >= limit:
		_set_status(
			"%s is limited to %d copies."
			% [card.display_name, limit],
			true
		)
		return

	selected_counts[path] = current_count + 1
	custom_deck_saved = false
	_refresh_builder_views()


func _remove_card_from_deck(card: CardDefinition) -> void:
	if card == null:
		return

	var path: String = card.resource_path
	var current_count: int = int(
		selected_counts.get(path, 0)
	)

	if current_count <= 1:
		selected_counts.erase(path)
	else:
		selected_counts[path] = current_count - 1

	custom_deck_saved = false
	_refresh_builder_views()


func _refresh_builder_views() -> void:
	_refresh_card_library()
	_refresh_deck_list()


func _on_card_filter_changed(_new_text: String) -> void:
	_refresh_card_library()


func _on_rarity_filter_changed(_index: int) -> void:
	_refresh_card_library()


func _on_deck_name_changed(new_name: String) -> void:
	custom_deck_name = new_name.strip_edges()
	custom_deck_saved = false


func _on_clear_deck_pressed() -> void:
	selected_counts.clear()
	custom_deck_saved = false
	_refresh_builder_views()
	_set_status("Deck cleared.", false)


func _on_builder_back_pressed() -> void:
	# Back acts as Cancel. Working values are separate from custom_decks, so
	# unfinished edits never overwrite a saved deck.
	_show_selection_page()


func _on_save_deck_pressed() -> void:
	if not _is_custom_deck_complete():
		_set_status(
			"The deck must contain exactly %d cards."
			% settings.deck_size,
			true
		)
		return

	if custom_deck_name.is_empty():
		custom_deck_name = "Custom Deck %d" % (
			active_custom_deck_index + 1
			if active_custom_deck_index >= 0
			else custom_decks.size() + 1
		)
		deck_name_edit.text = custom_deck_name

	var decks_to_save: Array[Dictionary] = _copy_custom_decks()
	var saved_deck: Dictionary = {
		"name": custom_deck_name,
		"counts": selected_counts.duplicate(true)
	}

	if (
		active_custom_deck_index >= 0
		and active_custom_deck_index < decks_to_save.size()
	):
		decks_to_save[active_custom_deck_index] = saved_deck
	else:
		decks_to_save.append(saved_deck)
		active_custom_deck_index = decks_to_save.size() - 1

	var save_error: Error = _save_custom_decks(decks_to_save)
	if save_error != OK:
		_set_status("Could not save the deck.", true)
		push_error(
			"Could not save custom decks: " + error_string(save_error)
		)
		return

	custom_decks = decks_to_save
	custom_deck_saved = true
	_show_selection_page()


func _copy_custom_decks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for saved_deck: Dictionary in custom_decks:
		result.append(saved_deck.duplicate(true))

	return result


func _save_custom_decks(decks_to_save: Array[Dictionary]) -> Error:
	var config := ConfigFile.new()
	config.set_value(
		SAVE_META_SECTION,
		SAVE_COUNT_KEY,
		decks_to_save.size()
	)

	for index: int in range(decks_to_save.size()):
		var saved_deck: Dictionary = decks_to_save[index]
		var section: String = SAVE_SECTION_PREFIX + str(index + 1)
		var counts: Dictionary = _get_saved_deck_counts(saved_deck)

		config.set_value(
			section,
			SAVE_NAME_KEY,
			str(saved_deck.get("name", "Custom Deck"))
		)
		config.set_value(
			section,
			SAVE_CARDS_KEY,
			_counts_to_card_paths(counts)
		)

	return config.save(SAVE_PATH)


func _counts_to_card_paths(counts: Dictionary) -> PackedStringArray:
	var card_paths := PackedStringArray()

	for card: CardDefinition in _get_sorted_available_cards():
		var copies: int = int(
			counts.get(card.resource_path, 0)
		)

		for _copy_index: int in range(copies):
			card_paths.append(card.resource_path)

	return card_paths


func _get_saved_deck_counts(saved_deck: Dictionary) -> Dictionary:
	var raw_counts: Variant = saved_deck.get("counts", {})
	if raw_counts is Dictionary:
		return raw_counts

	return {}


func _load_custom_decks() -> void:
	custom_decks.clear()
	selected_counts.clear()
	active_custom_deck_index = -1
	custom_deck_name = "Custom Deck"
	custom_deck_saved = false

	var config := ConfigFile.new()
	var load_error: Error = config.load(SAVE_PATH)

	if load_error != OK:
		return

	var deck_count: int = int(
		config.get_value(
			SAVE_META_SECTION,
			SAVE_COUNT_KEY,
			-1
		)
	)

	# Migration: the first version saved one deck directly in custom_deck_1.
	if deck_count < 0:
		deck_count = (
			1
			if config.has_section(SAVE_SECTION_PREFIX + "1")
			else 0
		)

	for index: int in range(maxi(0, deck_count)):
		var section: String = SAVE_SECTION_PREFIX + str(index + 1)
		if not config.has_section(section):
			continue

		var deck_name: String = str(
			config.get_value(
				section,
				SAVE_NAME_KEY,
				"Custom Deck %d" % (index + 1)
			)
		).strip_edges()

		if deck_name.is_empty():
			deck_name = "Custom Deck %d" % (index + 1)

		var stored_paths: Variant = config.get_value(
			section,
			SAVE_CARDS_KEY,
			PackedStringArray()
		)
		var counts: Dictionary = _card_paths_to_counts(stored_paths)

		custom_decks.append({
			"name": deck_name,
			"counts": counts
		})


func _card_paths_to_counts(stored_paths: Variant) -> Dictionary:
	var result: Dictionary = {}

	if not (
		stored_paths is PackedStringArray
		or stored_paths is Array
	):
		return result

	for raw_path: Variant in stored_paths:
		if _get_counts_total(result) >= settings.deck_size:
			break

		var path: String = str(raw_path)
		var card: CardDefinition = card_by_path.get(
			path,
			null
		) as CardDefinition

		if card == null:
			continue

		var current_count: int = int(result.get(path, 0))
		if current_count >= settings.get_copy_limit(card):
			continue

		result[path] = current_count + 1

	return result


func _on_preset_selected(index: int) -> void:
	if index < 0 or index >= preset_decks.size():
		return

	var selected_deck: DeckDefinition = preset_decks[index]
	if selected_deck == null:
		return

	deck_selected.emit(selected_deck)


func _on_custom_deck_selected(index: int) -> void:
	if index < 0 or index >= custom_decks.size():
		return

	var saved_deck: Dictionary = custom_decks[index]
	var counts: Dictionary = _get_saved_deck_counts(saved_deck)
	var custom_deck: DeckDefinition = _build_custom_deck_definition(counts)

	if custom_deck == null:
		_edit_custom_deck(index)
		_set_status(
			"Complete and save this deck before using it.",
			true
		)
		return

	deck_selected.emit(custom_deck)


func _build_custom_deck_definition(
	counts: Dictionary
) -> DeckDefinition:
	if not _is_counts_complete(counts):
		return null

	var result := DeckDefinition.new()

	for card: CardDefinition in _get_sorted_available_cards():
		var copies: int = int(
			counts.get(card.resource_path, 0)
		)

		if copies <= 0:
			continue

		var entry := DeckEntry.new()
		entry.card = card
		entry.copies = copies
		result.entries.append(entry)

	return result


func _get_selected_total() -> int:
	return _get_counts_total(selected_counts)


func _get_counts_total(counts: Dictionary) -> int:
	var total: int = 0

	for raw_count: Variant in counts.values():
		total += int(raw_count)

	return total


func _is_custom_deck_complete() -> bool:
	return _is_counts_complete(selected_counts)


func _is_counts_complete(counts: Dictionary) -> bool:
	if _get_counts_total(counts) != settings.deck_size:
		return false

	for raw_path: Variant in counts.keys():
		var path: String = str(raw_path)
		var card: CardDefinition = card_by_path.get(
			path,
			null
		) as CardDefinition
		var copies: int = int(counts.get(raw_path, 0))

		if card == null:
			return false

		if copies <= 0 or copies > settings.get_copy_limit(card):
			return false

	return true


func _get_custom_preview(counts: Dictionary) -> CardDefinition:
	for card: CardDefinition in _get_sorted_available_cards():
		if int(counts.get(card.resource_path, 0)) > 0:
			return card

	return null


func _get_deck_preview(deck: DeckDefinition) -> CardDefinition:
	if deck == null:
		return null

	for entry: DeckEntry in deck.entries:
		if entry != null and entry.card != null:
			return entry.card

	return null


func _get_sorted_available_cards() -> Array[CardDefinition]:
	var result: Array[CardDefinition] = []

	for card: CardDefinition in settings.available_cards:
		if card != null:
			result.append(card)

	result.sort_custom(
		Callable(self, "_sort_cards")
	)

	return result


func _sort_cards(
	first: CardDefinition,
	second: CardDefinition
) -> bool:
	if first.mana_cost != second.mana_cost:
		return first.mana_cost < second.mana_cost

	return (
		first.display_name.nocasecmp_to(second.display_name)
		< 0
	)


func _get_rarity_name(card: CardDefinition) -> String:
	if card.rarity == CardDefinition.Rarity.RARE:
		return "RARE"

	return "COMMON"


func _get_card_tooltip(card: CardDefinition) -> String:
	return "%s\nMana: %d\n%s • Max copies: %d" % [
		card.display_name,
		card.mana_cost,
		_get_rarity_name(card),
		settings.get_copy_limit(card)
	]


func _set_status(message: String, is_error: bool) -> void:
	if status_label == null:
		return

	status_label.text = message
	status_label.add_theme_color_override(
		"font_color",
		COLOR_ERROR if is_error else COLOR_MUTED
	)


func _clear_content_host() -> void:
	if content_host == null:
		return

	_clear_children(content_host)

	card_grid = null
	card_scroll = null
	deck_list = null
	deck_count_label = null
	deck_progress = null
	save_button = null
	status_label = null
	search_edit = null
	rarity_filter = null
	deck_name_edit = null


func _clear_children(parent: Node) -> void:
	if parent == null:
		return

	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _play_open_animation() -> void:
	if root_control == null:
		return

	root_control.modulate.a = 0.0
	root_control.scale = Vector2(0.985, 0.985)
	root_control.pivot_offset = get_viewport().get_visible_rect().size * 0.5

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(root_control, "modulate:a", 1.0, 0.22)
	tween.tween_property(root_control, "scale", Vector2.ONE, 0.22)


func _make_style(
	background_color: Color,
	corner_radius: int,
	border_width: int = 0,
	border_color: Color = Color.TRANSPARENT
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.corner_radius_bottom_right = corner_radius
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.border_color = border_color
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	return style


func _apply_primary_button_style(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color(0.08, 0.06, 0.025, 1.0))
	button.add_theme_color_override("font_hover_color", Color(0.05, 0.04, 0.02, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.05, 0.04, 0.02, 1.0))
	button.add_theme_stylebox_override(
		"normal",
		_make_style(COLOR_GOLD, 10)
	)
	button.add_theme_stylebox_override(
		"hover",
		_make_style(Color(1.0, 0.79, 0.34, 1.0), 10)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_make_style(Color(0.78, 0.50, 0.12, 1.0), 10)
	)
	button.add_theme_stylebox_override(
		"disabled",
		_make_style(Color(0.25, 0.27, 0.32, 1.0), 10)
	)


func _apply_secondary_button_style(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_stylebox_override(
		"normal",
		_make_style(Color(0.11, 0.14, 0.22, 1.0), 10, 1, Color(0.3, 0.37, 0.54, 1.0))
	)
	button.add_theme_stylebox_override(
		"hover",
		_make_style(Color(0.16, 0.20, 0.31, 1.0), 10, 1, COLOR_RARE)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_make_style(Color(0.08, 0.10, 0.17, 1.0), 10, 1, COLOR_RARE)
	)


func _apply_small_button_style(button: Button) -> void:
	button.add_theme_font_size_override(
		"font_size",
		24 if _is_mobile_ui() else 20
	)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_stylebox_override(
		"normal",
		_make_style(Color(0.14, 0.18, 0.28, 1.0), 8)
	)
	button.add_theme_stylebox_override(
		"hover",
		_make_style(Color(0.22, 0.30, 0.48, 1.0), 8)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_make_style(Color(0.08, 0.10, 0.18, 1.0), 8)
	)
