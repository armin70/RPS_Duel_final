class_name GameHUD
extends CanvasLayer


signal end_turn_pressed



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

func _ready() -> void:
	end_turn_button.pressed.connect(
		_on_end_turn_button_pressed
	)
	game_over_overlay.visible = false

	restart_button.pressed.connect(
		Callable(
			self,
			"_on_restart_button_pressed"
		)
	)

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
