class_name BoardState
extends RefCounted


var slots: Dictionary = {}


func _init() -> void:
	for slot_id: int in SlotID.all_slots():
		slots[slot_id] = null


func is_slot_empty(slot_id):
	if not SlotID.is_valid(slot_id):
		return false

	return slots[slot_id] == null


func get_card(slot_id: int) -> CardInstance:
	if not SlotID.is_valid(slot_id):
		return null

	return slots.get(slot_id, null)


func place_card(
	slot_id: int,
	card_instance: CardInstance
) -> bool:
	if card_instance == null:
		return false

	if not SlotID.is_valid(slot_id):
		return false

	if not is_slot_empty(slot_id):
		return false

	slots[slot_id] = card_instance

	card_instance.zone = CardZone.Type.BOARD
	card_instance.current_slot = slot_id

	return true


func remove_card(slot_id: int) -> CardInstance:
	if not SlotID.is_valid(slot_id):
		return null

	var card: CardInstance = get_card(slot_id)

	if card == null:
		return null

	slots[slot_id] = null
	card.current_slot = CardInstance.NO_SLOT

	return card

func move_card(
	from_slot_id: int,
	to_slot_id: int
) -> bool:
	if not SlotID.is_valid(from_slot_id):
		return false

	if not SlotID.is_valid(to_slot_id):
		return false

	if from_slot_id == to_slot_id:
		return false

	var moving_card: CardInstance = get_card(
		from_slot_id
	)

	if moving_card == null:
		return false

	var destination_card: CardInstance = get_card(
		to_slot_id
	)

	# مقصد خالی باشد: Move معمولی
	# مقصد کارت داشته باشد: دو کارت Switch می‌شوند
	slots[to_slot_id] = moving_card
	slots[from_slot_id] = destination_card

	moving_card.zone = CardZone.Type.BOARD
	moving_card.current_slot = to_slot_id

	if destination_card != null:
		destination_card.zone = CardZone.Type.BOARD
		destination_card.current_slot = from_slot_id

	return true
func get_occupied_cards() -> Array[CardInstance]:
	var occupied_cards: Array[CardInstance] = []

	for slot_id: int in SlotID.all_slots():
		var card: CardInstance = get_card(slot_id)

		if card != null:
			occupied_cards.append(card)

	return occupied_cards
