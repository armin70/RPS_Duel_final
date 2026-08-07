class_name SlotID
extends RefCounted


enum Type {
	FRONT_LEFT,
	FRONT_MIDDLE_0,
	FRONT_MIDDLE_1,
	FRONT_RIGHT,

	BACK_LEFT,
	BACK_MIDDLE_0,
	BACK_MIDDLE_1,
	BACK_RIGHT
}


enum Row {
	FRONT,
	BACK
}


enum Lane {
	LEFT,
	MIDDLE,
	RIGHT
}


static func all_slots() -> Array[int]:
	return [
		Type.FRONT_LEFT,
		Type.FRONT_MIDDLE_0,
		Type.FRONT_MIDDLE_1,
		Type.FRONT_RIGHT,

		Type.BACK_LEFT,
		Type.BACK_MIDDLE_0,
		Type.BACK_MIDDLE_1,
		Type.BACK_RIGHT
	]


static func is_valid(slot_id: int) -> bool:
	return slot_id in all_slots()


static func get_row(slot_id: int) -> Row:
	if slot_id <= Type.FRONT_RIGHT:
		return Row.FRONT

	return Row.BACK


static func get_lane(slot_id: int) -> Lane:
	if slot_id in [
		Type.FRONT_LEFT,
		Type.BACK_LEFT
	]:
		return Lane.LEFT

	if slot_id in [
		Type.FRONT_RIGHT,
		Type.BACK_RIGHT
	]:
		return Lane.RIGHT

	return Lane.MIDDLE


static func get_position(slot_id: int) -> int:
	if slot_id in [
		Type.FRONT_MIDDLE_1,
		Type.BACK_MIDDLE_1
	]:
		return 1

	return 0
