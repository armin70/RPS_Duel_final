class_name TutorialController
extends CanvasLayer

## Interactive, deterministic tutorial for RPS Duel.
##
## The tutorial runs on the real match.  It only gates player input, fixes the
## tutorial hands/board state, and pauses combat at the explanation moments.

signal combat_gate_released

const ROCK_PATH: String = "res://data/cards/normal_rock.tres"
const PAPER_PATH: String = "res://data/cards/normal_paper.tres"
const SCISSORS_PATH: String = "res://data/cards/normal_scissors.tres"
const MUSTACHE_PATH: String = "res://data/cards/mustache_rock.tres"
const COLLECTOR_PATH: String = "res://data/cards/collector_rock.tres"

const ROCK_ID: String = "normal_rock"
const PAPER_ID: String = "normal_paper"
const SCISSORS_ID: String = "normal_scissors"
const MUSTACHE_ID: String = "mustache_rock"
const COLLECTOR_ID: String = "collector_rock"

const FIRST_ROCK_SLOT: int = SlotID.Type.FRONT_LEFT
const FIRST_SCISSORS_SLOT: int = SlotID.Type.FRONT_MIDDLE_0
const MOVE_ROCK_TO_SLOT: int = SlotID.Type.FRONT_MIDDLE_1
const MUSTACHE_SLOT: int = SlotID.Type.FRONT_LEFT
const COLLECTOR_SLOT: int = SlotID.Type.BACK_LEFT
const FINAL_SCISSORS_SLOT: int = SlotID.Type.FRONT_RIGHT

# Board cards/slots already matched the screen well in v3.  Hand cards sit much
# closer to the camera, so they intentionally use an almost 2x spotlight.
const CARD_SPOTLIGHT_SIZE := Vector2(108.0, 148.0)
const HAND_CARD_SPOTLIGHT_SIZE := Vector2(216.0, 296.0)
const SLOT_SPOTLIGHT_SIZE := Vector2(102.0, 128.0)
const CONTROL_SPOTLIGHT_PADDING := Vector2(18.0, 14.0)
const SCALE_SPOTLIGHT_SIZE := Vector2(260.0, 190.0)

const GUIDE_FRAME_DIR: String = "res://game/tutorial/demon_frames"
const GUIDE_FRAME_COUNT: int = 69
const GUIDE_FRAME_FPS: float = 30.0
const GUIDE_FRAME_SIZE := Vector2(240.0, 336.0)

const TUTORIAL_PROGRESS_PATH: String = \
	"user://tutorial_progress.cfg"
const TUTORIAL_PROGRESS_SECTION: String = "tutorial"
const TUTORIAL_PROGRESS_KEY: String = "completed"


enum Step {
	INTRO_1,
	INTRO_2,
	RPS_RULE,
	BOARD_INTRO,
	DEALER_ROW,
	GOAL,
	PLAYER_ROWS,
	PLAY_ROCK_PROMPT,
	PLAY_ROCK,
	ROCK_RESULT,
	SCORING_RULE,
	LANES,
	MIDDLE_LANE,
	DEALER_REFRESH,
	DRAW_REFRESH,
	PLAY_SCISSORS,
	MIDDLE_PLACEMENT,
	OPPONENT_ARRIVES,
	HIDDEN_CARD_DEMO,
	HIDDEN_PLAY,
	END_TURN_1,
	WAIT_REVEAL_1,
	REVEAL_1_INTRO,
	LANE_1_RESULT,
	LANE_2_INTRO,
	RESOLUTION_ORDER,
	SCORE_SCALE,
	COMBAT_1_RUNNING,
	NEW_TURN_2,
	MANA_CARD_COST,
	MANA_TOTAL,
	BAD_POSITION,
	MOVE_ROCK,
	MOVE_RESULT,
	COVER_SETUP,
	COVER_SCISSORS,
	END_TURN_2,
	WAIT_REVEAL_2,
	REVEAL_2_RESULT,
	COMBAT_2_RUNNING,
	SPECIAL_CARD,
	CONDITIONAL_RULE,
	PLAY_MUSTACHE,
	MUSTACHE_EFFECT,
	END_TURN_MUSTACHE,
	WAIT_REVEAL_MUSTACHE,
	COMBAT_MUSTACHE_RUNNING,
	COLLECTOR_SETUP,
	COLLECTOR_INFO,
	PLAY_COLLECTOR,
	COLLECTOR_RESOLVING,
	COLLECTOR_PROMOTION,
	FINAL_SCISSORS,
	END_TURN_3,
	WAIT_REVEAL_3,
	COMBAT_3_RUNNING,
	DEALER_POWER,
	REMOVED_CARDS,
	COMPLETE,
	FULL_DIV,
	FINISHED,
}

var guide_sprite: AnimatedSprite2D


var match_controller: MatchController3D
var step: Step = Step.INTRO_1
var active: bool = false

var first_rock_id: int = -1
var scissors_id: int = -1
var cover_rock_id: int = -1
var mustache_id: int = -1
var collector_id: int = -1
var final_scissors_id: int = -1

var target_nodes_3d: Array[Node3D] = []
var target_control: Control
var target_padding: Vector2 = Vector2.ZERO
var guided_drop_slot_id: int = -1
var pulse_time: float = 0.0
var feedback_time: float = 0.0
var normal_message: String = ""

# UI
var overlay_root: Control
var dim_top: ColorRect
var dim_bottom: ColorRect
var dim_left: ColorRect
var dim_right: ColorRect
var focus_border: Panel
var pointer_label: Label
var dialogue_panel: Panel
var title_label: Label
var message_label: Label
var instruction_label: Label
var continue_button: Button
var skip_button: Button
var progress_label: Label
var card_preview_texture: TextureRect
var card_preview_panel: Panel


func setup(controller: MatchController3D) -> void:
	match_controller = controller
	layer = 100
	_build_ui()
	set_process(true)


func prepare_match_state() -> void:
	if match_controller == null or match_controller.state == null:
		return

	var player: PlayerState = _player()
	if player == null:
		return

	# The opening section is solo and deterministic.
	var opening_hand: Array[CardInstance] = _replace_hand_with_exact(
		player,
		TutorialScenario.opening_player_hand()
	)
	if opening_hand.size() >= 3:
		scissors_id = opening_hand[0].instance_id
		first_rock_id = opening_hand[1].instance_id

	# Mana is visible in the reference from the beginning, but it is not
	# explained until after the first real battle.
	player.mana_capacity = 2
	player.current_mana = 2
	player.board_move_used_turn = -1

	_set_dealer_board_exact(
		TutorialScenario.dealer_solo_opening()
	)


func start() -> void:
	if active:
		return
	active = true
	visible = true
	_set_opponent_hand_visible(false)
	_set_step(Step.INTRO_1)


func is_active() -> bool:
	return active and step != Step.FINISHED


func can_start_drag(card: CardInstance) -> bool:
	if not is_active():
		return true
	if card == null:
		return false

	match step:
		Step.PLAY_ROCK:
			return card.instance_id == first_rock_id and card.zone == CardZone.Type.HAND
		Step.PLAY_SCISSORS:
			return card.instance_id == scissors_id and card.zone == CardZone.Type.HAND
		Step.MOVE_ROCK:
			return card.instance_id == first_rock_id and card.zone == CardZone.Type.BOARD
		Step.COVER_SCISSORS:
			return card.instance_id == cover_rock_id and card.zone == CardZone.Type.HAND
		Step.SPECIAL_CARD:
			return card.instance_id == mustache_id and card.zone == CardZone.Type.HAND
		Step.COLLECTOR_SETUP:
			return card.instance_id == collector_id and card.zone == CardZone.Type.HAND
		Step.PLAY_MUSTACHE:
			return card.instance_id == mustache_id and card.zone == CardZone.Type.HAND
		Step.PLAY_COLLECTOR:
			return card.instance_id == collector_id and card.zone == CardZone.Type.HAND
		Step.FINAL_SCISSORS:
			return card.instance_id == final_scissors_id and card.zone == CardZone.Type.HAND
		_:
			return false


func can_drop(card: CardInstance, place: CardPlace3D) -> bool:
	if not is_active():
		return true
	if card == null or place == null:
		return false
	if place.kind != CardPlace3D.Kind.PLAYER_BOARD:
		return false
	if place.owner_id != match_controller.local_player_id:
		return false

	match step:
		Step.PLAY_ROCK:
			return card.instance_id == first_rock_id and place.logical_id == FIRST_ROCK_SLOT
		Step.PLAY_SCISSORS:
			return card.instance_id == scissors_id and place.logical_id == FIRST_SCISSORS_SLOT
		Step.MOVE_ROCK:
			return card.instance_id == first_rock_id and place.logical_id == MOVE_ROCK_TO_SLOT
		Step.COVER_SCISSORS:
			return card.instance_id == cover_rock_id and place.logical_id == FIRST_SCISSORS_SLOT
		Step.PLAY_MUSTACHE:
			return card.instance_id == mustache_id and place.logical_id == MUSTACHE_SLOT
		Step.PLAY_COLLECTOR:
			return card.instance_id == collector_id and place.logical_id == COLLECTOR_SLOT
		Step.FINAL_SCISSORS:
			return card.instance_id == final_scissors_id and place.logical_id == FINAL_SCISSORS_SLOT
		_:
			return false


func can_press_end_turn() -> bool:
	if not is_active():
		return true
	return step in [
		Step.END_TURN_1,
		Step.END_TURN_2,
		Step.END_TURN_MUSTACHE,
		Step.END_TURN_3,
	]


func try_handle_card_tap(card: CardInstance) -> bool:
	if not is_active() or card == null:
		return false

	if step == Step.SPECIAL_CARD and card.instance_id == mustache_id:
		_set_step(Step.CONDITIONAL_RULE)
		return true

	if step == Step.COLLECTOR_SETUP and card.instance_id == collector_id:
		_set_step(Step.COLLECTOR_INFO)
		return true

	return false


func can_toggle_keep_card() -> bool:
	return not is_active()


func notify_successful_drop(
	card: CardInstance,
	original_zone: CardZone.Type,
	slot_id: int
) -> void:
	if not is_active() or card == null:
		return

	match step:
		Step.PLAY_ROCK:
			if card.instance_id == first_rock_id and slot_id == FIRST_ROCK_SLOT:
				_set_step(Step.ROCK_RESULT)
		Step.PLAY_SCISSORS:
			if card.instance_id == scissors_id and slot_id == FIRST_SCISSORS_SLOT:
				_set_step(Step.MIDDLE_PLACEMENT)
		Step.MOVE_ROCK:
			if original_zone == CardZone.Type.BOARD and card.instance_id == first_rock_id:
				_set_step(Step.MOVE_RESULT)
		Step.COVER_SCISSORS:
			if card.instance_id == cover_rock_id and slot_id == FIRST_SCISSORS_SLOT:
				_set_step(Step.END_TURN_2)
		Step.PLAY_MUSTACHE:
			if card.instance_id == mustache_id and slot_id == MUSTACHE_SLOT:
				# Do not refill mana here. Mustache now gets its own real combat.
				# The next turn will restore 5 mana before Collector is introduced.
				_set_step(Step.MUSTACHE_EFFECT)
		Step.PLAY_COLLECTOR:
			if card.instance_id == collector_id and slot_id == COLLECTOR_SLOT:
				_set_step(Step.COLLECTOR_RESOLVING)
				call_deferred("_resolve_tutorial_collector_sequence")
		Step.FINAL_SCISSORS:
			if card.instance_id == final_scissors_id and slot_id == FINAL_SCISSORS_SLOT:
				_set_step(Step.END_TURN_3)


func notify_wrong_action() -> void:
	if not is_active():
		return
	feedback_time = 0.0
	_restore_step_focus()


func notify_drag_started(card: CardInstance) -> void:
	if not is_active() or card == null:
		return
	if guided_drop_slot_id < 0:
		return

	# در ویدیوی مرجع کارت‌های Special ابتدا بزرگ نمایش داده می‌شوند.
	# به محض اینکه بازیکن واقعاً کارت Hand را می‌گیرد، Preview کنار می‌رود
	# و فقط Slot دقیق مقصد Highlight می‌شود.
	if (
		(step == Step.PLAY_MUSTACHE and card.instance_id == mustache_id)
		or (step == Step.PLAY_COLLECTOR and card.instance_id == collector_id)
	):
		_hide_card_preview()

	# Once the exact source card is picked up, show only the exact destination.
	_focus_board_slot(guided_drop_slot_id)


func notify_end_turn_pressed() -> void:
	if not is_active():
		return

	if step == Step.END_TURN_1:
		_set_step(Step.WAIT_REVEAL_1)
	elif step == Step.END_TURN_2:
		_set_step(Step.WAIT_REVEAL_2)
	elif step == Step.END_TURN_MUSTACHE:
		_set_step(Step.WAIT_REVEAL_MUSTACHE)
	elif step == Step.END_TURN_3:
		_set_step(Step.WAIT_REVEAL_3)


func wait_before_combat() -> void:
	# Called by MatchController after both players' cards have been revealed but
	# before animated scoring begins.  This lets the tutorial preserve every
	# explanation panel from the reference animation.
	if not is_active():
		return

	if step == Step.WAIT_REVEAL_1:
		_set_step(Step.REVEAL_1_INTRO)
		await combat_gate_released
	elif step == Step.WAIT_REVEAL_2:
		_set_step(Step.REVEAL_2_RESULT)
		await combat_gate_released
	elif step == Step.WAIT_REVEAL_MUSTACHE:
		# No explanation gate here: go straight into the real battle so the
		# MUSTACHE_SWEEP animation/score is visible immediately.
		_set_step(Step.COMBAT_MUSTACHE_RUNNING)
	elif step == Step.WAIT_REVEAL_3:
		_set_step(Step.COMBAT_3_RUNNING)


func prepare_new_turn_state() -> void:
	# Called after MatchEngine.finish_combat(), before visual sync.
	if not is_active():
		return

	var player: PlayerState = _player()
	if player == null:
		return

	if step == Step.COMBAT_1_RUNNING:
		_prepare_second_turn(player)
	elif step == Step.COMBAT_2_RUNNING:
		_prepare_third_turn(player)
	elif step == Step.COMBAT_MUSTACHE_RUNNING:
		_prepare_collector_turn(player)


func prepare_next_dealer_before_finish_combat() -> void:
	# MatchEngine.finish_combat() immediately deals the next Dealer row.
	# Priming the draw pile here lets the real DealerMover and Dealer behaviors
	# run normally while keeping the tutorial 100% deterministic.
	if not is_active():
		return

	if step == Step.COMBAT_1_RUNNING:
		_prime_dealer_draw(
			TutorialScenario.dealer_second_battle()
		)
	elif step == Step.COMBAT_2_RUNNING:
		_prime_dealer_draw(
			TutorialScenario.dealer_third_battle()
		)
	elif step == Step.COMBAT_MUSTACHE_RUNNING:
		_prime_dealer_draw(
			TutorialScenario.dealer_collector_turn()
		)
	elif step == Step.COMBAT_3_RUNNING:
		_prime_dealer_draw(
			TutorialScenario.dealer_after_final_battle()
		)



func execute_scripted_bot_turn() -> bool:
	# Called instead of BotController.play_turn() while the tutorial is active.
	# Returns true when a scripted tutorial turn was handled.
	if not is_active():
		return false

	var plays: Array[Dictionary] = []
	match step:
		Step.END_TURN_1:
			plays = TutorialScenario.battle_1_bot_plays()
		Step.END_TURN_2:
			plays = TutorialScenario.battle_2_bot_plays()
		Step.END_TURN_MUSTACHE:
			plays = TutorialScenario.mustache_battle_bot_plays()
		Step.END_TURN_3:
			plays = TutorialScenario.battle_3_bot_plays()
		_:
			return false

	var bot: PlayerState = match_controller.state.get_player(
		match_controller.bot_player_id
	)
	if bot == null:
		return false

	match_controller.engine.clear_play_records(
		match_controller.bot_player_id
	)

	for play: Dictionary in plays:
		var card_path: String = String(play.get("card_path", ""))
		var slot_id: int = int(play.get("slot_id", -1))
		var card: CardInstance = _find_hand_card_by_path(bot, card_path)

		if card == null:
			push_error("Tutorial bot card missing: " + card_path)
			continue

		var success: bool = match_controller.engine.play_card(
			match_controller.bot_player_id,
			card,
			slot_id
		)

		if not success:
			push_error(
				"Tutorial bot play failed | card="
				+ card_path
				+ " | slot="
				+ str(slot_id)
			)

	return true


func sync_visual_visibility() -> void:
	# Re-applied after MatchController respawns visual cards.
	if not is_active():
		return

	var opponent_should_be_visible: bool = (
		step >= Step.OPPONENT_ARRIVES
	)
	_set_opponent_hand_visible(opponent_should_be_visible)


func _prepare_second_turn(player: PlayerState) -> void:
	# Exact board after the first battle.
	var rock: CardInstance = _force_definition_on_board(
		player, ROCK_PATH, FIRST_ROCK_SLOT, first_rock_id
	)
	if rock != null:
		first_rock_id = rock.instance_id

	var scissors: CardInstance = _force_definition_on_board(
		player, SCISSORS_PATH, FIRST_SCISSORS_SLOT, scissors_id
	)
	if scissors != null:
		scissors_id = scissors.instance_id

	_clear_other_board_slots(
		player,
		[FIRST_ROCK_SLOT, FIRST_SCISSORS_SLOT]
	)

	var second_hand: Array[CardInstance] = _replace_hand_with_exact(
		player,
		TutorialScenario.turn_2_player_hand()
	)
	if second_hand.size() >= 5:
		mustache_id = second_hand[0].instance_id
		collector_id = second_hand[1].instance_id
		cover_rock_id = second_hand[2].instance_id

	player.mana_capacity = 3
	player.current_mana = 3
	player.board_move_used_turn = -1

	var bot: PlayerState = match_controller.state.get_player(
		match_controller.bot_player_id
	)
	if bot != null:
		var bot_rock: CardInstance = _force_definition_on_board(
			bot,
			ROCK_PATH,
			SlotID.Type.FRONT_MIDDLE_0,
			-1
		)
		_clear_other_board_slots(
			bot,
			[SlotID.Type.FRONT_MIDDLE_0]
		)
		_replace_hand_with_exact(
			bot,
			TutorialScenario.battle_2_bot_hand()
		)
		bot.mana_capacity = 3
		bot.current_mana = 3
		bot.board_move_used_turn = -1


func _prepare_third_turn(player: PlayerState) -> void:
	# Player board in the reference before the special-card lesson:
	# two old Rock cards in the middle.
	var rock_a: CardInstance = _force_definition_on_board(
		player, ROCK_PATH, SlotID.Type.FRONT_MIDDLE_0, cover_rock_id
	)
	if rock_a != null:
		cover_rock_id = rock_a.instance_id

	var rock_b: CardInstance = _force_definition_on_board(
		player, ROCK_PATH, SlotID.Type.FRONT_MIDDLE_1, first_rock_id
	)
	if rock_b != null:
		first_rock_id = rock_b.instance_id

	_clear_other_board_slots(
		player,
		[SlotID.Type.FRONT_MIDDLE_0, SlotID.Type.FRONT_MIDDLE_1]
	)

	var third_hand: Array[CardInstance] = _replace_hand_with_exact(
		player,
		TutorialScenario.turn_3_player_hand()
	)
	if third_hand.size() >= 5:
		mustache_id = third_hand[0].instance_id

	# Mustache gets its own turn at exactly 4 mana. Its real card cost is paid
	# now; mana is not refilled until the combat actually finishes.
	player.mana_capacity = maxi(player.mana_capacity, 5)
	player.current_mana = 4
	player.board_move_used_turn = -1

	var bot: PlayerState = match_controller.state.get_player(
		match_controller.bot_player_id
	)
	if bot != null:
		_force_definition_on_board(
			bot, SCISSORS_PATH, SlotID.Type.FRONT_LEFT, -1
		)
		_force_definition_on_board(
			bot, ROCK_PATH, SlotID.Type.FRONT_MIDDLE_0, -1
		)
		_clear_other_board_slots(
			bot,
			[SlotID.Type.FRONT_LEFT, SlotID.Type.FRONT_MIDDLE_0]
		)
		_replace_hand_with_exact(
			bot,
			TutorialScenario.mustache_battle_bot_hand()
		)
		# No new opponent placement in the Mustache demonstration battle.
		bot.mana_capacity = maxi(bot.mana_capacity, 5)
		bot.current_mana = 5
		bot.board_move_used_turn = -1


func _prepare_collector_turn(player: PlayerState) -> void:
	# This is a NEW turn after Mustache has already demonstrated its real
	# MUSTACHE_SWEEP. Keep Mustache + the two Rock friends on board so Collector
	# can collect them exactly as the tutorial teaches.
	var mustache: CardInstance = _force_definition_on_board(
		player, MUSTACHE_PATH, MUSTACHE_SLOT, mustache_id
	)
	if mustache != null:
		mustache_id = mustache.instance_id

	var rock_a: CardInstance = _force_definition_on_board(
		player, ROCK_PATH, SlotID.Type.FRONT_MIDDLE_0, cover_rock_id
	)
	if rock_a != null:
		cover_rock_id = rock_a.instance_id

	var rock_b: CardInstance = _force_definition_on_board(
		player, ROCK_PATH, SlotID.Type.FRONT_MIDDLE_1, first_rock_id
	)
	if rock_b != null:
		first_rock_id = rock_b.instance_id

	_clear_other_board_slots(
		player,
		[MUSTACHE_SLOT, SlotID.Type.FRONT_MIDDLE_0, SlotID.Type.FRONT_MIDDLE_1]
	)

	var collector_hand: Array[CardInstance] = _replace_hand_with_exact(
		player,
		TutorialScenario.collector_turn_player_hand()
	)
	if collector_hand.size() >= 5:
		collector_id = collector_hand[0].instance_id
		final_scissors_id = collector_hand[1].instance_id

	# New turn: 5 mana. Collector costs 3 and the final Scissors costs 2.
	player.mana_capacity = 5
	player.current_mana = 5
	player.board_move_used_turn = -1

	var bot: PlayerState = match_controller.state.get_player(
		match_controller.bot_player_id
	)
	if bot != null:
		_force_definition_on_board(
			bot, SCISSORS_PATH, SlotID.Type.FRONT_LEFT, -1
		)
		_force_definition_on_board(
			bot, ROCK_PATH, SlotID.Type.FRONT_MIDDLE_0, -1
		)
		_clear_other_board_slots(
			bot,
			[SlotID.Type.FRONT_LEFT, SlotID.Type.FRONT_MIDDLE_0]
		)
		_replace_hand_with_exact(
			bot,
			TutorialScenario.battle_3_bot_hand()
		)
		# Opponent mana is hidden; give enough for the exact final scripted plays.
		bot.mana_capacity = maxi(bot.mana_capacity, 8)
		bot.current_mana = 8
		bot.board_move_used_turn = -1


func notify_combat_finished() -> void:
	if not is_active():
		return

	if step == Step.COMBAT_1_RUNNING:
		_set_step(Step.NEW_TURN_2)
	elif step == Step.COMBAT_2_RUNNING:
		_set_step(Step.SPECIAL_CARD)
	elif step == Step.COMBAT_MUSTACHE_RUNNING:
		_set_step(Step.COLLECTOR_SETUP)
	elif step == Step.COMBAT_3_RUNNING:
		_set_step(Step.DEALER_POWER)


func skip() -> void:
	_exit_tutorial_to_menu()


func _set_step(new_step: Step) -> void:
	step = new_step
	feedback_time = 0.0
	target_nodes_3d.clear()
	target_control = null
	target_padding = Vector2.ZERO
	guided_drop_slot_id = -1
	pointer_label.visible = false
	instruction_label.visible = false
	continue_button.visible = false
	_hide_card_preview()

	match step:
		Step.INTRO_1:
			_show_dialogue(
				"",
				"سلام پهلوون،\nچیزی که قراره بهت نشون بدم، هم برات آشناست، هم عجیب غریبه.",
				"ادامه"
			)
			_set_focus_none()

		Step.INTRO_2:
			_show_dialogue(
				"",
				"اما نگران نباش،\nعمو دیو قراره بهت یاد بده",
				"ادامه"
			)
			_set_focus_none()

		Step.RPS_RULE:
			_show_dialogue(
				"",
				"بازی ما، اول و آخرش سنگ، کاغذ، قیچیه خودمونه\nاین‌ها هم کارت‌های بازی‌اند...",
				"ادامه"
			)
			_focus_hand_cards([ROCK_ID, PAPER_ID, SCISSORS_ID])

		Step.BOARD_INTRO:
			_show_dialogue("", "این هم زمین بازی ماست", "ادامه")
			_focus_board_area()

		Step.DEALER_ROW:
			_show_dialogue(
				"",
				"این ردیف جاییه که من کارت‌های خودمو بازی می‌کنم",
				"ادامه"
			)
			_focus_dealer_row()

		Step.GOAL:
			_show_dialogue(
				"",
				"اینجوری...\nهدف اینه که کارت رو با زمین بازی کنی که برنده سنگ کاغذ قیچی دوتا کارت باشی",
				"ادامه"
			)
			_focus_board_area()

		Step.PLAYER_ROWS:
			_show_dialogue(
				"",
				"این ۲ ردیف، جاییه که کارت‌های خودتو بازی می‌کنی",
				"ادامه"
			)
			_focus_player_rows()

		Step.PLAY_ROCK_PROMPT:
			_show_dialogue(
				"",
				"حالا یکی از کارت‌هاتو بنداز جایی که بتونی برنده باشی...",
				"ادامه"
			)
			_focus_card(first_rock_id)

		Step.MANA_CARD_COST:
			_show_dialogue(
				"",
				"برای بازی کردن هر کارت یه میزان مشخصی مانا باید مصرف کنی،\nاینجا می‌تونی تعداد مانا هر کارت رو ببینی...",
				"ادامه"
			)
			_focus_card(cover_rock_id)

		Step.MANA_TOTAL:
			_show_dialogue(
				"",
				"اینجا هم تعداد کل مانایی که در حال حاضر داری رو نشون می‌ده،\nبعد هر نوبت یه دونه به تعداد کل مانا اضافه می‌شه.",
				"ادامه"
			)
			_focus_mana()

		Step.PLAY_ROCK:
			_show_action(
				"",
				"حالا یکی از کارت‌هاتو بنداز جایی که بتونی برنده باشی...",
				""
			)
			_focus_card_and_slot(first_rock_id, FIRST_ROCK_SLOT)

		Step.ROCK_RESULT:
			_show_dialogue(
				"",
				"سنگ تو قیچی رو می‌بره و بهت امتیاز می‌ده...",
				"ادامه"
			)
			_focus_card(first_rock_id)

		Step.SCORING_RULE:
			_show_dialogue(
				"",
				"اگه ببری ۳ امتیاز، مساوی کنی ۱ امتیاز و ببازی ۰ امتیاز می‌گیری\nدرست مثل فوتبال :)",
				"ادامه"
			)
			_focus_balance_scale()

		Step.LANES:
			_show_dialogue(
				"",
				"زمین بازی ۳ تا ستون داره.\nکارت‌های هر ستون هم با هم رقابت می‌کنند",
				"ادامه"
			)
			_focus_player_rows()

		Step.MIDDLE_LANE:
			_show_dialogue(
				"",
				"بله درست فهمیدی ستون وسط ۲ تا کارت جا می‌شه.\nاین وسط میدون جنگه :)",
				"ادامه"
			)
			_focus_middle_lane()

		Step.DEALER_REFRESH:
			_show_dialogue(
				"",
				"بعد از هر نوبت، من کارت‌های جدید روی زمین می‌چینم...",
				"ادامه"
			)
			_focus_dealer_row()

		Step.DRAW_REFRESH:
			_show_dialogue(
				"",
				"چند تا کارت جدید هم از دسته کارت‌هایی که داره به دست خودت اضافه می‌شه",
				"ادامه"
			)
			_focus_all_local_hand_cards()

		Step.PLAY_SCISSORS:
			_show_action("", "حالا یه کارت جدید بازی کن", "")
			_focus_card_and_slot(scissors_id, FIRST_SCISSORS_SLOT)

		Step.MIDDLE_PLACEMENT:
			_show_dialogue(
				"",
				"داخل ستون وسط مهم نیست کارت رو کدوم سمت بذاری",
				"ادامه"
			)
			_focus_middle_lane()

		Step.OPPONENT_ARRIVES:
			_set_opponent_hand_visible(true)
			_show_dialogue(
				"",
				"صبر کن ببینم...\nفکر کنم یه حریف اومده باهات بازی کنه",
				"ادامه"
			)
			_focus_opponent_hand()

		Step.HIDDEN_CARD_DEMO:
			_set_card_face_up(scissors_id, false)
			_show_dialogue(
				"",
				"الان حریف کارت قیچی تو و جایی که بازی کردی رو نمی‌بینه",
				"ادامه"
			)
			_focus_card(scissors_id)

		Step.HIDDEN_PLAY:
			_show_dialogue(
				"",
				"هر دو بازیکن، همزمان با هم بازی می‌کنند. زمانی که هر دو بازیکن دکمه مبارزه رو بزنن، کارت‌های همدیگر رو می‌تونند ببینند.",
				"ادامه"
			)
			_focus_opponent_hand()

		Step.END_TURN_1:
			_show_action(
				"",
				"حالا دکمه رو بزن که کارت‌های جدید هر دو بازیکن روی زمین رو بشن...",
				""
			)
			_focus_end_turn()

		Step.WAIT_REVEAL_1:
			_show_waiting("", "...")
			_set_focus_none()

		Step.REVEAL_1_INTRO:
			_show_dialogue(
				"",
				"حالا که همه کارت‌ها رو شد من امتیازها رو از سمت چپ حساب می‌کنم...",
				"ادامه"
			)
			_focus_player_rows()

		Step.LANE_1_RESULT:
			_show_dialogue(
				"",
				"ستون اول فقط کارت من و کارت خودت هست.\nچون ۲ تا سنگه، پس با هم مساوی می‌کنند.\n۱ امتیاز گرفتی",
				"ادامه"
			)
			_focus_player_slot_and_dealer(
				SlotID.Type.FRONT_LEFT,
				DealerSlotID.Type.LEFT
			)

		Step.LANE_2_INTRO:
			_show_dialogue(
				"",
				"ستون دوم جالب می‌شه: رو زمین یه قیچی و یه کاغذ منه،\nحریف یه سنگ داره و تو هم یه قیچی دیگه\nبیا نشون بدم چجوری حساب می‌شه...",
				"ادامه"
			)
			_focus_middle_player_and_dealer()

		Step.RESOLUTION_ORDER:
			_show_dialogue(
				"",
				"اول هر کدوم از بازیکن‌ها با کارت‌های من حساب می‌شه.\nبعدش نوبت تو و حریف می‌رسه...",
				"ادامه"
			)
			_focus_board_area()

		Step.SCORE_SCALE:
			_show_dialogue(
				"",
				"همینجوری که می‌بینی، امتیازها روی صفحه ترازو هر کدوم از بازیکن‌ها نشون داده می‌شه.\nاگه اختلاف به 30 عدد برسه، برنده می‌شید.",
				"ادامه"
			)
			_focus_balance_scale()

		Step.COMBAT_1_RUNNING:
			_show_waiting("", "...")
			_set_focus_none()

		Step.NEW_TURN_2:
			_show_dialogue(
				"",
				"بریم سراغ نوبت بعدی، من کارت‌هامو عوض می‌کنم. تو هم چندتا کارت جدید بردار یدونه مانا اضافه هم گیرت میاد",
				"ادامه"
			)
			_focus_all_local_hand_cards()

		Step.BAD_POSITION:
			_show_dialogue(
				"",
				"الان تو شرایط خوبی نیستی.\nستون سمت چپ، سنگت به کاغذ روی زمین می‌بازه.\nستون وسط هم، سنگ حریف قیچی تورو می‌زنه، و اینکه خودش ۲ تا قیچی روی زمین رو هم می‌بره",
				"ادامه"
			)
			_focus_board_area()

		Step.MOVE_ROCK:
			_show_action(
				"",
				"نگران نباش که عمو دیو اینجاست.\nبهتره، سنگ ستون سمت چپ رو جاشو عوض کنیم.\nکارت رو بگیر و بندازش یه جای بهتر...",
				""
			)
			_focus_card_and_slot(first_rock_id, MOVE_ROCK_TO_SLOT)

		Step.MOVE_RESULT:
			_show_dialogue(
				"",
				"برای این کار فقط ۱ مانا مصرف می‌شه.\nتو هر نوبت هم می‌تونی فقط ۱ دفعه این کارو انجام بدی.\nحالا کارت سنگت، به جای باخت از کاغذ، ۲ تا قیچی رو زمین رو می‌بره!!!!",
				"ادامه"
			)
			_focus_card(first_rock_id)

		Step.COVER_SETUP:
			_show_dialogue(
				"",
				"حالا صبر کن، هنوز می‌شه با همین ۲ تا مانایی که داری شرایط رو بهتر کرد :))))\nبیا قیچی رو از روی زمینت برداریم تا به سنگ حریف نبازی و نذاری امتیاز بگیره",
				"ادامه"
			)
			_focus_card(scissors_id)

		Step.COVER_SCISSORS:
			_show_action(
				"",
				"کارت‌هایی که داری همیشه نیاز نداره جای خالی زمین بازی بشه. قانون سنگ کاغذ قیچی روی کارت‌های خودتم برقراره.\nسنگ رو از دستت بردار و روی کارت قیچی زمینت بذار",
				""
			)
			_focus_card_and_slot(cover_rock_id, FIRST_SCISSORS_SLOT)

		Step.END_TURN_2:
			_show_action(
				"",
				"خب حالا دکمه رو بزن تا ببینیم حریف چیکار کرده",
				""
			)
			_focus_end_turn()

		Step.WAIT_REVEAL_2:
			_show_waiting("", "...")
			_set_focus_none()

		Step.REVEAL_2_RESULT:
			_show_dialogue(
				"",
				"خب بذار امتیازها حساب بشه.\nحریف ترجیح داد فقط ۲ تا از ۳ تا مانای خودشو مصرف کنه\nبریم نوبت بعدی",
				"ادامه"
			)
			_focus_balance_scale()

		Step.COMBAT_2_RUNNING:
			_show_waiting("", "...")
			_set_focus_none()

		Step.SPECIAL_CARD:
			_show_action(
				"",
				"الان ۴ تا مانا داری.\nیه کارت خیلی خوب هم داری.\nبزن روی کارت تا ببینیم داستانش چیه",
				""
			)
			_focus_card(mustache_id)

		Step.CONDITIONAL_RULE:
			_show_dialogue(
				"",
				"این یکی از کارت‌های شرطیه، یعنی اگه شرایطی که روی کارت نوشته شده رو داشته باشی می‌تونی از قدرت خاص کارت استفاده کنی.",
				"ادامه"
			)
			_show_card_preview(mustache_id)
			_set_focus_none()

		Step.PLAY_MUSTACHE:
			_show_action(
				"",
				"به به، سنگ سیبیل رفیق باز رو صدا کن بیاد که کارو برات درمیاره :))))\nدقت کن که مهم نیست کجای زمین بازیش کنی. پس یه جای خوب براش بذار",
				""
			)
			# مثل ویدیوی مرجع کارت هنوز بزرگ دیده می‌شود، ولی هدف واقعی
			# interaction همان کارت داخل Hand است. با شروع Drag preview جمع می‌شود.
			_show_card_preview(mustache_id)
			_focus_card_and_slot(mustache_id, MUSTACHE_SLOT)

		Step.MUSTACHE_EFFECT:
			_show_dialogue(
				"",
				"حالا موقع حمله سنگ سیبیل، خودش و دو تا رفیقش هر ۴ تا کارت زمین رو می‌برند.",
				"ادامه"
			)
			_focus_card(mustache_id)

		Step.END_TURN_MUSTACHE:
			_show_action(
				"",
				"حالا دکمه مبارزه رو بزن تا قدرت سنگ سیبیل رو خودت ببینی.",
				""
			)
			_focus_end_turn()

		Step.WAIT_REVEAL_MUSTACHE:
			_show_waiting("", "...")
			_set_focus_none()

		Step.COMBAT_MUSTACHE_RUNNING:
			_show_waiting("", "...")
			_set_focus_none()

		Step.COLLECTOR_SETUP:
			_show_action(
				"",
				"از دستم در رفت یه زمین چیدم که برای تو خوب نیست :))\nنگران نباش هواتو دارم،\nکارت فرغون رو بزن روش و بخون ببین چی میگه...",
				""
			)
			_focus_card(collector_id)

		Step.COLLECTOR_INFO:
			_show_dialogue(
				"",
				"چه جالب...\nاین دقیقا چیزیه که نیاز داریم. این کارت رو هر موقع بازی کنی هر کجای زمین سنگ داشته باشی برش می‌داره می‌بره :)\nفراموش نکن که حاشیه هر کارت نشون دهنده مدل سنگ کاغذ یا قیچیه. آبی‌ها سنگ، قرمزها قیچی و زردها کاغذ",
				"ادامه"
			)
			_show_card_preview(collector_id)
			_set_focus_none()

		Step.PLAY_COLLECTOR:
			_show_action(
				"",
				"حالا بذارش روی ردیف دوم پشت سنگ سیبیل.\n۲ تا مانای دیگه هم می‌مونه می‌تونی یه کارت دیگه هم بازی کنی.\nبعدش هم دکمه رو بزن",
				""
			)
			_show_card_preview(collector_id)
			_focus_card_and_slot(collector_id, COLLECTOR_SLOT)

		Step.COLLECTOR_RESOLVING:
			_show_waiting("", "...")
			_set_focus_none()

		Step.COLLECTOR_PROMOTION:
			_show_dialogue(
				"",
				"سنگ‌ها رفتند...\nدقت کن که فرغون که ردیف دوم بود الان که جلوش خالی شد رفت ردیف جلو.",
				"ادامه"
			)
			_focus_left_lane()

		Step.FINAL_SCISSORS:
			_show_action(
				"",
				"۲ تا مانای دیگه هم مونده؛ یه کارت دیگه هم بازی کن.",
				""
			)
			_focus_card_and_slot(final_scissors_id, FINAL_SCISSORS_SLOT)

		Step.END_TURN_3:
			_show_action(
				"",
				"آخ آخ، حریف هم همچین بی کار نبوده...\nشرمنده تقصیر من شد.\nصبر کن برات جبران کنم مشتی...\nدکمه رو بزن",
				""
			)
			_focus_end_turn()

		Step.WAIT_REVEAL_3:
			_show_waiting("", "...")
			_set_focus_none()

		Step.COMBAT_3_RUNNING:
			_show_waiting("", "...")
			_set_focus_none()

		Step.DEALER_POWER:
			_show_dialogue(
				"",
				"این یکی از قدرت‌های منه :))))\nوقتی کارت دیو بیاد رو زمین کل اون ستون خالی می‌شه.\nنگران کارت‌های حذف شده هم نباش",
				"ادامه"
			)
			_focus_dealer_row()

		Step.REMOVED_CARDS:
			_show_dialogue(
				"",
				"همشون میرن داخل دسته کارت ها و وقتی نوبتشون بشه دوباره میان تو دستت.",
				"ادامه"
			)
			_set_focus_none()

		Step.COMPLETE:
			_show_dialogue(
				"",
				"به نظرم دیگه آماده‌ای. برو یه دست خودت تنهایی بازی کن تا بازی بیشتر دستت بیاد.\nیادت نره توضیحات روی کارت‌ها رو دقت کن و برو حالشو ببر.",
				"شروع بازی"
			)
			_set_focus_none()
		Step.FULL_DIV:
			_show_dialogue(
				"",
				"حالا دیگه آماده‌ای پهلوون :))))",
				"بازگشت به منو"
			)

			_focus_dealer_row()
		Step.FINISHED:
			_finish_tutorial()

	_update_hud_gate()
	_update_progress()


func _on_continue_pressed() -> void:
	if not is_active():
		return

	match step:
		Step.INTRO_1:
			_set_step(Step.INTRO_2)
		Step.INTRO_2:
			_set_step(Step.RPS_RULE)
		Step.RPS_RULE:
			_set_step(Step.BOARD_INTRO)
		Step.BOARD_INTRO:
			_set_step(Step.DEALER_ROW)
		Step.DEALER_ROW:
			_set_step(Step.GOAL)
		Step.GOAL:
			_set_step(Step.PLAYER_ROWS)
		Step.PLAYER_ROWS:
			_set_step(Step.PLAY_ROCK_PROMPT)
		Step.PLAY_ROCK_PROMPT:
			# No mana explanation in the solo opening section.
			_set_step(Step.PLAY_ROCK)
		Step.ROCK_RESULT:
			_set_step(Step.SCORING_RULE)
		Step.SCORING_RULE:
			_set_step(Step.LANES)
		Step.LANES:
			_set_step(Step.MIDDLE_LANE)
		Step.MIDDLE_LANE:
			await _apply_solo_dealer_refresh()
			_set_step(Step.DEALER_REFRESH)
		Step.DEALER_REFRESH:
			await _prepare_solo_second_hand()
			_set_step(Step.DRAW_REFRESH)
		Step.DRAW_REFRESH:
			_set_step(Step.PLAY_SCISSORS)
		Step.MIDDLE_PLACEMENT:
			await _prepare_opponent_arrival()
			_set_step(Step.OPPONENT_ARRIVES)
		Step.OPPONENT_ARRIVES:
			_set_step(Step.HIDDEN_CARD_DEMO)
		Step.HIDDEN_CARD_DEMO:
			_set_card_face_up(scissors_id, true)
			_set_step(Step.HIDDEN_PLAY)
		Step.HIDDEN_PLAY:
			_set_step(Step.END_TURN_1)
		Step.REVEAL_1_INTRO:
			_set_step(Step.LANE_1_RESULT)
		Step.LANE_1_RESULT:
			_set_step(Step.LANE_2_INTRO)
		Step.LANE_2_INTRO:
			_set_step(Step.RESOLUTION_ORDER)
		Step.RESOLUTION_ORDER:
			_set_step(Step.SCORE_SCALE)
		Step.SCORE_SCALE:
			_set_step(Step.COMBAT_1_RUNNING)
			combat_gate_released.emit()
		Step.NEW_TURN_2:
			_set_step(Step.MANA_CARD_COST)
		Step.MANA_CARD_COST:
			_set_step(Step.MANA_TOTAL)
		Step.MANA_TOTAL:
			_set_step(Step.BAD_POSITION)
		Step.BAD_POSITION:
			_set_step(Step.MOVE_ROCK)
		Step.MOVE_RESULT:
			_set_step(Step.COVER_SETUP)
		Step.COVER_SETUP:
			_set_step(Step.COVER_SCISSORS)
		Step.REVEAL_2_RESULT:
			_set_step(Step.COMBAT_2_RUNNING)
			combat_gate_released.emit()
		Step.CONDITIONAL_RULE:
			_set_step(Step.PLAY_MUSTACHE)
		Step.MUSTACHE_EFFECT:
			_set_step(Step.END_TURN_MUSTACHE)
		Step.COLLECTOR_INFO:
			_set_step(Step.PLAY_COLLECTOR)
		Step.COLLECTOR_PROMOTION:
			_set_step(Step.FINAL_SCISSORS)
		Step.DEALER_POWER:
			_set_step(Step.REMOVED_CARDS)
		Step.REMOVED_CARDS:
			_set_step(Step.COMPLETE)
		Step.COMPLETE:
			await _show_full_div_row()
			_set_step(Step.FULL_DIV)

		Step.FULL_DIV:
			_exit_tutorial_to_menu()

func _exit_tutorial_to_menu() -> void:
	# رسیدن به انتهای Tutorial یا زدن Skip یعنی
	# Tutorial خودکار دیگر در Single Player نمایش داده نشود.
	_mark_tutorial_completed()

	active = false

	if guide_sprite != null:
		guide_sprite.stop()

	if overlay_root != null:
		overlay_root.hide()

	visible = false

	# کل Main Scene از اول Load می‌شود.
	# در نتیجه Main Menu دوباره ظاهر می‌شود.
	get_tree().paused = false
	get_tree().reload_current_scene()


func _mark_tutorial_completed() -> void:
	var config := ConfigFile.new()

	# اگر فایل قبلاً وجود داشته باشد، مقدارهای دیگرش حفظ می‌شوند.
	config.load(TUTORIAL_PROGRESS_PATH)

	config.set_value(
		TUTORIAL_PROGRESS_SECTION,
		TUTORIAL_PROGRESS_KEY,
		true
	)

	var save_error: Error = config.save(
		TUTORIAL_PROGRESS_PATH
	)

	if save_error != OK:
		push_error(
			"Could not save tutorial progress: "
			+ str(save_error)
		)


func _finish_tutorial() -> void:
	active = false
	step = Step.FINISHED
	visible = false
	if guide_sprite != null:
		guide_sprite.stop()
	_hide_card_preview()
	target_nodes_3d.clear()
	target_control = null
	if match_controller != null and match_controller.hud != null:
		match_controller.hud.set_interaction_enabled(
			not match_controller.interaction_locked
		)


func _update_hud_gate() -> void:
	if match_controller == null or match_controller.hud == null:
		return
	if match_controller.interaction_locked:
		match_controller.hud.set_interaction_enabled(false)
		return
	match_controller.hud.set_interaction_enabled(can_press_end_turn())


func _update_progress() -> void:
	if progress_label == null:
		return
	var current: int = clampi(int(step) + 1, 1, int(Step.COMPLETE) + 1)
	var total: int = int(Step.COMPLETE) + 1
	progress_label.text = "آموزش  %d / %d" % [current, total]


func _show_dialogue(title: String, text: String, button_text: String) -> void:
	title_label.text = title
	normal_message = text
	message_label.text = text
	instruction_label.visible = false
	continue_button.text = button_text
	continue_button.visible = true


func _show_action(title: String, text: String, instruction: String) -> void:
	title_label.text = title
	normal_message = text
	message_label.text = text
	# The reference animation has no extra helper sentence in the bubble.
	instruction_label.text = instruction
	instruction_label.visible = false
	continue_button.visible = false
	pointer_label.visible = true


func _show_waiting(title: String, text: String) -> void:
	title_label.text = title
	normal_message = text
	message_label.text = text
	instruction_label.visible = false
	continue_button.visible = false
	pointer_label.visible = false


func _refresh_hud() -> void:
	if match_controller == null or match_controller.hud == null:
		return
	match_controller.hud.refresh(
		match_controller.state,
		match_controller.local_player_id
	)


func _set_opponent_hand_visible(show_hand: bool) -> void:
	if match_controller == null:
		return
	for raw_view: Variant in match_controller.opponent_hand_views.values():
		var view: Card3D = raw_view as Card3D
		if view != null:
			view.visible = show_hand


func _set_card_face_up(instance_id: int, face_up: bool) -> void:
	var view: Card3D = _card_view(instance_id)
	if view != null:
		view.set_face_up(face_up)

func _show_full_div_row() -> void:
	# کارت‌های Dealer فعلی رو نگه می‌داریم
	# تا سیستم بفهمه چهار دیو، کارت‌های NEW هستند.
	var previous_dealer_card_ids: Dictionary = \
		match_controller._get_dealer_card_ids()

	# چهار دیو را روی زمین بگذار
	_set_dealer_board_exact(
		TutorialScenario.dealer_full_div()
	)

	# اول Visual چهار دیو ساخته شود
	await match_controller.refresh_tutorial_visual_state()

	_set_opponent_hand_visible(true)

	# حالا Placed VFX واقعی هر چهار دیو اجرا شود
	await match_controller._play_new_dealer_placed_vfx(
		previous_dealer_card_ids
	)

	# بعد از تمام شدن VFX، قدرت دیوها اجرا شود
	match_controller.engine._run_dealer_enter_behaviors()

	# کارت‌هایی که دیو پاک کرده از نظر تصویری هم حذف شوند
	await match_controller.refresh_tutorial_visual_state()

	_set_opponent_hand_visible(true)


func _apply_solo_dealer_refresh() -> void:
	_set_dealer_board_exact(
		TutorialScenario.dealer_first_battle()
	)
	await match_controller.refresh_tutorial_visual_state()
	_set_opponent_hand_visible(false)


func _prepare_solo_second_hand() -> void:
	var player: PlayerState = _player()
	if player == null:
		return

	var cards: Array[CardInstance] = _replace_hand_with_exact(
		player,
		TutorialScenario.solo_second_player_hand()
	)
	if cards.size() >= 4:
		scissors_id = cards[0].instance_id

	# Early tutorial uses the real cards but does not teach mana yet.
	player.mana_capacity = maxi(player.mana_capacity, 2)
	player.current_mana = 2
	_refresh_hud()

	await match_controller.refresh_tutorial_visual_state()
	_set_opponent_hand_visible(false)


func _prepare_opponent_arrival() -> void:
	var bot: PlayerState = match_controller.state.get_player(
		match_controller.bot_player_id
	)
	if bot == null:
		return

	_replace_hand_with_exact(
		bot,
		TutorialScenario.battle_1_bot_hand()
	)
	bot.mana_capacity = maxi(bot.mana_capacity, 2)
	bot.current_mana = 2

	await match_controller.refresh_tutorial_visual_state()
	_set_opponent_hand_visible(true)


func _find_hand_card_by_path(
	player: PlayerState,
	resource_path: String
) -> CardInstance:
	if player == null:
		return null

	var definition: CardDefinition = load(resource_path) as CardDefinition
	if definition == null:
		return null

	for card: CardInstance in player.hand:
		if _matches_definition(card, definition):
			return card

	return null


func _set_dealer_board_exact(resource_paths: Array[String]) -> void:
	if match_controller == null or match_controller.state == null:
		return
	if resource_paths.size() != DealerSlotID.all_slots().size():
		push_error("Tutorial Dealer layout must contain exactly 4 cards.")
		return

	var dealer = match_controller.state.dealer
	if dealer == null:
		return

	var slots: Array[int] = DealerSlotID.all_slots()
	for slot_id: int in slots:
		var old_card: CardInstance = dealer.slots.get(slot_id, null) as CardInstance
		if old_card != null:
			old_card.zone = CardZone.Type.DISCARD
			old_card.current_slot = CardInstance.NO_SLOT
			dealer.discard_pile.append(old_card)
		dealer.slots[slot_id] = null

	for index: int in range(slots.size()):
		var definition: CardDefinition = load(resource_paths[index]) as CardDefinition
		if definition == null:
			push_error("Tutorial Dealer resource missing: " + resource_paths[index])
			continue
		var card: CardInstance = match_controller.engine.card_factory.create_card(
			definition,
			0
		)
		card.zone = CardZone.Type.DEALER_BOARD
		card.current_slot = slots[index]
		dealer.slots[slots[index]] = card


func _prime_dealer_draw(resource_paths: Array[String]) -> void:
	if match_controller == null or match_controller.state == null:
		return
	if resource_paths.size() != DealerSlotID.all_slots().size():
		push_error("Tutorial Dealer draw must contain exactly 4 cards.")
		return

	var dealer = match_controller.state.dealer
	if dealer == null:
		return

	dealer.draw_pile.clear()

	# DealerMover uses pop_back() while iterating LEFT -> RIGHT, so append the
	# desired row in reverse order.
	for index: int in range(resource_paths.size() - 1, -1, -1):
		var definition: CardDefinition = load(resource_paths[index]) as CardDefinition
		if definition == null:
			push_error("Tutorial Dealer resource missing: " + resource_paths[index])
			continue
		var card: CardInstance = match_controller.engine.card_factory.create_card(
			definition,
			0
		)
		card.zone = CardZone.Type.DRAW
		card.current_slot = CardInstance.NO_SLOT
		dealer.draw_pile.append(card)


func _clear_other_board_slots(
	player: PlayerState,
	keep_slots: Array[int]
) -> void:
	if player == null:
		return
	for slot_id: int in SlotID.all_slots():
		if keep_slots.has(slot_id):
			continue
		_clear_board_slot(player, slot_id)


func _resolve_tutorial_collector_sequence() -> void:
	if not is_active() or step != Step.COLLECTOR_RESOLVING:
		return

	var player: PlayerState = _player()
	if player == null:
		return

	var collector: CardInstance = player.board.get_card(COLLECTOR_SLOT)
	if collector == null or collector.instance_id != collector_id:
		push_error("Tutorial Collector is not in BACK_LEFT.")
		return

	# The reference animation has Collector resolve immediately after placement
	# and it also collects Mustache Rock. The production Collector currently
	# resolves at combat start and skips same-turn cards, so this one sequence is
	# intentionally tutorial-only and does not change the real card behavior.
	var mustache: CardInstance = player.board.get_card(MUSTACHE_SLOT)
	if mustache != null:
		mustache.turn_played = match_controller.state.turn_number - 1

	await match_controller.play_tutorial_collector_vfx_now()

	var rock_slots: Array[int] = []
	for slot_id: int in SlotID.all_slots():
		var card: CardInstance = player.board.get_card(slot_id)
		if card == null or card == collector or card.definition == null:
			continue
		if card.definition.gesture == CardGesture.Type.ROCK:
			rock_slots.append(slot_id)

	for slot_id: int in rock_slots:
		_clear_board_slot(player, slot_id)

	if player.board.get_card(COLLECTOR_SLOT) == collector:
		player.board.move_card(COLLECTOR_SLOT, MUSTACHE_SLOT)

	collector.ability_used = true

	await match_controller.refresh_tutorial_visual_state()
	_set_opponent_hand_visible(true)
	_set_step(Step.COLLECTOR_PROMOTION)


func _replace_hand_with_exact(
	player: PlayerState,
	resource_paths: Array[String]
) -> Array[CardInstance]:
	var result: Array[CardInstance] = []
	if player == null:
		return result

	# Put the current random hand back into the draw pile.  The tutorial then
	# creates its own deterministic cards and therefore looks identical on
	# every run regardless of deck shuffle/order.
	for index: int in range(player.hand.size() - 1, -1, -1):
		var old_card: CardInstance = player.hand[index]
		player.hand.remove_at(index)
		if old_card != null:
			old_card.zone = CardZone.Type.DRAW
			player.draw_pile.append(old_card)

	for resource_path: String in resource_paths:
		var definition: CardDefinition = load(resource_path) as CardDefinition
		if definition == null:
			push_error("Tutorial card resource is missing: " + resource_path)
			continue
		var card: CardInstance = match_controller.engine.card_factory.create_card(
			definition,
			player.player_id
		)
		card.zone = CardZone.Type.HAND
		player.hand.append(card)
		result.append(card)

	return result


func _player() -> PlayerState:
	if match_controller == null or match_controller.state == null:
		return null
	return match_controller.state.get_player(match_controller.local_player_id)


func _ensure_card_in_hand(
	player: PlayerState,
	resource_path: String,
	excluded_ids: Dictionary
) -> CardInstance:
	if player == null:
		return null
	var definition := load(resource_path) as CardDefinition
	if definition == null:
		push_error("Tutorial card resource is missing: " + resource_path)
		return null

	for card: CardInstance in player.hand:
		if _matches_definition(card, definition) and not excluded_ids.has(card.instance_id):
			return card

	for index: int in range(player.draw_pile.size()):
		var draw_card: CardInstance = player.draw_pile[index]
		if _matches_definition(draw_card, definition) and not excluded_ids.has(draw_card.instance_id):
			player.draw_pile.remove_at(index)
			draw_card.zone = CardZone.Type.HAND
			player.hand.append(draw_card)
			return draw_card

	for index: int in range(player.discard_pile.size()):
		var discard_card: CardInstance = player.discard_pile[index]
		if _matches_definition(discard_card, definition) and not excluded_ids.has(discard_card.instance_id):
			player.discard_pile.remove_at(index)
			discard_card.zone = CardZone.Type.HAND
			player.hand.append(discard_card)
			return discard_card

	var created: CardInstance = match_controller.engine.card_factory.create_card(
		definition,
		player.player_id
	)
	created.zone = CardZone.Type.HAND
	player.hand.append(created)
	return created


func _matches_definition(card: CardInstance, definition: CardDefinition) -> bool:
	return (
		card != null
		and card.definition != null
		and definition != null
		and card.definition.card_id == definition.card_id
	)


func _force_definition_on_board(
	player: PlayerState,
	resource_path: String,
	slot_id: int,
	preferred_instance_id: int
) -> CardInstance:
	var definition := load(resource_path) as CardDefinition
	if definition == null:
		return null

	var existing: CardInstance = player.board.get_card(slot_id)
	if existing != null and _matches_definition(existing, definition):
		existing.turn_played = mini(existing.turn_played, match_controller.state.turn_number - 1)
		return existing

	# Reuse the preferred tutorial card if it still exists elsewhere on board.
	var candidate: CardInstance = null
	for board_slot: int in SlotID.all_slots():
		var board_card: CardInstance = player.board.get_card(board_slot)
		if board_card == null:
			continue
		if board_card.instance_id == preferred_instance_id and _matches_definition(board_card, definition):
			candidate = player.board.remove_card(board_slot)
			break

	_clear_board_slot(player, slot_id)

	if candidate == null:
		candidate = match_controller.engine.card_factory.create_card(
			definition,
			player.player_id
		)

	if not player.board.place_card(slot_id, candidate):
		return null
	candidate.turn_played = match_controller.state.turn_number - 1
	candidate.reset_for_board_entry()
	return candidate


func _clear_board_slot(player: PlayerState, slot_id: int) -> void:
	if player == null:
		return
	var old_card: CardInstance = player.board.remove_card(slot_id)
	if old_card == null:
		return
	old_card.zone = CardZone.Type.DISCARD
	if not player.discard_pile.has(old_card):
		player.discard_pile.append(old_card)


func _card_view(instance_id: int) -> Card3D:
	if match_controller == null or instance_id < 0:
		return null
	return match_controller.card_views.get(instance_id, null) as Card3D


func _focus_card(instance_id: int) -> void:
	target_nodes_3d.clear()
	var view: Card3D = _card_view(instance_id)
	if view != null:
		target_nodes_3d.append(view)
	target_control = null
	# Hand cards are visually almost twice the projected size of board cards.
	target_padding = HAND_CARD_SPOTLIGHT_SIZE if _is_local_hand_card(instance_id) else CARD_SPOTLIGHT_SIZE


func _is_local_hand_card(instance_id: int) -> bool:
	var player: PlayerState = _player()
	if player == null:
		return false
	for card: CardInstance in player.hand:
		if card != null and card.instance_id == instance_id:
			return true
	return false


func _focus_board_slot(slot_id: int) -> void:
	target_nodes_3d.clear()
	var place: CardPlace3D = match_controller.game_layout.get_board_place(
		match_controller.local_player_id,
		slot_id
	)
	if place != null:
		target_nodes_3d.append(place)
	target_control = null
	target_padding = SLOT_SPOTLIGHT_SIZE


func _focus_card_and_slot(instance_id: int, slot_id: int) -> void:
	# Do NOT merge source card + destination into one giant rectangle.  Start
	# by showing only the exact card; notify_drag_started() switches to the
	# exact destination slot once the card is picked up.
	guided_drop_slot_id = slot_id
	_focus_card(instance_id)


func _restore_step_focus() -> void:
	match step:
		Step.PLAY_ROCK:
			_focus_card_and_slot(first_rock_id, FIRST_ROCK_SLOT)
		Step.PLAY_SCISSORS:
			_focus_card_and_slot(scissors_id, FIRST_SCISSORS_SLOT)
		Step.MOVE_ROCK:
			_focus_card_and_slot(first_rock_id, MOVE_ROCK_TO_SLOT)
		Step.COVER_SCISSORS:
			_focus_card_and_slot(cover_rock_id, FIRST_SCISSORS_SLOT)
		Step.SPECIAL_CARD:
			_focus_card(mustache_id)
		Step.PLAY_MUSTACHE:
			_focus_card_and_slot(mustache_id, MUSTACHE_SLOT)
		Step.COLLECTOR_SETUP:
			_focus_card(collector_id)
		Step.PLAY_COLLECTOR:
			_focus_card_and_slot(collector_id, COLLECTOR_SLOT)
		Step.FINAL_SCISSORS:
			_focus_card_and_slot(final_scissors_id, FINAL_SCISSORS_SLOT)
		Step.END_TURN_1, Step.END_TURN_2, Step.END_TURN_MUSTACHE, Step.END_TURN_3:
			_focus_end_turn()


func _focus_hand_cards(card_ids: Array[String]) -> void:
	target_nodes_3d.clear()
	var player := _player()
	if player == null:
		return
	for card: CardInstance in player.hand:
		if card == null or card.definition == null:
			continue
		if not card_ids.has(String(card.definition.card_id)):
			continue
		var view := _card_view(card.instance_id)
		if view != null:
			target_nodes_3d.append(view)
	target_control = null
	target_padding = HAND_CARD_SPOTLIGHT_SIZE


func _focus_all_local_hand_cards() -> void:
	target_nodes_3d.clear()
	var player := _player()
	if player == null:
		return
	for card: CardInstance in player.hand:
		var view := _card_view(card.instance_id)
		if view != null:
			target_nodes_3d.append(view)
	target_control = null
	target_padding = HAND_CARD_SPOTLIGHT_SIZE


func _focus_opponent_hand() -> void:
	target_nodes_3d.clear()
	if match_controller == null:
		return
	for raw_view: Variant in match_controller.opponent_hand_views.values():
		var view := raw_view as Card3D
		if view != null:
			target_nodes_3d.append(view)
	target_control = null
	target_padding = CARD_SPOTLIGHT_SIZE


func _focus_front_row() -> void:
	target_nodes_3d.clear()
	for slot_id: int in [
		SlotID.Type.FRONT_LEFT,
		SlotID.Type.FRONT_MIDDLE_0,
		SlotID.Type.FRONT_MIDDLE_1,
		SlotID.Type.FRONT_RIGHT,
	]:
		var place: CardPlace3D = match_controller.game_layout.get_board_place(
			match_controller.local_player_id,
			slot_id
		)
		if place != null:
			target_nodes_3d.append(place)
	target_control = null
	target_padding = SLOT_SPOTLIGHT_SIZE


func _focus_middle_lane() -> void:
	target_nodes_3d.clear()
	for slot_id: int in [
		SlotID.Type.FRONT_MIDDLE_0,
		SlotID.Type.FRONT_MIDDLE_1,
		SlotID.Type.BACK_MIDDLE_0,
		SlotID.Type.BACK_MIDDLE_1,
	]:
		var place: CardPlace3D = match_controller.game_layout.get_board_place(
			match_controller.local_player_id,
			slot_id
		)
		if place != null:
			target_nodes_3d.append(place)
	target_control = null
	target_padding = SLOT_SPOTLIGHT_SIZE


func _focus_player_rows() -> void:
	target_nodes_3d.clear()
	if match_controller == null or match_controller.game_layout == null:
		return
	for slot_id: int in SlotID.all_slots():
		var place: CardPlace3D = match_controller.game_layout.get_board_place(
			match_controller.local_player_id,
			slot_id
		)
		if place != null:
			target_nodes_3d.append(place)
	target_control = null
	target_padding = SLOT_SPOTLIGHT_SIZE


func _focus_dealer_row() -> void:
	target_nodes_3d.clear()
	if match_controller == null or match_controller.game_layout == null:
		return
	for slot_id: int in DealerSlotID.all_slots():
		var anchor: Marker3D = match_controller.game_layout.get_dealer_anchor(slot_id)
		if anchor != null:
			target_nodes_3d.append(anchor)
	target_control = null
	target_padding = SLOT_SPOTLIGHT_SIZE


func _focus_board_area() -> void:
	target_nodes_3d.clear()
	if match_controller == null or match_controller.game_layout == null:
		return
	for slot_id: int in SlotID.all_slots():
		var local_place: CardPlace3D = match_controller.game_layout.get_board_place(
			match_controller.local_player_id,
			slot_id
		)
		if local_place != null:
			target_nodes_3d.append(local_place)
	for dealer_slot_id: int in DealerSlotID.all_slots():
		var anchor: Marker3D = match_controller.game_layout.get_dealer_anchor(dealer_slot_id)
		if anchor != null:
			target_nodes_3d.append(anchor)
	target_control = null
	target_padding = SLOT_SPOTLIGHT_SIZE


func _focus_left_lane() -> void:
	target_nodes_3d.clear()
	if match_controller == null or match_controller.game_layout == null:
		return
	for slot_id: int in [SlotID.Type.FRONT_LEFT, SlotID.Type.BACK_LEFT]:
		var place: CardPlace3D = match_controller.game_layout.get_board_place(
			match_controller.local_player_id,
			slot_id
		)
		if place != null:
			target_nodes_3d.append(place)
	target_control = null
	target_padding = SLOT_SPOTLIGHT_SIZE


#func _focus_balance_scale() -> void:
	#target_nodes_3d.clear()
	#if match_controller != null and match_controller.balance_scale != null:
		#target_nodes_3d.append(match_controller.balance_scale)
	#target_control = null
	#target_padding = SCALE_SPOTLIGHT_SIZE


func _focus_mana() -> void:
	target_nodes_3d.clear()
	target_control = match_controller.hud.player_mana_label
	target_padding = CONTROL_SPOTLIGHT_PADDING


func _focus_end_turn() -> void:
	target_nodes_3d.clear()
	target_control = match_controller.hud.end_turn_button
	target_padding = CONTROL_SPOTLIGHT_PADDING


func _set_focus_none() -> void:
	target_nodes_3d.clear()
	target_control = null
	_hide_focus()


func _focus_balance_scale() -> void:
	target_nodes_3d.clear()

func _focus_player_slot_and_dealer(
	player_slot_id: int,
	dealer_slot_id: int
) -> void:
	target_nodes_3d.clear()

	if (
		match_controller == null
		or match_controller.game_layout == null
	):
		return

	# خانه‌ی زمین خود بازیکن
	var player_place: CardPlace3D = \
		match_controller.game_layout.get_board_place(
			match_controller.local_player_id,
			player_slot_id
		)

	if player_place != null:
		target_nodes_3d.append(player_place)

	# خانه‌ی متناظر Dealer
	var dealer_anchor: Marker3D = \
		match_controller.game_layout.get_dealer_anchor(
			dealer_slot_id
		)

	if dealer_anchor != null:
		target_nodes_3d.append(dealer_anchor)

	target_control = null
	target_padding = SLOT_SPOTLIGHT_SIZE

	if (
		match_controller != null
		and match_controller.balance_scale != null
	):
		target_nodes_3d.append(
			match_controller.balance_scale
		)

	target_control = null
	target_padding = SCALE_SPOTLIGHT_SIZE

func _focus_middle_player_and_dealer() -> void:
	target_nodes_3d.clear()

	if (
		match_controller == null
		or match_controller.game_layout == null
	):
		return

	# دو خانه‌ی جلوی وسط خود بازیکن
	for player_slot_id: int in [
		SlotID.Type.FRONT_MIDDLE_0,
		SlotID.Type.FRONT_MIDDLE_1
	]:
		var player_place: CardPlace3D = \
			match_controller.game_layout.get_board_place(
				match_controller.local_player_id,
				player_slot_id
			)

		if player_place != null:
			target_nodes_3d.append(
				player_place
			)

	# دو خانه‌ی وسط Dealer
	for dealer_slot_id: int in [
		DealerSlotID.Type.MIDDLE_0,
		DealerSlotID.Type.MIDDLE_1
	]:
		var dealer_anchor: Marker3D = \
			match_controller.game_layout.get_dealer_anchor(
				dealer_slot_id
			)

		if dealer_anchor != null:
			target_nodes_3d.append(
				dealer_anchor
			)

	target_control = null
	target_padding = SLOT_SPOTLIGHT_SIZE

func _process(delta: float) -> void:
	if not active or overlay_root == null:
		return
	pulse_time += delta

	if feedback_time > 0.0:
		feedback_time -= delta
		if feedback_time <= 0.0:
			message_label.text = normal_message

	_update_spotlight()


func _update_spotlight() -> void:
	var rect := Rect2()
	var has_rect: bool = false

	if target_control != null and is_instance_valid(target_control) and target_control.is_visible_in_tree():
		rect = target_control.get_global_rect().grow(12.0)
		has_rect = true
	elif not target_nodes_3d.is_empty() and match_controller != null and match_controller.camera_3d != null:
		var camera: Camera3D = match_controller.camera_3d
		for node: Node3D in target_nodes_3d:
			if node == null or not is_instance_valid(node):
				continue
			if camera.is_position_behind(node.global_position):
				continue
			var screen_pos: Vector2 = camera.unproject_position(node.global_position)
			var size := target_padding
			if size == Vector2.ZERO:
				size = SLOT_SPOTLIGHT_SIZE
			var node_rect := Rect2(screen_pos - size * 0.5, size)
			if not has_rect:
				rect = node_rect
				has_rect = true
			else:
				rect = rect.merge(node_rect)

	var viewport_rect := get_viewport().get_visible_rect()
	if not has_rect:
		_hide_focus()
		_position_dialogue(viewport_rect.size, Rect2(), false)
		return
	rect = rect.intersection(viewport_rect)
	if rect.size.x <= 2.0 or rect.size.y <= 2.0:
		_hide_focus()
		return

	var pulse := 4.0 + sin(pulse_time * 5.0) * 3.0
	var focus_rect := rect.grow(pulse)
	_position_dialogue(viewport_rect.size, focus_rect, true)
	focus_border.visible = true
	focus_border.position = focus_rect.position
	focus_border.size = focus_rect.size

	# Four rectangles dim everything except the live focus rectangle. They do
	# not consume mouse/touch input, so the actual Card3D/slot stays interactive.
	var vp_size := viewport_rect.size
	dim_top.visible = true
	dim_bottom.visible = true
	dim_left.visible = true
	dim_right.visible = true

	dim_top.position = Vector2.ZERO
	dim_top.size = Vector2(vp_size.x, maxf(0.0, focus_rect.position.y))

	dim_bottom.position = Vector2(0.0, focus_rect.end.y)
	dim_bottom.size = Vector2(vp_size.x, maxf(0.0, vp_size.y - focus_rect.end.y))

	dim_left.position = Vector2(0.0, focus_rect.position.y)
	dim_left.size = Vector2(maxf(0.0, focus_rect.position.x), focus_rect.size.y)

	dim_right.position = Vector2(focus_rect.end.x, focus_rect.position.y)
	dim_right.size = Vector2(maxf(0.0, vp_size.x - focus_rect.end.x), focus_rect.size.y)

	if pointer_label.visible:
		var pointer_x := clampf(focus_rect.get_center().x - 28.0, 8.0, vp_size.x - 64.0)
		var pointer_y := clampf(focus_rect.position.y - 62.0 + sin(pulse_time * 4.0) * 8.0, 8.0, vp_size.y - 70.0)
		pointer_label.position = Vector2(pointer_x, pointer_y)


func _position_dialogue(
	viewport_size: Vector2,
	focus_rect: Rect2,
	has_focus: bool
) -> void:
	if dialogue_panel == null:
		return

	var panel_width: float = clampf(
		viewport_size.x * 0.46,
		460.0,
		600.0
	)

	var panel_height: float = clampf(
		viewport_size.y * 0.36,
		470.0,
		640.0
	)

	panel_width = minf(
		panel_width,
		viewport_size.x - 32.0
	)

	panel_height = minf(
		panel_height,
		viewport_size.y - 80.0
	)

	var margin: float = 20.0
	var x: float = (
		viewport_size.x
		- panel_width
		- margin
	)

	if (
		has_focus
		and focus_rect.get_center().x
		> viewport_size.x * 0.55
	):
		x = margin

	# Keep the speech panel away from the player's hand.
	var y: float = clampf(
		viewport_size.y * 0.14,
		24.0,
		viewport_size.y
		- panel_height
		- 24.0
	)

	dialogue_panel.position = Vector2(x, y)
	dialogue_panel.size = Vector2(
		panel_width,
		panel_height
	)

	# Animated demon sits centered under the dialogue box.
	if guide_sprite != null:
		var demon_width: float = panel_width * 0.48
		var demon_height: float = (
			demon_width
			* GUIDE_FRAME_SIZE.y
			/ GUIDE_FRAME_SIZE.x
		)

		guide_sprite.scale = Vector2(
			demon_width / GUIDE_FRAME_SIZE.x,
			demon_height / GUIDE_FRAME_SIZE.y
		)

		guide_sprite.position = Vector2(
			x
			+ (panel_width - demon_width) * 0.5,
			y + panel_height - 30.0
		)


func _hide_focus() -> void:
	if focus_border == null:
		return
	focus_border.visible = false
	dim_top.visible = false
	dim_bottom.visible = false
	dim_left.visible = false
	dim_right.visible = false


func _show_card_preview(instance_id: int) -> void:
	if card_preview_texture == null or card_preview_panel == null:
		return

	var view: Card3D = _card_view(instance_id)
	if view == null or view.card_instance == null:
		_hide_card_preview()
		return
	if view.card_instance.definition == null:
		_hide_card_preview()
		return

	var texture: Texture2D = view.card_instance.definition.front_texture
	if texture == null:
		_hide_card_preview()
		return

	card_preview_texture.texture = texture
	card_preview_panel.visible = true
	card_preview_texture.visible = true


func _hide_card_preview() -> void:
	if card_preview_panel != null:
		card_preview_panel.visible = false
	if card_preview_texture != null:
		card_preview_texture.visible = false


func _build_ui() -> void:
	overlay_root = Control.new()
	overlay_root.name = "TutorialOverlay"
	overlay_root.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	overlay_root.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	add_child(overlay_root)

	var dim_color := Color(
		0.035,
		0.02,
		0.065,
		0.62
	)

	for index: int in range(4):
		var rect := ColorRect.new()
		rect.color = dim_color
		rect.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE
		)
		rect.visible = false
		overlay_root.add_child(rect)

		match index:
			0:
				dim_top = rect
			1:
				dim_bottom = rect
			2:
				dim_left = rect
			3:
				dim_right = rect

	# -------------------------------------------------
	# Animated Demon Guide - Sprite Frames
	# -------------------------------------------------
	guide_sprite = AnimatedSprite2D.new()
	guide_sprite.name = "GuideSprite"
	guide_sprite.centered = false

	var guide_frames := SpriteFrames.new()
	guide_frames.set_animation_speed(
		&"default",
		GUIDE_FRAME_FPS
	)
	guide_frames.set_animation_loop(
		&"default",
		true
	)

	for frame_index: int in range(
		1,
		GUIDE_FRAME_COUNT + 1
	):
		var frame_path: String = (
			GUIDE_FRAME_DIR
			+ "/frame_%04d.png" % frame_index
		)

		if not ResourceLoader.exists(frame_path):
			push_error(
				"Tutorial demon frame missing: "
				+ frame_path
			)
			continue

		var frame_texture := load(
			frame_path
		) as Texture2D

		if frame_texture != null:
			guide_frames.add_frame(
				&"default",
				frame_texture
			)

	guide_sprite.sprite_frames = guide_frames
	guide_sprite.animation = &"default"
	guide_sprite.play()

	# Add before Dialogue so the dialogue box can render above it.
	overlay_root.add_child(
		guide_sprite
	)

	# -------------------------------------------------
	# Spotlight
	# -------------------------------------------------
	focus_border = Panel.new()
	focus_border.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	focus_border.visible = false

	var focus_style := StyleBoxFlat.new()
	focus_style.bg_color = Color(
		1.0,
		0.8,
		0.18,
		0.04
	)
	focus_style.border_color = Color(
		1.0,
		0.77,
		0.18,
		0.98
	)
	focus_style.set_border_width_all(4)
	focus_style.set_corner_radius_all(16)

	focus_border.add_theme_stylebox_override(
		"panel",
		focus_style
	)

	overlay_root.add_child(
		focus_border
	)

	# -------------------------------------------------
	# Large card preview
	# -------------------------------------------------
	card_preview_panel = Panel.new()
	card_preview_panel.name = "CardPreview"
	card_preview_panel.anchor_left = 0.32
	card_preview_panel.anchor_right = 0.60
	card_preview_panel.anchor_top = 0.07
	card_preview_panel.anchor_bottom = 0.83
	card_preview_panel.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	card_preview_panel.visible = false

	var preview_style := StyleBoxFlat.new()
	preview_style.bg_color = Color(
		0.0,
		0.0,
		0.0,
		0.0
	)
	preview_style.border_color = Color(
		0.0,
		0.0,
		0.0,
		0.0
	)
	preview_style.set_border_width_all(0)
	preview_style.set_corner_radius_all(12)

	card_preview_panel.add_theme_stylebox_override(
		"panel",
		preview_style
	)

	overlay_root.add_child(
		card_preview_panel
	)

	card_preview_texture = TextureRect.new()
	card_preview_texture.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	card_preview_texture.offset_left = 8.0
	card_preview_texture.offset_top = 8.0
	card_preview_texture.offset_right = -8.0
	card_preview_texture.offset_bottom = -8.0
	card_preview_texture.expand_mode = (
		TextureRect.EXPAND_IGNORE_SIZE
	)
	card_preview_texture.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)
	card_preview_texture.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	card_preview_texture.visible = false

	card_preview_panel.add_child(
		card_preview_texture
	)

	# -------------------------------------------------
	# Pointer
	# -------------------------------------------------
	pointer_label = Label.new()
	pointer_label.text = "▼"
	pointer_label.add_theme_font_size_override(
		"font_size",
		42
	)
	pointer_label.add_theme_color_override(
		"font_color",
		Color(
			1.0,
			0.79,
			0.2
		)
	)
	pointer_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	pointer_label.visible = false
	pointer_label.size = Vector2(
		64.0,
		58.0
	)
	pointer_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	overlay_root.add_child(
		pointer_label
	)

	# -------------------------------------------------
	# Dialogue panel
	# این بعد از GuideComposite اضافه می‌شود،
	# پس باکس روی دیو رسم می‌شود.
	# -------------------------------------------------
	dialogue_panel = Panel.new()
	dialogue_panel.name = "Dialogue"
	dialogue_panel.anchor_left = 0.0
	dialogue_panel.anchor_right = 0.0
	dialogue_panel.anchor_top = 0.0
	dialogue_panel.anchor_bottom = 0.0
	dialogue_panel.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	var dialogue_style := StyleBoxFlat.new()
	dialogue_style.bg_color = Color(
		0.965,
		0.925,
		0.79,
		0.98
	)
	dialogue_style.border_color = Color(
		0.30,
		0.16,
		0.12,
		0.98
	)
	dialogue_style.set_border_width_all(4)
	dialogue_style.set_corner_radius_all(18)

	dialogue_panel.add_theme_stylebox_override(
		"panel",
		dialogue_style
	)

	overlay_root.add_child(
		dialogue_panel
	)

	# -------------------------------------------------
	# Title
	# -------------------------------------------------
	title_label = Label.new()
	title_label.anchor_left = 0.19
	title_label.anchor_right = 0.95
	title_label.anchor_top = 0.09
	title_label.anchor_bottom = 0.27
	title_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	title_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)
	title_label.add_theme_font_size_override(
		"font_size",
		25
	)
	title_label.add_theme_color_override(
		"font_color",
		Color(
			0.29,
			0.13,
			0.10
		)
	)
	title_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	title_label.visible = false

	dialogue_panel.add_child(
		title_label
	)

	# -------------------------------------------------
	# Main dialogue text
	# -------------------------------------------------
	message_label = Label.new()
	message_label.anchor_left = 0.08
	message_label.anchor_right = 0.95
	message_label.anchor_top = 0.10
	message_label.anchor_bottom = 0.73
	message_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	message_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_TOP
	)
	message_label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)
	message_label.add_theme_font_size_override(
		"font_size",
		30
	)
	message_label.text_direction = (
		Control.TEXT_DIRECTION_RTL
	)
	message_label.add_theme_color_override(
		"font_color",
		Color(
			0.20,
			0.105,
			0.085
		)
	)
	message_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	dialogue_panel.add_child(
		message_label
	)

	# -------------------------------------------------
	# Instruction
	# -------------------------------------------------
	instruction_label = Label.new()
	instruction_label.anchor_left = 0.19
	instruction_label.anchor_right = 0.67
	instruction_label.anchor_top = 0.72
	instruction_label.anchor_bottom = 0.94
	instruction_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	instruction_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)
	instruction_label.add_theme_font_size_override(
		"font_size",
		17
	)
	instruction_label.add_theme_color_override(
		"font_color",
		Color(
			0.43,
			0.20,
			0.10
		)
	)
	instruction_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	dialogue_panel.add_child(
		instruction_label
	)

	# -------------------------------------------------
	# Continue button
	# -------------------------------------------------
	continue_button = Button.new()
	continue_button.anchor_left = 0.72
	continue_button.anchor_right = 0.95
	continue_button.anchor_top = 0.72
	continue_button.anchor_bottom = 0.92
	continue_button.mouse_filter = (
		Control.MOUSE_FILTER_STOP
	)
	continue_button.add_theme_font_size_override(
		"font_size",
		18
	)
	continue_button.pressed.connect(
		_on_continue_pressed
	)

	dialogue_panel.add_child(
		continue_button
	)

	# -------------------------------------------------
	# Progress
	# -------------------------------------------------
	progress_label = Label.new()
	progress_label.anchor_left = 0.02
	progress_label.anchor_right = 0.18
	progress_label.anchor_top = 0.02
	progress_label.anchor_bottom = 0.10
	progress_label.add_theme_font_size_override(
		"font_size",
		14
	)
	progress_label.add_theme_color_override(
		"font_color",
		Color(
			0.35,
			0.20,
			0.14
		)
	)
	progress_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	progress_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	progress_label.visible = false

	dialogue_panel.add_child(
		progress_label
	)

	# -------------------------------------------------
	# Skip tutorial button
	# -------------------------------------------------
	skip_button = Button.new()
	skip_button.text = "رد کردن آموزش"
	skip_button.anchor_left = 0.82
	skip_button.anchor_right = 0.98
	skip_button.anchor_top = 0.02
	skip_button.anchor_bottom = 0.075
	skip_button.mouse_filter = (
		Control.MOUSE_FILTER_STOP
	)
	skip_button.pressed.connect(skip)

	overlay_root.add_child(
		skip_button
	)
