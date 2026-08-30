class_name RootOpponentBehavior
extends CardBehavior

@export var affects_heroes: bool = true

func on_played_to_board(context: CardBehaviorContext) -> void:
	if context == null or context.state == null:
		return
	var opponent: PlayerState = context.get_opponent()
	if opponent == null:
		return
	var target: CardInstance = opponent.board.get_card(context.slot_id)
	if target == null:
		return
	if target.is_hero() and not affects_heroes:
		return
	target.rooted_by_card_turn = context.state.turn_number
	print("ROOT OPPONENT | source=", context.source_card.definition.display_name, " | target=", target.definition.display_name, " | turn=", context.state.turn_number)
