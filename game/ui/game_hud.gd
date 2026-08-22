class_name GameHUD
extends CanvasLayer


signal end_turn_pressed

var menu_button: BaseButton

@onready var info_button: TextureButton = $InfoButton
@onready var info_panel: Control = $InfoPanel
@onready var close_button: TextureButton = $InfoPanel/CloseButton
@onready var turn_label: Label = $Root/PlayerInfo/TurnLabel
@onready var player_score_label: Label = $Root/PlayerInfo/PlayerScoreLabel
@onready var opponent_score_label: Label = $Root/PlayerInfo/OpponentScoreLabel
@onready var player_mana_panel: Control = \
	$Root/PlayerManaPanel
@onready var player_mana_label: Label = \
	$Root/PlayerManaPanel/PlayerManaLabel
@onready var opponent_mana_label: Label = $Root/PlayerInfo/OpponentManaLabel

@export var end_turn_button: TextureButton

@onready var game_over_overlay: Control = \
	%GameOverOverlay

@onready var result_label: Label = \
	%ResultLabel

@onready var score_label: Label = \
	%ScoreLabel

@onready var restart_button: Button = \
	%RestartButton
@onready var survey_button: Button = %SurveyButton
@onready var music_button: TextureButton = \
	$Root/PlayerPassPanel/MusicButton
@export_category("Dealer Notice")

@export_range(0.10, 0.80, 0.01)
var dealer_notice_height_ratio: float = 0.58

@export_range(0.0, 0.50, 0.01)
var dealer_notice_left_ratio: float = 0.02

@export_range(0.0, 0.70, 0.01)
var dealer_notice_top_ratio: float = 0.17


var dealer_notice_rect: TextureRect
var dealer_notice_tween: Tween
@export var music_on_texture: Texture2D
@export var music_off_texture: Texture2D
@export var survey_url: String = ""
var exit_confirmation: Control
var exit_yes_button: Button
var exit_no_button: Button

@export_category("Low Mana Feedback")
@export var low_mana_message: String = "Not enough mana"
@export_range(20, 150, 5)
var low_mana_vibration_ms: int = 45
@export_range(0.2, 2.0, 0.05)
var low_mana_message_duration: float = 0.75

var low_mana_toast: Label
var low_mana_toast_tween: Tween
var low_mana_visual_tween: Tween

# Prefer the whole PlayerManaPanel so its background texture and text
# shake / flash together. If the scene does not have that wrapper,
# fall back safely to the Mana label only.
var player_mana_visual: Control
var player_mana_base_modulate: Color = Color.WHITE
var player_mana_base_position: Vector2 = Vector2.ZERO
var player_mana_base_scale: Vector2 = Vector2.ONE
var player_mana_base_rotation: float = 0.0

func _ready() -> void:
	# Resolve Back by node name instead of a brittle serialized path. The active
	# binary scene has changed several times, so the button may live elsewhere.
	_setup_menu_button()
	_build_exit_confirmation()

	end_turn_button.pressed.connect(
		_on_end_turn_button_pressed
	)
	game_over_overlay.visible = false
	survey_button.pressed.connect(
		_on_survey_button_pressed
	)
	music_button.process_mode = Node.PROCESS_MODE_ALWAYS

	music_button.pressed.connect(
		_on_music_button_pressed
	)

	_refresh_music_button()
	restart_button.pressed.connect(
		Callable(
			self,
			"_on_restart_button_pressed"
		)
	)
	info_panel.hide()

	info_button.pressed.connect(
		_on_info_button_pressed
	)

	close_button.pressed.connect(
		_on_info_close_pressed
	)
	_build_dealer_notice()
	_build_low_mana_feedback()

	player_mana_visual = player_mana_panel

	if player_mana_visual != null:
		player_mana_base_modulate = player_mana_visual.modulate
		player_mana_base_position = player_mana_visual.position
		player_mana_base_scale = player_mana_visual.scale
		player_mana_base_rotation = player_mana_visual.rotation
		player_mana_visual.pivot_offset = player_mana_visual.size * 0.5
	

func _setup_menu_button() -> void:
	menu_button = find_child("MenuButton", true, false) as BaseButton

	if menu_button == null:
		# Last-resort runtime Back button. This keeps navigation available even
		# if an older/newer serialized HUD no longer contains MenuButton.
		var fallback := Button.new()
		fallback.name = "RuntimeMenuButton"
		fallback.text = "BACK"
		fallback.position = Vector2(18.0, 18.0)
		fallback.size = Vector2(126.0, 52.0)
		fallback.focus_mode = Control.FOCUS_NONE
		add_child(fallback)
		menu_button = fallback
		push_warning("MenuButton was not found. Runtime Back button created.")

	menu_button.process_mode = Node.PROCESS_MODE_ALWAYS
	menu_button.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_button.disabled = false
	menu_button.z_index = 900

	if not menu_button.pressed.is_connected(_on_menu_button_pressed):
		menu_button.pressed.connect(_on_menu_button_pressed)

func _build_exit_confirmation() -> void:
	exit_confirmation = Control.new()
	exit_confirmation.name = "ExitConfirmationOverlay"
	exit_confirmation.process_mode = Node.PROCESS_MODE_ALWAYS
	exit_confirmation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	exit_confirmation.mouse_filter = Control.MOUSE_FILTER_STOP
	exit_confirmation.z_index = 1000
	exit_confirmation.visible = false
	add_child(exit_confirmation)

	var dark := ColorRect.new()
	dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dark.color = Color(0.0, 0.0, 0.0, 0.72)
	dark.mouse_filter = Control.MOUSE_FILTER_STOP
	exit_confirmation.add_child(dark)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	exit_confirmation.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(470.0, 210.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.035, 0.06, 0.98)
	panel_style.border_color = Color(0.45, 0.82, 1.0, 0.95)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(16)
	panel.add_theme_stylebox_override("panel", panel_style)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 22)
	panel.add_child(content)

	var title := Label.new()
	title.text = "Return to Main Menu?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 25)
	content.add_child(title)

	var message := Label.new()
	message.text = "Your current match will end."
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_font_size_override("font_size", 17)
	content.add_child(message)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	content.add_child(row)

	exit_no_button = Button.new()
	exit_no_button.text = "NO"
	exit_no_button.custom_minimum_size = Vector2(140.0, 52.0)
	exit_no_button.focus_mode = Control.FOCUS_NONE
	exit_no_button.process_mode = Node.PROCESS_MODE_ALWAYS
	exit_no_button.pressed.connect(_cancel_return_to_menu)
	row.add_child(exit_no_button)

	exit_yes_button = Button.new()
	exit_yes_button.text = "YES"
	exit_yes_button.custom_minimum_size = Vector2(140.0, 52.0)
	exit_yes_button.focus_mode = Control.FOCUS_NONE
	exit_yes_button.process_mode = Node.PROCESS_MODE_ALWAYS
	exit_yes_button.pressed.connect(_confirm_return_to_menu)
	row.add_child(exit_yes_button)


func _input(event: InputEvent) -> void:
	# Fallback for the serialized HUD: even if another Control accidentally
	# intercepts MenuButton's normal pressed signal, a direct press inside the
	# visible button rectangle still opens the confirmation overlay.
	if not is_instance_valid(menu_button):
		return
	if not menu_button.is_visible_in_tree():
		return
	if is_instance_valid(exit_confirmation) and exit_confirmation.visible:
		return

	var pressed: bool = false
	var position: Vector2 = Vector2.ZERO

	if event is InputEventScreenTouch:
		pressed = event.pressed
		position = event.position
	elif event is InputEventMouseButton:
		pressed = (
			event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed
		)
		position = event.position
	else:
		return

	if pressed and menu_button.get_global_rect().has_point(position):
		_on_menu_button_pressed()
		get_viewport().set_input_as_handled()


func _build_low_mana_feedback() -> void:
	# No box around Mana. The Mana label itself is the feedback target.
	low_mana_toast = Label.new()
	low_mana_toast.name = "LowManaToast"
	low_mana_toast.text = low_mana_message
	low_mana_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	low_mana_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	low_mana_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	low_mana_toast.z_index = 100
	low_mana_toast.visible = false
	low_mana_toast.add_theme_font_size_override("font_size", 19)
	low_mana_toast.add_theme_color_override(
		"font_color",
		Color(1.0, 0.84, 0.76, 1.0)
	)
	low_mana_toast.add_theme_color_override(
		"font_outline_color",
		Color(0.10, 0.025, 0.02, 0.88)
	)
	low_mana_toast.add_theme_constant_override("outline_size", 5)
	add_child(low_mana_toast)


func _layout_low_mana_feedback() -> void:
	if low_mana_toast == null:
		return

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var toast_width: float = minf(280.0, viewport_size.x * 0.48)
	low_mana_toast.size = Vector2(toast_width, 42.0)
	low_mana_toast.pivot_offset = low_mana_toast.size * 0.5

	var mana_target: Control = player_mana_visual
	if mana_target == null:
		mana_target = player_mana_label

	if mana_target == null:
		low_mana_toast.position = Vector2(
			(viewport_size.x - toast_width) * 0.5,
			viewport_size.y * 0.72
		)
		return

	var mana_rect: Rect2 = mana_target.get_global_rect()
	var toast_x: float = clampf(
		mana_rect.get_center().x - toast_width * 0.5,
		8.0,
		maxf(8.0, viewport_size.x - toast_width - 8.0)
	)
	var toast_y: float = maxf(
		8.0,
		mana_rect.position.y - 46.0
	)
	low_mana_toast.position = Vector2(toast_x, toast_y)


func show_low_mana_feedback() -> void:
	_layout_low_mana_feedback()

	if low_mana_toast_tween != null:
		if low_mana_toast_tween.is_valid():
			low_mana_toast_tween.kill()

	if low_mana_visual_tween != null:
		if low_mana_visual_tween.is_valid():
			low_mana_visual_tween.kill()

	# Small warning close to the Mana display.
	if low_mana_toast != null:
		low_mana_toast.text = low_mana_message
		low_mana_toast.visible = true
		low_mana_toast.modulate.a = 0.0
		low_mana_toast.position.y += 5.0

		low_mana_toast_tween = create_tween()
		low_mana_toast_tween.tween_property(
			low_mana_toast,
			"modulate:a",
			1.0,
			0.07
		)
		low_mana_toast_tween.parallel().tween_property(
			low_mana_toast,
			"position:y",
			low_mana_toast.position.y - 5.0,
			0.10
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		low_mana_toast_tween.tween_interval(
			maxf(0.05, low_mana_message_duration - 0.17)
		)
		low_mana_toast_tween.tween_property(
			low_mana_toast,
			"modulate:a",
			0.0,
			0.10
		)
		low_mana_toast_tween.tween_callback(
			low_mana_toast.hide
		)

	# Shake + flash the ENTIRE Mana visual (background texture + number/text).
	if player_mana_visual != null:
		player_mana_visual.modulate = player_mana_base_modulate
		player_mana_visual.position = player_mana_base_position
		player_mana_visual.scale = player_mana_base_scale
		player_mana_visual.rotation = player_mana_base_rotation
		player_mana_visual.pivot_offset = player_mana_visual.size * 0.5

		var warning_color := Color(1.0, 0.30, 0.11, 1.0)
		low_mana_visual_tween = create_tween()

		# First hit: quick flash + right kick + tiny pop.
		low_mana_visual_tween.tween_property(
			player_mana_visual,
			"position:x",
			player_mana_base_position.x + 8.0,
			0.040
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		low_mana_visual_tween.parallel().tween_property(
			player_mana_visual,
			"rotation",
			player_mana_base_rotation + 0.055,
			0.040
		)
		low_mana_visual_tween.parallel().tween_property(
			player_mana_visual,
			"modulate",
			warning_color,
			0.040
		)
		low_mana_visual_tween.parallel().tween_property(
			player_mana_visual,
			"scale",
			player_mana_base_scale * 1.075,
			0.050
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

		# Recoil left and briefly return to its normal color.
		low_mana_visual_tween.tween_property(
			player_mana_visual,
			"position:x",
			player_mana_base_position.x - 8.0,
			0.050
		)
		low_mana_visual_tween.parallel().tween_property(
			player_mana_visual,
			"rotation",
			player_mana_base_rotation - 0.050,
			0.050
		)
		low_mana_visual_tween.parallel().tween_property(
			player_mana_visual,
			"modulate",
			player_mana_base_modulate,
			0.050
		)

		# Second smaller flash.
		low_mana_visual_tween.tween_property(
			player_mana_visual,
			"position:x",
			player_mana_base_position.x + 5.0,
			0.045
		)
		low_mana_visual_tween.parallel().tween_property(
			player_mana_visual,
			"rotation",
			player_mana_base_rotation + 0.032,
			0.045
		)
		low_mana_visual_tween.parallel().tween_property(
			player_mana_visual,
			"modulate",
			warning_color,
			0.045
		)

		# Settle cleanly back to the original UI state.
		low_mana_visual_tween.tween_property(
			player_mana_visual,
			"position",
			player_mana_base_position,
			0.085
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		low_mana_visual_tween.parallel().tween_property(
			player_mana_visual,
			"rotation",
			player_mana_base_rotation,
			0.085
		)
		low_mana_visual_tween.parallel().tween_property(
			player_mana_visual,
			"modulate",
			player_mana_base_modulate,
			0.085
		)
		low_mana_visual_tween.parallel().tween_property(
			player_mana_visual,
			"scale",
			player_mana_base_scale,
			0.085
		)

	# Safe on unsupported platforms (Godot simply ignores it there).
	# Android still needs the VIBRATE export permission enabled.
	Input.vibrate_handheld(low_mana_vibration_ms)


func _build_dealer_notice() -> void:
	dealer_notice_rect = TextureRect.new()
	dealer_notice_rect.name = "DealerNotice"

	dealer_notice_rect.expand_mode = (
		TextureRect.EXPAND_IGNORE_SIZE
	)

	dealer_notice_rect.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)

	dealer_notice_rect.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	# پشت بقیه UIهای HUD باشد.
	dealer_notice_rect.z_index = -10

	dealer_notice_rect.visible = false

	add_child(dealer_notice_rect)


func show_dealer_notice(
	texture: Texture2D,
	duration: float = 3.0
) -> void:
	if texture == null:
		return

	if dealer_notice_rect == null:
		return

	if dealer_notice_tween != null:
		if dealer_notice_tween.is_valid():
			dealer_notice_tween.kill()

	var viewport_size: Vector2 = (
		get_viewport().get_visible_rect().size
	)

	var texture_size: Vector2 = texture.get_size()

	if texture_size.y <= 0.0:
		return

	var notice_height: float = (
		viewport_size.y
		* dealer_notice_height_ratio
	)

	var aspect_ratio: float = (
		texture_size.x
		/ texture_size.y
	)

	var notice_width: float = (
		notice_height
		* aspect_ratio
	)

	dealer_notice_rect.texture = texture

	dealer_notice_rect.size = Vector2(
		notice_width,
		notice_height
	)

	dealer_notice_rect.position = Vector2(
		viewport_size.x
		* dealer_notice_left_ratio,

		viewport_size.y
		* dealer_notice_top_ratio
	)

	dealer_notice_rect.modulate.a = 0.0
	dealer_notice_rect.visible = true

	dealer_notice_tween = create_tween()

	# Fade in
	dealer_notice_tween.tween_property(
		dealer_notice_rect,
		"modulate:a",
		1.0,
		0.18
	)

	# چند ثانیه بماند
	dealer_notice_tween.tween_interval(
		duration
	)

	# Fade out
	dealer_notice_tween.tween_property(
		dealer_notice_rect,
		"modulate:a",
		0.0,
		0.30
	)

	dealer_notice_tween.tween_callback(
		dealer_notice_rect.hide
	)


	add_child(exit_confirmation)
func _get_music_manager() -> Node:
	# Resolve from /root. This also makes running the gameplay scene directly
	# from the editor safe when the Autoload entry is temporarily unavailable.
	var root := get_tree().root
	if root == null:
		return null

	var existing := root.get_node_or_null("MusicManager")
	if existing != null:
		return existing

	var manager_scene := load("res://audio/music_manager.tscn") as PackedScene
	if manager_scene == null:
		return null

	var manager := manager_scene.instantiate()
	if manager == null:
		return null

	manager.name = "MusicManager"
	root.add_child(manager)
	return manager


func _on_music_button_pressed() -> void:
	var manager := _get_music_manager()
	if manager == null:
		push_warning("MusicManager autoload is not available.")
		return

	if manager.is_music_paused():
		manager.resume_music()
	else:
		manager.pause_music()

	_refresh_music_button()


func _refresh_music_button() -> void:
	var manager := _get_music_manager()
	if manager == null:
		# Keep the HUD usable even if the audio autoload is temporarily absent.
		music_button.texture_normal = music_off_texture
		return

	if manager.is_music_paused():
		music_button.texture_normal = music_off_texture
	else:
		music_button.texture_normal = music_on_texture

func _on_survey_button_pressed() -> void:
	if survey_url.is_empty():
		return

	OS.shell_open(survey_url)


func _on_menu_button_pressed() -> void:
	if not is_instance_valid(exit_confirmation):
		return

	exit_confirmation.visible = true
	exit_confirmation.move_to_front()


func _cancel_return_to_menu() -> void:
	if is_instance_valid(exit_confirmation):
		exit_confirmation.visible = false


func _confirm_return_to_menu() -> void:
	get_tree().paused = false

	# The active project uses the binary main_game.scn, which contains the
	# transparent main menu. Reloading arbitrary current PackedScene state was
	# unreliable after the menu had queue_free()'d itself, so return explicitly.
	var menu_scene_path: String = "res://game/main_game.scn"
	var scene_error: Error = get_tree().change_scene_to_file(menu_scene_path)

	if scene_error != OK:
		push_warning(
			"Could not open main_game.scn; falling back to current scene reload."
		)
		var reload_error: Error = get_tree().reload_current_scene()
		if reload_error != OK:
			push_error("Could not return to the main menu.")

func _on_info_button_pressed() -> void:
	info_panel.show()


func _on_info_close_pressed() -> void:
	info_panel.hide()


func refresh(
	state: MatchState,
	local_player_id: int
) -> void:
	if state == null:
		return

	var player: PlayerState = state.get_player(
		local_player_id
	)

	var opponent_id: int = 2 if local_player_id == 1 else 1

	var opponent: PlayerState = state.get_player(
		opponent_id
	)

	if player == null or opponent == null:
		return

	turn_label.text = "Turn: %d" % state.turn_number

	if state.rush_mode_enabled:
		player_score_label.text = \
			"Your Cards: %d" % player.get_remaining_card_count()

		opponent_score_label.text = \
			"Opponent Cards: %d" % opponent.get_remaining_card_count()
	else:
		player_score_label.text = \
			"Your Score: %d" % player.score

		opponent_score_label.text = \
			"Opponent Score: %d" % opponent.score

	player_mana_label.text = \
		" %d / %d" % [
			player.current_mana,
			player.mana_capacity
		]

	opponent_mana_label.text = \
		"Opponent Mana: %d / %d" % [
			opponent.current_mana,
			opponent.mana_capacity
		]

	end_turn_button.disabled = (
		player.is_ready
		or state.phase != MatchPhase.Type.MAIN
	)



func set_interaction_enabled(enabled: bool) -> void:
	end_turn_button.disabled = not enabled


func _on_end_turn_button_pressed() -> void:
	end_turn_pressed.emit()


func set_scores(
	player_one_score: int,
	player_two_score: int
) -> void:
	if player_score_label != null:
		player_score_label.text = \
			str(player_one_score)

	if opponent_score_label != null:
		opponent_score_label.text = \
			str(player_two_score)


func show_game_over(
	local_won: bool,
	local_score: int,
	opponent_score: int,
	score_difference: int,
	is_draw: bool = false,
	rush_mode: bool = false
) -> void:
	if is_draw:
		result_label.text = "DRAW"
	elif local_won:
		result_label.text = "YOU WIN"
	else:
		result_label.text = "YOU LOSE"

	if rush_mode:
		score_label.text = (
			"YOUR CARDS LEFT: "
			+ str(local_score)
			+ "\n"
			+ "OPPONENT CARDS LEFT: "
			+ str(opponent_score)
		)
	else:
		score_label.text = (
			"YOUR SCORE: "
			+ str(local_score)
			+ "\n"
			+ "OPPONENT SCORE: "
			+ str(opponent_score)
			+ "\n"
			+ "SCORE DIFFERENCE: "
			+ str(score_difference)
		)

	game_over_overlay.visible = true
	game_over_overlay.modulate.a = 0.0

	var tween: Tween = create_tween()

	tween.set_trans(
		Tween.TRANS_QUAD
	)

	tween.set_ease(
		Tween.EASE_OUT
	)

	tween.tween_property(
		game_over_overlay,
		"modulate:a",
		1.0,
		0.35
	)


func _on_restart_button_pressed() -> void:
	var reload_error: Error = \
		get_tree().reload_current_scene()

	if reload_error != OK:
		push_error(
			"Could not reload the current scene."
		)
