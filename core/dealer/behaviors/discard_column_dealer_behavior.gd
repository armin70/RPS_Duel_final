class_name DiscardColumnDealerBehavior
extends DealerCardBehavior


func on_enter_board(
	state: MatchState,
	dealer_card: CardInstance,
	dealer_slot_id: int
) -> void:
	if state == null:
		return

	if dealer_card == null:
		return

	var target_slots: Array[int] = \
		_get_target_slots(dealer_slot_id)

	if target_slots.is_empty():
		return

	# کارت‌های هر دو بازیکن بررسی می‌شوند.
	for player_id: int in [1, 2]:
		var player: PlayerState = state.get_player(
			player_id
		)

		if player == null:
			continue

		for player_slot_id: int in target_slots:
			var discarded_card: CardInstance = \
				CardMover.board_to_discard(
					player,
					player_slot_id
				)

			if discarded_card == null:
				continue

			print(
				"DEALER COLUMN DISCARD | player=",
				player_id,
				" | slot=",
				player_slot_id,
				" | card=",
				discarded_card.definition.display_name
			)


func _get_target_slots(
	dealer_slot_id: int
) -> Array[int]:
	match dealer_slot_id:
		DealerSlotID.Type.LEFT:
			return [
				SlotID.Type.FRONT_LEFT,
				SlotID.Type.BACK_LEFT
			]

		DealerSlotID.Type.MIDDLE_0:
			return [
				SlotID.Type.FRONT_MIDDLE_0,
				SlotID.Type.BACK_MIDDLE_0
			]

		DealerSlotID.Type.MIDDLE_1:
			return [
				SlotID.Type.FRONT_MIDDLE_1,
				SlotID.Type.BACK_MIDDLE_1
			]

		DealerSlotID.Type.RIGHT:
			return [
				SlotID.Type.FRONT_RIGHT,
				SlotID.Type.BACK_RIGHT
			]

	return []
