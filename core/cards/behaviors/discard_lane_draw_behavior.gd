class_name DiscardLaneDrawBehavior
extends CardBehavior


func on_played_to_board(
	context: CardBehaviorContext
) -> void:
	if context == null:
		return

	var player: PlayerState = context.get_owner()

	if player == null:
		return

	var source_card: CardInstance = \
		context.source_card

	if source_card == null:
		return

	var target_slots: Array[int] = \
		_get_lane_slots(context.slot_id)

	if target_slots.is_empty():
		return

	var discarded_count: int = 0

	# اگر کارت روی کارت دیگری قرار گرفته باشد،
	# کارت زیرین قبلاً توسط سیستم Cover حذف شده است.
	if context.replaced_card != null:
		discarded_count += 1

	# کارت‌های دیگر همان لاین حذف می‌شوند.
	for target_slot_id: int in target_slots:
		var target_card: CardInstance = \
			player.board.get_card(
				target_slot_id
			)

		if target_card == null:
			continue

		# خود کارت افکت‌دار روی Board باقی می‌ماند.
		if target_card == source_card:
			continue

		var removed_card: CardInstance = \
			CardMover.board_to_discard(
				player,
				target_slot_id
			)

		if removed_card == null:
			continue

		discarded_count += 1

		print(
			"LANE DISCARD | card=",
			removed_card.definition.display_name,
			" | slot=",
			target_slot_id
		)

	# به تعداد کارت‌های حذف‌شده Draw می‌کنیم.
	var drawn_cards: Array[CardInstance] = \
		CardMover.draw_cards_to_hand(
			player,
			discarded_count
		)

	print(
		"LANE DISCARD DRAW | source=",
		source_card.definition.display_name,
		" | discarded=",
		discarded_count,
		" | drawn=",
		drawn_cards.size()
	)


func _get_lane_slots(
	source_slot_id: int
) -> Array[int]:
	match source_slot_id:
		SlotID.Type.FRONT_LEFT, \
		SlotID.Type.BACK_LEFT:
			return [
				SlotID.Type.FRONT_LEFT,
				SlotID.Type.BACK_LEFT
			]

		SlotID.Type.FRONT_RIGHT, \
		SlotID.Type.BACK_RIGHT:
			return [
				SlotID.Type.FRONT_RIGHT,
				SlotID.Type.BACK_RIGHT
			]

		SlotID.Type.FRONT_MIDDLE_0, \
		SlotID.Type.FRONT_MIDDLE_1, \
		SlotID.Type.BACK_MIDDLE_0, \
		SlotID.Type.BACK_MIDDLE_1:
			return [
				SlotID.Type.FRONT_MIDDLE_0,
				SlotID.Type.FRONT_MIDDLE_1,
				SlotID.Type.BACK_MIDDLE_0,
				SlotID.Type.BACK_MIDDLE_1
			]

	return []
