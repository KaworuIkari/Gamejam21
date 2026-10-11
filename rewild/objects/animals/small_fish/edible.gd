extends Node
class_name Edible
## Add as a child of any creature that can be eaten. Composition instead of an interface:
## fish scenes can be completely different; this node is the shared "eatable" trait.

const GROUP := &"edible"
signal eaten(by: Node)

@export var nutrition := 0.5            # how much hunger one bite removes (shark hunger is 0..1)
@export var body: Node3D                # the moving root of the creature; defaults to parent
@export var free_on_eaten := true       # false = handle it yourself via the `eaten` signal

var is_eaten := false


func _ready() -> void:
	add_to_group(GROUP)
	if body == null:
		body = get_parent() as Node3D


func get_body() -> Node3D:
	return body if is_instance_valid(body) and body.is_inside_tree() else null


## Returns the nutrition gained (0 if it was already eaten this frame).
func eat(by: Node) -> float:
	if is_eaten:
		return 0.0
	is_eaten = true
	remove_from_group(GROUP)
	eaten.emit(by)
	if free_on_eaten and is_instance_valid(body):
		body.queue_free()
	return nutrition


## Find the Edible belonging to a collider: checks the node, its children, then up a few parents
## (the collider is often a child body or area of the creature's root).
static func find_on(node: Node, max_up := 3) -> Edible:
	var n := node
	for i in max_up + 1:
		if n == null:
			return null
		if n is Edible:
			return n
		for c in n.get_children():
			if c is Edible:
				return c
		n = n.get_parent()
	return null