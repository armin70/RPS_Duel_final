class_name DealerMover
extends RefCounted

static func deal_new_board(
	dealer: DealerState
) -> bool:
	if dealer == null:
		return false

	# کارت‌های قبلی وارد Discard می‌شوند.
	for slot_id: int in DealerSlotID.all_slots():
		var old_card: CardInstance = dealer.slots[slot_id]

		if old_card != null:
			old_card.zone = CardZone.Type.DISCARD
			old_card.current_slot = CardInstance.NO_SLOT
			dealer.discard_pile.append(old_card)

		dealer.slots[slot_id] = null

	# چهار کارت جدید پخش می‌شوند.
	for slot_id: int in DealerSlotID.all_slots():
		if dealer.draw_pile.is_empty():
			_recycle_discard(dealer)

		if dealer.draw_pile.is_empty():
			return false

		var card: CardInstance = dealer.draw_pile.pop_back()

		card.zone = CardZone.Type.DEALER_BOARD
		card.current_slot = slot_id
		dealer.slots[slot_id] = card

	return true


static func _recycle_discard(
	dealer: DealerState
) -> void:
	for card: CardInstance in dealer.discard_pile:
		card.zone = CardZone.Type.DRAW
		card.current_slot = CardInstance.NO_SLOT
		dealer.draw_pile.append(card)

	dealer.discard_pile.clear()
	dealer.draw_pile.shuffle()
