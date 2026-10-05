extends Control
## 设置菜单：4 个分页，所有改动即时生效，关闭时写盘。
## 用法：settings_menu.open()；关闭时发出 closed。

signal closed

const UILayoutRules = preload("res://ui/layout/ui_layout.gd")
const ResponsiveRow = preload("res://ui/layout/responsive_settings_row.gd")

const SECTIONS: Array[String] = ["audio", "video", "controls", "accessibility"]
const TAB_TITLES: Array[String] = ["TAB_AUDIO", "TAB_VIDEO", "TAB_CONTROLS", "TAB_ACCESSIBILITY"]

const LABEL_WIDTH := 460.0
const CONTROL_WIDTH := 620.0
const ROW_HEIGHT := 64.0
const BODY_FONT_SIZE := 24
const CONTROL_FONT_SIZE := 22
const SECTION_FONT_SIZE := 34

@onready var _tabs: TabContainer = %Tabs
@onready var _reset_button: Button = %ResetButton
@onready var _back_button: Button = %BackButton
@onready var _margin: MarginContainer = $Margin
@onready var _panel_rows: VBoxContainer = $Margin/Panel/VBox
@onready var _title: Label = $Margin/Panel/VBox/Header/Title
@onready var _tab_hint: Label = $Margin/Panel/VBox/Header/TabHint
@onready var _back_hint: Label = $Margin/Panel/VBox/Footer/BackHint
var _refreshers: Array[Callable] = []
var _settings_rows: Array[ResponsiveSettingsRow] = []
var _section_gaps: Array[Control] = []


func _ready() -> void:
	for i in TAB_TITLES.size():
		_tabs.set_tab_title(i, TAB_TITLES[i])
	_build_audio(%AudioRows)
	_build_video(%VideoRows)
	_build_controls(%ControlsRows)
	_build_accessibility(%AccessibilityRows)

	_reset_button.pressed.connect(_on_reset_pressed)
	_back_button.pressed.connect(close)
	_tabs.tab_changed.connect(_on_tab_changed)
	SettingsManager.setting_changed.connect(func(_s, _k, _v): _refresh_all())
	resized.connect(_update_responsive_layout)
	_on_tab_changed(_tabs.current_tab)
	_refresh_all()
	_update_responsive_layout()


func open(tab: int = -1) -> void:
	if tab >= 0:
		_tabs.current_tab = tab
	show()
	_refresh_all()
	_focus_current_tab.call_deferred()


func close() -> void:
	SettingsManager.save()
	hide()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _focus_current_tab() -> void:
	var page := _tabs.get_current_tab_control()
	for c in page.find_children("*", "Control", true, false):
		var ctrl := c as Control
		if ctrl.focus_mode == Control.FOCUS_ALL and ctrl.is_visible_in_tree() \
				and not (ctrl is BaseButton and ctrl.disabled):
			ctrl.grab_focus()
			return
	_back_button.grab_focus()


func _on_tab_changed(tab: int) -> void:
	_reset_button.visible = true


func _on_reset_pressed() -> void:
	var section := SECTIONS[_tabs.current_tab]
	SettingsManager.reset_section(section)
	if section == "controls":
		SettingsManager.reset_bindings()
	_refresh_all()


func _refresh_all() -> void:
	for r in _refreshers:
		r.call()


# ------------------------------------------------------------------ 分页内容

func _build_audio(p: Control) -> void:
	_header(p, "HEADER_VOLUME")
	_slider(p, "OPT_MASTER_VOLUME", "audio", "master_volume", 0, 100, 1, "%d%%")
	_slider(p, "OPT_MUSIC_VOLUME", "audio", "music_volume", 0, 100, 1, "%d%%")
	_slider(p, "OPT_SFX_VOLUME", "audio", "sfx_volume", 0, 100, 1, "%d%%")
	_slider(p, "OPT_AMBIENT_VOLUME", "audio", "ambient_volume", 0, 100, 1, "%d%%")


func _build_video(p: Control) -> void:
	_header(p, "HEADER_DISPLAY")
	var window_mode := _option(p, "OPT_WINDOW_MODE", "video", "window_mode",
		["WINDOW_WINDOWED", "WINDOW_BORDERLESS", "WINDOW_EXCLUSIVE"])
	var res_items: Array = SettingsManager.RESOLUTIONS.map(func(r: Vector2i): return "%d × %d" % [r.x, r.y])
	var res := _option(p, "OPT_RESOLUTION", "video", "resolution", res_items)
	_set_desktop_only(window_mode)
	_set_desktop_only(res)
	_refreshers.append(func():
		res.disabled = SettingsManager.get_value("video", "window_mode") != SettingsManager.WindowMode.WINDOWED
		res.focus_mode = Control.FOCUS_NONE if res.disabled else Control.FOCUS_ALL)
	_option(p, "OPT_VSYNC", "video", "vsync", ["VSYNC_OFF", "VSYNC_ON", "VSYNC_ADAPTIVE"])
	var fps_items: Array = SettingsManager.FPS_LIMITS.map(func(f: int): return "FPS_UNLIMITED" if f == 0 else str(f))
	_option(p, "OPT_MAX_FPS", "video", "max_fps", fps_items)

	_header(p, "HEADER_GRAPHICS")
	_option(p, "OPT_QUALITY", "video", "quality", ["QUALITY_LOW", "QUALITY_MEDIUM", "QUALITY_HIGH", "QUALITY_ULTRA"])
	_slider(p, "OPT_RENDER_SCALE", "video", "render_scale", 50, 100, 5, "%d%%")
	_option(p, "OPT_SCALER", "video", "scaler", ["SCALER_BILINEAR", "SCALER_FSR1", "SCALER_FSR2"])
	_slider(p, "OPT_FOV", "video", "fov", 60, 110, 1, "%d°")


func _build_controls(p: Control) -> void:
	_header(p, "HEADER_SENSITIVITY")
	_slider(p, "OPT_MOUSE_SENS", "controls", "mouse_sensitivity", 0.1, 3.0, 0.05, "%.2f")
	_slider(p, "OPT_PAD_SENS", "controls", "gamepad_sensitivity", 0.1, 3.0, 0.05, "%.2f")
	_toggle(p, "OPT_INVERT_Y", "controls", "invert_y")
	_toggle(p, "OPT_VIBRATION", "controls", "vibration")

	_header(p, "HEADER_KEYBINDS")
	var head := _row(p, "BIND_COL_ACTION")
	head.label.theme_type_variation = &"HintLabel"
	for key in ["BIND_COL_KBM", "BIND_COL_PAD"]:
		var l := Label.new()
		l.text = key
		l.theme_type_variation = &"HintLabel"
		l.add_theme_font_size_override(&"font_size", CONTROL_FONT_SIZE)
		l.custom_minimum_size.x = 260
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.controls.add_child(l)
	for action in SettingsManager.REBINDABLE_ACTIONS:
		var row := _row(p, "ACTION_" + String(action).to_upper())
		for kind in ["kbm", "joy"]:
			var b := KeyRebindButton.new()
			b.action = action
			b.kind = kind
			b.custom_minimum_size = Vector2(260, ROW_HEIGHT)
			b.add_theme_font_size_override(&"font_size", CONTROL_FONT_SIZE)
			row.controls.add_child(b)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 24)
	p.add_child(footer)
	var hint := Label.new()
	hint.text = "BIND_HINT"
	hint.theme_type_variation = &"HintLabel"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(hint)
	var reset := Button.new()
	reset.text = "BIND_RESET_ALL"
	reset.custom_minimum_size = Vector2(240, ROW_HEIGHT)
	reset.add_theme_font_size_override(&"font_size", CONTROL_FONT_SIZE)
	reset.pressed.connect(SettingsManager.reset_bindings)
	footer.add_child(reset)


func _build_accessibility(p: Control) -> void:
	_header(p, "HEADER_LANGUAGE")
	_option(p, "OPT_LANGUAGE", "accessibility", "locale", ["LANG_ZH", "LANG_EN"])
	_header(p, "HEADER_ACCESSIBILITY")
	_slider(p, "OPT_UI_SCALE", "accessibility", "ui_scale", 80, 150, 10, "%d%%", true)
	_toggle(p, "OPT_CAMERA_SHAKE", "accessibility", "camera_shake")
	_toggle(p, "OPT_SUBTITLES", "accessibility", "subtitles")
	_header(p, "HEADER_DIALOGUE")
	_option(p, "OPT_TEXT_SPEED", "accessibility", "dialogue_text_speed",
		["SPEED_SLOW", "SPEED_NORMAL", "SPEED_FAST", "SPEED_INSTANT"])
	_option(p, "OPT_DIALOGUE_FONT", "accessibility", "dialogue_font_size",
		["SIZE_SMALL", "SIZE_MEDIUM", "SIZE_LARGE"])
	_slider(p, "OPT_DIALOGUE_OPACITY", "accessibility", "dialogue_box_opacity", 30, 100, 5, "%d%%")


# ------------------------------------------------------------------ 行构建工具

func _header(parent: Control, key: String) -> void:
	if parent.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 24
		parent.add_child(gap)
		_section_gaps.append(gap)
	var l := Label.new()
	l.text = key
	l.theme_type_variation = &"HeaderLabel"
	l.add_theme_font_size_override(&"font_size", SECTION_FONT_SIZE)
	parent.add_child(l)


func _row(parent: Control, label_key: String) -> ResponsiveSettingsRow:
	var row: ResponsiveSettingsRow = ResponsiveRow.new()
	row.label.text = label_key
	row.label_width = LABEL_WIDTH
	row.separation = 24
	row.row_height = ROW_HEIGHT
	parent.add_child(row)
	_settings_rows.append(row)
	return row


## apply_on_release: 拖动时不立即应用（用于界面缩放这类会让滑条“跑掉”的设置）
func _slider(parent: Control, key: String, section: String, setting: String,
		min_v: float, max_v: float, step: float, fmt: String, apply_on_release := false) -> HSlider:
	var row := _row(parent, key)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.custom_minimum_size = Vector2(CONTROL_WIDTH - 130, 48)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.controls.add_child(s)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 106
	value_label.add_theme_font_size_override(&"font_size", CONTROL_FONT_SIZE)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	row.controls.add_child(value_label)

	var is_int := typeof(SettingsManager.get_default(section, setting)) == TYPE_INT
	var to_value := func(v: float) -> Variant: return int(roundf(v)) if is_int else snappedf(v, step)
	var commit := func(v: float) -> void: SettingsManager.set_value(section, setting, to_value.call(v))

	s.value_changed.connect(func(v: float):
		value_label.text = fmt % to_value.call(v)
		if not apply_on_release or not s.has_meta("dragging"):
			commit.call(v))
	if apply_on_release:
		s.drag_started.connect(func(): s.set_meta("dragging", true))
		s.drag_ended.connect(func(_changed: bool):
			s.remove_meta("dragging")
			commit.call(s.value))
	_refreshers.append(func():
		var v: Variant = SettingsManager.get_value(section, setting)
		s.set_value_no_signal(v)
		value_label.text = fmt % v)
	return s


func _option(parent: Control, key: String, section: String, setting: String, items: Array) -> OptionButton:
	var row := _row(parent, key)
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(CONTROL_WIDTH, ROW_HEIGHT)
	o.add_theme_font_size_override(&"font_size", CONTROL_FONT_SIZE)
	o.fit_to_longest_item = false
	for item in items:
		o.add_item(str(item))
	o.item_selected.connect(func(i: int): SettingsManager.set_value(section, setting, i))
	row.controls.add_child(o)
	_refreshers.append(func(): o.select(int(SettingsManager.get_value(section, setting))))
	return o


func _toggle(parent: Control, key: String, section: String, setting: String) -> CheckButton:
	var row := _row(parent, key)
	var c := CheckButton.new()
	c.custom_minimum_size = Vector2(CONTROL_WIDTH, ROW_HEIGHT)
	c.add_theme_font_size_override(&"font_size", BODY_FONT_SIZE)
	c.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	c.toggled.connect(func(on: bool): SettingsManager.set_value(section, setting, on))
	row.controls.add_child(c)
	_refreshers.append(func(): c.set_pressed_no_signal(bool(SettingsManager.get_value(section, setting))))
	return c


func _set_desktop_only(control: Control) -> void:
	# 窗口模式和窗口分辨率不适用于 Android/iOS，隐藏但不移除设置逻辑。
	var row := control.get_parent().get_parent() as Control
	if row:
		row.visible = not OS.has_feature("mobile")


func _update_responsive_layout() -> void:
	var metrics := UILayoutRules.settings_metrics(size)
	var compact := UILayoutRules.is_compact(size)
	_margin.add_theme_constant_override("margin_left", int(metrics.margin_x))
	_margin.add_theme_constant_override("margin_right", int(metrics.margin_x))
	_margin.add_theme_constant_override("margin_top", int(metrics.margin_y))
	_margin.add_theme_constant_override("margin_bottom", int(metrics.margin_y))
	_panel_rows.add_theme_constant_override("separation", int(metrics.panel_gap))
	_title.add_theme_font_size_override(&"font_size", int(metrics.title_size))
	_tabs.add_theme_font_size_override(&"font_size", int(metrics.tab_size))
	_tab_hint.visible = not compact
	_back_hint.visible = not compact
	for gap in _section_gaps:
		gap.custom_minimum_size.y = int(metrics.panel_gap)
	for row in _settings_rows:
		row.compact = compact
		row.apply_metrics(metrics)
