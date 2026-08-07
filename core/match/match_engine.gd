class_name MatchEngine
extends RefCounted

const BOARD_MOVE_MANA_COST: int = 1
var state: MatchState
var card_factory: CardFactory = CardFactory.new()
var active_battle_sequence: BattleSequence
var play_records_by_player: Dictionary = {
	1: [],
	2: []
}
func start_match(
	rules: MatchRules,
	player_one_deck: DeckDefinition,
	player_two_deck: DeckDefinition,
	dealer_deck: DeckDefinition
) -> MatchState:
	state = MatchState.new(rules)

	state.player_one.draw_pile = card_factory.build_deck(
		player_one_deck,
		1
	)

	state.player_two.draw_pile = card_factory.build_deck(
		player_two_deck,
		2
	)
	state.dealer.draw_pile = card_factory.build_deck(
		dealer_deck,
		0
	)

	DealerMover.deal_new_board(state.dealer)

	_run_dealer_enter_behaviors()

	_setup_player(state.player_one)
	_setup_player(state.player_two)

	state.turn_number = 1
	state.phase = MatchPhase.Type.MAIN

	return state

func _run_dealer_enter_behaviors() -> void:
	if state == null:
		return

	if state.dealer == null:
		return

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

		var dealer_behavior: DealerCardBehavior = \
			dealer_card.definition.dealer_behavior

		if dealer_behavior == null:
			continue

		dealer_behavior.on_enter_board(
			state,
			dealer_card,
			dealer_slot_id
		)



func _setup_player(
	player: PlayerState
) -> void:
	if player == null:
		return

	player.mana_capacity = \
		state.rules.starting_mana

	player.current_mana = \
		player.mana_capacity

	CardMover.draw_cards_to_hand(
		player,
		state.rules.starting_hand_size
	)

func play_card(
	player_id: int,
	card: CardInstance,
	slot_id: int
) -> bool:
	if state == null:
		return false

	if state.phase != MatchPhase.Type.MAIN:
		return false

	var player: PlayerState = state.get_player(
		player_id
	)

	if player == null or card == null:
		return false

	if player.is_ready:
		return false

	if card.definition == null:
		return false

	if card.owner_id != player_id:
		return false

	if not player.hand.has(card):
		return false

	if not SlotID.is_valid(slot_id):
		return false

	# برای قرارگرفتن در ردیف عقب،
	# کارت جلوی همان ستون باید وجود داشته باشد.
	if not _can_play_in_row_order(
		player,
		slot_id
	):
		print(
			"PLAY FAILED | matching front slot "
			+ "must be occupied first"
		)
		return false

	var mana_cost: int = card.definition.mana_cost

	if player.current_mana < mana_cost:
		return false

	var replaced_card: CardInstance = \
		player.board.get_card(slot_id)
	var board_before: Dictionary = \
		_snapshot_board_cards(player)
	# Slot اشغال است؛ باید شرایط Cover بررسی شود.
	if replaced_card != null:
		if replaced_card.definition == null:
			return false

		# کارت باید حداقل یک Turn از زمان چیده‌شدنش گذشته باشد.
# Turn ورود کارت و اولین Turn بعد از آن قابل Cover نیست.
		var turns_since_played: int = (
			state.turn_number
			- replaced_card.turn_played
		)

		if turns_since_played < 1:
			print(
				"COVER FAILED | target card must survive "
				+ "one full turn first"
			)
			return false

		var new_gesture: CardGesture.Type = \
			card.definition.gesture

		var old_gesture: CardGesture.Type = \
			replaced_card.definition.gesture

		if not CardGesture.can_cover(
			new_gesture,
			old_gesture
		):
			print(
				"COVER FAILED | ",
				CardGesture.Type.keys()[new_gesture],
				" cannot cover ",
				CardGesture.Type.keys()[old_gesture]
			)
			return false

	# اگر Slot اشغال بود، ابتدا کارت قدیمی Discard می‌شود.
	if replaced_card != null:
		var discarded_card: CardInstance = \
			CardMover.board_to_discard(
				player,
				slot_id
			)
		if discarded_card == null:
			push_error(
				"Cover failed: old card could not be discarded."
			)
			return false

		print(
			"CARD COVERED | old=",
			discarded_card.definition.display_name,
			" | new=",
			card.definition.display_name,
			" | slot=",
			slot_id
		)
	if not CardMover.hand_to_board(
		player,
		card,
		slot_id
	):
		return false

	# کارت از Hand دوباره وارد Board شده است.
	# افکت‌های یک‌بارمصرف برای این حضور جدید آماده می‌شوند.
	card.reset_for_board_entry()

	player.current_mana -= mana_cost
	card.turn_played = state.turn_number
	if card.definition.behavior != null:
		var play_context := CardBehaviorContext.new(
			self,
			state,
			card,
			player_id,
			slot_id,
			replaced_card
		)

		card.definition.behavior.on_played_to_board(
			play_context
		)
	_record_completed_play(
		player_id,
		card,
		slot_id,
		board_before
	)

	return true

func move_board_card(
	player_id: int,
	from_slot_id: int,
	to_slot_id: int
) -> bool:
	if state == null:
		return false

	if state.phase != MatchPhase.Type.MAIN:
		return false

	var player: PlayerState = state.get_player(
		player_id
	)

	if player == null:
		return false

	if player.is_ready:
		return false

	if not SlotID.is_valid(from_slot_id):
		return false

	if not SlotID.is_valid(to_slot_id):
		return false

	if from_slot_id == to_slot_id:
		return false

	# در هر Turn فقط یک بار امکان جابه‌جایی وجود دارد.
	if (
		player.board_move_used_turn
		== state.turn_number
	):
		print(
			"BOARD MOVE FAILED | already used this turn"
		)
		return false

	var moving_card: CardInstance = \
		player.board.get_card(
			from_slot_id
		)

	if not _can_move_in_row_order(
		player,
		from_slot_id,
		to_slot_id
	):
		print(
			"BOARD MOVE FAILED | invalid row order"
		)
		return false

	if player.current_mana < BOARD_MOVE_MANA_COST:
		print(
			"BOARD MOVE FAILED | not enough mana"
		)
		return false

	if moving_card == null:
		print(
			"BOARD MOVE FAILED | source slot is empty"
		)
		return false

	if moving_card.owner_id != player_id:
		print(
			"BOARD MOVE FAILED | card belongs to another player"
		)
		return false

	var replaced_card: CardInstance = \
		player.board.get_card(to_slot_id)

	# مقصد کارت دارد؛ همان قانون Cover عادی اجرا شود.
	if replaced_card != null:
		if moving_card.definition == null:
			return false

		if replaced_card.definition == null:
			return false

		var turns_since_played: int = (
			state.turn_number
			- replaced_card.turn_played
		)

		if turns_since_played < 1:
			print(
				"BOARD COVER FAILED | target card "
				+ "must survive one full turn first"
			)
			return false

		if not CardGesture.can_cover(
			moving_card.definition.gesture,
			replaced_card.definition.gesture
		):
			print(
				"BOARD COVER FAILED | moving card "
				+ "does not beat destination"
			)
			return false

		# دقیقاً مثل Cover عادی:
		# کارت مقصد از Board خارج و Discard می‌شود.
		var discarded_card: CardInstance = \
			CardMover.board_to_discard(
				player,
				to_slot_id
			)

		if discarded_card == null:
			return false

	var moved: bool = player.board.move_card(
		from_slot_id,
		to_slot_id
	)

	if not moved:
		print(
			"BOARD MOVE FAILED | BoardState rejected move"
		)
		return false

	player.current_mana -= \
		BOARD_MOVE_MANA_COST

	player.board_move_used_turn = \
		state.turn_number

	print(
		"BOARD CARD MOVED | player=",
		player_id,
		" | card=",
		moving_card.definition.display_name,
		" | from=",
		from_slot_id,
		" | to=",
		to_slot_id,
		" | mana_left=",
		player.current_mana
	)

	return true


func _start_new_turn_for_player(
	player: PlayerState
) -> void:
	if player == null:
		return

	# تمام کارت‌های باقی‌مانده Hand قبلی دور ریخته می‌شوند.
	var discarded_hand_count: int = \
		CardMover.discard_hand(player)

	player.mana_capacity = mini(
		player.mana_capacity
			+ state.rules.mana_gain_per_turn,
		state.rules.maximum_mana
	)

	player.current_mana = \
		player.mana_capacity

	# Hand جدید ساخته می‌شود.
	var drawn_cards: Array[CardInstance] = \
		CardMover.draw_cards_to_hand(
			player,
			state.rules.cards_drawn_per_turn
		)

	print(
		"NEW TURN HAND | player=",
		player.player_id,
		" | hand_discarded=",
		discarded_hand_count,
		" | drawn=",
		drawn_cards.size(),
		" | draw=",
		player.draw_pile.size(),
		" | discard=",
		player.discard_pile.size(),
		" | reserve=",
		player.reserve_pile.size()
	)


func _run_start_combat_behaviors() -> void:
	if state == null:
		return

	# اول یک Snapshot می‌گیریم تا تغییر Board هنگام اجرای
	# Collector باعث خراب‌شدن Loop نشود.
	var behavior_cards: Array[Dictionary] = []

	for player_id in [1, 2]:
		var player: PlayerState = state.get_player(
			player_id
		)

		if player == null:
			continue

		for slot_id: int in SlotID.all_slots():
			var card: CardInstance = player.board.get_card(
				slot_id
			)

			if card == null:
				continue

			if card.definition == null:
				continue

			if card.definition.behavior == null:
				continue

			behavior_cards.append({
				"player_id": player_id,
				"slot_id": slot_id,
				"card": card
			})

	for entry: Dictionary in behavior_cards:
		var player_id: int = int(
			entry["player_id"]
		)

		var slot_id: int = int(
			entry["slot_id"]
		)

		var card: CardInstance = \
			entry["card"] as CardInstance

		if card == null:
			continue

		if card.definition == null:
			continue

		if card.definition.behavior == null:
			continue

		var context := CardBehaviorContext.new(
			self,
			state,
			card,
			player_id,
			slot_id
		)

		card.definition.behavior.on_start_combat(
			context
		)


func set_player_ready(player_id: int) -> bool:
	if state == null:
		return false

	if state.phase != MatchPhase.Type.MAIN:
		return false

	var player: PlayerState = state.get_player(player_id)

	if player == null:
		return false

	if player.is_ready:
		return false

	player.is_ready = true
	return true

func are_both_players_ready() -> bool:
	if state == null:
		return false

	return (
		state.player_one.is_ready
		and state.player_two.is_ready
	)


func begin_combat() -> BattleSequence:
	if state == null:
		return null

	if state.phase != MatchPhase.Type.MAIN:
			return null

	if not are_both_players_ready():
		return null

	state.phase = MatchPhase.Type.BATTLE
	# همه Behaviorهای Start Combat قبل از ساخت صف اجرا می‌شوند.
	_run_start_combat_behaviors()
	if _check_score_victory():
		return BattleSequence.new()
	active_battle_sequence = \
		BattleResolver.build_sequence(state)

	return active_battle_sequence

func apply_battle_act(
	act: BattleAct
) -> bool:
	if state == null:
		return false

	if act == null:
		return false

	if state.phase != MatchPhase.Type.BATTLE:
		return false

	if act.resolved:
		return false

	var attacker_player: PlayerState = \
		state.get_player(
			act.attacker_owner_id
		)

	if attacker_player != null:
		attacker_player.score += \
			act.attacker_points

	if act.defender_owner_id != 0:
		var defender_player: PlayerState = \
			state.get_player(
				act.defender_owner_id
			)

		if defender_player != null:
			defender_player.score += \
				act.defender_points

	act.resolved = true

	var game_ended: bool = \
		_check_score_victory()

	print(
		"VICTORY CHECK | P1=",
		state.player_one.score,
		" | P2=",
		state.player_two.score,
		" | difference=",
		abs(
			state.player_one.score
			- state.player_two.score
		),
		" | target=",
		state.rules.winning_score_difference,
		" | ended=",
		game_ended
	)

	return true


func _get_card_behavior(
	card: CardInstance
) -> CardBehavior:
	if card == null:
		return null

	if card.definition == null:
		return null

	return card.definition.behavior


func _card_destroys_defeated_player(
	card: CardInstance
) -> bool:
	var behavior: CardBehavior = \
		_get_card_behavior(card)

	if behavior == null:
		return false

	return behavior.destroys_defeated_player_card()


func _card_expires_after_combat(
	card: CardInstance
) -> bool:
	var behavior: CardBehavior = \
		_get_card_behavior(card)

	if behavior == null:
		return false

	return behavior.expires_after_combat()


func _send_board_card_to_reserve(
	player_id: int,
	card: CardInstance,
	reason: String
) -> bool:
	if card == null:
		return false

	var player: PlayerState = state.get_player(
		player_id
	)

	if player == null:
		return false

	var slot_id: int = card.current_slot

	if not SlotID.is_valid(slot_id):
		return false

	if not _can_play_in_row_order(
		player,
		slot_id
	):
		print(
			"PLAY FAILED | front row must be full "
			+ "before using the back row"
		)
		return false

	var replaced_card: CardInstance = \
		player.board.get_card(slot_id)
	# مطمئن می‌شویم همان CardInstance هنوز در همان Slot است.
	if player.board.get_card(slot_id) != card:
		return false

	var removed_card: CardInstance = \
		CardMover.board_to_reserve(
			player,
			slot_id
		)

	if removed_card == null:
		return false

	print(
		reason,
		" | player=",
		player_id,
		" | card=",
		removed_card.definition.display_name,
		" | slot=",
		slot_id
	)

	return true


func _resolve_killer_cards() -> void:
	if state == null:
		return

	if active_battle_sequence == null:
		return

	# کارت‌هایی که توسط Killer شکست خورده‌اند.
	var defeated_targets: Array[Dictionary] = []

	# جلوگیری از ثبت دوباره یک CardInstance.
	var defeated_instance_ids: Dictionary = {}

	for act: BattleAct in active_battle_sequence.acts:
		if act == null:
			continue

		if not act.resolved:
			continue

		# Killer فقط کارت Player مقابل را می‌کشد.
		# نتیجه مقابل Dealer باعث حذف Dealer نمی‌شود.
		if act.type != BattleAct.Type.PLAYER_VS_PLAYER:
			continue

		# Attacker برنده شده و Killer است.
		if (
			act.attacker_outcome
			== BattleAct.Outcome.WIN
			and _card_destroys_defeated_player(
				act.attacker
			)
			and act.defender != null
		):
			if not defeated_instance_ids.has(
				act.defender.instance_id
			):
				defeated_instance_ids[
					act.defender.instance_id
				] = true

				defeated_targets.append({
					"player_id":
						act.defender_owner_id,
					"card":
						act.defender
				})

		# Defender برنده شده و Killer است.
		if (
			act.defender_outcome
			== BattleAct.Outcome.WIN
			and _card_destroys_defeated_player(
				act.defender
			)
			and act.attacker != null
		):
			if not defeated_instance_ids.has(
				act.attacker.instance_id
			):
				defeated_instance_ids[
					act.attacker.instance_id
				] = true

				defeated_targets.append({
					"player_id":
						act.attacker_owner_id,
					"card":
						act.attacker
				})

	# اول کارت‌هایی که Killer شکست داده حذف می‌شوند.
	for target: Dictionary in defeated_targets:
		var target_player_id: int = int(
			target["player_id"]
		)

		var target_card: CardInstance = \
			target["card"] as CardInstance

		_send_board_card_to_reserve(
			target_player_id,
			target_card,
			"KILLER DESTROYED TARGET"
		)

	# بعد Snapshot تمام Killerهای باقی‌مانده را می‌گیریم.
	var expiring_killers: Array[Dictionary] = []

	for player_id: int in [1, 2]:
		var player: PlayerState = state.get_player(
			player_id
		)

		if player == null:
			continue

		for slot_id: int in SlotID.all_slots():
			var card: CardInstance = \
				player.board.get_card(slot_id)

			if card == null:
				continue

			if not _card_expires_after_combat(card):
				continue

			expiring_killers.append({
				"player_id": player_id,
				"card": card
			})

	# تمام Killerها، چه برده باشند چه نه، از Board خارج می‌شوند.
	for killer_entry: Dictionary in expiring_killers:
		var killer_player_id: int = int(
			killer_entry["player_id"]
		)

		var killer_card: CardInstance = \
			killer_entry["card"] as CardInstance

		_send_board_card_to_reserve(
			killer_player_id,
			killer_card,
			"KILLER EXPIRED"
		)


func finish_combat() -> bool:
	if state == null:
		return false

	if state.phase != MatchPhase.Type.BATTLE:
		return false

	state.phase = MatchPhase.Type.CLEANUP

	# نتیجه تمام Clashها بررسی می‌شود.
	# اهداف شکست‌خورده و خود Killerها وارد Reserve می‌شوند.
	_resolve_killer_cards()

	var dealer_ready: bool = \
		DealerMover.deal_new_board(
			state.dealer
		)

	if not dealer_ready:
		push_error(
			"Dealer could not deal a new board."
		)

		state.phase = MatchPhase.Type.GAME_OVER
		return false

	# کارت‌های Dealer وارد زمین شده‌اند.
	# قدرت آن‌ها قبل از شروع چیدن اجرا می‌شود.
	_run_dealer_enter_behaviors()

	state.turn_number += 1

	_start_new_turn_for_player(
		state.player_one
	)

	_start_new_turn_for_player(
		state.player_two
	)

	state.player_one.is_ready = false
	state.player_two.is_ready = false


	state.phase = MatchPhase.Type.MAIN

	return true


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


func _can_play_in_row_order(
	player: PlayerState,
	target_slot_id: int
) -> bool:
	if player == null:
		return false

	var required_front_slot: int = \
		_get_required_front_slot(
			target_slot_id
		)

	# مقصد یکی از Slotهای جلو است.
	if required_front_slot == -1:
		return true

	# Slot عقب فقط وقتی قابل استفاده است
	# که Slot جلوی همان ستون کارت داشته باشد.
	return (
		player.board.get_card(
			required_front_slot
		) != null
	)


func _can_move_in_row_order(
	player: PlayerState,
	from_slot_id: int,
	to_slot_id: int
) -> bool:
	if player == null:
		return false

	# اگر از ردیف جلو حرکت می‌کنیم و پشت همان ستون
	# کارت وجود دارد، اجازه نداریم جلوی آن را خالی کنیم.
	var matching_back_slot: int = \
		_get_matching_back_slot(
			from_slot_id
		)

	if (
		matching_back_slot != -1
		and player.board.get_card(
			matching_back_slot
		) != null
	):
		return false

	var required_front_slot: int = \
		_get_required_front_slot(
			to_slot_id
		)

	# حرکت به ردیف جلو آزاد است.
	if required_front_slot == -1:
		return true

	# نمی‌توان همان کارت جلویی را به پشت خودش منتقل کرد؛
	# چون بعد از حرکت Slot جلو خالی می‌شود.
	if from_slot_id == required_front_slot:
		return false

	# مقصد عقب فقط با وجود کارت جلوی همان ستون باز است.
	return (
		player.board.get_card(
			required_front_slot
		) != null
	)


func clear_play_records(
	player_id: int
) -> void:
	play_records_by_player[player_id] = []


func consume_play_records(
	player_id: int
) -> Array[CardPlayRecord]:
	var result: Array[CardPlayRecord] = []

	var stored_records: Array = \
		play_records_by_player.get(
			player_id,
			[]
		)

	for raw_record: Variant in stored_records:
		var record: CardPlayRecord = \
			raw_record as CardPlayRecord

		if record != null:
			result.append(record)

	play_records_by_player[player_id] = []

	return result


func _snapshot_board_cards(
	player: PlayerState
) -> Dictionary:
	var result: Dictionary = {}

	if player == null:
		return result

	for slot_id: int in SlotID.all_slots():
		var card: CardInstance = \
			player.board.get_card(slot_id)

		if card == null:
			continue

		result[card.instance_id] = card

	return result


func _is_card_still_on_board(
	player: PlayerState,
	target_card: CardInstance
) -> bool:
	if player == null:
		return false

	if target_card == null:
		return false

	for slot_id: int in SlotID.all_slots():
		if (
			player.board.get_card(slot_id)
			== target_card
		):
			return true

	return false


func _record_completed_play(
	player_id: int,
	played_card: CardInstance,
	slot_id: int,
	board_before: Dictionary
) -> void:
	var player: PlayerState = \
		state.get_player(player_id)

	if player == null:
		return

	var record := CardPlayRecord.new()

	record.card = played_card
	record.owner_id = player_id
	record.slot_id = slot_id

	for raw_card: Variant in board_before.values():
		var previous_card: CardInstance = \
			raw_card as CardInstance

		if previous_card == null:
			continue

		if not _is_card_still_on_board(
			player,
			previous_card
		):
			record.removed_cards.append(
				previous_card
			)

	var stored_records: Array = \
		play_records_by_player.get(
			player_id,
			[]
		)

	stored_records.append(record)

	play_records_by_player[player_id] = \
		stored_records


func _check_score_victory() -> bool:
	if state == null:
		return false

	if state.rules == null:
		return false

	if state.player_one == null:
		return false

	if state.player_two == null:
		return false

	var difference: int = (
		state.player_one.score
		- state.player_two.score
	)

	var required_difference: int = \
		state.rules.winning_score_difference

	if abs(difference) < required_difference:
		return false

	state.winner_id = 1 if difference > 0 else 2
	state.phase = MatchPhase.Type.GAME_OVER

	print("")
	print("========== GAME OVER ==========")
	print("WINNER ID: ", state.winner_id)
	print("PLAYER 1 SCORE: ", state.player_one.score)
	print("PLAYER 2 SCORE: ", state.player_two.score)
	print("DIFFERENCE: ", abs(difference))

	return true
