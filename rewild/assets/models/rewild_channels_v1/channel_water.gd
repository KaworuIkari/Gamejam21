@tool
extends Node3D
## Visual animation only. Water volume and route progression belong to gameplay.
@export var flow_direction := Vector2(0, -1)
@export var flow_speed := 0.7
func _ready() -> void:
 var material = ShaderMaterial.new()
 material.shader = preload("res://assets/models/rewild_channels_v1/channel_water.gdshader")
 material.set_shader_parameter("flow_direction", flow_direction)
 material.set_shader_parameter("flow_speed", flow_speed)
 for mesh in find_children("Water", "MeshInstance3D", true, false):
  mesh.material_override = material
