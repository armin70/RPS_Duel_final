class_name CardPile3D
extends Node3D


enum Type {
	DRAW,
	DISCARD,
	RESERVE
}


@export_range(1, 2, 1)
var owner_id: int = 1

@export var pile_type: Type = Type.DRAW

@export_category("Visual Stack")

@export_range(1, 30, 1)
var maximum_visible_layers: int = 12

@export_range(0.001, 0.1, 0.001)
var layer_height: float = 0.018


@onready var stack_mesh: MeshInstance3D = \
	$StackMesh

@onready var pile_name_label: Label3D = \
	$PileNameLabel

@onready var count_label: Label3D = \
	$CountLabel

@onready var card_anchor: Marker3D = \
	$CardAnchor


func _ready() -> void:
	_refresh_name()
	set_card_count(0)


func refresh_from_player(
	player: PlayerState
) -> void:
	if player == null:
		set_card_count(0)
		return

	if player.player_id != owner_id:
		set_card_count(0)
		return

	var card_count: int = 0

	match pile_type:
		Type.DRAW:
			card_count = player.draw_pile.size()

		Type.DISCARD:
			card_count = player.discard_pile.size()

		Type.RESERVE:
			card_count = player.reserve_pile.size()

	set_card_count(card_count)


func set_card_count(
	card_count: int
) -> void:
	card_count = maxi(card_count, 0)

	count_label.text = str(card_count)

	if card_count == 0:
		stack_mesh.visible = false
		card_anchor.position.y = 0.03
		return

	stack_mesh.visible = true

	var visible_layers: int = mini(
		card_count,
		maximum_visible_layers
	)

	var stack_height: float = (
		0.06
		+ float(visible_layers - 1)
		* layer_height
	)

	stack_mesh.scale.y = stack_height / 0.06
	stack_mesh.position.y = stack_height / 2.0

	card_anchor.position.y = stack_height


func _refresh_name() -> void:
	match pile_type:
		Type.DRAW:
			pile_name_label.text = "DRAW"

		Type.DISCARD:
			pile_name_label.text = "DISCARD"

		Type.RESERVE:
			pile_name_label.text = "RESERVE"
