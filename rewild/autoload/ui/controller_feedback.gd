extends Node
## Owns active-device tracking and rumble lifecycle; settings remain in SettingsManager.
var _feedback_device := -1
var _was_paused := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## Feedback follows the active input device, so mouse play never vibrates an idle pad.
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		_feedback_device = event.device
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.25:
		_feedback_device = event.device
	elif (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		stop()
		_feedback_device = -1


func play(weak: float, strong: float, duration: float) -> void:
	if get_tree().paused or not bool(get_parent().get_value("controls", "vibration")):
		return
	if _feedback_device in Input.get_connected_joypads():
		Input.start_joy_vibration(_feedback_device, weak, strong, duration)


func stop() -> void:
	for device in Input.get_connected_joypads():
		Input.stop_joy_vibration(device)


func _process(_delta: float) -> void:
	var paused := get_tree().paused
	if paused and not _was_paused:
		stop()
	_was_paused = paused


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		stop()


