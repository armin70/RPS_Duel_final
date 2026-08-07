class_name DefenseBehavior
extends CardBehavior


@export_range(1, 10, 1)
var starting_shields: int = 3


func on_start_combat(
	context: CardBehaviorContext
) -> void:
	if context == null:
		return

	var source_card: CardInstance = context.source_card

	if source_card == null:
		return

	# Shield فقط یک بار برای این CardInstance ساخته می‌شود.
	if source_card.shields_initialized:
		return

	source_card.shields_initialized = true
	source_card.shield_count += starting_shields

	print(
		"DEFENSE INITIALIZED | card=",
		source_card.definition.display_name,
		" | shields=",
		source_card.shield_count
	)


func modify_battle_outcome(
	_state: MatchState,
	source_card: CardInstance,
	_opponent_card: CardInstance,
	current_outcome: int
) -> int:
	if source_card == null:
		return current_outcome

	# Shield فقط جلوی LOSS را می‌گیرد.
	if current_outcome != BattleAct.Outcome.LOSS:
		return current_outcome

	# دیگر Shield باقی نمانده است.
	if source_card.shield_count <= 0:
		return current_outcome

	source_card.shield_count -= 1

	print(
		"DEFENSE SHIELD USED | card=",
		source_card.definition.display_name,
		" | shields_left=",
		source_card.shield_count
	)

	# LOSS به TIE تبدیل می‌شود.
	return BattleAct.Outcome.TIE
