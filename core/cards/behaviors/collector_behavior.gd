class_name CollectorBehavior
extends CardBehavior


@export var collected_gesture: CardGesture.Type = \
	CardGesture.Type.ROCK

@export_range(0, 100, 1)
var points_per_card: int = 1


func on_start_combat(
	context: CardBehaviorContext
) -> void:
	if context == null:
		return

	if context.state == null:
		return

	var source_card: CardInstance = \
		context.source_card

	if source_card == null:
		return

	if source_card.definition == null:
		return

	# این Collector قبلاً در همین حضور روی Board استفاده شده است.
	if source_card.ability_used:
		return

	# Collector فقط یک بار فعال می‌شود؛ حتی اگر Target نداشته باشد.
	source_card.ability_used = true

	# فقط Board صاحب خود Collector بررسی می‌شود.
	var owner: PlayerState = \
		context.state.get_player(
			context.owner_id
		)

	if owner == null:
		return

	# ابتدا Slotها را ذخیره می‌کنیم تا هنگام Discard کردن،
	# تغییر Board باعث خراب‌شدن Loop نشود.
	var target_slot_ids: Array[int] = []

	for slot_id: int in SlotID.all_slots():
		var target_card: CardInstance = \
			owner.board.get_card(
				slot_id
			)

		if target_card == null:
			continue

		if target_card.definition == null:
			continue

		# خود Collector جمع نمی‌شود.
		if target_card == source_card:
			continue

		# کارت‌های چیده‌شده در همین Turn جمع نمی‌شوند.
		if (
			target_card.turn_played
			>= context.state.turn_number
		):
			continue

		if (
			target_card.definition.gesture
			!= collected_gesture
		):
			continue

		target_slot_ids.append(slot_id)

	var discarded_count: int = 0

	for target_slot_id: int in target_slot_ids:
		var discarded_card: CardInstance = \
			CardMover.board_to_discard(
				owner,
				target_slot_id
			)

		if discarded_card != null:
			discarded_count += 1

	var gained_points: int = (
		discarded_count
		* points_per_card
	)

	owner.score += gained_points

	print(
		"COLLECTOR RESOLVED | owner=",
		context.owner_id,
		" | card=",
		source_card.definition.display_name,
		" | discarded=",
		discarded_count,
		" | points=",
		gained_points
	)
