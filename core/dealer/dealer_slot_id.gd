class_name DealerSlotID
extends RefCounted


enum Type {
	LEFT,
	MIDDLE_0,
	MIDDLE_1,
	RIGHT
}


static func all_slots() -> Array[int]:
	return [
		Type.LEFT,
		Type.MIDDLE_0,
		Type.MIDDLE_1,
		Type.RIGHT
	]


static func get_lane(slot_id: int) -> SlotID.Lane:
	match slot_id:
		Type.LEFT:
			return SlotID.Lane.LEFT

		Type.RIGHT:
			return SlotID.Lane.RIGHT

		Type.MIDDLE_0, Type.MIDDLE_1:
			return SlotID.Lane.MIDDLE

	push_error("Invalid Dealer slot: %d" % slot_id)
	return SlotID.Lane.MIDDLE
