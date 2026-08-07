class_name CreditCardBehavior
extends CardBehavior


func modify_battle_outcome(
	state: MatchState,
	source_card: CardInstance,
	opponent_card: CardInstance,
	current_outcome: int
) -> int:
	if state == null:
		return current_outcome

	if source_card == null:
		return current_outcome

	if source_card.definition == null:
		return current_outcome

	if opponent_card == null:
		return current_outcome

	if opponent_card.definition == null:
		return current_outcome

	# قدرت فقط در اولین Turn حضور کارت روی Board فعال است.
	if source_card.turn_played != state.turn_number:
		return current_outcome

	# کارت بانکی فقط در اولین Turn می‌تواند
	# Scissors را برخلاف Paper معمولی شکست دهد.
	if (
		opponent_card.definition.gesture
		!= CardGesture.Type.SCISSORS
	):
		return current_outcome

	print(
		"CREDIT CARD BOOST | defeated SCISSORS | opponent=",
		opponent_card.definition.display_name
	)

	return BattleAct.Outcome.WIN
