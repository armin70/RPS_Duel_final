class_name HeroPowerControl
extends Control


signal active_power_requested

var engine: MatchEngine
var player_id: int = 1
var active_button: Button
var last_signature: String = ""


# Standalone ACTIVE button position next to the player's hand.
# Change these values if you want to move/resize it later.
const ACTIVE_BUTTON_LEFT_FROM_CENTER: float = -790.0
const ACTIVE_BUTTON_RIGHT_FROM_CENTER: float = -570.0
const ACTIVE_BUTTON_TOP_FROM_BOTTOM: float = -112.0
const ACTIVE_BUTTON_BOTTOM_FROM_BOTTOM: float = -50.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_ui()
	set_process(true)


func bind_match(new_engine: MatchEngine, new_player_id: int) -> void:
	engine = new_engine
	player_id = new_player_id
	last_signature = ""
	_refresh_now()


func _process(_delta: float) -> void:
	_refresh_now()


func _build_ui() -> void:
	# Only the ACTIVE button remains; there is no hero information panel.
	anchor_left = 0.5
	anchor_top = 1.0
	anchor_right = 0.5
	anchor_bottom = 1.0
	offset_left = ACTIVE_BUTTON_LEFT_FROM_CENTER
	offset_top = ACTIVE_BUTTON_TOP_FROM_BOTTOM
	offset_right = ACTIVE_BUTTON_RIGHT_FROM_CENTER
	offset_bottom = ACTIVE_BUTTON_BOTTOM_FROM_BOTTOM

	active_button = Button.new()
	active_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	active_button.focus_mode = Control.FOCUS_NONE
	active_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	active_button.add_theme_font_size_override("font_size", 22)
	active_button.pressed.connect(_on_active_pressed)
	add_child(active_button)


func _refresh_now() -> void:
	if engine == null or engine.state == null:
		visible = false
		return

	var player: PlayerState = engine.state.get_player(player_id)
	if player == null or player.hero == null:
		visible = false
		return

	var hero: CardInstance = player.hero
	if not hero.hero_revealed:
		visible = false
		return

	var hero_def: HeroDefinition = hero.get_hero_definition()
	if hero_def == null:
		visible = false
		return

	visible = true

	var signature: String = "%d|%d|%d" % [
		player.current_mana,
		hero.hero_active_used_turn,
		engine.state.turn_number
	]
	if signature == last_signature:
		return
	last_signature = signature

	active_button.text = "ACTIVE — %d MANA" % hero_def.active_mana_cost
	active_button.disabled = not engine.can_activate_hero_active(player_id)


func _on_active_pressed() -> void:
	active_power_requested.emit()
