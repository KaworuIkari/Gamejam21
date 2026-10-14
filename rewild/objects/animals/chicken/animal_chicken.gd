extends CharacterBody3D
class_name AnimalChicken
## IDLE ⇄ WANDER (curvy loops)
## hungry → GO_EAT (zig-zag, may stop early) → EATING → look for a playmate
## GO_PLAY → PLAYING (stand together, flap + sing, quiet wind-down) → IDLE
## more than `crowd_limit` playing together → LEAVING → IDLE
## Wings flap at random over any animation, except during the play wind-down.

signal sang  # hook audio here later

const GROUP := &"chickens"
enum State { IDLE, WANDER, GO_EAT, EATING, GO_PLAY, PLAYING, LEAVING }
const PLAY_STATES := [State.GO_PLAY, State.PLAYING]

@export_group("Nodes")
@export var animation_tree: AnimationTree  # auto-found if empty
@export var agent: NavigationAgent3D  # auto-found if empty

@export_group("Movement")
@export var walk_speed := 2.5
@export var acceleration := 8.0
@export var turn_speed := 12.0  # body yaw toward facing direction
@export var max_turn_rate := 5.0  # rad/s heading change while walking; lower = wider curves
@export var waypoint_radius := 0.5
@export var move_timeout := 15.0  # give up on a route leg after this long
@export var fall_recover_depth := 3.0
@export var model_faces_positive_z := true

@export_group("Idle & Wander")
@export var idle_time := Vector2(3.0, 8.0)
@export var wander_radius := 30.0  # fallback when no arc fits
@export var arc_radius := Vector2(1.5, 4.0)
@export var arc_sweep_deg := Vector2(90.0, 330.0)  # >270° ≈ a full loop
@export var arc_step_deg := 30.0

@export_group("Hunger & Foraging")
@export var hunger_interval_mean := 60.0
@export var hunger_interval_dev := 10.0  # standard deviation
@export var eat_search_radius := 60.0
@export var eat_timeout := 8.0  # fallback if the eat state is never seen
@export var zigzag_step := 1.2
@export var zigzag_width := Vector2(0.4, 1.0)
@export var find_food_chance := 0.15  # per zig-zag corner: stop dead and eat there

@export_group("Play")
@export var play_search_radius := 100.0
@export var play_distance := 0.6
@export var play_event_mean := 6.0
@export var play_event_dev := 2.0
@export var play_events_to_finish := 2
@export var play_wind_down := 10.0
@export var crowd_radius := 2.5
@export var crowd_limit := 2
@export var leave_distance := 6.0
@export var play_block_after := 20.0

@export_group("Wings")
@export var flap_interval_mean := 24.0
@export var flap_state_name := "flap_wings"
@export var flap_anim_name := "flap_wings"
@export var flap_length := 0.0  # 0 = read from the animation
@export var wings_blend_speed := 10.0
@export var wings_blend_out := 0.15

@export_group("AnimationTree Paths")
@export var wings_blend_param := "parameters/WingsBlend/blend_amount"
@export var wings_playback_param := "parameters/Wings/playback"
@export var body_playback_param := "parameters/Body/playback"
@export var eat_state_name := "eat"

@export_group("Debug")
@export var debug := true

@onready var debug_label: Label3D = get_node_or_null("DebugLabel3D")

var is_moving := false  # Body state machine: idle ⇄ walk
var is_eating := false  # Body state machine: idle → eat (one-shot trigger)
var state := State.IDLE

var _route := PackedVector3Array()
var _route_i := 0
var _leg_time := 0.0
var _waypoint_reached := false  # true on the frame a route corner is passed
var _desired_h := Vector3.ZERO
var _heading := Vector3.ZERO
var _face_dir := Vector3.ZERO

var _timer := 0.0  # idle wait / eat timeout / play wind-down
var _eat_seen := false
var _playmate: AnimalChicken
var _play_events := 0
var _play_event_timer := 0.0
var _winding_down := false
var _replan_timer := 0.0
var _play_block := 0.0

var _hungry := false
var _hunger_timer := 0.0
var _hunger_interval := 60.0

var _flap_timer := 0.0
var _flap_t := -1.0  # time into the current flap; -1 = not flapping
var _wing_blend := 0.0
var _wings_pb: AnimationNodeStateMachinePlayback
var _body_pb: AnimationNodeStateMachinePlayback

# optimize process
var _slow_tick_timer := 0.0
const SLOW_TICK_INTERVAL := 3.0

# === Lifecycle ===

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
	_reset_hunger(true)
	_flap_timer = _exp(flap_interval_mean)
	if debug_label:
		debug_label.no_depth_test = true
	_enter_idle()

func _physics_process(delta: float) -> void:
		_desired_h = Vector3.ZERO
		_face_dir = Vector3.ZERO
		_hunger_timer -= delta
		_hungry = _hungry or _hunger_timer <= 0.0
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
		_update_casual_sing(delta)
		_update_debug_label()
		
		_slow_tick_timer += delta
		if _slow_tick_timer >= SLOW_TICK_INTERVAL:
			_slow_tick_timer = 0.0
			_fall_guard()

# === States ===

func _enter_idle() -> void:
	_timer = randf_range(idle_time.x, idle_time.y)
	state = State.IDLE

func _tick_idle(delta: float) -> void:
	if not _nav_ready():
		return
	if _hungry:
		_enter_go_eat()
		return
	_timer -= delta
	if _timer <= 0.0:
		var arc := _arc_route()
		if arc.is_empty():
			arc.append(_random_nav_point(global_position, wander_radius))
		_set_route(arc)
		state = State.WANDER

func _tick_wander(delta: float) -> void:
	if _hungry:
		_enter_go_eat()
	elif _follow_route(delta):
		_enter_idle()

func _enter_go_eat() -> void:
	_set_route(_zigzag_route(_random_nav_point(global_position, eat_search_radius)))
	state = State.GO_EAT

func _tick_go_eat(delta: float) -> void:
	if _follow_route(delta):
		_enter_eating()
	elif _waypoint_reached and randf() < find_food_chance:
		_stop_now()  # spotted something: stop dead and peck here
		_enter_eating()

func _enter_eating() -> void:
	is_eating = true
	_eat_seen = false
	_timer = eat_timeout
	state = State.EATING

func _tick_eating(delta: float) -> void:
	var in_eat := _body_pb != null and _body_pb.get_current_node() == StringName(eat_state_name)
	if in_eat:
		_eat_seen = true
		is_eating = false  # consume the trigger; eat → idle plays out At End
	_timer -= delta
	if (_eat_seen and not in_eat) or _timer <= 0.0:
		is_eating = false
		_reset_hunger()
		if not _try_start_play():  # just ate: look for company
			_enter_idle()

func _enter_go_play(partner: AnimalChicken) -> void:
	_playmate = partner
	_replan_timer = 0.5
	_set_route(PackedVector3Array([_play_spot(partner)]))
	state = State.GO_PLAY

func _tick_go_play(delta: float) -> void:
	if _abandon_play_if_needed():
		return
	_replan_timer -= delta
	if _replan_timer <= 0.0:  # partner may still be shuffling
		_replan_timer = 0.5
		_route[0] = _play_spot(_playmate)
		agent.target_position = _route[0]
	if _follow_route(delta):
		_enter_playing(_playmate)

func _enter_playing(partner: AnimalChicken) -> void:
	_playmate = partner
	_play_events = 0
	_winding_down = false
	_play_event_timer = _play_interval()
	agent.target_position = global_position
	state = State.PLAYING

func _tick_playing(delta: float) -> void:
	if _abandon_play_if_needed():
		return
	var nearest := _closest_chicken()
	_face_dir = (nearest if nearest else _playmate).global_position - global_position
	if _winding_down:  # show is over: stay quietly, no flapping
		_timer -= delta
		if _timer <= 0.0:
			_clear_play()
			_enter_idle()
		return
	if global_position.distance_to(_playmate.global_position) > play_distance * 2.5:
		return  # wait for the partner to arrive
	_play_event_timer -= delta
	if _play_event_timer > 0.0:
		return
	_flap()
	_sing()
	_play_events += 1
	if _play_events >= play_events_to_finish:
		_winding_down = true
		_timer = play_wind_down
	else:
		_play_event_timer = _play_interval()

func _enter_leaving() -> void:
	var crowd := _playing_neighbors()
	var center := Vector3.ZERO
	for c in crowd:
		center += c.global_position
	center /= maxf(crowd.size(), 1)
	var away := global_position - center
	away.y = 0.0
	if away.length() < 0.05:
		away = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	_clear_play()
	_set_route(PackedVector3Array([_closest_nav_point(global_position + away.normalized() * leave_distance)]))
	state = State.LEAVING

func _tick_leaving(delta: float) -> void:
	if _follow_route(delta):
		_enter_idle()

# === Play ===

## Public: whether this chicken can play right now.
func can_play_with(_other: AnimalChicken) -> bool:
	return _play_block <= 0.0 and not _hungry and state in [State.IDLE, State.WANDER, State.PLAYING]

## Public: another chicken asks to play. Returns true if accepted.
func request_play(from: AnimalChicken) -> bool:
	if not can_play_with(from):
		return false
	if state != State.PLAYING:  # already playing: the newcomer just joins
		_enter_playing(from)
	return true

func _try_start_play() -> bool:
	if _play_block > 0.0:
		return false
	var best: AnimalChicken = null
	var best_d := play_search_radius
	for c in _other_chickens():
		var d := global_position.distance_to(c.global_position)
		if d < best_d and c.can_play_with(self):
			best_d = d
			best = c
	if best and best.request_play(self):
		_enter_go_play(best)
		return true
	return false

## Shared checks for GO_PLAY and PLAYING. Returns true if play was abandoned.
func _abandon_play_if_needed() -> bool:
	if _playing_neighbors().size() > crowd_limit:
		_enter_leaving()
		return true
	if not (is_instance_valid(_playmate) and _playmate.state in PLAY_STATES):
		_clear_play()
		_enter_idle()
		return true
	return false

func _clear_play() -> void:
	_playmate = null
	_winding_down = false
	_play_block = play_block_after

func _play_spot(other: AnimalChicken) -> Vector3:
	var dir := global_position - other.global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		dir = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	return _closest_nav_point(other.global_position + dir.normalized() * play_distance)

## singing
@onready var sound_emitter : FmodEventEmitter3D = $chicken_anim1/wil_chicken_01/Skeleton3D/wil_chicken_01_001/Sing
@onready var sound_emitter2 : FmodEventEmitter3D = $chicken_anim1/wil_chicken_01/Skeleton3D/wil_chicken_01_001/Sing2

@export_group("Casual Singing")
@export var casual_sing_radius := 12.0
@export_range(0.0, 1.0) var casual_sing_chance := 0.6
@onready var _player = get_tree().get_first_node_in_group("player") as LIRA_Character
var _greeted := false

func _sing() -> void:
	sound_emitter.play()
	WorldEvents.report(global_position, &"chicken", 1.0)

func _sing2() -> void:
	sound_emitter2.play()
	WorldEvents.report(global_position, &"chicken", 0.1)

func _update_casual_sing(_delta: float) -> void:
	if _greeted and global_position.distance_squared_to(_player.global_position) > 900.0:
		_greeted = false
	if _greeted:
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	if global_position.distance_squared_to(_player.global_position) > casual_sing_radius * casual_sing_radius:
		return
	_greeted = true  # the roll is spent whether or not it sings, like Minecraft's first-notice sound
	if randf() < casual_sing_chance:
		_sing2()

func _other_chickens() -> Array[AnimalChicken]:
	var out: Array[AnimalChicken] = []
	for n in get_tree().get_nodes_in_group(GROUP):
		if n != self and n is AnimalChicken:
			out.append(n)
	return out

func _closest_chicken() -> AnimalChicken:
	var best: AnimalChicken = null
	var best_d := INF
	for c in _other_chickens():
		var d := global_position.distance_squared_to(c.global_position)
		if d < best_d:
			best_d = d
			best = c
	return best

## Chickens (including self) going to or playing within crowd_radius.
func _playing_neighbors() -> Array[AnimalChicken]:
	var out: Array[AnimalChicken] = []
	for n in get_tree().get_nodes_in_group(GROUP):
		var c := n as AnimalChicken
		if c and c.state in PLAY_STATES and c.global_position.distance_to(global_position) <= crowd_radius:
			out.append(c)
	return out

# === Routes ===

func _set_route(points: PackedVector3Array) -> void:
	_route = points
	if _route.is_empty():
		_route.append(global_position)
	_route_i = 0
	agent.target_position = _route[0]
	_leg_time = 0.0

## Walks the route corner by corner. Returns true when the last point is reached.
func _follow_route(delta: float) -> bool:
	_waypoint_reached = false
	_leg_time += delta
	var leg_done := _leg_time >= move_timeout \
			or _flat_dist(_route[_route_i]) < waypoint_radius \
			or (_leg_time > 0.1 and agent.is_navigation_finished())  # path needs a frame to exist
	if not leg_done:
		_steer_along_path()
		return false
	_route_i += 1
	if _route_i >= _route.size():
		return true
	_waypoint_reached = true
	agent.target_position = _route[_route_i]
	_leg_time = 0.0
	return false

func _steer_along_path() -> void:
	var to := agent.get_next_path_position() - global_position
	to.y = 0.0
	if to.length() < 0.05:  # standing on the current path point (just above/below us): aim at the next
		var path := agent.get_current_navigation_path()
		var idx := agent.get_current_navigation_path_index() + 1
		if idx < path.size():
			to = path[idx] - global_position
			to.y = 0.0
	if to.length() > 0.05:
		_desired_h = to.normalized() * walk_speed

## Arc or loop curving left or right from the current heading, snapped to the nav mesh.
func _arc_route() -> PackedVector3Array:
	var pts := PackedVector3Array()
	var right := _flat_forward().cross(Vector3.UP).normalized()
	var side := 1.0 if randf() < 0.5 else -1.0
	var center := global_position + right * randf_range(arc_radius.x, arc_radius.y) * side
	var start := global_position - center
	var sweep := deg_to_rad(randf_range(arc_sweep_deg.x, arc_sweep_deg.y))
	var n := maxi(2, ceili(sweep / deg_to_rad(arc_step_deg)))
	for k in range(1, n + 1):
		var p := center + start.rotated(Vector3.UP, -side * sweep * float(k) / n)
		var q := _closest_nav_point(p)
		if Vector2(q.x - p.x, q.z - p.z).length() > 1.0:
			break  # arc runs off the nav mesh: end the route here
		pts.append(q)
	return pts

## Zig-zag toward goal: corners alternate left and right of the straight line.
func _zigzag_route(goal: Vector3) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var to := goal - global_position
	to.y = 0.0
	var dist := to.length()
	if dist > 0.1:
		var dir := to / dist
		var right := dir.cross(Vector3.UP).normalized()
		var n := maxi(1, int(dist / zigzag_step))
		var side := 1.0 if randf() < 0.5 else -1.0
		for k in range(1, n):
			var corner := global_position + dir * (dist * k / n) + right * side * randf_range(zigzag_width.x, zigzag_width.y)
			pts.append(_closest_nav_point(corner))
			side = -side
	pts.append(goal)
	return pts

# === Motion ===

func _apply_motion(delta: float) -> void:
	var cur := Vector3(velocity.x, 0.0, velocity.z)
	var target_speed := _desired_h.length()
	var h: Vector3
	if target_speed > 0.01:  # turn the heading at a limited rate, so corners become curves
		if _heading == Vector3.ZERO:
			_heading = cur.normalized() if cur.length() > 0.1 else _flat_forward()
		var angle := _heading.signed_angle_to(_desired_h / target_speed, Vector3.UP)
		_heading = _heading.rotated(Vector3.UP, clampf(angle, -max_turn_rate * delta, max_turn_rate * delta))
		var turn_slow := clampf(0.5 + 0.5 * cos(angle), 0.25, 1.0)  # slow down on sharp turns
		h = _heading * move_toward(cur.length(), target_speed * turn_slow, acceleration * delta)
	else:
		h = cur.move_toward(Vector3.ZERO, acceleration * delta)
		if h.length() < 0.05:
			_heading = Vector3.ZERO
	velocity.x = h.x
	velocity.z = h.z
	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity += get_gravity() * delta
	move_and_slide()
	is_moving = h.length() > 0.15
	if _face_dir == Vector3.ZERO and h.length() > 0.1:
		_face_dir = h

func _face(delta: float) -> void:
	var d := Vector3(_face_dir.x, 0.0, _face_dir.z)
	if d.length() < 0.01:
		return
	var yaw := atan2(d.x, d.z) if model_faces_positive_z else atan2(-d.x, -d.z)
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-turn_speed * delta))

func _stop_now() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_heading = Vector3.ZERO
	agent.target_position = global_position

func _fall_guard() -> void:
	var p := _closest_nav_point(global_position)
	if p != Vector3.ZERO and global_position.y < p.y - fall_recover_depth:
		global_position = p + Vector3.UP * 0.5
		velocity = Vector3.ZERO

# === Wings ===

func _update_wings(delta: float) -> void:
	_flap_timer -= delta
	if _flap_timer <= 0.0:
		_flap_timer = _exp(flap_interval_mean)
		_flap()
	if _flap_t >= 0.0:
		_flap_t += delta
		if _flap_t >= flap_length:
			_flap_t = -1.0
	var flapping := _flap_t >= 0.0 and _flap_t < flap_length - wings_blend_out
	_wing_blend = lerpf(_wing_blend, 1.0 if flapping else 0.0, 1.0 - exp(-wings_blend_speed * delta))
	animation_tree.set(wings_blend_param, _wing_blend)

func _flap() -> void:
	var already_flapping := _flap_t >= 0.0
	var quiet_time := state == State.PLAYING and _winding_down
	if already_flapping or quiet_time:
		return
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

# === Hunger ===

func _reset_hunger(random_start := false) -> void:
	_hungry = false
	_hunger_interval = maxf(randfn(hunger_interval_mean, hunger_interval_dev), 10.0)
	_hunger_timer = _hunger_interval * (randf() if random_start else 1.0)

## 0 = just ate, 1 = hungry.
func hunger_level() -> float:
	if _hungry:
		return 1.0
	return clampf(1.0 - _hunger_timer / maxf(_hunger_interval, 0.001), 0.0, 1.0)

# === Helpers ===

func _nav_ready() -> bool:
	return NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) > 0

func _closest_nav_point(p: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(agent.get_navigation_map(), p)

func _random_nav_point(center: Vector3, radius: float) -> Vector3:
	var a := randf() * TAU
	var r := sqrt(randf()) * radius  # uniform over the disc
	return _closest_nav_point(center + Vector3(cos(a) * r, 0.0, sin(a) * r))

func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()

func _flat_forward() -> Vector3:
	var f := global_basis.z if model_faces_positive_z else -global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 1e-3 else Vector3.FORWARD

func _exp(mean: float) -> float:
	return -mean * log(1.0 - randf())  # exponential: "could happen any time"

func _play_interval() -> float:
	return maxf(randfn(play_event_mean, play_event_dev), 1.0)

func _update_debug_label() -> void:
	if debug_label == null:
		return
	debug_label.visible = debug
	if debug:
		debug_label.text = "%s\nhunger %d%%" % [State.keys()[state], roundi(hunger_level() * 100.0)]
