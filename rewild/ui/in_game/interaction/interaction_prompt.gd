extends CanvasLayer
## Reusable presentation only: the interaction owner supplies availability.
const LightUI = preload("res://ui/theme/light/light_ui.gd")

@onready var _root: Control = $Root
@onready var _panel: PanelContainer = $Root/Anchor/Panel
@onready var _before: Label = $Root/Anchor/Panel/Row/Before
@onready var _key: Label = $Root/Anchor/Panel/Row/Key/Label
@onready var _after: Label = $Root/Anchor/Panel/Row/After

var _available := false
var _action: StringName = &"interact"
var _message_key := "DLG_TALK_PROMPT"
var _device_kind := "kbm"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_viewport = get_tree().root
	LightUI.apply(_root)
	_panel.add_theme_stylebox_override(&"panel", LightUI.surface(Color(1, 0.99, 0.95, 0.12), Color(1, 1, 0.97, 0.65), 20, 24, 14))
	LightUI.frost(_panel)
	$Root/Anchor/Panel/Row/Key.add_theme_stylebox_override(&"panel", LightUI.surface(Color(1, 0.88, 0.59, 0.38), Color(0.94, 0.77, 0.39, 0.65), 10, 12, 4))
	var settings := get_node_or_null("/root/SettingsManager")
	if settings:
		settings.bindings_changed.connect(_refresh_text)
	_refresh_text()
	_root.hide()


func configure(action: StringName, message_key: String) -> void:
	_action = action
	_message_key = message_key
	if is_node_ready():
		_refresh_text()


func set_available(available: bool) -> void:
	_available = available


func _process(_delta: float) -> void:
	var dialogic := get_node_or_null("/root/Dialogic")
	_root.visible = _available and not get_tree().paused and (dialogic == null or dialogic.current_timeline == null)


func _input(event: InputEvent) -> void:
	var kind := _device_kind
	if event is InputEventJoypadButton and event.pressed:
		kind = "joy"
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.4:
		kind = "joy"
	elif (event is InputEventKey or event is InputEventMouseButton) and event.pressed:
		kind = "kbm"
	if kind != _device_kind:
		_device_kind = kind
		_refresh_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	var parts := tr(_message_key).split("%s", true, 1)
	_before.text = parts[0].strip_edges()
	_after.text = parts[1].strip_edges() if parts.size() > 1 else ""
	_before.visible = not _before.text.is_empty()
	_after.visible = not _after.text.is_empty()
	var settings := get_node_or_null("/root/SettingsManager")
	var binding: InputEvent = null
	if settings:
		binding = settings.get_binding(_action, _device_kind)
	_key.text = settings.event_to_text(binding) if settings else "F"
