#########
# Replaces all children with another scene
# single use during kitbash
#########

@tool
extends Node3D

@export var replacement_scene: PackedScene
@export_tool_button("Replace All Children") var replace_button = replace_children

func replace_children():
	if replacement_scene == null:
		push_error("Assign replacement_scene first")
		return

	# Remove existing children
	for child in get_children():
		child.queue_free()

	# Spawn one instance
	var new_node = replacement_scene.instantiate()
	add_child(new_node)
	new_node.owner = get_tree().edited_scene_root
