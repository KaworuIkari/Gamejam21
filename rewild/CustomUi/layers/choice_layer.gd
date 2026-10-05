@tool
extends DialogicLayoutLayer
## 选项层：在对话框上方竖排显示像素按钮（复用全局像素主题），支持键鼠 / 手柄。

@export_file("*.ttf", "*.tres") var choice_font: String = "res://fonts/ChillBitmap7x.ttf"
@export var choice_font_size: int = 32
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
	var font: Font = load(choice_font) if ResourceLoader.exists(choice_font) else null
	for b in _choices.get_children():
		if b is Button:
			b.custom_minimum_size = Vector2(choice_min_width, 64)
			b.add_theme_font_size_override(&"font_size", choice_font_size)
			if font:
				b.add_theme_font_override(&"font", font)
