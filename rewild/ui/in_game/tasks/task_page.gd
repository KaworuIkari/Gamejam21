extends Control
## Presentation only. Shows the Quests autoload's quests when there are any (res://quests/),
## otherwise the demo record. The demo row is the template for the real quest rows.
## Above the quests it shows how green the land is, in total and per GrowthRegion.
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
var _rows: Array[Button] = []
var _selected_id: StringName = &""
## The player folded the open quest shut: do not pick the first one again.
var _collapsed := false
var _restore: VBoxContainer
var _restore_total: Label
var _restore_total_bar: Label
var _restore_rows: VBoxContainer

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
	var quests := _quests()
	if quests:
		quests.changed.connect(func() -> void:
			if visible:
				_render())
	resized.connect(_update_layout)
	_build_restoration()
	_render()
	_update_layout()
	hide()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_render()
		_render_restoration()

func open() -> void:
	_archive = false
	_selected = true
	_tracking = false
	var tq: Quest = _quests().tracked_quest() if _quest_mode() else null
	_selected_id = tq.get_id() if tq else &""
	_collapsed = false
	_render()
	_render_restoration()
	show()
	_update_layout()
	if _quest_mode():
		if not _rows.is_empty():
			_rows[0].grab_focus()
		else:
			_close_button.grab_focus()
	elif show_demo:
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
	_collapsed = false
	_render()

func _select_demo() -> void:
	_selected = not _selected
	_render()

func _toggle_tracking() -> void:
	if _quest_mode():
		var q := _selected_quest()
		if q:
			var quests := _quests()
			quests.track(null if quests.tracked == q.get_id() else q)
		return
	_tracking = not _tracking
	_render()

func _render() -> void:
	if _quest_mode():
		_render_quests()
		return
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
	var lines: Array = []
	for index in steps.size():
		lines.append([tr(str(steps[index])), index < completed])
	_fill_steps(lines)

func _fill_steps(lines: Array) -> void:
	var step_container := get_node("Center/TerminalPanel/Window/Scroll/Margin/Content/Detail/Split/Steps")
	for child in step_container.get_children():
		if child.name != &"Heading":
			step_container.remove_child(child)
			child.queue_free()
	for line in lines:
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = ("[✓] " if line[1] else "[ ] ") + line[0]
		if line[1]:
			label.add_theme_color_override(&"font_color", Color(0.6, 0.69, 0.56))
		step_container.add_child(label)

# --- Restoration -----------------------------------------------------------------------

const BAR_CELLS := 20

func _build_restoration() -> void:
	_restore = VBoxContainer.new()
	_restore.add_theme_constant_override(&"separation", 6)
	var total := _restore_row()
	_restore_total = total.get_child(0)
	_restore_total_bar = total.get_child(1)
	_restore.add_child(total)
	_restore_rows = VBoxContainer.new()
	_restore.add_child(_restore_rows)
	_restore.add_child(HSeparator.new())
	var content := %Filters.get_parent()
	content.add_child(_restore)
	content.move_child(_restore, 0)
	var growth := get_node_or_null(^"/root/GrowthMap")
	if growth:
		growth.progress_changed.connect(func() -> void:
			if visible:
				_render_restoration())
	_render_restoration()

func _render_restoration() -> void:
	var growth := get_node_or_null(^"/root/GrowthMap")
	var regions: Array[Dictionary] = growth.progress_regions() if growth else []
	_restore.visible = not regions.is_empty()
	if regions.is_empty():
		return
	_restore_total.text = tr("RESTORE_TITLE")
	_restore_total_bar.text = _bar(growth.progress_total)
	var rows := _restore_rows.get_children()
	for i in maxi(rows.size(), regions.size()):
		if i >= regions.size():
			rows[i].queue_free()
			continue
		var row: HBoxContainer = rows[i] if i < rows.size() else null
		if row == null:
			row = _restore_row()
			row.modulate = Color(0.6, 0.69, 0.56)
			_restore_rows.add_child(row)
		row.get_child(0).text = "  " + tr(regions[i].title)
		row.get_child(1).text = _bar(regions[i].value)

## Name in a fixed-width column, then the bar, so every bar starts at the same x.
func _restore_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.custom_minimum_size.x = 200
	row.add_child(name_label)
	row.add_child(Label.new())
	return row

## 0..1 -> whole percent; only shows 100 once the ground is really all green.
static func percent(value: float) -> int:
	return mini(int(value * 100.0), 99) if value < 0.995 else 100

## "[■■■■□□□□…] 23%"
func _bar(value: float) -> String:
	var p := percent(value)
	var filled := int(p / 100.0 * BAR_CELLS)
	return "[%s%s] %3d%%" % ["■".repeat(filled), "□".repeat(BAR_CELLS - filled), p]

# --- Real quests ----------------------------------------------------------------------

func _quests() -> Node:
	return get_node_or_null(^"/root/Quests")

func _quest_mode() -> bool:
	var quests := _quests()
	return quests != null and not quests.quests.is_empty()

## Quests shown on the current tab: active ones, or completed ones in the archive.
func _listed() -> Array[Quest]:
	var quests := _quests()
	var out: Array[Quest] = []
	for q: Quest in quests.quests:
		var st: int = quests.status(q)
		if st == (quests.Status.DONE if _archive else quests.Status.ACTIVE):
			out.append(q)
	return out

func _selected_quest() -> Quest:
	for q in _listed():
		if q.get_id() == _selected_id:
			return q
	return null

func _select_quest(id: StringName) -> void:
	_collapsed = _selected_id == id
	_selected_id = &"" if _collapsed else id
	_render()

func _render_quests() -> void:
	var quests := _quests()
	var listed := _listed()
	if _selected_quest() == null and not _collapsed:
		_selected_id = listed[0].get_id() if not listed.is_empty() else &""
	%Filters.visible = true
	%ListHeader.visible = not listed.is_empty()
	%DemoNotice.visible = false
	%DemoTask.visible = false
	%ActiveButton.button_pressed = not _archive
	%ArchiveButton.button_pressed = _archive
	set_return_binding(_return_binding)
	for r in _rows:
		r.queue_free()
	_rows.clear()
	var index := %DemoTask.get_index()
	for i in listed.size():
		var q := listed[i]
		var row: Button = %DemoTask.duplicate()
		for n in row.find_children("*", "", true, false):
			n.unique_name_in_owner = false
		row.visible = true
		row.button_pressed = q.get_id() == _selected_id
		row.get_node("Row/Id").text = ("v %02d" if row.button_pressed else "> %02d") % (i + 1)
		row.get_node("Row/RowTitle").text = tr(q.title)
		row.get_node("Row/Progress").text = "%d/%d" % [_done_steps(q), q.steps.size()]
		var tracked: bool = quests.tracked_quest() == q
		row.get_node("Row/DemoStatus").text = tr("QUEST_STATUS_DONE" if _archive
				else "QUEST_STATUS_TRACKED" if tracked else "QUEST_STATUS_ACTIVE")
		row.pressed.connect(_select_quest.bind(q.get_id()))
		%DemoTask.get_parent().add_child(row)
		%DemoTask.get_parent().move_child(row, index + 1 + i)
		_rows.append(row)
	var q := _selected_quest()
	%Detail.visible = q != null
	%EmptySpace.visible = listed.is_empty()
	%EmptyLabel.text = "QUEST_EMPTY_ARCHIVE" if _archive else "QUEST_EMPTY_ACTIVE"
	if q == null:
		return
	# The detail section sits after all the rows.
	%Detail.get_parent().move_child(%Detail, index + 1 + listed.size())
	%DetailTitle.text = tr(q.title)
	%Location.text = tr(q.location)
	var text := tr(q.description)
	if not q.rewards.is_empty():
		var names: Array[String] = []
		for a in q.rewards:
			names.append(ability_name(a, q.rewards[a]))
		text += "\n\n" + tr("QUEST_REWARDS") % ", ".join(names)
	%Description.text = text
	var lines: Array = []
	for i in q.steps.size():
		var p: Vector2i = quests.step_progress(q, i)
		var line := tr(q.steps[i].text)
		if p.y > 1:
			line += "  (%d/%d)" % [p.x, p.y]
		lines.append([line, p.x >= p.y])
	_fill_steps(lines)
	%TrackButton.visible = not _archive
	var is_tracked: bool = quests.tracked_quest() == q
	%TrackButton.text = tr("QUEST_UNTRACK" if is_tracked else "QUEST_TRACK")
	%TrackButton.button_pressed = is_tracked

func _done_steps(q: Quest) -> int:
	var quests := _quests()
	return quests.done_steps(q)

## "Water gun Lv2" from an ability name; unknown names are shown as written.
static func ability_name(ability: StringName, level: int) -> String:
	# Quest items (e.g. the energy core) have a name per level and no "Lv".
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
	%DetailTitle.add_theme_font_size_override(&"font_size", 24 if compact else 36)
	%Split.vertical = compact
	%DemoStatus.visible = not compact
	%StatusHeader.visible = not compact
