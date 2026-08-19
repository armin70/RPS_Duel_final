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

	_enforce_matching_middle_pair(dealer)

	return true


static func _enforce_matching_middle_pair(
	dealer: DealerState
) -> void:
	var first_middle: CardInstance = dealer.slots.get(
		DealerSlotID.Type.MIDDLE_0,
		null
	) as CardInstance
	var second_middle: CardInstance = dealer.slots.get(
		DealerSlotID.Type.MIDDLE_1,
		null
	) as CardInstance

	var source_card: CardInstance = null
	var target_slot_id: int = -1

	if _requires_matching_middle_pair(first_middle):
		source_card = first_middle
		target_slot_id = DealerSlotID.Type.MIDDLE_1
	elif _requires_matching_middle_pair(second_middle):
		source_card = second_middle
		target_slot_id = DealerSlotID.Type.MIDDLE_0

	if source_card == null or source_card.definition == null:
		return

	var current_target: CardInstance = dealer.slots.get(
		target_slot_id,
		null
	) as CardInstance

	# هر دو جایگاه از قبل همان Gladiator را دارند.
	if (
		current_target != null
		and current_target.definition == source_card.definition
	):
		return

	# اول نسخه دوم را بین جایگاه‌های کناری پیدا می‌کنیم و با کارت وسط
	# جابه‌جا می‌کنیم؛ به این ترتیب هیچ کارتی از چرخه خارج نمی‌شود.
	for side_slot_id: int in [
		DealerSlotID.Type.LEFT,
		DealerSlotID.Type.RIGHT
	]:
		var side_card: CardInstance = dealer.slots.get(
			side_slot_id,
			null
		) as CardInstance

		if (
			side_card == null
			or side_card.definition != source_card.definition
		):
			continue

		dealer.slots[target_slot_id] = side_card
		side_card.current_slot = target_slot_id

		dealer.slots[side_slot_id] = current_target
		if current_target != null:
			current_target.current_slot = side_slot_id

		_print_middle_pair(source_card)
		return

	# اگر نسخه دوم هنوز Draw نشده، آن را از Draw می‌گیریم و کارت عادی
	# جایگاه دوم را به همان Pile برمی‌گردانیم.
	var pair_card: CardInstance = _take_matching_card(
		dealer.draw_pile,
		source_card.definition
	)

	if pair_card != null:
		_replace_middle_from_pile(
			dealer,
			target_slot_id,
			pair_card,
			dealer.draw_pile,
			CardZone.Type.DRAW
		)
		_print_middle_pair(source_card)
		return

	# نسخه دوم ممکن است در دور قبل وارد Discard شده باشد.
	pair_card = _take_matching_card(
		dealer.discard_pile,
		source_card.definition
	)

	if pair_card != null:
		_replace_middle_from_pile(
			dealer,
			target_slot_id,
			pair_card,
			dealer.discard_pile,
			CardZone.Type.DISCARD
		)
		_print_middle_pair(source_card)
		return

	push_error(
		"Dealer card '%s' needs two deck copies for its middle pair."
		% source_card.definition.display_name
	)


static func _requires_matching_middle_pair(
	card: CardInstance
) -> bool:
	if card == null or card.definition == null:
		return false

	var behavior: DealerCardBehavior = card.definition.dealer_behavior
	return (
		behavior != null
		and behavior.requires_matching_middle_pair()
	)


static func _take_matching_card(
	pile: Array[CardInstance],
	definition: CardDefinition
) -> CardInstance:
	for index: int in range(pile.size()):
		var card: CardInstance = pile[index]
		if card == null or card.definition != definition:
			continue

		pile.remove_at(index)
		return card

	return null


static func _replace_middle_from_pile(
	dealer: DealerState,
	target_slot_id: int,
	pair_card: CardInstance,
	return_pile: Array[CardInstance],
	return_zone: CardZone.Type
) -> void:
	var displaced_card: CardInstance = dealer.slots.get(
		target_slot_id,
		null
	) as CardInstance

	if displaced_card != null:
		displaced_card.zone = return_zone
		displaced_card.current_slot = CardInstance.NO_SLOT
		return_pile.push_front(displaced_card)

	pair_card.zone = CardZone.Type.DEALER_BOARD
	pair_card.current_slot = target_slot_id
	dealer.slots[target_slot_id] = pair_card


static func _print_middle_pair(source_card: CardInstance) -> void:
	print(
		"DEALER MIDDLE PAIR | card=",
		source_card.definition.display_name
	)


static func _recycle_discard(
	dealer: DealerState
) -> void:
	for card: CardInstance in dealer.discard_pile:
		card.zone = CardZone.Type.DRAW
		card.current_slot = CardInstance.NO_SLOT
		dealer.draw_pile.append(card)

	dealer.discard_pile.clear()
	dealer.draw_pile.shuffle()
