#########
# Drops the selected nodes onto the Terrain3D ground.
# Select nodes in the scene tree, open this file in the Script editor,
# then File > Run (Ctrl/Cmd+Shift+X). Undo with Ctrl/Cmd+Z.
# Reads the terrain height directly, so it works at any distance and needs no collision.
#########

@tool
extends EditorScript

## true: the model's lowest point touches the ground (works whatever the origin is).
## false: the node's origin touches the ground. Clearables (litter) always use their origin.
const USE_MODEL_BOTTOM := true
## Sink objects slightly so their edges don't float on slopes.
const SINK := 0.05


func _run() -> void:
	var root := get_scene()
	var terrains := root.find_children("", "Terrain3D", true, false)
	if terrains.is_empty() or terrains[0].data == null:
		push_error("snap_to_terrain: no Terrain3D in the open scene")
		return
	var data = terrains[0].data

	var undo := get_editor_interface().get_editor_undo_redo()
	undo.create_action("Snap to Terrain3D")
	var count := 0
	for node in get_editor_interface().get_selection().get_top_selected_nodes():
		if not node is Node3D:
			continue
		var pos: Vector3 = node.global_position
		var height: float = data.get_height(pos)
		if is_nan(height):
			push_warning("snap_to_terrain: %s is outside the terrain" % node.name)
			continue
		# Litter piles have stray bits hanging below their base, so they sit by origin.
		var by_bottom := USE_MODEL_BOTTOM and not node is Clearable
		var bottom_offset := _bottom_offset(node) if by_bottom else 0.0
		var target := Vector3(pos.x, height - bottom_offset - SINK, pos.z)
		undo.add_do_property(node, "global_position", target)
		undo.add_undo_property(node, "global_position", pos)
		count += 1
	undo.commit_action()
	print("snap_to_terrain: snapped %d node(s)" % count)


## How far the model's lowest point sits below the node's origin (negative if below).
func _bottom_offset(node: Node3D) -> float:
	var lowest := INF
	for v in [node] + node.find_children("*", "VisualInstance3D", true, false):
		if not v is VisualInstance3D or not v.is_visible_in_tree():
			continue
		var box: AABB = v.global_transform * v.get_aabb()
		lowest = minf(lowest, box.position.y)
	return 0.0 if lowest == INF else lowest - node.global_position.y
