class_name ChangelingBehavior
extends CardBehavior

@export_enum("WIN", "TIE", "LOSS") var trigger_outcome: int = BattleAct.Outcome.WIN
@export var next_definition_path: String = ""


func on_battle_resolved(
	context: CardBehaviorContext,
	outcome: int,
	_opponent_card: CardInstance,
	_act_type: int
) -> void:
	if context == null or context.source_card == null:
		return
	if outcome != trigger_outcome:
		return
	if next_definition_path.is_empty():
		return

	# Do not visually/type-swap in the middle of a multi-clash battle. The
	# MatchEngine applies this after every BattleAct has finished.
	if context.source_card.pending_definition_path.is_empty():
		context.source_card.pending_definition_path = next_definition_path
