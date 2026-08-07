class_name DealerState
extends RefCounted


var draw_pile: Array[CardInstance] = []
var slots: Dictionary = {}
var discard_pile: Array[CardInstance] = []

func _init() -> void:
	for slot_id: int in DealerSlotID.all_slots():
		slots[slot_id] = null
