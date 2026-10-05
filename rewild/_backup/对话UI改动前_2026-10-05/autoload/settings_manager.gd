extends Node
## 全局设置管理（Autoload: SettingsManager）
## - 读写 user://settings.cfg
## - 启动时应用全部设置；运行时 set_value() 立即生效
## - 管理按键重绑定（每个动作一个键鼠绑定 + 一个手柄绑定）

signal setting_changed(section: String, key: String, value: Variant)
signal bindings_changed

const UILayoutRules = preload("res://ui/layout/ui_layout.gd")

const SAVE_PATH := "user://settings.cfg"

enum WindowMode { WINDOWED, BORDERLESS_FULLSCREEN, EXCLUSIVE_FULLSCREEN }
enum Quality { LOW, MEDIUM, HIGH, ULTRA }
enum Scaler { BILINEAR, FSR1, FSR2 }
enum VSync { OFF, ON, ADAPTIVE }

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3840, 2160),
]
const FPS_LIMITS: Array[int] = [30, 60, 120, 144, 0] # 0 = 不限制
const LOCALES: Array[String] = ["zh_CN", "en"]

## 设置项 key -> AudioBus 名称
const AUDIO_BUSES := {
	"master_volume": "Master",
	"music_volume": "Music",
	"sfx_volume": "SFX",
	"ambient_volume": "Ambient",
}

## 可在设置里重绑定的动作（需在 项目设置 > 输入映射 中存在）
const REBINDABLE_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right",
	&"jump", &"sprint", &"interact", &"pause",
]

const DEFAULTS := {
	"audio": {
		"master_volume": 80,
		"music_volume": 70,
		"sfx_volume": 80,
		"ambient_volume": 70,
	},
	"video": {
		"window_mode": WindowMode.WINDOWED,
		"resolution": 1, # RESOLUTIONS 下标，默认 1600x900
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
	},
}

var _config := ConfigFile.new()
var _values: Dictionary = {}
var _default_events: Dictionary = {} # action -> Array[InputEvent]
var _environments: Array[WeakRef] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_values = DEFAULTS.duplicate(true)
	for action in REBINDABLE_ACTIONS:
		if InputMap.has_action(action):
			_default_events[action] = InputMap.action_get_events(action).map(func(e): return e.duplicate())
	_load()
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
	_config.set_value(section, key, value)
	_apply(section, key)
	setting_changed.emit(section, key, value)


func reset_section(section: String) -> void:
	if section == "input":
		reset_bindings()
		return
	for key in DEFAULTS.get(section, {}):
		set_value(section, key, DEFAULTS[section][key])


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
				# fov 由相机自行读取 / 监听 setting_changed
		"accessibility":
			match key:
				"locale":
					TranslationServer.set_locale(LOCALES[clampi(v, 0, LOCALES.size() - 1)])
				"ui_scale":
					get_tree().root.content_scale_factor = UILayoutRules.content_scale(float(v))
		# controls 由玩家控制器读取


func _apply_volume(bus_name: String, percent: Variant) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var linear := clampf(float(percent) / 100.0, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, linear <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))


func _apply_window() -> void:
	# 在编辑器内嵌窗口中运行时不改动窗口，避免干扰编辑器
	if Engine.is_embedded_in_editor() or DisplayServer.get_name() == "headless":
		return
	var mode: int = get_value("video", "window_mode")
	match mode:
		WindowMode.BORDERLESS_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WindowMode.EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var res := RESOLUTIONS[clampi(get_value("video", "resolution"), 0, RESOLUTIONS.size() - 1)]
			var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
			res = res.min(usable.size)
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
