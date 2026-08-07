class_name FrontShieldBehavior
extends CardBehavior


func on_start_combat(
	context: CardBehaviorContext
) -> void:
	if context == null:
		return

	var source_card: CardInstance = \
		context.source_card

	if source_card == null:
		return

	# این کارت قبلاً Shield خودش را داده است.
	if source_card.ability_used:
		return

	var owner: PlayerState = \
		context.get_owner()

	if owner == null:
		return

	var front_slot_id: int = \
		_get_front_slot(
			context.slot_id
		)

	# کارت باید در ردیف عقب باشد.
	if front_slot_id == -1:
		return

	var target_card: CardInstance = \
		owner.board.get_card(
			front_slot_id
		)

	# کارت جلوی ستون دیگر وجود ندارد.
	# قدرت فعلاً مصرف نمی‌شود.
	if target_card == null:
		return

	# یک Shield اضافه می‌شود و می‌تواند Stack شود.
	target_card.shield_count += 1

	# قدرت این CardInstance برای همیشه مصرف شد.
	source_card.ability_used = true

	print(
		"FRONT SHIELD GRANTED | source=",
		source_card.definition.display_name,
		" | target=",
		target_card.definition.display_name,
		" | shields=",
		target_card.shield_count
	)


func _get_front_slot(
	source_slot_id: int
) -> int:
	match source_slot_id:
		SlotID.Type.BACK_LEFT:
			return SlotID.Type.FRONT_LEFT

		SlotID.Type.BACK_MIDDLE_0:
			return SlotID.Type.FRONT_MIDDLE_0

		SlotID.Type.BACK_MIDDLE_1:
			return SlotID.Type.FRONT_MIDDLE_1

		SlotID.Type.BACK_RIGHT:
			return SlotID.Type.FRONT_RIGHT

	return -1
