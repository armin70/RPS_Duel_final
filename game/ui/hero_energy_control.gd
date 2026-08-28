class_name HeroEnergyControl
extends Control


signal special_attack_requested


const ENERGY_PER_BAR: int = 15
const MAX_BARS: int = 4
const MAX_ENERGY: int = ENERGY_PER_BAR * MAX_BARS

var engine: MatchEngine
var local_player_id: int = 1

var local_panel: PanelContainer
var opponent_panel: PanelContainer
var local_title: Label
var opponent_title: Label
var local_bars: Array[ProgressBar] = []
var opponent_bars: Array[ProgressBar] = []
var special_button: Button
var last_signature: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	set_process(true)


func bind_match(new_engine: MatchEngine, new_local_player_id: int) -> void:
	engine = new_engine
	local_player_id = new_local_player_id
	last_signature = ""
	_refresh_now()


func _process(_delta: float) -> void:
	_refresh_now()


func _build_ui() -> void:
	local_panel = _build_energy_panel(false)
	local_panel.name = "LocalEnergyPanel"
	local_panel.anchor_left = 1.0
	local_panel.anchor_top = 1.0
	local_panel.anchor_right = 1.0
	local_panel.anchor_bottom = 1.0
	local_panel.offset_left = -600.0
	local_panel.offset_top = -150.0
	local_panel.offset_right = -30.0
	local_panel.offset_bottom = -35.0
	add_child(local_panel)

	opponent_panel = _build_energy_panel(true)
	opponent_panel.name = "OpponentEnergyPanel"
	opponent_panel.anchor_left = 1.0
	opponent_panel.anchor_top = 0.0
	opponent_panel.anchor_right = 1.0
	opponent_panel.anchor_bottom = 0.0
	opponent_panel.offset_left = -650.0
	opponent_panel.offset_top = 24.0
	opponent_panel.offset_right = -30.0
	opponent_panel.offset_bottom = 105.0
	add_child(opponent_panel)


func _build_energy_panel(is_opponent: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.035, 0.055, 0.90)
	panel_style.border_color = Color(0.38, 0.62, 0.92, 0.85)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(12)
	panel_style.content_margin_left = 14.0
	panel_style.content_margin_right = 14.0
	panel_style.content_margin_top = 9.0
	panel_style.content_margin_bottom = 9.0
	panel.add_theme_stylebox_override("panel", panel_style)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	panel.add_child(root)

	var title := Label.new()
	title.add_theme_font_size_override("font_size", 18)
	root.add_child(title)
	if is_opponent:
		opponent_title = title
	else:
		local_title = title

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	root.add_child(row)

	var target_array: Array[ProgressBar] = opponent_bars if is_opponent else local_bars
	for _index: int in range(MAX_BARS):
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(58.0, 17.0)
		bar.min_value = 0.0
		bar.max_value = float(ENERGY_PER_BAR)
		bar.value = 0.0
		bar.show_percentage = false

		var empty_style := StyleBoxFlat.new()
		empty_style.bg_color = Color(0.08, 0.10, 0.14, 0.95)
		empty_style.border_color = Color(0.25, 0.32, 0.42, 1.0)
		empty_style.set_border_width_all(1)
		empty_style.set_corner_radius_all(5)
		bar.add_theme_stylebox_override("background", empty_style)

		var fill_style := StyleBoxFlat.new()
		fill_style.bg_color = (
			Color(0.20, 0.82, 1.0, 1.0)
			if not is_opponent
			else Color(1.0, 0.38, 0.24, 1.0)
		)
		fill_style.set_corner_radius_all(5)
		bar.add_theme_stylebox_override("fill", fill_style)

		row.add_child(bar)
		target_array.append(bar)

	if not is_opponent:
		special_button = Button.new()
		special_button.text = "SPECIAL ATTACK"
		special_button.focus_mode = Control.FOCUS_NONE
		special_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		special_button.mouse_filter = Control.MOUSE_FILTER_STOP
		special_button.add_theme_font_size_override("font_size", 18)
		special_button.pressed.connect(_on_special_pressed)
		root.add_child(special_button)

	return panel


func _refresh_now() -> void:
	if engine == null or engine.state == null:
		visible = false
		return

	var state: MatchState = engine.state
	if state.rush_mode_enabled:
		visible = false
		return

	var local_player: PlayerState = state.get_player(local_player_id)
	var opponent_id: int = 2 if local_player_id == 1 else 1
	var opponent: PlayerState = state.get_player(opponent_id)
	if (
		local_player == null
		or opponent == null
		or local_player.hero == null
		or opponent.hero == null
	):
		visible = false
		return

	visible = true
	var signature: String = "%d|%d|%d|%d|%d|%d|%d|%d" % [
		local_player.energy_points,
		opponent.energy_points,
		local_player.hero.hero_health,
		opponent.hero.hero_health,
		local_player.hero.shield_count,
		opponent.hero.shield_count,
		state.turn_number,
		int(state.phase)
	]
	if signature == last_signature:
		return
	last_signature = signature

	local_title.text = "ENERGY  %d/%d   •   HERO HP %d/%d" % [
		clampi(local_player.energy_points, 0, MAX_ENERGY),
		MAX_ENERGY,
		maxi(0, local_player.hero.hero_health),
		maxi(1, local_player.hero.hero_max_health)
	]
	opponent_title.text = "ENEMY ENERGY  %d/%d   •   HERO HP %d/%d" % [
		clampi(opponent.energy_points, 0, MAX_ENERGY),
		MAX_ENERGY,
		maxi(0, opponent.hero.hero_health),
		maxi(1, opponent.hero.hero_max_health)
	]

	_refresh_bar_values(local_bars, local_player.energy_points)
	_refresh_bar_values(opponent_bars, opponent.energy_points)

	if special_button != null:
		special_button.disabled = not engine.can_use_special_attack(local_player_id)
		special_button.text = (
			"SPECIAL ATTACK — READY"
			if not special_button.disabled
			else "SPECIAL ATTACK — 4 BARS"
		)


func _refresh_bar_values(bars: Array[ProgressBar], energy: int) -> void:
	var remaining: int = clampi(energy, 0, MAX_ENERGY)
	for bar: ProgressBar in bars:
		if bar == null:
			continue
		var segment_value: int = mini(ENERGY_PER_BAR, remaining)
		bar.value = float(segment_value)
		remaining = maxi(0, remaining - ENERGY_PER_BAR)


func _on_special_pressed() -> void:
	special_attack_requested.emit()
