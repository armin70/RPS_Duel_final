@tool
extends Node3D
class_name VFXEmitterBB

var materials : Array[ShaderMaterial]:
	get():
		if !materials.is_empty():
			return materials
		
		var result : Array[ShaderMaterial]
		for c in get_children():
			if c is GPUParticles3D || c is MeshInstance3D:
				if c.material_override:
					result.append(c.material_override)
		if !Engine.is_editor_hint():
			materials = result
		return result

var meshes : Array[MeshInstance3D]:
	get():
		if !meshes.is_empty():
			return meshes
		
		var result : Array[MeshInstance3D]
		for c in get_children():
			if c is MeshInstance3D:
				result.append(c)
		if !Engine.is_editor_hint():
			meshes = result
		return result

var particles : Array[GPUParticles3D]:
	get():
		if !particles.is_empty():
			return particles
		
		var result : Array[GPUParticles3D]
		for c in get_children():
			if c is GPUParticles3D:
				result.append(c)
		if !Engine.is_editor_hint():
			particles = result
		return result

var anim: AnimationPlayer:
	get:
		return get_node_or_null("AnimationPlayer") as AnimationPlayer

@export var emitting : bool = true:
	set(v):
		emitting = v
		for p in particles:
			p.emitting = emitting
		if emitting:
			open()
		else:
			close()

@export_range(0.0, 8.0, 0.01) var speed_scale : float = 1.0:
	set(v):
		speed_scale = v
		for p in particles:
			p.speed_scale = speed_scale
		_set_shader_param("speed_scale", speed_scale)

func _restart_particles() -> void:
	for p in particles:
		p.restart()

func _set_particle_param(key : String, value : Variant) -> void:
	var parts : Array[GPUParticles3D] = particles
	for p in parts:
		p.set(key, value)

func _set_shader_param(key : String, value : Variant) -> void:
	var mats : Array[ShaderMaterial] = materials
	for m in mats:
		m.set_shader_parameter(key, value)

func open() -> void:
	var animation_player: AnimationPlayer = anim

	if animation_player != null:
		if animation_player.has_animation("open"):
			animation_player.play("open")


func close() -> void:
	var animation_player: AnimationPlayer = anim

	if animation_player != null:
		if animation_player.has_animation("close"):
			animation_player.play("close")
