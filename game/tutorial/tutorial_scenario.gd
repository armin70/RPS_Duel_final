class_name TutorialScenario
extends RefCounted

## Edit this file when you want to change the tutorial match script.
## The controller reads the exact hands, Dealer rows and opponent plays from here.

const ROCK_PATH: String = "res://data/cards/normal_rock.tres"
const PAPER_PATH: String = "res://data/cards/normal_paper.tres"
const SCISSORS_PATH: String = "res://data/cards/normal_scissors.tres"
const MUSTACHE_PATH: String = "res://data/cards/mustache_rock.tres"
const COLLECTOR_PATH: String = "res://data/cards/collector_rock.tres"

const DEALER_ROCK_PATH: String = "res://data/cards/dealer_rock.tres"
const DEALER_PAPER_PATH: String = "res://data/cards/dealer_paper.tres"
const DEALER_SCISSORS_PATH: String = "res://data/cards/dealer_scissors.tres"
const PALE_DIV_PATH: String = "res://data/cards/pale_div.tres"


# -----------------------------------------------------------------------------
# PLAYER HANDS
# -----------------------------------------------------------------------------

static func opening_player_hand() -> Array[String]:
	# Start of the solo teaching section.
	return [
		SCISSORS_PATH,
		ROCK_PATH,
		PAPER_PATH,
	]


static func solo_second_player_hand() -> Array[String]:
	# After the Dealer refresh and before the opponent appears.
	# Scissors is the card the tutorial forces the player to play next.
	return [
		SCISSORS_PATH,
		ROCK_PATH,
		PAPER_PATH,
		PAPER_PATH,
	]


static func turn_2_player_hand() -> Array[String]:
	# The first real mana-teaching turn shown in the reference video.
	return [
		MUSTACHE_PATH,
		COLLECTOR_PATH,
		ROCK_PATH,
		PAPER_PATH,
		PAPER_PATH,
	]


static func turn_3_player_hand() -> Array[String]:
	# Mustache turn. The other cards may be visible, but only Mustache is
	# interactable. A real combat happens before Collector is taught.
	return [
		MUSTACHE_PATH,
		COLLECTOR_PATH,
		SCISSORS_PATH,
		PAPER_PATH,
		PAPER_PATH,
	]


static func collector_turn_player_hand() -> Array[String]:
	# New turn after Mustache has demonstrated its real sweep in combat.
	# Collector costs 3, leaving 2 mana for the final Scissors.
	return [
		COLLECTOR_PATH,
		SCISSORS_PATH,
		PAPER_PATH,
		PAPER_PATH,
		PAPER_PATH,
	]


# -----------------------------------------------------------------------------
# OPPONENT HANDS + EXACT PLAYS
# -----------------------------------------------------------------------------

static func battle_1_bot_hand() -> Array[String]:
	return [
		ROCK_PATH,
		PAPER_PATH,
		PAPER_PATH,
		PAPER_PATH,
		PAPER_PATH,
	]


static func battle_1_bot_plays() -> Array[Dictionary]:
	return [
		{
			"card_path": ROCK_PATH,
			"slot_id": SlotID.Type.FRONT_MIDDLE_0,
		},
	]


static func battle_2_bot_hand() -> Array[String]:
	return [
		SCISSORS_PATH,
		PAPER_PATH,
		PAPER_PATH,
		PAPER_PATH,
		PAPER_PATH,
	]


static func battle_2_bot_plays() -> Array[Dictionary]:
	# Opponent spends only 2 of 3 mana, exactly as the tutorial text says.
	return [
		{
			"card_path": SCISSORS_PATH,
			"slot_id": SlotID.Type.FRONT_LEFT,
		},
	]


static func mustache_battle_bot_hand() -> Array[String]:
	# The opponent keeps its existing board and does not add a new card in the
	# Mustache demonstration battle. These are only hidden hand fillers.
	return [
		PAPER_PATH,
		PAPER_PATH,
		PAPER_PATH,
		PAPER_PATH,
		PAPER_PATH,
	]


static func mustache_battle_bot_plays() -> Array[Dictionary]:
	# Empty on purpose: Mustache is demonstrated against the Dealer using the
	# real MUSTACHE_SWEEP battle act, without introducing another opponent move.
	return []


static func battle_3_bot_hand() -> Array[String]:
	return [
		PAPER_PATH,
		SCISSORS_PATH,
		SCISSORS_PATH,
		SCISSORS_PATH,
		PAPER_PATH,
	]


static func battle_3_bot_plays() -> Array[Dictionary]:
	# Combined with the surviving cards from earlier turns this produces the
	# exact final opponent board from the reference animation:
	# FRONT: Scissors | Rock | Paper | Scissors
	# BACK:            Scissors | Scissors
	return [
		{
			"card_path": PAPER_PATH,
			"slot_id": SlotID.Type.FRONT_MIDDLE_1,
		},
		{
			"card_path": SCISSORS_PATH,
			"slot_id": SlotID.Type.FRONT_RIGHT,
		},
		{
			"card_path": SCISSORS_PATH,
			"slot_id": SlotID.Type.BACK_MIDDLE_0,
		},
		{
			"card_path": SCISSORS_PATH,
			"slot_id": SlotID.Type.BACK_MIDDLE_1,
		},
	]


# -----------------------------------------------------------------------------
# DEALER ROWS (LEFT, MIDDLE_0, MIDDLE_1, RIGHT)
# -----------------------------------------------------------------------------

static func dealer_solo_opening() -> Array[String]:
	return [
		DEALER_SCISSORS_PATH,
		DEALER_ROCK_PATH,
		DEALER_PAPER_PATH,
		DEALER_ROCK_PATH,
	]


static func dealer_first_battle() -> Array[String]:
	# The Dealer refresh that happens while the tutorial is still solo.
	return [
		DEALER_ROCK_PATH,
		DEALER_SCISSORS_PATH,
		DEALER_PAPER_PATH,
		DEALER_PAPER_PATH,
	]


static func dealer_second_battle() -> Array[String]:
	return [
		DEALER_PAPER_PATH,
		DEALER_SCISSORS_PATH,
		DEALER_SCISSORS_PATH,
		DEALER_SCISSORS_PATH,
	]


static func dealer_third_battle() -> Array[String]:
	# All-paper row used for the dedicated Mustache demonstration battle.
	return [
		DEALER_SCISSORS_PATH,
		DEALER_PAPER_PATH,
		DEALER_ROCK_PATH,
		DEALER_PAPER_PATH,
	]


static func dealer_collector_turn() -> Array[String]:
	# Dealer row shown after the Mustache demonstration and during the Collector
	# lesson: Scissors | Rock | Paper | Scissors.
	return [
		DEALER_PAPER_PATH,
		DEALER_PAPER_PATH,
		DEALER_PAPER_PATH,
		DEALER_PAPER_PATH,
	]


static func dealer_after_final_battle() -> Array[String]:
	# Pale Div enters MIDDLE_0. Its normal Dealer enter behavior then clears
	# the middle column using the real game logic.
	return [
		DEALER_SCISSORS_PATH,
		PALE_DIV_PATH,
		DEALER_SCISSORS_PATH,
		DEALER_PAPER_PATH,
	]


static func dealer_full_div() -> Array[String]:

	return [
		PALE_DIV_PATH,
		PALE_DIV_PATH,
		PALE_DIV_PATH,
		PALE_DIV_PATH,
	]
