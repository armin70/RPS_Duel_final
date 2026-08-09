class_name Card3D
extends Area3D


signal drag_requested(
	card_view: Card3D,
	screen_position: Vector2
)


@export var back_texture: Texture2D


var card_instance: CardInstance
var home_transform: Transform3D
var is_draggable: bool = false
var is_disabled: bool = false


@onready var card_art: MeshInstance3D = $CardArt
@onready var disabled_label: Label3D = $DisabledLabel
@onready var disabled_card: MeshInstance3D = $Disabled_card

@onready var shield_badge: Node3D = %ShieldBadge
@onready var shield_count_label: Label3D = %ShieldCount


const KEEP_RAISE_HEIGHT: float = 0.18


var keep_selected: bool = false
var displayed_shield_count: int = 0
var shield_badge_base_scale: Vector3 = Vector3.ONE
var card_material: StandardMaterial3D


func _ready() -> void:
	shield_badge_base_scale = shield_badge.scale
	shield_badge.visible = false

	collision_layer = 1
	collision_mask = 0
	input_ray_pickable = true

	_create_card_material()


func _create_card_material() -> void:
	if card_material != null:
		return

	card_material = StandardMaterial3D.new()

	# Card art should not change color with table lighting.
	card_material.shading_mode = \
		BaseMaterial3D.SHADING_MODE_UNSHADED

	card_material.cull_mode = \
		BaseMaterial3D.CULL_DISABLED

	card_art.material_override = card_material


func setup(
	new_card_instance: CardInstance,
	new_home_transform: Transform3D,
	new_is_draggable: bool,
	start_face_up: bool = true
) -> void:
	card_instance = new_card_instance
	home_transform = new_home_transform
	is_draggable = new_is_draggable

	global_transform = home_transform

	_create_card_material()
	set_face_up(start_face_up)


func set_face_up(value: bool) -> void:
	_create_card_material()

	if card_material == null:
		return

	if value:
		if (
			card_instance != null
			and card_instance.definition != null
			and card_instance.definition.front_texture != null
		):
			card_material.albedo_texture = \
				card_instance.definition.front_texture
		else:
			card_material.albedo_texture = null

			push_warning(
				"Card front texture is missing."
			)
	else:
		card_material.albedo_texture = back_texture


func move_home(
	new_home_transform: Transform3D
) -> void:
	home_transform = new_home_transform
	_apply_home_transform()


func return_home() -> void:
	_apply_home_transform()


func set_keep_selected(value: bool) -> void:
	keep_selected = value
	_apply_home_transform()


func _apply_home_transform() -> void:
	global_transform = home_transform

	if (
		keep_selected
		and card_instance != null
		and card_instance.zone == CardZone.Type.HAND
	):
		global_position += \
			Vector3.UP * KEEP_RAISE_HEIGHT


func _input_event(
	_camera: Node,
	event: InputEvent,
	_event_position: Vector3,
	_normal: Vector3,
	_shape_index: int
) -> void:
	if not is_draggable:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			drag_requested.emit(
				self,
				event.position
			)

	elif event is InputEventMouseButton:
		if (
			event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed
		):
			drag_requested.emit(
				self,
				event.position
			)


func set_disabled(
	value: bool,
	_animate_change: bool = true
) -> float:
	is_disabled = value

	# DisabledLabel is intentionally not used in the current presentation.
	# disabled_label.visible = value
	disabled_card.visible = value

	# A disabled card can still be picked so game logic can decide whether
	# the interaction is allowed.
	input_ray_pickable = true

	# One-shot disabled-hit VFX is now handled by CardVFXManager3D.
	return 0.0


func set_shield_count(
	new_count: int,
	animate_change: bool = true
) -> void:
	new_count = maxi(new_count, 0)

	var previous_count: int = displayed_shield_count
	displayed_shield_count = new_count

	shield_badge.visible = new_count > 0

	if new_count <= 0:
		return

	shield_count_label.text = str(new_count)

	if animate_change and new_count != previous_count:
		_play_shield_badge_pulse()


func _play_shield_badge_pulse() -> void:
	shield_badge.scale = (
		shield_badge_base_scale
		* 1.35
	)

	var tween: Tween = create_tween()

	tween.set_trans(
		Tween.TRANS_BACK
	)

	tween.set_ease(
		Tween.EASE_OUT
	)

	tween.tween_property(
		shield_badge,
		"scale",
		shield_badge_base_scale,
		0.25
	)
