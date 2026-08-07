class_name KillerBehavior
extends CardBehavior


func destroys_defeated_player_card() -> bool:
	return true


func expires_after_combat() -> bool:
	return true
