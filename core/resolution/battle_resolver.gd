class_name BattleResolver
extends RefCounted


static func build_sequence(
	state: MatchState
) -> BattleSequence:
	var sequence := BattleSequence.new()

	if state == null:
		return sequence

	# ردیف جلو ـ لاین چپ
	_add_side_lane_sequence(
		state,
		sequence,
		SlotID.Type.FRONT_LEFT,
		DealerSlotID.Type.LEFT
	)

	# ردیف جلو ـ لاین وسط
	_add_middle_row_sequence(
		state,
		sequence,
		SlotID.Type.FRONT_MIDDLE_0,
		SlotID.Type.FRONT_MIDDLE_1
	)

	# ردیف جلو ـ لاین راست
	_add_side_lane_sequence(
		state,
		sequence,
		SlotID.Type.FRONT_RIGHT,
		DealerSlotID.Type.RIGHT
	)

	# ردیف عقب ـ لاین چپ
	_add_side_lane_sequence(
		state,
		sequence,
		SlotID.Type.BACK_LEFT,
		DealerSlotID.Type.LEFT
	)

	# ردیف عقب ـ لاین وسط
	_add_middle_row_sequence(
		state,
		sequence,
		SlotID.Type.BACK_MIDDLE_0,
		SlotID.Type.BACK_MIDDLE_1
	)

	# ردیف عقب ـ لاین راست
	_add_side_lane_sequence(
		state,
		sequence,
		SlotID.Type.BACK_RIGHT,
		DealerSlotID.Type.RIGHT
	)

	# Build all PvP clashes after Dealer attacks so Taunt can redirect targets
	# BEFORE any clash mutates shields/charges. BFG then expands real wins.
	_add_all_player_pvp_clashes(state, sequence)
	_append_bfg_column_wins(state, sequence)

	return sequence
static func _create_player_vs_dealer_act(
	state: MatchState,
	player_id: int,
	player_card: CardInstance,
	player_slot_id: int,
	dealer_card: CardInstance,
	dealer_slot_id: int
) -> BattleAct:
	var act := BattleAct.new()

	act.type = BattleAct.Type.PLAYER_VS_DEALER
	act.attacker = player_card
	act.defender = dealer_card
	act.attacker_owner_id = player_id
	act.defender_owner_id = 0
	act.attacker_slot_id = player_slot_id
	act.dealer_slot_id = dealer_slot_id

	var outcome: BattleAct.Outcome = _compare_gestures(
		player_card.get_gesture(),
		dealer_card.get_gesture()
	)

	var player_card_is_disabled: bool = \
		DisableGestureBehavior.is_card_disabled(
			state,
			player_id,
			player_slot_id,
			player_card
		)

	if player_card_is_disabled and outcome == BattleAct.Outcome.WIN:
		outcome = BattleAct.Outcome.TIE

	# Rostam sleeps on the turn after Fury: a would-be win becomes a tie.
	if (
		outcome == BattleAct.Outcome.WIN
		and player_card.is_hero_sleeping(state.turn_number)
	):
		outcome = BattleAct.Outcome.TIE

	outcome = _apply_behavior_to_outcome(
		state,
		player_card,
		dealer_card,
		outcome
	)

	if player_card_is_disabled and outcome == BattleAct.Outcome.WIN:
		outcome = BattleAct.Outcome.TIE

	# Debuffer from the previous turn downgrades any would-be win to a tie.
	if (
		outcome == BattleAct.Outcome.WIN
		and player_card.cannot_win_due_to_debuffer(state.turn_number)
	):
		outcome = BattleAct.Outcome.TIE

	# A global OP Healer charge can turn any friendly LOSS into a TIE.
	if outcome == BattleAct.Outcome.LOSS:
		outcome = OPHealerBehavior.try_prevent_loss(
			state, player_id, player_card, outcome
		)

	if outcome == BattleAct.Outcome.WIN:
		var hit_count: int = _get_winning_hit_count(state, player_card)
		act.attacker_landed_hits = hit_count
		act.attacker_points = _points_for_outcome(state, outcome) * hit_count
	elif outcome == BattleAct.Outcome.LOSS:
		# Dealer hits consume Hero shields too, exactly like other incoming hits.
		var hit_result: Dictionary = _apply_incoming_hits(
			player_card,
			1,
			outcome,
			false
		)
		outcome = int(hit_result.get("outcome", outcome))
		act.defender_landed_hits = int(hit_result.get("landed_hits", 0))

	act.attacker_outcome = outcome
	if outcome != BattleAct.Outcome.WIN:
		act.attacker_points = _points_for_outcome(state, outcome)
	act.attacker_points = _apply_afrasiab_active_score(
		state, player_card, outcome, act.attacker_points
	)

	return act


static func _create_player_vs_player_act(
	state: MatchState,
	player_one_card: CardInstance,
	player_two_card: CardInstance,
	player_one_slot_id: int,
	player_two_slot_id: int
) -> BattleAct:
	var act := BattleAct.new()
	act.type = BattleAct.Type.PLAYER_VS_PLAYER
	act.attacker = player_one_card
	act.defender = player_two_card
	act.attacker_owner_id = 1
	act.defender_owner_id = 2
	act.attacker_slot_id = player_one_slot_id
	act.defender_slot_id = player_two_slot_id

	var player_one_outcome: int = _compare_gestures(
		player_one_card.get_gesture(),
		player_two_card.get_gesture()
	)
	var player_two_outcome: int = _opposite_outcome(player_one_outcome)


	var player_one_is_disabled: bool = \
		DisableGestureBehavior.is_card_disabled(
			state, 1, player_one_slot_id, player_one_card
		)
	var player_two_is_disabled: bool = \
		DisableGestureBehavior.is_card_disabled(
			state, 2, player_two_slot_id, player_two_card
		)

	if player_one_is_disabled and player_one_outcome == BattleAct.Outcome.WIN:
		player_one_outcome = BattleAct.Outcome.TIE
		player_two_outcome = BattleAct.Outcome.TIE
	if player_two_is_disabled and player_two_outcome == BattleAct.Outcome.WIN:
		player_one_outcome = BattleAct.Outcome.TIE
		player_two_outcome = BattleAct.Outcome.TIE

	var modified_player_one_outcome: int = _apply_behavior_to_outcome(
		state,
		player_one_card,
		player_two_card,
		player_one_outcome
	)
	if modified_player_one_outcome != player_one_outcome:
		player_one_outcome = modified_player_one_outcome
		player_two_outcome = _opposite_outcome(player_one_outcome)

	var modified_player_two_outcome: int = _apply_behavior_to_outcome(
		state,
		player_two_card,
		player_one_card,
		player_two_outcome
	)
	if modified_player_two_outcome != player_two_outcome:
		player_two_outcome = modified_player_two_outcome
		player_one_outcome = _opposite_outcome(player_two_outcome)

	if player_one_is_disabled and player_one_outcome == BattleAct.Outcome.WIN:
		player_one_outcome = BattleAct.Outcome.TIE
		player_two_outcome = BattleAct.Outcome.TIE
	if player_two_is_disabled and player_two_outcome == BattleAct.Outcome.WIN:
		player_one_outcome = BattleAct.Outcome.TIE
		player_two_outcome = BattleAct.Outcome.TIE

	# Rostam sleep is checked after normal card behaviors/Disable but before
	# shields are consumed. A sleeping Rostam can still lose; only a win is tied.
	if (
		player_one_outcome == BattleAct.Outcome.WIN
		and player_one_card.is_hero_sleeping(state.turn_number)
	):
		player_one_outcome = BattleAct.Outcome.TIE
		player_two_outcome = BattleAct.Outcome.TIE
	if (
		player_two_outcome == BattleAct.Outcome.WIN
		and player_two_card.is_hero_sleeping(state.turn_number)
	):
		player_one_outcome = BattleAct.Outcome.TIE
		player_two_outcome = BattleAct.Outcome.TIE

	# Debuffer status belongs to the defeated CardInstance and lasts for the
	# following turn: a would-be win is converted to a tie.
	if (
		player_one_outcome == BattleAct.Outcome.WIN
		and player_one_card.cannot_win_due_to_debuffer(state.turn_number)
	):
		player_one_outcome = BattleAct.Outcome.TIE
		player_two_outcome = BattleAct.Outcome.TIE
	if (
		player_two_outcome == BattleAct.Outcome.WIN
		and player_two_card.cannot_win_due_to_debuffer(state.turn_number)
	):
		player_one_outcome = BattleAct.Outcome.TIE
		player_two_outcome = BattleAct.Outcome.TIE

	# OP Healer is a global five-charge safety net. Only one side can be losing
	# in a normal RPS clash, so the first successful prevention neutralizes it.
	if player_one_outcome == BattleAct.Outcome.LOSS:
		var healed_one: int = OPHealerBehavior.try_prevent_loss(
			state, 1, player_one_card, player_one_outcome
		)
		if healed_one == BattleAct.Outcome.TIE:
			player_one_outcome = BattleAct.Outcome.TIE
			player_two_outcome = BattleAct.Outcome.TIE
	elif player_two_outcome == BattleAct.Outcome.LOSS:
		var healed_two: int = OPHealerBehavior.try_prevent_loss(
			state, 2, player_two_card, player_two_outcome
		)
		if healed_two == BattleAct.Outcome.TIE:
			player_one_outcome = BattleAct.Outcome.TIE
			player_two_outcome = BattleAct.Outcome.TIE

	# A Fury winner lands two attacks. Shields absorb hits one-by-one; any hit
	# that remains after the shield reaches zero is an exposed Hero hit.
	if player_one_outcome == BattleAct.Outcome.WIN:
		var player_one_hit_count: int = _get_winning_hit_count(state, player_one_card)
		var player_one_hit_result: Dictionary = _apply_incoming_hits(
			player_two_card,
			player_one_hit_count,
			player_two_outcome,
			player_one_card.is_hero()
		)
		act.attacker_landed_hits = int(player_one_hit_result.get("landed_hits", 0))
		act.attacker_unshielded_hero_hits = int(
			player_one_hit_result.get("unshielded_hero_hits", 0)
		)
		player_two_outcome = int(player_one_hit_result.get("outcome", player_two_outcome))
		player_one_outcome = _opposite_outcome(player_two_outcome)

	elif player_two_outcome == BattleAct.Outcome.WIN:
		var player_two_hit_count: int = _get_winning_hit_count(state, player_two_card)
		var player_two_hit_result: Dictionary = _apply_incoming_hits(
			player_one_card,
			player_two_hit_count,
			player_one_outcome,
			player_two_card.is_hero()
		)
		act.defender_landed_hits = int(player_two_hit_result.get("landed_hits", 0))
		act.defender_unshielded_hero_hits = int(
			player_two_hit_result.get("unshielded_hero_hits", 0)
		)
		player_one_outcome = int(player_two_hit_result.get("outcome", player_one_outcome))
		player_two_outcome = _opposite_outcome(player_one_outcome)

	act.attacker_outcome = player_one_outcome
	act.defender_outcome = player_two_outcome
	act.attacker_points = _hero_adjusted_points(
		state,
		player_one_outcome,
		act.attacker_landed_hits,
		act.attacker_unshielded_hero_hits
	)
	act.defender_points = _hero_adjusted_points(
		state,
		player_two_outcome,
		act.defender_landed_hits,
		act.defender_unshielded_hero_hits
	)
	act.attacker_points = _apply_afrasiab_active_score(
		state, player_one_card, player_one_outcome, act.attacker_points
	)
	act.defender_points = _apply_afrasiab_active_score(
		state, player_two_card, player_two_outcome, act.defender_points
	)

	return act

static func _compare_gestures(
	attacker_gesture: CardGesture.Type,
	defender_gesture: CardGesture.Type
) -> BattleAct.Outcome:
	# دو Gesture یکسان همیشه مساوی هستند.
	if attacker_gesture == defender_gesture:
		return BattleAct.Outcome.TIE

	# DIV تمام Gestureهای دیگر را شکست می‌دهد.
	if attacker_gesture == CardGesture.Type.DIV:
		return BattleAct.Outcome.WIN

	# هیچ Gesture معمولی نمی‌تواند DIV را شکست دهد.
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

static func _opposite_outcome(
	outcome: BattleAct.Outcome
) -> BattleAct.Outcome:
	match outcome:
		BattleAct.Outcome.WIN:
			return BattleAct.Outcome.LOSS

		BattleAct.Outcome.LOSS:
			return BattleAct.Outcome.WIN

		_:
			return BattleAct.Outcome.TIE


static func _points_for_outcome(
	state: MatchState,
	outcome: BattleAct.Outcome
) -> int:
	match outcome:
		BattleAct.Outcome.WIN:
			return state.rules.win_points

		BattleAct.Outcome.LOSS:
			return state.rules.loss_points

		_:
			return state.rules.tie_points

static func _get_dealer_slot_for_board_slot(
	slot_id: int
) -> int:
	match slot_id:
		SlotID.Type.FRONT_LEFT, \
		SlotID.Type.BACK_LEFT:
			return DealerSlotID.Type.LEFT

		SlotID.Type.FRONT_MIDDLE_0, \
		SlotID.Type.BACK_MIDDLE_0:
			return DealerSlotID.Type.MIDDLE_0

		SlotID.Type.FRONT_MIDDLE_1, \
		SlotID.Type.BACK_MIDDLE_1:
			return DealerSlotID.Type.MIDDLE_1

		SlotID.Type.FRONT_RIGHT, \
		SlotID.Type.BACK_RIGHT:
			return DealerSlotID.Type.RIGHT

	return -1

static func _get_dealer_card(
	state: MatchState,
	dealer_slot_id: int
) -> CardInstance:
	if state == null:
		return null

	if state.dealer == null:
		return null

	# حالت اول:
	# DealerState خودش تابع get_card دارد.
	if state.dealer.has_method("get_card"):
		return state.dealer.call(
			"get_card",
			dealer_slot_id
		) as CardInstance

	# حالت دوم:
	# DealerState یک board دارد.
	var dealer_board: Variant = \
		_get_property_if_exists(
			state.dealer,
			&"board"
		)

	if dealer_board is Object:
		var board_object: Object = dealer_board

		if board_object.has_method("get_card"):
			return board_object.call(
				"get_card",
				dealer_slot_id
			) as CardInstance

	# حالت سوم:
	# DealerState مستقیماً Dictionary به اسم slots دارد.
	var dealer_slots_value: Variant = \
		_get_property_if_exists(
			state.dealer,
			&"slots"
		)

	if dealer_slots_value is Dictionary:
		var dealer_slots: Dictionary = \
			dealer_slots_value

		return dealer_slots.get(
			dealer_slot_id,
			null
		) as CardInstance

	push_error(
		"BattleResolver could not find Dealer card storage."
	)

	return null

static func _get_property_if_exists(
	object: Object,
	property_name: StringName
) -> Variant:
	if object == null:
		return null

	for property_info: Dictionary in \
		object.get_property_list():

		var found_name := StringName(
			property_info.get("name", "")
		)

		if found_name == property_name:
			return object.get(property_name)

	return null

static func _add_dealer_attacks(
	state: MatchState,
	sequence: BattleSequence,
	player_id: int,
	player_card: CardInstance,
	player_slot_id: int,
	normal_dealer_slots: Array[int]
) -> void:
	if player_card == null:
		return

	var attack_type: int = \
		CardBehavior.DealerAttackType.NORMAL

	if (
		player_card.definition != null
		and player_card.definition.behavior != null
	):
		attack_type = (
			player_card
			.definition
			.behavior
			.get_dealer_attack_type(
				state,
				player_card
			)
		)

	# سنگ سیبیل دیگر چهار حمله جداگانه نمی‌سازد.
	# یک Act مخصوص می‌سازد و امتیاز تمام Dealerها را یک‌جا می‌دهد.
	if (
		attack_type
		== CardBehavior.DealerAttackType.SWEEP_WIN
	):
		var dealer_card_count: int = 0

		for dealer_slot_id: int in \
			DealerSlotID.all_slots():

			var dealer_card: CardInstance = \
				_get_dealer_card(
					state,
					dealer_slot_id
				)

			if dealer_card != null:
				dealer_card_count += 1

		var mustache_act := BattleAct.new()

		mustache_act.type = \
			BattleAct.Type.MUSTACHE_SWEEP

		mustache_act.attacker = player_card
		mustache_act.attacker_owner_id = player_id
		mustache_act.attacker_slot_id = player_slot_id

		mustache_act.dealer_attack_type = \
			CardBehavior.DealerAttackType.SWEEP_WIN

		mustache_act.attacker_outcome = \
			BattleAct.Outcome.WIN

		mustache_act.attacker_points = (
			state.rules.win_points
			* dealer_card_count
		)

		sequence.add_act(mustache_act)
		return

# Special RPS: عبارت «کارت‌های دیو» در Rule Sheet یعنی Dealer cards.
# این Sweep فقط روی Dealer board اجرا می‌شود و هرگز کارت Player مقابل را هدف نمی‌گیرد.
# فقط یک Act می‌سازد و امتیاز Dealerهایی که Counter مستقیمش نیستند را یک‌جا می‌دهد.
	if (
		attack_type
		== CardBehavior.DealerAttackType.CHAINSAW_SWEEP
	):
		var defeated_dealer_count: int = 0

		for dealer_slot_id: int in DealerSlotID.all_slots():
			var dealer_card: CardInstance = \
				_get_dealer_card(
					state,
					dealer_slot_id
				)

			if dealer_card == null:
				continue

			if dealer_card.definition == null:
				continue

			# Chainsaw هر Dealer را می‌برد به‌جز Gestureای که در RPS
			# به Gesture خود Chainsaw می‌برد. مثال:
			# Scissors -> به‌جز Rock / Paper -> به‌جز Scissors / Rock -> به‌جز Paper.
			if (
				_compare_gestures(
					player_card.get_gesture(),
					dealer_card.get_gesture()
				)
				== BattleAct.Outcome.LOSS
			):
				continue

			defeated_dealer_count += 1

		var chainsaw_act := BattleAct.new()

		chainsaw_act.type = \
			BattleAct.Type.CHAINSAW_SWEEP

		chainsaw_act.attacker = player_card
		chainsaw_act.attacker_owner_id = player_id
		chainsaw_act.attacker_slot_id = player_slot_id

		chainsaw_act.dealer_attack_type = \
			CardBehavior.DealerAttackType.CHAINSAW_SWEEP

		if defeated_dealer_count > 0:
			chainsaw_act.attacker_outcome = \
				BattleAct.Outcome.WIN
		else:
			chainsaw_act.attacker_outcome = \
				BattleAct.Outcome.LOSS

		chainsaw_act.attacker_points = (
			state.rules.win_points
			* defeated_dealer_count
		)

		sequence.add_act(chainsaw_act)
		return

	# حمله معمولی یا Chainsaw
	var target_slots: Array[int] = []
	target_slots.assign(normal_dealer_slots)



	for dealer_slot_id: int in target_slots:
		var dealer_card: CardInstance = \
			_get_dealer_card(
				state,
				dealer_slot_id
			)

		if dealer_card == null:
			continue

		var act: BattleAct = \
			_create_player_vs_dealer_act(
				state,
				player_id,
				player_card,
				player_slot_id,
				dealer_card,
				dealer_slot_id
			)
		act.dealer_attack_type = attack_type
		sequence.add_act(act)



static func _add_side_lane_sequence(
	state: MatchState,
	sequence: BattleSequence,
	player_slot_id: int,
	dealer_slot_id: int
) -> void:
	var player_one_card: CardInstance = \
		state.player_one.board.get_card(
			player_slot_id
		)

	var player_two_card: CardInstance = \
		state.player_two.board.get_card(
			player_slot_id
		)

	var normal_targets: Array[int] = [
		dealer_slot_id
	]

	if not state.rush_mode_enabled:
		# حمله Player 1 به Dealer
		_add_dealer_attacks(
			state,
			sequence,
			1,
			player_one_card,
			player_slot_id,
			normal_targets
		)

		# حمله Player 2 به Dealer
		_add_dealer_attacks(
			state,
			sequence,
			2,
			player_two_card,
			player_slot_id,
			normal_targets
		)

static func _add_middle_row_sequence(
	state: MatchState,
	sequence: BattleSequence,
	first_middle_slot: int,
	second_middle_slot: int
) -> void:
	var middle_player_slots: Array[int] = [
		first_middle_slot,
		second_middle_slot
	]

	var normal_middle_targets: Array[int] = [
		DealerSlotID.Type.MIDDLE_0,
		DealerSlotID.Type.MIDDLE_1
	]

	if not state.rush_mode_enabled:
		# حمله کارت‌های وسط Player 1 به Dealer
		for player_slot_id: int in middle_player_slots:
			var player_one_card: CardInstance = \
				state.player_one.board.get_card(
					player_slot_id
				)

			_add_dealer_attacks(
				state,
				sequence,
				1,
				player_one_card,
				player_slot_id,
				normal_middle_targets
			)

		# حمله کارت‌های وسط Player 2 به Dealer
		for player_slot_id: int in middle_player_slots:
			var player_two_card: CardInstance = \
				state.player_two.board.get_card(
					player_slot_id
				)

			_add_dealer_attacks(
				state,
				sequence,
				2,
				player_two_card,
				player_slot_id,
				normal_middle_targets
			)

static func _column_slots_for(slot_id: int) -> Array[int]:
	match slot_id:
		SlotID.Type.FRONT_LEFT, SlotID.Type.BACK_LEFT:
			return [SlotID.Type.FRONT_LEFT, SlotID.Type.BACK_LEFT]
		SlotID.Type.FRONT_MIDDLE_0, SlotID.Type.BACK_MIDDLE_0:
			return [SlotID.Type.FRONT_MIDDLE_0, SlotID.Type.BACK_MIDDLE_0]
		SlotID.Type.FRONT_MIDDLE_1, SlotID.Type.BACK_MIDDLE_1:
			return [SlotID.Type.FRONT_MIDDLE_1, SlotID.Type.BACK_MIDDLE_1]
		SlotID.Type.FRONT_RIGHT, SlotID.Type.BACK_RIGHT:
			return [SlotID.Type.FRONT_RIGHT, SlotID.Type.BACK_RIGHT]
	return []


static func _pair_key(card_a: CardInstance, card_b: CardInstance) -> String:
	if card_a == null or card_b == null:
		return ""
	var low: int = mini(card_a.instance_id, card_b.instance_id)
	var high: int = maxi(card_a.instance_id, card_b.instance_id)
	return str(low) + ":" + str(high)


static func _existing_pvp_pairs(sequence: BattleSequence) -> Dictionary:
	var pairs: Dictionary = {}
	if sequence == null:
		return pairs
	for act: BattleAct in sequence.acts:
		if act == null or act.type != BattleAct.Type.PLAYER_VS_PLAYER:
			continue
		var key: String = _pair_key(act.attacker, act.defender)
		if not key.is_empty():
			pairs[key] = true
	return pairs


static func _is_taunt_card(card: CardInstance) -> bool:
	if card == null or card.definition == null:
		return false
	return card.definition.behavior is TauntBehavior


static func _lane_taunt_slots(player: PlayerState, lane: int) -> Array[int]:
	var result: Array[int] = []
	if player == null:
		return result

	for slot_id: int in SlotID.all_slots():
		if SlotID.get_lane(slot_id) != lane:
			continue

		var card: CardInstance = player.board.get_card(slot_id)
		if not _is_taunt_card(card):
			continue

		result.append(slot_id)

	return result


static func _select_taunt_slot(
	player: PlayerState,
	lane: int,
	protected_card: CardInstance
) -> int:
	var taunt_slots: Array[int] = _lane_taunt_slots(player, lane)
	if taunt_slots.is_empty():
		return -1

	# A Taunt never redirects a loss away from another Taunt. Taunts are the
	# protectors and must be allowed to take their own normal clash.
	if _is_taunt_card(protected_card):
		return -1

	# Prefer a Taunt that still has shields. If several Taunts exist, the normal
	# SlotID order keeps the result deterministic (front cards before back).
	for slot_id: int in taunt_slots:
		var taunt_card: CardInstance = player.board.get_card(slot_id)
		if taunt_card != null and taunt_card.shield_count > 0:
			return slot_id

	# Even with no shield left, the Taunt still intercepts and can take the loss
	# itself instead of the protected card.
	return taunt_slots[0]


static func _normal_pvp_target_slots(source_slot: int) -> Array[int]:
	# Side lanes fight the exact opposing slot. Middle cards preserve the game's
	# existing all-to-all rule inside their own front/back middle row.
	if source_slot in [
		SlotID.Type.FRONT_LEFT,
		SlotID.Type.BACK_LEFT,
		SlotID.Type.FRONT_RIGHT,
		SlotID.Type.BACK_RIGHT
	]:
		return [source_slot]
	if source_slot in [
		SlotID.Type.FRONT_MIDDLE_0,
		SlotID.Type.FRONT_MIDDLE_1
	]:
		return [SlotID.Type.FRONT_MIDDLE_0, SlotID.Type.FRONT_MIDDLE_1]
	if source_slot in [
		SlotID.Type.BACK_MIDDLE_0,
		SlotID.Type.BACK_MIDDLE_1
	]:
		return [SlotID.Type.BACK_MIDDLE_0, SlotID.Type.BACK_MIDDLE_1]
	return []


static func _add_pvp_pair_once(
	state: MatchState,
	sequence: BattleSequence,
	pairs: Dictionary,
	player_one_card: CardInstance,
	player_two_card: CardInstance,
	player_one_slot: int,
	player_two_slot: int
) -> void:
	if player_one_card == null or player_two_card == null:
		return

	var key: String = _pair_key(player_one_card, player_two_card)
	if key.is_empty() or pairs.has(key):
		return

	sequence.add_act(
		_create_player_vs_player_act(
			state,
			player_one_card,
			player_two_card,
			player_one_slot,
			player_two_slot
		)
	)
	pairs[key] = true


static func _add_all_player_pvp_clashes(
	state: MatchState,
	sequence: BattleSequence
) -> void:
	if state == null or sequence == null:
		return

	var pairs: Dictionary = {}

	# Start from every NORMAL PvP matchup. Taunt only replaces a matchup when
	# one card would beat the other by RPS. The losing card is removed from that
	# clash and its lane Taunt takes the winning attack instead.
	#
	# This is intentionally different from the old implementation where every
	# opposing card fought Taunt AND could still fight the original card.
	for player_one_slot: int in SlotID.all_slots():
		var player_one_card: CardInstance = \
			state.player_one.board.get_card(player_one_slot)
		if player_one_card == null:
			continue

		var normal_targets: Array[int] = \
			_normal_pvp_target_slots(player_one_slot)

		for player_two_slot: int in normal_targets:
			var player_two_card: CardInstance = \
				state.player_two.board.get_card(player_two_slot)
			if player_two_card == null:
				continue

			var lane: int = SlotID.get_lane(player_one_slot)
			var raw_outcome: int = _compare_gestures(
				player_one_card.get_gesture(),
				player_two_card.get_gesture()
			)

			# Player 1 is the winner: Player 2's losing card is protected by
			# Player 2's Taunt. The winner fights Taunt instead.
			if raw_outcome == BattleAct.Outcome.WIN:
				var player_two_taunt_slot: int = _select_taunt_slot(
					state.player_two,
					lane,
					player_two_card
				)
				if player_two_taunt_slot != -1:
					var player_two_taunt: CardInstance = \
						state.player_two.board.get_card(player_two_taunt_slot)
					_add_pvp_pair_once(
						state,
						sequence,
						pairs,
						player_one_card,
						player_two_taunt,
						player_one_slot,
						player_two_taunt_slot
					)
					continue

			# Player 2 is the winner: Player 1's losing card is protected by
			# Player 1's Taunt. The Player 2 winner fights that Taunt instead.
			if raw_outcome == BattleAct.Outcome.LOSS:
				var player_one_taunt_slot: int = _select_taunt_slot(
					state.player_one,
					lane,
					player_one_card
				)
				if player_one_taunt_slot != -1:
					var player_one_taunt: CardInstance = \
						state.player_one.board.get_card(player_one_taunt_slot)
					_add_pvp_pair_once(
						state,
						sequence,
						pairs,
						player_one_taunt,
						player_two_card,
						player_one_taunt_slot,
						player_two_slot
					)
					continue

			# Ties are not dangerous, and a normal clash involving Taunt itself
			# must remain normal. No protection is needed.
			_add_pvp_pair_once(
				state,
				sequence,
				pairs,
				player_one_card,
				player_two_card,
				player_one_slot,
				player_two_slot
			)


static func _append_bfg_column_wins(state: MatchState, sequence: BattleSequence) -> void:
	if state == null or sequence == null or state.rush_mode_enabled:
		return

	var pairs: Dictionary = _existing_pvp_pairs(sequence)
	var snapshot: Array[BattleAct] = []
	snapshot.assign(sequence.acts)
	var first_clash_seen: Dictionary = {}

	# BFG only checks the FIRST opposing player card it competes with. If that
	# first clash is not a win, later wins in the same battle do not trigger the
	# column sweep.
	for act: BattleAct in snapshot:
		if act == null or act.type != BattleAct.Type.PLAYER_VS_PLAYER:
			continue

		for side: int in [0, 1]:
			var bfg: CardInstance = act.attacker if side == 0 else act.defender
			if bfg == null or bfg.definition == null:
				continue
			if not (bfg.definition.behavior is BFGBehavior):
				continue
			if first_clash_seen.has(bfg.instance_id):
				continue
			first_clash_seen[bfg.instance_id] = true

			var outcome: int = act.attacker_outcome if side == 0 else act.defender_outcome
			if outcome != BattleAct.Outcome.WIN:
				continue

			var bfg_slot: int = act.attacker_slot_id if side == 0 else act.defender_slot_id
			var enemy_owner_id: int = act.defender_owner_id if side == 0 else act.attacker_owner_id
			if enemy_owner_id not in [1, 2]:
				continue

			var enemy: PlayerState = state.get_player(enemy_owner_id)
			if enemy == null:
				continue

			for enemy_slot: int in _column_slots_for(bfg_slot):
				var target: CardInstance = enemy.board.get_card(enemy_slot)
				if target == null:
					continue
				var key: String = _pair_key(bfg, target)
				if pairs.has(key):
					continue
				sequence.add_act(_create_forced_pvp_win_act(
					state,
					bfg,
					target,
					bfg_slot,
					enemy_slot
				))
				pairs[key] = true


static func _create_forced_pvp_win_act(
	state: MatchState,
	winner: CardInstance,
	loser: CardInstance,
	winner_slot: int,
	loser_slot: int
) -> BattleAct:
	var act := BattleAct.new()
	act.type = BattleAct.Type.PLAYER_VS_PLAYER
	var loser_outcome: int = BattleAct.Outcome.LOSS
	loser_outcome = OPHealerBehavior.try_prevent_loss(
		state, loser.owner_id, loser, loser_outcome
	)
	var winner_outcome: int = _opposite_outcome(loser_outcome)
	var hit_result: Dictionary = {}
	if winner_outcome == BattleAct.Outcome.WIN:
		hit_result = _apply_incoming_hits(loser, 1, loser_outcome, winner.is_hero())
		loser_outcome = int(hit_result.get("outcome", loser_outcome))
		winner_outcome = _opposite_outcome(loser_outcome)

	if winner.owner_id == 1:
		act.attacker = winner
		act.defender = loser
		act.attacker_owner_id = 1
		act.defender_owner_id = 2
		act.attacker_slot_id = winner_slot
		act.defender_slot_id = loser_slot
		act.attacker_outcome = winner_outcome
		act.defender_outcome = loser_outcome
		act.attacker_landed_hits = int(hit_result.get("landed_hits", 0))
		act.attacker_unshielded_hero_hits = int(hit_result.get("unshielded_hero_hits", 0))
		act.attacker_points = _hero_adjusted_points(
			state, winner_outcome, act.attacker_landed_hits, act.attacker_unshielded_hero_hits
		)
		act.defender_points = _points_for_outcome(state, loser_outcome)
	else:
		act.attacker = loser
		act.defender = winner
		act.attacker_owner_id = 1
		act.defender_owner_id = 2
		act.attacker_slot_id = loser_slot
		act.defender_slot_id = winner_slot
		act.attacker_outcome = loser_outcome
		act.defender_outcome = winner_outcome
		act.defender_landed_hits = int(hit_result.get("landed_hits", 0))
		act.defender_unshielded_hero_hits = int(hit_result.get("unshielded_hero_hits", 0))
		act.attacker_points = _points_for_outcome(state, loser_outcome)
		act.defender_points = _hero_adjusted_points(
			state, winner_outcome, act.defender_landed_hits, act.defender_unshielded_hero_hits
		)
	return act


static func _get_winning_hit_count(
	state: MatchState,
	winner: CardInstance
) -> int:
	if state == null or winner == null:
		return 1
	if not winner.is_hero_furious(state.turn_number):
		return 1
	var hero_def: HeroDefinition = winner.get_hero_definition()
	if hero_def != null and hero_def.hero_kind == HeroDefinition.HeroKind.ROSTAM:
		return 2
	return 1


static func _apply_incoming_hits(
	loser: CardInstance,
	hit_count: int,
	current_outcome: int,
	source_is_hero: bool = false
) -> Dictionary:
	var result: Dictionary = {
		"outcome": current_outcome,
		"landed_hits": 0,
		"unshielded_hero_hits": 0,
		"hero_health_damage": 0
	}
	if loser == null or current_outcome != BattleAct.Outcome.LOSS:
		return result

	hit_count = maxi(1, hit_count)
	result["landed_hits"] = hit_count

	# A temporary shield can be burned by ANY incoming loss: normal card,
	# Dealer, Hero or Special. Only a Hero-vs-Hero unshielded hit can reduce HP.
	var shield_hits: int = mini(loser.shield_count, hit_count)
	if shield_hits > 0:
		loser.shield_count -= shield_hits
		print(
			"SHIELD USED | card=",
			loser.definition.display_name if loser.definition != null else "Unknown",
			" | hits=",
			shield_hits,
			" | shields_left=",
			loser.shield_count
		)

	var unshielded_hits: int = hit_count - shield_hits
	if loser.is_hero():
		result["unshielded_hero_hits"] = unshielded_hits
		# Health itself is applied when this BattleAct resolves, after its attack
		# animation. source_is_hero only marks whether these hits are allowed to
		# become real Hero HP damage.
		if source_is_hero and unshielded_hits > 0:
			result["hero_health_damage"] = unshielded_hits

	# If every incoming hit was absorbed, the clash is neutralized. Otherwise
	# it remains a real loss for scoring/energy even when the attacker is a
	# normal card that cannot directly damage Hero HP.
	if unshielded_hits <= 0:
		result["outcome"] = BattleAct.Outcome.TIE
	else:
		result["outcome"] = BattleAct.Outcome.LOSS
	return result


static func _hero_adjusted_points(
	state: MatchState,
	outcome: int,
	landed_hits: int,
	unshielded_hero_hits: int
) -> int:
	if unshielded_hero_hits > 0 and outcome == BattleAct.Outcome.WIN:
		# Defeating an exposed Hero is always worth 15, even if Fury lands
		# multiple physical hits in the same clash.
		return 15
	var points: int = _points_for_outcome(state, outcome)
	if outcome == BattleAct.Outcome.WIN and landed_hits > 1:
		points *= landed_hits
	return points


static func _apply_afrasiab_active_score(
	state: MatchState,
	card: CardInstance,
	outcome: int,
	points: int
) -> int:
	if state == null or card == null:
		return points
	if not card.is_hero_afrasiab_active(state.turn_number):
		return points
	var hero_def: HeroDefinition = card.get_hero_definition()
	if hero_def == null or hero_def.hero_kind != HeroDefinition.HeroKind.AFRASIAB:
		return points
	if outcome == BattleAct.Outcome.TIE:
		return 3
	if outcome == BattleAct.Outcome.LOSS:
		return -2
	return points


static func _apply_behavior_to_outcome(
	state: MatchState,
	source_card: CardInstance,
	opponent_card: CardInstance,
	current_outcome: int
) -> int:
	if source_card == null:
		return current_outcome

	if source_card.definition == null:
		return current_outcome

	var behavior: CardBehavior = \
		source_card.definition.behavior

	if behavior == null:
		return current_outcome

	# DefenseBehavior initializes its shield at Start Combat. Actual shield
	# consumption is centralized in _apply_incoming_hits so Fury can consume
	# two charges correctly instead of one charge cancelling both attacks.
	if behavior is DefenseBehavior:
		return current_outcome

	return behavior.modify_battle_outcome(
		state,
		source_card,
		opponent_card,
		current_outcome
	)
