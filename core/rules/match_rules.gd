class_name MatchRules
extends Resource


@export_category("Draw")

@export_range(1, 10, 1)
var starting_hand_size: int = 5

@export_range(1, 10, 1)
var cards_drawn_per_turn: int = 5


@export_category("Scoring")

@export_range(0, 3, 1)
var loss_points: int = 0

@export_range(0, 3, 1)
var tie_points: int = 1

@export_range(0, 3, 1)
var win_points: int = 3


@export_category("Mana")

@export_range(0, 10, 1)
var starting_mana: int = 2

@export_range(0, 10, 1)
var mana_gain_per_turn: int = 1

@export_range(0, 20, 1)
var maximum_mana: int = 10


@export_category("Victory")

@export_range(1, 200, 1)
var winning_score_difference: int = 40
