class_name ToggleBufferBehavior
extends CardBehavior

@export var open_card_path: String = ""
@export var closed_card_path: String = ""


func on_played_to_board(
	context: CardBehaviorContext
) -> void:
	if context == null or context.source_card == null:
		return

	# A newly played copy always begins in its open form.
	context.source_card.ability_used = false
	_apply_state_definition(context.source_card, false)


func on_battle_resolved(
	context: CardBehaviorContext,
	outcome: int,
	_opponent_card: CardInstance,
	_act_type: int
) -> void:
	if context == null or context.source_card == null:
		return

	if outcome != BattleAct.Outcome.WIN:
		return

	var source_card: CardInstance = context.source_card

	# Open + win -> closed.
	if not source_card.ability_used:
		source_card.ability_used = true
		_apply_state_definition(source_card, true)
		return

	# Closed + win -> grant one random friendly shield, then reopen.
	_grant_random_friendly_shield(context)
	source_card.ability_used = false
	_apply_state_definition(source_card, false)


func _apply_state_definition(
	source_card: CardInstance,
	closed_state: bool
) -> void:
	if source_card == null:
		return

	var path: String = closed_card_path if closed_state else open_card_path
	if path.is_empty():
		return

	var next_definition: CardDefinition = ResourceLoader.load(path) as CardDefinition
	if next_definition == null:
		push_warning("ToggleBufferBehavior could not load: " + path)
		return

	source_card.definition = next_definition


func _grant_random_friendly_shield(
	context: CardBehaviorContext
) -> void:
	var owner: PlayerState = context.get_owner()
	if owner == null or owner.board == null:
		return

	var candidates: Array[CardInstance] = []
	for slot_id: int in SlotID.all_slots():
		var card: CardInstance = owner.board.get_card(slot_id)
		if card != null:
			candidates.append(card)

	if candidates.is_empty():
		return

	var target: CardInstance = candidates[randi() % candidates.size()]
	if target == null:
		return

	target.shield_count += 1
	print(
		"TOGGLE BUFFER SHIELD | source=", context.source_card.definition.display_name,
		" | target=", target.definition.display_name,
		" | shields=", target.shield_count
	)
