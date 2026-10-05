@tool
extends DialogicLayoutLayer
## 对话历史：全屏回看面板。打开时暂停对话；Esc / 手柄 B / 历史键 / 返回按钮关闭。

@export_file("*.ttf", "*.tres") var history_font: String = "res://fonts/ChillBitmap7x.ttf"
@export var history_font_size: int = 32
@export var name_separator: String = "："

@onready var _root: Control = %HistoryRoot
@onready var _scroll: ScrollContainer = %Scroll
@onready var _log: VBoxContainer = %Log
@onready var _close_button: Button = %CloseButton
@onready var _title: Label = %Title

var _was_paused := false


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_root.hide()
	var history = DialogicUtil.autoload().History
	history.open_requested.connect(open)
	history.close_requested.connect(close)
	_close_button.pressed.connect(func(): DialogicUtil.autoload().History.close_history())
	_apply_export_overrides()


func _apply_export_overrides() -> void:
	if not is_node_ready():
		return
	var font: Font = load(history_font) if ResourceLoader.exists(history_font) else null
	var t := Theme.new()
	t.default_font_size = history_font_size
	if font:
		t.default_font = font
		for key in [&"normal_font", &"bold_font", &"italics_font", &"bold_italics_font"]:
			t.set_font(key, &"RichTextLabel", font)
	for key in [&"normal_font_size", &"bold_font_size", &"italics_font_size", &"bold_italics_font_size"]:
		t.set_font_size(key, &"RichTextLabel", history_font_size)
	_log.theme = t


func is_open() -> bool:
	return _root.visible


func open() -> void:
	if is_open():
		return
	var dialogic := DialogicUtil.autoload()
	_was_paused = dialogic.paused
	DialogueUtils.set_paused(true)
	_rebuild()
	_root.show()
	_close_button.grab_focus()
	await get_tree().process_frame
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func close() -> void:
	if not is_open():
		return
	_root.hide()
	DialogueUtils.set_paused(_was_paused)


func _rebuild() -> void:
	for c in _log.get_children():
		c.queue_free()
	var entries: Array = DialogicUtil.autoload().History.get_simple_history()
	if entries.is_empty():
		_add_entry("[color=#9aa1a9]%s[/color]" % tr("DLG_HISTORY_EMPTY"))
		return
	for info: Dictionary in entries:
		match str(info.get("event_type", "")):
			"Text":
				var line := str(info.get("text", ""))
				if info.get("character", ""):
					var col: Color = info.get("character_color", Color("e8c872"))
					line = "[color=#%s]%s%s[/color]%s" % [col.to_html(false), info["character"], name_separator, line]
				_add_entry(line)
			"Choice":
				_add_entry("[color=#e8c872]▶ %s[/color]" % str(info.get("text", "")))
			_:
				pass


func _add_entry(bbcode: String) -> void:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.text = bbcode
	_log.add_child(r)


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not is_open():
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause") or event.is_action_pressed(&"dialogue_history"):
		get_viewport().set_input_as_handled()
		DialogicUtil.autoload().History.close_history()
	elif event.is_action_pressed(&"dialogic_default_action") and not (event is InputEventMouseButton):
		# 历史打开时不推进对话
		get_viewport().set_input_as_handled()
