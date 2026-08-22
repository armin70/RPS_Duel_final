class_name RushSacrificeControl
extends Control


signal sacrifice_drop_requested(screen_position: Vector2)
signal gesture_chosen(gesture: int)
signal choice_cancelled


var sacrifice_button: Button
var instruction_label: Label
var arrow_line: Line2D
var arrow_head: Polygon2D
var choice_panel: PanelContainer
var choice_title: Label
var rock_button: Button
var paper_button: Button
var scissors_button: Button
var cancel_button: Button
var remaining_cards_button: Button
var remaining_cards_panel: PanelContainer
var remaining_cards_grid: GridContainer
var remaining_cards_title: Label
var remaining_cards_empty_label: Label
var cached_remaining_cards: Array[CardInstance] = []

var rush_note_overlay: Control
var rush_note_texture: TextureRect
var rush_note_understood_button: TextureButton
var rush_note_has_been_shown: bool = false
var rush_note_previous_pause_state: bool = false

var drag_active: bool = false
var drag_moved: bool = false
var drag_start: Vector2 = Vector2.ZERO
var rush_visible: bool = false
var interaction_available: bool = false
var message_serial: int = 0

const DRAG_THRESHOLD: float = 12.0

# ------------------------------------------------------------------
# EASY UI POSITION SETTINGS
# Change only these values if you want to move the two Rush buttons.
# Smaller Y = higher on screen, larger Y = lower on screen.
# X is the distance from the left edge.
# ------------------------------------------------------------------
const RUSH_LEFT_BUTTON_X: float = 40.0
const SACRIFICE_BUTTON_Y: float = 0.38
const MY_CARDS_BUTTON_Y: float = 0.49

const RUSH_NOTE_TEXTURE_PATH: String = "res://art/rush_mode_note.png"
const UNDERSTOOD_TEXTURE_PATH: String = "res://art/iunderstand.png"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	set_rush_visible(false)


func _build_ui() -> void:
	sacrifice_button = Button.new()
	sacrifice_button.name = "RushSacrificeButton"
	sacrifice_button.text = "SACRIFICE\nروی کارت بکش"
	sacrifice_button.focus_mode = Control.FOCUS_NONE
	sacrifice_button.mouse_filter = Control.MOUSE_FILTER_STOP
	sacrifice_button.anchor_left = 0.0
	sacrifice_button.anchor_top = SACRIFICE_BUTTON_Y
	sacrifice_button.anchor_right = 0.0
	sacrifice_button.anchor_bottom = SACRIFICE_BUTTON_Y
	sacrifice_button.offset_left = RUSH_LEFT_BUTTON_X
	sacrifice_button.offset_top = -40.0
	sacrifice_button.offset_right = 300.0
	sacrifice_button.offset_bottom = 40.0
	sacrifice_button.add_theme_font_size_override("font_size", 24)
	add_child(sacrifice_button)

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.08, 0.035, 0.10, 0.94)
	normal_style.border_color = Color(0.95, 0.48, 0.90, 0.95)
	normal_style.set_border_width_all(2)
	normal_style.set_corner_radius_all(12)

	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.16, 0.05, 0.18, 0.98)
	hover_style.border_color = Color(1.0, 0.72, 0.96, 1.0)

	sacrifice_button.add_theme_stylebox_override("normal", normal_style)
	sacrifice_button.add_theme_stylebox_override("hover", hover_style)
	sacrifice_button.add_theme_stylebox_override("pressed", hover_style)
	sacrifice_button.button_down.connect(_on_sacrifice_button_down)
	sacrifice_button.pressed.connect(_on_sacrifice_button_tapped)

	remaining_cards_button = Button.new()
	remaining_cards_button.name = "RushRemainingCardsButton"
	remaining_cards_button.text = "MY CARDS\nView remaining"
	remaining_cards_button.focus_mode = Control.FOCUS_NONE
	remaining_cards_button.mouse_filter = Control.MOUSE_FILTER_STOP
	remaining_cards_button.anchor_left = 0.0
	remaining_cards_button.anchor_top = MY_CARDS_BUTTON_Y
	remaining_cards_button.anchor_right = 0.0
	remaining_cards_button.anchor_bottom = MY_CARDS_BUTTON_Y
	remaining_cards_button.offset_left = RUSH_LEFT_BUTTON_X
	remaining_cards_button.offset_top = -40.0
	remaining_cards_button.offset_right = 300.0
	remaining_cards_button.offset_bottom = 40.0
	remaining_cards_button.add_theme_font_size_override("font_size", 22)
	remaining_cards_button.add_theme_stylebox_override("normal", normal_style.duplicate())
	remaining_cards_button.add_theme_stylebox_override("hover", hover_style.duplicate())
	remaining_cards_button.add_theme_stylebox_override("pressed", hover_style.duplicate())
	remaining_cards_button.pressed.connect(_on_remaining_cards_pressed)
	add_child(remaining_cards_button)

	instruction_label = Label.new()
	instruction_label.name = "RushSacrificeInstruction"
	instruction_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	instruction_label.anchor_left = 0.0
	instruction_label.anchor_top = 0.42
	instruction_label.anchor_right = 0.0
	instruction_label.anchor_bottom = 0.52
	instruction_label.offset_left = 18.0
	instruction_label.offset_top = -104.0
	instruction_label.offset_right = 470.0
	instruction_label.offset_bottom = -42.0
	instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction_label.add_theme_font_size_override("font_size", 16)
	instruction_label.add_theme_color_override("font_outline_color", Color.BLACK)
	instruction_label.add_theme_constant_override("outline_size", 5)
	instruction_label.visible = false
	add_child(instruction_label)

	arrow_line = Line2D.new()
	arrow_line.name = "SacrificeArrowLine"
	arrow_line.width = 6.0
	arrow_line.default_color = Color(1.0, 0.58, 0.92, 0.96)
	arrow_line.antialiased = true
	arrow_line.z_index = 200
	arrow_line.visible = false
	add_child(arrow_line)

	arrow_head = Polygon2D.new()
	arrow_head.name = "SacrificeArrowHead"
	arrow_head.polygon = PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(-18.0, -10.0),
		Vector2(-18.0, 10.0)
	])
	arrow_head.color = Color(1.0, 0.58, 0.92, 0.96)
	arrow_head.z_index = 201
	arrow_head.visible = false
	add_child(arrow_head)

	choice_panel = PanelContainer.new()
	choice_panel.name = "RushGestureChoicePanel"
	choice_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	choice_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	choice_panel.anchor_left = 0.5
	choice_panel.anchor_top = 0.5
	choice_panel.anchor_right = 0.5
	choice_panel.anchor_bottom = 0.5
	choice_panel.offset_left = -235.0
	choice_panel.offset_top = -118.0
	choice_panel.offset_right = 235.0
	choice_panel.offset_bottom = 118.0
	choice_panel.z_index = 300
	choice_panel.visible = false
	add_child(choice_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.03, 0.055, 0.98)
	panel_style.border_color = Color(0.90, 0.46, 0.88, 1.0)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(16)
	choice_panel.add_theme_stylebox_override("panel", panel_style)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	choice_panel.add_child(content)

	choice_title = Label.new()
	choice_title.text = "نوع جدید کارت را انتخاب کن"
	choice_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	choice_title.add_theme_font_size_override("font_size", 22)
	content.add_child(choice_title)

	var warning := Label.new()
	warning.text = "یک کارت تصادفی دیگر از زمینت برای همیشه حذف می‌شود."
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.add_theme_font_size_override("font_size", 14)
	content.add_child(warning)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	content.add_child(row)

	rock_button = _make_choice_button("ROCK", CardGesture.Type.ROCK)
	paper_button = _make_choice_button("PAPER", CardGesture.Type.PAPER)
	scissors_button = _make_choice_button("SCISSORS", CardGesture.Type.SCISSORS)
	row.add_child(rock_button)
	row.add_child(paper_button)
	row.add_child(scissors_button)

	cancel_button = Button.new()
	cancel_button.text = "CANCEL"
	cancel_button.focus_mode = Control.FOCUS_NONE
	cancel_button.custom_minimum_size = Vector2(150.0, 42.0)
	cancel_button.pressed.connect(_on_choice_cancelled)
	content.add_child(cancel_button)

	_build_remaining_cards_panel()
	_build_rush_note()


func _build_rush_note() -> void:
	rush_note_overlay = Control.new()
	rush_note_overlay.name = "RushModeExplanationNote"
	rush_note_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	rush_note_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	rush_note_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rush_note_overlay.z_index = 600
	rush_note_overlay.visible = false
	add_child(rush_note_overlay)

	var dim := ColorRect.new()
	dim.name = "DimBackground"
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	rush_note_overlay.add_child(dim)

	rush_note_texture = TextureRect.new()
	rush_note_texture.name = "RushModeNoteImage"
	rush_note_texture.anchor_left = 0.06
	rush_note_texture.anchor_top = 0.05
	rush_note_texture.anchor_right = 0.94
	rush_note_texture.anchor_bottom = 0.83
	rush_note_texture.offset_left = 0.0
	rush_note_texture.offset_top = 0.0
	rush_note_texture.offset_right = 0.0
	rush_note_texture.offset_bottom = 0.0
	rush_note_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rush_note_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rush_note_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rush_note_texture.texture = load(RUSH_NOTE_TEXTURE_PATH) as Texture2D
	rush_note_overlay.add_child(rush_note_texture)

	rush_note_understood_button = TextureButton.new()
	rush_note_understood_button.name = "RushUnderstoodButton"
	rush_note_understood_button.anchor_left = 0.5
	rush_note_understood_button.anchor_top = 1.0
	rush_note_understood_button.anchor_right = 0.5
	rush_note_understood_button.anchor_bottom = 1.0
	rush_note_understood_button.offset_left = -210.0
	rush_note_understood_button.offset_top = -175.0
	rush_note_understood_button.offset_right = 210.0
	rush_note_understood_button.offset_bottom = -25.0
	rush_note_understood_button.ignore_texture_size = true
	rush_note_understood_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	rush_note_understood_button.focus_mode = Control.FOCUS_NONE
	rush_note_understood_button.mouse_filter = Control.MOUSE_FILTER_STOP

	var understood_texture := load(UNDERSTOOD_TEXTURE_PATH) as Texture2D
	if understood_texture != null:
		rush_note_understood_button.texture_normal = understood_texture
		rush_note_understood_button.texture_pressed = understood_texture
		rush_note_understood_button.texture_hover = understood_texture

	rush_note_understood_button.pressed.connect(_on_rush_note_understood)
	rush_note_overlay.add_child(rush_note_understood_button)

	# Fallback text keeps the note usable even if the old texture asset
	# is temporarily missing while files are being copied between builds.
	if understood_texture == null:
		var fallback := Label.new()
		fallback.text = "متوجه شدم"
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fallback.add_theme_font_size_override("font_size", 28)
		rush_note_understood_button.add_child(fallback)


func _show_rush_note() -> void:
	if rush_note_overlay == null or rush_note_has_been_shown:
		return

	rush_note_has_been_shown = true
	cancel_drag()
	hide_gesture_choices()
	_hide_remaining_cards()
	rush_note_overlay.visible = true

	var tree := get_tree()
	if tree != null:
		rush_note_previous_pause_state = tree.paused
		tree.paused = true


func _hide_rush_note(restore_pause: bool = true) -> void:
	if rush_note_overlay != null:
		rush_note_overlay.visible = false

	if restore_pause:
		var tree := get_tree()
		if tree != null:
			tree.paused = rush_note_previous_pause_state


func _on_rush_note_understood() -> void:
	_hide_rush_note(true)


func _build_remaining_cards_panel() -> void:
	remaining_cards_panel = PanelContainer.new()
	remaining_cards_panel.name = "RushRemainingCardsPanel"
	remaining_cards_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	remaining_cards_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	remaining_cards_panel.anchor_left = 0.5
	remaining_cards_panel.anchor_top = 0.5
	remaining_cards_panel.anchor_right = 0.5
	remaining_cards_panel.anchor_bottom = 0.5
	remaining_cards_panel.offset_left = -390.0
	remaining_cards_panel.offset_top = -330.0
	remaining_cards_panel.offset_right = 390.0
	remaining_cards_panel.offset_bottom = 330.0
	remaining_cards_panel.z_index = 320
	remaining_cards_panel.visible = false
	add_child(remaining_cards_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.02, 0.025, 0.045, 0.985)
	panel_style.border_color = Color(0.68, 0.76, 1.0, 0.98)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(16)
	remaining_cards_panel.add_theme_stylebox_override("panel", panel_style)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	remaining_cards_panel.add_child(root)

	remaining_cards_title = Label.new()
	remaining_cards_title.text = "MY REMAINING CARDS"
	remaining_cards_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	remaining_cards_title.add_theme_font_size_override("font_size", 24)
	root.add_child(remaining_cards_title)

	var hint := Label.new()
	hint.text = "These are every card you still own in this Rush match."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	root.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 510.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root.add_child(scroll)

	remaining_cards_grid = GridContainer.new()
	remaining_cards_grid.columns = 4
	remaining_cards_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remaining_cards_grid.add_theme_constant_override("h_separation", 12)
	remaining_cards_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(remaining_cards_grid)

	remaining_cards_empty_label = Label.new()
	remaining_cards_empty_label.text = "No cards remaining."
	remaining_cards_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	remaining_cards_empty_label.visible = false
	root.add_child(remaining_cards_empty_label)

	var close := Button.new()
	close.text = "CLOSE"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(170.0, 46.0)
	close.pressed.connect(_hide_remaining_cards)
	root.add_child(close)


func _make_choice_button(text: String, gesture: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(120.0, 54.0)
	button.add_theme_font_size_override("font_size", 17)
	button.pressed.connect(_on_gesture_button_pressed.bind(gesture))
	return button


func set_rush_visible(value: bool) -> void:
	var was_visible: bool = rush_visible
	rush_visible = value
	visible = value

	if value and not was_visible and not rush_note_has_been_shown:
		_show_rush_note()

	if not value:
		cancel_drag()
		hide_gesture_choices()
		_hide_remaining_cards()
		if rush_note_overlay != null and rush_note_overlay.visible:
			_hide_rush_note(true)


func set_interaction_available(value: bool) -> void:
	interaction_available = value
	if sacrifice_button != null:
		sacrifice_button.disabled = not value
	if not value:
		cancel_drag()


func set_remaining_cards(cards: Array[CardInstance]) -> void:
	cached_remaining_cards = cards.duplicate()
	if remaining_cards_title != null:
		remaining_cards_title.text = "MY REMAINING CARDS  •  %d" % cached_remaining_cards.size()
	if remaining_cards_panel != null and remaining_cards_panel.visible:
		_rebuild_remaining_cards_grid()


func _on_remaining_cards_pressed() -> void:
	if not rush_visible or remaining_cards_panel == null:
		return
	cancel_drag()
	hide_gesture_choices()
	_rebuild_remaining_cards_grid()
	remaining_cards_panel.visible = true


func _hide_remaining_cards() -> void:
	if remaining_cards_panel != null:
		remaining_cards_panel.visible = false


func _rebuild_remaining_cards_grid() -> void:
	if remaining_cards_grid == null:
		return

	for child: Node in remaining_cards_grid.get_children():
		child.queue_free()

	if remaining_cards_empty_label != null:
		remaining_cards_empty_label.visible = cached_remaining_cards.is_empty()

	for card: CardInstance in cached_remaining_cards:
		if card == null or card.definition == null:
			continue
		remaining_cards_grid.add_child(_make_remaining_card_tile(card))


func _make_remaining_card_tile(card: CardInstance) -> Control:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(172.0, 224.0)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tile_style := StyleBoxFlat.new()
	tile_style.bg_color = Color(0.055, 0.065, 0.095, 0.98)
	tile_style.border_color = Color(0.28, 0.34, 0.52, 0.95)
	tile_style.set_border_width_all(1)
	tile_style.set_corner_radius_all(10)
	tile.add_theme_stylebox_override("panel", tile_style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	tile.add_child(box)

	var picture := TextureRect.new()
	picture.custom_minimum_size = Vector2(152.0, 154.0)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.texture = card.definition.front_texture
	box.add_child(picture)

	var name_label := Label.new()
	name_label.text = card.definition.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 14)
	box.add_child(name_label)

	var type_label := Label.new()
	type_label.text = "%s  •  %s" % [
		_gesture_name(card.get_gesture()),
		_zone_name(card.zone)
	]
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.add_theme_font_size_override("font_size", 12)
	if card.has_gesture_override():
		type_label.text += "  •  CHANGED"
	box.add_child(type_label)

	return tile


func _gesture_name(gesture: int) -> String:
	match gesture:
		CardGesture.Type.ROCK:
			return "ROCK"
		CardGesture.Type.PAPER:
			return "PAPER"
		CardGesture.Type.SCISSORS:
			return "SCISSORS"
		_:
			return "OTHER"


func _zone_name(zone: int) -> String:
	match zone:
		CardZone.Type.HAND:
			return "HAND"
		CardZone.Type.BOARD:
			return "BOARD"
		CardZone.Type.DRAW:
			return "DRAW"
		CardZone.Type.DISCARD:
			return "DISCARD"
		CardZone.Type.RESERVE:
			return "RESERVE"
		_:
			return "IN PLAY"


func _on_sacrifice_button_down() -> void:
	if not rush_visible or not interaction_available:
		return
	if choice_panel != null and choice_panel.visible:
		return

	drag_active = true
	drag_moved = false
	drag_start = sacrifice_button.get_global_rect().get_center()
	_update_arrow(drag_start)
	arrow_line.visible = true
	arrow_head.visible = true
	show_message(
		"من را روی کارتی که می‌خواهی تغییر بدهی بکش. "
		+ "بعد نوع جدیدش را انتخاب کن. یک کارت تصادفی دیگر از زمینت حذف می‌شود."
	)


func _on_sacrifice_button_tapped() -> void:
	if not rush_visible:
		return
	show_message(
		"این دکمه را روی کارت موردنظرت بکش. بعد از انتخاب ROCK، PAPER یا SCISSORS، "
		+ "یک کارت تصادفی دیگر از زمینت برای همیشه فدا و حذف می‌شود."
	)


func _input(event: InputEvent) -> void:
	if not drag_active:
		return

	var pointer_position: Vector2
	var has_position: bool = false
	var released: bool = false

	if event is InputEventScreenDrag:
		pointer_position = event.position
		has_position = true
	elif event is InputEventMouseMotion:
		pointer_position = event.position
		has_position = true
	elif event is InputEventScreenTouch:
		pointer_position = event.position
		has_position = true
		released = not event.pressed
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			pointer_position = event.position
			has_position = true
			released = not event.pressed

	if not has_position:
		return

	if not drag_moved and pointer_position.distance_to(drag_start) >= DRAG_THRESHOLD:
		drag_moved = true

	_update_arrow(pointer_position)

	if released:
		var was_dragged: bool = drag_moved
		cancel_drag()
		if was_dragged:
			sacrifice_drop_requested.emit(pointer_position)


func _update_arrow(pointer_position: Vector2) -> void:
	if arrow_line == null or arrow_head == null:
		return

	var start: Vector2 = sacrifice_button.get_global_rect().get_center()
	var delta: Vector2 = pointer_position - start
	var direction: Vector2 = delta.normalized() if delta.length() > 0.001 else Vector2.RIGHT

	arrow_line.points = PackedVector2Array([
		start,
		pointer_position - direction * 10.0
	])
	arrow_head.position = pointer_position
	arrow_head.rotation = direction.angle()


func cancel_drag() -> void:
	drag_active = false
	drag_moved = false
	if arrow_line != null:
		arrow_line.visible = false
	if arrow_head != null:
		arrow_head.visible = false


func show_gesture_choices(current_gesture: int) -> void:
	cancel_drag()
	if choice_panel == null:
		return

	rock_button.visible = current_gesture != CardGesture.Type.ROCK
	paper_button.visible = current_gesture != CardGesture.Type.PAPER
	scissors_button.visible = current_gesture != CardGesture.Type.SCISSORS
	choice_panel.visible = true
	show_message("یکی از دو نوع دیگر را انتخاب کن. خود کارت انتخاب‌شده فدا نمی‌شود.")


func hide_gesture_choices() -> void:
	if choice_panel != null:
		choice_panel.visible = false


func _on_gesture_button_pressed(gesture: int) -> void:
	hide_gesture_choices()
	gesture_chosen.emit(gesture)


func _on_choice_cancelled() -> void:
	hide_gesture_choices()
	choice_cancelled.emit()


func show_message(text: String, duration: float = 3.2) -> void:
	if instruction_label == null:
		return

	message_serial += 1
	var serial: int = message_serial
	instruction_label.text = text
	instruction_label.visible = true

	if duration <= 0.0:
		return

	_hide_message_later(serial, duration)


func _hide_message_later(serial: int, duration: float) -> void:
	await get_tree().create_timer(duration, true).timeout
	if serial != message_serial:
		return
	if choice_panel != null and choice_panel.visible:
		return
	instruction_label.visible = false
