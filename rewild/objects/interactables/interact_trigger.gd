class_name InteractTrigger
extends Area3D
## Press-to-use zone for props (levers, pumps, valves). Add it under the prop, give it a
## CollisionShape3D (or let it make a sphere of `radius`), then connect `interacted` to
## whatever should happen, e.g. WaterFlowSwitch.turn_on.
## Player check and prompt match dialogue_trigger.gd.

signal interacted

## Translation key for the prompt; "%s" is replaced by the bound key.
@export var message_key := "INTERACT_PUMP_PROMPT"
## Can only be used once per run (the prompt disappears afterwards).
@export var one_shot := true
@export var player_group: StringName = &"player"
## Radius of the auto-made sphere when there's no CollisionShape3D child.
@export var radius := 3.0

const PROMPT_SCENE = preload("res://ui/in_game/interaction/interaction_prompt.tscn")

var _player_inside := false
var _used := false
var _prompt: CanvasLayer


func _ready() -> void:
	if not _has_shape():
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = radius
		shape.shape = sphere
		add_child(shape)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_prompt = PROMPT_SCENE.instantiate()
	add_child(_prompt)
	_prompt.configure(&"interact", message_key)


func _process(_delta: float) -> void:
	_prompt.set_available(_can_use())


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_echo() and event.is_action_pressed(&"interact") and _can_use():
		get_viewport().set_input_as_handled()
		use()


## Can also be called from code (e.g. a cutscene).
func use() -> void:
	if one_shot and _used:
		return
	_used = true
	interacted.emit()


func _can_use() -> bool:
	if not _player_inside or (one_shot and _used) or get_tree().paused:
		return false
	var dialogic := get_node_or_null(^"/root/Dialogic")
	return dialogic == null or dialogic.current_timeline == null


func _has_shape() -> bool:
	for c in get_children():
		if c is CollisionShape3D or c is CollisionPolygon3D:
			return true
	return false


func _is_player(body: Node) -> bool:
	return body.is_in_group(player_group) or (body is CharacterBody3D and &"frozen" in body)


func _on_body_entered(body: Node) -> void:
	if _is_player(body):
		_player_inside = true


func _on_body_exited(body: Node) -> void:
	if _is_player(body):
		_player_inside = false
