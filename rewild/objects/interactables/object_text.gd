@icon("res://addons/dialogic/Editor/Images/Resources/portrait.svg")
class_name ObjectText
extends "res://ui/CustomUi/dialogue_trigger.gd"
## Attach to any object to show text in the shared dialogue box when the player presses interact.
## Add an ObjectText node under the object (or call ObjectText.attach_to(object, ["KEY"])),
## then fill Pages. Each page is a translation key from i18n/strings.csv or plain text;
## "\n" in the CSV becomes a line break. Uses the default Dialogic style (custom_ui_.tscn),
## so fonts, size, pausing, auto/skip/history all match the other dialogue.
## Setting `timeline` instead plays that authored timeline, like a DialogueTrigger.

## One page per entry, in order. Translation keys or plain text.
@export var pages: Array[String] = []
## Optional speaker shown on the name plate (e.g. dialogue/characters/XBot.dch).
@export var speaker: DialogicCharacter
## Optional name-plate text when there is no speaker resource. Translation key or plain text.
@export var speaker_name := ""
## Prompt text; "%s" is replaced by the bound interact key.
@export var prompt_key := "INSPECT_PROMPT"

var _text_timeline: DialogicTimeline
var _page := -1
var _history_start := 0


## Adds an ObjectText under `parent` (any Node3D) with an auto-made sphere of `range_radius`.
static func attach_to_object(parent: Node3D, page_list: Array[String], range_radius := 2.5) -> ObjectText:
	var node := ObjectText.new()
	node.name = &"ObjectText"
	node.pages = page_list
	node.radius = range_radius
	node.collision_layer = 0
	node.monitorable = false
	parent.add_child(node)
	return node


func _create_prompt() -> void:
	super._create_prompt()
	_prompt.configure(&"interact", prompt_key)


func _can_start() -> bool:
	if not timeline.is_empty():
		return super._can_start()
	var dialogic := _dialogic()
	return not pages.is_empty() and not (one_shot and _used) and dialogic != null \
			and dialogic.current_timeline == null and not get_tree().paused


func start() -> void:
	if not timeline.is_empty():
		super.start()
		return
	if not _can_start():
		return
	_used = one_shot
	_owns_dialogue = true
	_prompt.set_available(false)
	_dialogic().start(_make_timeline())
	dialogue_started.emit("")


## Swap the text at runtime (e.g. after a quest step). Takes effect next time it is read.
func set_pages(page_list: Array[String]) -> void:
	pages = page_list


func _make_timeline() -> DialogicTimeline:
	_text_timeline = DialogicTimeline.new()
	_text_timeline.events_processed = true
	_page = -1
	var character := _speaker_character()
	for index in pages.size():
		var event := DialogicTextEvent.new()
		event.text = _page_text(index)
		event.character = character
		event.event_started.connect(_on_page_started.bind(index))
		_text_timeline.events.append(event)
	return _text_timeline


func _speaker_character() -> DialogicCharacter:
	if speaker != null:
		return speaker
	if speaker_name.is_empty():
		return null
	var character := DialogicCharacter.new()
	character.display_name = tr(speaker_name)
	character.color = Color.WHITE
	return character


func _page_text(index: int) -> String:
	var text := tr(pages[index]).replace("\\n", "\n")
	# An empty string would make Dialogic skip the page without showing the box.
	return text if not text.is_empty() else String.chr(0x200B)


func _on_page_started(_event: DialogicEvent, index: int) -> void:
	_page = index
	if index == 0:
		_history_start = Dialogic.History.simple_history_content.size()


## Language switch mid-read: update the visible page and this read's history, like the tablets.
func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED or _text_timeline == null:
		return
	for index in _text_timeline.events.size():
		_text_timeline.events[index].text = _page_text(index)
	if Dialogic.current_timeline != _text_timeline or _page < 0:
		return
	DialogueUtils.refresh_current_text(_page_text(_page))
	var history: Array = Dialogic.History.simple_history_content
	for index in range(_page + 1):
		if _history_start + index < history.size():
			history[_history_start + index]["text"] = _page_text(index)
	Dialogic.History.simple_history_changed.emit()
