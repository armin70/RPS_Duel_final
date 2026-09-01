class_name MatchEngine
extends RefCounted

const BOARD_MOVE_MANA_COST: int = 1
const ENERGY_PER_BAR: int = 15
const MAX_ENERGY_BARS: int = 4
const MAX_ENERGY_POINTS: int = ENERGY_PER_BAR * MAX_ENERGY_BARS


func get_board_move_mana_cost() -> int:
	if state != null and state.rush_mode_enabled:
		return 0

	return BOARD_MOVE_MANA_COST


func get_board_move_mana_cost_for_card(
	player_id: int,
	card: CardInstance
) -> int:
	return get_board_move_mana_cost()


func _get_hero_move_limit(card: CardInstance) -> int:
	if card == null or not card.is_hero():
		return 0
	return 1


func _can_hero_move_this_turn(card: CardInstance) -> bool:
	if card == null or not card.is_hero():
		return false
	if state != null and card.is_hero_rooted(state.turn_number):
		return false
	return card.hero_moves_this_turn < _get_hero_move_limit(card)
var state: MatchState
var card_factory: CardFactory = CardFactory.new()
var active_battle_sequence: BattleSequence
var play_records_by_player: Dictionary = {
	1: [],
	2: []
}
# Cards removed by the most recent Rush unused-mana penalty. The 3D
# controller reads this after finish_combat() so it can animate the OLD hand
# before rebuilding the next-turn hand visuals.
var last_rush_penalty_cards: Dictionary = {
	1: [],
	2: []
}

# Exact CardInstance references that lost at least one direct PvP clash in the
# current Rush combat. This snapshot is captured immediately after the battle
# sequence is built, before presentation/animation can touch any combat state.
var rush_pvp_loser_snapshot: Dictionary = {
	1: [],
	2: []
}
func start_match(
	rules: MatchRules,
	player_one_deck: DeckDefinition,
	player_two_deck: DeckDefinition,
	dealer_deck: DeckDefinition,
	rush_mode_enabled: bool = false
) -> MatchState:
	state = MatchState.new(rules)
	state.rush_mode_enabled = rush_mode_enabled

	state.player_one.draw_pile = card_factory.build_deck(
		player_one_deck,
		1
	)

	state.player_two.draw_pile = card_factory.build_deck(
		player_two_deck,
		2
	)
	if not state.rush_mode_enabled:
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

	# Dealer effects may remove a temporary Hero protector. Restore the Hero
	# before applying normal front-row promotion.
	_restore_missing_guarded_heroes()
	_normalize_all_player_front_rows()


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

# =========================================================
# Hero system
# =========================================================

func can_place_hero_at_slot(player_id: int, slot_id: int) -> bool:
	if state == null or not SlotID.is_valid(slot_id):
		return false
	var player: PlayerState = state.get_player(player_id)
	if player == null or player.hero != null:
		return false
	if not player.board.is_slot_empty(slot_id):
		return false
	# Hero setup now follows the same front/back placement rule as normal cards.
	return _can_play_in_row_order(player, slot_id)


func place_hero(
	player_id: int,
	hero_definition: HeroDefinition,
	slot_id: int
) -> CardInstance:
	if state == null or hero_definition == null:
		return null
	if not can_place_hero_at_slot(player_id, slot_id):
		return null

	var player: PlayerState = state.get_player(player_id)

	var hero: CardInstance = card_factory.create_card(
		hero_definition,
		player_id
	)
	hero.zone = CardZone.Type.BOARD
	# Hero setup now follows normal Cover timing too: it cannot be covered on
	# the same turn it first enters the board.
	hero.turn_played = state.turn_number
	hero.hero_revealed = false
	hero.hero_max_health = maxi(1, hero_definition.starting_health)
	hero.hero_health = hero.hero_max_health
	hero.shields_initialized = true
	hero.shield_count = maxi(0, hero_definition.starting_shields)

	if not player.board.place_card(slot_id, hero):
		return null

	player.hero = hero
	print(
		"HERO PLACED | player=", player_id,
		" | hero=", hero_definition.display_name,
		" | slot=", slot_id,
		" | hp=", hero.hero_health, "/", hero.hero_max_health,
		" | shields=", hero.shield_count
	)
	return hero


func reveal_all_heroes() -> bool:
	if state == null:
		return false

	var changed: bool = false
	for player_id: int in [1, 2]:
		var player: PlayerState = state.get_player(player_id)
		if player == null or player.hero == null:
			continue
		if player.hero.hero_revealed:
			continue
		player.hero.hero_revealed = true
		changed = true

	return changed


func are_heroes_revealed() -> bool:
	if state == null:
		return false

	var found_hero: bool = false
	for player_id: int in [1, 2]:
		var player: PlayerState = state.get_player(player_id)
		if player == null or player.hero == null:
			continue
		found_hero = true
		if not player.hero.hero_revealed:
			return false

	return found_hero


func can_activate_hero_active(player_id: int) -> bool:
	if state == null or state.phase != MatchPhase.Type.MAIN:
		return false
	var player: PlayerState = state.get_player(player_id)
	if player == null or player.is_ready or player.hero == null:
		return false
	var hero: CardInstance = player.hero
	if hero.zone != CardZone.Type.BOARD:
		return false
	if not SlotID.is_valid(hero.current_slot):
		return false
	if player.board.get_card(hero.current_slot) != hero:
		return false
	if not hero.hero_revealed:
		return false
	if hero.hero_active_used_turn == state.turn_number:
		return false
	var hero_def: HeroDefinition = hero.get_hero_definition()
	if hero_def == null:
		return false
	# Tahmineh's shield Active Roots her for the whole turn. If she already
	# moved this turn, the Active is no longer legal.
	if (
		hero_def.hero_kind == HeroDefinition.HeroKind.TAHMINEH
		and hero.hero_moves_this_turn > 0
	):
		return false
	return player.current_mana >= hero_def.active_mana_cost


func activate_hero_active(player_id: int) -> bool:
	if not can_activate_hero_active(player_id):
		return false

	var player: PlayerState = state.get_player(player_id)
	var hero: CardInstance = player.hero
	var hero_def: HeroDefinition = hero.get_hero_definition()
	player.current_mana -= hero_def.active_mana_cost
	hero.hero_active_used_turn = state.turn_number

	match hero_def.hero_kind:
		HeroDefinition.HeroKind.ROSTAM:
			hero.hero_fury_turn = state.turn_number
			hero.hero_sleep_turn = state.turn_number + 1
		HeroDefinition.HeroKind.TAHMINEH:
			hero.shield_count += 1
			hero.hero_root_turn = state.turn_number
		HeroDefinition.HeroKind.AFRASIAB:
			hero.hero_afrasiab_active_turn = state.turn_number

	print(
		"HERO ACTIVE | player=", player_id,
		" | hero=", hero_def.display_name,
		" | active=", hero_def.active_title,
		" | mana_left=", player.current_mana
	)
	return true


func _queue_tahmineh_free_paper(
	_player_id: int,
	_hero: CardInstance
) -> void:
	# Hero passives are currently disabled.
	return


func _apply_hero_battle_metadata(_act: BattleAct) -> void:
	# Hero passives are currently disabled. Active scoring is resolved directly
	# in BattleResolver so presentation order cannot change the result.
	return


func _is_guard_card_for_hero(
	player: PlayerState,
	card: CardInstance
) -> bool:
	if player == null or card == null or player.hero == null:
		return false
	var hero: CardInstance = player.hero
	return (
		hero.is_hero_guarded()
		and hero.hero_guard_card_instance_id == card.instance_id
		and hero.current_slot == card.current_slot
	)


func _restore_guarded_hero_if_protector_missing(
	player: PlayerState
) -> bool:
	if player == null or player.hero == null:
		return false
	var hero: CardInstance = player.hero
	if not hero.is_hero_guarded():
		return false
	var slot_id: int = hero.current_slot
	if not SlotID.is_valid(slot_id):
		hero.clear_hero_guard()
		return false
	var protector: CardInstance = player.board.get_card(slot_id)
	if (
		protector != null
		and protector.instance_id == hero.hero_guard_card_instance_id
	):
		return false

	# The guard card was moved/discarded/destroyed by another rule. As soon as
	# the slot becomes free the persistent Hero resurfaces there.
	if player.board.is_slot_empty(slot_id):
		hero.clear_hero_guard()
		hero.turn_played = state.turn_number
		player.board.place_card(slot_id, hero)
		print("HERO GUARD BROKEN | hero=", hero.definition.display_name)
		return true

	return false


func _restore_missing_guarded_heroes() -> void:
	if state == null:
		return
	_restore_guarded_hero_if_protector_missing(state.player_one)
	_restore_guarded_hero_if_protector_missing(state.player_two)


func _expire_hero_guards() -> void:
	if state == null:
		return

	for player_id: int in [1, 2]:
		var player: PlayerState = state.get_player(player_id)
		if player == null or player.hero == null:
			continue
		var hero: CardInstance = player.hero
		if not hero.is_hero_guarded():
			continue
		if hero.hero_guard_turn != state.turn_number:
			continue

		var slot_id: int = hero.current_slot
		if not SlotID.is_valid(slot_id):
			hero.clear_hero_guard()
			continue

		var protector: CardInstance = player.board.get_card(slot_id)
		if (
			protector != null
			and protector.instance_id == hero.hero_guard_card_instance_id
		):
			CardMover.board_to_reserve(player, slot_id)

		if player.board.is_slot_empty(slot_id):
			hero.clear_hero_guard()
			hero.turn_played = state.turn_number
			player.board.place_card(slot_id, hero)
			print(
				"HERO GUARD EXPIRED | hero=",
				hero.definition.display_name,
				" | slot=",
				slot_id
			)


# =========================================================
# Front-first board placement
# =========================================================

func resolve_play_slot(
	player_id: int,
	requested_slot_id: int
) -> int:
	if state == null:
		return -1

	if not SlotID.is_valid(requested_slot_id):
		return -1

	var player: PlayerState = state.get_player(
		player_id
	)

	if player == null:
		return -1

	# Dropping directly on an occupied card remains an explicit Cover attempt.
	# Auto-placement only redirects EMPTY destinations.
	if player.board.get_card(requested_slot_id) != null:
		return requested_slot_id

	match SlotID.get_lane(requested_slot_id):
		SlotID.Lane.LEFT:
			if player.board.is_slot_empty(
				SlotID.Type.FRONT_LEFT
			):
				return SlotID.Type.FRONT_LEFT

			return requested_slot_id

		SlotID.Lane.RIGHT:
			if player.board.is_slot_empty(
				SlotID.Type.FRONT_RIGHT
			):
				return SlotID.Type.FRONT_RIGHT

			return requested_slot_id

		SlotID.Lane.MIDDLE:
			# Middle placement is side-selectable again. FRONT_MIDDLE_0 and
			# FRONT_MIDDLE_1 are two distinct targets, so dropping on one side
			# never redirects the card to the other side. Back remains front-first
			# only within the exact middle sub-column the player selected.
			match requested_slot_id:
				SlotID.Type.BACK_MIDDLE_0:
					if player.board.is_slot_empty(
						SlotID.Type.FRONT_MIDDLE_0
					):
						return SlotID.Type.FRONT_MIDDLE_0

				SlotID.Type.BACK_MIDDLE_1:
					if player.board.is_slot_empty(
						SlotID.Type.FRONT_MIDDLE_1
					):
						return SlotID.Type.FRONT_MIDDLE_1

			return requested_slot_id

	return requested_slot_id


func _promote_back_to_front(
	player: PlayerState,
	front_slot_id: int,
	back_slot_id: int
) -> bool:
	if player == null:
		return false

	if not player.board.is_slot_empty(front_slot_id):
		return false

	var card: CardInstance = player.board.get_card(
		back_slot_id
	)

	if card == null:
		return false
	var moved: bool = player.board.move_card(
		back_slot_id,
		front_slot_id
	)

	if moved:
		print(
			"AUTO FRONT PROMOTION | player=",
			player.player_id,
			" | card=",
			card.definition.display_name if card.definition != null else "Card",
			" | from=",
			back_slot_id,
			" | to=",
			front_slot_id
		)

	return moved


func _normalize_player_front_rows(
	player: PlayerState
) -> void:
	if player == null:
		return

	# Side lanes keep their original one-to-one promotion behavior.
	_promote_back_to_front(
		player,
		SlotID.Type.FRONT_LEFT,
		SlotID.Type.BACK_LEFT
	)
	_promote_back_to_front(
		player,
		SlotID.Type.FRONT_RIGHT,
		SlotID.Type.BACK_RIGHT
	)

	# Middle row: first preserve the exact front/back pairing on BOTH sides.
	# Doing both exact checks before fallback matters when both front slots are
	# empty: a BACK_MIDDLE_1 card should prefer FRONT_MIDDLE_1, not get stolen
	# early by FRONT_MIDDLE_0's fallback.
	_promote_back_to_front(
		player,
		SlotID.Type.FRONT_MIDDLE_0,
		SlotID.Type.BACK_MIDDLE_0
	)
	_promote_back_to_front(
		player,
		SlotID.Type.FRONT_MIDDLE_1,
		SlotID.Type.BACK_MIDDLE_1
	)

	# If a middle Front slot is still empty after its exact-behind check,
	# allow the remaining card from the other middle Back slot to advance.
	if player.board.is_slot_empty(SlotID.Type.FRONT_MIDDLE_0):
		_promote_back_to_front(
			player,
			SlotID.Type.FRONT_MIDDLE_0,
			SlotID.Type.BACK_MIDDLE_1
		)

	if player.board.is_slot_empty(SlotID.Type.FRONT_MIDDLE_1):
		_promote_back_to_front(
			player,
			SlotID.Type.FRONT_MIDDLE_1,
			SlotID.Type.BACK_MIDDLE_0
		)


func _normalize_all_player_front_rows() -> void:
	if state == null:
		return

	_normalize_player_front_rows(state.player_one)
	_normalize_player_front_rows(state.player_two)


# =========================================================
# Rush sacrifice / transform
# =========================================================

func can_rush_transform_card(
	player_id: int,
	target_card: CardInstance
) -> bool:
	if state == null or not state.rush_mode_enabled:
		return false

	if state.phase != MatchPhase.Type.MAIN:
		return false

	var player: PlayerState = state.get_player(player_id)
	if player == null or player.is_ready or target_card == null:
		return false

	if target_card.owner_id != player_id:
		return false

	if target_card.zone != CardZone.Type.BOARD:
		return false
	if target_card.is_hero():
		return false

	var current_gesture: CardGesture.Type = target_card.get_gesture()
	if current_gesture not in [
		CardGesture.Type.ROCK,
		CardGesture.Type.PAPER,
		CardGesture.Type.SCISSORS
	]:
		return false

	return not get_rush_sacrifice_candidates(
		player_id,
		target_card
	).is_empty()


func get_rush_sacrifice_candidates(
	player_id: int,
	target_card: CardInstance
) -> Array[CardInstance]:
	var result: Array[CardInstance] = []

	if state == null:
		return result

	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return result

	for card: CardInstance in player.board.get_occupied_cards():
		if card == null or card == target_card or card.is_hero():
			continue
		result.append(card)

	return result


func apply_rush_transform(
	player_id: int,
	target_card: CardInstance,
	new_gesture: CardGesture.Type
) -> CardInstance:
	if not can_rush_transform_card(player_id, target_card):
		return null

	if new_gesture not in [
		CardGesture.Type.ROCK,
		CardGesture.Type.PAPER,
		CardGesture.Type.SCISSORS
	]:
		return null

	if target_card.get_gesture() == new_gesture:
		return null

	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return null

	var candidates: Array[CardInstance] = \
		get_rush_sacrifice_candidates(player_id, target_card)

	if candidates.is_empty():
		return null

	# The player chooses the target type. Only the payment card is random.
	var sacrifice_card: CardInstance = candidates.pick_random()
	if sacrifice_card == null:
		return null

	var sacrifice_slot: int = sacrifice_card.current_slot
	if not SlotID.is_valid(sacrifice_slot):
		return null

	var removed_card: CardInstance = CardMover.board_to_removed(
		player,
		sacrifice_slot
	)
	if removed_card == null:
		return null

	target_card.set_gesture_override(new_gesture)

	# Removing a Front card may expose a Back card. Keep the normal promotion
	# rules after the sacrifice payment is removed.
	_normalize_player_front_rows(player)

	print(
		"RUSH TRANSFORM | player=",
		player_id,
		" | target=",
		target_card.definition.display_name
			if target_card.definition != null else "Card",
		" | new_type=",
		CardGesture.Type.keys()[new_gesture],
		" | sacrificed=",
		removed_card.definition.display_name
			if removed_card.definition != null else "Card"
	)

	return removed_card


func can_cover_card(
	player_id: int,
	card: CardInstance,
	target_slot_id: int
) -> bool:
	if state == null or state.phase != MatchPhase.Type.MAIN:
		return false
	if not SlotID.is_valid(target_slot_id):
		return false

	var player: PlayerState = state.get_player(player_id)
	if player == null or card == null or player.is_ready:
		return false
	if card.definition == null or card.owner_id != player_id:
		return false

	var target_card: CardInstance = player.board.get_card(target_slot_id)
	if target_card == null or target_card == card:
		return false
	if target_card.definition == null:
		return false

	var turns_since_played: int = state.turn_number - target_card.turn_played
	if turns_since_played < 1:
		return false

	if not CardGesture.can_cover(card.get_gesture(), target_card.get_gesture()):
		return false

	if card.zone == CardZone.Type.HAND:
		# Heroes are persistent setup pieces and never enter Hand.
		if card.is_hero():
			return false
		return _can_play_in_row_order(player, target_slot_id)

	if card.zone == CardZone.Type.BOARD:
		if not SlotID.is_valid(card.current_slot):
			return false
		if player.board.get_card(card.current_slot) != card:
			return false
		if card.is_rooted_by_card(state.turn_number):
			return false

		if card.is_hero():
			if not card.hero_revealed:
				return false
			if not _can_hero_move_this_turn(card):
				return false
		else:
			if player.board_move_used_turn == state.turn_number:
				return false

		return _can_move_in_row_order(
			player,
			card.current_slot,
			target_slot_id
		)

	return false


func play_card(
	player_id: int,
	card: CardInstance,
	slot_id: int
) -> bool:
	if state == null or state.phase != MatchPhase.Type.MAIN:
		return false

	var player: PlayerState = state.get_player(player_id)
	if player == null or card == null or player.is_ready:
		return false
	if card.definition == null or card.owner_id != player_id:
		return false
	if not player.hand.has(card) or not SlotID.is_valid(slot_id):
		return false

	slot_id = resolve_play_slot(player_id, slot_id)
	if not SlotID.is_valid(slot_id):
		return false
	if not _can_play_in_row_order(player, slot_id):
		return false

	var mana_cost: int = card.get_mana_cost()
	if player.current_mana < mana_cost:
		return false

	var replaced_card: CardInstance = player.board.get_card(slot_id)
	var board_before: Dictionary = _snapshot_board_cards(player)

	if replaced_card != null:
		if not can_cover_card(player_id, card, slot_id):
			return false

		# Normal card -> Hero: the Hero may not be discarded. Instead it absorbs
		# the covering card's current R/P/S type. The covering normal card pays
		# the Cover cost by going to Reserve and the Hero remains in its slot.
		if replaced_card.is_hero():
			player.hand.erase(card)
			card.zone = CardZone.Type.RESERVE
			card.current_slot = CardInstance.NO_SLOT
			player.reserve_pile.append(card)
			player.current_mana -= mana_cost

			replaced_card.set_gesture_override(card.get_gesture())
			# Treat the transformed Hero as the newly-covered board card. This keeps
			# the normal one-turn Cover cooldown intact and prevents chain-covering
			# the same Hero repeatedly in one turn.
			replaced_card.turn_played = state.turn_number

			print(
				"HERO TYPE COVER | hero=",
				replaced_card.definition.display_name,
				" | new_type=",
				CardGesture.Type.keys()[replaced_card.get_gesture()],
				" | consumed=",
				card.definition.display_name
			)
			return true

		var discarded_card: CardInstance = CardMover.board_to_discard(
			player,
			slot_id
		)
		if discarded_card == null:
			return false

	if not CardMover.hand_to_board(player, card, slot_id):
		return false

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
		card.definition.behavior.on_played_to_board(play_context)

	_restore_guarded_hero_if_protector_missing(player)
	_normalize_player_front_rows(player)

	var final_slot_id: int = slot_id
	if SlotID.is_valid(card.current_slot):
		final_slot_id = card.current_slot

	_record_completed_play(
		player_id,
		card,
		final_slot_id,
		board_before
	)
	return true


func move_board_card(
	player_id: int,
	from_slot_id: int,
	to_slot_id: int
) -> bool:
	if state == null or state.phase != MatchPhase.Type.MAIN:
		return false
	if not SlotID.is_valid(from_slot_id) or not SlotID.is_valid(to_slot_id):
		return false
	if from_slot_id == to_slot_id:
		return false

	var player: PlayerState = state.get_player(player_id)
	if player == null or player.is_ready:
		return false

	var moving_card: CardInstance = player.board.get_card(from_slot_id)
	if moving_card == null or moving_card.owner_id != player_id:
		return false
	if moving_card.is_rooted_by_card(state.turn_number):
		print("BOARD MOVE FAILED | card rooted by opponent effect")
		return false

	if moving_card.is_hero():
		if not moving_card.hero_revealed:
			return false
		if not _can_hero_move_this_turn(moving_card):
			print("HERO MOVE FAILED | hero move already used this turn")
			return false
	else:
		if player.board_move_used_turn == state.turn_number:
			print("BOARD MOVE FAILED | already used this turn")
			return false

	# Heroes now obey the same front/back movement gate as ordinary cards.
	if not _can_move_in_row_order(player, from_slot_id, to_slot_id):
		return false

	var move_cost: int = get_board_move_mana_cost_for_card(player_id, moving_card)
	if player.current_mana < move_cost:
		return false

	var target_card: CardInstance = player.board.get_card(to_slot_id)
	var board_before: Dictionary = _snapshot_board_cards(player)

	if target_card != null:
		if not can_cover_card(player_id, moving_card, to_slot_id):
			return false

		# Normal board card -> Hero. The normal card is consumed into Reserve and
		# the persistent Hero takes that card's current R/P/S type.
		if target_card.is_hero() and not moving_card.is_hero():
			var consumed: CardInstance = CardMover.board_to_reserve(
				player,
				from_slot_id
			)
			if consumed == null:
				return false

			target_card.set_gesture_override(moving_card.get_gesture())
			target_card.turn_played = state.turn_number
			player.current_mana -= move_cost
			player.board_move_used_turn = state.turn_number
			_restore_guarded_hero_if_protector_missing(player)
			_normalize_player_front_rows(player)
			print(
				"HERO TYPE COVER FROM BOARD | hero=",
				target_card.definition.display_name,
				" | new_type=",
				CardGesture.Type.keys()[target_card.get_gesture()]
			)
			return true

		# Hero -> normal card uses the exact same Cover rule as ordinary cards:
		# the card underneath is sent to Reserve/Discard and the Hero takes its slot.
		var discarded_card: CardInstance = CardMover.board_to_discard(
			player,
			to_slot_id
		)
		if discarded_card == null:
			return false

	var moved: bool = player.board.move_card(from_slot_id, to_slot_id)
	if not moved:
		return false

	player.current_mana -= move_cost
	if moving_card.is_hero():
		moving_card.hero_moves_this_turn += 1
		moving_card.hero_last_moved_turn = state.turn_number
	else:
		player.board_move_used_turn = state.turn_number

	_restore_guarded_hero_if_protector_missing(player)
	_normalize_player_front_rows(player)

	var final_slot_id: int = to_slot_id
	if SlotID.is_valid(moving_card.current_slot):
		final_slot_id = moving_card.current_slot

	_record_completed_board_move(
		player_id,
		moving_card,
		from_slot_id,
		final_slot_id,
		board_before
	)
	return true


func _start_new_turn_for_player(
	player: PlayerState
) -> void:
	if player == null:
		return

	# Mommy's free card exists in hand for exactly one turn. Remove an
	# unplayed reward permanently before the ordinary hand is discarded.
	_expire_unplayed_mommy_hand_cards(player)

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

	# Hero rewards are extra cards and arrive after the normal hand draw.
	for reward: CardInstance in player.pending_hero_rewards:
		if reward == null:
			continue
		reward.zone = CardZone.Type.HAND
		reward.current_slot = CardInstance.NO_SLOT
		player.hand.append(reward)
		drawn_cards.append(reward)
	player.pending_hero_rewards.clear()

	# Mommy rewards also arrive after the normal draw, but unlike Hero rewards
	# they are free and disappear permanently if not played this turn.
	for reward: CardInstance in player.pending_mommy_rewards:
		if reward == null:
			continue
		reward.zone = CardZone.Type.HAND
		reward.current_slot = CardInstance.NO_SLOT
		player.hand.append(reward)
		drawn_cards.append(reward)
	player.pending_mommy_rewards.clear()

	if player.hero != null:
		player.hero.hero_moves_this_turn = 0

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

	# Start-combat abilities (Collector, etc.) may remove a guard card. If that
	# happens the Hero immediately resurfaces before the battle is built.
	_restore_missing_guarded_heroes()
	_normalize_all_player_front_rows()


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

	active_battle_sequence = \
		BattleResolver.build_sequence(state)

	if state.rush_mode_enabled:
		_capture_rush_pvp_loser_snapshot()

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
		attacker_player.score += act.attacker_points
		_add_player_energy(attacker_player, act.attacker_points)

	if act.defender_owner_id != 0:
		var defender_player: PlayerState = \
			state.get_player(
				act.defender_owner_id
			)

		if defender_player != null:
			defender_player.score += act.defender_points
			_add_player_energy(defender_player, act.defender_points)

	_apply_hero_health_damage_from_act(act)
	_apply_hero_battle_metadata(act)

	_run_resolved_behavior_for_side(
		act.attacker,
		act.attacker_owner_id,
		act.attacker_slot_id,
		act.attacker_outcome,
		act.defender,
		act.type
	)

	if act.defender_owner_id != 0:
		_run_resolved_behavior_for_side(
			act.defender,
			act.defender_owner_id,
			act.defender_slot_id,
			act.defender_outcome,
			act.attacker,
			act.type
		)

	act.resolved = true

	return true


func _apply_hero_health_damage_from_act(act: BattleAct) -> void:
	if act == null or act.type != BattleAct.Type.PLAYER_VS_PLAYER:
		return

	if (
		act.attacker != null
		and act.attacker.is_hero()
		and act.defender != null
		and act.defender.is_hero()
		and act.attacker_outcome == BattleAct.Outcome.WIN
		and act.attacker_unshielded_hero_hits > 0
	):
		var damage: int = mini(
			act.attacker_unshielded_hero_hits,
			maxi(0, act.defender.hero_health)
		)
		act.defender.hero_health = maxi(0, act.defender.hero_health - damage)
		print(
			"HERO HP DAMAGE | attacker=", act.attacker_owner_id,
			" | target=", act.defender_owner_id,
			" | damage=", damage,
			" | hp=", act.defender.hero_health, "/", act.defender.hero_max_health
		)

	if (
		act.defender != null
		and act.defender.is_hero()
		and act.attacker != null
		and act.attacker.is_hero()
		and act.defender_outcome == BattleAct.Outcome.WIN
		and act.defender_unshielded_hero_hits > 0
	):
		var damage: int = mini(
			act.defender_unshielded_hero_hits,
			maxi(0, act.attacker.hero_health)
		)
		act.attacker.hero_health = maxi(0, act.attacker.hero_health - damage)
		print(
			"HERO HP DAMAGE | attacker=", act.defender_owner_id,
			" | target=", act.attacker_owner_id,
			" | damage=", damage,
			" | hp=", act.attacker.hero_health, "/", act.attacker.hero_max_health
		)


func _add_player_energy(player: PlayerState, amount: int) -> void:
	if player == null or state == null or state.rush_mode_enabled:
		return
	if amount == 0:
		return

	player.energy_points = clampi(
		player.energy_points + amount,
		0,
		MAX_ENERGY_POINTS
	)


func get_player_energy(player_id: int) -> int:
	if state == null:
		return 0
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return 0
	return clampi(player.energy_points, 0, MAX_ENERGY_POINTS)


func get_player_energy_bars(player_id: int) -> int:
	return mini(
		MAX_ENERGY_BARS,
		floori(float(get_player_energy(player_id)) / float(ENERGY_PER_BAR))
	)


func can_use_special_attack(player_id: int) -> bool:
	if state == null or state.rush_mode_enabled:
		return false
	if state.phase != MatchPhase.Type.MAIN:
		return false

	var player: PlayerState = state.get_player(player_id)
	if player == null or player.is_ready:
		return false
	if player.energy_points < MAX_ENERGY_POINTS:
		return false

	var opponent_id: int = 2 if player_id == 1 else 1
	var opponent: PlayerState = state.get_player(opponent_id)
	if opponent == null or opponent.hero == null:
		return false
	if opponent.hero.hero_health <= 0:
		return false

	return true


func use_special_attack(player_id: int) -> bool:
	if not can_use_special_attack(player_id):
		return false

	var player: PlayerState = state.get_player(player_id)
	var opponent_id: int = 2 if player_id == 1 else 1
	var opponent: PlayerState = state.get_player(opponent_id)
	var target_hero: CardInstance = opponent.hero

	# Four full bars are always consumed. A temporary shield blocks this one
	# health loss exactly like it blocks an unshielded Hero-vs-Hero hit.
	player.energy_points = 0
	if target_hero.shield_count > 0:
		target_hero.shield_count -= 1
		print(
			"SPECIAL BLOCKED BY SHIELD | attacker=", player_id,
			" | target=", opponent_id,
			" | shields_left=", target_hero.shield_count
		)
	else:
		target_hero.hero_health = maxi(0, target_hero.hero_health - 1)
		print(
			"SPECIAL HERO DAMAGE | attacker=", player_id,
			" | target=", opponent_id,
			" | hp=", target_hero.hero_health, "/", target_hero.hero_max_health
		)

	_check_hero_health_victory()
	return true


func _check_hero_health_victory() -> bool:
	if state == null or state.rush_mode_enabled:
		return false
	if state.player_one == null or state.player_two == null:
		return false
	if state.player_one.hero == null or state.player_two.hero == null:
		return false

	var player_one_dead: bool = state.player_one.hero.hero_health <= 0
	var player_two_dead: bool = state.player_two.hero.hero_health <= 0
	if not player_one_dead and not player_two_dead:
		return false

	if player_one_dead and player_two_dead:
		state.winner_id = 0
	elif player_one_dead:
		state.winner_id = 2
	else:
		state.winner_id = 1

	state.phase = MatchPhase.Type.GAME_OVER
	print("")
	print("========== HERO GAME OVER ==========")
	print("WINNER ID: ", state.winner_id)
	print("PLAYER 1 HERO HP: ", state.player_one.hero.hero_health)
	print("PLAYER 2 HERO HP: ", state.player_two.hero.hero_health)
	return true


func _get_card_behavior(
	card: CardInstance
) -> CardBehavior:
	if card == null:
		return null

	if card.definition == null:
		return null

	return card.definition.behavior


func _run_resolved_behavior_for_side(
	card: CardInstance,
	player_id: int,
	slot_id: int,
	outcome: int,
	opponent_card: CardInstance,
	act_type: int
) -> void:
	var behavior: CardBehavior = _get_card_behavior(card)
	if behavior == null:
		return

	var context := CardBehaviorContext.new(
		self,
		state,
		card,
		player_id,
		slot_id
	)

	behavior.on_battle_resolved(
		context,
		outcome,
		opponent_card,
		act_type
	)


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
	if card.is_hero():
		return false

	var player: PlayerState = state.get_player(
		player_id
	)

	if player == null:
		return false

	var slot_id: int = card.current_slot

	if not SlotID.is_valid(slot_id):
		return false

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


func _remove_board_card_permanently(
	player_id: int,
	card: CardInstance,
	reason: String
) -> bool:
	if card == null or state == null:
		return false
	if card.is_hero():
		return false

	var player: PlayerState = state.get_player(player_id)

	if player == null:
		return false

	var slot_id: int = card.current_slot

	if not SlotID.is_valid(slot_id):
		return false

	if player.board.get_card(slot_id) != card:
		return false

	var removed_card: CardInstance = CardMover.board_to_removed(
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


func _append_unique_rush_loser(
	player_id: int,
	card: CardInstance,
	outcome: BattleAct.Outcome
) -> void:
	if outcome != BattleAct.Outcome.LOSS:
		return

	if player_id not in [1, 2] or card == null:
		return
	if card.is_hero():
		return

	if not rush_pvp_loser_snapshot.has(player_id):
		rush_pvp_loser_snapshot[player_id] = []

	var losers: Array = rush_pvp_loser_snapshot[player_id]

	# A middle card can fight both opposing middle cards. Keep the exact card
	# only once, but NEVER cancel its LOSS because it also has a WIN/TIE.
	for value: Variant in losers:
		var existing := value as CardInstance
		if existing == card:
			return

	losers.append(card)
	rush_pvp_loser_snapshot[player_id] = losers


func _capture_rush_pvp_loser_snapshot() -> void:
	rush_pvp_loser_snapshot = {
		1: [],
		2: []
	}

	if (
		state == null
		or not state.rush_mode_enabled
		or active_battle_sequence == null
	):
		return

	for act: BattleAct in active_battle_sequence.acts:
		if act == null or act.type != BattleAct.Type.PLAYER_VS_PLAYER:
			continue

		_append_unique_rush_loser(
			act.attacker_owner_id,
			act.attacker,
			act.attacker_outcome
		)
		_append_unique_rush_loser(
			act.defender_owner_id,
			act.defender,
			act.defender_outcome
		)


func _find_board_slot_for_card(
	player: PlayerState,
	card: CardInstance
) -> int:
	if player == null or card == null:
		return -1

	# Do not trust current_slot here. Rush middle cards participate in multiple
	# clashes and other cleanup/ability code may change bookkeeping. The board
	# itself is the source of truth.
	for slot_id: int in SlotID.all_slots():
		if player.board.get_card(slot_id) == card:
			return slot_id

	return -1


func _remove_rush_loser_by_reference(
	player_id: int,
	card: CardInstance
) -> bool:
	if state == null or card == null:
		return false
	if card.is_hero():
		return false

	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return false

	var slot_id: int = _find_board_slot_for_card(player, card)
	if not SlotID.is_valid(slot_id):
		return false

	var removed_card: CardInstance = CardMover.board_to_removed(
		player,
		slot_id
	)

	if removed_card == null:
		return false

	print(
		"RUSH PVP LOSER REMOVED | player=",
		player_id,
		" | card=",
		removed_card.definition.display_name
			if removed_card.definition != null
			else "Unknown",
		" | slot=",
		slot_id
	)

	return true


func _resolve_rush_pvp_losers() -> void:
	if state == null or not state.rush_mode_enabled:
		return

	# The loser set was frozen at begin_combat(). Order no longer matters:
	# if card X loses first and then beats card Y, BOTH X and Y are still in
	# this snapshot and both are permanently removed.
	for player_id: int in [1, 2]:
		var losers: Array = rush_pvp_loser_snapshot.get(player_id, [])

		for value: Variant in losers:
			var card := value as CardInstance
			if card == null:
				continue

			_remove_rush_loser_by_reference(
				player_id,
				card
			)

	# Do not carry stale loser references into the next turn.
	rush_pvp_loser_snapshot = {
		1: [],
		2: []
	}



func _resolve_new_special_card_results() -> void:
	if state == null or active_battle_sequence == null:
		return

	var cards_to_remove: Array[Dictionary] = []
	var remove_ids: Dictionary = {}
	var mommy_spawns: Array[Dictionary] = []

	for act: BattleAct in active_battle_sequence.acts:
		if act == null or not act.resolved:
			continue

		_process_special_card_result_side(
			act.attacker_owner_id,
			act.attacker,
			act.attacker_outcome,
			act.defender_owner_id,
			act.defender,
			act.type,
			cards_to_remove,
			remove_ids,
			mommy_spawns
		)
		if act.defender_owner_id in [1, 2]:
			_process_special_card_result_side(
				act.defender_owner_id,
				act.defender,
				act.defender_outcome,
				act.attacker_owner_id,
				act.attacker,
				act.type,
				cards_to_remove,
				remove_ids,
				mommy_spawns
			)

	# Resolve removals after every BattleAct has already animated/resolved.
	for entry: Dictionary in cards_to_remove:
		_send_board_card_to_reserve(
			int(entry.get("player_id", 0)),
			entry.get("card", null) as CardInstance,
			String(entry.get("reason", "SPECIAL CARD REMOVED"))
		)

	# Mommy does NOT spawn onto the board. A free same-type normal card is
	# queued for the owner's NEXT hand. One Mommy triggers at most once/turn.
	for entry: Dictionary in mommy_spawns:
		_queue_mommy_free_hand_card(
			int(entry.get("player_id", 0)),
			entry.get("source", null) as CardInstance
		)


func _process_special_card_result_side(
	owner_id: int,
	card: CardInstance,
	outcome: int,
	opponent_owner_id: int,
	opponent_card: CardInstance,
	act_type: int,
	cards_to_remove: Array[Dictionary],
	remove_ids: Dictionary,
	mommy_spawns: Array[Dictionary]
) -> void:
	if owner_id not in [1, 2] or card == null or card.definition == null:
		return
	var behavior: CardBehavior = card.definition.behavior
	if behavior == null:
		return

	# Mommy: any win (PvP or Dealer) queues one free same-type card for next hand.
	if behavior is MommyBehavior and outcome == BattleAct.Outcome.WIN:
		if card.mommy_triggered_turn != state.turn_number:
			card.mommy_triggered_turn = state.turn_number
			mommy_spawns.append({"player_id": owner_id, "source": card})

	# The remaining effects explicitly refer to the opposing player's card.
	if act_type != BattleAct.Type.PLAYER_VS_PLAYER:
		# Martyr healer is the exception: any loss can trigger its final shield.
		if behavior is MartyrHealerBehavior and outcome == BattleAct.Outcome.LOSS:
			if card.martyr_triggered_turn != state.turn_number:
				card.martyr_triggered_turn = state.turn_number
				_grant_random_friendly_shield(owner_id, card)
			_queue_special_remove(cards_to_remove, remove_ids, owner_id, card, "MARTYR HEALER EXPIRED")
		return

	if behavior is DebufferBehavior and outcome == BattleAct.Outcome.WIN:
		if opponent_card != null:
			opponent_card.debuffed_no_win_turn = state.turn_number + 1
			print("DEBUFFER APPLIED | target=", opponent_card.definition.display_name, " | turn=", state.turn_number + 1)

	if behavior is KamikazeBehavior and outcome == BattleAct.Outcome.LOSS:
		_queue_special_remove(cards_to_remove, remove_ids, owner_id, card, "KAMIKAZE EXPIRED")
		if opponent_owner_id in [1, 2] and opponent_card != null and not opponent_card.is_hero():
			_queue_special_remove(cards_to_remove, remove_ids, opponent_owner_id, opponent_card, "KAMIKAZE TOOK WINNER")

	if behavior is MartyrHealerBehavior and outcome == BattleAct.Outcome.LOSS:
		if card.martyr_triggered_turn != state.turn_number:
			card.martyr_triggered_turn = state.turn_number
			_grant_random_friendly_shield(owner_id, card)
		_queue_special_remove(cards_to_remove, remove_ids, owner_id, card, "MARTYR HEALER EXPIRED")


func _queue_special_remove(
	entries: Array[Dictionary],
	ids: Dictionary,
	player_id: int,
	card: CardInstance,
	reason: String
) -> void:
	if card == null or card.is_hero() or ids.has(card.instance_id):
		return
	ids[card.instance_id] = true
	entries.append({"player_id": player_id, "card": card, "reason": reason})


func _grant_random_friendly_shield(player_id: int, source: CardInstance) -> void:
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return
	var candidates: Array[CardInstance] = []
	for slot_id: int in SlotID.all_slots():
		var target: CardInstance = player.board.get_card(slot_id)
		if target == null or target == source:
			continue
		candidates.append(target)
	if candidates.is_empty():
		return
	var chosen: CardInstance = candidates.pick_random()
	chosen.shield_count += 1
	print("MARTYR SHIELD | target=", chosen.definition.display_name, " | shields=", chosen.shield_count)


func _queue_mommy_free_hand_card(
	player_id: int,
	source: CardInstance
) -> void:
	if source == null or source.definition == null:
		return

	var behavior := source.definition.behavior as MommyBehavior
	if behavior == null or behavior.spawned_card == null:
		return

	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return

	var reward: CardInstance = card_factory.create_card(
		behavior.spawned_card,
		player_id
	)
	if reward == null:
		return

	# Free next turn. It expires at the START of the turn after that if it was
	# never played. Playing it clears this marker in reset_for_board_entry().
	reward.mana_cost_override = 0
	reward.temporary_hand_expire_turn = state.turn_number + 2
	reward.zone = CardZone.Type.DRAW
	reward.current_slot = CardInstance.NO_SLOT
	player.pending_mommy_rewards.append(reward)

	print(
		"MOMMY REWARD QUEUED | owner=", player_id,
		" | card=", reward.definition.display_name,
		" | expires_start_turn=", reward.temporary_hand_expire_turn
	)


func _expire_unplayed_mommy_hand_cards(player: PlayerState) -> void:
	if player == null or state == null:
		return

	var expired: Array[CardInstance] = []
	for card: CardInstance in player.hand:
		if card == null:
			continue
		if card.temporary_hand_expire_turn < 0:
			continue
		if state.turn_number < card.temporary_hand_expire_turn:
			continue
		expired.append(card)

	for card: CardInstance in expired:
		player.hand.erase(card)
		card.zone = CardZone.Type.REMOVED
		card.current_slot = CardInstance.NO_SLOT
		print(
			"MOMMY FREE CARD EXPIRED | owner=", player.player_id,
			" | card=", card.definition.display_name
		)


func _apply_pending_card_definition_changes() -> void:
	if state == null:
		return

	for player_id: int in [1, 2]:
		var player: PlayerState = state.get_player(player_id)
		if player == null:
			continue

		for slot_id: int in SlotID.all_slots():
			var card: CardInstance = player.board.get_card(slot_id)
			if card == null or card.pending_definition_path.is_empty():
				continue

			var next_def: CardDefinition = ResourceLoader.load(
				card.pending_definition_path
			) as CardDefinition
			card.pending_definition_path = ""
			if next_def == null:
				continue

			var old_name: String = (
				card.definition.display_name if card.definition != null else "Card"
			)
			card.definition = next_def
			print(
				"CHANGELING TRANSFORM | owner=", player_id,
				" | old=", old_name,
				" | new=", next_def.display_name
			)


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


func _resolve_dealer_lane_losers() -> void:
	if state == null or active_battle_sequence == null:
		return

	var affected_lanes: Dictionary = _get_loser_discard_lanes()
	if affected_lanes.is_empty():
		return

	var defeated_targets: Array[Dictionary] = []
	var defeated_instance_ids: Dictionary = {}

	for act: BattleAct in active_battle_sequence.acts:
		if act == null or not act.resolved:
			continue

		# خود Gladiator Div در مبارزه‌ی Dealer یک DIV است و کارت‌های
		# معمولی همیشه به آن می‌بازند. اثر ویژه فقط باید بازنده‌ی Clash
		# بین دو بازیکن را حذف کند، نه کارتی را که به خود Dealer باخته است.
		if act.type != BattleAct.Type.PLAYER_VS_PLAYER:
			continue

		_queue_dealer_lane_loser(
			defeated_targets,
			defeated_instance_ids,
			affected_lanes,
			act.attacker_owner_id,
			act.attacker,
			act.attacker_slot_id,
			act.attacker_outcome
		)
		_queue_dealer_lane_loser(
			defeated_targets,
			defeated_instance_ids,
			affected_lanes,
			act.defender_owner_id,
			act.defender,
			act.defender_slot_id,
			act.defender_outcome
		)

	for target: Dictionary in defeated_targets:
		_send_board_card_to_reserve(
			int(target.get("player_id", 0)),
			target.get("card", null) as CardInstance,
			"GLADIATOR DIV DISCARDED LOSER"
		)


func _get_loser_discard_lanes() -> Dictionary:
	var result: Dictionary = {}

	if state == null or state.dealer == null:
		return result

	for dealer_slot_id: int in DealerSlotID.all_slots():
		var dealer_card: CardInstance = state.dealer.slots.get(
			dealer_slot_id,
			null
		) as CardInstance

		if dealer_card == null or dealer_card.definition == null:
			continue

		var behavior: DealerCardBehavior = \
			dealer_card.definition.dealer_behavior

		if (
			behavior == null
			or not behavior.discards_lane_losers_after_combat()
		):
			continue

		result[DealerSlotID.get_lane(dealer_slot_id)] = true

	return result


func _queue_dealer_lane_loser(
	targets: Array[Dictionary],
	instance_ids: Dictionary,
	affected_lanes: Dictionary,
	player_id: int,
	card: CardInstance,
	slot_id: int,
	outcome: BattleAct.Outcome
) -> void:
	if outcome != BattleAct.Outcome.LOSS:
		return

	if player_id not in [1, 2]:
		return

	if card == null or not SlotID.is_valid(slot_id):
		return

	if not affected_lanes.has(SlotID.get_lane(slot_id)):
		return

	if instance_ids.has(card.instance_id):
		return

	instance_ids[card.instance_id] = true
	targets.append({
		"player_id": player_id,
		"card": card
	})



func _apply_rush_unused_mana_penalty(
	player: PlayerState
) -> Array[CardInstance]:
	var removed_cards: Array[CardInstance] = []

	if (
		state == null
		or not state.rush_mode_enabled
		or player == null
	):
		return removed_cards

	var unused_mana: int = maxi(0, player.current_mana)
	var cards_to_remove: int = floori(
		float(unused_mana) / 2.0
	)

	if cards_to_remove <= 0:
		return removed_cards

	for index: int in range(cards_to_remove):
		var removed_card: CardInstance = \
			CardMover.remove_random_hand_card(player)

		if removed_card == null:
			break

		removed_cards.append(removed_card)

		print(
			"RUSH UNUSED MANA PENALTY | player=",
			player.player_id,
			" | unused_mana=",
			unused_mana,
			" | card=",
			removed_card.definition.display_name
				if removed_card.definition != null
				else "Unknown"
		)

	return removed_cards


func get_last_rush_penalty_cards(
	player_id: int
) -> Array[CardInstance]:
	var result: Array[CardInstance] = []

	if not last_rush_penalty_cards.has(player_id):
		return result

	for value: Variant in last_rush_penalty_cards[player_id]:
		var card := value as CardInstance
		if card != null:
			result.append(card)

	return result


func finish_combat() -> bool:
	if state == null:
		return false

	last_rush_penalty_cards = {
		1: [],
		2: []
	}

	if state.phase != MatchPhase.Type.BATTLE:
		return false

	state.phase = MatchPhase.Type.CLEANUP

	# Resolve the new card families only after every battle animation/result has
	# been applied, so middle-row multi-clashes cannot invalidate references.
	_resolve_new_special_card_results()

	# Changeling changes type only after the entire battle phase is over.
	_apply_pending_card_definition_changes()

	# Rush removes every card that lost a direct PvP clash before any normal
	# Killer/Reserve cleanup can claim it. This is the only permanent removal.
	if state.rush_mode_enabled:
		_resolve_rush_pvp_losers()

	# نتیجه تمام Clashها بررسی می‌شود.
	# اهداف شکست‌خورده و خود Killerها وارد Reserve می‌شوند.
	_resolve_killer_cards()

	# اگر Gladiator Div در یک لاین باشد، کارت‌های بازنده‌ی Clash بین
	# دو بازیکن در همان لاین بعد از Combat از زمین خارج می‌شوند.
	if not state.rush_mode_enabled:
		_resolve_dealer_lane_losers()

	# A Hero guard lasts exactly this combat turn. The protecting normal card
	# now goes to Reserve and the Hero resurfaces before board normalization.
	_expire_hero_guards()

	# Cleanup is complete. Any survivor directly behind an empty Front advances.
	_normalize_all_player_front_rows()

	if state.rush_mode_enabled:
		# Direct PvP elimination has priority. If a player lost their final card
		# in combat, the match ends before unused-mana penalties are considered.
		if _check_rush_card_victory():
			return false

		# Every two unspent mana remove one random CURRENT-HAND card permanently.
		# Both penalties belong to the same end-of-turn cleanup window.
		last_rush_penalty_cards[1] = \
			_apply_rush_unused_mana_penalty(state.player_one)
		last_rush_penalty_cards[2] = \
			_apply_rush_unused_mana_penalty(state.player_two)

		if _check_rush_card_victory():
			return false
	else:
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


func _check_rush_card_victory() -> bool:
	if state == null or not state.rush_mode_enabled:
		return false

	var player_one_cards: int = \
		state.player_one.get_remaining_card_count()
	var player_two_cards: int = \
		state.player_two.get_remaining_card_count()

	if player_one_cards > 0 and player_two_cards > 0:
		return false

	if player_one_cards <= 0 and player_two_cards <= 0:
		# Both players can lose their final cards in different lanes during the
		# same combat. Winner 0 is a real draw, not a score-based tiebreaker.
		state.winner_id = 0
	elif player_one_cards <= 0:
		state.winner_id = 2
	else:
		state.winner_id = 1

	state.phase = MatchPhase.Type.GAME_OVER

	print("")
	print("========== RUSH GAME OVER ==========")
	print("WINNER ID: ", state.winner_id)
	print("PLAYER 1 CARDS: ", player_one_cards)
	print("PLAYER 2 CARDS: ", player_two_cards)

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

	# A Front card may move away even when a Back card is behind it.
	# _normalize_player_front_rows() immediately advances that Back card.

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


func _snapshot_board_slot_ids(
	player: PlayerState
) -> Dictionary:
	var result: Dictionary = {}

	if player == null:
		return result

	for slot_id: int in SlotID.all_slots():
		var card: CardInstance = player.board.get_card(
			slot_id
		)

		if card == null:
			continue

		result[card.instance_id] = slot_id

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

	record.type = CardPlayRecord.Type.PLAY_CARD
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

	# بعضی Abilityها خود کارت تازه‌Playشده را همان لحظه از Board خارج می‌کنند.
	# آن کارت هم باید در همان Action از نظر بصری حذف شود، نه در Cleanup آخر.
	if not _is_card_still_on_board(
		player,
		played_card
	):
		record.removed_cards.append(
			played_card
		)

	record.board_slots_after = \
		_snapshot_board_slot_ids(player)

	var stored_records: Array = \
		play_records_by_player.get(
			player_id,
			[]
		)

	stored_records.append(record)

	play_records_by_player[player_id] = \
		stored_records


func _record_completed_board_move(
	player_id: int,
	moved_card: CardInstance,
	from_slot_id: int,
	to_slot_id: int,
	board_before: Dictionary
) -> void:
	var player: PlayerState = \
		state.get_player(player_id)

	if player == null or moved_card == null:
		return

	var record := CardPlayRecord.new()
	record.type = CardPlayRecord.Type.MOVE_BOARD_CARD
	record.card = moved_card
	record.owner_id = player_id
	record.from_slot_id = from_slot_id
	record.slot_id = to_slot_id

	for raw_card: Variant in board_before.values():
		var previous_card: CardInstance = \
			raw_card as CardInstance

		if previous_card == null:
			continue

		if previous_card == moved_card:
			continue

		if not _is_card_still_on_board(
			player,
			previous_card
		):
			record.removed_cards.append(
				previous_card
			)

	record.board_slots_after = \
		_snapshot_board_slot_ids(player)

	var stored_records: Array = \
		play_records_by_player.get(
			player_id,
			[]
		)

	stored_records.append(record)
	play_records_by_player[player_id] = \
		stored_records


func finalize_combat_score() -> bool:
	if state == null:
		return false

	if state.phase != MatchPhase.Type.BATTLE:
		return false

	# Rush keeps its own card-elimination victory condition. Normal mode now
	# ends only when a Hero reaches zero health; score only charges Energy.
	if state.rush_mode_enabled:
		return false

	return _check_hero_health_victory()


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
