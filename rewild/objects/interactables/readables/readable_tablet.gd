extends "res://objects/interactables/readables/readable_note.gd"
## Same dialogue interaction as notes, with independently saved read-to-end credit.
@export var read_event: StringName = &""
var _reading: DialogicTimeline
var _page := -1
var _history_start := 0


func _ready() -> void:
	super._ready()
	Quests.changed.connect(_refresh_read_state)
	_refresh_read_state()


func _refresh_read_state() -> void:
	var read := Quests.event_count(read_event) > 0
	_prompt.configure(&"interact", "REREAD_TABLET_PROMPT" if read else "READ_TABLET_PROMPT")
	$SoftSparkles.emitting = not read


func make_reading_timeline() -> DialogicTimeline:
	_reading = DialogicTimeline.new()
	_reading.events_processed = true
	_page = -1
	for index in content.page_keys.size():
		var event := DialogicTextEvent.new()
		event.text = _page_text(index)
		event.event_started.connect(_on_page_started.bind(index))
		_reading.events.append(event)
	if not _reading.events.is_empty():
		_reading.events[-1].event_finished.connect(_on_read_to_end)
	return _reading


func _page_text(index: int) -> String:
	return tr(content.page_keys[index]).replace("\\n", "\n")


func _on_page_started(_event: DialogicEvent, index: int) -> void:
	_page = index
	if index == 0:
		_history_start = Dialogic.History.simple_history_content.size()


func _on_read_to_end(_event: DialogicEvent) -> void:
	# Ending/cancelling a timeline does not finish its last text event.
	if is_inside_tree() and not SceneRouter.is_busy() and Dialogic.current_timeline == _reading \
			and Quests.event_count(read_event) == 0:
		Quests.report(read_event)


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED or _reading == null:
		return
	for index in _reading.events.size():
		_reading.events[index].text = _page_text(index)
	if Dialogic.current_timeline != _reading or _page < 0:
		return
	DialogueUtils.refresh_current_text(_page_text(_page))
	var history: Array = Dialogic.History.simple_history_content
	for index in range(_page + 1):
		if _history_start + index < history.size():
			history[_history_start + index]["text"] = _page_text(index)
	Dialogic.History.simple_history_changed.emit()
