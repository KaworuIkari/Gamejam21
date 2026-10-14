extends CanvasLayer
## Owns the HUD entry and Tab routing. PauseMenu owns pause and mouse state.
## Also shows the tracked quest (top left) and quest / unlock notices (top centre).
const ACTION := &"task_terminal"
const TaskPage = preload("res://ui/in_game/tasks/task_page.gd")
var _pause_menu: CanvasLayer
var _tracker: VBoxContainer
var _tracker_title: Label
var _tracker_step: Label
var _toast: Label
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
	_build_quest_hud()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_binding()

func _process(_delta: float) -> void:
	_hud.visible = not get_tree().paused and not _dialogue_active() and not SceneRouter.is_busy()

func _input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed(ACTION):
		return
	if _page.is_open():
		get_viewport().set_input_as_handled()
		_request_close()
	elif not get_tree().paused and not _dialogue_active() and not SceneRouter.is_busy():
		get_viewport().set_input_as_handled()
		_request_open()

# --- Quest HUD ------------------------------------------------------------------------

func _build_quest_hud() -> void:
	_tracker = VBoxContainer.new()
	_tracker.position = Vector2(32, 32)
	_tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tracker_title = _hud_label(26)
	_tracker_step = _hud_label(22)
	_tracker.add_child(_tracker_title)
	_tracker.add_child(_tracker_step)
	_hud.add_child(_tracker)
	_toast = _hud_label(32)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.position.y = 96
	_toast.modulate.a = 0.0
	_hud.add_child(_toast)
	var quests := get_node_or_null(^"/root/Quests")
	if quests == null:
		_tracker.hide()
		return
	quests.changed.connect(_refresh_tracker)
	quests.quest_started.connect(func(q: Quest) -> void: _notify(tr("QUEST_TOAST_STARTED") % tr(q.title)))
	quests.quest_completed.connect(func(q: Quest) -> void: _notify(tr("QUEST_TOAST_DONE") % tr(q.title)))
	quests.ability_changed.connect(func(a: StringName, level: int) -> void:
		_notify(tr("QUEST_TOAST_ABILITY") % TaskPage.ability_name(a, level)))
	_refresh_tracker()

func _hud_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", Color(1, 0.98, 0.92))
	l.add_theme_color_override(&"font_outline_color", Color(0.08, 0.12, 0.1, 0.9))
	l.add_theme_constant_override(&"outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _refresh_tracker() -> void:
	var quests := get_node_or_null(^"/root/Quests")
	var q: Quest = quests.tracked_quest() if quests else null
	_tracker.visible = q != null
	if q == null:
		return
	var i: int = quests.current_step(q)
	_tracker_title.text = tr(q.title)
	if i >= q.steps.size():
		_tracker_step.text = ""
		return
	var p: Vector2i = quests.step_progress(q, i)
	_tracker_step.text = "› " + tr(q.steps[i].text) + ("  %d/%d" % [p.x, p.y] if p.y > 1 else "")

## Queued so a quest completing, its reward and the next quest each get their moment.
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

func _request_open() -> void:
	if is_instance_valid(_pause_menu) and not _dialogue_active() and not SceneRouter.is_busy():
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
