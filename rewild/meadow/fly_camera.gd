extends Camera3D
## Simple free camera for looking around the meadow.
## Hold right mouse to look, WASD to move, Q/E down/up, Shift to go fast.

@export var speed: float = 8.0
@export var fast_multiplier: float = 5.0
@export var sensitivity: float = 0.003

var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	_yaw = rotation.y
	_pitch = rotation.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * sensitivity
		_pitch = clampf(_pitch - event.relative.y * sensitivity, -1.5, 1.5)
		rotation = Vector3(_pitch, _yaw, 0.0)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()


func _process(delta: float) -> void:
	var dir := Vector3(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_E)) - float(Input.is_key_pressed(KEY_Q)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
	if dir == Vector3.ZERO:
		return
	var s := speed * (fast_multiplier if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	global_position += global_transform.basis * dir.normalized() * s * delta
