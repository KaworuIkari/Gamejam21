@tool
extends DialogicLayoutLayer
## 底部玻璃对话框：头像 + 头像上方名牌 + 正文 + 白色继续圆钮（点击推进时闪金色）+ 右下角按钮（自动 / 跳过 / 历史）
## 字号、文字速度、不透明度读取 SettingsManager（设置 > 语言与辅助 > 对话）。

## 对话字体覆盖。留空 = 使用项目主题字体（与菜单 / 设置一致，推荐）
@export_file("*.ttf", "*.tres") var dialogue_font: String = ""
## 设置里“小 / 中 / 大”对应的字号（运行时吸附到 UIType.GRID_PX 的整数倍）
@export var font_sizes: PackedInt32Array = [24, 36, 48]
## 名牌字号
@export var name_font_size: int = 36
## 角落按钮字号
@export var button_font_size: int = 24
## 头像是像素画时关掉（最近邻采样）；3D 渲染图 / 手绘图保持开启（线性采样，缩小更平滑）
@export var portrait_smooth_filter: bool = true

const SETTINGS_SECTION := "accessibility"
const NEXT_GOLD: Texture2D = preload("res://ui/theme/glass/next_circle_gold.png")

@onready var _box: Control = %Box
@onready var _panel: PanelContainer = %Panel
@onready var _portrait_frame: Control = %PortraitFrame
@onready var _portrait_clip: Control = %PortraitClip
@onready var _portrait_container: Control = %DialogicNode_PortraitContainer
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
	_auto_button.toggled.connect(_on_auto_toggled)
	_skip_button.pressed.connect(_request_skip)
	_history_button.pressed.connect(_open_history)
	var dialogic := DialogicUtil.autoload()
	dialogic.Inputs.auto_advance.toggled.connect(_sync_auto_button)
	dialogic.Text.speaker_updated.connect(_on_speaker_updated)
	_portrait_clip.resized.connect(_refresh_portrait_layout)
	_text.resized.connect(_place_name_plate)
	_portrait_frame.visibility_changed.connect(_place_name_plate)
	_next_indicator.visibility_changed.connect(func():
		if not _next_indicator.visible:
			_next_hidden_msec = Time.get_ticks_msec())
	_place_name_plate.call_deferred()
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
	_portrait_frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if portrait_smooth_filter else CanvasItem.TEXTURE_FILTER_NEAREST
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


func _on_setting_changed(section: String, key: String, _value: Variant) -> void:
	if section == SETTINGS_SECTION and key.begins_with("dialogue_"):
		_apply_export_overrides()


# ------------------------------------------------------------------ 头像 / 名牌

func _on_speaker_updated(character: DialogicCharacter) -> void:
	var has_portrait := character != null and not character.portraits.is_empty()
	_portrait_frame.visible = has_portrait
	_refresh_portrait_layout.call_deferred()
	_place_name_plate.call_deferred()


## 名牌骑在对话框上边缘，左边与头像对齐（没有头像时与正文对齐）
func _place_name_plate() -> void:
	if not is_instance_valid(_name_plate) or not is_instance_valid(_text) or not is_instance_valid(_box):
		return
	var s := _box.get_global_transform().get_scale().x
	if is_zero_approx(s):
		return
	var anchor_ctrl: Control = _portrait_frame if _portrait_frame.is_visible_in_tree() else _text
	var x := (anchor_ctrl.global_position.x - _box.global_position.x) / s
	_name_plate.offset_left = x
	_name_plate.offset_right = x + 1.0


## 头像容器在布局完成前尺寸为 0，会把头像定位到错误位置；尺寸变化后重新对齐
func _refresh_portrait_layout() -> void:
	if not is_instance_valid(_portrait_container) or _portrait_clip.size == Vector2.ZERO:
		return
	_portrait_container.update_transform_from_properties()
	_portrait_container.container_resized_during_game()


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
	DialogueUtils.push_pause(&"skip_confirm")
	var ok := true
	var popup_script: Script = load("res://ui/common/confirm_popup.gd")
	if popup_script:
		ok = await popup_script.ask(self, tr("DLG_SKIP_CONFIRM"), "DLG_SKIP")
	DialogueUtils.pop_pause(&"skip_confirm")
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
