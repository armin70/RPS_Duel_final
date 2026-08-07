class_name IntroCameraController
extends Camera3D


signal camera_arrived_at_game


@export var menu_camera_marker: Marker3D
@export var game_camera_marker: Marker3D

@export_range(0.1, 5.0, 0.1)
var move_duration: float = 1.2

var is_moving: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	current = true

	if menu_camera_marker == null:
		push_error("Menu Camera Marker is missing.")
		return

	if game_camera_marker == null:
		push_error("Game Camera Marker is missing.")
		return

	global_transform = menu_camera_marker.global_transform


func move_to_game_position() -> void:
	if is_moving:
		return

	if game_camera_marker == null:
		return

	is_moving = true

	var tween: Tween = create_tween()

	tween.set_pause_mode(
		Tween.TWEEN_PAUSE_PROCESS
	)

	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(
		self,
		"global_transform",
		game_camera_marker.global_transform,
		move_duration
	)

	await tween.finished

	global_transform = \
		game_camera_marker.global_transform

	is_moving = false
	camera_arrived_at_game.emit()

	print("CAMERA ARRIVED AT GAME POSITION")
