class_name TauntBehavior
extends CardBehavior

@export_range(1, 10, 1)
var starting_shields: int = 3


func on_played_to_board(
	context: CardBehaviorContext
) -> void:
	_initialize_shields(context)


func on_start_combat(
	context: CardBehaviorContext
) -> void:
	# Fallback for cards that entered the board through a non-standard path.
	_initialize_shields(context)


func _initialize_shields(
	context: CardBehaviorContext
) -> void:
	if context == null:
		return

	var source_card: CardInstance = context.source_card
	if source_card == null:
		return

	if source_card.shields_initialized:
		return

	source_card.shields_initialized = true
	source_card.shield_count += starting_shields

	print(
		"TAUNT SHIELDS INITIALIZED | card=",
		source_card.definition.display_name if source_card.definition != null else "Taunt",
		" | shields=",
		source_card.shield_count
	)
