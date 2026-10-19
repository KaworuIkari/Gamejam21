extends "res://ui/CustomUi/dialogue_trigger.gd"
## Reuses dialogue targeting, input, freeze/unfreeze and prompt feedback.
## Supply a content resource, or optionally an authored Dialogic timeline.
@export var content: Resource

func _create_prompt() -> void:
	super._create_prompt()
	_prompt.configure(&"interact", "READ_NOTE_PROMPT")

func _can_start() -> bool:
	if not timeline.is_empty():
		return super._can_start()
	var dialogic := _dialogic()
	return not (one_shot and _used) and dialogic != null and dialogic.current_timeline == null and not get_tree().paused

func start() -> void:
	if not timeline.is_empty():
		super.start()
		return
	if not _can_start():
		return
	_used = one_shot
	_owns_dialogue = true
	_prompt.set_available(false)
	_dialogic().start(make_reading_timeline())
	dialogue_started.emit("")

func make_reading_timeline() -> DialogicTimeline:
	var reading := DialogicTimeline.new()
	var event := DialogicTextEvent.new()
	var body := ""
	if content != null and content.has_method("get_text"):
		body = content.get_text()
	# Keep a truly blank story placeholder open until the player advances it.
	# An empty string would make Dialogic skip the event without displaying UI.
	event.text = body if not body.is_empty() else String.chr(0x200B)
	if content is ReadableNoteContent:
		event.character = content.speaker
	reading.events = [event]
	reading.events_processed = true
	return reading
