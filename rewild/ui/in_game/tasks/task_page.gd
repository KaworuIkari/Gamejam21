extends Control
## Presentation only. Demo data never leaves this UI module or touches saves.
signal close_requested

const UIScaler = preload("res://ui/layout/ui_scaler.gd")
const UILayoutRules = preload("res://ui/layout/ui_layout.gd")
const Demo = preload("res://ui/in_game/tasks/task_demo.gd")
## Disable this in the inspector to return to the completely empty "待编辑" page.
@export var show_demo := true
@onready var _panel: PanelContainer = %TerminalPanel
@onready var _close_button: Button = %CloseButton
var _return_binding := "Tab"
var _record: Dictionary = {}
var _archive := false
var _selected := true
var _tracking := false

## A real provider can supply a display snapshot without putting gameplay logic here.
## Fields: title, description, location, steps (Array[String]), completed_steps (int).
## Text values may be translation keys or authored display text.
func set_task_record(record: Dictionary) -> void:
	_record = record.duplicate(true)
	if is_node_ready():
		_render()

func set_return_binding(binding: String) -> void:
	_return_binding = binding
	if is_node_ready():
		_close_button.text = "%s [%s / Esc]" % [tr("TASK_TERMINAL_CLOSE"), binding]

func _ready() -> void:
	_close_button.pressed.connect(func(): close_requested.emit())
	%ActiveButton.pressed.connect(_set_archive.bind(false))
	%ArchiveButton.pressed.connect(_set_archive.bind(true))
	%DemoTask.pressed.connect(_select_demo)
	%TrackButton.pressed.connect(_toggle_tracking)
	get_viewport().size_changed.connect(_update_layout)
	resized.connect(_update_layout)
	_render()
	_update_layout()
	hide()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_render()

func open() -> void:
	_archive = false
	_selected = true
	_tracking = false
	_render()
	show()
	_update_layout()
	if show_demo:
		%DemoTask.grab_focus()
	else:
		_close_button.grab_focus()

func close() -> void:
	hide()
	_tracking = false

func is_open() -> bool:
	return visible

func _set_archive(archive: bool) -> void:
	_archive = archive
	_render()

func _select_demo() -> void:
	_selected = not _selected
	_render()

func _toggle_tracking() -> void:
	_tracking = not _tracking
	_render()

func _render() -> void:
	%Filters.visible = show_demo
	%ListHeader.visible = show_demo
	%DemoNotice.visible = show_demo
	%DemoTask.visible = show_demo and not _archive
	%Detail.visible = show_demo and not _archive and _selected
	%EmptySpace.visible = not show_demo or _archive or not _selected
	%EmptyLabel.text = "TASK_DEMO_ARCHIVE_EMPTY" if show_demo and _archive else "TASK_DEMO_SELECT" if show_demo else "TASK_TERMINAL_EMPTY"
	%ActiveButton.button_pressed = not _archive
	%ArchiveButton.button_pressed = _archive
	%DemoTask.button_pressed = _selected
	%Id.text = ("v 01" if _selected else "> 01")
	set_return_binding(_return_binding)
	%RowTitle.text = tr(str(_record.get("title", Demo.TITLE)))
	%DetailTitle.text = tr(str(_record.get("title", Demo.TITLE)))
	%Description.text = tr(str(_record.get("description", Demo.DESCRIPTION)))
	%Location.text = tr(str(_record.get("location", Demo.LOCATION)))
	var steps: Array = _record.get("steps", Demo.STEPS)
	var completed := clampi(int(_record.get("completed_steps", Demo.COMPLETED_STEPS)), 0, steps.size())
	%Progress.text = "%d/%d" % [completed, steps.size()]
	%DemoStatus.text = tr("TASK_DEMO_TRACKING" if _tracking else "TASK_DEMO_REFERENCE")
	%TrackButton.text = tr("TASK_DEMO_UNTRACK" if _tracking else "TASK_DEMO_TRACK")
	%TrackButton.button_pressed = _tracking
	var step_container := get_node("Center/TerminalPanel/Window/Scroll/Margin/Content/Detail/Split/Steps")
	for child in step_container.get_children():
		if child.name != &"Heading":
			step_container.remove_child(child)
			child.queue_free()
	for index in steps.size():
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = ("[✓] " if index < completed else "[ ] ") + tr(str(steps[index]))
		if index < completed:
			label.add_theme_color_override(&"font_color", Color(0.6, 0.69, 0.56))
		step_container.add_child(label)

func _update_layout() -> void:
	if not is_node_ready():
		return
	var viewport_size := UIScaler.virtual_viewport_size(get_viewport())
	var compact := UILayoutRules.is_compact(viewport_size)
	_panel.custom_minimum_size = Vector2(minf(1200.0, maxf(0.0, viewport_size.x - 64.0)), minf(740.0, maxf(0.0, viewport_size.y - 64.0)))
	%Title.add_theme_font_size_override(&"font_size", 36 if compact else 48)
	%DetailTitle.add_theme_font_size_override(&"font_size", 24 if compact else 36)
	%Split.vertical = compact
	%DemoStatus.visible = not compact
	%StatusHeader.visible = not compact
