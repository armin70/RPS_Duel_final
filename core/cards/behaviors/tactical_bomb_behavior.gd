class_name TacticalBombBehavior
extends CardBehavior

@export var destroyed_gesture: CardGesture.Type = CardGesture.Type.ROCK


func on_played_to_board(context: CardBehaviorContext) -> void:
	if context == null or context.state == null:
		return
	if context.source_card == null:
		return

	var owner: PlayerState = context.get_owner()
	if owner == null or owner.board == null:
		return

	var lane: int = SlotID.get_lane(context.slot_id)
	var targets: Array[int] = []

	# "ستون خودش": only cards on this player's side of the same column/lane.
	# Heroes are never discarded by this bomb.
	for slot_id: int in SlotID.all_slots():
		if SlotID.get_lane(slot_id) != lane:
			continue
		var card: CardInstance = owner.board.get_card(slot_id)
		if card == null or card == context.source_card:
			continue
		if card.is_hero():
			continue
		if card.get_gesture() != destroyed_gesture:
			continue
		targets.append(slot_id)

	var removed_count: int = 0
	for slot_id: int in targets:
		var removed: CardInstance = CardMover.board_to_reserve(owner, slot_id)
		if removed == null:
			continue
		removed_count += 1
		print(
			"TACTICAL BOMB REMOVED | source=", context.source_card.definition.display_name,
			" | target=", removed.definition.display_name,
			" | slot=", slot_id
		)

	if removed_count <= 0:
		return

	var drawn: Array[CardInstance] = CardMover.draw_cards_to_hand(
		owner,
		removed_count
	)
	print(
		"TACTICAL BOMB REFILL | owner=", context.owner_id,
		" | removed=", removed_count,
		" | drawn=", drawn.size()
	)
