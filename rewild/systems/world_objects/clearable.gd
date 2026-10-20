class_name Clearable extends Node3D
## Something LIRA clears by holding interact: litter, rubble, cages, wall sections.
## Put the prop scene under this node. When cleared, the whole node shrinks away
## (collision included), the ground around it blooms a little, and `replace_with`
## (e.g. an open enclosure) plus `release` (e.g. the rescued animal) are spawned.
## Progression listens to `cleared` and counts by tag.

signal cleared(clearable: Clearable)

## Abilities the player has unlocked (e.g. &"demolition_auth"). Set by the level.
static var abilities: Dictionary = {}
## The one clearable the prompt is for, so holding interact clears one thing at a time.
static var _focus: Clearable

@export var object_id: StringName = &""
## Each tag is also reported to the quests when this is cleared, so a quest step with
## event "garbage" counts every Clearable tagged garbage.
@export var tags: Array[StringName] = []
@export var hold_time := 0.8
## How close the player must be, in metres.
@export var radius := 3.0
## Needs this ability before it can be cleared (empty = always). Abilities come from
## quest rewards (Quests autoload) or the static `abilities` dictionary below.
@export var required_ability: StringName = &""
## Spawned at the same transform once cleared (e.g. Rescue_Enclosure_Open).
@export var replace_with: PackedScene
## Spawned once cleared, offset by release_offset (e.g. the trapped animal).
@export var release: PackedScene
@export var release_offset := Vector3(0, 0.5, 1.5)
## Green bloom around the spot when cleared (0 = none).
@export var bloom_radius := 6.0
@export var message_key := "CLEAR_PROMPT"
@export var locked_key := "CLEAR_LOCKED"

const PROMPT_SCENE = preload("res://ui/in_game/interaction/clear_hold_prompt.tscn")

var is_cleared := false

var _player: Node3D
var _hold := 0.0
var _prompt: CanvasLayer
var _prompt_locked := false
var _base_position := Vector3.ZERO


func _ready() -> void:
	add_to_group(&"clearable")
	_base_position = position
	var area := Area3D.new()
	area.name = "ClearRange"
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func is_locked() -> bool:
	if required_ability == &"" or abilities.get(required_ability, false):
		return false
	var quests := get_node_or_null(^"/root/Quests")
	return not (quests and quests.has_ability(required_ability))


func has_tag(tag: StringName) -> bool:
	return tag in tags


func _process(delta: float) -> void:
	if is_cleared:
		return
	_update_focus()
	var focused := _focus == self
	if focused and _prompt == null:
		_prompt = PROMPT_SCENE.instantiate()
		add_child(_prompt)
		_prompt_locked = not is_locked()  # forces configure below
	if _prompt:
		var locked := is_locked()
		if locked != _prompt_locked:
			_prompt_locked = locked
			_prompt.configure(&"interact", locked_key if locked else message_key)
		_prompt.set_available(focused and _can_act())
		_prompt.set_interactable(not locked)

	if focused and _can_act() and not is_locked() and Input.is_action_pressed(&"interact"):
		_hold += delta
		# Shake harder as the hold completes, so the player sees it working.
		var k := _hold / hold_time
		position = _base_position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.06 * k
		if _hold >= hold_time:
			_prompt.play_activation()
			clear()
	elif _hold > 0.0:
		_hold = 0.0
		position = _base_position
	if _prompt:
		_prompt.set_hold_progress(_hold / maxf(hold_time, 0.001))


## Also callable from code (cutscenes, debug skip).
func clear(instant := false) -> void:
	if is_cleared:
		return
	is_cleared = true
	if _focus == self:
		_focus = null
	if _prompt:
		_prompt.set_available(false)
	position = _base_position
	var growth := get_node_or_null(^"/root/GrowthMap")
	if growth and bloom_radius > 0.0:
		growth.reveal_from(global_position, 0.0 if instant else 1.5, bloom_radius)
	if replace_with:
		var r: Node3D = replace_with.instantiate()
		get_parent().add_child(r)
		r.transform = transform
	if release:
		var a: Node3D = release.instantiate()
		get_parent().add_child(a)
		a.global_position = global_transform * release_offset
	cleared.emit(self)
	var quests := get_node_or_null(^"/root/Quests")
	if quests and not instant:
		for t in tags:
			quests.report(t)
	if instant:
		queue_free()
		return
	var t := create_tween()
	t.tween_property(self, "scale", Vector3.ONE * 0.01, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(queue_free)


func _update_focus() -> void:
	if _player == null:
		if _focus == self:
			_focus = null
		return
	var d := global_position.distance_squared_to(_player.global_position)
	if _focus == null or not is_instance_valid(_focus) or _focus.is_cleared or _focus._player == null \
			or d < _focus.global_position.distance_squared_to(_player.global_position) - 0.01:
		_focus = self


func _can_act() -> bool:
	if get_tree().paused:
		return false
	var dialogic := get_node_or_null(^"/root/Dialogic")
	return dialogic == null or dialogic.current_timeline == null


func _is_player(body: Node) -> bool:
	return body.is_in_group(&"player") or (body is CharacterBody3D and &"frozen" in body)


func _on_body_entered(body: Node) -> void:
	if _is_player(body):
		_player = body


func _on_body_exited(body: Node) -> void:
	if body == _player:
		_player = null
