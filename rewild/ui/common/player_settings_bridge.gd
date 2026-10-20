extends Node
## 把“设置 > 操作 / 画面”里的玩家相关设置应用到队友的角色控制器上，
## 不修改 addons/real-controller/character.gd 本身。
##
## 识别方式：场景里带 frozen + mouse_sensitivity 属性的 CharacterBody3D（real-controller 角色）。
## - 鼠标灵敏度 / 手柄灵敏度：以角色在场景里设好的数值为基准，乘以设置里的倍率
## - 视野 FOV：直接写到角色的 camera_3d 上
## 由 SettingsManager 创建并在设置变化时调用 refresh()。
## LIRA 的反转 Y 轴通过 settings_invert_y 接入；震动由 SettingsManager 管理。

const META_BASE_MOUSE := &"_settings_base_mouse_sensitivity"
const META_BASE_PAD := &"_settings_base_controller_sensitivity"

var _players: Array[Node] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)
	_scan_existing.call_deferred()


func _scan_existing() -> void:
	for n in get_tree().root.find_children("*", "CharacterBody3D", true, false):
		_try_register(n)


func _on_node_added(node: Node) -> void:
	if node is CharacterBody3D:
		_try_register.call_deferred(node)


func _try_register(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree() or _players.has(node):
		return
	if not (&"frozen" in node and &"mouse_sensitivity" in node):
		return
	node.set_meta(META_BASE_MOUSE, node.get(&"mouse_sensitivity"))
	if &"controller_sensitivity" in node:
		node.set_meta(META_BASE_PAD, node.get(&"controller_sensitivity"))
	_players.append(node)
	_apply(node)


## 设置变化时由 SettingsManager 调用
func refresh() -> void:
	_players = _players.filter(func(p): return is_instance_valid(p))
	for p in _players:
		_apply(p)


func _apply(player: Node) -> void:
	var sm := get_parent()
	if sm == null or not sm.has_method("get_value"):
		return
	var mouse_mult := float(sm.get_value("controls", "mouse_sensitivity"))
	var pad_mult := float(sm.get_value("controls", "gamepad_sensitivity"))
	player.set(&"mouse_sensitivity", float(player.get_meta(META_BASE_MOUSE)) * mouse_mult)
	if player.has_meta(META_BASE_PAD):
		player.set(&"controller_sensitivity", float(player.get_meta(META_BASE_PAD)) * pad_mult)
	if &"settings_invert_y" in player:
		player.set(&"settings_invert_y", bool(sm.get_value("controls", "invert_y")))
	var cam = player.get(&"camera_3d") if &"camera_3d" in player else null
	if cam is Camera3D:
		cam.fov = float(sm.get_value("video", "fov"))
