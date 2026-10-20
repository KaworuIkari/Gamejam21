class_name CoordinatePad
extends CanvasLayer
## Phone-style keypad (1–9, then Clear · 0 · Confirm) for typing the boat's coordinates.
## Usage:  if await CoordinatePad.ask(self, "211026"): ...
## A wrong code shows COORD_PAD_WRONG and clears the entry; Cancel / Esc returns false.
## Keyboard: 0–9, Backspace, Enter, Esc. The game is paused while it is open.

const LightUI = preload("res://ui/theme/light/light_ui.gd")
const WRONG_COLOR := Color(0.85, 0.22, 0.2)

signal decided(accepted: bool)

var _answer := ""
var _entry := ""
var _display: Label
var _status: Label
var _first: Button


static func ask(context: Node, answer: String) -> bool:
	var pad := CoordinatePad.new()
	pad._answer = answer
	var tree := context.get_tree()
	var was_paused := tree.paused
	var mouse_mode := Input.mouse_mode
	tree.paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	tree.root.add_child(pad)
	var result: bool = await pad.decided
	pad.queue_free()
	tree.paused = was_paused
	Input.mouse_mode = mouse_mode
	return result


func _ready() -> void:
	layer = 120  # like ConfirmPopup: above the pause menu, below scene transitions
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 16)
	panel.add_child(column)

	var title := Label.new()
	title.text = "COORD_PAD_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_display = Label.new()
	_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_display.add_theme_font_size_override(&"font_size", 48)
	column.add_child(_display)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override(&"font_color", WRONG_COLOR)
	column.add_child(_status)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 12)
	grid.add_theme_constant_override(&"v_separation", 12)
	var grid_center := CenterContainer.new()
	grid_center.add_child(grid)
	column.add_child(grid_center)
	var keys: Array = []
	for digit in range(1, 10):
		keys.append([str(digit), _type.bind(str(digit))])
	keys.append_array([["COORD_PAD_CLEAR", _clear], ["0", _type.bind("0")], ["COORD_PAD_CONFIRM", _confirm]])
	for entry in keys:
		var key := Button.new()
		key.text = entry[0]
		key.custom_minimum_size = Vector2(110, 80)
		if entry[0].length() == 1:
			key.add_theme_font_size_override(&"font_size", 36)
		key.pressed.connect(entry[1])
		grid.add_child(key)
		if _first == null:
			_first = key

	var cancel := Button.new()
	cancel.text = "UI_CANCEL"
	cancel.custom_minimum_size.x = 140
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(decided.emit.bind(false))
	column.add_child(cancel)

	LightUI.apply(root)
	LightUI.frost(panel)
	LightUI.soften_dim(dim)
	_refresh()
	_first.grab_focus.call_deferred()


func _type(digit: String) -> void:
	if _entry.length() >= _answer.length():
		return
	_entry += digit
	_status.text = ""
	_refresh()


func _clear() -> void:
	_entry = ""
	_status.text = ""
	_refresh()


func _confirm() -> void:
	if _entry == _answer:
		decided.emit(true)
		return
	_entry = ""
	_status.text = tr("COORD_PAD_WRONG")
	_refresh()


## "3 7 _ _": typed digits, then blanks up to the code's length.
func _refresh() -> void:
	var cells: Array[String] = []
	for i in _answer.length():
		cells.append(_entry[i] if i < _entry.length() else "_")
	_display.text = " ".join(cells)


# _input, not _unhandled_input: Enter must confirm, not press the focused digit key.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		decided.emit(false)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var code: int = event.keycode
	if code >= KEY_0 and code <= KEY_9:
		_type(str(code - KEY_0))
	elif code >= KEY_KP_0 and code <= KEY_KP_9:
		_type(str(code - KEY_KP_0))
	elif code == KEY_BACKSPACE:
		_entry = _entry.left(-1)
		_refresh()
	elif code == KEY_ENTER or code == KEY_KP_ENTER:
		_confirm()
	else:
		return
	get_viewport().set_input_as_handled()
