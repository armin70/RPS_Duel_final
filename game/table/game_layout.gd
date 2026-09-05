class_name GameLayout3D
extends Node3D


# Source 2.5D arena image.
const BOARD_IMAGE_SIZE: Vector2 = Vector2(2048.0, 921.0)
const BOARD_IMAGE_ASPECT: float = BOARD_IMAGE_SIZE.x / BOARD_IMAGE_SIZE.y

# A real horizontal plane in 3D. With the original perspective camera this
# produces the board-game composition from the reference: far side smaller,
# player side larger, while all artwork still comes from one flat texture.
const GROUND_TEXTURE_PATH: String = "res://art/main_land/Land2.5D_V1.1.png"
const GROUND_NODE_NAME: String = "Land2DWorldPlane"
const GROUND_WORLD_WIDTH: float = 9.5
const GROUND_WORLD_DEPTH: float = GROUND_WORLD_WIDTH / BOARD_IMAGE_ASPECT
const GROUND_WORLD_Y: float = -0.13
const GROUND_WORLD_CENTER_Z: float = -0.35
const SLOT_WORLD_Y: float = -0.095

# Original gameplay camera from the pre-2.5D scene.
const GAME_CAMERA_POSITION: Vector3 = Vector3(0.0, 3.066, 2.596)
const GAME_CAMERA_ROTATION_DEGREES: Vector3 = Vector3(-53.4, 0.0, 0.0)
const GAME_CAMERA_FOV: float = 45.0

# Hands are intentionally independent from the field layout.
# Player hand stays large in the foreground; opponent hand stays at the top.
const PLAYER_HAND_POSITION: Vector3 = Vector3(0.0, 0.45, 1.80)
const PLAYER_HAND_SCALE: float = 1.15
const OPPONENT_HAND_POSITION: Vector3 = Vector3(0.0, 0.08, -2.02)
const OPPONENT_HAND_SCALE: float = 1.05

# Field cards should fill the printed slots rather than looking like tiny
# pieces in the middle of the illustration.
const BOARD_CARD_SCALE: float = 1.45

# Five printed columns, left to right:
# player back (I), player front (II), dealer, enemy front (II), enemy back (I).
const PLAYER_BACK_X_PX: float = 684.5
const PLAYER_FRONT_X_PX: float = 829.5
const DEALER_X_PX: float = 1024.0
const OPPONENT_FRONT_X_PX: float = 1221.0
const OPPONENT_BACK_X_PX: float = 1368.5

# Four logical lanes, top to bottom, measured directly on the source image.
const LANE_LEFT_Y_PX: float = 166.0
const LANE_MIDDLE_0_Y_PX: float = 345.0
const LANE_MIDDLE_1_Y_PX: float = 508.0
const LANE_RIGHT_Y_PX: float = 684.0


@export_category("Hand Layout")
@export var hand_spacing: float = 0.25
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
	_configure_reference_camera()
	_configure_reference_ground()
	_apply_reference_field_layout()
	_configure_reference_hands()
	_configure_dealer_places()
	_configure_board_places()

	var viewport := get_viewport()
	if viewport != null:
		var resize_callable := Callable(self, "_late_apply_reference_layout")
		if not viewport.size_changed.is_connected(resize_callable):
			viewport.size_changed.connect(resize_callable)

	_connect_legacy_camera_arrival_signal()

	# A real window resize already proves these final values are correct.
	# The only startup issue is ordering: the binary scene / old intro camera can
	# write its transform after our first _ready(). Re-apply the exact same
	# layout after the scene has rendered a few frames, then once more shortly
	# afterward. This makes the first visible game state match the resized state.
	call_deferred("_stabilize_initial_reference_layout")


func _late_apply_reference_layout() -> void:
	_configure_reference_camera()
	_configure_reference_ground()
	_apply_reference_field_layout()
	_configure_reference_hands()


func _stabilize_initial_reference_layout() -> void:
	# Let all sibling _ready() methods and one deferred queue finish first.
	await get_tree().process_frame
	await get_tree().process_frame
	_late_apply_reference_layout()

	# Some old binary-scene camera setup finishes a little later than _ready().
	# Re-applying after a short delay is equivalent to the manual resize that
	# currently fixes the view, but happens automatically before interaction.
	await get_tree().create_timer(0.12).timeout
	_late_apply_reference_layout()

	await get_tree().create_timer(0.35).timeout
	_late_apply_reference_layout()


func _connect_legacy_camera_arrival_signal() -> void:
	var camera := _get_game_camera()
	if camera == null:
		return

	# Older main_game.scn builds can still have IntroCameraController attached.
	# If it completes a tween after startup, restore the gameplay view once the
	# camera reports that it has arrived.
	if not camera.has_signal("camera_arrived_at_game"):
		return

	var callback := Callable(self, "_on_legacy_camera_arrived")
	if not camera.is_connected("camera_arrived_at_game", callback):
		camera.connect("camera_arrived_at_game", callback)


func _on_legacy_camera_arrived() -> void:
	call_deferred("_late_apply_reference_layout")


func _get_game_camera() -> Camera3D:
	var scene_root: Node = get_parent()
	if scene_root != null:
		var scene_camera := scene_root.get_node_or_null("Camera3D") as Camera3D
		if scene_camera != null:
			return scene_camera

	return get_viewport().get_camera_3d()


func _configure_reference_camera() -> void:
	var camera := _get_game_camera()
	if camera == null:
		push_error("GameLayout3D: Camera3D is missing.")
		return

	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.position = GAME_CAMERA_POSITION
	camera.rotation_degrees = GAME_CAMERA_ROTATION_DEGREES
	camera.fov = GAME_CAMERA_FOV
	camera.near = 0.05
	camera.far = 100.0
	camera.current = true


func _get_existing_scene_ground() -> Sprite3D:
	var scene_root: Node = get_parent()
	if scene_root == null:
		return null

	var board_visual := scene_root.get_node_or_null("BoardVisual") as Node3D
	if board_visual == null:
		return null

	return board_visual.get_node_or_null("GroundMap") as Sprite3D


func _hide_legacy_world_if_needed() -> void:
	var scene_root: Node = get_parent()
	if scene_root == null:
		return

	var board_visual := scene_root.get_node_or_null("BoardVisual") as Node3D
	if board_visual != null:
		# The text .tscn already contains our lightweight GroundMap.
		# The older binary .scn contains the heavy 3D world instead.
		if board_visual.get_node_or_null("GroundMap") != null:
			board_visual.visible = true
		else:
			board_visual.visible = false

	var old_land := scene_root.get_node_or_null("Land&Inviormentglb") as Node3D
	if old_land != null:
		old_land.visible = false


func _configure_ground_sprite(ground: Sprite3D) -> void:
	if ground == null:
		return

	var texture := load(GROUND_TEXTURE_PATH) as Texture2D
	if texture == null:
		push_error(
			"GameLayout3D: Could not load 2.5D ground texture: %s"
			% GROUND_TEXTURE_PATH
		)
		return

	ground.texture = texture
	ground.pixel_size = GROUND_WORLD_WIDTH / BOARD_IMAGE_SIZE.x
	ground.shaded = false
	ground.double_sided = true
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.global_position = Vector3(
		0.0,
		GROUND_WORLD_Y,
		GROUND_WORLD_CENTER_Z
	)
	ground.global_rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	ground.scale = Vector3.ONE
	ground.visible = true


func _configure_reference_ground() -> void:
	_hide_legacy_world_if_needed()

	var ground := _get_existing_scene_ground()
	if ground != null:
		_configure_ground_sprite(ground)
		return

	# Compatibility path for the old binary main_game.scn.
	var scene_root: Node = get_parent()
	if scene_root == null:
		return

	ground = scene_root.get_node_or_null(GROUND_NODE_NAME) as Sprite3D
	if ground == null:
		ground = Sprite3D.new()
		ground.name = GROUND_NODE_NAME
		scene_root.add_child(ground)

	_configure_ground_sprite(ground)


func _configure_reference_hands() -> void:
	if player_hand_origin != null:
		player_hand_origin.position = PLAYER_HAND_POSITION
		player_hand_origin.rotation = Vector3.ZERO
		player_hand_origin.scale = Vector3.ONE * PLAYER_HAND_SCALE

	if opponent_hand_origin != null:
		opponent_hand_origin.position = OPPONENT_HAND_POSITION
		opponent_hand_origin.rotation = Vector3.ZERO
		opponent_hand_origin.scale = Vector3.ONE * OPPONENT_HAND_SCALE


func _pixel_to_local(pixel_position: Vector2) -> Vector3:
	var normalized_x: float = pixel_position.x / BOARD_IMAGE_SIZE.x
	var normalized_y: float = pixel_position.y / BOARD_IMAGE_SIZE.y

	var global_point := Vector3(
		(normalized_x - 0.5) * GROUND_WORLD_WIDTH,
		SLOT_WORLD_Y,
		GROUND_WORLD_CENTER_Z
			+ (normalized_y - 0.5) * GROUND_WORLD_DEPTH
	)

	return to_local(global_point)


func _lane_pixel_y_from_board_slot(slot_id: int) -> float:
	match slot_id:
		SlotID.Type.FRONT_LEFT, SlotID.Type.BACK_LEFT:
			return LANE_LEFT_Y_PX
		SlotID.Type.FRONT_MIDDLE_0, SlotID.Type.BACK_MIDDLE_0:
			return LANE_MIDDLE_0_Y_PX
		SlotID.Type.FRONT_MIDDLE_1, SlotID.Type.BACK_MIDDLE_1:
			return LANE_MIDDLE_1_Y_PX
		SlotID.Type.FRONT_RIGHT, SlotID.Type.BACK_RIGHT:
			return LANE_RIGHT_Y_PX

	return BOARD_IMAGE_SIZE.y * 0.5


func _lane_pixel_y_from_dealer_slot(slot_id: int) -> float:
	match slot_id:
		DealerSlotID.Type.LEFT:
			return LANE_LEFT_Y_PX
		DealerSlotID.Type.MIDDLE_0:
			return LANE_MIDDLE_0_Y_PX
		DealerSlotID.Type.MIDDLE_1:
			return LANE_MIDDLE_1_Y_PX
		DealerSlotID.Type.RIGHT:
			return LANE_RIGHT_Y_PX

	return BOARD_IMAGE_SIZE.y * 0.5


func _column_pixel_x(player_id: int, slot_id: int) -> float:
	var row: int = SlotID.get_row(slot_id)

	if player_id == 1:
		return (
			PLAYER_FRONT_X_PX
			if row == SlotID.Row.FRONT
			else PLAYER_BACK_X_PX
		)

	return (
		OPPONENT_FRONT_X_PX
		if row == SlotID.Row.FRONT
		else OPPONENT_BACK_X_PX
	)


func _apply_reference_field_layout() -> void:
	# Remove all offsets that belonged to the previous horizontal 3D table.
	$PlayerBoard.transform = Transform3D.IDENTITY
	$PlayerBoard/FrontRow.transform = Transform3D.IDENTITY
	$PlayerBoard/BackRow.transform = Transform3D.IDENTITY
	$OpponentBoard.transform = Transform3D.IDENTITY
	$OpponentBoard/FrontRow.transform = Transform3D.IDENTITY
	$OpponentBoard/BackRow.transform = Transform3D.IDENTITY
	$DealerRow.transform = Transform3D.IDENTITY

	var card_basis := Basis.IDENTITY.scaled(
		Vector3.ONE * BOARD_CARD_SCALE
	)

	for player_id: int in board_places:
		var player_places: Dictionary = board_places[player_id]

		for slot_id: int in player_places:
			var place := player_places[slot_id] as CardPlace3D
			if place == null:
				continue

			var pixel_position := Vector2(
				_column_pixel_x(player_id, slot_id),
				_lane_pixel_y_from_board_slot(slot_id)
			)

			place.transform = Transform3D(
				card_basis,
				_pixel_to_local(pixel_position)
			)

	for slot_id: int in dealer_places:
		var dealer_place := dealer_places[slot_id] as CardPlace3D
		if dealer_place == null:
			continue

		var dealer_pixel := Vector2(
			DEALER_X_PX,
			_lane_pixel_y_from_dealer_slot(slot_id)
		)

		dealer_place.transform = Transform3D(
			card_basis,
			_pixel_to_local(dealer_pixel)
		)


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

	# Layer 2 is reserved for board drop targets.
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

	# Middle cards remain on their exact upper/lower half of the tall printed
	# middle rectangle; a single middle card is not re-centered.
	return get_board_anchor_transform(
		player_id,
		slot_id
	)
