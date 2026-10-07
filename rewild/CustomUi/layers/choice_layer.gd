@tool
extends DialogicLayoutLayer
## 选项层：在对话框上方竖排显示像素按钮（复用全局像素主题），支持键鼠 / 手柄。

## 选项字体覆盖。留空 = 使用项目主题字体
@export_file("*.ttf", "*.tres") var choice_font: String = ""
## 选项字号（运行时吸附到 UIType.GRID_PX 的整数倍）
@export var choice_font_size: int = 36
@export var choice_min_width: int = 720

@onready var _choices: VBoxContainer = %Choices


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_apply_export_overrides()


func _apply_export_overrides() -> void:
	if not is_node_ready():
		return
	var font := UIType.font_or_null(choice_font)
	var size := UIType.snap(choice_font_size)
	for b in _choices.get_children():
		if b is Button:
			b.custom_minimum_size = Vector2(choice_min_width, 64)
			b.add_theme_font_size_override(&"font_size", size)
			UIType.apply_font(b, &"font", font)
