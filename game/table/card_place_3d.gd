class_name CardPlace3D
extends Area3D


enum Kind {
	PLAYER_BOARD,
	DEALER,
	HAND
}


enum HighlightKind {
	NORMAL,
	VALID_COVER,
	INVALID_COVER
}


@export var kind: Kind = Kind.PLAYER_BOARD
@export_range(0, 2, 1) var owner_id: int = 0
@export var logical_id: int = -1


@onready var card_anchor: Marker3D = $CardAnchor
@onready var slot_mesh: MeshInstance3D = $SlotMesh

var slot_mesh_home_transform: Transform3D = Transform3D.IDENTITY
var drop_highlight_material: StandardMaterial3D

const NORMAL_HIGHLIGHT_COLOR := Color(0.44, 0.96, 1.0, 0.42)
const VALID_COVER_COLOR := Color(0.26, 1.0, 0.38, 0.58)
const INVALID_COVER_COLOR := Color(1.0, 0.16, 0.10, 0.64)


func _ready() -> void:
	input_ray_pickable = false

	if slot_mesh != null:
		slot_mesh_home_transform = slot_mesh.transform
		slot_mesh.visible = false

		var source_material := \
			slot_mesh.get_surface_override_material(0) as StandardMaterial3D

		if source_material != null:
			drop_highlight_material = \
				source_material.duplicate() as StandardMaterial3D
		else:
			drop_highlight_material = StandardMaterial3D.new()

		if drop_highlight_material != null:
			drop_highlight_material.shading_mode = \
				BaseMaterial3D.SHADING_MODE_UNSHADED
			drop_highlight_material.transparency = \
				BaseMaterial3D.TRANSPARENCY_ALPHA
			drop_highlight_material.albedo_color = \
				NORMAL_HIGHLIGHT_COLOR
			slot_mesh.set_surface_override_material(
				0,
				drop_highlight_material
			)


func show_drop_highlight(
	world_transform: Transform3D,
	highlight_kind: int = HighlightKind.NORMAL
) -> void:
	if slot_mesh == null:
		return

	var highlight_transform: Transform3D = world_transform
	highlight_transform.origin += Vector3.UP * 0.018

	slot_mesh.global_transform = highlight_transform

	if drop_highlight_material != null:
		match highlight_kind:
			HighlightKind.VALID_COVER:
				drop_highlight_material.albedo_color = \
					VALID_COVER_COLOR

			HighlightKind.INVALID_COVER:
				drop_highlight_material.albedo_color = \
					INVALID_COVER_COLOR

			_:
				drop_highlight_material.albedo_color = \
					NORMAL_HIGHLIGHT_COLOR

	# Cover feedback extends a little outside the card, so it stays visible
	# even when the destination already has card art on top of the slot.
	if highlight_kind == HighlightKind.NORMAL:
		slot_mesh.scale = Vector3.ONE
	else:
		slot_mesh.scale = Vector3(1.12, 1.0, 1.12)

	slot_mesh.visible = true


func hide_drop_highlight() -> void:
	if slot_mesh == null:
		return

	slot_mesh.visible = false
	slot_mesh.transform = slot_mesh_home_transform
	slot_mesh.scale = Vector3.ONE

	if drop_highlight_material != null:
		drop_highlight_material.albedo_color = NORMAL_HIGHLIGHT_COLOR
