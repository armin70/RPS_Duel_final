class_name PoisonBehavior
extends CardBehavior


func on_played_to_board(context: CardBehaviorContext) -> void:
	if context == null or context.state == null or context.source_card == null:
		return

	var owner: PlayerState = context.get_owner()
	if owner == null or owner.board == null:
		return

	# Poison is a curse, not a combat card. Playing it pays its mana cost.
	# Once used/cleansed, it is removed from the match completely:
	# it must NOT go to Discard and must NOT return on a later shuffle.
	var removed: CardInstance = owner.board.remove_card(context.slot_id)
	if removed != context.source_card:
		if removed != null:
			owner.board.place_card(context.slot_id, removed)
		return

	removed.zone = CardZone.Type.REMOVED
	removed.current_slot = CardInstance.NO_SLOT

	print(
		"POISON REMOVED | player=", context.owner_id,
		" | mana_cost=", removed.get_mana_cost()
	)
