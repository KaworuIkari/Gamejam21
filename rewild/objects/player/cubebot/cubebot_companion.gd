class_name CubeBotCompanion
extends CharacterBody3D
## Companion brain that drives a CubeBot on the navmesh.
## Per physics frame: gravity, nav steering, facing, ground transitions. Nothing else.
## Decisions (mode, gait, mood, jumps, look targets) run in _think() on a jittered
## 0.3–0.6 s tick, which also doubles as a natural reaction delay.
##
## Scene:
##   CubeBotCompanion (CharacterBody3D, this script)
##   ├─ CollisionShape3D
##   ├─ NavigationAgent3D   (path_desired_distance ~0.5, target_desired_distance ~0.6)
##   └─ CubeBot             (cubebot.tscn; rotate it 180° if the bot walks backwards)

enum Mode { FOLLOW, ORBIT, IDLE, WANDER, INVESTIGATE, REST }
enum Gait { IDLE, WALK, RUN }

const GAIT_ANIM: Array[StringName] = [&"Idle", &"Walk", &"Run"]
const COYOTE := 0.15        ## airborne this long before Fall plays (steps, ramps)
const HARD_LANDING := 0.35  ## airborne longer than this plays Land

#######################
# A chicken would do WorldEvents.report(global_position, &"chicken", 0.8), and so on.
# Autoloads are statically typed in Godot 4, so VSCode catches typos in report and happened.
# The “not every time” part is handled on the listener side, in _on_world_event:
# the event must be within notice_radius
# a 4 s cooldown since the last investigation
# a roll of interest × curiosity
# it’s ignored while tired or already investigating
# The bus also covers your “enabled after a certain event” requirement. Set wake_on = &"cubebot_wake"
# in the inspector and have whatever trigger report that kind. Or just set companion.active = true from level code.
#######################

## Off until something switches it on: set it from code, or report `wake_on` to WorldEvents.
@export var active := false:
	set(v):
		active = v
		if is_node_ready():
			_set_active(v)
## If set, a WorldEvents report of this kind switches the bot on.
@export var wake_on: StringName = &""
## Optional. Otherwise looked up as %LIRA in the current scene on activation.
@onready var lira: LIRA_Character = get_tree().get_first_node_in_group("player")

@export_group("Movement")
@export var walk_speed := 1.6
@export var run_speed := 4.8
@export var accel := 14.0
@export var turn_speed := 8.0
@export var jump_velocity := 4.5

@export_group("Personality")
@export var follow_distance := 2.2
## Beyond this distance from LIRA it drops whatever it's doing and catches up.
@export var leash := 14.0
## Following but not getting closer for this long (e.g. a wall the navmesh does not know):
## hop over to LIRA instead.
@export var stuck_time := 1.5
@export var catch_up_height := 3.0
## LIRA counts as running above this horizontal speed.
@export var lira_run_speed := 3.0
@export_range(0.0, 1.0) var jump_chance := 0.08  ## per think tick while running
@export_range(0.0, 1.0) var curiosity := 0.6
@export var notice_radius := 18.0
@export var stamina_drain := 0.12  ## per second of running; full tank = 1
@export var stamina_regen := 0.1

@onready var _bot: CubeBot = $CubeBot
@onready var _nav: NavigationAgent3D = $NavigationAgent3D
@onready var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
@onready var _base_emission: float = _bot.eye_emission

var _mode := Mode.FOLLOW
var _mode_t := 0.0          # seconds left in the current mode
var _gait := Gait.IDLE
var _speed := 0.0
var _stamina := 1.0
var _tired := false
var _lazy := false          # sometimes walks even when LIRA runs
var _side := 0.0            # lateral follow offset, rerolled per FOLLOW
var _orbit_a := 0.0
var _orbit_dir := 1.0
var _focus := Vector3.ZERO  # last interesting event position
var _noticed := false       # saw an event, will go on the next think tick
var _yaw_goal := 0.0
var _mood_v := -1.0
var _think_t := 0.0
var _think_dt := 0.0
var _air_t := 0.0
var _anim := &""
var _anim_lock := false     # a one-shot (Jump_Start / Land) is playing
var _last_curious_ms := -100000
var _stuck_t := 0.0
var _progress_from := Vector3.ZERO
var _catching := false      # mid catch-up hop

# teleportation for separate nav mesh
@export var teleport_cooldown := 1.5
var _teleport_cd := 0.0

func _ready() -> void:
	_yaw_goal = rotation.y
	_bot.animation_finished.connect(_on_anim_finished)
	WorldEvents.happened.connect(_on_world_event)
	_set_active(active)


# --- per frame: only movement and ground transitions ------------------------

func _physics_process(delta: float) -> void:
	if _catching:
		return
	_think_t -= delta
	if _think_t <= 0.0:
		_think()
	if _check_stuck(delta):
		return

	var v := velocity
	if is_on_floor():
		if _air_t > 0.0:
			_on_landed()
	else:
		v.y -= _gravity * delta
		_air_t += delta
		if _air_t > COYOTE and not _anim_lock and _anim != &"Fall":
			_play(&"Fall")

	var want := Vector3.ZERO
	if _speed > 0.0:
		if _nav.is_navigation_finished():
			_arrived()
		else:
			# must be polled every physics frame for the agent to advance along its path
			var to := _nav.get_next_path_position() - global_position
			to.y = 0.0
			want = to.normalized() * _speed

	var a := accel if _air_t == 0.0 else accel * 0.3
	var h := Vector3(v.x, 0.0, v.z).move_toward(want, a * delta)
	if h.length_squared() > 0.25:
		_yaw_goal = atan2(h.x, h.z)
	rotation.y = lerp_angle(rotation.y, _yaw_goal, minf(turn_speed * delta, 1.0))

	velocity = Vector3(h.x, v.y, h.z)
	move_and_slide()


# --- decisions: a few times per second --------------------------------------

func _think() -> void:
	var dt := _think_dt
	_think_dt = randf_range(0.3, 0.6)
	_think_t = _think_dt
	_mode_t -= dt

	_teleport_cd -= dt

	if _gait == Gait.RUN:
		_stamina -= stamina_drain * dt
		if _stamina <= 0.0:
			_stamina = 0.0
			_tired = true
			_enter(Mode.REST)
			return
	else:
		_stamina = minf(_stamina + stamina_regen * dt, 1.0)
		if _tired and _stamina > 0.5:
			_tired = false
			_dim(false)

	if _noticed:
		_noticed = false
		_enter(Mode.INVESTIGATE)
		return

	var lp := lira.global_position
	var lv := lira.velocity
	lv.y = 0.0
	var l_speed2 := lv.length_squared()
	var off := lp - global_position
	off.y = 0.0
	var d2 := off.length_squared()

	if not _can_reach(lp):
		if _mode != Mode.FOLLOW:
			_enter(Mode.FOLLOW)
		var close := follow_distance + 0.8
		if (d2 > close * close or absf(lp.y - global_position.y) > 1.5) and _teleport_cd <= 0.0:
			_teleport_to_lira()
		else:
			_set_gait(Gait.IDLE)  # speed 0, so the agent is never polled for a dead path
			_yaw_goal = _yaw_to(lp)
		return

	if d2 > leash * leash and _mode != Mode.FOLLOW:
		_enter(Mode.FOLLOW)

	match _mode:
		Mode.FOLLOW:
			_think_follow(lp, lv, l_speed2, d2)
		Mode.ORBIT:
			if l_speed2 > 1.0 or _mode_t <= 0.0:
				_enter(Mode.FOLLOW)
		Mode.IDLE:
			var far := follow_distance * 2.5
			if d2 > far * far or _mode_t <= 0.0:
				_enter(Mode.FOLLOW)
			elif randf() < 0.15:
				_pick_look()
		Mode.WANDER:
			if _mode_t <= 0.0 or l_speed2 > lira_run_speed * lira_run_speed:
				_enter(Mode.FOLLOW)
		Mode.INVESTIGATE, Mode.REST:
			if _mode_t <= 0.0:
				_enter(Mode.FOLLOW)
			elif _mode == Mode.REST and randf() < 0.2:
				_pick_look()

	_try_jump()


func _think_follow(lp: Vector3, lv: Vector3, l_speed2: float, d2: float) -> void:
	var lira_runs := l_speed2 > lira_run_speed * lira_run_speed
	var close := follow_distance + 0.8
	if randf() < 0.05:
		_lazy = not _lazy

	var goal: Vector3
	if l_speed2 > 0.25:
		var fwd := lv.normalized()
		goal = lp - fwd * follow_distance + Vector3(-fwd.z, 0.0, fwd.x) * _side
	else:
		var away := global_position - lp
		away.y = 0.0
		goal = lp + away.normalized() * follow_distance

	if d2 > 36.0 or (lira_runs and not _lazy):
		_go(goal, Gait.RUN)
	elif d2 < close * close and l_speed2 < 0.25:
		_set_gait(Gait.IDLE)
		_yaw_goal = _yaw_to(lp)
	else:
		_go(goal, Gait.WALK)
	_mood(0.5 if lira_runs else 0.15)

	# LIRA has stopped and we're beside her: do something less rigid
	if l_speed2 < 0.25 and d2 < close * close and _mode_t <= 0.0:
		var r := randf()
		if r < 0.35:
			_enter(Mode.ORBIT)
		elif r < 0.8:
			_enter(Mode.IDLE)
		else:
			_enter(Mode.WANDER)


func _enter(m: Mode) -> void:
	_mode = m
	match m:
		Mode.FOLLOW:
			_mode_t = randf_range(2.0, 5.0)  # minimum time before idling about
			_lazy = randf() < 0.2
			_side = randf_range(-1.2, 1.2)
		Mode.ORBIT:
			_mode_t = randf_range(4.0, 9.0)
			var off := global_position - lira.global_position
			_orbit_a = atan2(off.z, off.x)
			_orbit_dir = 1.0 if randf() < 0.5 else -1.0
			_set_gait(Gait.WALK)
			_orbit_step()
			_mood(0.35)
		Mode.IDLE:
			_mode_t = randf_range(2.0, 5.0)
			_set_gait(Gait.IDLE)
			_pick_look()
			_mood(0.0)
		Mode.WANDER:
			_mode_t = 8.0  # give-up timer
			var ang := randf() * TAU
			_go(lira.global_position + Vector3(cos(ang), 0.0, sin(ang)) * randf_range(3.0, 7.0), Gait.WALK)
			_mood(0.25)
		Mode.INVESTIGATE:
			_mode_t = 10.0
			var away := global_position - _focus
			away.y = 0.0
			_go(_focus + away.normalized() * 1.5, Gait.RUN)
			_mood(1.0)
		Mode.REST:
			_mode_t = randf_range(1.5, 3.0)
			_set_gait(Gait.IDLE)
			_mood(0.0)
			_dim(true)


## Called (from _physics_process) once the nav target is reached.
func _arrived() -> void:
	match _mode:
		Mode.ORBIT:
			if randf() < 0.15:
				_enter(Mode.IDLE)  # pause mid-circle
			else:
				_orbit_step()
		Mode.INVESTIGATE:
			_enter(Mode.IDLE)
			_mode_t = randf_range(2.5, 4.5)
			_yaw_goal = _yaw_to(_focus)
			_mood(0.8)
		Mode.WANDER:
			_enter(Mode.IDLE)
			_yaw_goal = randf() * TAU
		_:
			_set_gait(Gait.IDLE)


func _orbit_step() -> void:
	_orbit_a += _orbit_dir * 0.6
	_nav.target_position = lira.global_position \
			+ Vector3(cos(_orbit_a), 0.0, sin(_orbit_a)) * follow_distance * 1.3


func _try_jump() -> void:
	if _gait != Gait.RUN or _air_t > 0.0 or _anim_lock or _stamina < 0.3:
		return
	if randf() > jump_chance:
		return
	velocity.y = jump_velocity
	_stamina -= 0.1
	_anim_lock = true
	_play(&"Jump_Start", 0.05)


# --- events -----------------------------------------------------------------

func _on_world_event(pos: Vector3, kind: StringName, interest: float) -> void:
	if not active:
		if wake_on != &"" and kind == wake_on:
			active = true
		return
	if _mode == Mode.INVESTIGATE or _noticed or _tired:
		return
	var now := Time.get_ticks_msec()
	if now - _last_curious_ms < 4000:
		return
	if global_position.distance_squared_to(pos) > notice_radius * notice_radius:
		return
	if randf() > interest * curiosity:
		return
	_last_curious_ms = now
	_focus = pos
	_noticed = true          # stop and stare now, set off on the next think tick
	_set_gait(Gait.IDLE)
	_yaw_goal = _yaw_to(pos)
	_mood(1.0)


func _on_anim_finished(n: StringName) -> void:
	_anim_lock = false
	if n == &"Jump_Start" and not is_on_floor():
		_play(&"Fall")
	else:
		_play(GAIT_ANIM[_gait])


func _on_landed() -> void:
	var hard := _air_t > HARD_LANDING
	_air_t = 0.0
	if hard:
		_anim_lock = true
		_play(&"Land", 0.05, 1.6 if _gait == Gait.RUN else 1.0)
	else:
		_anim_lock = false
		_play(GAIT_ANIM[_gait])


# --- helpers ----------------------------------------------------------------

## True when it just started a catch-up hop because following made no progress.
func _check_stuck(delta: float) -> bool:
	var far := lira != null and global_position.distance_to(lira.global_position) > follow_distance * 3.0
	if _speed <= 0.0 or not far or _mode != Mode.FOLLOW:
		_stuck_t = 0.0
		_progress_from = global_position
		return false
	if global_position.distance_to(_progress_from) > 0.5:
		_stuck_t = 0.0
		_progress_from = global_position
		return false
	_stuck_t += delta
	if _stuck_t < stuck_time:
		return false
	_catch_up()
	return true


## A big hop that lands beside LIRA, over whatever was in the way.
func _catch_up() -> void:
	_catching = true
	_stuck_t = 0.0
	velocity = Vector3.ZERO
	var from := global_position
	var side := Vector3(from.x - lira.global_position.x, 0.0, from.z - lira.global_position.z)
	side = side.normalized() if side.length() > 0.01 else Vector3.BACK
	var to := lira.global_position + side * follow_distance
	var map := _nav.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		var on_mesh := NavigationServer3D.map_get_closest_point(map, to)
		if on_mesh.distance_to(to) < follow_distance:
			to = on_mesh
	_yaw_goal = _yaw_to(to)
	rotation.y = _yaw_goal
	_anim_lock = true
	_play(&"Jump_Start", 0.05)
	var height := catch_up_height + maxf(to.y - from.y, 0.0)
	var hop := create_tween()
	hop.tween_method(func(t: float) -> void:
		global_position = from.lerp(to, t) + Vector3.UP * sin(t * PI) * height,
		0.0, 1.0, clampf(from.distance_to(to) / 8.0, 0.5, 1.5))
	await hop.finished
	_catching = false
	_air_t = 0.0
	_progress_from = global_position
	_anim_lock = true
	_play(&"Land", 0.05)


func _set_active(on: bool) -> void:
	set_physics_process(on)
	if on:
		_think_t = 0.0
		_enter(Mode.FOLLOW)
	else:
		velocity = Vector3.ZERO
		_set_gait(Gait.IDLE)


func _go(p: Vector3, g: Gait) -> void:
	_nav.target_position = p
	_set_gait(g)


func _set_gait(g: Gait) -> void:
	if g == Gait.RUN and _tired:
		g = Gait.WALK
	if g == _gait:
		return
	_gait = g
	match g:
		Gait.IDLE: _speed = 0.0
		Gait.WALK: _speed = walk_speed
		Gait.RUN: _speed = run_speed
	if not _anim_lock and _anim != &"Fall":
		_play(GAIT_ANIM[g])


func _play(a: StringName, blend := 0.15, speed := 1.0) -> void:
	if a == _anim:
		return
	_anim = a
	_bot.play(a, blend, speed)


func _mood(m: float) -> void:
	if absf(m - _mood_v) < 0.05:
		return
	_mood_v = m
	_bot.glow_to(m, 0.6)


func _dim(on: bool) -> void:
	create_tween().tween_property(_bot, ^"eye_emission", 0.8 if on else _base_emission, 0.8)


func _pick_look() -> void:
	if randf() < 0.65:
		_yaw_goal = _yaw_to(lira.global_position)
	else:
		_yaw_goal = randf() * TAU


func _yaw_to(p: Vector3) -> float:
	return atan2(p.x - global_position.x, p.z - global_position.z)

## True if a path from here ends at LIRA's spot on the mesh. A flying LIRA above a
## connected mesh counts as reachable (we project her onto the mesh), so the bot only
## teleports when the mesh is genuinely disconnected.
func _can_reach(p: Vector3) -> bool:
	var map := _nav.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return true  # map not synced yet, don't judge
	var end := NavigationServer3D.map_get_closest_point(map, p)
	var path := NavigationServer3D.map_get_path(map, global_position, end, true)
	return not path.is_empty() and path[path.size() - 1].distance_to(end) < 0.5


func _teleport_to_lira() -> void:
	_teleport_cd = teleport_cooldown
	var away := global_position - lira.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.BACK
	var map := _nav.get_navigation_map()
	var to := NavigationServer3D.map_get_closest_point(
			map, lira.global_position + away * follow_distance)
	if global_position.distance_to(to) < 1.0:
		return  # already as close as the mesh allows (LIRA is flying over a gap)
	global_position = to + Vector3.UP * 0.1
	velocity = Vector3.ZERO
	_air_t = 0.0
	_stuck_t = 0.0
	_progress_from = global_position
	_yaw_goal = _yaw_to(lira.global_position)
	rotation.y = _yaw_goal
