extends AnimalBase
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

@export_group("Distance Bands")
@export var flee_radius := 10.0  # closer than this: bark, then run
@export var calm_radius := 30.0  # farther than this: roam freely
## AVOID ends only once the player is past calm_radius * this.
@export var escape_clear_factor := 2.0

@export_group("Movement")
@export var run_speed := 7.0
@export var tick_interval := 2.0  # how often decisions are made

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

@export_group("Animation Clips")
@export var run_anim := "running_rig"
@export var bark_anim := "bark_rig"

var state := State.IDLE

var _target := Vector3.ZERO
var _has_target := false

var _idle_timer := 0.0
var _escape_time := 0.0
var _escape_dir := Vector3.ZERO  # carried between legs so the route arcs
var _investigate_timer := 0.0
var _grace := 0.0
var _event_pos := Vector3.ZERO
var _tick_timer := 0.0

@onready var lira: LIRA_Character = get_tree().get_first_node_in_group("player")
@onready var bark_sound: FmodEventEmitter3D = $fox_rigged/root/Skeleton3D/Retopo_fox_002/FmodEventEmitter3DBark


# === Lifecycle ===

func _ready() -> void:
	super._ready()
	if animation_player == null:
		push_error("AnimalFox: assign an AnimationPlayer in the inspector")
		set_physics_process(false)
		return
	WorldEvents.happened.connect(_on_world_event)
	_tick_timer = randf() * tick_interval  # stagger foxes so they do not all think on one frame
	_enter_idle()


func _nav_ready() -> bool:
	return is_instance_valid(lira) and super._nav_ready()


# === State machine ===

func _tick_state(delta: float) -> void:
	_grace = maxf(_grace - delta, 0.0)

	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = tick_interval
		_decide()

	match state:
		State.IDLE: _tick_idle(delta)
		State.WANDER: _tick_wander(delta)
		State.WATCH: _tick_watch()
		State.ALERT: _tick_alert()
		State.AVOID: _tick_avoid(delta)
		State.INVESTIGATE: _tick_investigate(delta)
		State.FOLLOW: _tick_follow(delta)


# === Decisions (every tick_interval seconds) ===

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

	if state == State.FOLLOW and calm_exit:
		_enter_idle()  # grace just ended
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
	animation_locked = true
	bark_sound.play()
	animation_player.play(bark_anim)
	await animation_player.animation_finished
	if not is_inside_tree():
		return
	animation_locked = false
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


# === Targets ===

func _set_target(p: Vector3, arrive := -1.0) -> void:
	_target = p
	_has_target = true
	agent.target_desired_distance = waypoint_radius if arrive < 0.0 else arrive
	agent.target_position = p
	_begin_leg()


func _clear_target() -> void:
	_has_target = false


## Steers toward the current target. Returns true once the leg is done.
func _follow_target(delta: float, speed: float) -> bool:
	if not _has_target:
		return true
	if _leg_done(delta):
		_clear_target()
		return true
	_steer_along_path(speed)
	return false


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
	return _random_nav_point(global_position, wander_radius)


# === Animation ===

func _pick_clip() -> String:
	if not is_moving:
		return idle_anim
	return run_anim if state == State.AVOID else walk_anim


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

func _player_distance() -> float:
	return global_position.distance_to(lira.global_position)


func _debug_text() -> String:
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
	return lines