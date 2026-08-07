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
var board_move_used_turn: int = -1

func _init(new_player_id: int) -> void:
	player_id = new_player_id
	board = BoardState.new()
