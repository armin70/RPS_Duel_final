class_name BattleSequence
extends RefCounted


var acts: Array[BattleAct] = []
var current_index: int = 0


func add_act(act: BattleAct) -> void:
	if act == null:
		return

	acts.append(act)


func has_next() -> bool:
	return current_index < acts.size()


func get_next() -> BattleAct:
	if not has_next():
		return null

	var act: BattleAct = acts[current_index]
	current_index += 1

	return act


func reset() -> void:
	current_index = 0


func is_empty() -> bool:
	return acts.is_empty()
