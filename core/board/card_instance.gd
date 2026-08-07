class_name CardInstance
extends RefCounted


const NO_SLOT: int = -1

var ability_used: bool = false
var instance_id: int
var definition: CardDefinition
var owner_id: int

var zone: CardZone.Type = CardZone.Type.DRAW
var current_slot: int = NO_SLOT
var turn_played: int = -1
var disabled_combat_turn: int = -1
var shield_count: int = 0
var shields_initialized: bool = false
func _init(
	new_instance_id: int,
	new_definition: CardDefinition,
	new_owner_id: int
) -> void:
	instance_id = new_instance_id
	definition = new_definition
	owner_id = new_owner_id

func is_disabled_in_combat(
	combat_turn: int
) -> bool:
	return disabled_combat_turn == combat_turn

func reset_for_board_entry() -> void:
	# افکت‌های یک‌بارمصرف برای ورود جدید به Board آماده می‌شوند.
	ability_used = false

	# وضعیت‌های موقت Combat قبلی پاک می‌شوند.
	disabled_combat_turn = -1

	# شیلدهای قبلی نباید بعد از Discard باقی بمانند.
	shield_count = 0
	shields_initialized = false
