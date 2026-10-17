extends AnimalBase
class_name AnimalCrab
## IDLE ⇄ WANDER. Walks to a random point nearby, then stands for a while.
## Only two clips are needed: idle_anim and walk_anim (defaults "idle" and "walking").

enum State { IDLE, WANDER }

@export_group("Idle & Wander")
@export var idle_time := Vector2(2.0, 6.0)
@export var wander_radius := 8.0

var state := State.IDLE

var _timer := 0.0
var _target := Vector3.ZERO
var _has_target := false


# === Lifecycle ===

func _ready() -> void:
	super._ready()
	if animation_player == null:
		push_error("AnimalCrab: assign an AnimationPlayer in the inspector")
		set_physics_process(false)
		return
	_enter_idle()


# === State machine ===

func _tick_state(delta: float) -> void:
	match state:
		State.IDLE: _tick_idle(delta)
		State.WANDER: _tick_wander(delta)


func _enter_idle() -> void:
	_has_target = false
	_timer = randf_range(idle_time.x, idle_time.y)
	state = State.IDLE


func _tick_idle(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_set_target(_random_nav_point(global_position, wander_radius))
		state = State.WANDER


func _tick_wander(delta: float) -> void:
	if not _has_target or _leg_done(delta):
		_enter_idle()
		return
	_steer_along_path(walk_speed)


# === Targets ===

func _set_target(p: Vector3) -> void:
	_target = p
	_has_target = true
	agent.target_position = p
	_begin_leg()


# === Debug ===

func _debug_text() -> String:
	var lines := "%s  %s" % [State.keys()[state], _pick_clip()]
	if _has_target:
		lines += "\ntarget %.2fm" % _flat_dist(_target)
	else:
		lines += "\nno target"
	return lines