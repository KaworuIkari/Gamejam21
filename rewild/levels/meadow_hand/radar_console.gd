extends "res://objects/interactables/interact_trigger.gd"
## Keep all entry points behind the same quest/key/recovery checks.
var story: Node
var _message := ""

func _ready() -> void:
	one_shot = false
	collision_layer = 0
	collision_mask = 1
	super._ready()

func _process(_delta: float) -> void:
	var key: String = story.prompt_key()
	if key != _message:
		_message = key
		_prompt.configure(&"interact", key)
	_prompt.set_interactable(story.can_operate())
	_prompt.set_available(super._can_use() and not story.finished_reading() and not story.busy)

func _can_use() -> bool:
	return super._can_use() and story.can_operate()

func use() -> void:
	if _can_use():
		story.activate_radar()
