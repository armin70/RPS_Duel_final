class_name DisableGestureBehavior
extends CardBehavior


@export var disabled_gesture: CardGesture.Type = \
	CardGesture.Type.ROCK


func disables_target(
	source_slot_id: int,
	target_slot_id: int,
	target_card: CardInstance
) -> bool:
	if target_card == null:
		return false

	if target_card.definition == null:
		return false

	# هنوز فقط Gesture تعیین‌شده را Disable می‌کند.
	if (
		target_card.definition.gesture
		!= disabled_gesture
	):
		return false

	var source_lane: SlotID.Lane = \
		SlotID.get_lane(source_slot_id)

	var target_lane: SlotID.Lane = \
		SlotID.get_lane(target_slot_id)

	# Left فقط Left
	# Right فقط Right
	# هر دو ستون Middle یک Lane محسوب می‌شوند.
	return source_lane == target_lane


static func is_card_disabled(
	state: MatchState,
	target_owner_id: int,
	target_slot_id: int,
	target_card: CardInstance
) -> bool:
	if state == null:
		return false

	if target_card == null:
		return false

	if target_card.definition == null:
		return false

	if not SlotID.is_valid(target_slot_id):
		return false

	var disabler_owner_id: int = (
		2 if target_owner_id == 1 else 1
	)

	var disabler_owner: PlayerState = \
		state.get_player(disabler_owner_id)

	if disabler_owner == null:
		return false

	# تمام کارت‌های حریف بررسی می‌شوند تا ببینیم
	# Disabler فعالی در Lane هدف وجود دارد یا نه.
	for source_slot_id: int in SlotID.all_slots():
		var source_card: CardInstance = \
			disabler_owner.board.get_card(
				source_slot_id
			)

		if source_card == null:
			continue

		if source_card.definition == null:
			continue

		var behavior: DisableGestureBehavior = \
			source_card.definition.behavior \
			as DisableGestureBehavior

		if behavior == null:
			continue

		if behavior.disables_target(
			source_slot_id,
			target_slot_id,
			target_card
		):
			return true

	return false
