class_name OPHealerBehavior
extends CardBehavior

@export_range(1, 20, 1) var starting_charges: int = 5

func on_played_to_board(context: CardBehaviorContext) -> void:
	if context == null or context.source_card == null:
		return
	context.source_card.op_healer_charges = starting_charges

static func try_prevent_loss(
	state: MatchState,
	owner_id: int,
	losing_card: CardInstance,
	current_outcome: int
) -> int:
	if state == null or losing_card == null:
		return current_outcome
	if current_outcome != BattleAct.Outcome.LOSS:
		return current_outcome
	var owner: PlayerState = state.get_player(owner_id)
	if owner == null:
		return current_outcome
	for slot_id: int in SlotID.all_slots():
		var healer: CardInstance = owner.board.get_card(slot_id)
		if healer == null or healer.definition == null:
			continue
		if not (healer.definition.behavior is OPHealerBehavior):
			continue
		if healer.op_healer_charges <= 0:
			continue
		healer.op_healer_charges -= 1
		print("OP HEALER PREVENTED LOSS | owner=", owner_id, " | target=", losing_card.definition.display_name, " | charges_left=", healer.op_healer_charges)
		return BattleAct.Outcome.TIE
	return current_outcome
