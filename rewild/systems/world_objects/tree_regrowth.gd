extends Node
## Counts the plain trees (placed straight from the model or scattered, not a Restorable) for
## the "tree_restored" quest event: a tree counts once the ground under it has turned green.
## Trees that already stand on green ground when first seen do not count, like a Restorable.
## Add it to the level: it takes the trees already in the scene, and picks up trees that appear
## later (the scatter tool builds its trees after the level is ready) as they are added.

## Ground greenness (0..1) under a tree that counts as restored (same as Restorable's default).
const THRESHOLD := 0.6
## Model folders whose scenes are trees.
const TREE_MODELS: Array[String] = ["/stylized_nature/TwistedTree/", "/stylized_nature/CommonTree/", "/stylized_nature/Pine/"]
## Trees closer than this (metres) are one tree: a wrapper scene and the model inside it, or
## copies on the same spot, must not count twice.
const SAME_SPOT := 1.0
const CHECK_INTERVAL := 0.5

@export var event: StringName = &"tree_restored"

var _waiting: Array[Node3D] = []
var _seen := {}  # Vector2i grid cell -> true
var _timer := 0.0


## Skips the looks inside a Restorable (it reports itself).
static func _is_plain_tree(node: Node) -> bool:
	if node.get_parent() is Restorable:
		return false
	for folder in TREE_MODELS:
		if node.scene_file_path.contains(folder):
			return true
	return false


func _ready() -> void:
	for node in get_parent().find_children("*", "Node3D", true, false):
		if _is_plain_tree(node):
			_watch(node)
	get_tree().node_added.connect(_on_node_added)
	set_process(not _waiting.is_empty())


func _on_node_added(node: Node) -> void:
	if node is Node3D and _is_plain_tree(node):
		_watch.call_deferred(node)  # its transform is set after it is added


func _watch(tree: Node3D) -> void:
	if not is_instance_valid(tree) or not tree.is_inside_tree():
		return
	var spot := tree.global_position
	var cell := Vector2i(roundi(spot.x / SAME_SPOT), roundi(spot.z / SAME_SPOT))
	if _seen.has(cell):
		return
	_seen[cell] = true
	if GrowthMap.sample(spot) < THRESHOLD:
		_waiting.append(tree)
		set_process(true)


func _process(delta: float) -> void:
	_timer += delta
	if _timer < CHECK_INTERVAL:
		return
	_timer = 0.0
	for tree in _waiting.duplicate():
		if not is_instance_valid(tree):
			_waiting.erase(tree)
		elif GrowthMap.sample(tree.global_position) >= THRESHOLD:
			_waiting.erase(tree)
			Quests.report(event)
	set_process(not _waiting.is_empty())

