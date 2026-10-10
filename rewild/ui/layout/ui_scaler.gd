extends Node
## 只缩放“我们的 UI”（res://ui/ 与 res://ui/CustomUi/ 下的界面），不碰全局缩放。
##
## 为什么需要它：
##   UI 按 1920×1080 设计；项目基准分辨率由队友设为 1080×720（主场景用 SubViewport
##   做像素化，基准分辨率决定像素颗粒大小）。如果改全局 content_scale_factor 或改回
##   1920×1080，会让像素化变细。所以这里只把 UI 根节点按 1080 高度排版后再整体缩放。
##
## 规则：一个铺满全屏（四个锚点 0,0,1,1）的顶层 Control，只要它或它的祖先属于
## res://ui/ 或 res://ui/CustomUi/，就会被缩放。
## 注意：Godot 4.7 里从带 scale 的 Control 弹出的下拉菜单不会显示，
## 所以我们的 UI 不使用 OptionButton / PopupMenu（设置页用 OptionStepper 代替）。
## 由 SettingsManager 创建；“界面缩放”设置通过 user_scale 生效。

const DESIGN_HEIGHT := 1080.0
const UI_PREFIXES: Array[String] = ["res://ui/"]
const META := &"_ui_scaler_root"

static var _factor := 1.0

## 设置里的“界面缩放”（1.0 = 100%）
var user_scale := 1.0:
	set(value):
		user_scale = value
		_refresh_all()

var _roots: Array[Control] = []


## 当前 UI 缩放倍数（基准分辨率换算 × 界面缩放）
static func factor() -> float:
	return _factor


## UI 排版用的“设计尺寸”下的视口大小（代替 get_viewport().get_visible_rect().size）
static func virtual_viewport_size(viewport: Viewport) -> Vector2:
	return viewport.get_visible_rect().size / maxf(_factor, 0.01)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_update_factor()
	get_tree().node_added.connect(_on_node_added)
	get_tree().root.size_changed.connect(_refresh_all)
	# F5 直接启动时，主场景（主菜单）比本节点更早进入场景树，node_added 已经错过，
	# 所以启动时把已存在的界面补登记一遍。
	_scan_existing.call_deferred()


func _scan_existing() -> void:
	for n in get_tree().root.find_children("*", "Control", true, false):
		_try_register(n)


func _update_factor() -> void:
	var base_h := float(ProjectSettings.get_setting("display/window/size/viewport_height", DESIGN_HEIGHT))
	_factor = base_h / DESIGN_HEIGHT * user_scale


func _on_node_added(node: Node) -> void:
	if node is Control:
		_try_register.call_deferred(node)


func _try_register(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree() or not _is_ours(node):
		return
	var c := node as Control
	if c.get_parent() is Control or c.has_meta(META):
		return
	var full_rect := is_equal_approx(c.anchor_left, 0.0) and is_equal_approx(c.anchor_top, 0.0) \
			and is_equal_approx(c.anchor_right, 1.0) and is_equal_approx(c.anchor_bottom, 1.0)
	if not full_rect:
		return
	c.set_meta(META, true)
	_roots = _roots.filter(func(r): return is_instance_valid(r))
	_roots.append(c)
	_apply(c)


func _apply(c: Control) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 0.0
	c.anchor_bottom = 0.0
	c.pivot_offset = Vector2.ZERO
	c.position = Vector2.ZERO
	c.scale = Vector2(_factor, _factor)
	c.size = virtual_viewport_size(c.get_viewport())


func _refresh_all() -> void:
	_update_factor()
	if not is_inside_tree():
		return
	_roots = _roots.filter(func(c): return is_instance_valid(c))
	for c in _roots:
		if c.is_inside_tree():
			_apply(c)


func _is_ours(node: Node) -> bool:
	var n := node
	while n != null:
		if _path_is_ours(n.scene_file_path):
			return true
		var s: Script = n.get_script()
		if s != null and _path_is_ours(s.resource_path):
			return true
		n = n.get_parent()
	return false


func _path_is_ours(path: String) -> bool:
	for p in UI_PREFIXES:
		if path.begins_with(p):
			return true
	return false
