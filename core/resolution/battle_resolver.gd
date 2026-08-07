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

	var outcome: BattleAct.Outcome = \
		_compare_gestures(
			player_card.definition.gesture,
			dealer_card.definition.gesture
		)

	var player_card_is_disabled: bool = \
		DisableGestureBehavior.is_card_disabled(
			state,
			player_id,
			player_slot_id,
			player_card
		)

	# کارت Disableشده اجازه Win ندارد.
	if (
		player_card_is_disabled
		and outcome == BattleAct.Outcome.WIN
	):
		outcome = BattleAct.Outcome.TIE
	outcome = _apply_behavior_to_outcome(
		state,
		player_card,
		dealer_card,
		outcome
	)

	# Behavior ویژه نباید قانون Disabler را دور بزند.
	if (
		player_card_is_disabled
		and outcome == BattleAct.Outcome.WIN
	):
		outcome = BattleAct.Outcome.TIE

	# Shield روی نتیجه نهایی اعمال می‌شود.
	outcome = _apply_shield_to_outcome(
		player_card,
		outcome
	)

	act.attacker_outcome = outcome

	act.attacker_points = _points_for_outcome(
		state,
		outcome
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
		player_one_card.definition.gesture,
		player_two_card.definition.gesture
	)

	var player_two_outcome: int = _opposite_outcome(
		player_one_outcome
	)

	var player_one_is_disabled: bool = \
		DisableGestureBehavior.is_card_disabled(
			state,
			1,
			player_one_slot_id,
			player_one_card
		)

	var player_two_is_disabled: bool = \
		DisableGestureBehavior.is_card_disabled(
			state,
			2,
			player_two_slot_id,
			player_two_card
		)


	# اعمال Disabler روی Player 1
	if (
		player_one_is_disabled
		and player_one_outcome
		== BattleAct.Outcome.WIN
	):
		player_one_outcome = BattleAct.Outcome.TIE
		player_two_outcome = BattleAct.Outcome.TIE


	# اعمال Disabler روی Player 2
	if (
		player_two_is_disabled
		and player_two_outcome
		== BattleAct.Outcome.WIN
	):
		player_one_outcome = BattleAct.Outcome.TIE
		player_two_outcome = BattleAct.Outcome.TIE

	# Behavior کارت Player 1
	var modified_player_one_outcome: int = \
		_apply_behavior_to_outcome(
			state,
			player_one_card,
			player_two_card,
			player_one_outcome
		)

	if modified_player_one_outcome != player_one_outcome:
		player_one_outcome = modified_player_one_outcome
		player_two_outcome = _opposite_outcome(
			player_one_outcome
		)

	# Behavior کارت Player 2
	var modified_player_two_outcome: int = \
		_apply_behavior_to_outcome(
			state,
			player_two_card,
			player_one_card,
			player_two_outcome
		)

	if modified_player_two_outcome != player_two_outcome:
		player_two_outcome = modified_player_two_outcome
		player_one_outcome = _opposite_outcome(
			player_two_outcome
		)

	# بررسی نهایی Disabler بعد از تمام Behaviorها.
	if (
		player_one_is_disabled
		and player_one_outcome
		== BattleAct.Outcome.WIN
	):
		player_one_outcome = BattleAct.Outcome.TIE
		player_two_outcome = BattleAct.Outcome.TIE

	if (
		player_two_is_disabled
		and player_two_outcome
		== BattleAct.Outcome.WIN
	):
		player_one_outcome = BattleAct.Outcome.TIE
		player_two_outcome = BattleAct.Outcome.TIE

	# Shield کارت Player 1
	var player_one_after_shield: int = \
		_apply_shield_to_outcome(
			player_one_card,
			player_one_outcome
		)

	if player_one_after_shield != player_one_outcome:
		player_one_outcome = BattleAct.Outcome.TIE
		player_two_outcome = BattleAct.Outcome.TIE


	# Shield کارت Player 2
	var player_two_after_shield: int = \
		_apply_shield_to_outcome(
			player_two_card,
			player_two_outcome
		)

	if player_two_after_shield != player_two_outcome:
		player_one_outcome = BattleAct.Outcome.TIE
		player_two_outcome = BattleAct.Outcome.TIE



	act.attacker_outcome = player_one_outcome
	act.defender_outcome = player_two_outcome

	act.attacker_points = _points_for_outcome(
		state,
		player_one_outcome
	)

	act.defender_points = _points_for_outcome(
		state,
		player_two_outcome
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

# اره‌برقی دیگر برای هر کارت Dealer یک Act جدا نمی‌سازد.
# فقط یک Act می‌سازد و امتیاز کارت‌های غیر ROCK را یک‌جا می‌دهد.
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

			# اره‌برقی کارت ROCK را نمی‌برد.
			if (
				dealer_card.definition.gesture
				== CardGesture.Type.ROCK
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

	# مبارزه Player 1 و Player 2 با یکدیگر
	if (
		player_one_card != null
		and player_two_card != null
	):
		sequence.add_act(
			_create_player_vs_player_act(
				state,
				player_one_card,
				player_two_card,
				player_slot_id,
				player_slot_id
			)
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

	# Clash کارت‌های وسط دو بازیکن
	for player_one_slot_id: int in middle_player_slots:
		var player_one_card: CardInstance = \
			state.player_one.board.get_card(
				player_one_slot_id
			)

		if player_one_card == null:
			continue

		for player_two_slot_id: int in middle_player_slots:
			var player_two_card: CardInstance = \
				state.player_two.board.get_card(
					player_two_slot_id
				)

			if player_two_card == null:
				continue

			sequence.add_act(
				_create_player_vs_player_act(
					state,
					player_one_card,
					player_two_card,
					player_one_slot_id,
					player_two_slot_id
				)
			)
			
static func _apply_shield_to_outcome(
	card: CardInstance,
	current_outcome: int
) -> int:
	if card == null:
		return current_outcome

	# Shield فقط LOSS را متوقف می‌کند.
	if current_outcome != BattleAct.Outcome.LOSS:
		return current_outcome

	if card.shield_count <= 0:
		return current_outcome

	card.shield_count -= 1

	var card_name: String = "Unknown"

	if card.definition != null:
		card_name = card.definition.display_name

	print(
		"SHIELD USED | card=",
		card_name,
		" | shields_left=",
		card.shield_count
	)

	return BattleAct.Outcome.TIE

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

	return behavior.modify_battle_outcome(
		state,
		source_card,
		opponent_card,
		current_outcome
	)
