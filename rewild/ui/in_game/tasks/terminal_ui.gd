extends CanvasLayer
## Owns the HUD entry and Tab routing. PauseMenu owns pause and mouse state.
const ACTION := &"task_terminal"
var _pause_menu: CanvasLayer
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
