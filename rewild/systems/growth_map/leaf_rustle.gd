class_name LeafRustle extends Node
## Rustle of leaves growing out on the trees whose leaves use tree_leaves.gdshader: once when
## the ground under a tree greens past the material's leaf_start (first leaves) and again past
## leaf_full (full canopy). Add it under the level; trees already leafy on load stay quiet.

const LEAF_SHADER := preload("res://systems/growth_map/tree_leaves.gdshader")

var _trees: Array[Dictionary] = []  # {pos, start, full, stage}
var _pending := false
var _last_msec := 0


func _ready() -> void:
	var seen := {}
	for mesh: MeshInstance3D in get_parent().find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var mat := mesh.get_active_material(i) as ShaderMaterial
			if mat == null or mat.shader != LEAF_SHADER:
				continue
			var cell := Vector3i((mesh.global_position / 3.0).round())  # a tree's leaf meshes share a spot
			if not seen.has(cell):
				seen[cell] = true
				_trees.append({pos = mesh.global_position, stage = 0,
						start = mat.get_shader_parameter(&"leaf_start"), full = mat.get_shader_parameter(&"leaf_full")})
			break
	GrowthMap.changed.connect(_queue_check)
	_check.call_deferred(true)


func _queue_check() -> void:
	if _pending:
		return
	_pending = true
	# Growth changes every simulation tick; a few checks a second is plenty.
	await get_tree().create_timer(0.3).timeout
	_pending = false
	_check(false)


func _check(silent: bool) -> void:
	for tree in _trees:
		var g := GrowthMap.sample(tree.pos)
		var stage := 2 if g >= tree.full else 1 if g >= tree.start else 0
		if stage > tree.stage and not silent and Time.get_ticks_msec() - _last_msec > 150:
			_last_msec = Time.get_ticks_msec()
			UIAudio.play_sfx_at(UIAudio.LEAF_RUSTLE, tree.pos, 0.1, 0.0 if stage == 2 else -3.0)
		tree.stage = stage
