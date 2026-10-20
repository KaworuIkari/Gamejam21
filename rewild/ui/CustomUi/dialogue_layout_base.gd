@tool
extends DialogicLayoutBase
## 自定义对话布局的根节点（custom_ui_.tscn）。
## - 提供全局字体/字号/颜色给 Dialogic 自带的图层（如词汇表）读取
## - 隐藏角色图像，保留 Dialogic 的 join / leave / update 指令兼容性
## - 对话期间冻结玩家（不能移动/转视角）并显示鼠标，结束后恢复
## - 切换场景（如返回主菜单）时自动结束对话

@export var canvas_layer: int = 10

@export_subgroup("Global")
@export var global_bg_color: Color = Color(0.95, 0.97, 0.93, 0.9)
@export var global_font_color: Color = Color(0.22, 0.29, 0.28, 1)
## Dialogic 自带图层（如词汇表）读取的全局字体。留空 = 使用项目主题字体（见 UIType）
@export_file("*.ttf", "*.tres") var global_font: String = ""
@export var global_font_size: int = UIType.MEDIUM


var _tree_was_paused := false

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
		DialogueUtils.clear_pauses()


# ------------------------------------------------------------------ 冻结玩家

func _on_timeline_started() -> void:
	_dialogue_scene = get_tree().current_scene
	# 新对话开始时清掉上一段对话可能残留的暂停原因（游戏暂停除外，由 _process 维护）
	var game_paused := DialogueUtils.is_pause_reason_active(&"game_paused")
	DialogueUtils.clear_pauses()
	if game_paused:
		DialogueUtils.push_pause(&"game_paused")
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
	if paused:
		DialogueUtils.push_pause(&"game_paused")
		set(&"visible", false)
	else:
		DialogueUtils.pop_pause(&"game_paused")
		set(&"visible", true)


## Dialogic 图层通过它读取 global_* 设置；字体留空时回落到项目主题字体，
## 保证自带图层和我们的图层用同一套字体
func get_global_setting(setting: StringName, default: Variant) -> Variant:
	if setting == &"font" and global_font.is_empty():
		return UIType.theme_font_path()
	if setting == &"font_size":
		return UIType.snap(global_font_size)
	return super(setting, default)


func _apply_export_overrides() -> void:
	set(&"layer", canvas_layer)
	var stage := get_node_or_null(^"StagePortraitLayer") as CanvasItem
	if stage:
		stage.hide()
