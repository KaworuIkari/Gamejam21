extends CanvasLayer
## Debug builds only (created by DebugAutoload): a floating panel of cheats for quick tests.
## F1 shows / hides it (the mouse is released while it is open); drag the title to move it.
## Add a button with _button(text, callable) in _build.

const TOGGLE_KEY := KEY_F1
const PauseMenu = preload("res://ui/in_game/pause_menu.gd")
## [label, landmark node path from the level root, world offset, snap to terrain].
const TELEPORTS := [
	["森林", "Enviroment/West_forest/Trail_Sign_Barren2", Vector3(0, 0, 4), true],
	["水泵", "Enviroment/North_water_source/Ruined_Pump_House_Golden", Vector3(0, 0, 8), true],
	["终端", "Enviroment/Central_lake/LakePowerStation", Vector3(0, 0, 8), true],
	["机器人工厂", "Enviroment/East_Robot_factory/Jetpack_root", Vector3(-4, 0, 0), true],
	["船", "NavigationRegion3D/Workboat", Vector3(0, 3, 0), false],
	["雷达站", "Enviroment/East_Mountain/RadioObservatory", Vector3(0, 0, 10), true],
]

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
		["获得混沌能量模块", func(): BatteryCharge.collect()],
		["狐狸钥匙", func(): Quests.grant(&"fox_key")],
	]:
		column.add_child(_button(entry[0], entry[1]))
	var teleports := GridContainer.new()
	teleports.columns = 2
	column.add_child(teleports)
	for spot in TELEPORTS:
		var button := _button("传送：" + spot[0], _teleport.bind(spot[1], spot[2], spot[3]))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		teleports.add_child(button)
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
	_status.text = "水枪 %d  背包 %d  射速 %d/3  容量 %d/3\n材料 %d  齿轮 %d  混沌能量模块 %s" % [
		Quests.ability_level(&"water_gun"), Quests.ability_level(&"jetpack"),
		WaterGunUpgrades.level(WaterGunUpgrades.RATE), WaterGunUpgrades.level(WaterGunUpgrades.TANK),
		WaterGunUpgrades.material(), Quests.event_count(&"factory_gear"),
		"有" if Quests.has_ability(BatteryCharge.BATTERY) else "无"]


## Free upgrade, without spending material.
func _upgrade(track: StringName) -> void:
	Quests.grant(track, mini(WaterGunUpgrades.level(track) + 1, WaterGunUpgrades.MAX_LEVEL))


## Moves the player next to a landmark of the current level, standing on the terrain.
func _teleport(path: String, offset: Vector3, snap: bool) -> void:
	var scene := get_tree().current_scene
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	var landmark := scene.get_node_or_null(path) as Node3D if scene else null
	if player == null or landmark == null:
		push_warning("debug teleport: no player or landmark %s" % path)
		return
	var target := landmark.global_position + offset
	if snap:
		var terrains := scene.find_children("*", "Terrain3D", true, false)
		if not terrains.is_empty() and terrains[0].data:
			var height: float = terrains[0].data.get_height(target)
			if not is_nan(height):
				target.y = maxf(height, target.y)
		target.y += 1.0
	player.global_position = target
	if player is CharacterBody3D:
		player.velocity = Vector3.ZERO


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
