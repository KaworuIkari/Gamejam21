class_name WaterWell
extends Node3D
## Put under a well (the level adds one to every well under Enviroment/Global/Wells).
## Hold interact beside the dry well to start it: the `rise` nodes (water you add later,
## like the pump's WaterFlowSwitch) move up, `activated` fires, and the well becomes a
## water source where WaterRefill lets LIRA fill her tank. Saved per well.

signal activated

const HOLD_PROMPT_SCENE = preload("res://ui/in_game/interaction/clear_hold_prompt.tscn")

@export var hold_time := 1.5
## How close LIRA must be to start the well, and later to fill her tank from it, in the
## well's own metres (a well scaled ×2 reaches twice as far).
@export var radius := 2.5
@export var prompt_key := "WELL_ACTIVATE_PROMPT"
## Water meshes inside the well: they start rise_height lower and move up when activated.
@export var rise: Array[Node3D] = []
@export var rise_height := 1.5
@export var rise_time := 3.0
## Saved event; empty = made from the well's path in the level.
@export var saved_event: StringName = &""

var is_source := false

var _prompt: CanvasLayer
var _player: Node3D
var _hold := 0.0
## A well accepts only a new press while it owns the interaction.
var _hold_started := false


func _ready() -> void:
	add_to_group(&"water_wells")
	if saved_event == &"":
		var scene := get_tree().current_scene
		var path := String(scene.get_path_to(get_parent()) if scene else get_parent().name)
		saved_event = StringName("well_" + path.to_snake_case().replace("/", "__"))
	var area := Area3D.new()
	area.name = "WellRange"
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(func(body: Node3D) -> void: if body.is_in_group(&"player"): _player = body)
	area.body_exited.connect(func(body: Node3D) -> void: if body == _player: _player = null)
	if Quests.event_count(saved_event) > 0:
		_become_source()
		return
	for water in rise:
		water.position.y -= rise_height
	_prompt = HOLD_PROMPT_SCENE.instantiate()
	add_child(_prompt)
	_prompt.configure(&"interact", prompt_key)


## LIRA is inside the well's range (used for starting it and, once it runs, for filling).
func player_near() -> bool:
	return _player != null


func _process(delta: float) -> void:
	if is_source or _prompt == null:
		return
	var can := can_activate()
	var pressed := Input.is_action_pressed(&"interact")
	if not can or not pressed:
		_hold_started = false
	_prompt.set_available(can)
	_prompt.set_interactable(_hold_started or not pressed)
	if can and pressed and _hold_started:
		_hold += delta
		if _hold >= hold_time:
			_prompt.play_activation()
			activate()
	else:
		_hold = 0.0
	_prompt.set_hold_progress(_hold / hold_time)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_echo() and event.is_action_pressed(&"interact"):
		_hold_started = can_activate()


## Reading > available clearing > the nearest inactive well. Locked litter does not block.
func can_activate() -> bool:
	if is_source or not is_instance_valid(_player) or get_tree().paused:
		return false
	var dialogic := get_node_or_null(^"/root/Dialogic")
	if dialogic != null and dialogic.current_timeline != null:
		return false
	for candidate in get_tree().get_nodes_in_group(&"dialogue_interaction_candidates"):
		if candidate is DialogueTrigger and candidate._is_active_target():
			return false
	if Clearable.has_active_target(get_tree()):
		return false
	var distance := global_position.distance_squared_to(_player.global_position)
	for well in get_tree().get_nodes_in_group(&"water_wells"):
		if well == self or well.is_source or not is_instance_valid(well._player):
			continue
		var other_distance: float = well.global_position.distance_squared_to(_player.global_position)
		if other_distance < distance or (is_equal_approx(other_distance, distance) and well.get_instance_id() < get_instance_id()):
			return false
	return true


## Also callable from code (cutscenes, debug).
func activate() -> void:
	if is_source:
		return
	Quests.report(saved_event)
	for water in rise:
		create_tween().tween_property(water, ^"position:y", water.position.y + rise_height, rise_time) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_become_source()
	activated.emit()


func _become_source() -> void:
	is_source = true
	_hold = 0.0
	if _prompt:
		_prompt.set_available(false)
	add_to_group(&"water_sources")
