extends Control
## Presentation only. Left: the core battery charging with the four regions' recovery
## (BatteryCharge). Right: water-gun upgrades bought with material from cleared garbage
## (WaterGunUpgrades). Layout lives in task_page.tscn; rows are filled in here.
signal close_requested

const UIScaler = preload("res://ui/layout/ui_scaler.gd")
const UILayoutRules = preload("res://ui/layout/ui_layout.gd")
const BAR_CELLS := 20
const DIM := Color(0.6, 0.69, 0.56)
## Per upgrade track: name key and effect key (shown under the name).
const TRACK_TEXT := {
	WaterGunUpgrades.RATE: ["UPGRADE_RATE", "UPGRADE_RATE_DESC"],
	WaterGunUpgrades.TANK: ["UPGRADE_TANK", "UPGRADE_TANK_DESC"],
}
@onready var _panel: PanelContainer = %TerminalPanel
@onready var _close_button: Button = %CloseButton
var _return_binding := "Tab"
var _buttons: Dictionary = {}  # track -> Button
var _labels: Dictionary = {}   # track -> Label

func set_return_binding(binding: String) -> void:
	_return_binding = binding
	if is_node_ready():
		_close_button.text = "%s [%s / Esc]" % [tr("TASK_TERMINAL_CLOSE"), binding]

func _ready() -> void:
	_close_button.pressed.connect(func(): close_requested.emit())
	get_viewport().size_changed.connect(_update_layout)
	resized.connect(_update_layout)
	_build_upgrades()
	Quests.changed.connect(_render_if_open)
	GrowthMap.progress_changed.connect(_render_if_open)
	_render()
	_update_layout()
	hide()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_render()

func open() -> void:
	_render()
	show()
	_update_layout()
	for track in WaterGunUpgrades.TRACKS:
		if not _buttons[track].disabled:
			_buttons[track].grab_focus()
			return
	_close_button.grab_focus()

func close() -> void:
	hide()

func is_open() -> bool:
	return visible

func _render_if_open() -> void:
	if visible:
		_render()

func _render() -> void:
	set_return_binding(_return_binding)
	_render_battery()
	_render_upgrades()

# --- Battery ---------------------------------------------------------------------------

func _render_battery() -> void:
	var full := Quests.has_ability(BatteryCharge.BATTERY)
	%BatteryStatus.text = tr("TERMINAL_BATTERY_FULL" if full else "TERMINAL_BATTERY_CHARGING")
	%BatteryBar.text = "%s  %s" % [tr("TERMINAL_BATTERY_CHARGE"), _bar(BatteryCharge.charge())]
	var regions: Array[Dictionary] = GrowthMap.progress_regions()
	var rows := %Regions.get_children()
	for i in maxi(rows.size(), regions.size()):
		if i >= regions.size():
			rows[i].queue_free()
			continue
		var row: HBoxContainer = rows[i] if i < rows.size() else null
		if row == null:
			row = HBoxContainer.new()
			var name_label := Label.new()
			name_label.custom_minimum_size.x = 160
			row.add_child(name_label)
			row.add_child(Label.new())
			row.modulate = DIM
			%Regions.add_child(row)
		row.get_child(0).text = tr(regions[i].title)
		row.get_child(1).text = _bar(regions[i].value)

## 0..1 -> whole percent; only shows 100 once the ground is really all green.
static func percent(value: float) -> int:
	return mini(int(value * 100.0), 99) if value < 0.995 else 100

## "[■■■■□□□□…] 23%"
func _bar(value: float) -> String:
	var p := percent(value)
	var filled := int(p / 100.0 * BAR_CELLS)
	return "[%s%s] %3d%%" % ["■".repeat(filled), "□".repeat(BAR_CELLS - filled), p]

# --- Upgrades --------------------------------------------------------------------------

func _build_upgrades() -> void:
	for track in WaterGunUpgrades.TRACKS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 24)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var button := Button.new()
		button.set_meta(&"no_glass", true)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(_buy.bind(track))
		row.add_child(button)
		%UpgradeRows.add_child(row)
		_labels[track] = label
		_buttons[track] = button

func _render_upgrades() -> void:
	%Material.text = tr("TERMINAL_MATERIAL") % [WaterGunUpgrades.material(), Quests.event_count(WaterGunUpgrades.GARBAGE)]
	for track in WaterGunUpgrades.TRACKS:
		var level := WaterGunUpgrades.level(track)
		var maxed := level >= WaterGunUpgrades.MAX_LEVEL
		_labels[track].text = "%s  Lv %d/%d\n%s" % [tr(TRACK_TEXT[track][0]), level, WaterGunUpgrades.MAX_LEVEL, tr(TRACK_TEXT[track][1])]
		var button: Button = _buttons[track]
		button.text = tr("UPGRADE_MAX") if maxed else tr("UPGRADE_BUY") % WaterGunUpgrades.COST
		button.disabled = not WaterGunUpgrades.can_buy(track)

func _buy(track: StringName) -> void:
	var button: Button = _buttons[track]
	WaterGunUpgrades.buy(track)
	if button.disabled:
		_close_button.grab_focus()

# ---------------------------------------------------------------------------------------

## "Water gun Lv2" from an ability name; unknown names are shown as written.
static func ability_name(ability: StringName, level: int) -> String:
	# Items (e.g. the battery) have a name per level and no "Lv".
	var item_key := "ITEM_%s_%d" % [String(ability).to_upper(), level]
	var item := TranslationServer.translate(item_key)
	if item != item_key:
		return item
	var key := "ABILITY_" + String(ability).to_upper()
	var text := TranslationServer.translate(key)
	if text == key:
		text = String(ability).capitalize()
	return TranslationServer.translate("ABILITY_LEVEL") % [text, level]

func _update_layout() -> void:
	if not is_node_ready():
		return
	var viewport_size := UIScaler.virtual_viewport_size(get_viewport())
	var compact := UILayoutRules.is_compact(viewport_size)
	_panel.custom_minimum_size = Vector2(minf(1200.0, maxf(0.0, viewport_size.x - 64.0)), minf(740.0, maxf(0.0, viewport_size.y - 64.0)))
	%Title.add_theme_font_size_override(&"font_size", 36 if compact else 48)
	%Split.vertical = compact
