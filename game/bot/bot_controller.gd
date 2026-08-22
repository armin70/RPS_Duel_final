class_name BotController
extends RefCounted


const MAX_ACTIONS_PER_TURN: int = 12
const MIN_COLLECTOR_TARGETS: int = 2
const BOARD_MOVE_MANA_COST: int = 1
const INVALID_SCORE: float = -1000000.0
const HARDCORE_SETTING: StringName = &"gameplay/hardcore_bot"

# The bot should spend its single board move only when the resulting
# position is meaningfully better.
const STRATEGIC_MOVE_MIN_IMPROVEMENT: float = 4.0
const STRATEGIC_MOVE_MANA_PENALTY: float = 1.15


var random := RandomNumberGenerator.new()

# FAIR MODE KNOWLEDGE
# Snapshot of the opponent board at the START of the turn, before any
# secret play/move happens. Values are cloned CardInstances so later
# movement cannot leak a changed current_slot or other mutable state.
var fair_known_opponent_board: Dictionary = {}
var fair_known_opponent_player_id: int = -1
var fair_known_turn_number: int = -1
var fair_snapshot_ready: bool = false


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


# =========================================================
# FAIR KNOWLEDGE SNAPSHOT
# =========================================================

func capture_fair_opponent_snapshot(
	state: MatchState,
	opponent_player_id: int
) -> void:
	fair_known_opponent_board.clear()
	fair_known_opponent_player_id = opponent_player_id
	fair_known_turn_number = -1
	fair_snapshot_ready = false

	if state == null:
		return

	var opponent: PlayerState = state.get_player(
		opponent_player_id
	)

	if opponent == null:
		return

	for slot_id: int in SlotID.all_slots():
		var card: CardInstance = opponent.board.get_card(
			slot_id
		)

		if card == null:
			continue

		var snapshot_card: CardInstance = 			_make_fair_card_snapshot(
				card,
				slot_id
			)

		if snapshot_card != null:
			fair_known_opponent_board[
				slot_id
			] = snapshot_card

	fair_known_turn_number = state.turn_number
	fair_snapshot_ready = true

	print(
		"FAIR BOT SNAPSHOT | turn=",
		state.turn_number,
		" | known_cards=",
		fair_known_opponent_board.size()
	)


func _make_fair_card_snapshot(
	card: CardInstance,
	known_slot_id: int
) -> CardInstance:
	if card == null or card.definition == null:
		return null

	var snapshot := CardInstance.new(
		card.instance_id,
		card.definition,
		card.owner_id
	)

	snapshot.zone = card.zone
	snapshot.current_slot = known_slot_id
	snapshot.turn_played = card.turn_played
	snapshot.disabled_combat_turn = (
		card.disabled_combat_turn
	)
	snapshot.shield_count = card.shield_count
	snapshot.shields_initialized = (
		card.shields_initialized
	)
	snapshot.ability_used = card.ability_used

	return snapshot


func _can_inspect_opponent_card(
	state: MatchState,
	card: CardInstance
) -> bool:
	if state == null or card == null:
		return false

	if is_hardcore_mode():
		return true

	if not fair_snapshot_ready:
		return false

	if fair_known_turn_number != state.turn_number:
		return false

	for known_variant: Variant in 			fair_known_opponent_board.values():
		var known_card := known_variant as CardInstance

		if known_card == null:
			continue

		if known_card.instance_id == card.instance_id:
			return true

	return false


func _get_visible_opponent_card(
	state: MatchState,
	opponent: PlayerState,
	slot_id: int
) -> CardInstance:
	if state == null or opponent == null:
		return null

	# Hardcore intentionally keeps perfect information.
	if is_hardcore_mode():
		return opponent.board.get_card(slot_id)

	# Fair fails closed. If a fresh snapshot was not captured,
	# it sees no opponent identity instead of leaking real state.
	if not fair_snapshot_ready:
		return null

	if fair_known_turn_number != state.turn_number:
		return null

	if (
		fair_known_opponent_player_id
		!= opponent.player_id
	):
		return null

	return fair_known_opponent_board.get(
		slot_id,
		null
	) as CardInstance


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
		var source_card: CardInstance = null

		# کارت‌های خود Bot همیشه معلوم‌اند.
		if source_owner_id == bot.player_id:
			source_card = source_player.board.get_card(
				source_slot_id
			)
		else:
			# برای حریف فقط Snapshot عمومی ابتدای Turn استفاده می‌شود.
			# بنابراین Disabler قدیمی که مخفیانه جابه‌جا شده، محل جدیدش لو نمی‌رود.
			source_card = _get_visible_opponent_card(
				state,
				source_player,
				source_slot_id
			)

		if source_card == null:
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

	# Rush has a completely separate planner. It does not score Dealer combat
	# at all; it optimizes permanent PvP eliminations, survival, free movement,
	# and the unused-mana sacrifice rule.
	if state.rush_mode_enabled:
		_play_rush_turn(
			engine,
			state,
			bot,
			opponent
		)
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

	# اگر Move برای فرار از Disabler مصرف نشده، همه جابه‌جایی‌های قانونی
	# را بررسی کن. مقصد می‌تواند خالی یا یک کارت قدیمی قابل Cover باشد.
	# بعد از Move، Planner عادی ادامه پیدا می‌کند؛ پس Move -> Play/Cover داریم.
	if (
		not is_hardcore_mode()
		and _try_best_strategic_move(
			engine,
			state,
			bot,
			opponent
		)
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


# =========================================================
# RUSH MODE PLANNER
# =========================================================

func _play_rush_turn(
	engine: MatchEngine,
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState
) -> void:
	if engine == null or state == null or bot == null or opponent == null:
		return

	print(
		"BOT STRATEGY | RUSH | mana=",
		bot.current_mana,
		" | bot_cards=",
		bot.get_remaining_card_count(),
		" | opponent_cards=",
		opponent.get_remaining_card_count()
	)

	# Movement costs zero mana in Rush but remains limited to once per turn.
	# Use it first to rescue a card from a known permanent loss or create a
	# better elimination matchup.
	_try_best_rush_move(
		engine,
		state,
		bot,
		opponent
	)

	# Rush-only sacrifice/transform decision. The bot chooses the new gesture
	# strategically, but the payment card is still randomly selected by Engine,
	# exactly like the player's button. Keep it conservative: sacrifice only to
	# rescue a board card from a clearly bad permanent-loss position.
	_try_best_rush_transform(
		engine,
		state,
		bot,
		opponent
	)

	var completed_actions: int = 0
	var blocked_candidates: Dictionary = {}

	while completed_actions < MAX_ACTIONS_PER_TURN:
		var best_candidate: Dictionary = \
			_find_best_rush_play_candidate(
				state,
				bot,
				opponent,
				blocked_candidates
			)

		if best_candidate.is_empty():
			break

		var best_score: float = float(
			best_candidate.get("score", INVALID_SCORE)
		)

		# If less than two mana remain there is no Rush sacrifice. Do not throw
		# a card onto the board for a clearly bad matchup just to spend the last
		# harmless point of mana.
		if bot.current_mana < 2 and best_score < 0.0:
			break

		# A negative score while a sacrifice is pending means the planner judged
		# that intentionally losing a random hand card is safer than this play.
		if (
			bot.current_mana >= 2
			and best_score < 0.0
		):
			break

		var card := best_candidate.get("card", null) as CardInstance
		var slot_id: int = int(best_candidate.get("slot_id", -1))

		if card == null or not SlotID.is_valid(slot_id):
			break

		var candidate_key: String = _get_candidate_key(card, slot_id)
		var success: bool = engine.play_card(
			bot.player_id,
			card,
			slot_id
		)

		if not success:
			blocked_candidates[candidate_key] = true
			continue

		completed_actions += 1
		blocked_candidates.clear()

		print(
			"RUSH BOT PLAY | card=",
			card.definition.display_name,
			" | slot=",
			slot_id,
			" | score=",
			best_score,
			" | mana_left=",
			bot.current_mana,
			" | pending_penalty=",
			_rush_penalty_count_for_mana(bot.current_mana)
		)


func _find_best_rush_play_candidate(
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

		for slot_id: int in SlotID.all_slots():
			var candidate_key: String = _get_candidate_key(card, slot_id)

			if blocked_candidates.has(candidate_key):
				continue

			if not _is_legal_play_candidate(
				state,
				bot,
				card,
				slot_id
			):
				continue

			var score: float = _score_rush_play_candidate(
				state,
				bot,
				opponent,
				card,
				slot_id
			)

			# Small noise prevents exact repetition without changing the Rush goals.
			score += random.randf_range(-0.08, 0.08)

			if score > best_score:
				best_score = score
				best_candidate = {
					"card": card,
					"slot_id": slot_id,
					"score": score
				}

	return best_candidate


func _score_rush_play_candidate(
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState,
	card: CardInstance,
	slot_id: int
) -> float:
	if card == null or card.definition == null:
		return INVALID_SCORE

	var score: float = _score_rush_card_matchups(
		state,
		bot,
		opponent,
		card,
		slot_id
	)

	var cost: int = card.definition.mana_cost
	var penalty_before: int = _rush_penalty_count_for_mana(
		bot.current_mana
	)
	var penalty_after: int = _rush_penalty_count_for_mana(
		maxi(0, bot.current_mana - cost)
	)
	var sacrifices_avoided: int = maxi(
		0,
		penalty_before - penalty_after
	)

	# Preventing a random permanent hand loss is a core Rush objective.
	score += float(sacrifices_avoided) * 24.0

	# Prefer exact/near-exact mana usage when tactical values are close.
	if bot.current_mana - cost < 2:
		score += 2.5

	var replaced: CardInstance = bot.board.get_card(slot_id)
	if replaced != null:
		# Cover does not permanently delete the old card in Rush, but it removes
		# a useful body from this combat, so valuable cards should not be covered
		# casually.
		score -= _card_importance(replaced) * 0.35

	var behavior: CardBehavior = card.definition.behavior

	if behavior is DefenseBehavior:
		score += 4.0
	elif behavior is FrontShieldBehavior:
		score += 5.0
	elif behavior is DisableGestureBehavior:
		score += _score_rush_disabler(
			state,
			bot,
			opponent,
			behavior as DisableGestureBehavior,
			slot_id
		)

	return score


func _score_rush_disabler(
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState,
	behavior: DisableGestureBehavior,
	slot_id: int
) -> float:
	if behavior == null:
		return 0.0

	var affected: int = 0
	var valuable_affected: float = 0.0

	for target_slot_id: int in SlotID.all_slots():
		var target: CardInstance = _get_visible_opponent_card(
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

		affected += 1
		valuable_affected += _card_importance(target)

	return float(affected) * 6.0 + valuable_affected * 0.25


func _score_rush_card_matchups(
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState,
	card: CardInstance,
	slot_id: int
) -> float:
	if card == null or card.definition == null:
		return INVALID_SCORE

	var known_targets: int = 0
	var wins: int = 0
	var losses: int = 0
	var ties: int = 0
	var defeated_value: float = 0.0

	for target_slot_id: int in _get_opponent_target_slots(slot_id):
		var target: CardInstance = _get_visible_opponent_card(
			state,
			opponent,
			target_slot_id
		)

		if target == null or target.definition == null:
			continue

		known_targets += 1

		var outcome: int = _compare_gestures(
			card.get_gesture(),
			target.get_gesture()
		)

		if (
			card.definition.behavior is CreditCardBehavior
			and target.get_gesture() == CardGesture.Type.SCISSORS
		):
			outcome = BattleAct.Outcome.WIN

		var bot_disabled: bool = _is_card_disabled_for_bot_view(
			state,
			bot,
			bot.player_id,
			slot_id,
			card
		)
		var opponent_disabled: bool = _is_card_disabled_for_bot_view(
			state,
			bot,
			opponent.player_id,
			target_slot_id,
			target
		)

		var new_disabler := card.definition.behavior as DisableGestureBehavior
		if (
			new_disabler != null
			and new_disabler.disables_target(
				slot_id,
				target_slot_id,
				target
			)
		):
			opponent_disabled = true

		if bot_disabled and outcome == BattleAct.Outcome.WIN:
			outcome = BattleAct.Outcome.TIE

		var opponent_outcome: int = _opposite_outcome(outcome)
		if opponent_disabled and opponent_outcome == BattleAct.Outcome.WIN:
			outcome = BattleAct.Outcome.TIE

		match outcome:
			BattleAct.Outcome.WIN:
				wins += 1
				defeated_value += _card_importance(target)
			BattleAct.Outcome.LOSS:
				losses += 1
			_:
				ties += 1

	# Fair mode does not peek at current-turn secret cards. Unknown lanes get a
	# mild risk tax instead of fake certainty.
	if known_targets == 0:
		return -2.0 - _card_importance(card) * 0.10

	var score: float = 0.0
	score += float(wins) * 18.0
	score += defeated_value * 0.70
	score += float(ties) * 1.5

	# CRITICAL Rush rule: one LOSS is enough to permanently eliminate this
	# CardInstance, even if the same middle card also has one or more WINs.
	if losses > 0:
		score -= 28.0
		score -= _card_importance(card) * 1.25

	return score


func _try_best_rush_move(
	engine: MatchEngine,
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState
) -> bool:
	if engine == null or state == null or bot == null or opponent == null:
		return false

	if bot.board_move_used_turn == state.turn_number:
		return false

	var best_from: int = -1
	var best_to: int = -1
	var best_improvement: float = 2.0

	for from_slot_id: int in SlotID.all_slots():
		var moving_card: CardInstance = bot.board.get_card(from_slot_id)

		if moving_card == null or moving_card.definition == null:
			continue

		var current_score: float = _score_rush_card_matchups(
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

			# Rush repositioning is for survival/targeting. Do not burn another own
			# board card through a Cover while a free empty destination exists.
			if bot.board.get_card(to_slot_id) != null:
				continue

			var destination_score: float = _score_rush_card_matchups(
				state,
				bot,
				opponent,
				moving_card,
				to_slot_id
			)
			var improvement: float = destination_score - current_score

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
			"RUSH BOT FREE MOVE | from=",
			best_from,
			" | to=",
			best_to,
			" | improvement=",
			best_improvement
		)

	return moved



func _try_best_rush_transform(
	engine: MatchEngine,
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState
) -> bool:
	if engine == null or state == null or bot == null or opponent == null:
		return false

	var board_cards: Array[CardInstance] = bot.board.get_occupied_cards()
	if board_cards.size() < 2:
		return false

	var best_target: CardInstance
	var best_gesture: int = -1
	var best_gain: float = 6.0

	for target: CardInstance in board_cards:
		if target == null or target.definition == null:
			continue
		if not engine.can_rush_transform_card(bot.player_id, target):
			continue

		var slot_id: int = target.current_slot
		if not SlotID.is_valid(slot_id):
			continue

		var current_score: float = _score_rush_card_matchups(
			state,
			bot,
			opponent,
			target,
			slot_id
		)

		# Do not permanently burn another own card just to optimize an already
		# acceptable matchup. Sacrifice is a rescue tool first.
		if current_score >= 0.0:
			continue

		var old_override: int = target.gesture_override
		var old_gesture: CardGesture.Type = target.get_gesture()

		for candidate_gesture: int in [
			CardGesture.Type.ROCK,
			CardGesture.Type.PAPER,
			CardGesture.Type.SCISSORS
		]:
			if candidate_gesture == old_gesture:
				continue

			var candidate_type: CardGesture.Type = candidate_gesture
			target.set_gesture_override(candidate_type)
			var transformed_score: float = _score_rush_card_matchups(
				state,
				bot,
				opponent,
				target,
				slot_id
			)

			var candidates: Array[CardInstance] = \
				engine.get_rush_sacrifice_candidates(bot.player_id, target)
			var expected_cost: float = 18.0
			if not candidates.is_empty():
				var importance_sum: float = 0.0
				for other: CardInstance in candidates:
					importance_sum += _card_importance(other)
				expected_cost += (
					importance_sum / float(candidates.size())
				) * 0.75

			var gain: float = (
				transformed_score
				- current_score
				- expected_cost
			)

			if gain > best_gain:
				best_gain = gain
				best_target = target
				best_gesture = candidate_gesture

		target.gesture_override = old_override

	if best_target == null or best_gesture < 0:
		return false

	var selected_gesture: CardGesture.Type = best_gesture
	var removed_card: CardInstance = engine.apply_rush_transform(
		bot.player_id,
		best_target,
		selected_gesture
	)

	if removed_card == null:
		return false

	print(
		"RUSH BOT SACRIFICE | target=",
		best_target.definition.display_name,
		" | new_type=",
		CardGesture.Type.keys()[selected_gesture],
		" | sacrificed=",
		removed_card.definition.display_name
			if removed_card.definition != null else "Card",
		" | tactical_gain=",
		best_gain
	)
	return true

func _rush_penalty_count_for_mana(mana: int) -> int:
	return floori(float(maxi(0, mana)) / 2.0)


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

	if turns_since_played < 2:
		return false

	return CardGesture.can_cover(
		card.get_gesture(),
		replaced_card.get_gesture()
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

	# Generic Dealer-lane consequence hook.
	# Gladiator can expose get_ai_pvp_loss_penalty() without BotController
	# knowing the card id/name.
	score += _score_dealer_pvp_consequence(
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
			card.get_gesture(),
			target.get_gesture()
		)

		# Credit Card در Turn ورود Scissors را می‌برد.
		if (
			card.definition.behavior is CreditCardBehavior
			and target.get_gesture()
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
			card.get_gesture(),
			dealer_card.get_gesture()
		)

		if card.definition.behavior is MustacheRockBehavior:
			if _count_other_rocks_for_view(state, bot, bot, card) >= 2:
				outcome = BattleAct.Outcome.WIN

		elif card.definition.behavior is ChainsawBehavior:
			if (
				dealer_card.get_gesture()
				!= CardGesture.Type.ROCK
			):
				outcome = BattleAct.Outcome.WIN

		elif card.definition.behavior is CreditCardBehavior:
			if (
				dealer_card.get_gesture()
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
				dealer_card.get_gesture()
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


func _calculate_move_net_benefit(
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState,
	moving_card: CardInstance,
	from_slot_id: int,
	to_slot_id: int
) -> float:
	if (
		state == null
		or bot == null
		or moving_card == null
		or moving_card.definition == null
	):
		return INVALID_SCORE

	var current_score: float = _score_existing_card_position(
		state,
		bot,
		opponent,
		moving_card,
		from_slot_id
	)

	var destination_score: float = _score_existing_card_position(
		state,
		bot,
		opponent,
		moving_card,
		to_slot_id
	)

	# Mana itself has value in normal mode. Rush board movement is free.
	var move_mana_penalty: float = (
		0.0
		if state.rush_mode_enabled
		else STRATEGIC_MOVE_MANA_PENALTY
	)

	var benefit: float = (
		destination_score
		- current_score
		- move_mana_penalty
	)

	var replaced: CardInstance = bot.board.get_card(
		to_slot_id
	)

	if replaced != null:
		var replaced_score: float = _score_existing_card_position(
			state,
			bot,
			opponent,
			replaced,
			to_slot_id
		)

		# Cover means we intentionally give up the card already there.
		# This is a REAL cost, especially for valuable/special cards.
		benefit -= _card_importance(replaced) * 1.25

		# If that card is genuinely in a bad position, removing it has some value,
		# but this bonus is capped so the bot does not Cover for weak reasons.
		if replaced_score < -4.0:
			benefit += minf(
				abs(replaced_score) * 0.35,
				4.0
			)

		# When the board is completely jammed, opening one slot is useful,
		# but not enough by itself to justify a bad move.
		if _get_empty_legal_slot_count(bot) == 0:
			benefit += 1.5

	return benefit


func _try_best_strategic_move(
	engine: MatchEngine,
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState
) -> bool:
	if engine == null or state == null or bot == null:
		return false

	if bot.current_mana < engine.get_board_move_mana_cost():
		return false

	if bot.board_move_used_turn == state.turn_number:
		return false

	var best_from: int = -1
	var best_to: int = -1
	var best_improvement: float = (
		STRATEGIC_MOVE_MIN_IMPROVEMENT
	)

	for from_slot_id: int in SlotID.all_slots():
		var moving_card: CardInstance = 			bot.board.get_card(
				from_slot_id
			)

		if (
			moving_card == null
			or moving_card.definition == null
		):
			continue

		for to_slot_id: int in SlotID.all_slots():
			if not _is_legal_move_candidate(
				state,
				bot,
				moving_card,
				from_slot_id,
				to_slot_id
			):
				continue

			var improvement: float = _calculate_move_net_benefit(
				state,
				bot,
				opponent,
				moving_card,
				from_slot_id,
				to_slot_id
			)

			# No random movement. Only a clear positive net benefit is accepted.
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
			"BOT STRATEGIC MOVE | from=",
			best_from,
			" | to=",
			best_to,
			" | improvement=",
			best_improvement
		)

	return moved


func _try_reposition_disabled_card(
	engine: MatchEngine,
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState
) -> bool:
	if bot.current_mana < engine.get_board_move_mana_cost():
		return false

	if bot.board_move_used_turn == state.turn_number:
		return false

	var best_from: int = -1
	var best_to: int = -1
	var best_improvement: float = STRATEGIC_MOVE_MIN_IMPROVEMENT

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

			var improvement: float = _calculate_move_net_benefit(
				state,
				bot,
				opponent,
				moving_card,
				from_slot_id,
				to_slot_id
			)

			# Even escaping Disable must produce a real net improvement.
			# The current-position score already includes the Disable penalty,
			# so no artificial +100 bonus is needed.
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
			target.get_gesture(),
			bot_card.get_gesture()
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
			target.get_gesture(),
			dealer_card.get_gesture()
		)

		if target.definition.behavior is CreditCardBehavior:
			if (
				dealer_card.get_gesture()
				== CardGesture.Type.SCISSORS
			):
				outcome = BattleAct.Outcome.WIN

		elif target.definition.behavior is ChainsawBehavior:
			if (
				dealer_card.get_gesture()
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

	if turns_since_played < 2:
		return false

	return CardGesture.can_cover(
		moving_card.get_gesture(),
		replaced.get_gesture()
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

	score += _score_dealer_pvp_consequence(
		state,
		bot,
		opponent,
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
			target.get_gesture()
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
			card.get_gesture()
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

	if card.get_gesture() == CardGesture.Type.DIV:
		value += 12.0

	value += float(card.shield_count) * 2.0

	return value


func _score_dealer_pvp_consequence(
	state: MatchState,
	bot: PlayerState,
	opponent: PlayerState,
	card: CardInstance,
	slot_id: int
) -> float:
	# This upgrade is intentionally FAIR-only so Hardcore behavior stays
	# otherwise unchanged.
	if is_hardcore_mode():
		return 0.0

	if (
		state == null
		or state.dealer == null
		or bot == null
		or opponent == null
		or card == null
		or card.definition == null
	):
		return 0.0

	# Take the strongest consequence in this lane instead of stacking duplicate
	# middle Dealer cards that represent the same lane rule.
	var loss_penalty: float = 0.0

	for dealer_slot_id: int in _get_dealer_target_slots(
		state,
		bot,
		card,
		slot_id
	):
		var dealer_card: CardInstance = 			state.dealer.slots.get(
				dealer_slot_id,
				null
			) as CardInstance

		if (
			dealer_card == null
			or dealer_card.definition == null
		):
			continue

		var dealer_behavior: DealerCardBehavior = 			dealer_card.definition.dealer_behavior

		if dealer_behavior == null:
			continue

		if not dealer_behavior.has_method(
			"get_ai_pvp_loss_penalty"
		):
			continue

		var raw_penalty: Variant = dealer_behavior.call(
			"get_ai_pvp_loss_penalty"
		)

		loss_penalty = maxf(
			loss_penalty,
			float(raw_penalty)
		)

	if loss_penalty <= 0.0:
		return 0.0

	var result: float = 0.0
	var known_targets: int = 0

	for target_slot_id: int in 			_get_opponent_target_slots(slot_id):
		var target: CardInstance = 			_get_visible_opponent_card(
				state,
				opponent,
				target_slot_id
			)

		if target == null or target.definition == null:
			continue

		known_targets += 1

		var outcome: int = _compare_gestures(
			card.get_gesture(),
			target.get_gesture()
		)

		if outcome == BattleAct.Outcome.LOSS:
			# Losing a valuable bot card in a permanent-loss lane is very bad.
			result -= loss_penalty * (
				1.0
				+ _card_importance(card) * 0.10
			)
		elif outcome == BattleAct.Outcome.WIN:
			# Conversely, winning there can permanently punish a known enemy card.
			result += loss_penalty * 0.45
			result += _card_importance(target) * 0.35

	# With no publicly-known enemy identity the Fair bot must NOT peek.
	# It only applies a small uncertainty tax, especially to valuable cards.
	if known_targets == 0:
		result -= loss_penalty * (
			0.08
			+ _card_importance(card) * 0.015
		)

	return result


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
