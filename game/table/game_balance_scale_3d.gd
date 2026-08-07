class_name GameBalanceScale3D
extends Node3D


enum RotationAxis {
	X,
	Y,
	Z
}


@export_category("Scale Parts")
@export var beam_pivot: Node3D


@export_category("Balance Settings")
@export var rotation_axis: RotationAxis = RotationAxis.Z

@export_range(1.0, 55.0, 0.5)
var max_tilt_degrees: float = 45.0

@export_range(0.1, 20.0, 0.1)
var smoothing_speed: float = 5.0

# روشن یعنی Player 1 در سمت چپ ترازو است.
@export var player_one_is_left: bool = true


var base_beam_rotation: Vector3 = Vector3.ZERO
var target_balance_ratio: float = 0.0


func _ready() -> void:
	if beam_pivot == null:
		push_error("Balance Scale: Beam Pivot is not assigned.")
		set_process(false)
		return

	base_beam_rotation = beam_pivot.rotation


func _process(delta: float) -> void:
	var direction: float = 1.0 if player_one_is_left else -1.0

	var tilt_radians: float = deg_to_rad(
		target_balance_ratio
		* max_tilt_degrees
		* direction
	)

	var target_rotation: Vector3 = base_beam_rotation

	match rotation_axis:
		RotationAxis.X:
			target_rotation.x += tilt_radians
		RotationAxis.Y:
			target_rotation.y += tilt_radians
		RotationAxis.Z:
			target_rotation.z += tilt_radians

	var smoothing_weight: float = 1.0 - exp(
		-smoothing_speed * delta
	)

	beam_pivot.rotation.x = lerp_angle(
		beam_pivot.rotation.x,
		target_rotation.x,
		smoothing_weight
	)

	beam_pivot.rotation.y = lerp_angle(
		beam_pivot.rotation.y,
		target_rotation.y,
		smoothing_weight
	)

	beam_pivot.rotation.z = lerp_angle(
		beam_pivot.rotation.z,
		target_rotation.z,
		smoothing_weight
	)


func set_balance(
	player_one_score: int,
	player_two_score: int,
	winning_difference: int
) -> void:
	if winning_difference <= 0:
		target_balance_ratio = 0.0
		return

	var score_difference: int = (
		player_one_score
		- player_two_score
	)

	target_balance_ratio = clampf(
		float(score_difference)
		/ float(winning_difference),
		-1.0,
		1.0
	)


func reset_balance() -> void:
	target_balance_ratio = 0.0
