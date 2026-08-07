class_name CardBehaviorContext
extends RefCounted


var engine: MatchEngine
var state: MatchState
var source_card: CardInstance
var owner_id: int
var slot_id: int

# کارتی که هنگام Cover از زیر کارت جدید حذف شده است.
var replaced_card: CardInstance


func _init(
	new_engine: MatchEngine,
	new_state: MatchState,
	new_source_card: CardInstance,
	new_owner_id: int,
	new_slot_id: int,
	new_replaced_card: CardInstance = null
) -> void:
	engine = new_engine
	state = new_state
	source_card = new_source_card
	owner_id = new_owner_id
	slot_id = new_slot_id
	replaced_card = new_replaced_card


func get_owner() -> PlayerState:
	if state == null:
		return null

	return state.get_player(owner_id)


func get_opponent() -> PlayerState:
	if state == null:
		return null

	var opponent_id: int = (
		2 if owner_id == 1 else 1
	)

	return state.get_player(opponent_id)
