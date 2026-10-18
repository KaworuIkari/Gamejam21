extends CanvasLayer
## Text-only ending placeholder; the existing menu theme supplies all styling.
const LightUI = preload("res://ui/theme/light/light_ui.gd")
var route: StringName
var _content: VBoxContainer
var _feedback: Label
var _returning := false

func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	LightUI.apply(root)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	LightUI.soften_dim(dim)
	root.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,24)
	root.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	LightUI.frost(panel)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation",24)
	panel.add_child(_content)
	var title := Label.new()
	title.text = "ENDING_DEVICE_TITLE" if route == &"disruptor" else "ENDING_BOAT_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size",UIType.LARGE)
	_content.add_child(title)
	var body := Label.new()
	body.text = tr("ENDING_DEVICE_BODY" if route == &"disruptor" else "ENDING_BOAT_BODY").replace("\\n","\n")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(body)
	_feedback = Label.new()
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_feedback)
	var save := Button.new()
	save.text = "PAUSE_SAVE"
	save.pressed.connect(_save_progress)
	_content.add_child(save)
	var back := Button.new()
	back.text = "PAUSE_MAIN_MENU"
	back.pressed.connect(_return_to_menu)
	_content.add_child(back)
	# Reserve space for the vertical scrollbar in short/narrow windows.
	root.resized.connect(func(): panel.custom_minimum_size.x = minf(720,maxf(0,root.size.x-80)))
	panel.custom_minimum_size.x = minf(720,maxf(0,get_viewport().get_visible_rect().size.x-80))
	save.grab_focus.call_deferred()

func _input(event: InputEvent) -> void:
	if _returning:
		return # Let the return-confirmation popup handle Esc / controller cancel.
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"task_terminal"):
		get_viewport().set_input_as_handled()

func _save_progress() -> void:
	_feedback.text = "ENDING_SAVE_OK" if SaveManager.save_current() else "ENDING_SAVE_UNAVAILABLE"

func _return_to_menu() -> void:
	if _returning:
		return
	_returning = true
	var accepted: bool = await ConfirmPopup.ask(self,tr("PAUSE_RETURN_CONFIRM"),"PAUSE_MAIN_MENU",true)
	_returning = false
	if accepted and is_inside_tree():
		SceneRouter.goto_main_menu()
