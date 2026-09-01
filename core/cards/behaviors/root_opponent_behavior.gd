class_name RootOpponentBehavior
extends CardBehavior

@export var affects_heroes: bool = true


func on_start_combat(context: CardBehaviorContext) -> void:
	if context == null or context.state == null:
		return

	var source: CardInstance = context.source_card
	if source == null:
		return

	# Rooter only fires the first time this CardInstance reaches battle phase
	# after entering the board.
	if source.ability_used:
		return
	source.ability_used = true

	var opponent: PlayerState = context.get_opponent()
	if opponent == null or opponent.board == null:
		return

	var source_lane: int = SlotID.get_lane(context.slot_id)
	var rooted_turn: int = context.state.turn_number + 1

	for target_slot: int in SlotID.all_slots():
		if SlotID.get_lane(target_slot) != source_lane:
			continue

		var target: CardInstance = opponent.board.get_card(target_slot)
		if target == null:
			continue
		if target.is_hero() and not affects_heroes:
			continue

		# The old CardInstance is rooted through the next main phase. If the
		# player covers/switches it, the replacement CardInstance is not rooted.
		target.rooted_by_card_turn = rooted_turn
		print(
			"ROOTER APPLIED | source=", source.definition.display_name,
			" | target=", target.definition.display_name,
			" | rooted_turn=", rooted_turn
		)
