extends Node
## The world at the start of a new game: what is switched off until the story wakes it
## (`dormant`) and the few permanent patches of green on the otherwise bare ground
## (`green_spots`). The level fills both in; this node does nothing else.
## (Player gear is not handled here: it comes from quest rewards, see LIRA's Abilities.
##  Ground that is green from the start otherwise comes from the terrain's painted green slot, see GrowthMap.always_green_slot.)

## Hidden and frozen until awaken() is called (animals, the companion bot...).
var dormant: Array[Node3D] = []
## Node3D -> radius in metres: ground around it is green from the start and stays green.
var green_spots: Dictionary = {}


func _ready() -> void:
	for node in dormant:
		_set_awake(node, false)
	for spot: Node3D in green_spots:
		GrowthMap.seed_circle(spot.global_position, green_spots[spot])


## Switches everything back on; animal spawners that were held back now spawn.
func awaken() -> void:
	for node in dormant:
		wake(node)


## Switches one dormant node back on (e.g. only the companion bot).
func wake(node: Node3D) -> void:
	_set_awake(node, true)
	for spawner in node.find_children("*", "AnimalSpawner", true, false):
		spawner.spawn_all()


func _set_awake(node: Node3D, awake: bool) -> void:
	node.visible = awake
	node.process_mode = Node.PROCESS_MODE_INHERIT if awake else Node.PROCESS_MODE_DISABLED
