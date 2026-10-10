class_name ConfirmPopup
extends CanvasLayer
## 通用确认弹窗（支持键鼠 / 手柄）
## 用法：  if await ConfirmPopup.ask(self, "确定吗？"): ...

const LightUI = preload("res://ui/theme/light/light_ui.gd")
const UILayoutRules = preload("res://ui/layout/ui_layout.gd")

signal decided(accepted: bool)

var _message: String
var _confirm_key: String
var _danger: bool
var _cancel_btn: Button
var _prev_focus: Control
var _root: Control
var _panel: PanelContainer
var _content: VBoxContainer
var _buttons: HBoxContainer


static func ask(context: Node, message: String, confirm_key := "UI_CONFIRM", danger := false) -> bool:
	var popup := ConfirmPopup.new()
	popup._message = message
	popup._confirm_key = confirm_key
	popup._danger = danger
	popup._prev_focus = context.get_viewport().gui_get_focus_owner()
	context.get_tree().root.add_child(popup)
	var result: bool = await popup.decided
	if is_instance_valid(popup._prev_focus) and popup._prev_focus.is_visible_in_tree():
		popup._prev_focus.grab_focus()
	popup.queue_free()
	return result


func _ready() -> void:
	# 高于暂停/存档页（100），低于场景切换遮罩（128）。
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS

	_root = Control.new()
	_root.name = &"ConfirmRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.name = &"Dim"
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var margin := MarginContainer.new()
	margin.name = &"SafeMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(margin)

	var center := CenterContainer.new()
	center.name = &"Center"
	margin.add_child(center)

	_panel = PanelContainer.new()
	_panel.name = &"ConfirmPanel"
	center.add_child(_panel)

	_content = VBoxContainer.new()
	_content.name = &"Content"
	_panel.add_child(_content)

	var label := Label.new()
	label.text = _message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(label)

	_buttons = HBoxContainer.new()
	_buttons.name = &"Buttons"
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_child(_buttons)

	var ok := Button.new()
	ok.text = _confirm_key
	ok.custom_minimum_size.x = 200
	if _danger:
		ok.theme_type_variation = &"DangerButton"
	ok.pressed.connect(func(): decided.emit(true))
	_buttons.add_child(ok)

	_cancel_btn = Button.new()
	_cancel_btn.text = "UI_CANCEL"
	_cancel_btn.custom_minimum_size.x = 200
	_cancel_btn.pressed.connect(func(): decided.emit(false))
	_buttons.add_child(_cancel_btn)

	# 把焦点限制在弹窗内
	for b: Button in [ok, _cancel_btn]:
		var other: Button = _cancel_btn if b == ok else ok
		b.focus_neighbor_top = b.get_path_to(b)
		b.focus_neighbor_bottom = b.get_path_to(b)
		b.focus_neighbor_left = b.get_path_to(ok)
		b.focus_neighbor_right = b.get_path_to(_cancel_btn)
		b.focus_next = b.get_path_to(other)
		b.focus_previous = b.get_path_to(other)

	# 默认聚焦“取消”，防止误操作
	_cancel_btn.grab_focus.call_deferred()
	_root.resized.connect(_update_responsive_layout)
	LightUI.apply(_root)
	LightUI.frost(_panel)
	LightUI.soften_dim(dim)
	_update_responsive_layout()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		decided.emit(false)


func _update_responsive_layout() -> void:
	var compact := UILayoutRules.is_compact(_root.size)
	var margin := 24 if compact else 96
	var metrics := UILayoutRules.settings_metrics(_root.size)
	var safe_margin := _root.get_node("SafeMargin") as MarginContainer
	safe_margin.add_theme_constant_override("margin_left", margin)
	safe_margin.add_theme_constant_override("margin_right", margin)
	safe_margin.add_theme_constant_override("margin_top", margin)
	safe_margin.add_theme_constant_override("margin_bottom", margin)
	_panel.custom_minimum_size.x = minf(640.0, maxf(0.0, _root.size.x - margin * 2.0))
	_content.add_theme_constant_override("separation", int(metrics.panel_gap))
	_buttons.add_theme_constant_override("separation", int(metrics.row_gap))
	for button in _buttons.get_children():
		(button as Button).custom_minimum_size.x = 140 if compact else 200
