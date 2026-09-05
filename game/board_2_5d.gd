class_name Board2_5D
extends Node3D


@export_category("Ground Map")
@export var ground_sprite: Sprite3D
@export var camera_3d: Camera3D
@export_range(4.0, 12.0, 0.05)
var world_width: float = 9.5
@export var texture_pixel_size: Vector2 = Vector2(2048.0, 921.0)
@export_range(-0.25, 0.0, 0.005)
var ground_y: float = -0.13
@export var ground_center_z: float = -0.35

@export_category("Camera")
@export var camera_position: Vector3 = Vector3(0.0, 3.066, 2.596)
@export var camera_rotation_degrees: Vector3 = Vector3(-53.4, 0.0, 0.0)
@export_range(30.0, 75.0, 0.5)
var camera_fov: float = 45.0


func _ready() -> void:
	_configure_ground()
	_configure_camera()

	var viewport := get_viewport()
	if viewport != null:
		var resize_callable := Callable(self, "_configure_camera")
		if not viewport.size_changed.is_connected(resize_callable):
			viewport.size_changed.connect(resize_callable)

	# main_game.scn can finish its own camera setup after this node.
	# Apply the same known-good perspective again after startup settles.
	call_deferred("_stabilize_initial_camera")


func _stabilize_initial_camera() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_configure_ground()
	_configure_camera()

	await get_tree().create_timer(0.12).timeout
	_configure_camera()

	await get_tree().create_timer(0.35).timeout
	_configure_camera()


func _configure_ground() -> void:
	if ground_sprite == null:
		return

	if texture_pixel_size.x > 0.0:
		ground_sprite.pixel_size = world_width / texture_pixel_size.x

	ground_sprite.position = Vector3(
		0.0,
		ground_y,
		ground_center_z
	)
	ground_sprite.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	ground_sprite.scale = Vector3.ONE
	ground_sprite.shaded = false
	ground_sprite.double_sided = true
	ground_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _configure_camera() -> void:
	if camera_3d == null:
		return

	camera_3d.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera_3d.position = camera_position
	camera_3d.rotation_degrees = camera_rotation_degrees
	camera_3d.fov = camera_fov
	camera_3d.near = 0.05
	camera_3d.far = 100.0
	camera_3d.current = true
