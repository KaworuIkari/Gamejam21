extends Node
## Samples real player feedback. Presentation and binding text live in startup_hint.
const HINT = preload("res://ui/in_game/startup/startup_hint.tscn")
@export var feedback_seconds := 2.5
@export var look_radians := 0.18
@export var walk_metres := 1.5
@export var sprint_seconds := 0.8

var player: CharacterBody3D
var _hint: CanvasLayer
var _step := -1 # -1: wake-up remark; 0..3: checks; 4: pre-terminal objective.
var _confirmed := false
var _elapsed := 0.0
var _progress := 0.0
var _last_position := Vector3.ZERO
var _last_look := Vector3.ZERO
var _look_input := false
var _jump_input := false


func _ready() -> void:
	# A new-game marker prevents fresh checks being imposed on older saves/F6 runs.
	if not SaveManager.current_data.has("startup_checks"):
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	var state: Dictionary = SaveManager.current_data["startup_checks"]
	_step = clampi(int(state.get("step", -1)), -1, 4)
	_confirmed = bool(state.get("confirmed", false)) and _step >= 0 and _step < 4
	_hint = HINT.instantiate()
	add_child(_hint)
	_hint.show_step(_step, _confirmed)
	_sample_origin()


func _blocked() -> bool:
	return get_tree().paused or SceneRouter.is_busy() or player.frozen \
			or get_tree().get_first_node_in_group(&"opening_sequence") != null \
			or Dialogic.current_timeline != null


func _input(event: InputEvent) -> void:
	if _hint == null or _blocked() or _confirmed:
		return
	if _step == 0:
		if event is InputEventMouseMotion:
			_look_input = _look_input or event.relative.length_squared() > 0.0
		elif event is InputEventJoypadMotion and event.axis in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
			_look_input = _look_input or absf(event.axis_value) > 0.2
	elif _step == 2 and event.is_action_pressed(&"jump") and not event.is_echo():
		_jump_input = true


func _physics_process(delta: float) -> void:
	if _hint == null:
		return
	if Quests.terminal_unlocked():
		queue_free()
		return
	var blocked := _blocked()
	var pause_menu := get_tree().get_first_node_in_group(&"pause_menu")
	var review: bool = pause_menu != null and pause_menu.is_showing_overview() \
			and get_tree().get_first_node_in_group(&"opening_sequence") == null and not SceneRouter.is_busy()
	_hint.layer = 101 if review else 20
	_hint.set_context(not blocked or review, review)
	if blocked:
		_sample_origin()
		_look_input = false
		_jump_input = false
		return
	var movement := player.global_position - _last_position
	var look: Vector3 = player.camera_pivot.rotation
	var look_change := absf(angle_difference(_last_look.y, look.y)) + absf(look.x - _last_look.x)
	_sample_origin()
	if _step == 4:
		return
	if _step == -1 or _confirmed:
		_elapsed += delta
		if _elapsed >= feedback_seconds:
			_step += 1
			_confirmed = false
			_elapsed = 0.0
			_progress = 0.0
			_look_input = false
			_jump_input = false
			_save_state()
			_hint.show_step(_step, false)
		return
	var moved := Vector2(movement.x, movement.z).length()
	var walking := Input.get_vector(&"left", &"right", &"forward", &"backward").length_squared() > 0.0
	var passed := false
	match _step:
		0:
			if _look_input:
				_progress += look_change
			passed = _progress >= look_radians
		1:
			if walking and player.is_on_floor():
				_progress += moved
			passed = _progress >= walk_metres
		2:
			passed = _jump_input and player.is_jumping and player.velocity.y > 0.1 and not player.is_on_floor()
			if player.is_on_floor() and not Input.is_action_pressed(&"jump"):
				_jump_input = false
		3:
			# Accumulate real sprinting; floor seams and brief collisions must not reset it.
			if walking and player.is_sprinting and moved > 0.001 and Input.is_action_pressed(&"sprint"):
				_progress += delta
			passed = _progress >= sprint_seconds
	_look_input = false
	if passed:
		_confirmed = true
		_elapsed = 0.0
		_save_state()
		_hint.show_step(_step, true)


func _sample_origin() -> void:
	_last_position = player.global_position
	_last_look = player.camera_pivot.rotation


func _save_state() -> void:
	SaveManager.current_data["startup_checks"] = {"step": _step, "confirmed": _confirmed}
