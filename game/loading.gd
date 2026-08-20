class_name CloudMenuController
extends Node3D


signal clouds_intro_finished
signal clouds_outro_finished


@export_category("Animation Sections")

@export var intro_end_time: float = 2.0
@export var menu_loop_start: float = 2.0
@export var menu_loop_end: float = 8.0
@export var outro_end_time: float = 9.0

@export_range(0.1, 3.0, 0.1)
var animation_speed: float = 1.0

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


enum Phase {
	STOPPED,
	INTRO,
	MENU_LOOP,
	OUTRO,
	FINISHED
}


var phase: Phase = Phase.STOPPED

var cloud_players: Array[AnimationPlayer] = []
var animation_names: Dictionary = {}

var master_player: AnimationPlayer = null


func _ready() -> void:
	# ابرها حتی وقتی منو بازی را Pause کرده حرکت می‌کنند.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_mobile_cloud_material_fix()

	_find_cloud_animation_players()

	if cloud_players.is_empty():
		push_error("No cloud AnimationPlayers were found.")
		return

	master_player = cloud_players[0]

	play_menu_intro()


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


func _process(_delta: float) -> void:
	if not is_instance_valid(master_player):
		return

	var current_time: float = \
		master_player.current_animation_position

	match phase:
		Phase.INTRO:
			if current_time >= intro_end_time:
				_seek_all_clouds(menu_loop_start)

				phase = Phase.MENU_LOOP
				clouds_intro_finished.emit()

				print(
					"CLOUDS MENU LOOP STARTED | ",
					menu_loop_start,
					" to ",
					menu_loop_end
				)

		Phase.MENU_LOOP:
			if current_time >= menu_loop_end:
				_seek_all_clouds(menu_loop_start)

		Phase.OUTRO:
			if current_time >= outro_end_time:
				_seek_all_clouds(outro_end_time)
				_pause_all_clouds()

				phase = Phase.FINISHED
				clouds_outro_finished.emit()

				print("CLOUD OUTRO FINISHED")

		_:
			pass


func _find_cloud_animation_players() -> void:
	cloud_players.clear()
	animation_names.clear()

	var nodes: Array[Node] = find_children(
		"*",
		"AnimationPlayer",
		true,
		false
	)

	for node: Node in nodes:
		var player := node as AnimationPlayer

		if player == null:
			continue

		var animation_name: StringName = \
			_get_main_animation_name(player)

		if animation_name == &"":
			push_warning(
				"No usable animation found in: "
				+ str(player.get_path())
			)
			continue

		var animation: Animation = \
			player.get_animation(animation_name)

		if animation == null:
			continue

		if animation.length < outro_end_time:
			push_warning(
				"Cloud animation is shorter than "
				+ str(outro_end_time)
				+ " seconds: "
				+ str(player.get_path())
			)

		# Loop را خودمان بین 2 و 8 کنترل می‌کنیم.
		animation.loop_mode = Animation.LOOP_NONE

		player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.speed_scale = animation_speed

		cloud_players.append(player)
		animation_names[player] = animation_name

		print(
			"CLOUD FOUND | ",
			player.get_path(),
			" | animation=",
			animation_name
		)


func _get_main_animation_name(
	player: AnimationPlayer
) -> StringName:
	if (
		player.autoplay != &""
		and player.autoplay != &"RESET"
		and player.has_animation(player.autoplay)
	):
		return player.autoplay

	for animation_name: StringName in \
			player.get_animation_list():

		if animation_name == &"RESET":
			continue

		return animation_name

	return &""


func play_menu_intro() -> void:
	if cloud_players.is_empty():
		return

	phase = Phase.INTRO

	for player: AnimationPlayer in cloud_players:
		var animation_name: StringName = \
			animation_names.get(player, &"")

		if animation_name == &"":
			continue

		player.speed_scale = animation_speed
		player.play(animation_name)
		player.seek(0.0, true)

	print("CLOUD INTRO STARTED | 0 to 2")


func play_cloud_outro() -> void:
	if phase == Phase.OUTRO:
		return

	if phase == Phase.FINISHED:
		return

	# Loop منو قطع می‌شود و همه مستقیماً از ثانیه 8 ادامه می‌دهند.
	phase = Phase.OUTRO

	for player: AnimationPlayer in cloud_players:
		if not is_instance_valid(player):
			continue

		var animation_name: StringName = \
			animation_names.get(player, &"")

		if animation_name == &"":
			continue

		player.speed_scale = animation_speed
		player.play(animation_name)
		player.seek(menu_loop_end, true)

	print(
		"CLOUD OUTRO STARTED | ",
		menu_loop_end,
		" to ",
		outro_end_time
	)


func _seek_all_clouds(time_position: float) -> void:
	for player: AnimationPlayer in cloud_players:
		if not is_instance_valid(player):
			continue

		player.seek(time_position, true)


func _pause_all_clouds() -> void:
	for player: AnimationPlayer in cloud_players:
		if not is_instance_valid(player):
			continue

		player.pause()
