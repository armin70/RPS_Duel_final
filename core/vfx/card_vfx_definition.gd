class_name CardVFXDefinition
extends Resource


enum SpawnTarget {
	SOURCE_CARD,
	TARGET_CARD,
	DEALER_ANCHOR,
	BOARD_ANCHOR
}


@export_category("Scene")

@export var scene: PackedScene

@export var spawn_target: SpawnTarget = \
	SpawnTarget.SOURCE_CARD


@export_category("Playback")

# Leave empty to use autoplay or the first non-RESET animation.
@export var animation_name: StringName = &""

# Some VFX scenes contain child particle systems that are not driven by
# the main AnimationPlayer. Enable this only for those effects.
@export var restart_descendant_particles: bool = false

# Extra time considered part of the effect. Useful for particle tails.
@export_range(0.0, 5.0, 0.05)
var completion_padding: float = 0.0

# Extra time the instance remains alive after gameplay has finished waiting.
@export_range(0.0, 5.0, 0.05)
var cleanup_delay: float = 0.15

# Optional manual duration. Zero means detect it from the animation/particles.
@export_range(0.0, 20.0, 0.05)
var duration_override: float = 0.0


@export_category("Transform")

# Applied relative to the selected source/target/anchor transform.
@export var local_offset: Vector3 = Vector3.ZERO
@export var local_rotation_degrees: Vector3 = Vector3.ZERO

@export_range(0.01, 10.0, 0.01)
var scale_multiplier: float = 1.0
