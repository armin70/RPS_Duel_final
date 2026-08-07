class_name BotController
extends RefCounted


const MAX_ACTIONS_PER_TURN: int = 12
const MIN_COLLECTOR_TARGETS: int = 2
const BOARD_MOVE_MANA_COST: int = 1
const INVALID_SCORE: float = -1000000.0
const HARDCORE_SETTING: StringName = &"gameplay/hardcore_bot"


var random := RandomNumberGenerator.new()


func _init() -> void:
	random.randomize()


# حالت پیش‌فرض Fair است. منوی Hardcore فقط همین Setting را True می‌کند.
func set_hardcore_mode(enabled: bool) -> void:
	ProjectSettings.set_setting(
		HARDCORE_SETTING,
		enabled
	)


func is_hardcore_mode() -> bool:
	return bool(
		ProjectSettings.get_setting(
			HARDCORE_SETTING,
			false
		)
	)


# در حالت Fair فقط کارت‌هایی که در Turnهای قبلی قرار گرفته‌اند
# قابل بررسی‌اند؛ کارت‌های Turn جاری هنوز Face-down هستند.
func _can_inspect_opponent_card(
	state: MatchState,
	card: CardInstance
) -> bool:
	if state == null or card == null:
		return false

	if is_hardcore_mode():
		return true

	return card.turn_played < state.turn_number


func _get_visible_opponent_card(
	state: MatchState,
	opponent: PlayerState,
	slot_id: int
) -> CardInstance:
	if state == null or opponent == null:
		return null

	var card: CardInstance = opponent.board.get_card(
		slot_id
	)

	if not _can_inspect_opponent_card(state, card):
		return null

	return card


# نسخه دید ربات از Disable است. در حالت Fair، Disabler مخفیِ
# بازیکن وارد تصمیم‌گیری ربات نمی‌شود. در Hardcore رفتار قبلی حفظ می‌شود.
func _is_card_disabled_for_bot_view(
	state: MatchState,
	bot: PlayerState,
	target_owner_id: int,
	target_slot_id: int,
	target_card: CardInstance
) -> bool:
	if state == null or bot == null:
		return false

	if target_card == null or target_card.definition == null:
		return false

	if not SlotID.is_valid(target_slot_id):
		return false

	var source_owner_id: int = (
		2 if target_owner_id == 1 else 1
	)

	var source_player: PlayerState = state.get_player(
		source_owner_id
	)

	if source_player == null:
		return false

	for source_slot_id: int in SlotID.all_slots():
		var source_card: CardInstance = \
			source_player.board.get_card(
				source_slot_id
			)

		if source_card == null:
			continue

		# کارت‌های خود ربات همیشه برای خودش معلوم‌اند.
		# کارت‌های طرف مقابل فقط پس از Reveal بررسی می‌شوند.
		if source_owner_id != bot.player_id:
			if not _can_inspect_opponent_card(
				state,
				source_card
			):
				continue

		if source_card.definition == null:
			continue

		var behavior := (
			source_card.definition.behavior
			as DisableGestureBehavior
		)

		if behavior == null:
			continue

		if behavior.disables_target(
			source_slot_id,
			target_slot_id,
			target_card
		):
			return true

	return false


func play_turn(
	engine: MatchEngine,
	bot_player_id: int
) -> void:
	if engine == null or engine.state == null:
		return

	var state: MatchState = engine.state

	if state.phase != MatchPhase.Type.MAIN:
		return

	var bot: PlayerState = state.get_player(
		bot_player_id
	)

	if bot == null or bot.is_ready:
		return

	var opponent_id: int = (
		2 if bot_player_id == 1 else 1
	)

	var opponent: PlayerState = state.get_player(
		opponent_id
	)

	if opponent == null:
		return

	var completed_actions: int = 0

	print(
		"BOT DIFFICULTY | ",
		"HARDCORE" if is_hardcore_mode() else "FAIR"
	)

	# اول کارت Disableشده را واقعاً از خطر خارج می‌کنیم.
	# ترتیب دفاعی:
	# 1) انتقال به Lane امن
	# 2) Cover کردن و فرستادن کارت Disableشده به Reserve
	# 3) پاک‌کردن Lane با Bomb
	if _try_reposition_disabled_card(
		engine,
		state,
		bot,
		opponent
	):
		completed_actions += 1

	if _try_replace_disabled_card(
		engine,
		state,
		bot,
		opponent
	):
		completed_actions += 1
	elif _try_bomb_disabled_lane(
		engine,
		state,
		bot,
		opponent
	):
		completed_actions += 1

	var blocked_candidates: Dictionary = {}

	while completed_actions < MAX_ACTIONS_PER_TURN:
		var best_candidate: Dictionary = \
			_find_best_play_candidate(
				state,
				bot,
				opponent,
				blocked_candidates
			)

		if best_candidate.is_empty():
			break

		var card: CardInstance = \
			best_candidate.get(
				"card",
				null
			) as CardInstance

		var slot_id: int = int(
			best_candidate.get(
				"slot_id",
				-1
			)
		)

		if card == null or not SlotID.is_valid(slot_id):
			break

		var candidate_key: String = \
			_get_candidate_key(
				card,
				slot_id
			)

		var success: bool = engine.play_card(
			bot.player_id,
			card,
			slot_id
		)

		if not success:
			# یک انتخاب نامعتبر نباید کل Turn ربات را متوقف کند.
			blocked_candidates[candidate_key] = true
			continue

		completed_actions += 1
		blocked_candidates.clear()

		print(
			"BOT SMART PLAY | card=",
			card.definition.display_name,
			" | slot=",
			slot_id,
			" | score=",
			best_candidate.get("score", 0.0),
			" | mana_left=",
			bot.current_mana
		)


func _find_best_play_candidate(
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState,
	blocked_candidates: Dictionary
) -> Dictionary:
	var best_candidate: Dictionary = {}
	var best_score: float = INVALID_SCORE

	for card: CardInstance in bot.hand:
		if card == null or card.definition == null:
			continue

		if card.definition.mana_cost > bot.current_mana:
			continue

		# Collector فقط وقتی استفاده می‌شود که حداقل دو کارت
		# مناسب برای جمع‌کردن روی Board وجود داشته باشد.
		var collector := \
			card.definition.behavior as CollectorBehavior

		if collector != null:
			var collector_targets: int = \
				_count_collector_targets(
					state,
					bot,
					card,
					collector
				)

			if collector_targets < MIN_COLLECTOR_TARGETS:
				continue

		for slot_id: int in SlotID.all_slots():
			var candidate_key: String = \
				_get_candidate_key(
					card,
					slot_id
				)

			if blocked_candidates.has(candidate_key):
				continue

			if not _is_legal_play_candidate(
				state,
				bot,
				card,
				slot_id
			):
				continue

			# Disabler فقط وقتی Candidate محسوب می‌شود که:
			# - واقعاً حداقل یک کارت حریف را Match کند؛
			# - آن کارت از قبل Disable نشده باشد؛
			# - Disable شدنش جلوی یک Win واقعی را بگیرد.
			var disabler := \
				card.definition.behavior \
				as DisableGestureBehavior

			if disabler != null:
				if not _is_useful_disabler_placement(
					state,
					bot,
					opponent,
					disabler,
					slot_id
				):
					continue

			var score: float = \
				_score_play_candidate(
					state,
					bot,
					opponent,
					card,
					slot_id
				)

			# اختلاف خیلی کوچک را کمی تصادفی می‌کنیم تا ربات
			# همیشه دقیقاً یک الگوی ثابت نداشته باشد.
			score += random.randf_range(
				-0.15,
				0.15
			)

			if score > best_score:
				best_score = score
				best_candidate = {
					"card": card,
					"slot_id": slot_id,
					"score": score
				}

	return best_candidate


func _is_legal_play_candidate(
	state: MatchState,
	bot: PlayerState,
	card: CardInstance,
	slot_id: int
) -> bool:
	if state == null or bot == null or card == null:
		return false

	if card.definition == null:
		return false

	if not SlotID.is_valid(slot_id):
		return false

	if card.definition.mana_cost > bot.current_mana:
		return false

	var required_front_slot: int = \
		_get_required_front_slot(slot_id)

	if (
		required_front_slot != -1
		and bot.board.get_card(required_front_slot) == null
	):
		return false

	var replaced_card: CardInstance = \
		bot.board.get_card(slot_id)

	if replaced_card == null:
		return true

	if replaced_card.definition == null:
		return false

	var turns_since_played: int = (
		state.turn_number
		- replaced_card.turn_played
	)

	if turns_since_played < 1:
		return false

	return CardGesture.can_cover(
		card.definition.gesture,
		replaced_card.definition.gesture
	)


func _score_play_candidate(
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState,
	card: CardInstance,
	slot_id: int
) -> float:
	var score: float = 0.0

	# خرج Mana مهم است، ولی نباید باعث شود ربات
	# کارت مفید را اصلاً بازی نکند.
	score -= float(card.definition.mana_cost) * 0.35

	# مبارزه با Player مقابل مهم‌تر از Dealer است.
	score += _score_against_opponent(
		state,
		bot,
		opponent,
		card,
		slot_id
	) * 2.6

	score += _score_against_dealer(
		state,
		bot,
		card,
		slot_id
	)

	score += _score_special_behavior(
		state,
		bot,
		opponent,
		card,
		slot_id
	)

	var replaced_card: CardInstance = \
		bot.board.get_card(slot_id)

	if replaced_card != null:
		score += _score_covering_own_card(
			state,
			bot,
			opponent,
			replaced_card,
			slot_id
		)

	return score


func _score_against_opponent(
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState,
	card: CardInstance,
	slot_id: int
) -> float:
	var score: float = 0.0
	var target_slots: Array[int] = \
		_get_opponent_target_slots(slot_id)

	for target_slot_id: int in target_slots:
		var target: CardInstance = \
			_get_visible_opponent_card(
				state,
				opponent,
				target_slot_id
			)

		if target == null or target.definition == null:
			continue

		var bot_outcome: int = _compare_gestures(
			card.definition.gesture,
			target.definition.gesture
		)

		# Credit Card در Turn ورود Scissors را می‌برد.
		if (
			card.definition.behavior is CreditCardBehavior
			and target.definition.gesture
			== CardGesture.Type.SCISSORS
		):
			bot_outcome = BattleAct.Outcome.WIN

		var opponent_outcome: int = \
			_opposite_outcome(bot_outcome)

		var bot_disabled: bool = \
			_is_card_disabled_for_bot_view(
				state,
				bot,
				bot.player_id,
				slot_id,
				card
			)

		var opponent_disabled: bool = \
			_is_card_disabled_for_bot_view(
				state,
				bot,
				opponent.player_id,
				target_slot_id,
				target
			)

		var new_disabler := \
			card.definition.behavior \
			as DisableGestureBehavior

		if (
			new_disabler != null
			and new_disabler.disables_target(
				slot_id,
				target_slot_id,
				target
			)
		):
			opponent_disabled = true

		if (
			bot_disabled
			and bot_outcome == BattleAct.Outcome.WIN
		):
			bot_outcome = BattleAct.Outcome.TIE
			opponent_outcome = BattleAct.Outcome.TIE

		if (
			opponent_disabled
			and opponent_outcome
			== BattleAct.Outcome.WIN
		):
			bot_outcome = BattleAct.Outcome.TIE
			opponent_outcome = BattleAct.Outcome.TIE

		score += _outcome_value(bot_outcome)
		score -= _outcome_value(opponent_outcome) * 0.75

		# Killer باید مهم‌ترین کارت حریف را هدف بگیرد.
		if (
			card.definition.behavior is KillerBehavior
			and bot_outcome == BattleAct.Outcome.WIN
		):
			score += 10.0
			score += _card_importance(target) * 2.2

	return score


func _score_against_dealer(
	state: MatchState,
	bot: PlayerState,
	card: CardInstance,
	slot_id: int
) -> float:
	if state == null or state.dealer == null:
		return 0.0

	var target_slots: Array[int] = \
		_get_dealer_target_slots(
			state,
			bot,
			card,
			slot_id
		)

	var score: float = 0.0
	var bot_disabled: bool = \
		_is_card_disabled_for_bot_view(
			state,
			bot,
			bot.player_id,
			slot_id,
			card
		)

	for dealer_slot_id: int in target_slots:
		var dealer_card: CardInstance = \
			state.dealer.slots.get(
				dealer_slot_id,
				null
			) as CardInstance

		if dealer_card == null:
			continue

		if dealer_card.definition == null:
			continue

		var outcome: int = _compare_gestures(
			card.definition.gesture,
			dealer_card.definition.gesture
		)

		if card.definition.behavior is MustacheRockBehavior:
			if _count_other_rocks_for_view(state, bot, bot, card) >= 2:
				outcome = BattleAct.Outcome.WIN

		elif card.definition.behavior is ChainsawBehavior:
			if (
				dealer_card.definition.gesture
				!= CardGesture.Type.ROCK
			):
				outcome = BattleAct.Outcome.WIN

		elif card.definition.behavior is CreditCardBehavior:
			if (
				dealer_card.definition.gesture
				== CardGesture.Type.SCISSORS
			):
				outcome = BattleAct.Outcome.WIN

		if (
			bot_disabled
			and outcome == BattleAct.Outcome.WIN
		):
			outcome = BattleAct.Outcome.TIE

		match outcome:
			BattleAct.Outcome.WIN:
				score += 5.0

			BattleAct.Outcome.TIE:
				score += 1.25

			BattleAct.Outcome.LOSS:
				score -= 3.5

	return score


func _score_special_behavior(
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState,
	card: CardInstance,
	slot_id: int
) -> float:
	var behavior: CardBehavior = card.definition.behavior

	if behavior == null:
		return 0.0

	if behavior is CollectorBehavior:
		var collector := behavior as CollectorBehavior
		var target_count: int = \
			_count_collector_targets(
				state,
				bot,
				card,
				collector
			)

		return float(target_count) * 14.0

	if behavior is DisableGestureBehavior:
		return _score_disabler_placement(
			state,
			bot,
			opponent,
			behavior as DisableGestureBehavior,
			slot_id
		)

	if behavior is DiscardLaneDrawBehavior:
		return _score_demolisher_placement(
			state,
			bot,
			opponent,
			card,
			slot_id
		)

	if behavior is MustacheRockBehavior:
		var other_rocks: int = \
			_count_other_rocks_for_view(state, bot, bot, card)

		if other_rocks >= 2:
			return 30.0

		return -18.0

	if behavior is ChainsawBehavior:
		var non_rock_dealers: int = 0

		for dealer_slot_id: int in DealerSlotID.all_slots():
			var dealer_card: CardInstance = \
				state.dealer.slots.get(
					dealer_slot_id,
					null
				) as CardInstance

			if dealer_card == null:
				continue

			if dealer_card.definition == null:
				continue

			if (
				dealer_card.definition.gesture
				!= CardGesture.Type.ROCK
			):
				non_rock_dealers += 1

		return float(non_rock_dealers) * 5.0

	if behavior is FrontShieldBehavior:
		if SlotID.get_row(slot_id) != SlotID.Row.BACK:
			return -8.0

		var front_slot_id: int = \
			_get_required_front_slot(slot_id)

		var protected_card: CardInstance = \
			bot.board.get_card(front_slot_id)

		if protected_card == null:
			return -8.0

		return 6.0 + _card_importance(
			protected_card
		) * 0.5

	if behavior is DefenseBehavior:
		return 7.0

	return 0.0


func _score_disabler_placement(
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState,
	behavior: DisableGestureBehavior,
	slot_id: int
) -> float:
	var score: float = 0.0
	var newly_disabled_count: int = 0
	var useful_target_count: int = 0

	for target_slot_id: int in SlotID.all_slots():
		var target: CardInstance = \
			_get_visible_opponent_card(
				state,
				opponent,
				target_slot_id
			)

		if target == null or target.definition == null:
			continue

		# این شرط دقیقاً بررسی می‌کند که Gesture و Lane
		# کارت حریف با Disabler هماهنگ است یا نه.
		if not behavior.disables_target(
			slot_id,
			target_slot_id,
			target
		):
			continue

		# روی کارت از قبل Disableشده دوباره Disabler نریز.
		if _is_card_disabled_for_bot_view(
			state,
			bot,
			opponent.player_id,
			target_slot_id,
			target
		):
			continue

		newly_disabled_count += 1

		if not _target_has_a_real_win(
			state,
			bot,
			opponent,
			target,
			target_slot_id
		):
			continue

		useful_target_count += 1
		score += 24.0
		score += _card_importance(target) * 1.25

	if newly_disabled_count == 0:
		return INVALID_SCORE

	if useful_target_count == 0:
		return INVALID_SCORE

	return score


func _score_demolisher_placement(
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState,
	source_card: CardInstance,
	slot_id: int
) -> float:
	var score: float = 0.0
	var removed_count: int = 0
	var lane: SlotID.Lane = SlotID.get_lane(slot_id)

	for target_slot_id: int in SlotID.all_slots():
		if SlotID.get_lane(target_slot_id) != lane:
			continue

		var target: CardInstance = \
			bot.board.get_card(target_slot_id)

		if target == null:
			continue

		removed_count += 1

		var danger: float = _card_danger_score(
			state,
			bot,
			opponent,
			target,
			target_slot_id
		)

		# کارت‌های ضعیف، Disableشده یا در حال باخت
		# گزینه‌های خوبی برای خالی‌کردن Lane هستند.
		score += danger * 1.5
		score -= _card_importance(target) * 0.55

	# اگر روی کارت دیگری Cover شود، همان کارت هم حذف می‌شود.
	if bot.board.get_card(slot_id) != null:
		score += 5.0

	if removed_count == 0:
		return -20.0

	# Draw جایگزین ارزش اضافی دارد.
	score += float(removed_count) * 4.0

	return score


func _score_covering_own_card(
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState,
	replaced_card: CardInstance,
	slot_id: int
) -> float:
	var score: float = 0.0

	score += _card_danger_score(
		state,
		bot,
		opponent,
		replaced_card,
		slot_id
	) * 1.7

	score -= _card_importance(replaced_card) * 0.8

	if _get_empty_legal_slot_count(bot) == 0:
		score += 10.0

	return score


func _try_reposition_disabled_card(
	engine: MatchEngine,
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState
) -> bool:
	if bot.current_mana < BOARD_MOVE_MANA_COST:
		return false

	if bot.board_move_used_turn == state.turn_number:
		return false

	var best_from: int = -1
	var best_to: int = -1
	var best_improvement: float = INVALID_SCORE

	for from_slot_id: int in SlotID.all_slots():
		var moving_card: CardInstance = \
			bot.board.get_card(from_slot_id)

		if moving_card == null or moving_card.definition == null:
			continue

		if not _is_card_disabled_for_bot_view(
			state,
			bot,
			bot.player_id,
			from_slot_id,
			moving_card
		):
			continue

		var current_score: float = \
			_score_existing_card_position(
				state,
				bot,
				opponent,
				moving_card,
				from_slot_id
			)

		for to_slot_id: int in SlotID.all_slots():
			if not _is_legal_move_candidate(
				state,
				bot,
				moving_card,
				from_slot_id,
				to_slot_id
			):
				continue

			# مقصد باید واقعاً از Disabler حریف امن باشد.
			if _is_card_disabled_for_bot_view(
				state,
				bot,
				bot.player_id,
				to_slot_id,
				moving_card
			):
				continue

			var destination_score: float = \
				_score_existing_card_position(
					state,
					bot,
					opponent,
					moving_card,
					to_slot_id
				)

			# فرار از Disable همیشه اولویت اصلی دارد.
			var improvement: float = (
				destination_score
				- current_score
				+ 100.0
			)

			var replaced: CardInstance = \
				bot.board.get_card(to_slot_id)

			if replaced != null:
				improvement += _card_danger_score(
					state,
					bot,
					opponent,
					replaced,
					to_slot_id
				)
				improvement -= _card_importance(
					replaced
				) * 0.6

			if improvement > best_improvement:
				best_improvement = improvement
				best_from = from_slot_id
				best_to = to_slot_id

	if best_from == -1 or best_to == -1:
		return false

	var moved: bool = engine.move_board_card(
		bot.player_id,
		best_from,
		best_to
	)

	if moved:
		print(
			"BOT ESCAPED DISABLER | from=",
			best_from,
			" | to=",
			best_to,
			" | improvement=",
			best_improvement
		)

	return moved


func _try_replace_disabled_card(
	engine: MatchEngine,
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState
) -> bool:
	var best_card: CardInstance = null
	var best_slot_id: int = -1
	var best_score: float = INVALID_SCORE

	for target_slot_id: int in SlotID.all_slots():
		var disabled_card: CardInstance = \
			bot.board.get_card(target_slot_id)

		if disabled_card == null or disabled_card.definition == null:
			continue

		if not _is_card_disabled_for_bot_view(
			state,
			bot,
			bot.player_id,
			target_slot_id,
			disabled_card
		):
			continue

		for hand_card: CardInstance in bot.hand:
			if hand_card == null or hand_card.definition == null:
				continue

			if not _is_legal_play_candidate(
				state,
				bot,
				hand_card,
				target_slot_id
			):
				continue

			# کارت جایگزین نباید در همان Slot دوباره Disable شود.
			if _is_card_disabled_for_bot_view(
				state,
				bot,
				bot.player_id,
				target_slot_id,
				hand_card
			):
				continue

			# حتی هنگام Cover دفاعی هم Disabler بی‌هدف مصرف نشود.
			var replacement_disabler := \
				hand_card.definition.behavior \
				as DisableGestureBehavior

			if replacement_disabler != null:
				if not _is_useful_disabler_placement(
					state,
					bot,
					opponent,
					replacement_disabler,
					target_slot_id
				):
					continue

			var candidate_score: float = 80.0
			candidate_score += _card_danger_score(
				state,
				bot,
				opponent,
				disabled_card,
				target_slot_id
			) * 2.0
			candidate_score += _score_play_candidate(
				state,
				bot,
				opponent,
				hand_card,
				target_slot_id
			)

			if candidate_score > best_score:
				best_score = candidate_score
				best_card = hand_card
				best_slot_id = target_slot_id

	if best_card == null or best_slot_id == -1:
		return false

	var replaced: bool = engine.play_card(
		bot.player_id,
		best_card,
		best_slot_id
	)

	if replaced:
		print(
			"BOT DISCARDED DISABLED CARD BY COVER | slot=",
			best_slot_id,
			" | replacement=",
			best_card.definition.display_name
		)

	return replaced


func _try_bomb_disabled_lane(
	engine: MatchEngine,
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState
) -> bool:
	var disabled_lanes: Dictionary = {}

	for slot_id: int in SlotID.all_slots():
		var board_card: CardInstance = \
			bot.board.get_card(slot_id)

		if board_card == null or board_card.definition == null:
			continue

		if _is_card_disabled_for_bot_view(
			state,
			bot,
			bot.player_id,
			slot_id,
			board_card
		):
			disabled_lanes[SlotID.get_lane(slot_id)] = true

	if disabled_lanes.is_empty():
		return false

	var best_bomb: CardInstance = null
	var best_slot_id: int = -1
	var best_score: float = INVALID_SCORE

	for hand_card: CardInstance in bot.hand:
		if hand_card == null or hand_card.definition == null:
			continue

		if not (
			hand_card.definition.behavior
			is DiscardLaneDrawBehavior
		):
			continue

		for slot_id: int in SlotID.all_slots():
			var lane: SlotID.Lane = SlotID.get_lane(slot_id)

			if not disabled_lanes.has(lane):
				continue

			if not _is_legal_play_candidate(
				state,
				bot,
				hand_card,
				slot_id
			):
				continue

			var lane_score: float = 0.0
			var disabled_count: int = 0

			for lane_slot_id: int in SlotID.all_slots():
				if SlotID.get_lane(lane_slot_id) != lane:
					continue

				var lane_card: CardInstance = \
					bot.board.get_card(lane_slot_id)

				if lane_card == null:
					continue

				var is_disabled: bool = \
					_is_card_disabled_for_bot_view(
						state,
						bot,
						bot.player_id,
						lane_slot_id,
						lane_card
					)

				if is_disabled:
					disabled_count += 1
					lane_score += 45.0

				lane_score += _card_danger_score(
					state,
					bot,
					opponent,
					lane_card,
					lane_slot_id
				) * 1.5
				lane_score -= _card_importance(
					lane_card
				) * 0.75

			if disabled_count == 0:
				continue

			if lane_score > best_score:
				best_score = lane_score
				best_bomb = hand_card
				best_slot_id = slot_id

	if best_bomb == null or best_slot_id == -1:
		return false

	var bombed: bool = engine.play_card(
		bot.player_id,
		best_bomb,
		best_slot_id
	)

	if bombed:
		print(
			"BOT CLEARED DISABLED LANE WITH BOMB | slot=",
			best_slot_id,
			" | score=",
			best_score
		)

	return bombed


func _is_useful_disabler_placement(
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState,
	behavior: DisableGestureBehavior,
	slot_id: int
) -> bool:
	for target_slot_id: int in SlotID.all_slots():
		var target: CardInstance = \
			_get_visible_opponent_card(
				state,
				opponent,
				target_slot_id
			)

		if target == null or target.definition == null:
			continue

		if not behavior.disables_target(
			slot_id,
			target_slot_id,
			target
		):
			continue

		if _is_card_disabled_for_bot_view(
			state,
			bot,
			opponent.player_id,
			target_slot_id,
			target
		):
			continue

		if _target_has_a_real_win(
			state,
			bot,
			opponent,
			target,
			target_slot_id
		):
			return true

	return false


func _target_has_a_real_win(
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState,
	target: CardInstance,
	target_slot_id: int
) -> bool:
	# اول برخورد با کارت‌های Bot؛ این مهم‌تر از Dealer است.
	for bot_slot_id: int in _get_opponent_target_slots(
		target_slot_id
	):
		var bot_card: CardInstance = \
			bot.board.get_card(bot_slot_id)

		if bot_card == null or bot_card.definition == null:
			continue

		if _compare_gestures(
			target.definition.gesture,
			bot_card.definition.gesture
		) == BattleAct.Outcome.WIN:
			return true

	# بعد بررسی می‌کنیم کارت حریف از Dealer امتیاز Win می‌گیرد یا نه.
	for dealer_slot_id: int in _get_dealer_target_slots(
		state,
		opponent,
		target,
		target_slot_id
	):
		var dealer_card: CardInstance = \
			state.dealer.slots.get(
				dealer_slot_id,
				null
			) as CardInstance

		if dealer_card == null or dealer_card.definition == null:
			continue

		var outcome: int = _compare_gestures(
			target.definition.gesture,
			dealer_card.definition.gesture
		)

		if target.definition.behavior is CreditCardBehavior:
			if (
				dealer_card.definition.gesture
				== CardGesture.Type.SCISSORS
			):
				outcome = BattleAct.Outcome.WIN

		elif target.definition.behavior is ChainsawBehavior:
			if (
				dealer_card.definition.gesture
				!= CardGesture.Type.ROCK
			):
				outcome = BattleAct.Outcome.WIN

		elif target.definition.behavior is MustacheRockBehavior:
			if _count_other_rocks_for_view(state, bot, opponent, target) >= 2:
				outcome = BattleAct.Outcome.WIN

		if outcome == BattleAct.Outcome.WIN:
			return true

	return false


func _is_legal_move_candidate(
	state: MatchState,
	bot: PlayerState,
	moving_card: CardInstance,
	from_slot_id: int,
	to_slot_id: int
) -> bool:
	if from_slot_id == to_slot_id:
		return false

	if not SlotID.is_valid(from_slot_id):
		return false

	if not SlotID.is_valid(to_slot_id):
		return false

	var matching_back: int = \
		_get_matching_back_slot(from_slot_id)

	if (
		matching_back != -1
		and bot.board.get_card(matching_back) != null
	):
		return false

	var required_front: int = \
		_get_required_front_slot(to_slot_id)

	if required_front != -1:
		if from_slot_id == required_front:
			return false

		if bot.board.get_card(required_front) == null:
			return false

	var replaced: CardInstance = \
		bot.board.get_card(to_slot_id)

	if replaced == null:
		return true

	if replaced.definition == null:
		return false

	var turns_since_played: int = (
		state.turn_number
		- replaced.turn_played
	)

	if turns_since_played < 1:
		return false

	return CardGesture.can_cover(
		moving_card.definition.gesture,
		replaced.definition.gesture
	)


func _score_existing_card_position(
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState,
	card: CardInstance,
	slot_id: int
) -> float:
	var score: float = 0.0

	if _is_card_disabled_for_bot_view(
		state,
		bot,
		bot.player_id,
		slot_id,
		card
	):
		score -= 18.0

	score += _score_against_opponent(
		state,
		bot,
		opponent,
		card,
		slot_id
	) * 2.0

	score += _score_against_dealer(
		state,
		bot,
		card,
		slot_id
	)

	return score


func _card_danger_score(
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState,
	card: CardInstance,
	slot_id: int
) -> float:
	var danger: float = 0.0

	if _is_card_disabled_for_bot_view(
		state,
		bot,
		bot.player_id,
		slot_id,
		card
	):
		danger += 10.0

	var position_score: float = \
		_score_existing_card_position(
			state,
			bot,
			opponent,
			card,
			slot_id
		)

	if position_score < 0.0:
		danger += abs(position_score) * 0.5

	return danger


func _count_collector_targets(
	state: MatchState,
	bot: PlayerState,
	source_card: CardInstance,
	behavior: CollectorBehavior
) -> int:
	var count: int = 0

	for slot_id: int in SlotID.all_slots():
		var target: CardInstance = \
			bot.board.get_card(slot_id)

		if target == null or target == source_card:
			continue

		if target.definition == null:
			continue

		if target.turn_played >= state.turn_number:
			continue

		if (
			target.definition.gesture
			!= behavior.collected_gesture
		):
			continue

		count += 1

	return count


func _count_other_rocks_for_view(
	state: MatchState,
	bot: PlayerState,
	owner: PlayerState,
	source_card: CardInstance
) -> int:
	var count: int = 0

	if state == null or bot == null or owner == null:
		return count

	for slot_id: int in SlotID.all_slots():
		var card: CardInstance = \
			owner.board.get_card(slot_id)

		if card == null or card == source_card:
			continue

		if owner.player_id != bot.player_id:
			if not _can_inspect_opponent_card(state, card):
				continue

		if card.definition == null:
			continue

		if (
			card.definition.gesture
			== CardGesture.Type.ROCK
		):
			count += 1

	return count


func _card_importance(card: CardInstance) -> float:
	if card == null or card.definition == null:
		return 0.0

	var value: float = float(
		card.definition.mana_cost
	)

	var behavior: CardBehavior = \
		card.definition.behavior

	if behavior is DisableGestureBehavior:
		value += 8.0
	elif behavior is CollectorBehavior:
		value += 7.0
	elif behavior is KillerBehavior:
		value += 6.0
	elif behavior is MustacheRockBehavior:
		value += 7.0
	elif behavior is ChainsawBehavior:
		value += 7.0
	elif behavior is DefenseBehavior:
		value += 5.0
	elif behavior is FrontShieldBehavior:
		value += 4.0
	elif behavior is CreditCardBehavior:
		value += 4.0
	elif behavior is DiscardLaneDrawBehavior:
		value += 3.0

	if card.definition.gesture == CardGesture.Type.DIV:
		value += 12.0

	value += float(card.shield_count) * 2.0

	return value


func _get_opponent_target_slots(
	slot_id: int
) -> Array[int]:
	if SlotID.get_lane(slot_id) != SlotID.Lane.MIDDLE:
		return [slot_id]

	if SlotID.get_row(slot_id) == SlotID.Row.FRONT:
		return [
			SlotID.Type.FRONT_MIDDLE_0,
			SlotID.Type.FRONT_MIDDLE_1
		]

	return [
		SlotID.Type.BACK_MIDDLE_0,
		SlotID.Type.BACK_MIDDLE_1
	]


func _get_dealer_target_slots(
	state: MatchState,
	bot: PlayerState,
	card: CardInstance,
	slot_id: int
) -> Array[int]:
	var behavior: CardBehavior = \
		card.definition.behavior

	if behavior is ChainsawBehavior:
		return DealerSlotID.all_slots()

	if (
		behavior is MustacheRockBehavior
		and _count_other_rocks_for_view(state, bot, bot, card) >= 2
	):
		return DealerSlotID.all_slots()

	match slot_id:
		SlotID.Type.FRONT_LEFT, \
		SlotID.Type.BACK_LEFT:
			return [DealerSlotID.Type.LEFT]

		SlotID.Type.FRONT_RIGHT, \
		SlotID.Type.BACK_RIGHT:
			return [DealerSlotID.Type.RIGHT]

		_:
			return [
				DealerSlotID.Type.MIDDLE_0,
				DealerSlotID.Type.MIDDLE_1
			]


func _get_empty_legal_slot_count(
	bot: PlayerState
) -> int:
	var count: int = 0

	for slot_id: int in SlotID.all_slots():
		if not bot.board.is_slot_empty(slot_id):
			continue

		var required_front: int = \
			_get_required_front_slot(slot_id)

		if (
			required_front != -1
			and bot.board.get_card(required_front) == null
		):
			continue

		count += 1

	return count


func _get_required_front_slot(
	target_slot_id: int
) -> int:
	match target_slot_id:
		SlotID.Type.BACK_LEFT:
			return SlotID.Type.FRONT_LEFT

		SlotID.Type.BACK_MIDDLE_0:
			return SlotID.Type.FRONT_MIDDLE_0

		SlotID.Type.BACK_MIDDLE_1:
			return SlotID.Type.FRONT_MIDDLE_1

		SlotID.Type.BACK_RIGHT:
			return SlotID.Type.FRONT_RIGHT

	return -1


func _get_matching_back_slot(
	front_slot_id: int
) -> int:
	match front_slot_id:
		SlotID.Type.FRONT_LEFT:
			return SlotID.Type.BACK_LEFT

		SlotID.Type.FRONT_MIDDLE_0:
			return SlotID.Type.BACK_MIDDLE_0

		SlotID.Type.FRONT_MIDDLE_1:
			return SlotID.Type.BACK_MIDDLE_1

		SlotID.Type.FRONT_RIGHT:
			return SlotID.Type.BACK_RIGHT

	return -1


func _compare_gestures(
	attacker_gesture: CardGesture.Type,
	defender_gesture: CardGesture.Type
) -> int:
	if attacker_gesture == defender_gesture:
		return BattleAct.Outcome.TIE

	if attacker_gesture == CardGesture.Type.DIV:
		return BattleAct.Outcome.WIN

	if defender_gesture == CardGesture.Type.DIV:
		return BattleAct.Outcome.LOSS

	var attacker_wins: bool = (
		(
			attacker_gesture == CardGesture.Type.ROCK
			and defender_gesture
			== CardGesture.Type.SCISSORS
		)
		or
		(
			attacker_gesture == CardGesture.Type.PAPER
			and defender_gesture
			== CardGesture.Type.ROCK
		)
		or
		(
			attacker_gesture == CardGesture.Type.SCISSORS
			and defender_gesture
			== CardGesture.Type.PAPER
		)
	)

	if attacker_wins:
		return BattleAct.Outcome.WIN

	return BattleAct.Outcome.LOSS


func _opposite_outcome(outcome: int) -> int:
	match outcome:
		BattleAct.Outcome.WIN:
			return BattleAct.Outcome.LOSS

		BattleAct.Outcome.LOSS:
			return BattleAct.Outcome.WIN

		_:
			return BattleAct.Outcome.TIE


func _outcome_value(outcome: int) -> float:
	match outcome:
		BattleAct.Outcome.WIN:
			return 10.0

		BattleAct.Outcome.TIE:
			return 2.0

		BattleAct.Outcome.LOSS:
			return -8.0

	return 0.0


func _get_candidate_key(
	card: CardInstance,
	slot_id: int
) -> String:
	return str(card.instance_id) + ":" + str(slot_id)
