@tool
extends DialogicLayoutLayer
## 文字输入层（例如让玩家输入名字）。确认后焦点自动交还对话。

@export_file("*.ttf", "*.tres") var input_font: String = "res://fonts/ChillBitmap7x.ttf"
@export var input_font_size: int = 32

@onready var _node: Control = %DialogicNode_TextInput
@onready var _field: LineEdit = %InputField
@onready var _panel: Control = %TextInputPanel


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_apply_export_overrides()
	_node.visibility_changed.connect(func():
		if _node.visible:
			_field.grab_focus.call_deferred())


func _apply_export_overrides() -> void:
	if not is_node_ready():
		return
	var font: Font = load(input_font) if ResourceLoader.exists(input_font) else null
	var t := Theme.new()
	t.default_font_size = input_font_size
	if font:
		t.default_font = font
	_panel.theme = t
