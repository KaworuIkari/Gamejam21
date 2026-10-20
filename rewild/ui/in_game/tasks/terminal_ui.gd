extends CanvasLayer
## Owns the HUD entry and Tab routing. PauseMenu owns pause and mouse state.
## Also shows the battery charge and region recovery (top left) and unlock notices
## (top centre).
const ACTION := &"task_terminal"
const TaskPage = preload("res://ui/in_game/tasks/task_page.gd")
var _pause_menu: CanvasLayer
var _restore: VBoxContainer
var _restore_total: Label
var _restore_regions: Label
var _toast: Label
var _battery_notified := false
var _toast_queue: Array[String] = []
var _toast_tween: Tween
@onready var _entry: Button = %TerminalButton
@onready var _page: Control = $TaskPage
@onready var _hud: Control = $HUD

func configure(pause_menu: CanvasLayer) -> void:
	_pause_menu = pause_menu

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_entry.pressed.connect(_request_open)
	_page.close_requested.connect(_request_close)
	SettingsManager.bindings_changed.connect(_refresh_binding)
	_refresh_binding()
	_build_hud()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_binding()
		_refresh_restoration()

func _process(_delta: float) -> void:
	_hud.visible = _terminal_unlocked() and not get_tree().paused and not _dialogue_active() and not SceneRouter.is_busy()

func _input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed(ACTION) or not _terminal_unlocked():
		return
	if _page.is_open():
		get_viewport().set_input_as_handled()
		_request_close()
	elif not get_tree().paused and not _dialogue_active() and not SceneRouter.is_busy():
		get_viewport().set_input_as_handled()
		_request_open()

# --- HUD ------------------------------------------------------------------------------

func _build_hud() -> void:
	var column := VBoxContainer.new()
	column.position = Vector2(32, 32)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(column)
	_build_restoration_hud(column)
	_toast = _hud_label(32)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.position.y = 96
	_toast.modulate.a = 0.0
	_hud.add_child(_toast)
	# Unlock notices only; upgrades bought at the terminal show there instead.
	Quests.ability_changed.connect(func(a: StringName, level: int) -> void:
		if level <= 0 or a == Quests.TERMINAL or a in WaterGunUpgrades.TRACKS:
			return
		if a == &"jetpack" and level == 1:
			_notify(tr("QUEST_TOAST_JETPACK_ENABLED"))
		else:
			_notify(tr("QUEST_TOAST_ABILITY") % TaskPage.ability_name(a, level)))

func _hud_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", Color(1, 0.98, 0.92))
	l.add_theme_color_override(&"font_outline_color", Color(0.08, 0.12, 0.1, 0.9))
	l.add_theme_constant_override(&"outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# --- Restoration HUD ------------------------------------------------------------------

func _build_restoration_hud(column: Control) -> void:
	_restore = VBoxContainer.new()
	_restore.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_restore.add_theme_constant_override(&"separation", 2)
	_restore_total = _hud_label(22)
	_restore_regions = _hud_label(18)
	_restore.add_child(_restore_total)
	_restore.add_child(_restore_regions)
	column.add_child(_restore)
	var growth := get_node_or_null(^"/root/GrowthMap")
	if growth == null:
		_restore.hide()
		return
	growth.progress_changed.connect(_refresh_restoration)
	_refresh_restoration()

func _refresh_restoration() -> void:
	# Once, when the battery reaches 100%: it waits at the lake station.
	if not _battery_notified and BatteryCharge.ready_to_collect():
		_battery_notified = true
		_notify(tr("BATTERY_READY_NOTICE"))
	var growth := get_node_or_null(^"/root/GrowthMap")
	var regions: Array[Dictionary] = growth.progress_regions() if growth else []
	_restore.visible = not regions.is_empty()
	if regions.is_empty():
		return
	_restore_total.text = "%s  %d%%" % [tr("TERMINAL_BATTERY_CHARGE"), TaskPage.percent(BatteryCharge.charge())]
	var lines: Array[String] = []
	for r in regions:
		lines.append("%s  %d%%" % [tr(r.title), TaskPage.percent(r.value)])
	_restore_regions.text = "\n".join(lines)

## Queued so several unlocks in a row each get their moment.
func _notify(text: String) -> void:
	_toast_queue.append(text)
	if _toast_tween == null or not _toast_tween.is_running():
		_next_toast()

func _next_toast() -> void:
	if _toast_queue.is_empty():
		return
	_toast.text = _toast_queue.pop_front()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.3)
	_toast_tween.tween_interval(2.2)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(_next_toast)

## Until the player finds the terminal at the lake station there is no entry, no Tab and no HUD readout.
func _terminal_unlocked() -> bool:
	var quests := get_node_or_null(^"/root/Quests")
	return quests == null or quests.terminal_unlocked()

func _request_open() -> void:
	if is_instance_valid(_pause_menu) and _terminal_unlocked() and not _dialogue_active() and not SceneRouter.is_busy():
		_pause_menu.open_terminal()

func _request_close() -> void:
	if is_instance_valid(_pause_menu):
		_pause_menu.close_terminal()

func open_page() -> void:
	_hud.hide()
	_page.open()

func close_page() -> void:
	_page.close()

func is_open() -> bool:
	return _page.is_open()

func _dialogue_active() -> bool:
	var dialogic := get_node_or_null("/root/Dialogic")
	return dialogic != null and dialogic.current_timeline != null

func _refresh_binding() -> void:
	var binding := "—"
	for event in InputMap.action_get_events(ACTION):
		if event is InputEventKey:
			binding = OS.get_keycode_string(event.physical_keycode if event.physical_keycode else event.keycode)
			break
	_entry.text = ">_  %s  [%s]" % [tr("TASK_TERMINAL_TITLE"), binding]
	_page.set_return_binding(binding)
