class_name Card3D
extends Area3D


signal drag_requested(
	card_view: Card3D,
	screen_position: Vector2
)

signal inspect_requested(
	card_view: Card3D
)


@export var back_texture: Texture2D

@export_category("Card Inspect")
@export_range(0.20, 1.50, 0.05)
var inspect_hold_time: float = 0.45

@export_range(4.0, 80.0, 1.0)
var inspect_move_cancel_distance: float = 18.0


var card_instance: CardInstance
var home_transform: Transform3D
var is_draggable: bool = false
var is_disabled: bool = false
var is_face_up: bool = true


@onready var card_art: MeshInstance3D = $CardArt
@onready var card_name: Label3D = $CardName
@onready var disabled_label: Label3D = $DisabledLabel
@onready var disabled_card: MeshInstance3D = $Disabled_card

@onready var shield_badge: Node3D = %ShieldBadge
@onready var shield_count_label: Label3D = %ShieldCount


const KEEP_RAISE_HEIGHT: float = 0.18


var keep_selected: bool = false
var displayed_shield_count: int = 0
var shield_badge_base_scale: Vector3 = Vector3.ONE
var card_material: StandardMaterial3D

var _inspect_press_active: bool = false
var _inspect_press_position: Vector2 = Vector2.ZERO
var _inspect_press_serial: int = 0


func _ready() -> void:
	shield_badge_base_scale = shield_badge.scale
	shield_badge.visible = false

	collision_layer = 1
	collision_mask = 0
	input_ray_pickable = true

	_create_card_material()
	_refresh_gesture_override_label()


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
	_refresh_gesture_override_label()


func set_face_up(value: bool) -> void:
	is_face_up = value

	if not value:
		_cancel_inspect_hold()

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

	_refresh_gesture_override_label()


func refresh_gesture_override_label() -> void:
	_refresh_gesture_override_label()


func _refresh_gesture_override_label() -> void:
	if card_name == null:
		return

	if (
		card_instance == null
		or not is_face_up
		or not card_instance.has_gesture_override()
	):
		card_name.visible = false
		return

	var gesture: CardGesture.Type = card_instance.get_gesture()
	if gesture not in [
		CardGesture.Type.ROCK,
		CardGesture.Type.PAPER,
		CardGesture.Type.SCISSORS
	]:
		card_name.visible = false
		return

	card_name.text = CardGesture.Type.keys()[gesture]
	card_name.font_size = 11
	card_name.outline_size = 4
	card_name.modulate = Color.WHITE
	card_name.visible = true


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
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_inspect_hold(event.position)

			if is_draggable:
				drag_requested.emit(
					self,
					event.position
				)
		else:
			_cancel_inspect_hold()

	elif event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return

		if event.pressed:
			_begin_inspect_hold(event.position)

			if is_draggable:
				drag_requested.emit(
					self,
					event.position
				)
		else:
			_cancel_inspect_hold()


func _input(event: InputEvent) -> void:
	if not _inspect_press_active:
		return

	if event is InputEventScreenDrag:
		_cancel_inspect_if_moved(event.position)

	elif event is InputEventMouseMotion:
		_cancel_inspect_if_moved(event.position)

	elif event is InputEventScreenTouch:
		if not event.pressed:
			_cancel_inspect_hold()

	elif event is InputEventMouseButton:
		if (
			event.button_index == MOUSE_BUTTON_LEFT
			and not event.pressed
		):
			_cancel_inspect_hold()


func _begin_inspect_hold(
	screen_position: Vector2
) -> void:
	# Never reveal information for a face-down card.
	if not is_face_up:
		return

	if card_instance == null:
		return

	if card_instance.definition == null:
		return

	_inspect_press_active = true
	_inspect_press_position = screen_position
	_inspect_press_serial += 1

	var current_serial: int = _inspect_press_serial
	_wait_for_inspect_hold(current_serial)


func _wait_for_inspect_hold(
	serial: int
) -> void:
	await get_tree().create_timer(
		inspect_hold_time
	).timeout

	if not _inspect_press_active:
		return

	if serial != _inspect_press_serial:
		return

	if not is_face_up:
		_cancel_inspect_hold()
		return

	_inspect_press_active = false
	_inspect_press_serial += 1

	inspect_requested.emit(self)


func _cancel_inspect_if_moved(
	screen_position: Vector2
) -> void:
	if (
		screen_position.distance_to(
			_inspect_press_position
		)
		> inspect_move_cancel_distance
	):
		_cancel_inspect_hold()


func _cancel_inspect_hold() -> void:
	if not _inspect_press_active:
		return

	_inspect_press_active = false
	_inspect_press_serial += 1


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


# Rush unused-mana penalty presentation. The card rises out of the current
# hand and fades before MatchController rebuilds the next-turn hand.
func play_rush_penalty_remove(
	raise_height: float = 0.55,
	duration: float = 0.55
) -> float:
	is_draggable = false
	input_ray_pickable = false
	_cancel_inspect_hold()

	_create_card_material()

	if card_material == null:
		return 0.0

	# Hand cards do not need status overlays while they disappear.
	disabled_card.visible = false
	shield_badge.visible = false

	card_material.transparency = \
		BaseMaterial3D.TRANSPARENCY_ALPHA

	var start_color: Color = card_material.albedo_color
	start_color.a = 1.0
	card_material.albedo_color = start_color

	var end_color: Color = start_color
	end_color.a = 0.0

	var target_position: Vector3 = (
		global_position
		+ Vector3.UP * raise_height
	)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(
		self,
		"global_position",
		target_position,
		duration
	)
	tween.tween_property(
		card_material,
		"albedo_color",
		end_color,
		duration
	)
	tween.tween_property(
		self,
		"scale",
		scale * 0.86,
		duration
	)

	return duration
