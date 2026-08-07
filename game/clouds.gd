extends Node3D


func _ready() -> void:
	play_all_cloud_animations()


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
