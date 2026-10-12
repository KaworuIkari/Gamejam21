## Makes Sky flowers light up around a target (usually the player).
## Add as a child of a Terrain3DParticles node whose mesh material uses sky_flower.gdshader.
extends Node

## What the flowers glow around. Empty = the first node in the "player" group.
@export var target: Node3D
@export var radius := 3.0


func _process(_delta: float) -> void:
	if not target:
		target = get_tree().get_first_node_in_group("player") as Node3D
	var mat := get_parent().get("mesh_material_override") as ShaderMaterial
	if not mat:
		return
	mat.set_shader_parameter("glow_radius", radius if target else 0.0)
	if target:
		mat.set_shader_parameter("glow_center", target.global_position)
