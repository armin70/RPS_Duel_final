class_name PoisonBehavior
extends CardBehavior


func on_played_to_board(context: CardBehaviorContext) -> void:
	if context == null or context.state == null or context.source_card == null:
		return

	var owner: PlayerState = context.get_owner()
	if owner == null or owner.board == null:
		return

	# Poison is a curse, not a combat card. Paying its 4 mana cost by playing
	# it onto any empty legal slot immediately cleanses it into Discard.
	var removed: CardInstance = owner.board.remove_card(context.slot_id)
	if removed != context.source_card:
		if removed != null:
			owner.board.place_card(context.slot_id, removed)
		return

	removed.zone = CardZone.Type.DISCARD
	removed.current_slot = CardInstance.NO_SLOT
	owner.discard_pile.append(removed)

	print(
		"POISON CLEANSED | player=", context.owner_id,
		" | mana_cost=", removed.get_mana_cost()
	)
