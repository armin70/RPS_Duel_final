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
@onready var slot_mesh: MeshInstance3D = $SlotMesh

enum HighlightKind {
	NORMAL,
	VALID_COVER,
	INVALID_COVER
}


var slot_mesh_home_transform: Transform3D = Transform3D.IDENTITY
var normal_highlight_material: StandardMaterial3D
var valid_cover_material: StandardMaterial3D
var invalid_cover_material: StandardMaterial3D
var invalid_flash_tween: Tween


func _ready() -> void:
	input_ray_pickable = false

	if slot_mesh != null:
		slot_mesh_home_transform = slot_mesh.transform
		slot_mesh.visible = false

		var source_material := slot_mesh.get_active_material(0) as StandardMaterial3D

		if source_material != null:
			normal_highlight_material = source_material.duplicate() as StandardMaterial3D
		else:
			normal_highlight_material = StandardMaterial3D.new()
			normal_highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

		valid_cover_material = normal_highlight_material.duplicate() as StandardMaterial3D
		invalid_cover_material = normal_highlight_material.duplicate() as StandardMaterial3D

		normal_highlight_material.albedo_color = Color(
			0.64, 1.0, 1.0, 0.92
		)
		valid_cover_material.albedo_color = Color(
			0.30, 1.0, 0.38, 0.96
		)
		invalid_cover_material.albedo_color = Color(
			1.0, 0.16, 0.10, 0.97
		)

		# MeshInstance3D has no CanvasItem.modulate property. Alpha fading
		# must be handled by the 3D material itself.
		normal_highlight_material.transparency = \
			BaseMaterial3D.TRANSPARENCY_ALPHA
		valid_cover_material.transparency = \
			BaseMaterial3D.TRANSPARENCY_ALPHA
		invalid_cover_material.transparency = \
			BaseMaterial3D.TRANSPARENCY_ALPHA


func _set_highlight_material(
	highlight_kind: HighlightKind
) -> void:
	if slot_mesh == null:
		return

	var material: StandardMaterial3D = normal_highlight_material
	var highlight_alpha: float = 0.92

	match highlight_kind:
		HighlightKind.VALID_COVER:
			material = valid_cover_material
			highlight_alpha = 0.96

		HighlightKind.INVALID_COVER:
			material = invalid_cover_material
			highlight_alpha = 0.97

	if material == null:
		return

	# A previous invalid flash may have faded this material to alpha zero.
	# Restore its intended opacity whenever the highlight is shown again.
	var highlight_color: Color = material.albedo_color
	highlight_color.a = highlight_alpha
	material.albedo_color = highlight_color

	slot_mesh.set_surface_override_material(
		0,
		material
	)


func show_drop_highlight(
	world_transform: Transform3D,
	highlight_kind: HighlightKind = HighlightKind.NORMAL
) -> void:
	if slot_mesh == null:
		return

	var highlight_transform: Transform3D = world_transform
	highlight_transform.origin += Vector3.UP * 0.018

	_set_highlight_material(highlight_kind)
	slot_mesh.global_transform = highlight_transform
	slot_mesh.visible = true


func flash_invalid_drop(
	world_transform: Transform3D,
	duration: float = 0.22
) -> void:
	if slot_mesh == null:
		return

	if invalid_flash_tween != null:
		if invalid_flash_tween.is_valid():
			invalid_flash_tween.kill()

	show_drop_highlight(
		world_transform,
		HighlightKind.INVALID_COVER
	)

	slot_mesh.scale = Vector3.ONE
	invalid_flash_tween = create_tween()
	invalid_flash_tween.tween_property(
		slot_mesh,
		"scale",
		Vector3(1.10, 1.0, 1.10),
		0.06
	).set_trans(
		Tween.TRANS_BACK
	).set_ease(
		Tween.EASE_OUT
	)

	invalid_flash_tween.tween_property(
		slot_mesh,
		"scale",
		Vector3.ONE,
		0.07
	)

	invalid_flash_tween.tween_interval(
		maxf(0.0, duration - 0.17)
	)

	var faded_invalid_color: Color = \
		invalid_cover_material.albedo_color
	faded_invalid_color.a = 0.0

	invalid_flash_tween.tween_property(
		invalid_cover_material,
		"albedo_color",
		faded_invalid_color,
		0.04
	)

	invalid_flash_tween.tween_callback(
		hide_drop_highlight
	)


func hide_drop_highlight() -> void:
	if slot_mesh == null:
		return

	slot_mesh.visible = false
	slot_mesh.scale = Vector3.ONE
	slot_mesh.transform = slot_mesh_home_transform
