class_name ChainsawBehavior
extends CardBehavior


func get_dealer_attack_type(
	_state: MatchState,
	source_card: CardInstance
) -> int:
	if source_card == null:
		return DealerAttackType.NORMAL

	# قدرت این CardInstance قبلاً مصرف شده است.
	if source_card.ability_used:
		return DealerAttackType.NORMAL

	# قدرت در اولین فرصت حمله به Dealer مصرف می‌شود.
	source_card.ability_used = true

	print(
		"CHAINSAW ACTIVATED | card=",
		source_card.definition.display_name
	)

	return DealerAttackType.CHAINSAW_SWEEP
