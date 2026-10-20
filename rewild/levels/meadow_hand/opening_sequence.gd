extends CanvasLayer
## New saves only. Content: i18n/strings.csv; presentation: ui/CustomUi/opening_ui.tscn.
## Camera/animation hooks: started (black), page_started, reveal_started (fade), finished.
signal started
signal page_started(index: int)
signal reveal_started
signal finished

const STYLE := "res://dialogue/styles/Opening.tres"
const PAGE_KEYS: Array[String] = [
	"OPENING_BOOT", "OPENING_ACCIDENT", "OPENING_SCAN", "OPENING_MODULES",
	"OPENING_STATUS", "OPENING_REPAIR", "OPENING_START", "OPENING_OBJECTIVE",
]
@export_range(0.1, 5.0) var fade_duration := 1.5
## Delay multiplier, applied on top of the player's dialogue speed setting.
@export_range(1.0, 10.0) var text_delay_multiplier := 3.0

var player: CharacterBody3D
var _timeline: DialogicTimeline
var _black: ColorRect
var _was_frozen := false
var _active := false
var _page := 0


func _ready() -> void:
	# Missing key = legacy save or editor play; don't replay an opening retroactively.
	_page = int(SaveManager.current_data.get("opening_page", PAGE_KEYS.size()))
	if _page >= PAGE_KEYS.size():
		queue_free()
		return
	_page = maxi(_page, 0)
	_active = true
	add_to_group(&"opening_sequence")
	layer = 29
	_was_frozen = player.frozen
	player.frozen = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_black = ColorRect.new()
	_black.name = "BlackScreen"
	_black.color = Color.BLACK
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_black)
	started.emit()
	if SceneRouter.is_busy():
		await SceneRouter.transition_finished
	Dialogic.clear()
	Dialogic.Inputs.auto_advance.enabled_forced = false
	Dialogic.Inputs.auto_skip.enabled = false
	_timeline = DialogicTimeline.new()
	_timeline.events_processed = true
	for index in PAGE_KEYS.size():
		var event := DialogicTextEvent.new()
		event.text = _page_text(index)
		event.event_started.connect(_on_page_started.bind(index))
		_timeline.events.append(event)
	var layout: Node = Dialogic.Styles.load_style(STYLE)
	if not layout.is_node_ready():
		await layout.ready
	# Dialogic.start() doesn't clear a ready layout; restore earlier pages for History.
	_rebuild_history(_page)
	Dialogic.Text.text_started.connect(_on_text_started)
	Dialogic.timeline_ended.connect(_on_timeline_ended)
	Dialogic.start(_timeline, _page)


func _on_text_started(_info: Dictionary) -> void:
	if Dialogic.current_timeline == _timeline:
		Dialogic.Text.update_text_speed(-1, false, text_delay_multiplier)


func _page_text(index: int) -> String:
	return "[center]%s[/center]" % tr(PAGE_KEYS[index]).replace("\\n", "\n")


func _on_page_started(_event: DialogicEvent, index: int) -> void:
	_page = index
	SaveManager.current_data["opening_page"] = index
	page_started.emit(index)


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED or not _active or _timeline == null:
		return
	for index in PAGE_KEYS.size():
		_timeline.events[index].text = _page_text(index)
	if Dialogic.current_timeline != _timeline:
		return
	DialogueUtils.refresh_current_text(_page_text(_page))
	_rebuild_history(_page + 1)


func _input(event: InputEvent) -> void:
	# No gameplay input before the timeline starts or during the final reveal.
	if _active and not get_tree().paused and not event.is_action(&"pause") \
			and (_timeline == null or Dialogic.current_timeline != _timeline):
		get_viewport().set_input_as_handled()


func _rebuild_history(count: int) -> void:
	Dialogic.History.simple_history_content.clear()
	for index in count:
		Dialogic.History.store_simple_history_entry(_page_text(index), "Text")


func _on_timeline_ended() -> void:
	if not _active or not is_inside_tree() or SceneRouter.is_busy():
		return
	# Keep the player frozen through the reveal, even after the dialogue layout exits.
	Dialogic.Text.update_text_speed(-1, false, 1.0)
	Dialogic.Inputs.auto_skip.enabled = false
	SaveManager.current_data["opening_page"] = PAGE_KEYS.size()
	reveal_started.emit()
	var fade := create_tween()
	fade.tween_property(_black, "modulate:a", 0.0, fade_duration)
	if player.has_method(&"face_intro"):
		await player.face_intro()   # the fade opens on a camera flying in to LIRA's face
	if fade.is_running():
		await fade.finished
	# A held confirmation must not become a jump or a shot on the first playable frame.
	while Input.is_action_pressed(&"dialogic_default_action") or Input.is_action_pressed(&"use"):
		await get_tree().process_frame
	_active = false
	remove_from_group(&"opening_sequence")
	player.frozen = _was_frozen
	if not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	SaveManager.save_current()
	finished.emit()
	queue_free()


func _exit_tree() -> void:
	if _active:
		_active = false
		Dialogic.Text.update_text_speed(-1, false, 1.0)
		Dialogic.Inputs.auto_skip.enabled = false
		if is_instance_valid(player):
			player.frozen = _was_frozen
		if _timeline != null and Dialogic.current_timeline == _timeline:
			Dialogic.end_timeline(true)
