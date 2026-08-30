class_name CardBehavior
extends Resource


enum DealerAttackType {
	NORMAL,
	SWEEP_WIN,
	CHAINSAW_SWEEP
}


func on_start_combat(
	_context: CardBehaviorContext
) -> void:
	pass


func get_dealer_attack_type(
	_state: MatchState,
	_source_card: CardInstance
) -> int:
	return DealerAttackType.NORMAL


func modify_battle_outcome(
	_state: MatchState,
	_source_card: CardInstance,
	_opponent_card: CardInstance,
	current_outcome: int
) -> int:
	return current_outcome


# Called once after a battle act has been fully resolved and its final
# outcome/points have been applied. Stateful cards use this to react to wins.
func on_battle_resolved(
	_context: CardBehaviorContext,
	_outcome: int,
	_opponent_card: CardInstance,
	_act_type: int
) -> void:
	pass


# آیا این کارت، کارت Player مقابل را پس از برد حذف می‌کند؟
func destroys_defeated_player_card() -> bool:
	return false


# آیا این کارت بعد از پایان Combat از Board خارج می‌شود؟
func expires_after_combat() -> bool:
	return false


func on_played_to_board(
	_context: CardBehaviorContext
) -> void:
	pass
