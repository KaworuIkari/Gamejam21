class_name KeyRebindButton
extends Button
## 单个按键绑定按钮：点击后等待下一次输入并写入 SettingsManager

@export var action: StringName
@export_enum("kbm", "joy") var kind: String = "kbm"

const AXIS_THRESHOLD := 0.6

var _listening := false


func _ready() -> void:
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # 文本由 _update_text 手动翻译
	custom_minimum_size.x = maxf(custom_minimum_size.x, 260)
	set_process_input(false)
	pressed.connect(_start_listening)
	SettingsManager.bindings_changed.connect(_update_text)
	_update_text()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_TRANSLATION_CHANGED:
			if is_node_ready():
				_update_text()
		NOTIFICATION_VISIBILITY_CHANGED, NOTIFICATION_FOCUS_EXIT:
			if _listening:
				_stop_listening()


func _update_text() -> void:
	if _listening:
		text = tr("BIND_WAITING")
	else:
		text = SettingsManager.event_to_text(SettingsManager.get_binding(action, kind))


func _start_listening() -> void:
	_listening = true
	_update_text()
	# 等一帧，避免把触发按钮本身的那次点击/确认键当成新绑定
	await get_tree().process_frame
	if _listening:
		set_process_input(true)


func _stop_listening() -> void:
	_listening = false
	set_process_input(false)
	_update_text()


func _input(event: InputEvent) -> void:
	if not _listening or event is InputEventMouseMotion:
		return
	get_viewport().set_input_as_handled()

	if not event.is_pressed() or event.is_echo():
		return
	# 取消
	if event is InputEventKey and (event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE):
		_stop_listening()
		return
	if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_BACK:
		_stop_listening()
		return
	if SettingsManager.event_kind(event) != kind:
		return
	if event is InputEventJoypadMotion and absf(event.axis_value) < AXIS_THRESHOLD:
		return

	var clean := SettingsManager._deserialize_event(SettingsManager._serialize_event(event))
	if clean:
		SettingsManager.rebind(action, kind, clean)
	_stop_listening()
