@tool
extends Node3D
## Visual-only two-state prop; finale_story owns quest and inventory progression.
@export var activated := false:
 set(value):
  activated = value
  if is_node_ready(): _apply_state()
var _glow_materials: Array[StandardMaterial3D] = []
func _ready() -> void:
 # Runtime only: override materials set in the editor would be saved into the scene.
 if not Engine.is_editor_hint(): _prepare_materials($Core)
 _apply_state()
func _prepare_materials(node: Node) -> void:
 if node is MeshInstance3D:
  for i in node.mesh.get_surface_count():
   var material = node.get_active_material(i)
   if material is StandardMaterial3D and (material.emission_enabled or 'cyan' in material.resource_name.to_lower()):
    var local: StandardMaterial3D = material.duplicate()
    node.set_surface_override_material(i, local)
    _glow_materials.append(local)
 for child in node.get_children(): _prepare_materials(child)
func _apply_state() -> void:
 for material in _glow_materials:
  material.albedo_color = Color(0.08,0.75,0.95) if activated else Color(0.07,0.14,0.17)
  material.emission_enabled = activated
  material.emission = Color(0.06,0.65,1.0)
  material.emission_energy_multiplier = 2.0 if activated else 0.0
 $CoreLight.visible = activated
 $ConsoleLight.visible = activated
 $ActiveIndicators.visible = activated
