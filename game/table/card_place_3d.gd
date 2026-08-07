class_name CardPlace3D
extends Area3D


enum Kind {
	PLAYER_BOARD,
	DEALER,
	HAND
}


@export var kind: Kind = Kind.PLAYER_BOARD
@export_range(0, 2, 1) var owner_id: int = 0
@export var logical_id: int = -1


@onready var card_anchor: Marker3D = $CardAnchor

func _ready() -> void:
	input_ray_pickable = false
