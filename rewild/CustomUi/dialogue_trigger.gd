@icon("res://addons/dialogic/Editor/Images/Resources/portrait.svg")
class_name DialogueTrigger
extends Area3D
## 可复用的对话触发区域。
## 用法：拖一个 DialogueTrigger 到场景里（例如 NPC 下面），在 Inspector 里填 timeline。
## 玩家进入范围后头顶出现“按 F 交谈”，按交互键（interact）开始对话。
## 玩家判定：属于 player_group 分组的物体，或带 frozen 属性的 CharacterBody3D（real-controller 角色）。
## 已有 Area3D 想改成“按 F 对话”：DialogueTrigger.attach_to(那个Area3D, "时间线名")

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
## 提示文字的位置（相对本节点）
@export var prompt_offset: Vector3 = Vector3(0, 2.4, 0)
@export_file("*.ttf", "*.tres") var prompt_font: String = "res://fonts/ChillBitmap7x.ttf"

var _player_inside := false
var _used := false
var _prompt: Label3D


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if not _has_shape():
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = radius
		shape.shape = sphere
		add_child(shape)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_create_prompt()
	var dialogic := _dialogic()
	if dialogic:
		dialogic.timeline_ended.connect(_on_timeline_ended)


## 把一个已有的 Area3D 变成“按 F 对话”：复制它的碰撞形状和层/掩码，生成一个 DialogueTrigger 子节点
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
	_prompt = Label3D.new()
	# 不跟随父节点旋转 / 缩放，始终在触发器正上方
	_prompt.top_level = true
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.fixed_size = true
	_prompt.pixel_size = 0.0008
	_prompt.font_size = 32
	_prompt.outline_size = 8
	_prompt.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_prompt.modulate = Color("e8c872")
	if ResourceLoader.exists(prompt_font):
		_prompt.font = load(prompt_font)
	_prompt.visible = false
	add_child(_prompt)


func _process(_delta: float) -> void:
	if _prompt == null:
		return
	var show := _player_inside and not auto_start and _can_start()
	if show:
		_prompt.global_position = global_position + prompt_offset
		_prompt.text = tr("DLG_TALK_PROMPT") % _interact_key_text()
	_prompt.visible = show


func _unhandled_input(event: InputEvent) -> void:
	if _player_inside and event.is_action_pressed(&"interact") and _can_start():
		get_viewport().set_input_as_handled()
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
	dialogic.start(timeline)
	dialogue_started.emit(timeline)


func _can_start() -> bool:
	if one_shot and _used:
		return false
	var dialogic := _dialogic()
	return dialogic != null and dialogic.current_timeline == null and not get_tree().paused


func _is_player(body: Node) -> bool:
	return body.is_in_group(player_group) or (body is CharacterBody3D and &"frozen" in body)


func _on_body_entered(body: Node) -> void:
	if _is_player(body):
		_player_inside = true
		if auto_start:
			start.call_deferred()


func _on_body_exited(body: Node) -> void:
	if _is_player(body):
		_player_inside = false


func _on_timeline_ended() -> void:
	dialogue_finished.emit(timeline)


func _dialogic() -> Node:
	return get_node_or_null(^"/root/Dialogic")


func _interact_key_text() -> String:
	var sm := get_node_or_null(^"/root/SettingsManager")
	if sm and sm.has_method("event_to_text") and sm.has_method("get_binding"):
		var ev = sm.get_binding(&"interact", "kbm")
		if ev:
			return sm.event_to_text(ev)
	return "F"
