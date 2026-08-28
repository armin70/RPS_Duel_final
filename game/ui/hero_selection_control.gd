class_name HeroSelectionControl
extends CanvasLayer


signal hero_chosen(hero_definition: HeroDefinition)

var heroes: Array[HeroDefinition] = []
var selected_hero: HeroDefinition
var root: Control
var dim: ColorRect
var selection_panel: PanelContainer
var hero_row: HBoxContainer
var ground_hint_panel: PanelContainer
var ground_hint_label: Label
var ground_hint_image: TextureRect


func _ready() -> void:
	layer = 180
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func configure(hero_definitions: Array[HeroDefinition]) -> void:
	heroes = hero_definitions
	if not is_node_ready():
		await ready
	_show_selection_mode()
	_rebuild_hero_cards()


func show_ground_instruction(hero: HeroDefinition) -> void:
	selected_hero = hero
	if not is_node_ready():
		await ready

	# The dealer/table must remain visible while the player chooses a real 3D
	# board slot, so remove the full-screen dim and keep only a small hint.
	dim.hide()
	selection_panel.hide()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ground_hint_panel.show()
	ground_hint_label.text = (
		"جای شروع %s را مستقیماً روی زمین خودت انتخاب کن\n"
		+ "هیروهای هر دو بازیکن تا پایان مبارزه اول مخفی می‌مانند."
	) % hero.display_name
	ground_hint_image.texture = hero.front_texture


func finish_ground_selection() -> void:
	if not is_node_ready():
		return
	ground_hint_panel.hide()


func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root)

	dim = ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	selection_panel = PanelContainer.new()
	selection_panel.anchor_left = 0.5
	selection_panel.anchor_top = 0.5
	selection_panel.anchor_right = 0.5
	selection_panel.anchor_bottom = 0.5
	selection_panel.offset_left = -610.0
	selection_panel.offset_top = -345.0
	selection_panel.offset_right = 610.0
	selection_panel.offset_bottom = 345.0
	root.add_child(selection_panel)

	var outer_box := VBoxContainer.new()
	outer_box.add_theme_constant_override("separation", 18)
	selection_panel.add_child(outer_box)

	var title := Label.new()
	title.text = "هیروت را انتخاب کن"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	outer_box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "تصویر، تایپ، قدرت پسیو و اکتیو هر هیرو را قبل از انتخاب ببین."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 19)
	outer_box.add_child(subtitle)

	hero_row = HBoxContainer.new()
	hero_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_row.add_theme_constant_override("separation", 18)
	hero_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_box.add_child(hero_row)

	ground_hint_panel = PanelContainer.new()
	ground_hint_panel.anchor_left = 0.5
	ground_hint_panel.anchor_top = 0.0
	ground_hint_panel.anchor_right = 0.5
	ground_hint_panel.anchor_bottom = 0.0
	ground_hint_panel.offset_left = -360.0
	ground_hint_panel.offset_top = 26.0
	ground_hint_panel.offset_right = 360.0
	ground_hint_panel.offset_bottom = 142.0
	ground_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ground_hint_panel.hide()
	root.add_child(ground_hint_panel)

	var hint_row := HBoxContainer.new()
	hint_row.add_theme_constant_override("separation", 14)
	hint_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ground_hint_panel.add_child(hint_row)

	ground_hint_image = TextureRect.new()
	ground_hint_image.custom_minimum_size = Vector2(78.0, 104.0)
	ground_hint_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ground_hint_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ground_hint_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_row.add_child(ground_hint_image)

	ground_hint_label = Label.new()
	ground_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ground_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ground_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ground_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ground_hint_label.add_theme_font_size_override("font_size", 20)
	ground_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_row.add_child(ground_hint_label)


func _show_selection_mode() -> void:
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	dim.show()
	selection_panel.show()
	ground_hint_panel.hide()


func _rebuild_hero_cards() -> void:
	for child: Node in hero_row.get_children():
		child.queue_free()

	for hero: HeroDefinition in heroes:
		if hero == null:
			continue

		var card_panel := PanelContainer.new()
		card_panel.custom_minimum_size = Vector2(360.0, 500.0)
		hero_row.add_child(card_panel)

		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		card_panel.add_child(box)

		var image := TextureRect.new()
		image.custom_minimum_size = Vector2(300.0, 285.0)
		image.texture = hero.front_texture
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(image)

		var name_label := Label.new()
		name_label.text = "%s  —  %s" % [hero.display_name, _gesture_name(hero.gesture)]
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 24)
		box.add_child(name_label)

		var ability_label := Label.new()
		ability_label.text = "اکتیو: %s — %d مانا\n%s" % [
			hero.active_title,
			hero.active_mana_cost,
			hero.active_description
		]
		ability_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ability_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ability_label.add_theme_font_size_override("font_size", 17)
		box.add_child(ability_label)

		var choose_button := Button.new()
		choose_button.custom_minimum_size = Vector2(0.0, 58.0)
		choose_button.text = "انتخاب %s" % hero.display_name
		choose_button.add_theme_font_size_override("font_size", 20)
		choose_button.pressed.connect(_on_hero_selected.bind(hero))
		box.add_child(choose_button)


func _on_hero_selected(hero: HeroDefinition) -> void:
	selected_hero = hero
	hero_chosen.emit(hero)


func _gesture_name(gesture: CardGesture.Type) -> String:
	match gesture:
		CardGesture.Type.ROCK:
			return "سنگ"
		CardGesture.Type.PAPER:
			return "کاغذ"
		CardGesture.Type.SCISSORS:
			return "قیچی"
	return ""
