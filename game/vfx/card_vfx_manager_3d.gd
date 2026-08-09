class_name CardVFXManager3D
extends Node3D


@export_category("Runtime")
@export var runtime_root: Node3D

@export_category("Anchors")
@export var dealer_anchor: Node3D
@export var board_anchor: Node3D

@export_category("Debug")
@export var debug_logging: bool = false


func play_vfx(
	definition: CardVFXDefinition,
	source_card: Card3D = null,
	target_card: Card3D = null
) -> float:
	if definition == null:
		return 0.0

	if definition.scene == null:
		push_warning("Card VFX definition has no scene.")
		return 0.0

	var parent_node: Node3D = _resolve_runtime_parent(
		source_card,
		target_card
	)

	if parent_node == null:
		push_error(
			"VFX could not find a Node3D inside the active SceneTree."
		)
		return 0.0

	var holder := Node3D.new()
	holder.name = "RuntimeCardVFX"
	holder.process_mode = Node.PROCESS_MODE_ALWAYS
	parent_node.add_child(holder)

	# Keep the effect in world space. This also lets the source card be
	# moved/freed while a one-shot VFX is still finishing.
	holder.top_level = true
	holder.global_transform = (
		_get_spawn_transform(
			definition,
			source_card,
			target_card
		)
		* _get_definition_offset_transform(definition)
	)

	var instance := definition.scene.instantiate() as Node3D

	if instance == null:
		holder.queue_free()
		push_error(
			"Card VFX scene root must inherit Node3D: "
			+ str(definition.scene.resource_path)
		)
		return 0.0

	instance.process_mode = Node.PROCESS_MODE_ALWAYS
	holder.add_child(instance)
	instance.visible = true

	# Detect the duration immediately so gameplay can keep using the
	# existing synchronous float-return API. Actual playback starts on the
	# next frame, after the newly-instanced VFX and all descendants have
	# fully entered the SceneTree.
	var detected_duration: float = _detect_instance_duration(
		instance,
		definition
	)

	var effect_duration: float = detected_duration

	if definition.duration_override > 0.0:
		effect_duration = definition.duration_override

	effect_duration = maxf(
		effect_duration + definition.completion_padding,
		0.0
	)

	_start_instance_next_frame(
		instance,
		definition
	)

	_schedule_cleanup(
		holder,
		effect_duration
		+ definition.cleanup_delay
		+ 0.05
	)

	if debug_logging:
		print(
			"VFX SPAWN | scene=",
			definition.scene.resource_path,
			" | parent=",
			parent_node.get_path(),
			" | duration=",
			effect_duration,
			" | pos=",
			holder.global_position
		)

	return effect_duration


func get_spawn_transform(
	definition: CardVFXDefinition,
	source_card: Card3D = null,
	target_card: Card3D = null
) -> Transform3D:
	if definition == null:
		return global_transform

	return (
		_get_spawn_transform(
			definition,
			source_card,
			target_card
		)
		* _get_definition_offset_transform(definition)
	)


func _resolve_runtime_parent(
	source_card: Card3D,
	target_card: Card3D
) -> Node3D:
	if (
		is_instance_valid(runtime_root)
		and runtime_root.is_inside_tree()
	):
		return runtime_root

	# Prefer a node we know is currently rendering in this match.
	if is_instance_valid(source_card):
		var source_scene := source_card.get_tree()
		if source_scene != null:
			var current_scene := source_scene.current_scene as Node3D
			if current_scene != null:
				return current_scene

	if is_instance_valid(target_card):
		var target_scene := target_card.get_tree()
		if target_scene != null:
			var current_scene := target_scene.current_scene as Node3D
			if current_scene != null:
				return current_scene

	if is_inside_tree():
		var tree := get_tree()
		if tree != null:
			var current_scene := tree.current_scene as Node3D
			if current_scene != null:
				return current_scene

	return null


func _get_spawn_transform(
	definition: CardVFXDefinition,
	source_card: Card3D,
	target_card: Card3D
) -> Transform3D:
	match definition.spawn_target:
		CardVFXDefinition.SpawnTarget.SOURCE_CARD:
			if is_instance_valid(source_card):
				return source_card.global_transform

		CardVFXDefinition.SpawnTarget.TARGET_CARD:
			if is_instance_valid(target_card):
				return target_card.global_transform

		CardVFXDefinition.SpawnTarget.DEALER_ANCHOR:
			if is_instance_valid(dealer_anchor):
				return dealer_anchor.global_transform

		CardVFXDefinition.SpawnTarget.BOARD_ANCHOR:
			if is_instance_valid(board_anchor):
				return board_anchor.global_transform

	push_warning(
		"Could not resolve VFX spawn target. Using manager transform."
	)

	return global_transform


func _get_definition_offset_transform(
	definition: CardVFXDefinition
) -> Transform3D:
	var rotation_radians := Vector3(
		deg_to_rad(definition.local_rotation_degrees.x),
		deg_to_rad(definition.local_rotation_degrees.y),
		deg_to_rad(definition.local_rotation_degrees.z)
	)

	var basis := Basis.from_euler(rotation_radians)
	basis = basis.scaled(
		Vector3.ONE * definition.scale_multiplier
	)

	return Transform3D(
		basis,
		definition.local_offset
	)


func _collect_nodes(root: Node) -> Array[Node]:
	var nodes: Array[Node] = [root]
	var node_index: int = 0

	while node_index < nodes.size():
		var current_node: Node = nodes[node_index]

		for child: Node in current_node.get_children():
			nodes.append(child)

		node_index += 1

	return nodes


func _detect_instance_duration(
	instance: Node3D,
	definition: CardVFXDefinition
) -> float:
	var nodes: Array[Node] = _collect_nodes(instance)
	var maximum_duration: float = 0.0
	var found_animation: bool = false

	for node: Node in nodes:
		if not node is AnimationPlayer:
			continue

		var animation_player := node as AnimationPlayer
		var animation_name: StringName = _choose_animation_name(
			animation_player,
			definition.animation_name,
			false
		)

		if animation_name == &"":
			continue

		var animation := animation_player.get_animation(
			animation_name
		)

		if animation == null:
			continue

		found_animation = true

		var animation_speed: float = maxf(
			absf(animation_player.speed_scale),
			0.001
		)

		maximum_duration = maxf(
			maximum_duration,
			animation.length / animation_speed
		)

	# For effects that explicitly ask us to force particle playback (Saw,
	# etc.), include particle tails in the lifetime estimate.
	if definition.restart_descendant_particles or not found_animation:
		for node: Node in nodes:
			if node is GPUParticles3D:
				var gpu := node as GPUParticles3D
				maximum_duration = maxf(
					maximum_duration,
					gpu.lifetime / maxf(
						absf(gpu.speed_scale),
						0.01
					)
				)
			elif node is CPUParticles3D:
				var cpu := node as CPUParticles3D
				maximum_duration = maxf(
					maximum_duration,
					cpu.lifetime / maxf(
						absf(cpu.speed_scale),
						0.01
					)
				)

	return maximum_duration


func _start_instance_next_frame(
	instance: Node3D,
	definition: CardVFXDefinition
) -> void:
	if not is_instance_valid(instance):
		return

	if not instance.is_inside_tree():
		return

	var tree := instance.get_tree()

	if tree == null:
		return

	# The old Saw/Mustache implementation already needed this frame wait.
	# Runtime-instanced card VFX need the same initialization window.
	await tree.process_frame

	if not is_instance_valid(instance):
		return

	if not instance.is_inside_tree():
		return

	_start_instance(
		instance,
		definition
	)


func _start_instance(
	instance: Node3D,
	definition: CardVFXDefinition
) -> float:
	var nodes: Array[Node] = _collect_nodes(instance)
	var maximum_duration: float = 0.0
	var started_component_count: int = 0

	for node: Node in nodes:
		node.process_mode = Node.PROCESS_MODE_ALWAYS

		if node is AnimationTree:
			(node as AnimationTree).active = true

	for node: Node in nodes:
		if not node is AnimationPlayer:
			continue

		var animation_player := node as AnimationPlayer
		var animation_name: StringName = _choose_animation_name(
			animation_player,
			definition.animation_name,
			true
		)

		if animation_name == &"":
			continue

		var animation := animation_player.get_animation(
			animation_name
		)

		if animation == null:
			continue

		animation_player.stop()

		if animation_player.has_animation(&"RESET"):
			animation_player.play(&"RESET")
			animation_player.advance(0.0)

		animation_player.play(animation_name)
		animation_player.advance(0.0)

		var animation_speed: float = maxf(
			absf(animation_player.speed_scale),
			0.001
		)

		maximum_duration = maxf(
			maximum_duration,
			animation.length / animation_speed
		)

		started_component_count += 1

	# Some compound VFX (especially the Saw) contain child particle systems
	# that are not completely controlled by the main AnimationPlayer.
	if definition.restart_descendant_particles:
		for node: Node in nodes:
			if node is GPUParticles3D:
				var gpu_particles := node as GPUParticles3D
				gpu_particles.restart()
				gpu_particles.emitting = true

				maximum_duration = maxf(
					maximum_duration,
					gpu_particles.lifetime / maxf(
						absf(gpu_particles.speed_scale),
						0.01
					)
				)

				started_component_count += 1

			elif node is CPUParticles3D:
				var cpu_particles := node as CPUParticles3D
				cpu_particles.restart()
				cpu_particles.emitting = true

				maximum_duration = maxf(
					maximum_duration,
					cpu_particles.lifetime / maxf(
						absf(cpu_particles.speed_scale),
						0.01
					)
				)

				started_component_count += 1

			elif node is AnimatedSprite3D:
				(node as AnimatedSprite3D).play()
				started_component_count += 1

			elif node is AnimatedSprite2D:
				(node as AnimatedSprite2D).play()
				started_component_count += 1

	if started_component_count == 0:
		push_warning(
			"VFX has no playable animation/particle component: "
			+ str(definition.scene.resource_path)
		)
	elif debug_logging:
		print(
			"VFX PLAY | scene=",
			definition.scene.resource_path,
			" | components=",
			started_component_count
		)

	return maximum_duration


func _choose_animation_name(
	animation_player: AnimationPlayer,
	requested_name: StringName,
	warn_if_missing: bool = true
) -> StringName:
	if (
		requested_name != &""
		and animation_player.has_animation(requested_name)
	):
		return requested_name

	if requested_name != &"" and warn_if_missing:
		push_warning(
			"VFX animation not found: %s | available: %s"
			% [
				requested_name,
				animation_player.get_animation_list()
			]
		)

	var autoplay_name: StringName = animation_player.autoplay

	if (
		autoplay_name != &""
		and autoplay_name != &"RESET"
		and animation_player.has_animation(autoplay_name)
	):
		return autoplay_name

	for candidate: StringName in animation_player.get_animation_list():
		if candidate == &"RESET":
			continue
		return candidate

	return &""


func _schedule_cleanup(
	holder: Node3D,
	delay: float
) -> void:
	if not is_instance_valid(holder):
		return

	if delay <= 0.0:
		holder.queue_free()
		return

	var cleanup_timer := Timer.new()
	cleanup_timer.name = "VFXCleanupTimer"
	cleanup_timer.one_shot = true
	cleanup_timer.wait_time = maxf(delay, 0.001)
	cleanup_timer.process_mode = Node.PROCESS_MODE_ALWAYS

	holder.add_child(cleanup_timer)

	cleanup_timer.timeout.connect(
		func() -> void:
			if is_instance_valid(holder):
				holder.queue_free()
	)

	cleanup_timer.start()
