@tool
extends DialogicLayoutLayer
## 底部像素对话框：头像 + 名牌 + 正文 + 继续箭头 + 角落按钮（自动 / 跳过 / 历史）
## 字号、文字速度、不透明度读取 SettingsManager（设置 > 语言与辅助 > 对话）。

## 对话字体（ChillBitmap 7px 的像素网格是 8px，字号请用 8 的倍数）
@export_file("*.ttf", "*.tres") var dialogue_font: String = "res://fonts/ChillBitmap7x.ttf"
## 设置里“小 / 中 / 大”对应的字号
@export var font_sizes: PackedInt32Array = [24, 32, 40]
## 名牌字号
@export var name_font_size: int = 32
## 角落按钮字号
@export var button_font_size: int = 24
## 头像是像素画时关掉（最近邻采样）；3D 渲染图 / 手绘图保持开启（线性采样，缩小更平滑）
@export var portrait_smooth_filter: bool = true

const SETTINGS_SECTION := "accessibility"

@onready var _box: Control = %Box
@onready var _panel: PanelContainer = %Panel
@onready var _portrait_frame: Control = %PortraitFrame
@onready var _portrait_clip: Control = %PortraitClip
@onready var _portrait_container: Control = %DialogicNode_PortraitContainer
@onready var _text: RichTextLabel = %DialogicNode_DialogText
@onready var _name: Label = %DialogicNode_NameLabel
@onready var _auto_button: Button = %AutoButton
@onready var _skip_button: Button = %SkipButton
@onready var _history_button: Button = %HistoryButton

var _skip_confirming := false


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_auto_button.toggled.connect(_on_auto_toggled)
	_skip_button.pressed.connect(_request_skip)
	_history_button.pressed.connect(_open_history)
	var dialogic := DialogicUtil.autoload()
	dialogic.Inputs.auto_advance.toggled.connect(_sync_auto_button)
	dialogic.Text.speaker_updated.connect(_on_speaker_updated)
	_portrait_clip.resized.connect(_refresh_portrait_layout)
	# “跳过”只跳到下一个选项：出现选项时关闭快速跳过
	dialogic.Choices.question_shown.connect(func(_info): dialogic.Inputs.auto_skip.enabled = false)
	if has_node("/root/SettingsManager"):
		get_node("/root/SettingsManager").setting_changed.connect(_on_setting_changed)
		get_node("/root/SettingsManager").bindings_changed.connect(_update_button_texts)
	_sync_auto_button(dialogic.Inputs.auto_advance.is_enabled())
	_update_button_texts()
	_apply_export_overrides()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and not Engine.is_editor_hint():
		_update_button_texts()


func _apply_export_overrides() -> void:
	if not is_node_ready():
		return
	var font: Font = load(dialogue_font) if ResourceLoader.exists(dialogue_font) else null
	var size := _setting_font_size()
	for key in [&"normal_font_size", &"bold_font_size", &"italics_font_size", &"bold_italics_font_size", &"mono_font_size"]:
		_text.add_theme_font_size_override(key, size)
	if font:
		for key in [&"normal_font", &"bold_font", &"italics_font", &"bold_italics_font", &"mono_font"]:
			_text.add_theme_font_override(key, font)
		_name.add_theme_font_override(&"font", font)
		for b in [_auto_button, _skip_button, _history_button]:
			b.add_theme_font_override(&"font", font)
	_name.add_theme_font_size_override(&"font_size", name_font_size)
	for b in [_auto_button, _skip_button, _history_button]:
		b.add_theme_font_size_override(&"font_size", button_font_size)
	_portrait_frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if portrait_smooth_filter else CanvasItem.TEXTURE_FILTER_NEAREST
	_apply_opacity()


# ------------------------------------------------------------------ 设置联动

func _settings() -> Node:
	return get_node_or_null("/root/SettingsManager")


func _setting_font_size() -> int:
	var idx := 1
	if _settings() and not Engine.is_editor_hint():
		idx = int(_settings().get_value(SETTINGS_SECTION, "dialogue_font_size"))
	return font_sizes[clampi(idx, 0, font_sizes.size() - 1)]


func _apply_opacity() -> void:
	var opacity := 90.0
	if _settings() and not Engine.is_editor_hint():
		opacity = float(_settings().get_value(SETTINGS_SECTION, "dialogue_box_opacity"))
	_panel.self_modulate.a = clampf(opacity / 100.0, 0.0, 1.0)


func _on_setting_changed(section: String, key: String, _value: Variant) -> void:
	if section == SETTINGS_SECTION and key.begins_with("dialogue_"):
		_apply_export_overrides()


# ------------------------------------------------------------------ 头像 / 名牌

func _on_speaker_updated(character: DialogicCharacter) -> void:
	var has_portrait := character != null and not character.portraits.is_empty()
	_portrait_frame.visible = has_portrait
	_refresh_portrait_layout.call_deferred()


## 头像容器在布局完成前尺寸为 0，会把头像定位到错误位置；尺寸变化后重新对齐
func _refresh_portrait_layout() -> void:
	if not is_instance_valid(_portrait_container) or _portrait_clip.size == Vector2.ZERO:
		return
	_portrait_container.update_transform_from_properties()
	_portrait_container.container_resized_during_game()


# ------------------------------------------------------------------ 角落按钮

func _update_button_texts() -> void:
	_auto_button.text = "%s %s" % [tr("DLG_AUTO"), _hotkey_text(&"dialogue_auto")]
	_skip_button.text = "%s %s" % [tr("DLG_SKIP"), _hotkey_text(&"dialogue_skip")]
	_history_button.text = "%s %s" % [tr("DLG_HISTORY"), _hotkey_text(&"dialogue_history")]


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
	DialogueUtils.set_paused(true)
	var ok := true
	var popup_script: Script = load("res://ui/common/confirm_popup.gd")
	if popup_script:
		ok = await popup_script.ask(self, tr("DLG_SKIP_CONFIRM"), "DLG_SKIP")
	DialogueUtils.set_paused(false)
	_skip_confirming = false
	if ok:
		# 快速跳过所有文本，直到下一个选项或对话结束（遇到选项会自动停下）
		dialogic.Inputs.auto_skip.enabled = true


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not _box.is_visible_in_tree():
		return
	var dialogic := DialogicUtil.autoload()
	if dialogic.paused or get_tree().paused:
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
