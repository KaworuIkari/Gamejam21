extends CharacterBody3D
class_name AnimalFox
## IDLE ⇄ WANDER when far from the player.
## WATCH (stand still, face the player) at middle distance.
## Player too close → ALERT (bark) → AVOID, which keeps issuing fresh escape legs
## until the player is beyond calm_radius * escape_clear_factor.
## WorldEvents always win over watching the player: INVESTIGATE faces the event
## for 3 s and does nothing else.
## A "water_blob" event grants a grace period: the fox turns bold and FOLLOWs the
## player at half the flee radius instead of fleeing.
##
## Waypoint advancement is owned entirely by NavigationAgent3D: one target at a
## time, arrival decided by agent.is_navigation_finished().

enum State { IDLE, WANDER, WATCH, ALERT, AVOID, INVESTIGATE, FOLLOW }

@export_group("Nodes")
@export var animation_player: AnimationPlayer  # auto-found if empty
@export var agent: NavigationAgent3D  # auto-found if empty

@export_group("Distance Bands")
@export var flee_radius := 10.0  # closer than this: bark, then run
@export var calm_radius := 30.0  # farther than this: roam freely
## AVOID ends only once the player is past calm_radius * this.
@export var escape_clear_factor := 2.0

@export_group("Movement")
@export var walk_speed := 2.8
@export var run_speed := 7.0
@export var acceleration := 8.0
@export var turn_speed := 10.0  # body yaw toward facing direction
@export var max_turn_rate := 5.0  # rad/s heading change; lower = wider curves
## Must stay above run_speed / max_turn_rate, or the fox orbits path points
## it can never reach. At 7.0 / 5.0 that lower bound is 1.4 m.
@export var path_advance_distance := 2.0
@export var waypoint_radius := 3.0  # the agent's arrival distance; keep above the line above
@export var move_timeout := 12.0  # failsafe: give up on one leg after this long
@export var model_faces_positive_z := true

@export_group("Idle & Wander")
@export var idle_time := Vector2(3.0, 9.0)
@export var wander_radius := 15.0

@export_group("Escape")
@export var escape_leg := 12.0  # length of one escape leg; shorter = curvier overall
@export var escape_arc_deg := 60.0  # initial spread of the semicircle away from the player
@export var escape_drift_deg := 35.0  # per-leg direction change; this is what makes it curve
@export var escape_give_up := 60.0  # failsafe: stop fleeing after this long

@export_group("Events & Grace")
@export var curiosity_threshold := 0.6
@export var investigate_time := 3.0
@export var grace_kind: StringName = &"water_blob"
@export var grace_time := 60.0
@export var follow_factor := 0.3  # follow distance as a fraction of flee_radius
@export var follow_slack := 1.5  # dead zone, so the fox is not re-targeting constantly
@export var calm_exit := true  # on grace expiry, back off quietly instead of bolting

@export_group("Animation")
@export var blend_time := 0.2
@export var idle_anim := "idle_rig"
@export var walk_anim := "walking_rig"
@export var run_anim := "running_rig"
@export var bark_anim := "bark_rig"

@export_group("Debug")
@export var debug := false

const TICK := 2.0

var state := State.IDLE

var _target := Vector3.ZERO
var _has_target := false
var _leg_time := 0.0

var _desired_h := Vector3.ZERO  # wanted horizontal velocity this frame
var _face_dir := Vector3.ZERO  # explicit facing override this frame
var _heading := Vector3.ZERO  # rate-limited travel direction

var _tick_timer := 0.0
var _idle_timer := 0.0
var _escape_time := 0.0
var _escape_dir := Vector3.ZERO  # carried between legs so the route arcs
var _investigate_timer := 0.0
var _grace := 0.0
var _event_pos := Vector3.ZERO
var _barking := false

@onready var lira: LIRA_Character = get_tree().get_first_node_in_group("player")
@onready var bark_sound: FmodEventEmitter3D = $fox_rigged/root/Skeleton3D/Retopo_fox_002/FmodEventEmitter3DBark
@onready var debug_label: Label3D = get_node_or_null("DebugLabel3D")


# === Lifecycle ===

func _ready() -> void:
	if animation_player == null:
		animation_player = get_node_or_null("fox_rigged/AnimationPlayer")
	if agent == null:
		agent = get_node_or_null("NavigationAgent3D")
	if animation_player == null or agent == null:
		push_error("AnimalFox: needs an AnimationPlayer and a NavigationAgent3D")
		set_physics_process(false)
		return
	animation_player.playback_default_blend_time = blend_time
	agent.path_desired_distance = path_advance_distance
	agent.target_desired_distance = waypoint_radius
	agent.avoidance_enabled = false
	WorldEvents.happened.connect(_on_world_event)
	_tick_timer = randf() * TICK  # stagger foxes so they do not all think on one frame
	_enter_idle()


func _physics_process(delta: float) -> void:
	_desired_h = Vector3.ZERO
	_face_dir = Vector3.ZERO
	_grace = maxf(_grace - delta, 0.0)

	if _nav_ready():
		_tick_timer -= delta
		if _tick_timer <= 0.0:
			_tick_timer = TICK
			_decide()

		match state:
			State.IDLE: _tick_idle(delta)
			State.WANDER: _tick_wander(delta)
			State.WATCH: _tick_watch()
			State.ALERT: _tick_alert()
			State.AVOID: _tick_avoid(delta)
			State.INVESTIGATE: _tick_investigate(delta)
			State.FOLLOW: _tick_follow(delta)

	_apply_motion(delta)
	_face(delta)
	_animate()
	_update_debug_label()


# === Decisions (every TICK seconds) ===

func _decide() -> void:
	# These two run to completion and cannot be interrupted.
	if state == State.ALERT or state == State.INVESTIGATE:
		return

	var dist := _player_distance()

	if state == State.AVOID:
		if _escape_time > escape_give_up or dist > calm_radius * escape_clear_factor:
			_enter_idle()
		return

	# Grace period: the fox is bold, and tags along instead of fleeing.
	if _grace > 0.0:
		_decide_follow(dist)
		return

	if state == State.FOLLOW:
		# Grace just ended.
		if calm_exit:
			_enter_idle()
			return

	if dist < flee_radius:
		_enter_alert()
	elif dist < calm_radius:
		_clear_target()
		state = State.WATCH
	elif state == State.WATCH:
		_enter_idle()


# === States ===

func _enter_idle() -> void:
	_clear_target()
	_idle_timer = randf_range(idle_time.x, idle_time.y)
	state = State.IDLE


func _tick_idle(delta: float) -> void:
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_set_target(_wander_target())
		state = State.WANDER


func _tick_wander(delta: float) -> void:
	if _follow_target(delta, walk_speed):
		_enter_idle()


func _tick_watch() -> void:
	_face_dir = lira.global_position - global_position  # stand still, head turned


func _enter_alert() -> void:
	_clear_target()
	state = State.ALERT
	_bark()


func _tick_alert() -> void:
	_face_dir = lira.global_position - global_position  # hold the player in view while barking


func _bark() -> void:
	_barking = true
	bark_sound.play()
	animation_player.play(bark_anim)
	await animation_player.animation_finished
	if not is_inside_tree():
		return
	_barking = false
	if state == State.ALERT:
		_enter_avoid()


func _enter_avoid() -> void:
	_escape_time = 0.0
	_escape_dir = Vector3.ZERO
	_next_escape_leg()
	state = State.AVOID


func _tick_avoid(delta: float) -> void:
	_escape_time += delta
	if _follow_target(delta, run_speed):
		_next_escape_leg()  # arrived: set the next leg now, do not wait for the tick


func _tick_investigate(delta: float) -> void:
	_face_dir = _event_pos - global_position
	_investigate_timer -= delta
	if _investigate_timer <= 0.0:
		_enter_idle()


## Decided on the tick: hold a band at flee_radius * follow_factor from the player.
func _decide_follow(dist: float) -> void:
	var want := flee_radius * follow_factor
	if absf(dist - want) < follow_slack:
		_clear_target()  # close enough: stand and watch
	else:
		var out := global_position - lira.global_position
		out.y = 0.0
		out = out.normalized() if out.length() > 0.01 else Vector3.BACK
		_set_target(_closest_nav_point(lira.global_position + out * want), follow_slack * 0.5)
	state = State.FOLLOW


func _tick_follow(delta: float) -> void:
	if _has_target:
		_follow_target(delta, walk_speed)
	else:
		_face_dir = lira.global_position - global_position


# === Targets (the agent owns waypoint advancement) ===

func _set_target(p: Vector3, arrive := waypoint_radius) -> void:
	_target = p
	_has_target = true
	_leg_time = 0.0
	agent.target_desired_distance = arrive
	agent.target_position = p


func _clear_target() -> void:
	_has_target = false


## Steers toward the current target. Returns true once the agent reports arrival.
func _follow_target(delta: float, speed: float) -> bool:
	if not _has_target:
		return true
	_leg_time += delta
	# The path needs a frame to exist, so do not trust the agent before then.
	if (_leg_time > 0.1 and agent.is_navigation_finished()) or _leg_time >= move_timeout:
		_clear_target()
		return true
	_steer_along_path(speed)
	return false


func _steer_along_path(speed: float) -> void:
	var to := agent.get_next_path_position() - global_position
	to.y = 0.0
	if to.length() > 0.05:
		_desired_h = to.normalized() * speed


## One leg of the escape. Each leg drifts from the last, so the overall route curves.
func _next_escape_leg() -> void:
	if _escape_dir == Vector3.ZERO:
		var away := global_position - lira.global_position
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.BACK
		_escape_dir = away.rotated(Vector3.UP, deg_to_rad(randf_range(-escape_arc_deg, escape_arc_deg)))
	else:
		_escape_dir = _escape_dir.rotated(Vector3.UP, deg_to_rad(randf_range(-escape_drift_deg, escape_drift_deg)))

	var candidate := global_position + _escape_dir * escape_leg
	var snapped := _closest_nav_point(candidate)

	# Ran into the edge of the nav mesh: turn hard and try once more.
	if snapped.distance_to(candidate) > escape_leg * 0.5:
		_escape_dir = _escape_dir.rotated(Vector3.UP, deg_to_rad(randf_range(90.0, 180.0)))
		snapped = _closest_nav_point(global_position + _escape_dir * escape_leg)

	_set_target(snapped)


func _wander_target() -> Vector3:
	var a := randf() * TAU
	var r := sqrt(randf()) * wander_radius
	return _closest_nav_point(global_position + Vector3(cos(a) * r, 0.0, sin(a) * r))


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

	# Face where we actually move, unless a state asked for something else.
	if _face_dir == Vector3.ZERO and h.length() > 0.1:
		_face_dir = h


func _face(delta: float) -> void:
	var d := Vector3(_face_dir.x, 0.0, _face_dir.z)
	if d.length() < 0.01:
		return
	var yaw := atan2(d.x, d.z) if model_faces_positive_z else atan2(-d.x, -d.z)
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-turn_speed * delta))


func _animate() -> void:
	if _barking:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	var clip := idle_anim
	if speed > 0.15:
		clip = run_anim if state == State.AVOID else walk_anim
	if animation_player.current_animation != clip:
		animation_player.play(clip)


# === World events ===

func _on_world_event(pos: Vector3, kind: StringName, interest: float) -> void:
	if kind == grace_kind:
		_grace = grace_time  # the fox has learned this one is harmless
	if interest < curiosity_threshold:
		return
	if state == State.ALERT or state == State.AVOID:
		return  # too busy fleeing to be curious
	# Events outrank watching or following the player.
	_clear_target()
	_event_pos = pos
	_investigate_timer = investigate_time
	state = State.INVESTIGATE


# === Helpers ===

func _nav_ready() -> bool:
	return is_instance_valid(lira) \
			and NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) > 0


func _closest_nav_point(p: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(agent.get_navigation_map(), p)


func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func _flat_forward() -> Vector3:
	var f := global_basis.z if model_faces_positive_z else -global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 1e-3 else Vector3.FORWARD


func _player_distance() -> float:
	return global_position.distance_to(lira.global_position)


func _update_debug_label() -> void:
	if debug_label == null:
		return
	debug_label.visible = debug
	if not debug:
		return

	var lines := "%s  %.0fm" % [State.keys()[state], _player_distance()]

	if _has_target:
		lines += "\ntarget %.2fm (arrive %.2f)" % [_flat_dist(_target), agent.target_desired_distance]
		lines += "\npath   %.2fm (advance %.2f)" % [
			_flat_dist(agent.get_next_path_position()), agent.path_desired_distance]
		lines += "\nleg    %.1fs / %.0fs" % [_leg_time, move_timeout]
		if agent.is_navigation_finished():
			lines += "\nFINISHED"
	else:
		lines += "\nno target"

	if _grace > 0.0:
		lines += "\ngrace %.0fs" % _grace

	debug_label.text = lines
