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

# Optional per-instance mana override. Tahmineh uses this for the free Paper
# card created by her passive without mutating the shared CardDefinition.
var mana_cost_override: int = -1

# Runtime Hero state. Normal cards simply leave these values unused.
var hero_moves_this_turn: int = 0
var hero_last_moved_turn: int = -1
var hero_active_used_turn: int = -1
var hero_fury_turn: int = -1
var hero_sleep_turn: int = -1
var hero_root_turn: int = -1
# Tahmineh Active: for the marked turn her R/P/S type cannot be changed by
# covering her with a normal card.
var hero_type_lock_turn: int = -1
# Afrasiab Active is armed for this turn. If he loses directly to the enemy
# Champion/Hero, two Poison cards are inserted at random positions in that opponent's draw pile.
var hero_afrasiab_active_turn: int = -1
var hero_afrasiab_poison_triggered_turn: int = -1
var hero_stealth_turn: int = -1 # legacy, no longer used
# Heroes now use health as the real victory resource. Shield remains a
# temporary one-hit buffer that can be gained by abilities/effects.
var hero_health: int = 0
var hero_max_health: int = 0
# Reveal state is presentation-facing: the local Hero is visible after setup,
# while the opponent Hero becomes public with the first-turn card reveal.
var hero_revealed: bool = false

# Temporary Hero guard. When a Hero covers one of its owner's normal cards,
# the Hero tucks underneath that card for the current turn. The normal card
# remains the active board card and protects the Hero until cleanup.
var hero_guard_card_instance_id: int = -1
var hero_guard_turn: int = -1

# Rush transformation is per CardInstance. Never mutate CardDefinition.gesture,
# because the same Resource is shared by every copy of that card.
var gesture_override: int = -1

# Runtime state for the new special-card families.
# These live on CardInstance so shared CardDefinition resources are never mutated.
var rooted_by_card_turn: int = -1
var debuffed_no_win_turn: int = -1
var op_healer_charges: int = 0
var mommy_triggered_turn: int = -1
var martyr_triggered_turn: int = -1
# Mommy reward cards live in the NEXT hand for one turn only. If they are not
# played before that turn ends, MatchEngine removes them permanently.
var temporary_hand_expire_turn: int = -1
# Legacy field kept for compatibility with any older saved/runtime objects.
var temporary_spawn_expire_turn: int = -1
# Deferred CardDefinition swap used by Changeling. It is applied only after the
# whole battle phase has resolved, so multi-clash cards do not change mid-fight.
var pending_definition_path: String = ""

func is_rooted_by_card(turn_number: int) -> bool:
	return rooted_by_card_turn == turn_number

func cannot_win_due_to_debuffer(turn_number: int) -> bool:
	return debuffed_no_win_turn == turn_number

func is_temporary_spawn() -> bool:
	return temporary_spawn_expire_turn >= 0
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


func get_mana_cost() -> int:
	if mana_cost_override >= 0:
		return mana_cost_override

	if definition == null:
		return 0

	return maxi(0, definition.mana_cost)


func is_hero() -> bool:
	return definition is HeroDefinition


func get_hero_definition() -> HeroDefinition:
	return definition as HeroDefinition


func is_hero_stealthed(turn_number: int) -> bool:
	return is_hero() and hero_stealth_turn == turn_number


func is_hero_furious(turn_number: int) -> bool:
	return is_hero() and hero_fury_turn == turn_number


func is_hero_sleeping(turn_number: int) -> bool:
	return is_hero() and hero_sleep_turn == turn_number


func is_hero_rooted(turn_number: int) -> bool:
	return is_hero() and hero_root_turn == turn_number


func is_hero_type_locked(turn_number: int) -> bool:
	return is_hero() and hero_type_lock_turn == turn_number


func is_hero_afrasiab_active(turn_number: int) -> bool:
	return is_hero() and hero_afrasiab_active_turn == turn_number


func is_hero_guarded() -> bool:
	return (
		is_hero()
		and hero_guard_card_instance_id >= 0
		and hero_guard_turn >= 0
	)


func set_hero_guard(
	protector: CardInstance,
	turn_number: int,
	slot_id: int
) -> void:
	if not is_hero() or protector == null:
		return

	hero_guard_card_instance_id = protector.instance_id
	hero_guard_turn = turn_number
	zone = CardZone.Type.BOARD
	current_slot = slot_id


func clear_hero_guard() -> void:
	hero_guard_card_instance_id = -1
	hero_guard_turn = -1



func is_disabled_in_combat(
	combat_turn: int
) -> bool:
	return disabled_combat_turn == combat_turn

func reset_for_board_entry() -> void:
	# افکت‌های یک‌بارمصرف برای ورود جدید به Board آماده می‌شوند.
	ability_used = false

	# وضعیت‌های موقت Combat قبلی پاک می‌شوند.
	disabled_combat_turn = -1
	rooted_by_card_turn = -1
	debuffed_no_win_turn = -1
	op_healer_charges = 0
	mommy_triggered_turn = -1
	martyr_triggered_turn = -1
	temporary_hand_expire_turn = -1
	temporary_spawn_expire_turn = -1
	pending_definition_path = ""

	# شیلدهای قبلی نباید بعد از Discard باقی بمانند.
	shield_count = 0
	shields_initialized = false
