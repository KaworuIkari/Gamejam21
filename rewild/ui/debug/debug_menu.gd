extends CanvasLayer
## Debug builds only (created by DebugAutoload): a floating panel of cheats for quick tests.
## F1 shows / hides it (the mouse is released while it is open); drag the title to move it.
## Add a button with _button(text, callable) in _build.

const TOGGLE_KEY := KEY_F1
const PauseMenu = preload("res://ui/in_game/pause_menu.gd")

var _panel: PanelContainer
var _status: Label
var _dragging := false


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_panel.hide()
	Quests.changed.connect(_refresh)


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(24, 140)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.07, 0.88)
	style.border_color = Color(0.55, 0.95, 0.75, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override(&"panel", style)
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	_panel.add_child(column)
	var title := Label.new()
	title.text = "DEBUG  (F1)"
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title.gui_input.connect(_drag)
	column.add_child(title)
	_status = Label.new()
	_status.add_theme_font_size_override(&"font_size", 14)
	_status.add_theme_color_override(&"font_color", Color(0.7, 0.85, 0.75))
	column.add_child(_status)
	for entry in [
		["终端 + 水枪", func(): Quests.receive_starter_equipment()],
		["喷气背包（可飞行）", func(): Quests.grant(&"jetpack", maxi(1, Quests.ability_level(&"jetpack")))],
		["水枪射速 +1", _upgrade.bind(WaterGunUpgrades.RATE)],
		["水箱容量 +1", _upgrade.bind(WaterGunUpgrades.TANK)],
		["材料 +5（垃圾计数）", func(): Quests.report(WaterGunUpgrades.GARBAGE, 5)],
		["齿轮 +6", func(): Quests.report(&"factory_gear", 6)],
		["水泵激活", _start_pump],
		["获得电池", func(): BatteryCharge.collect()],
		["狐狸钥匙", func(): Quests.grant(&"fox_key")],
	]:
		column.add_child(_button(entry[0], entry[1]))
	_refresh()


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	button.pressed.connect(_refresh)
	return button


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == TOGGLE_KEY:
		get_viewport().set_input_as_handled()
		_panel.visible = not _panel.visible
		_refresh()
		if _panel.visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif not get_tree().paused:
			PauseMenu.restore_gameplay_mouse()


func _drag(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_panel.position += event.relative


func _refresh() -> void:
	if not _panel.visible:
		return
	_status.text = "水枪 %d  背包 %d  射速 %d/3  容量 %d/3\n材料 %d  齿轮 %d  电池 %s" % [
		Quests.ability_level(&"water_gun"), Quests.ability_level(&"jetpack"),
		WaterGunUpgrades.level(WaterGunUpgrades.RATE), WaterGunUpgrades.level(WaterGunUpgrades.TANK),
		WaterGunUpgrades.material(), Quests.event_count(&"factory_gear"),
		"有" if Quests.has_ability(BatteryCharge.BATTERY) else "无"]


## Free upgrade, without spending material.
func _upgrade(track: StringName) -> void:
	Quests.grant(track, mini(WaterGunUpgrades.level(track) + 1, WaterGunUpgrades.MAX_LEVEL))


## Starts the level's pump (the WaterFlowSwitch reporting pump_started) as if it were used.
func _start_pump() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for pump: WaterFlowSwitch in scene.find_children("*", "WaterFlowSwitch", true, false):
		if pump.quest_event == &"pump_started":
			pump.turn_on()
			if pump.trigger:
				pump.trigger._used = true
