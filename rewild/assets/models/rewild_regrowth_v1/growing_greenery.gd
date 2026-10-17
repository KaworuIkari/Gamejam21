@tool
class_name GrowingGreenery extends Node3D
## Plant-only overlay (ivy, moss, grass, leaves, flowers) on a barren structure.
## Like the forest trees' leaves, it grows in with the GrowthMap: every Patch_* mesh
## gets an overgrowth material (systems/growth_map/overgrowth.gdshader) that reads the
## ground growth under that patch and dissolves the plants in clump by clump, so a big
## landmark overgrows in sections from wherever it was watered. No polling, no tweens.
## Ivy/moss come first, then grass, then leaves, flowers last (thresholds per material
## in rewild_regrowth_v1/materials/).

## The glb's own material name -> overgrowth material that replaces it.
const OVERGROWTH := {
	"Moss olive": preload("res://assets/models/rewild_regrowth_v1/materials/overgrowth_moss_olive.tres"),
	"Olive green foliage": preload("res://assets/models/rewild_regrowth_v1/materials/overgrowth_olive_foliage.tres"),
	"Sunlit foliage": preload("res://assets/models/rewild_regrowth_v1/materials/overgrowth_sunlit_foliage.tres"),
	"Grass": preload("res://assets/models/rewild_regrowth_v1/materials/overgrowth_grass.tres"),
	"Leaves": preload("res://assets/models/rewild_regrowth_v1/materials/overgrowth_leaves.tres"),
	"Leaves_NormalTree": preload("res://assets/models/rewild_regrowth_v1/materials/overgrowth_leaves_normal_tree.tres"),
	"Flowers": preload("res://assets/models/rewild_regrowth_v1/materials/overgrowth_flowers.tres"),
}

## Editor only: show the plants (they always show fully grown in the editor).
@export var preview_green := true:
	set(value):
		preview_green = value
		if Engine.is_editor_hint() and is_inside_tree():
			for p in _patches:
				p.visible = value
## Optional ground point for the whole overlay, for structures standing where the
## ground can't turn green (pier, roof over the sea). Empty: each patch follows the
## ground right under it.
@export var sample_anchor: NodePath

var _patches: Array[MeshInstance3D] = []


func _ready() -> void:
	_collect(self)
	for p in _patches:
		_apply_materials(p)
	if Engine.is_editor_hint():
		for p in _patches:
			p.visible = preview_green
		return
	var growth := get_node_or_null(^"/root/GrowthMap")
	if growth:
		for mat in OVERGROWTH.values():
			growth.attach_material(mat)
	_apply_anchor.call_deferred()


func _collect(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and String(c.name).begins_with("Patch_"):
			_patches.append(c)
		else:
			_collect(c)


func _apply_materials(p: MeshInstance3D) -> void:
	for s in p.mesh.get_surface_count():
		var src := p.mesh.surface_get_material(s)
		var mat: Material = OVERGROWTH.get(src.resource_name if src else "")
		if mat:
			p.set_surface_override_material(s, mat)
		elif src:
			push_warning("GrowingGreenery: no overgrowth material for '%s' in %s" % [src.resource_name, name])


func _apply_anchor() -> void:
	var anchor := get_node_or_null(sample_anchor) as Node3D if not sample_anchor.is_empty() else null
	if anchor == null:
		return
	var at := anchor.global_position
	for p in _patches:
		# y = 1 tells the shader to read this point instead of the patch origin.
		p.set_instance_shader_parameter(&"sample_xz", Vector3(at.x, 1.0, at.z))


func patch_count() -> int:
	return _patches.size()
