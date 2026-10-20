@tool
extends DialogicLayoutLayer
## 全局底部对话框：姓名、正文、继续提示及自动 / 跳过 / 历史；不显示头像。
## 字号、文字速度、不透明度读取 SettingsManager（设置 > 语言与辅助 > 对话）。

## 对话字体覆盖。留空 = 使用项目主题字体（与菜单 / 设置一致，推荐）
@export_file("*.ttf", "*.tres") var dialogue_font: String = ""
## 设置里“小 / 中 / 大”对应的字号（运行时吸附到 UIType.GRID_PX 的整数倍）
@export var font_sizes: PackedInt32Array = [24, 36, 48]
## 名牌字号
@export var name_font_size: int = 36
## 角落按钮字号
@export var button_font_size: int = 24
## Full-screen system readout; only enabled by opening_ui.tscn.
@export var system_boot: bool = false

const LightUI = preload("res://ui/theme/light/light_ui.gd")
const SETTINGS_SECTION := "accessibility"
const NEXT_GOLD: Texture2D = preload("res://ui/theme/glass/next_circle_gold.png")

@onready var _box: Control = %Box
@onready var _panel: PanelContainer = %Panel
@onready var _text: RichTextLabel = %DialogicNode_DialogText
@onready var _name: Label = %DialogicNode_NameLabel
@onready var _name_plate: Control = %NamePlate
@onready var _next_indicator: Control = %NextIndicator
@onready var _auto_button: Button = %AutoButton
@onready var _skip_button: Button = %SkipButton
@onready var _history_button: Button = %HistoryButton

var _skip_confirming := false
var _next_hidden_msec := -100000


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	LightUI.apply(self)
	LightUI.frost(_panel, true)
	LightUI.frost(_name_plate)
	_next_indicator.modulate = Color(0.32, 0.47, 0.42, 1)
	_auto_button.toggled.connect(_on_auto_toggled)
	_skip_button.pressed.connect(_request_skip)
	_history_button.pressed.connect(_open_history)
	var dialogic := DialogicUtil.autoload()
	dialogic.Inputs.auto_advance.toggled.connect(_sync_auto_button)
	_next_indicator.visibility_changed.connect(func():
		if not _next_indicator.visible:
			_next_hidden_msec = Time.get_ticks_msec())
	# “跳过”只跳到下一个选项：出现选项时关闭快速跳过
	dialogic.Choices.question_shown.connect(func(_info): dialogic.Inputs.auto_skip.enabled = false)
	if has_node("/root/SettingsManager"):
		get_node("/root/SettingsManager").setting_changed.connect(_on_setting_changed)
		get_node("/root/SettingsManager").bindings_changed.connect(_update_button_texts)
	_sync_auto_button(dialogic.Inputs.auto_advance.is_enabled())
	_update_button_texts()
	_apply_export_overrides()
	if system_boot:
		_configure_system_boot()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and not Engine.is_editor_hint():
		_update_button_texts()
		var dialogic := DialogicUtil.autoload()
		dialogic.Text.update_name_label(dialogic.Text.get_current_speaker(), true)


func _apply_export_overrides() -> void:
	if not is_node_ready():
		return
	var font := UIType.font_or_null(dialogue_font)
	var size := _setting_font_size()
	for key in [&"normal_font_size", &"bold_font_size", &"italics_font_size", &"bold_italics_font_size", &"mono_font_size"]:
		_text.add_theme_font_size_override(key, size)
	for key in [&"normal_font", &"bold_font", &"italics_font", &"bold_italics_font", &"mono_font"]:
		UIType.apply_font(_text, key, font)
	# 行距取 2 个字体像素，让每一行都落在像素网格上
	_text.add_theme_constant_override(&"line_separation", UIType.pixel(size) * 2)
	UIType.apply_font(_name, &"font", font)
	_name.add_theme_font_size_override(&"font_size", UIType.snap(name_font_size))
	for b in [_auto_button, _skip_button, _history_button]:
		UIType.apply_font(b, &"font", font)
		b.add_theme_font_size_override(&"font_size", UIType.snap(button_font_size))
	_apply_opacity()


# ------------------------------------------------------------------ 设置联动

func _settings() -> Node:
	return get_node_or_null("/root/SettingsManager")


func _setting_font_size() -> int:
	var idx := 1
	if _settings() and not Engine.is_editor_hint():
		idx = int(_settings().get_value(SETTINGS_SECTION, "dialogue_font_size"))
	return UIType.snap(font_sizes[clampi(idx, 0, font_sizes.size() - 1)])


func _apply_opacity() -> void:
	var opacity := 90.0
	if _settings() and not Engine.is_editor_hint():
		opacity = float(_settings().get_value(SETTINGS_SECTION, "dialogue_box_opacity"))
	_panel.self_modulate.a = clampf(opacity / 100.0, 0.0, 1.0)
	var backdrop := _panel.get_node_or_null("LightBackdrop/Surface") as CanvasItem
	if backdrop:
		backdrop.self_modulate.a = _panel.self_modulate.a


func _on_setting_changed(section: String, key: String, _value: Variant) -> void:
	if section == SETTINGS_SECTION and key.begins_with("dialogue_"):
		_apply_export_overrides()


# ------------------------------------------------------------------ 角落按钮

func _update_button_texts() -> void:
	# 按钮上不再显示快捷键字母（快捷键本身仍然有效）
	_auto_button.text = tr("DLG_AUTO")
	_skip_button.text = tr("DLG_SKIP")
	_history_button.text = tr("DLG_HISTORY")


func _hotkey_text(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var code: Key = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
			if ev.physical_keycode != KEY_NONE and DisplayServer.get_name() != "headless":
				code = DisplayServer.keyboard_get_keycode_from_physical(ev.physical_keycode)
			return "[%s]" % OS.get_keycode_string(code)
	return ""


func _on_auto_toggled(on: bool) -> void:
	var inputs = DialogicUtil.autoload().Inputs
	if inputs.auto_advance.enabled_forced != on:
		inputs.auto_advance.enabled_forced = on


func _sync_auto_button(enabled: bool) -> void:
	_auto_button.set_pressed_no_signal(enabled)


func _open_history() -> void:
	DialogicUtil.autoload().History.open_history()


func _request_skip() -> void:
	if _skip_confirming:
		return
	_skip_confirming = true
	var dialogic := DialogicUtil.autoload()
	var timeline: DialogicTimeline = dialogic.current_timeline
	DialogueUtils.push_pause(&"skip_confirm")
	var ok := true
	var popup_script: Script = load("res://ui/common/confirm_popup.gd")
	if popup_script:
		ok = await popup_script.ask(self, tr("DLG_SKIP_CONFIRM"), "DLG_SKIP")
	DialogueUtils.pop_pause(&"skip_confirm")
	_skip_confirming = false
	if ok and timeline != null and dialogic.current_timeline == timeline:
		# 快速跳过所有文本，直到下一个选项或对话结束（遇到选项会自动停下）
		dialogic.Inputs.auto_skip.enabled = true


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not _box.is_visible_in_tree():
		return
	var dialogic := DialogicUtil.autoload()
	if dialogic.paused or get_tree().paused:
		return
	if event.is_action_pressed(&"dialogic_default_action") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not (get_viewport().gui_get_hovered_control() is Button)):
		_pulse_next_gold()
	# 正在输入文字（如对话里的“输入名字”）时，Q / Tab / H 是要打进输入框的字母
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if event.is_action_pressed(&"dialogue_auto"):
		get_viewport().set_input_as_handled()
		_auto_button.button_pressed = not _auto_button.button_pressed
	elif event.is_action_pressed(&"dialogue_skip"):
		get_viewport().set_input_as_handled()
		_request_skip()
	elif event.is_action_pressed(&"dialogue_history"):
		get_viewport().set_input_as_handled()
		_open_history()


# ------------------------------------------------------------------ 点击推进反馈

## 继续圆钮平时是白色；玩家主动点击 / 按键推进对话时，在圆钮位置闪一下金色并扩散淡出
func _pulse_next_gold() -> void:
	if not is_instance_valid(_next_indicator):
		return
	# Dialogic 可能在本帧更早处理了同一次按键并已把圆钮隐藏，所以放宽到“刚刚还显示着”
	if not _next_indicator.is_visible_in_tree() and Time.get_ticks_msec() - _next_hidden_msec > 120:
		return
	var tr_ := _next_indicator.get_node_or_null("Texture") as TextureRect
	var src_rect := Rect2(_next_indicator.global_position, Vector2.ZERO)
	if tr_:
		src_rect = tr_.get_global_rect()
	var pulse := TextureRect.new()
	pulse.texture = NEXT_GOLD
	pulse.ignore_texture_size = true
	pulse.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pulse.top_level = true
	add_child(pulse)
	pulse.global_position = src_rect.position
	pulse.size = src_rect.size
	pulse.pivot_offset = src_rect.size * 0.5
	pulse.scale = _box.get_global_transform().get_scale()
	var tw := pulse.create_tween().set_parallel(true)
	tw.tween_property(pulse, "scale", pulse.scale * 1.35, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(pulse, "modulate:a", 0.0, 0.4).from(1.0)
	tw.chain().tween_callback(pulse.queue_free)


## Reuse the same text renderer, controls and history without the bottom dialogue panel.
func _configure_system_boot() -> void:
	_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.hide()
	_name_plate.hide()
	var column := VBoxContainer.new()
	column.name = "SystemTextCenter"
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.anchor_left = 0.1
	column.anchor_right = 0.9
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(column)
	_text.reparent(column)
	_text.fit_content = true
	_text.scroll_active = false
	_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_text.add_theme_color_override(&"default_color", Color(0.91, 0.95, 0.93))
	for button in [_auto_button, _skip_button, _history_button]:
		for color in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]:
			button.add_theme_color_override(color, Color(0.91, 0.95, 0.93))
	var buttons: Control = _auto_button.get_parent()
	buttons.offset_right = -48.0
	buttons.offset_left = -640.0
	buttons.offset_top = -96.0
	buttons.offset_bottom = -48.0
	_next_indicator.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_next_indicator.offset_left = 32.0
	_next_indicator.offset_right = 33.0
	_next_indicator.offset_top = -150.0
	_next_indicator.offset_bottom = -149.0
	_next_indicator.modulate = Color.WHITE
