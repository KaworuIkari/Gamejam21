extends Node
## Finale presentation only; route selection remains in FinaleStory / quest 06.
const SCREEN = preload("res://ui/in_game/ending/ending_screen.tscn")
const STYLE := "res://dialogue/styles/Opening.tres"
const PAGES := {
	&"disruptor": ["ENDING_DEVICE_START", "ENDING_DEVICE_LOCATION", "ENDING_DEVICE_QUESTIONS", "ENDING_DEVICE_ISLAND", "ENDING_DEVICE_CONTINUE"],
	&"boat": ["ENDING_BOAT_START", "ENDING_BOAT_ISLAND", "ENDING_BOAT_OBJECTIVE", "ENDING_BOAT_DEPARTURE", "ENDING_BOAT_RECORD"],
}
signal page_started(index: int)

@export_range(1.0, 10.0) var text_delay_multiplier := 3.0
var route: StringName
var _screen: CanvasLayer
var _timeline: DialogicTimeline
var _page := 0
var _finished := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_screen = SCREEN.instantiate()
	_screen.route = route
	get_tree().root.add_child(_screen)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_page = clampi(int(SaveManager.current_data.get("ending_page", 0)), 0, PAGES[route].size())
	if _page == PAGES[route].size():
		_on_timeline_ended()
		return
	if SceneRouter.is_busy():
		await SceneRouter.transition_finished
	Dialogic.clear()
	Dialogic.Inputs.auto_advance.enabled_forced = false
	Dialogic.Inputs.auto_skip.enabled = false
	_timeline = DialogicTimeline.new()
	_timeline.events_processed = true
	for index in PAGES[route].size():
		var event := DialogicTextEvent.new()
		event.text = _page_text(index)
		event.event_started.connect(_on_page_started.bind(index))
		_timeline.events.append(event)
	var layout: Node = Dialogic.Styles.load_style(STYLE)
	if not layout.is_node_ready():
		await layout.ready
	_rebuild_history(_page)
	Dialogic.Text.text_started.connect(_on_text_started)
	Dialogic.timeline_ended.connect(_on_timeline_ended)
	# As in the opening, Dialogic freezes the player and Esc uses the pause menu.
	get_tree().paused = false
	Dialogic.start(_timeline, _page)


func _page_text(index: int) -> String:
	return "[center]%s[/center]" % tr(PAGES[route][index]).replace("\\n", "\n")


func _on_page_started(_event: DialogicEvent, index: int) -> void:
	_page = index
	SaveManager.current_data["ending_page"] = index
	page_started.emit(index)


func _on_text_started(_info: Dictionary) -> void:
	if Dialogic.current_timeline == _timeline:
		Dialogic.Text.update_text_speed(-1, false, text_delay_multiplier)


func _rebuild_history(count: int) -> void:
	Dialogic.History.simple_history_content.clear()
	for index in count:
		Dialogic.History.store_simple_history_entry(_page_text(index), "Text")


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED or _finished or _timeline == null:
		return
	for index in PAGES[route].size():
		_timeline.events[index].text = _page_text(index)
	if Dialogic.current_timeline == _timeline:
		DialogueUtils.refresh_current_text(_page_text(_page))
		_rebuild_history(_page + 1)


func _on_timeline_ended() -> void:
	if _finished or not is_inside_tree() or SceneRouter.is_busy():
		return
	_finished = true
	Dialogic.Text.update_text_speed(-1, false, 1.0)
	Dialogic.Inputs.auto_skip.enabled = false
	SaveManager.current_data["ending_page"] = PAGES[route].size()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_screen.show_result()


func _exit_tree() -> void:
	if _timeline != null and Dialogic.current_timeline == _timeline:
		Dialogic.Text.update_text_speed(-1, false, 1.0)
		Dialogic.Inputs.auto_skip.enabled = false
		Dialogic.end_timeline(true)
	if is_instance_valid(_screen):
		_screen.queue_free()
