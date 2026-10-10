extends CharacterBody3D
class_name AnimalChicken
## Walks on the nav mesh, gets hungry and eats, then looks for the closest chicken to play
## with: they stand together, flap and sing. Wings can flap at any time, over any animation.

signal sang                                   # hook audio here later

const GROUP := &"chickens"

enum State { IDLE, WANDER, GO_EAT, EATING, GO_PLAY, PLAYING, LEAVING }

@export_group("Nodes")
@export var animation_tree: AnimationTree     # auto-found if empty
@export var agent: NavigationAgent3D          # auto-found if empty

@export_group("Movement")
@export var walk_speed := 2.5
@export var acceleration := 8.0
@export var turn_speed := 12.0
@export var move_timeout := 15.0              # give up on a path after this long
@export var model_faces_positive_z := true

@export_group("Idle")
@export var idle_time := Vector2(3.0, 8.0)    # min/max seconds standing between wanders
@export var wander_radius := 30.0

@export_group("Hunger")
@export var hunger_interval_mean := 60.0
@export var hunger_interval_dev := 10.0       # used as standard deviation
@export var eat_search_radius := 60.0
@export var eat_timeout := 8.0                # fallback if the eat state is never seen

@export_group("Play")
@export var play_search_radius := 100.0
@export var play_distance := 0.6              # how close playmates stand
@export var play_event_mean := 6.0            # seconds between flap+sing
@export var play_event_dev := 2.0
@export var play_events_to_finish := 2
@export var play_wind_down := 10.0            # after the last event: stay, no flapping, then leave
@export var crowd_radius := 2.5
@export var crowd_limit := 2                  # more than this many playing together → leave
@export var leave_distance := 6.0
@export var play_block_after := 20.0          # won't start or accept play again for this long

@export_group("Wings")
@export var flap_interval_mean := 24.0        # random flaps: exponential, this mean
@export var flap_state_name := "flap_wings"         # state inside the Wings state machine
@export var flap_anim_name := "flap_wings"          # animation in the AnimationPlayer (for its length)
@export var flap_length := 0.0                # 0 = read from the animation
@export var wings_blend_speed := 10.0
@export var wings_blend_out := 0.15

@export_group("AnimationTree Paths")
@export var wings_blend_param := "parameters/WingsBlend/blend_amount"
@export var wings_playback_param := "parameters/Wings/playback"
@export var body_playback_param := "parameters/Body/playback"
@export var eat_state_name := "eat"

# edge case
@export var fall_recover_depth := 3.0

@export_group("Debug")
@export var debug_print := false

var is_moving := false                        # Body state machine: idle <-> walk
var is_eating := false                        # Body state machine: idle -> eat (one-shot trigger)
var state := State.IDLE

var _desired_h := Vector3.ZERO
var _face_dir := Vector3.ZERO
var _timer := 0.0
var _move_timer := 0.0
var _move_elapsed := 0.0
var _hunger_timer := 0.0
var _hungry := false
var _eat_seen := false
var _playmate: AnimalChicken
var _play_event_timer := 0.0
var _play_events := 0
var _wind_down := -1.0
var _play_block := 0.0
var _replan_timer := 0.0
var _flap_timer := 0.0
var _flap_t := -1.0
var _wing_blend := 0.0
var _wings_pb: AnimationNodeStateMachinePlayback
var _body_pb: AnimationNodeStateMachinePlayback


func _ready() -> void:
	add_to_group(GROUP)
	if animation_tree == null:
		animation_tree = get_node_or_null("AnimationTree")
	if agent == null:
		agent = get_node_or_null("NavigationAgent3D")
	if animation_tree == null or agent == null:
		push_error("AnimalChicken: needs an AnimationTree and a NavigationAgent3D")
		set_physics_process(false)
		return

	_wings_pb = animation_tree.get(wings_playback_param)
	_body_pb = animation_tree.get(body_playback_param)
	_detect_flap_length()

	_hunger_timer = randf() * _next_hunger_interval()    # random hunger level at spawn
	_flap_timer = _exp(flap_interval_mean)
	_enter_idle()

func _physics_process(delta: float) -> void:
	_desired_h = Vector3.ZERO
	_face_dir = Vector3.ZERO

	_hunger_timer -= delta
	if _hunger_timer <= 0.0:
		_hungry = true
	_play_block = maxf(_play_block - delta, 0.0)

	match state:
		State.IDLE: _tick_idle(delta)
		State.WANDER: _tick_wander(delta)
		State.GO_EAT: _tick_go_eat(delta)
		State.EATING: _tick_eating(delta)
		State.GO_PLAY: _tick_go_play(delta)
		State.PLAYING: _tick_playing(delta)
		State.LEAVING: _tick_leaving(delta)

	_apply_motion(delta)
	_face(delta)
	_update_wings(delta)


# --- states ------------------------------------------------------------------

func _tick_idle(delta: float) -> void:
	if not _nav_ready():
		return
	if _hungry:
		_go_to(_random_nav_point(global_position, eat_search_radius), State.GO_EAT)
		return
	_timer -= delta
	if _timer <= 0.0:
		_go_to(_random_nav_point(global_position, wander_radius), State.WANDER)


func _tick_wander(delta: float) -> void:
	if _hungry:
		_go_to(_random_nav_point(global_position, eat_search_radius), State.GO_EAT)
		return
	if _follow_path(delta):
		_enter_idle()


func _tick_go_eat(delta: float) -> void:
	if _follow_path(delta):          # arrived, or gave up: a hungry chicken pecks wherever it is
		_set_state(State.EATING)
		is_eating = true
		_eat_seen = false
		_timer = eat_timeout


func _tick_eating(delta: float) -> void:
	var cur: StringName = _body_pb.get_current_node() if _body_pb else &""
	if cur == StringName(eat_state_name):
		_eat_seen = true
		is_eating = false            # consume the trigger; eat -> idle plays out At End
	elif _eat_seen:
		_finish_eating()             # back out of the eat state: done
		return
	_timer -= delta
	if _timer <= 0.0:
		_finish_eating()


func _finish_eating() -> void:
	is_eating = false
	_hungry = false
	_hunger_timer = _next_hunger_interval()
	if not _try_start_play():        # just ate: look for company
		_enter_idle()


func _tick_go_play(delta: float) -> void:
	if not _partner_ok():
		_end_play()
		return
	if _crowd_count() > crowd_limit:
		_leave_crowd()
		return
	_replan_timer -= delta
	if _replan_timer <= 0.0:
		_replan_timer = 0.5
		agent.target_position = _play_spot(_playmate)    # partner may still be shuffling
	if _follow_path(delta):
		_enter_play()


func _tick_playing(delta: float) -> void:
	if _crowd_count() > crowd_limit:
		_leave_crowd()
		return
	if not _partner_ok():
		_end_play()
		return
	_face_dir = _playmate.global_position - global_position

	if _wind_down >= 0.0:            # last event done: hang around quietly, no flapping
		_wind_down -= delta
		if _wind_down <= 0.0:
			_end_play()
		return

	# Wait for the partner to actually arrive before the show starts
	if global_position.distance_to(_playmate.global_position) > play_distance * 2.5:
		return
	_play_event_timer -= delta
	if _play_event_timer <= 0.0:
		_flap()
		_sing()
		_play_events += 1
		if _play_events >= play_events_to_finish:
			_wind_down = play_wind_down
		else:
			_play_event_timer = _play_interval()


func _tick_leaving(delta: float) -> void:
	if _follow_path(delta):
		_enter_idle()


func _enter_idle() -> void:
	_timer = randf_range(idle_time.x, idle_time.y)
	_set_state(State.IDLE)


func _set_state(s: State) -> void:
	if s == state:
		return
	state = s
	if debug_print:
		print("[%s] %s" % [name, State.keys()[s]])


# --- play --------------------------------------------------------------------

## Whether this chicken is available to play with `other`.
func can_play_with(_other: AnimalChicken) -> bool:
	return _play_block <= 0.0 and not _hungry and state in [State.IDLE, State.WANDER, State.PLAYING]


## Called by another chicken that wants to play. Returns true if accepted.
func request_play(from: AnimalChicken) -> bool:
	if not can_play_with(from):
		return false
	if state != State.PLAYING:       # already playing: the newcomer just joins
		_playmate = from
		_enter_play()
	return true


func _try_start_play() -> bool:
	if _play_block > 0.0:
		return false
	var best: AnimalChicken = null
	var best_d := play_search_radius
	for n in get_tree().get_nodes_in_group(GROUP):
		var c := n as AnimalChicken
		if c == null or c == self or not c.can_play_with(self):
			continue
		var d := global_position.distance_to(c.global_position)
		if d < best_d:
			best_d = d
			best = c
	if best and best.request_play(self):
		_playmate = best
		_replan_timer = 0.5
		_go_to(_play_spot(best), State.GO_PLAY)
		return true
	return false


func _enter_play() -> void:
	agent.target_position = global_position
	_play_events = 0
	_wind_down = -1.0
	_play_event_timer = _play_interval()
	_set_state(State.PLAYING)


func _end_play() -> void:
	_playmate = null
	_wind_down = -1.0
	_play_block = play_block_after
	_enter_idle()


func _partner_ok() -> bool:
	return is_instance_valid(_playmate) and _playmate.state in [State.GO_PLAY, State.PLAYING]


func _crowd_count() -> int:
	var count := 0
	for n in get_tree().get_nodes_in_group(GROUP):
		var c := n as AnimalChicken
		if c and c.state in [State.GO_PLAY, State.PLAYING] \
				and c.global_position.distance_to(global_position) <= crowd_radius:
			count += 1               # includes self
	return count


func _leave_crowd() -> void:
	var center := Vector3.ZERO
	var count := 0
	for n in get_tree().get_nodes_in_group(GROUP):
		var c := n as AnimalChicken
		if c and c.state in [State.GO_PLAY, State.PLAYING] \
				and c.global_position.distance_to(global_position) <= crowd_radius:
			center += c.global_position
			count += 1
	center /= maxf(count, 1)
	var away := global_position - center
	away.y = 0.0
	if away.length() < 0.05:
		away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	_playmate = null
	_wind_down = -1.0
	_play_block = play_block_after
	var target := _closest_nav_point(global_position + away.normalized() * leave_distance)
	_go_to(target, State.LEAVING)


func _play_spot(other: AnimalChicken) -> Vector3:
	var dir := global_position - other.global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	return _closest_nav_point(other.global_position + dir.normalized() * play_distance)


func _sing() -> void:
	# TODO: play a cluck/song AudioStreamPlayer3D once the asset exists
	sang.emit()
	if debug_print:
		print("[%s] ♪ bawk ♪" % name)


# --- wings -------------------------------------------------------------------

func _update_wings(delta: float) -> void:
	_flap_timer -= delta
	if _flap_timer <= 0.0:
		_flap_timer = _exp(flap_interval_mean)
		_flap()                      # silently skipped if suppressed or already flapping

	if _flap_t >= 0.0:
		_flap_t += delta
		if _flap_t >= flap_length:
			_flap_t = -1.0

	var target := 1.0 if _flap_t >= 0.0 and _flap_t < flap_length - wings_blend_out else 0.0
	_wing_blend = lerpf(_wing_blend, target, 1.0 - exp(-wings_blend_speed * delta))
	animation_tree.set(wings_blend_param, _wing_blend)


func _flap() -> void:
	if _flap_t >= 0.0:
		return
	if state == State.PLAYING and _wind_down >= 0.0:
		return                       # quiet period after the play show
	_flap_t = 0.0
	if _wings_pb:
		_wings_pb.start(flap_state_name, true)


func _detect_flap_length() -> void:
	if flap_length > 0.0:
		return
	var ap := animation_tree.get_node_or_null(animation_tree.anim_player) as AnimationPlayer
	if ap:
		for anim_name in ap.get_animation_list():
			if anim_name == flap_anim_name or String(anim_name).ends_with("/" + flap_anim_name):
				flap_length = ap.get_animation(anim_name).length
				return
	flap_length = 1.0
	push_warning("AnimalChicken: '%s' not found, using flap_length 1.0s" % flap_anim_name)


# --- movement ----------------------------------------------------------------

func _go_to(point: Vector3, s: State) -> void:
	agent.target_position = point
	_move_timer = move_timeout
	_move_elapsed = 0.0
	_set_state(s)


## Steers along the agent path. Returns true when arrived (or timed out).
func _follow_path(delta: float) -> bool:
	_move_elapsed += delta
	_move_timer -= delta
	if _move_timer <= 0.0:
		return true
	if _move_elapsed > 0.1 and agent.is_navigation_finished():   # grace: path needs a frame
		return true
	var to := agent.get_next_path_position() - global_position
	to.y = 0.0
	if to.length() < 0.05:
		# Standing on the current waypoint (it's just above/below us): aim at the following one
		var path := agent.get_current_navigation_path()
		var idx := agent.get_current_navigation_path_index() + 1
		if idx < path.size():
			to = path[idx] - global_position
			to.y = 0.0
	if to.length() > 0.05:
		_desired_h = to.normalized() * walk_speed
	return false


func _apply_motion(delta: float) -> void:
	var h := Vector3(velocity.x, 0.0, velocity.z).move_toward(_desired_h, acceleration * delta)
	velocity.x = h.x
	velocity.z = h.z
	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity += get_gravity() * delta
	move_and_slide()
	_fall_guard()
	is_moving = h.length() > 0.15
	if _face_dir == Vector3.ZERO and h.length() > 0.1:
		_face_dir = h


func _face(delta: float) -> void:
	var d := Vector3(_face_dir.x, 0.0, _face_dir.z)
	if d.length() < 0.01:
		return
	var yaw := atan2(d.x, d.z) if model_faces_positive_z else atan2(-d.x, -d.z)
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-turn_speed * delta))


# --- navigation & random helpers ----------------------------------------------

func _nav_ready() -> bool:
	return NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) > 0


func _closest_nav_point(p: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(agent.get_navigation_map(), p)


func _random_nav_point(center: Vector3, radius: float) -> Vector3:
	var a := randf() * TAU
	var r := sqrt(randf()) * radius
	return _closest_nav_point(center + Vector3(cos(a) * r, 0.0, sin(a) * r))


func _exp(mean: float) -> float:
	return -mean * log(1.0 - randf())          # exponential: memoryless "could happen any time"


func _next_hunger_interval() -> float:
	return maxf(randfn(hunger_interval_mean, hunger_interval_dev), 10.0)


func _play_interval() -> float:
	return maxf(randfn(play_event_mean, play_event_dev), 1.0)

func _fall_guard() -> void:
	var p := NavigationServer3D.map_get_closest_point(agent.get_navigation_map(), global_position)
	if p != Vector3.ZERO and global_position.y < p.y - fall_recover_depth:
		global_position = p + Vector3.UP * 0.5
		velocity = Vector3.ZERO