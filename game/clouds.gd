extends Node3D


@export_category("Mobile Cloud Look")
@export_range(0.50, 1.0, 0.01)
var mobile_cloud_albedo_multiplier: float = 0.88
@export_range(0.0, 1.0, 0.01)
var mobile_cloud_max_metallic: float = 0.0
@export_range(0.0, 1.0, 0.01)
var mobile_cloud_max_specular: float = 0.18
@export_range(0.0, 1.0, 0.01)
var mobile_cloud_min_roughness: float = 0.90
@export_range(0.0, 2.0, 0.05)
var mobile_cloud_max_emission: float = 0.35


func _ready() -> void:
	_apply_mobile_cloud_material_fix()
	play_all_cloud_animations()


func _apply_mobile_cloud_material_fix() -> void:
	if not OS.has_feature("android") and not OS.has_feature("ios"):
		return

	var mesh_nodes: Array[Node] = find_children(
		"*",
		"MeshInstance3D",
		true,
		false
	)

	for node: Node in mesh_nodes:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue

		for surface_index: int in range(
			mesh_instance.mesh.get_surface_count()
		):
			var source_material: Material = \
				mesh_instance.get_surface_override_material(surface_index)
			if source_material == null:
				source_material = \
					mesh_instance.mesh.surface_get_material(surface_index)

			var standard_material := \
				source_material as StandardMaterial3D
			if standard_material == null:
				continue

			var adjusted_material := \
				standard_material.duplicate(true) as StandardMaterial3D
			if adjusted_material == null:
				continue

			var albedo: Color = adjusted_material.albedo_color
			adjusted_material.albedo_color = Color(
				albedo.r * mobile_cloud_albedo_multiplier,
				albedo.g * mobile_cloud_albedo_multiplier,
				albedo.b * mobile_cloud_albedo_multiplier,
				albedo.a
			)
			adjusted_material.metallic = minf(
				adjusted_material.metallic,
				mobile_cloud_max_metallic
			)
			adjusted_material.metallic_specular = minf(
				adjusted_material.metallic_specular,
				mobile_cloud_max_specular
			)
			adjusted_material.roughness = maxf(
				adjusted_material.roughness,
				mobile_cloud_min_roughness
			)
			if adjusted_material.emission_enabled:
				adjusted_material.emission_energy_multiplier = minf(
					adjusted_material.emission_energy_multiplier,
					mobile_cloud_max_emission
				)

			mesh_instance.set_surface_override_material(
				surface_index,
				adjusted_material
			)


func play_all_cloud_animations() -> void:
	var players: Array[Node] = find_children(
		"*",
		"AnimationPlayer",
		true,
		false
	)

	for node: Node in players:
		var player := node as AnimationPlayer

		if player == null:
			continue

		var animation_name: StringName = \
			_get_main_animation_name(player)

		if animation_name == &"":
			push_warning(
				"No playable animation found in: "
				+ str(player.get_path())
			)
			continue

		player.play(animation_name)
		player.seek(0.0, true)

		print(
			"PLAYING CLOUD ANIMATION | ",
			player.get_path(),
			" | ",
			animation_name
		)


func _get_main_animation_name(
	player: AnimationPlayer
) -> StringName:
	# اگر داخل Blender/Godot انیمیشن Autoplay داشته باشد،
	# اول همان انتخاب می‌شود.
	if (
		player.autoplay != &""
		and player.has_animation(player.autoplay)
	):
		return player.autoplay

	# در غیر این صورت اولین انیمیشنی که RESET نیست اجرا می‌شود.
	for animation_name: StringName in \
			player.get_animation_list():

		if animation_name == &"RESET":
			continue

		return animation_name

	return &""
