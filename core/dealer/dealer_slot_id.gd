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
