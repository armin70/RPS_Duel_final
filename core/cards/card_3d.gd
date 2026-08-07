class_name Card3D
extends Area3D


signal drag_requested(
	card_view: Card3D,
	screen_position: Vector2
)
@export_category("Killer Placement VFX")

@export var killer_placed_animation_name: StringName = &"place"


@onready var killer_paper_placed_vfx: VFXBattleSwingBB = $KillerPaperPlacedVFX

@onready var killer_rock_placed_vfx: VFXBattleSwingBB = $KillerRockPlacedVFX

@onready var killer_scissors_placed_vfx: VFXBattleSwingBB = $KillerScissorsPlacedVFX


var killer_rock_placed_player: AnimationPlayer
var killer_paper_placed_player: AnimationPlayer
var killer_scissors_placed_player: AnimationPlayer
@export var back_texture: Texture2D

@export_category("Collector VFX")
@export var rock_collector_animation_name: StringName = &"collect"
@export var paper_collector_animation_name: StringName = &"collect"
@export var scissors_collector_animation_name: StringName = &"collect"

var card_instance: CardInstance
var home_transform: Transform3D
var is_draggable: bool = false

@export_category("Card VFX")
@export var disabler_activate_animation_name: StringName = &"activate"
@export var disabled_hit_animation_name: StringName = &"hit"

@onready var disabler_activate_vfx: Node3D = \
	get_node_or_null("DisablerActivateVFX") as Node3D

@onready var rock_collector_vfx: Node3D = \
	get_node_or_null(
		"RockCollectorVFX"
	) as Node3D

@onready var paper_collector_vfx: Node3D = \
	get_node_or_null(
		"PaperCollectorVFX"
	) as Node3D

@onready var scissors_collector_vfx: Node3D = \
	get_node_or_null(
		"ScissorsCollectorVFX"
	) as Node3D

@onready var disabled_hit_vfx: Node3D = \
	get_node_or_null("DisabledHitVFX") as Node3D

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

var disabler_activate_player: AnimationPlayer
var disabled_hit_player: AnimationPlayer
var is_disabled: bool = false

var rock_collector_player: AnimationPlayer
var paper_collector_player: AnimationPlayer
var scissors_collector_player: AnimationPlayer


func _ready() -> void:
	shield_badge_base_scale = shield_badge.scale
	shield_badge.visible = false

	collision_layer = 1
	collision_mask = 0
	input_ray_pickable = true

	_create_card_material()
	_setup_card_vfx()


func _create_card_material() -> void:
	if card_material != null:
		return

	card_material = StandardMaterial3D.new()

	# رنگ تصویر تحت تأثیر نور میز تغییر نمی‌کند.
	card_material.shading_mode = \
		BaseMaterial3D.SHADING_MODE_UNSHADED

	# تصویر از هر دو سمت قابل رندر است.
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
	animate_change: bool = true
) -> float:
	var was_disabled: bool = is_disabled

	is_disabled = value
	# disabled_label.visible = value
	disabled_card.visible = value
	input_ray_pickable = true

	var became_disabled: bool = (
		value
		and not was_disabled
	)

	var hit_duration: float = 0.0

	if (
		became_disabled
		and animate_change
	):
		hit_duration = \
			play_disabled_hit_effect()

	if not value:
		if disabled_hit_player != null:
			disabled_hit_player.stop()

		if disabled_hit_vfx != null:
			disabled_hit_vfx.visible = false

	return hit_duration


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


func _setup_card_vfx() -> void:
	if disabler_activate_vfx != null:
		disabler_activate_vfx.visible = false

		disabler_activate_player = \
			_find_animation_player(
				disabler_activate_vfx
			)

		if disabler_activate_player != null:
			disabler_activate_player.animation_finished.connect(
				_on_disabler_activate_animation_finished
			)
		else:
			push_warning(
				"DisablerActivateVFX has no AnimationPlayer."
			)
	else:
		push_warning(
			"DisablerActivateVFX is missing from Card3D."
		)

	if disabled_hit_vfx != null:
		disabled_hit_vfx.visible = false

		disabled_hit_player = \
			_find_animation_player(
				disabled_hit_vfx
			)

		if disabled_hit_player != null:
			disabled_hit_player.animation_finished.connect(
				_on_disabled_hit_animation_finished
			)
		else:
			push_warning(
				"DisabledHitVFX has no AnimationPlayer."
			)
	else:
		push_warning(
			"DisabledHitVFX is missing from Card3D."
		)

	rock_collector_player = \
		_setup_single_card_vfx(
			rock_collector_vfx,
			"RockCollectorVFX"
		)

	paper_collector_player = \
		_setup_single_card_vfx(
			paper_collector_vfx,
			"PaperCollectorVFX"
		)

	scissors_collector_player = \
		_setup_single_card_vfx(
			scissors_collector_vfx,
			"ScissorsCollectorVFX"
		)
	killer_rock_placed_player = \
		_setup_single_card_vfx(
			killer_rock_placed_vfx,
			"KillerRockPlacedVFX"
		)

	killer_paper_placed_player = \
		_setup_single_card_vfx(
			killer_paper_placed_vfx,
			"KillerPaperPlacedVFX"
		)

	killer_scissors_placed_player = \
		_setup_single_card_vfx(
			killer_scissors_placed_vfx,
			"KillerScissorsPlacedVFX"
		)

func _find_animation_player(
	root: Node
) -> AnimationPlayer:
	if root == null:
		return null

	if root is AnimationPlayer:
		return root as AnimationPlayer

	for child: Node in root.get_children():
		var result: AnimationPlayer = \
			_find_animation_player(child)

		if result != null:
			return result

	return null


func _play_card_vfx(
	vfx_root: Node3D,
	animation_player: AnimationPlayer,
	animation_name: StringName
) -> float:
	if vfx_root == null:
		return 0.0

	if animation_player == null:
		return 0.0

	if not animation_player.has_animation(
		animation_name
	):
		push_warning(
			"Card VFX animation not found: %s | available: %s"
			% [
				animation_name,
				animation_player.get_animation_list()
			]
		)
		return 0.0

	var animation: Animation = \
		animation_player.get_animation(
			animation_name
		)

	if animation == null:
		return 0.0

	vfx_root.visible = true

	animation_player.stop()

	if animation_player.has_animation(&"RESET"):
		animation_player.play(&"RESET")
		animation_player.advance(0.0)

	animation_player.play(
		animation_name
	)

	animation_player.advance(0.0)

	var animation_speed: float = maxf(
		absf(animation_player.speed_scale),
		0.001
	)

	return animation.length / animation_speed


func play_on_placed_effect() -> float:
	if card_instance == null:
		return 0.0

	if card_instance.definition == null:
		return 0.0

	var disabler_behavior := (
		card_instance.definition.behavior
		as DisableGestureBehavior
	)

	if disabler_behavior == null:
		return 0.0

	return _play_card_vfx(
		disabler_activate_vfx,
		disabler_activate_player,
		disabler_activate_animation_name
	)


func play_disabled_hit_effect() -> float:
	if card_instance != null:
		if card_instance.definition != null:
			print(
				"CARD VFX | Card disabled | card=",
				card_instance.definition.display_name
			)

	return _play_card_vfx(
		disabled_hit_vfx,
		disabled_hit_player,
		disabled_hit_animation_name
	)


# این تابع باید داخل Card3D باشد؛ MatchController آن را روی card_view صدا می‌زند.
func play_collector_effect() -> float:
	if card_instance == null:
		return 0.0

	if card_instance.definition == null:
		return 0.0

	var collector_behavior := (
		card_instance.definition.behavior
		as CollectorBehavior
	)

	if collector_behavior == null:
		return 0.0

	match collector_behavior.collected_gesture:
		CardGesture.Type.ROCK:
			return _play_card_vfx(
				rock_collector_vfx,
				rock_collector_player,
				rock_collector_animation_name
			)

		CardGesture.Type.PAPER:
			return _play_card_vfx(
				paper_collector_vfx,
				paper_collector_player,
				paper_collector_animation_name
			)

		CardGesture.Type.SCISSORS:
			return _play_card_vfx(
				scissors_collector_vfx,
				scissors_collector_player,
				scissors_collector_animation_name
			)

	return 0.0


func _on_disabler_activate_animation_finished(
	finished_name: StringName
) -> void:
	if (
		finished_name
		!= disabler_activate_animation_name
	):
		return

	if disabler_activate_vfx != null:
		disabler_activate_vfx.visible = false


func _on_disabled_hit_animation_finished(
	finished_name: StringName
) -> void:
	if (
		finished_name
		!= disabled_hit_animation_name
	):
		return

	if disabled_hit_vfx != null:
		disabled_hit_vfx.visible = false


func _setup_single_card_vfx(
	vfx_root: Node3D,
	vfx_name: String
) -> AnimationPlayer:
	if vfx_root == null:
		push_warning(
			vfx_name + " is missing from Card3D."
		)
		return null

	vfx_root.visible = false

	var player: AnimationPlayer = \
		_find_animation_player(
			vfx_root
		)

	if player == null:
		push_warning(
			vfx_name + " has no AnimationPlayer."
		)

	return player

func play_killer_placed_effect() -> void:
	if card_instance == null:
		return

	if card_instance.definition == null:
		return

	var behavior: CardBehavior = card_instance.definition.behavior

	# فقط کارت Killer ادامه بدهد
	if behavior == null:
		return

	if not behavior.destroys_defeated_player_card():
		return

	match card_instance.definition.gesture:
		CardGesture.Type.ROCK:
			$KillerRockPlacedVFX.visible = true
			$KillerRockPlacedVFX/AnimationPlayer.play("place")

		CardGesture.Type.PAPER:
			$KillerPaperPlacedVFX.visible = true
			$KillerPaperPlacedVFX/AnimationPlayer.play("place")

		CardGesture.Type.SCISSORS:
			$KillerScissorsPlacedVFX.visible = true
			$KillerScissorsPlacedVFX/AnimationPlayer.play("place")

func play_bomb_placed_effect() -> void:
	if card_instance == null:
		return

	if card_instance.definition == null:
		return

	var behavior: CardBehavior = \
		card_instance.definition.behavior

	# فقط کارت‌های Bomb / Demolisher
	if not (behavior is DiscardLaneDrawBehavior):
		return

	$BombPlacedVFX.visible = true
	$BombPlacedVFX/AnimationPlayer.play("place")
