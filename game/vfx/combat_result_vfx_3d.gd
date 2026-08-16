class_name CombatResultVFX3D
extends Node3D


signal finished


var _sprite: AnimatedSprite3D


func play_and_wait(
	frames: SpriteFrames,
	animation_name: StringName,
	pixel_size: float,
	fallback_duration: float
) -> void:
	if frames == null:
		finished.emit()
		queue_free()
		return

	var resolved_animation: StringName = animation_name

	if not frames.has_animation(resolved_animation):
		if frames.has_animation(&"default"):
			resolved_animation = &"default"
		else:
			var animation_names: PackedStringArray = \
				frames.get_animation_names()

			if animation_names.is_empty():
				finished.emit()
				queue_free()
				return

			resolved_animation = StringName(animation_names[0])

	if frames.get_frame_count(resolved_animation) <= 0:
		finished.emit()
		queue_free()
		return

	_sprite = AnimatedSprite3D.new()
	add_child(_sprite)

	_sprite.sprite_frames = frames
	_sprite.animation = resolved_animation
	_sprite.pixel_size = pixel_size
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.no_depth_test = true
	_sprite.shaded = false
	_sprite.render_priority = 10

	_sprite.play(resolved_animation)

	# Version-safe timing: do not depend on SpriteFrames loop APIs.
	# We calculate one complete playback directly from frame durations + FPS.
	var playback_duration: float = _get_animation_duration(
		frames,
		resolved_animation
	)

	if playback_duration <= 0.0:
		playback_duration = fallback_duration

	if playback_duration > 0.0:
		await get_tree().create_timer(playback_duration).timeout

	finished.emit()
	queue_free()


func _get_animation_duration(
	frames: SpriteFrames,
	animation_name: StringName
) -> float:
	if frames == null:
		return 0.0

	if not frames.has_animation(animation_name):
		return 0.0

	var fps: float = frames.get_animation_speed(animation_name)

	if fps <= 0.0:
		return 0.0

	var frame_count: int = frames.get_frame_count(animation_name)
	var total_relative_duration: float = 0.0

	for frame_index: int in range(frame_count):
		total_relative_duration += frames.get_frame_duration(
			animation_name,
			frame_index
		)

	return total_relative_duration / fps
