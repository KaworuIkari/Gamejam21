@tool
extends DialogicLayoutLayer
## 文字输入层（例如让玩家输入名字）。确认后焦点自动交还对话。

## 输入框字体覆盖。留空 = 使用项目主题字体
@export_file("*.ttf", "*.tres") var input_font: String = ""
## 输入框字号（运行时吸附到 UIType.GRID_PX 的整数倍）
@export var input_font_size: int = 36

const LightUI = preload("res://ui/theme/light/light_ui.gd")

@onready var _node: Control = %DialogicNode_TextInput
@onready var _field: LineEdit = %InputField
@onready var _panel: Control = %TextInputPanel


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	LightUI.apply(self)
	LightUI.frost(_panel)
	_apply_export_overrides()
	_node.visibility_changed.connect(func():
		if _node.visible:
			_field.grab_focus.call_deferred())


func _apply_export_overrides() -> void:
	if not is_node_ready():
		return
	var font := UIType.font_or_null(input_font)
	var t: Theme = LightUI.bright_theme().duplicate()
	t.default_font_size = UIType.snap(input_font_size)
	if font:
		t.default_font = font
	t.set_color(&"font_color", &"LineEdit", LightUI.INK)
	t.set_color(&"caret_color", &"LineEdit", LightUI.INK)
	t.set_color(&"font_placeholder_color", &"LineEdit", LightUI.MUTED)
	t.set_stylebox(&"normal", &"LineEdit", t.get_stylebox(&"normal", &"Button"))
	t.set_stylebox(&"focus", &"LineEdit", t.get_stylebox(&"focus", &"Button"))
	_panel.theme = t
