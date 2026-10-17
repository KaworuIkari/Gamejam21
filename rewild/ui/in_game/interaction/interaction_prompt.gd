extends CanvasLayer
## Shared presentation; owners control availability, progress and accepted activation.
const LightUI = preload("res://ui/theme/light/light_ui.gd")
const ProgressOutline = preload("res://ui/in_game/interaction/interaction_progress.gd")
const COMPLETE_DURATION := 0.15
## Enabled only by clear_hold_prompt.tscn; tap prompts keep their original layout.
@export var hold_to_clear := false

@onready var _root: Control = $Root
@onready var _panel: PanelContainer = $Root/Anchor/Panel
@onready var _before: Label = $Root/Anchor/Panel/Row/Before
@onready var _key_box: PanelContainer = $Root/Anchor/Panel/Row/Key
@onready var _key: Label = $Root/Anchor/Panel/Row/Key/Label
@onready var _after: Label = $Root/Anchor/Panel/Row/After

var _available := false
var _interactable := true
var _action: StringName = &"interact"
var _message_key := "DLG_TALK_PROMPT"
var _device_kind := "kbm"
var _press_amount := 0.0
var _press_linger := 0.0
var _complete_remaining := 0.0
var _hold_progress := 0.0
var _key_style: StyleBoxFlat
var _outline: Control
var _hold_bar: ProgressBar

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_viewport = get_tree().root
	LightUI.apply(_root)
	_panel.add_theme_stylebox_override("panel", LightUI.surface(Color(1,0.99,0.95,0.12), Color(1,1,0.97,0.65),20,24,14))
	LightUI.frost(_panel)
	_key_style = LightUI.surface(Color(1,0.88,0.59,0.38),Color(0.94,0.77,0.39,0.65),10,12,4)
	_key_box.add_theme_stylebox_override("panel", _key_style)
	# A plain Node wrapper prevents PanelContainer from treating the outline as content.
	var wrapper := Node.new()
	wrapper.name = "FeedbackOverlay"
	_key_box.add_child(wrapper)
	_outline = ProgressOutline.new()
	_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(_outline)
	_key_box.resized.connect(_resize_outline)
	_resize_outline()
	if hold_to_clear:
		_build_hold_layout()
	var settings := get_node_or_null("/root/SettingsManager")
	if settings:
		settings.bindings_changed.connect(_refresh_text)
	_refresh_text()
	_root.hide()

func configure(action: StringName, message_key: String) -> void:
	_action = action
	_message_key = message_key
	if is_node_ready():
		_refresh_text()

func set_available(available: bool) -> void:
	_available = available
	if not available:
		_hold_progress = 0.0

func set_interactable(interactable: bool) -> void:
	_interactable = interactable
	if not interactable:
		_hold_progress = 0.0

func set_hold_progress(progress: float) -> void:
	_hold_progress = clampf(progress,0,1) if _available and _interactable else 0.0

## Call only when the owner accepts player input, not for scripted activations.
func play_activation() -> void:
	_complete_remaining = COMPLETE_DURATION
	_press_amount = 1.0
	_press_linger = 0.08
	layer = 15 # Briefly above the dialogue layer, below modal menus.

func _blocked() -> bool:
	return get_tree().paused or SceneRouter.is_busy()

func _dialogue_active() -> bool:
	var dialogic := get_node_or_null("/root/Dialogic")
	return dialogic != null and dialogic.current_timeline != null

func _process(delta: float) -> void:
	if _blocked():
		layer = 5
		_complete_remaining = 0.0
		_press_linger = 0.0
		_press_amount = 0.0
		_hold_progress = 0.0
		_root.hide()
		return
	var completing := _complete_remaining > 0.0
	layer = 15 if completing else 5
	_root.visible = completing or (_available and not _dialogue_active())
	if not _root.visible:
		_press_amount = 0.0
		return
	var pressed := _interactable and _available and not _dialogue_active() and Input.is_action_pressed(_action)
	_press_linger = maxf(0,_press_linger-delta)
	var target := 1.0 if pressed or _press_linger > 0 or completing else 0.0
	_press_amount = lerpf(_press_amount,target,1.0-exp(-24.0*delta))
	_key_box.pivot_offset = _key_box.size*0.5
	_key_box.scale = Vector2.ONE * lerpf(1.0,0.9,_press_amount)
	_key_style.bg_color = Color(1,0.88,0.59,0.38).lerp(Color(1,0.78,0.28,0.95),_press_amount)
	_key_style.border_color = Color(0.94,0.77,0.39,0.65).lerp(Color(1,0.95,0.76,1),_press_amount)
	_outline.progress = 1.0 if completing else _hold_progress
	_outline.queue_redraw()
	if hold_to_clear:
		_update_hold_style(completing)
	_root.modulate.a = clampf(_complete_remaining/COMPLETE_DURATION,0,1) if completing and (not _available or _dialogue_active()) else 1.0
	_complete_remaining = maxf(0,_complete_remaining-delta)

func _input(event: InputEvent) -> void:
	var kind := _device_kind
	if event is InputEventJoypadButton and event.pressed:
		kind = "joy"
	elif event is InputEventJoypadMotion and absf(event.axis_value)>0.4:
		kind = "joy"
	elif (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		kind = "kbm"
	if kind != _device_kind:
		_device_kind = kind
		_refresh_text()
	if _available and _interactable and not _blocked() and not _dialogue_active() and not event.is_echo() and event.is_action_pressed(_action):
		_press_amount = 1.0
		_press_linger = 0.08
	# Do not consume input: the owner must still receive the same event.

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()

func _resize_outline() -> void:
	if is_instance_valid(_outline):
		_outline.size = _key_box.size
		_outline.queue_redraw()

func _refresh_text() -> void:
	var parts := tr(_message_key).split("%s",true,1)
	_before.text = parts[0].strip_edges()
	_after.text = parts[1].strip_edges() if parts.size()>1 else ""
	_before.visible = not _before.text.is_empty()
	_after.visible = not _after.text.is_empty()
	var settings := get_node_or_null("/root/SettingsManager")
	var binding: InputEvent = settings.get_binding(_action,_device_kind) if settings else null
	_key.text = settings.event_to_text(binding) if settings else "F"


func _build_hold_layout() -> void:
	# Keep the 26px labels; compact the shell instead of scaling the text.
	_panel.add_theme_stylebox_override("panel", LightUI.surface(Color(0.95,0.97,0.91,0.16), Color(1,1,0.97,0.6),18,16,10))
	_key_box.custom_minimum_size = Vector2(42,36)
	_key_style.content_margin_left = 9
	_key_style.content_margin_right = 9
	_key_style.content_margin_top = 2
	_key_style.content_margin_bottom = 2
	var row := _key_box.get_parent() as HBoxContainer
	row.add_theme_constant_override("separation",10)
	var column := VBoxContainer.new()
	column.name = "HoldColumn"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation",8)
	_panel.add_child(column)
	row.reparent(column)
	_hold_bar = ProgressBar.new()
	_hold_bar.name = "HoldProgress"
	_hold_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hold_bar.show_percentage = false
	_hold_bar.max_value = 1.0
	_hold_bar.step = 0.001
	_hold_bar.custom_minimum_size.y = 6
	_hold_bar.add_theme_stylebox_override("background",LightUI.surface(Color(0.34,0.41,0.32,0.26),Color.TRANSPARENT,3,0,0))
	_hold_bar.add_theme_stylebox_override("fill",LightUI.surface(Color(0.84,0.75,0.46,0.94),Color.TRANSPARENT,3,0,0))
	column.add_child(_hold_bar)
	_outline.hide()
	for label in [_before,_key,_after]:
		label.add_theme_color_override("font_color",LightUI.INK)
		label.add_theme_color_override("font_shadow_color",Color.TRANSPARENT)
	_update_hold_style(false)


func _update_hold_style(completing: bool) -> void:
	_key_style.bg_color = Color(0.87,0.83,0.64,0.42).lerp(Color(0.89,0.83,0.58,0.7),_press_amount)
	_key_style.border_color = Color(0.85,0.79,0.56,0.65).lerp(Color(1,0.95,0.76,0.9),_press_amount)
	_hold_bar.value = 1.0 if completing else _hold_progress
	_hold_bar.visible = _interactable or completing