extends Node
## 全局设置管理（Autoload: SettingsManager）
## - 读写 user://settings.cfg
## - 启动时应用全部设置
## - 两步式修改：set_value() 立即生效（预览），commit() 确认并写盘，
##   revert() 撤回到上次确认的值。设置页的“应用 / 放弃”只调用这两个函数
## - 管理按键重绑定（每个动作一个键鼠绑定 + 一个手柄绑定），重绑定即时写盘，不经过 commit

signal setting_changed(section: String, key: String, value: Variant)
signal bindings_changed
## 是否存在“已预览、未应用”的更改发生变化
signal pending_changed(has_pending: bool)

## 子模块（由本节点创建，不需要单独注册 Autoload）
const UIScaler = preload("res://ui/layout/ui_scaler.gd")
const PlayerSettingsBridge = preload("res://ui/common/player_settings_bridge.gd")
var _ui_scaler: Node
var _player_bridge: Node

const UILayoutRules = preload("res://ui/layout/ui_layout.gd")

const SAVE_PATH := "user://settings.cfg"

enum WindowMode { WINDOWED, BORDERLESS_FULLSCREEN, EXCLUSIVE_FULLSCREEN }
enum Quality { LOW, MEDIUM, HIGH, ULTRA }
enum Scaler { BILINEAR, FSR1, FSR2 }
enum VSync { OFF, ON, ADAPTIVE }

const FPS_LIMITS: Array[int] = [30, 60, 120, 144, 0] # 0 = 不限制
const LOCALES: Array[String] = ["zh_CN", "en"]

## 设置项 key -> AudioBus 名称
const AUDIO_BUSES := {
	"master_volume": "Master",
	"music_volume": "Music",
	"sfx_volume": "SFX",
	"ambient_volume": "Ambient",
}

## 可在设置里重绑定的动作（名字必须和 项目设置 > 输入映射 一致；不存在的动作会自动跳过）
## 列出所有玩家会用到的键，重绑定时才能检测到冲突并自动交换
const REBINDABLE_ACTIONS: Array[StringName] = [
	&"forward", &"backward", &"left", &"right",
	&"jump", &"sprint", &"walk", &"use", &"use2", &"interact", &"pause", &"task_terminal",
	&"dialogue_auto", &"dialogue_skip", &"dialogue_history",
]
## 动作 -> 显示名（翻译键）；未列出的用 "ACTION_" + 大写动作名
const ACTION_LABELS := {
	&"forward": "ACTION_MOVE_FORWARD",
	&"backward": "ACTION_MOVE_BACK",
	&"left": "ACTION_MOVE_LEFT",
	&"right": "ACTION_MOVE_RIGHT",
}


static func action_label(action: StringName) -> String:
	return ACTION_LABELS.get(action, "ACTION_" + String(action).to_upper())


const DEFAULTS := {
	"audio": {
		"master_volume": 80,
		"music_volume": 70,
		"sfx_volume": 80,
		"ambient_volume": 70,
	},
	"video": {
		"window_mode": WindowMode.WINDOWED,
		"resolution": DisplayResolutions.AUTO, # 窗口尺寸；(0, 0) = 自动适配显示器（规则见 DisplayResolutions）
		"vsync": VSync.ON,
		"max_fps": 4, # FPS_LIMITS 下标，默认不限制
		"quality": Quality.HIGH,
		"render_scale": 100, # 百分比
		"scaler": Scaler.BILINEAR,
		"fov": 75,
	},
	"controls": {
		"mouse_sensitivity": 1.0,
		"gamepad_sensitivity": 1.0,
		"invert_y": false,
		"vibration": true,
	},
	"accessibility": {
		"locale": 0, # LOCALES 下标
		"ui_scale": 100, # 百分比
		"camera_shake": true,
		"subtitles": true,
		# 对话（Dialogic）相关
		"dialogue_text_speed": 1, # DIALOGUE_SPEEDS 下标：慢 / 中 / 快 / 瞬间
		"dialogue_font_size": 1, # 小 / 中 / 大
		"dialogue_box_opacity": 90, # 百分比
	},
}

## 对话文字速度倍率（乘在 Dialogic 的 letter_speed 上，越小越快，0 = 瞬间显示）
const DIALOGUE_SPEEDS: Array[float] = [2.5, 1.0, 0.4, 0.0]

var _config := ConfigFile.new()
var _values: Dictionary = {}
## 上次确认（commit）或读盘时的值；用于判断未应用更改和撤回。
## _config 只保存已确认的值，所以按键重绑定触发的写盘不会顺带写入未应用的设置
var _committed: Dictionary = {}
var _default_events: Dictionary = {} # action -> Array[InputEvent]
var _environments: Array[WeakRef] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ui_scaler = UIScaler.new()
	_ui_scaler.name = &"UIScaler"
	add_child(_ui_scaler)
	_player_bridge = PlayerSettingsBridge.new()
	_player_bridge.name = &"PlayerSettingsBridge"
	add_child(_player_bridge)
	_values = DEFAULTS.duplicate(true)
	for action in REBINDABLE_ACTIONS:
		if InputMap.has_action(action):
			_default_events[action] = InputMap.action_get_events(action).map(func(e): return e.duplicate())
	_load()
	_committed = _values.duplicate(true)
	apply_all.call_deferred()


# ------------------------------------------------------------------ 读写

func get_value(section: String, key: String) -> Variant:
	return _values.get(section, {}).get(key, DEFAULTS.get(section, {}).get(key))


func get_default(section: String, key: String) -> Variant:
	return DEFAULTS.get(section, {}).get(key)


func set_value(section: String, key: String, value: Variant) -> void:
	if not _values.has(section):
		_values[section] = {}
	if _values[section].get(key) == value:
		return
	_values[section][key] = value
	_apply(section, key)
	setting_changed.emit(section, key, value)
	pending_changed.emit(has_pending_changes())


func reset_section(section: String) -> void:
	if section == "input":
		reset_bindings()
		return
	for key in DEFAULTS.get(section, {}):
		set_value(section, key, DEFAULTS[section][key])


## 是否有已预览、尚未应用的更改
func has_pending_changes() -> bool:
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			if get_value(section, key) != _committed_value(section, key):
				return true
	return false


## 应用：把当前值确认为正式设置并写盘
func commit() -> void:
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			_config.set_value(section, key, get_value(section, key))
	_committed = _values.duplicate(true)
	save()
	pending_changed.emit(false)


## 放弃：把所有未应用的更改撤回到上次确认的值（会重新应用并刷新界面）
func revert() -> void:
	if not has_pending_changes():
		return
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			set_value(section, key, _committed_value(section, key))


func _committed_value(section: String, key: String) -> Variant:
	return _committed.get(section, {}).get(key, DEFAULTS[section][key])


func save() -> void:
	var err := _config.save(SAVE_PATH)
	if err != OK:
		push_warning("SettingsManager: 保存设置失败 (%s)" % error_string(err))


func _load() -> void:
	if _config.load(SAVE_PATH) != OK:
		return
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			if _config.has_section_key(section, key):
				var v: Variant = _config.get_value(section, key)
				if typeof(v) == typeof(DEFAULTS[section][key]) or _is_number(v) and _is_number(DEFAULTS[section][key]):
					_values[section][key] = v
	if _config.has_section("input"):
		for cfg_key in _config.get_section_keys("input"):
			var parts: PackedStringArray = cfg_key.split("__")
			if parts.size() != 2:
				continue
			var ev := _deserialize_event(_config.get_value("input", cfg_key))
			if ev:
				_set_binding_no_save(StringName(parts[0]), parts[1], ev)


func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


# ------------------------------------------------------------------ 应用

func apply_all() -> void:
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			_apply(section, key)


func _apply(section: String, key: String) -> void:
	var v: Variant = get_value(section, key)
	match section:
		"audio":
			_apply_volume(AUDIO_BUSES.get(key, ""), v)
		"video":
			match key:
				"window_mode", "resolution":
					_apply_window()
				"vsync":
					var modes := [DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ENABLED, DisplayServer.VSYNC_ADAPTIVE]
					DisplayServer.window_set_vsync_mode(modes[clampi(v, 0, 2)])
				"max_fps":
					Engine.max_fps = FPS_LIMITS[clampi(v, 0, FPS_LIMITS.size() - 1)]
				"quality":
					_apply_quality()
				"render_scale", "scaler":
					_apply_scaling()
				"fov":
					_player_bridge.refresh()
		"accessibility":
			match key:
				"locale":
					TranslationServer.set_locale(LOCALES[clampi(v, 0, LOCALES.size() - 1)])
				"ui_scale":
					# 只缩放我们的 UI，不改全局缩放（全局缩放会改变主场景像素化的分辨率）
					_ui_scaler.user_scale = UILayoutRules.content_scale(float(v))
				"dialogue_text_speed":
					apply_dialogue_speed()
				# dialogue_font_size / dialogue_box_opacity 由对话框图层监听 setting_changed 自行应用
		"controls":
			# 灵敏度等由 PlayerSettingsBridge 写到角色控制器上
			_player_bridge.refresh()


func apply_dialogue_speed() -> void:
	var dialogic := get_node_or_null(^"/root/Dialogic")
	if dialogic == null or not dialogic.has_subsystem("Settings"):
		return
	var idx := clampi(int(get_value("accessibility", "dialogue_text_speed")), 0, DIALOGUE_SPEEDS.size() - 1)
	dialogic.Settings.text_speed = DIALOGUE_SPEEDS[idx]


func _apply_volume(bus_name: String, percent: Variant) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var linear := clampf(float(percent) / 100.0, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, linear <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))


## 当前能否由游戏控制窗口（编辑器“游戏”标签页内嵌运行 / 无头模式下不能）
func can_control_window() -> bool:
	return not Engine.is_embedded_in_editor() and DisplayServer.get_name() != "headless"


func _apply_window() -> void:
	# 在编辑器内嵌窗口中运行时不改动窗口，避免干扰编辑器
	if not can_control_window():
		return
	var mode: int = get_value("video", "window_mode")
	match mode:
		WindowMode.BORDERLESS_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WindowMode.EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			# 放不下或“自动”时取自动档，保证宽高比不被截断变形
			var res := DisplayResolutions.resolve(get_value("video", "resolution"))
			var win := get_tree().root
			win.size = res
			win.move_to_center()


func _apply_scaling() -> void:
	var vp := get_tree().root
	var scaler: int = get_value("video", "scaler")
	var modes := [Viewport.SCALING_3D_MODE_BILINEAR, Viewport.SCALING_3D_MODE_FSR, Viewport.SCALING_3D_MODE_FSR2]
	vp.scaling_3d_mode = modes[clampi(scaler, 0, 2)]
	vp.scaling_3d_scale = clampf(float(get_value("video", "render_scale")) / 100.0, 0.25, 2.0)


func _apply_quality() -> void:
	var q: int = get_value("video", "quality")
	var vp := get_tree().root
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][q]
	vp.screen_space_aa = [Viewport.SCREEN_SPACE_AA_DISABLED, Viewport.SCREEN_SPACE_AA_FXAA, Viewport.SCREEN_SPACE_AA_FXAA, Viewport.SCREEN_SPACE_AA_SMAA][q]
	vp.positional_shadow_atlas_size = [1024, 2048, 4096, 8192][q]
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096, 8192][q], true)
	for ref in _environments:
		var env: Environment = ref.get_ref()
		if env:
			apply_quality_to_environment(env)


## 场景里的 WorldEnvironment 调用此函数注册，画质变化时自动同步
func register_environment(env: Environment) -> void:
	_environments = _environments.filter(func(r): return r.get_ref() != null)
	_environments.append(weakref(env))
	apply_quality_to_environment(env)


func apply_quality_to_environment(env: Environment) -> void:
	var q: int = get_value("video", "quality")
	env.ssao_enabled = q >= Quality.MEDIUM
	env.glow_enabled = q >= Quality.MEDIUM
	env.ssil_enabled = q >= Quality.ULTRA
	env.ssr_enabled = q >= Quality.ULTRA
	env.volumetric_fog_enabled = env.volumetric_fog_enabled and q >= Quality.HIGH


# ------------------------------------------------------------------ 按键绑定
# kind: "kbm"（键盘/鼠标）或 "joy"（手柄）

func event_kind(ev: InputEvent) -> String:
	if ev is InputEventKey or ev is InputEventMouseButton:
		return "kbm"
	if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
		return "joy"
	return ""


func get_binding(action: StringName, kind: String) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for ev in InputMap.action_get_events(action):
		if event_kind(ev) == kind:
			return ev
	return null


## 重绑定；若该按键已被其他动作占用，则与其交换
func rebind(action: StringName, kind: String, ev: InputEvent) -> void:
	var old := get_binding(action, kind)
	for other in REBINDABLE_ACTIONS:
		if other == action:
			continue
		var other_ev := get_binding(other, kind)
		if other_ev and _events_equal(other_ev, ev):
			if old:
				_set_binding_no_save(other, kind, old)
				_config.set_value("input", "%s__%s" % [other, kind], _serialize_event(old))
			else:
				InputMap.action_erase_event(other, other_ev)
	_set_binding_no_save(action, kind, ev)
	_config.set_value("input", "%s__%s" % [action, kind], _serialize_event(ev))
	save()
	bindings_changed.emit()


func reset_bindings() -> void:
	for action in _default_events:
		InputMap.action_erase_events(action)
		for ev in _default_events[action]:
			InputMap.action_add_event(action, ev.duplicate())
	if _config.has_section("input"):
		_config.erase_section("input")
	save()
	bindings_changed.emit()


func _set_binding_no_save(action: StringName, kind: String, ev: InputEvent) -> void:
	if not InputMap.has_action(action):
		return
	for existing in InputMap.action_get_events(action):
		if event_kind(existing) == kind:
			InputMap.action_erase_event(action, existing)
	InputMap.action_add_event(action, ev)


func _events_equal(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return _key_code(a) == _key_code(b)
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return a.button_index == b.button_index
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return a.button_index == b.button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		return a.axis == b.axis and signf(a.axis_value) == signf(b.axis_value)
	return false


func _key_code(ev: InputEventKey) -> Key:
	return ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode


func _serialize_event(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		return {"type": "key", "code": int(_key_code(ev))}
	if ev is InputEventMouseButton:
		return {"type": "mouse", "button": int(ev.button_index)}
	if ev is InputEventJoypadButton:
		return {"type": "joy_button", "button": int(ev.button_index)}
	if ev is InputEventJoypadMotion:
		return {"type": "joy_axis", "axis": int(ev.axis), "sign": signf(ev.axis_value)}
	return {}


func _deserialize_event(d: Variant) -> InputEvent:
	if typeof(d) != TYPE_DICTIONARY:
		return null
	match d.get("type", ""):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(d.get("code", 0))
			k.device = -1
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(d.get("button", 1))
			m.device = -1
			return m
		"joy_button":
			var jb := InputEventJoypadButton.new()
			jb.button_index = int(d.get("button", 0))
			jb.device = -1
			return jb
		"joy_axis":
			var ja := InputEventJoypadMotion.new()
			ja.axis = int(d.get("axis", 0))
			ja.axis_value = float(d.get("sign", 1.0))
			ja.device = -1
			return ja
	return null


## 把按键转换成可显示文字（已翻译）
func event_to_text(ev: InputEvent) -> String:
	if ev == null:
		return tr("BIND_NONE")
	if ev is InputEventKey:
		var code := _key_code(ev)
		if ev.physical_keycode != KEY_NONE and DisplayServer.get_name() != "headless":
			code = DisplayServer.keyboard_get_keycode_from_physical(ev.physical_keycode)
		return OS.get_keycode_string(code)
	if ev is InputEventMouseButton:
		match ev.button_index:
			MOUSE_BUTTON_LEFT: return tr("BIND_MOUSE_LEFT")
			MOUSE_BUTTON_RIGHT: return tr("BIND_MOUSE_RIGHT")
			MOUSE_BUTTON_MIDDLE: return tr("BIND_MOUSE_MIDDLE")
			MOUSE_BUTTON_WHEEL_UP: return tr("BIND_WHEEL_UP")
			MOUSE_BUTTON_WHEEL_DOWN: return tr("BIND_WHEEL_DOWN")
		return tr("BIND_MOUSE_N") % ev.button_index
	if ev is InputEventJoypadButton:
		var names := {
			JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
			JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
			JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
			JOY_BUTTON_START: "Menu", JOY_BUTTON_BACK: "View",
			JOY_BUTTON_DPAD_UP: "D-Pad ↑", JOY_BUTTON_DPAD_DOWN: "D-Pad ↓",
			JOY_BUTTON_DPAD_LEFT: "D-Pad ←", JOY_BUTTON_DPAD_RIGHT: "D-Pad →",
		}
		return names.get(ev.button_index, "Button %d" % ev.button_index)
	if ev is InputEventJoypadMotion:
		var pos: bool = ev.axis_value > 0
		match ev.axis:
			JOY_AXIS_LEFT_X: return tr("BIND_LSTICK") + (" →" if pos else " ←")
			JOY_AXIS_LEFT_Y: return tr("BIND_LSTICK") + (" ↓" if pos else " ↑")
			JOY_AXIS_RIGHT_X: return tr("BIND_RSTICK") + (" →" if pos else " ←")
			JOY_AXIS_RIGHT_Y: return tr("BIND_RSTICK") + (" ↓" if pos else " ↑")
			JOY_AXIS_TRIGGER_LEFT: return "LT"
			JOY_AXIS_TRIGGER_RIGHT: return "RT"
		return "Axis %d" % ev.axis
	return "?"
