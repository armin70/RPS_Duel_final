class_name GameHUD
extends CanvasLayer


signal end_turn_pressed

@onready var menu_button: TextureButton = $Root/PlayerPassPanel/MenuButton

@onready var info_button: TextureButton = $InfoButton
@onready var info_panel: Control = $InfoPanel
@onready var close_button: TextureButton = $InfoPanel/CloseButton
@onready var turn_label: Label = $Root/PlayerInfo/TurnLabel
@onready var player_score_label: Label = $Root/PlayerInfo/PlayerScoreLabel
@onready var opponent_score_label: Label = $Root/PlayerInfo/OpponentScoreLabel
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
var exit_confirmation: ConfirmationDialog

func _ready() -> void:
	menu_button.process_mode = Node.PROCESS_MODE_ALWAYS
	menu_button.pressed.connect(_on_menu_button_pressed)
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
	exit_confirmation = ConfirmationDialog.new()

	exit_confirmation.title = "Return to Menu"
	exit_confirmation.dialog_text = \
		"Are you sure you want to return to the main menu?"

	exit_confirmation.ok_button_text = "Yes"
	exit_confirmation.cancel_button_text = "No"

	exit_confirmation.process_mode = Node.PROCESS_MODE_ALWAYS

	exit_confirmation.confirmed.connect(
		_confirm_return_to_menu
	)
	_build_dealer_notice()
	
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
	exit_confirmation.popup_centered(
		Vector2i(500, 220)
	)
func _confirm_return_to_menu() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

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
	score_difference: int
) -> void:
	if local_won:
		result_label.text = "YOU WIN"
	else:
		result_label.text = "YOU LOSE"

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
