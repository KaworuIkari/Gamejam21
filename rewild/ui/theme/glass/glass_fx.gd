extends Node
## 玻璃模糊自动挂载（Autoload：GlassFx）
## 给所有使用玻璃主题贴图（res://ui/theme/glass/）的控件，在背后垫一个“模糊底”子节点：
##   - Panel / PanelContainer：强模糊 + 约 50% 深灰染色（glass_backdrop_panel_material.tres）
##   - Button / OptionButton / MenuButton：强模糊（glass_backdrop_material.tres，按钮贴图自带颜色）
## 嵌套面板（面板里的卡片、标签页内容区）不再重复垫底，只保留半透明贴图。
## 着色器不能直接挂在会画文字的控件上，所以用子节点垫底。
## 想让某个控件不要模糊：给它设置 meta "no_glass" = true。

const PANEL_BACKDROP_MAT: Material = preload("res://ui/theme/glass/glass_backdrop_panel_material.tres")
const BUTTON_BACKDROP_MAT: Material = preload("res://ui/theme/glass/glass_backdrop_material.tres")
const GLASS_DIR := "res://ui/theme/glass/"
const BUTTON_CLASSES := ["Button", "OptionButton", "MenuButton"]
const BACKDROP_NAME := "GlassBackdrop"
const DEFAULT_RADIUS := 24.0
const TEXTURE_RADIUS := {"panel.png": 28.0, "tab_panel.png": 28.0, "nameplate.png": 28.0}


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	_scan(get_tree().root)


func _scan(n: Node) -> void:
	_on_node_added(n)
	for c in n.get_children():
		_scan(c)


func _on_node_added(n: Node) -> void:
	if n.has_meta(&"no_glass") or n.name == BACKDROP_NAME:
		return
	var cls := n.get_class()
	if cls in BUTTON_CLASSES:
		_decorate.call_deferred(n.get_instance_id(), &"normal", BUTTON_BACKDROP_MAT, false)
	elif cls == "Panel" or cls == "PanelContainer":
		_decorate.call_deferred(n.get_instance_id(), &"panel", PANEL_BACKDROP_MAT, true)

func _glass_texture_name(sb: StyleBox) -> String:
	if sb is StyleBoxTexture and sb.texture != null and sb.texture.resource_path.begins_with(GLASS_DIR):
		return sb.texture.resource_path.get_file()
	return ""


func _has_backdrop_ancestor(c: Control) -> bool:
	var p := c.get_parent()
	while p != null:
		if p.has_node(BACKDROP_NAME):
			return true
		p = p.get_parent()
	return false


func _decorate(id: int, style_name: StringName, mat: Material, follow_alpha: bool) -> void:
	var c := instance_from_id(id) as Control
	if c == null or not c.is_inside_tree() or c.has_node(BACKDROP_NAME) or c.use_parent_material:
		return
	var tex_name := _glass_texture_name(c.get_theme_stylebox(style_name))
	if tex_name == "":
		return
	if follow_alpha and _has_backdrop_ancestor(c):
		return
	var radius: float = TEXTURE_RADIUS.get(tex_name, DEFAULT_RADIUS)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.anti_aliasing = true
	var bd := Panel.new()
	bd.name = BACKDROP_NAME
	bd.show_behind_parent = true
	bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bd.focus_mode = Control.FOCUS_NONE
	bd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bd.add_theme_stylebox_override(&"panel", sb)
	bd.material = mat
	c.add_child(bd, false, Node.INTERNAL_MODE_FRONT)
	var fit := func():
		sb.set_corner_radius_all(int(minf(radius, c.size.y * 0.5)))
	fit.call()
	c.resized.connect(fit)
	if follow_alpha:
		# 面板的 self_modulate.a（如对话框“不透明度”设置）同样作用到模糊底
		c.draw.connect(func():
			if not is_equal_approx(bd.self_modulate.a, c.self_modulate.a):
				bd.self_modulate.a = c.self_modulate.a)
		bd.self_modulate.a = c.self_modulate.a
