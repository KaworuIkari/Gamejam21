#########
# Turns the selected nodes into Clearables (litter LIRA can clear by holding interact).
# Drag props into Environment_clearable, select them all in the scene tree, open this
# file in the Script editor, then File > Run (Ctrl/Cmd+Shift+X). Undo with Ctrl/Cmd+Z.
# Nodes that already have a script are skipped. Fine-tune each one in the Inspector after.
#########

@tool
extends EditorScript

const CLEARABLE := preload("res://systems/world_objects/clearable.gd")
## Reported to the quests when cleared; "garbage" is upgrade material at the terminal.
const TAGS: Array[StringName] = [&"garbage"]
## Extra reach beyond the prop's own size, so big wrecks can be cleared from their edge.
const REACH := 2.0
const MIN_RADIUS := 3.0


func _run() -> void:
	var undo := get_editor_interface().get_editor_undo_redo()
	undo.create_action("Make Clearable")
	var count := 0
	for node in get_editor_interface().get_selection().get_top_selected_nodes():
		if not node is Node3D:
			continue
		if node.get_script() != null:
			push_warning("make_clearable: %s already has a script, skipped" % node.name)
			continue
		var radius := maxf(MIN_RADIUS, _half_size(node) + REACH)
		# In order: the script first, so tags and radius exist when they're set.
		undo.add_do_property(node, &"script", CLEARABLE)
		undo.add_do_property(node, &"tags", TAGS.duplicate())
		undo.add_do_property(node, &"radius", radius)
		undo.add_undo_property(node, &"script", null)
		count += 1
	undo.commit_action()
	print("make_clearable: made %d node(s) clearable" % count)


## Half the prop's widest horizontal extent, from its meshes.
func _half_size(node: Node3D) -> float:
	var box := AABB()
	var first := true
	for v in node.find_children("*", "VisualInstance3D", true, false):
		var b: AABB = v.global_transform * v.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return 0.0 if first else maxf(box.size.x, box.size.z) * 0.5
