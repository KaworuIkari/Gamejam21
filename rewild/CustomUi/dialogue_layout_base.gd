@tool
extends DialogicLayoutBase
## 自定义对话布局的根节点（custom_ui_.tscn）。
## - 提供全局字体/字号/颜色给 Dialogic 自带的图层（如词汇表）读取
## - 隐藏“站位立绘层”：join / leave / update 指令照常工作，但不在屏幕上画大立绘，
##   说话人的头像统一显示在对话框左侧
## - 对话期间冻结玩家（不能移动/转视角）并显示鼠标，结束后恢复
## - 切换场景（如返回主菜单）时自动结束对话

@export var canvas_layer: int = 10

@export_subgroup("Global")
@export var global_bg_color: Color = Color(0.15, 0.17, 0.19, 1)
@export var global_font_color: Color = Color("e6e8eb")
@export_file("*.ttf", "*.tres") var global_font: String = "res://fonts/ChillBitmap7x.ttf"
@export var global_font_size: int = 32
## 是否在屏幕上显示站位立绘（关闭时只在对话框里显示说话人头像）
@export var show_stage_portraits: bool = false


var _tree_was_paused := false
var _dialogic_paused_before := false

## 对话期间被冻结的玩家
var _frozen_players: Array[Node] = []
var _mouse_mode_before := Input.MOUSE_MODE_CAPTURED
var _dialogue_scene: Node = null


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# 游戏暂停（打开暂停菜单）时同步暂停对话，避免点击菜单时推进对话
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_export_overrides()
	# 应用“设置 > 对话 > 文字速度”
	var sm := get_node_or_null(^"/root/SettingsManager")
	if sm and sm.has_method("apply_dialogue_speed"):
		sm.apply_dialogue_speed()
	var dialogic := DialogicUtil.autoload()
	dialogic.timeline_started.connect(_on_timeline_started)
	dialogic.timeline_ended.connect(_release_player)
	get_tree().scene_changed.connect(_on_scene_changed)
	if dialogic.current_timeline != null:
		_on_timeline_started()


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		_release_player()


# ------------------------------------------------------------------ 冻结玩家

func _on_timeline_started() -> void:
	_dialogue_scene = get_tree().current_scene
	if not _frozen_players.is_empty():
		return
	for body in _find_players():
		if not body.get(&"frozen"):
			body.set(&"frozen", true)
			_frozen_players.append(body)
	_mouse_mode_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _release_player() -> void:
	for body in _frozen_players:
		if is_instance_valid(body):
			body.set(&"frozen", false)
	var had_players := not _frozen_players.is_empty()
	_frozen_players.clear()
	# 还在同一个场景里才把鼠标锁回去（回到主菜单时保持鼠标可见）
	if had_players and is_inside_tree() and get_tree().current_scene == _dialogue_scene \
			and _dialogue_scene != null and not get_tree().paused:
		Input.mouse_mode = _mouse_mode_before
	_dialogue_scene = null


## 玩家 = "player" 分组里的物体 + 场景中带 frozen 属性的 CharacterBody3D（real-controller 角色）
func _find_players() -> Array[Node]:
	var result: Array[Node] = []
	for n in get_tree().get_nodes_in_group(&"player"):
		if &"frozen" in n:
			result.append(n)
	var scene := get_tree().current_scene
	if scene:
		for n in scene.find_children("*", "CharacterBody3D", true, false):
			if &"frozen" in n and not result.has(n):
				result.append(n)
	return result


func _on_scene_changed() -> void:
	var dialogic := DialogicUtil.autoload()
	if dialogic.current_timeline != null and get_tree().current_scene != _dialogue_scene:
		_frozen_players.clear()
		dialogic.end_timeline(true)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# 对话中保持鼠标可见（防止点击时被角色脚本重新锁定）
	if not _frozen_players.is_empty() and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var paused := get_tree().paused
	if paused == _tree_was_paused:
		return
	_tree_was_paused = paused
	var dialogic := DialogicUtil.autoload()
	if paused:
		_dialogic_paused_before = dialogic.paused
		DialogueUtils.set_paused(true)
		set(&"visible", false)
	else:
		DialogueUtils.set_paused(_dialogic_paused_before)
		set(&"visible", true)


func _apply_export_overrides() -> void:
	set(&"layer", canvas_layer)
	var stage := get_node_or_null(^"StagePortraitLayer") as CanvasItem
	if stage:
		stage.visible = show_stage_portraits
