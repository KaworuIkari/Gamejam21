extends "res://objects/interactables/interact_trigger.gd"
var story: Node
var route: StringName
var _message := ""

func _ready() -> void:
	one_shot = false
	collision_layer = 0
	collision_mask = 1
	super._ready()

func _process(_delta: float) -> void:
	var key: String = story.prompt_key(route)
	if key != _message:
		_message = key
		_prompt.configure(&"interact",key)
	_prompt.set_interactable(story.can_choose(route))
	_prompt.set_available(super._can_use() and (story.boat_available() if route == &"boat" else story.available()) and not story.busy)

func _can_use() -> bool:
	return super._can_use() and story.can_choose(route)

func use() -> void:
	if _can_use():
		story.request_ending(route)
