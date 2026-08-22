class_name GameLayout3D
extends Node3D


@export_category("Hand Layout")
@export var hand_spacing: float = .25
@export var hand_angle_degrees: float = 10.0
@export var hand_arc_depth: float = 0.03


@onready var player_hand_origin: Node3D = $PlayerHand

@onready var opponent_hand_origin: Node3D = $OpponentHand
@onready var dealer_places: Dictionary = {
	DealerSlotID.Type.LEFT:
		$DealerRow/DealerLeft,

	DealerSlotID.Type.MIDDLE_0:
		$DealerRow/DealerMiddle0,

	DealerSlotID.Type.MIDDLE_1:
		$DealerRow/DealerMiddle1,

	DealerSlotID.Type.RIGHT:
		$DealerRow/DealerRight
}


@onready var board_places: Dictionary = {
	1: {
		SlotID.Type.FRONT_LEFT:
			$PlayerBoard/FrontRow/FrontLeft,
		SlotID.Type.FRONT_MIDDLE_0:
			$PlayerBoard/FrontRow/FrontMiddle0,
		SlotID.Type.FRONT_MIDDLE_1:
			$PlayerBoard/FrontRow/FrontMiddle1,
		SlotID.Type.FRONT_RIGHT:
			$PlayerBoard/FrontRow/FrontRight,

		SlotID.Type.BACK_LEFT:
			$PlayerBoard/BackRow/BackLeft,
		SlotID.Type.BACK_MIDDLE_0:
			$PlayerBoard/BackRow/BackMiddle0,
		SlotID.Type.BACK_MIDDLE_1:
			$PlayerBoard/BackRow/BackMiddle1,
		SlotID.Type.BACK_RIGHT:
			$PlayerBoard/BackRow/BackRight
	},

	2: {
		SlotID.Type.FRONT_LEFT:
			$OpponentBoard/FrontRow/FrontLeft,
		SlotID.Type.FRONT_MIDDLE_0:
			$OpponentBoard/FrontRow/FrontMiddle0,
		SlotID.Type.FRONT_MIDDLE_1:
			$OpponentBoard/FrontRow/FrontMiddle1,
		SlotID.Type.FRONT_RIGHT:
			$OpponentBoard/FrontRow/FrontRight,

		SlotID.Type.BACK_LEFT:
			$OpponentBoard/BackRow/BackLeft,
		SlotID.Type.BACK_MIDDLE_0:
			$OpponentBoard/BackRow/BackMiddle0,
		SlotID.Type.BACK_MIDDLE_1:
			$OpponentBoard/BackRow/BackMiddle1,
		SlotID.Type.BACK_RIGHT:
			$OpponentBoard/BackRow/BackRight
	}
}

@onready var pile_entities: Dictionary = {
	1: {
		CardPile3D.Type.DRAW:
			$PlayerPiles/DrawPile,

		CardPile3D.Type.DISCARD:
			$PlayerPiles/DiscardPile,

		CardPile3D.Type.RESERVE:
			$PlayerPiles/ReservePile
	},

	2: {
		CardPile3D.Type.DRAW:
			$OpponentPiles/DrawPile,

		CardPile3D.Type.DISCARD:
			$OpponentPiles/DiscardPile,

		CardPile3D.Type.RESERVE:
			$OpponentPiles/ReservePile
	}
}

func _ready() -> void:
	_configure_dealer_places()
	_configure_board_places()


func _configure_dealer_places() -> void:
	for slot_id: int in dealer_places:
		var place := dealer_places[slot_id] as CardPlace3D

		_configure_place(
			place,
			CardPlace3D.Kind.DEALER,
			0,
			slot_id
		)


func _configure_board_places() -> void:
	for player_id: int in board_places:
		var player_places: Dictionary = board_places[player_id]

		for slot_id: int in player_places:
			var place := (
				player_places[slot_id] as CardPlace3D
			)

			_configure_place(
				place,
				CardPlace3D.Kind.PLAYER_BOARD,
				player_id,
				slot_id
			)


func _configure_place(
	place: CardPlace3D,
	kind: CardPlace3D.Kind,
	owner_id: int,
	logical_id: int
) -> void:
	if place == null:
		return

	place.kind = kind
	place.owner_id = owner_id
	place.logical_id = logical_id

	# Layer 2 مخصوص جایگاه‌های Drop است.
	place.collision_layer = 2
	place.collision_mask = 0
	place.input_ray_pickable = true


func get_dealer_anchor(
	slot_id: int
) -> Marker3D:
	var place := dealer_places.get(
		slot_id,
		null
	) as CardPlace3D

	if place == null:
		return null

	return place.card_anchor


func get_board_place(
	player_id: int,
	slot_id: int
) -> CardPlace3D:
	var player_places: Dictionary = board_places.get(
		player_id,
		{}
	)

	return player_places.get(
		slot_id,
		null
	) as CardPlace3D

func get_hand_transform(
	player_id: int,
	index: int,
	card_count: int
) -> Transform3D:
	var hand_origin: Node3D

	if player_id == 1:
		hand_origin = player_hand_origin
	else:
		hand_origin = opponent_hand_origin

	if card_count <= 0:
		return hand_origin.global_transform

	var center: float = float(card_count - 1) / 2.0
	var offset: float = float(index) - center

	var local_position := Vector3(
		offset * hand_spacing,
		0.0,
		abs(offset) * hand_arc_depth
	)

	var angle: float = deg_to_rad(
		-offset * hand_angle_degrees
	)

	var local_transform := Transform3D(
		Basis(Vector3.UP, angle),
		local_position
	)

	return hand_origin.global_transform * local_transform


func get_pile_entity(
	player_id: int,
	pile_type: CardPile3D.Type
) -> CardPile3D:
	var player_piles: Dictionary = \
		pile_entities.get(
			player_id,
			{}
		)

	return player_piles.get(
		pile_type,
		null
	) as CardPile3D


func get_board_anchor_transform(
	player_id: int,
	slot_id: int
) -> Transform3D:
	var place: CardPlace3D = get_board_place(
		player_id,
		slot_id
	)

	if place == null or place.card_anchor == null:
		return Transform3D.IDENTITY

	return place.card_anchor.global_transform


func get_middle_row_center_transform(
	player_id: int,
	row: int
) -> Transform3D:
	var first_slot_id: int
	var second_slot_id: int

	if row == SlotID.Row.FRONT:
		first_slot_id = SlotID.Type.FRONT_MIDDLE_0
		second_slot_id = SlotID.Type.FRONT_MIDDLE_1
	else:
		first_slot_id = SlotID.Type.BACK_MIDDLE_0
		second_slot_id = SlotID.Type.BACK_MIDDLE_1

	var first_transform: Transform3D = get_board_anchor_transform(
		player_id,
		first_slot_id
	)
	var second_transform: Transform3D = get_board_anchor_transform(
		player_id,
		second_slot_id
	)

	var centered: Transform3D = first_transform
	centered.origin = (
		first_transform.origin
		+ second_transform.origin
	) * 0.5

	return centered


func get_board_visual_transform(
	player_id: int,
	slot_id: int,
	_middle_row_card_count: int = 2
) -> Transform3D:
	if not SlotID.is_valid(slot_id):
		return Transform3D.IDENTITY

	# Middle cards stay on the exact left/right slot selected by the player.
	# A single middle card is no longer visually re-centered between the slots.
	return get_board_anchor_transform(
		player_id,
		slot_id
	)
