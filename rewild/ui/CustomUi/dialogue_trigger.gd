@icon("res://addons/dialogic/Editor/Images/Resources/portrait.svg")
class_name DialogueTrigger
extends Area3D
## 可复用的对话触发区域。
## 用法：拖一个 DialogueTrigger 到场景里（例如 NPC 下面），在 Inspector 里填 timeline。
## 玩家进入范围后屏幕下方出现玻璃交互提示，按交互键（interact）开始对话。
## 玩家判定：属于 player_group 分组的物体，或带 frozen 属性的 CharacterBody3D（real-controller 角色）。
## 已有 Area3D 想改成“按交互绑定键对话”：DialogueTrigger.attach_to(那个Area3D, "时间线名")

signal dialogue_started(timeline: String)
signal dialogue_finished(timeline: String)

## 时间线名（如 "XBot_timeline"）或路径（res://.../xxx.dtl）
@export var timeline: String = ""
## 进入范围立即开始（不需要按键）
@export var auto_start: bool = false
## 只触发一次（本次运行内）
@export var one_shot: bool = false
## 玩家所在分组
@export var player_group: StringName = &"player"
## 没有手动添加 CollisionShape3D 时，自动生成的球形范围半径（米）
@export var radius: float = 2.5
const PROMPT_SCENE = preload("res://ui/in_game/interaction/interaction_prompt.tscn")

var _player_inside := false
var _used := false
var _owns_dialogue := false
var _player: Node3D
var _prompt: CanvasLayer


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if not _has_shape():
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = radius
		shape.shape = sphere
		add_child(shape)
	add_to_group(&"dialogue_interaction_candidates")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_create_prompt()
	var dialogic := _dialogic()
	if dialogic:
		dialogic.timeline_ended.connect(_on_timeline_ended)


## 把一个已有的 Area3D 变成“按交互绑定键对话”：复制它的碰撞形状和层/掩码，生成一个 DialogueTrigger 子节点
static func attach_to(area: Area3D, timeline_name: String) -> DialogueTrigger:
	var trigger := DialogueTrigger.new()
	trigger.name = &"DialogueTrigger"
	trigger.timeline = timeline_name
	trigger.collision_layer = area.collision_layer
	trigger.collision_mask = area.collision_mask
	for c in area.get_children():
		if c is CollisionShape3D or c is CollisionPolygon3D:
			trigger.add_child(c.duplicate())
	area.add_child(trigger)
	return trigger


func _has_shape() -> bool:
	for c in get_children():
		if c is CollisionShape3D or c is CollisionPolygon3D:
			return true
	return false


func _create_prompt() -> void:
	_prompt = PROMPT_SCENE.instantiate()
	add_child(_prompt)
	_prompt.configure(&"interact", "DLG_TALK_PROMPT")


func _process(_delta: float) -> void:
	_prompt.set_available(_is_active_target())


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_echo() and event.is_action_pressed(&"interact") and _is_active_target():
		get_viewport().set_input_as_handled()
		_prompt.play_activation()
		start()


## 也可以在代码里直接调用 start() 触发
func start() -> void:
	if not _can_start():
		return
	var dialogic := _dialogic()
	if dialogic == null or timeline.is_empty():
		push_warning("DialogueTrigger: 未设置 timeline 或 Dialogic 不可用")
		return
	_used = one_shot
	_owns_dialogue = true
	_prompt.set_available(false)
	dialogic.start(timeline)
	dialogue_started.emit(timeline)


func _can_start() -> bool:
	if one_shot and _used:
		return false
	var dialogic := _dialogic()
	return not timeline.is_empty() and dialogic != null and dialogic.current_timeline == null and not get_tree().paused


func _is_active_target() -> bool:
	if not _player_inside or auto_start or not _can_start() or not is_instance_valid(_player):
		return false
	var distance := global_position.distance_squared_to(_player.global_position)
	for candidate in get_tree().get_nodes_in_group(&"dialogue_interaction_candidates"):
		if candidate == self or not candidate is DialogueTrigger:
			continue
		if not candidate._player_inside or candidate.auto_start or not candidate._can_start():
			continue
		var other_distance: float = candidate.global_position.distance_squared_to(_player.global_position)
		if other_distance < distance or (is_equal_approx(other_distance, distance) and candidate.get_instance_id() < get_instance_id()):
			return false
	return true


func _is_player(body: Node) -> bool:
	return body.is_in_group(player_group) or (body is CharacterBody3D and &"frozen" in body)


func _on_body_entered(body: Node) -> void:
	if _is_player(body):
		_player_inside = true
		_player = body
		if auto_start:
			start.call_deferred()


func _on_body_exited(body: Node) -> void:
	if _is_player(body):
		_player_inside = false


func _on_timeline_ended() -> void:
	if _owns_dialogue:
		_owns_dialogue = false
		dialogue_finished.emit(timeline)


func _dialogic() -> Node:
	return get_node_or_null(^"/root/Dialogic")
