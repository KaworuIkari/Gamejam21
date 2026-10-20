extends CanvasLayer
## Shared card; boundary warnings persist, while checks/objectives use a timeout.
const LightUI = preload("res://ui/theme/light/light_ui.gd")
const ROWS := {
	0: ["STARTUP_LOOK_TITLE", "STARTUP_LOOK_BODY"],
	1: ["STARTUP_WALK_TITLE", "STARTUP_WALK_BODY"],
	2: ["STARTUP_JUMP_TITLE", "STARTUP_JUMP_BODY"],
	3: ["STARTUP_SPRINT_TITLE", "STARTUP_SPRINT_BODY"],
	5: ["STARTUP_WATER_GUN_TITLE", "STARTUP_WATER_GUN_BODY"],
	6: ["STARTUP_JETPACK_TITLE", "STARTUP_JETPACK_BODY"],
}
@export var display_seconds := 10.0
@export var animation_seconds := 0.35

@onready var _root: Control = $Root
@onready var _panel: PanelContainer = %Panel
@onready var _title: Label = %Title
@onready var _body: Label = %Body
@onready var _input_label: Label = %InputHint
@onready var _status: Label = %Status
var _step := -1
var _confirmed := false
var _device := "kbm"
var _age := 0.0
var _allowed := false
var _review := false
var _shown := false
var _switching := false
var _boundary_warning := false
var _motion: Tween


func _ready() -> void:
	_root.modulate.a = 0.0
	LightUI.apply(_root)
	LightUI.frost(_panel)
	SettingsManager.bindings_changed.connect(_refresh)
	Quests.changed.connect(_on_quest_changed)
	_root.resized.connect(_resize)
	_resize()
	_refresh()


func show_step(step: int, confirmed: bool, restart := false) -> void:
	var changed := step != _step or restart
	_step = step
	_confirmed = confirmed
	if changed:
		_age = 0.0
	if not is_node_ready() or _switching or _boundary_warning:
		return
	if changed and _shown:
		_switching = true
		_animate(false)
		await _motion.finished
		_switching = false
	_refresh()


func set_boundary_warning(active: bool) -> void:
	if active == _boundary_warning:
		return
	_boundary_warning = active
	_refresh()


func set_context(allowed: bool, review: bool) -> void:
	_allowed = allowed
	_review = review


func _process(delta: float) -> void:
	if _switching:
		return
	var shown := _allowed and (_boundary_warning or _review or _age < display_seconds)
	_animate(shown)
	if shown and not _boundary_warning and not _review and not get_tree().paused:
		_age += delta


func _animate(shown: bool) -> void:
	if shown == _shown:
		return
	_shown = shown
	if _motion:
		_motion.kill()
	var above := -(_panel.position.y + maxf(_panel.size.y, _panel.get_combined_minimum_size().y) + 16.0) * _root.scale.y
	if shown and _root.modulate.a <= 0.001:
		_root.position.y = above
	_motion = create_tween().set_parallel(true)
	_motion.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT if shown else Tween.EASE_IN)
	_motion.tween_property(_root, "position:y", 0.0 if shown else above, animation_seconds)
	_motion.tween_property(_root, "modulate:a", 1.0 if shown else 0.0, animation_seconds)


func _on_quest_changed() -> void:
	if _step == 4 and not _boundary_warning and _body.text != _objective_text():
		show_step(4, false, true)


func _objective_text() -> String:
	var quest: Quest = Quests.tracked_quest()
	if quest == null:
		return ""
	var objective := Quests.step_label(quest, Quests.current_step(quest))
	return tr("STARTUP_CURRENT_TARGET") % objective


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()


func _input(event: InputEvent) -> void:
	var device := _device
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.2):
		device = "joy"
	elif event is InputEventKey or event is InputEventMouse:
		device = "kbm"
	if device != _device:
		_device = device
		_refresh()


func _refresh() -> void:
	if _boundary_warning:
		_title.text = tr("BOUNDARY_WARNING_TITLE")
		_body.text = tr("BOUNDARY_WARNING_BODY")
		_title.show()
		_input_label.hide()
		_status.hide()
		return
	var row: Array = ROWS.get(_step, ["STARTUP_INTRO_TITLE", "STARTUP_INTRO_BODY"])
	_title.text = tr(row[0])
	_body.text = _objective_text() if _step == 4 else tr(row[1])
	_body.text = _body.text.replace("\\n", "\n")
	_title.visible = _step != 4
	_status.text = tr("STARTUP_FEEDBACK_OK")
	_status.visible = _confirmed
	_input_label.visible = ROWS.has(_step)
	match _step:
		0:
			_input_label.text = tr("STARTUP_LOOK_PAD" if _device == "joy" else "STARTUP_LOOK_INPUT")
		1:
			_input_label.text = _movement_keys()
		2:
			_input_label.text = tr("STARTUP_PRESS_JUMP") % _key(&"jump")
		3:
			_input_label.text = tr("STARTUP_HOLD_SPRINT") % [_key(&"sprint"), _movement_keys()]
		5:
			_input_label.text = tr("STARTUP_WATER_GUN_INPUT") % [_key(&"use2"), _key(&"use")]
		6:
			_input_label.text = tr("STARTUP_JETPACK_INPUT") % [_key(&"jump"), _key(&"jump")]


func _key(action: StringName) -> String:
	return SettingsManager.event_to_text(SettingsManager.get_binding(action, _device))


func _movement_keys() -> String:
	if _device == "joy":
		return tr("STARTUP_MOVE_PAD")
	return " / ".join([_key(&"forward"), _key(&"left"), _key(&"backward"), _key(&"right")])


func _resize() -> void:
	_panel.custom_minimum_size.x = minf(600.0, maxf(0.0, _root.size.x - 64.0))
