class_name PlayerState
extends RefCounted


var player_id: int

var draw_pile: Array[CardInstance] = []
var hand: Array[CardInstance] = []
var discard_pile: Array[CardInstance] = []
# کارت‌هایی که از Board حذف شده‌اند.
# این کارت‌ها تا Shuffle بعدی وارد چرخه نمی‌شوند.
var reserve_pile: Array[CardInstance] = []
var board: BoardState
var is_ready: bool = false
var current_mana: int = 0
var mana_capacity: int = 0
var score: int = 0
# Score is still kept as match/stat history, but normal-mode victory no longer
# depends on it. Current score gains/losses also charge this 0..60 energy pool.
var energy_points: int = 0
var board_move_used_turn: int = -1

# Every player owns exactly one persistent Hero outside the normal deck cycle.
var hero: CardInstance
var pending_hero_rewards: Array[CardInstance] = []
# Mommy rewards are generated after combat and delivered to the next hand.
var pending_mommy_rewards: Array[CardInstance] = []

func _init(new_player_id: int) -> void:
	player_id = new_player_id
	board = BoardState.new()


func get_remaining_card_count() -> int:
	# Hero cards are persistent board pieces and do not count toward Rush deck
	# elimination. Rush ends when the player's ordinary card pool is exhausted.
	var ordinary_board_cards: int = 0
	for card: CardInstance in board.get_occupied_cards():
		if card != null and not card.is_hero():
			ordinary_board_cards += 1

	return (
		draw_pile.size()
		+ hand.size()
		+ discard_pile.size()
		+ reserve_pile.size()
		+ pending_hero_rewards.size()
		+ pending_mommy_rewards.size()
		+ ordinary_board_cards
	)
