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

# Rush transformation is per CardInstance. Never mutate CardDefinition.gesture,
# because the same Resource is shared by every copy of that card.
var gesture_override: int = -1
func _init(
	new_instance_id: int,
	new_definition: CardDefinition,
	new_owner_id: int
) -> void:
	instance_id = new_instance_id
	definition = new_definition
	owner_id = new_owner_id

func get_gesture() -> CardGesture.Type:
	if gesture_override >= 0:
		return gesture_override

	if definition == null:
		return CardGesture.Type.ROCK

	return definition.gesture


func has_gesture_override() -> bool:
	return gesture_override >= 0


func set_gesture_override(new_gesture: CardGesture.Type) -> void:
	gesture_override = int(new_gesture)

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
