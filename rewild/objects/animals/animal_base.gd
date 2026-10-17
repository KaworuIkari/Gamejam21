extends CharacterBody3D
class_name AnimalBase
## Shared plumbing for every animal: navigation agent setup, path steering,
## rate-limited turning, facing, fall recovery, a clip hook for AnimationPlayer,
## and the debug label.
##
## Subclasses override:
##   _tick_state(delta)      - behaviour / state machine; runs only once navigation is ready
##   _after_motion(delta)    - optional; runs after motion and facing (wings, sounds, ...)
##   _pick_clip() -> String  - which AnimationPlayer clip to play this frame
##   _debug_text() -> String - lines for the debug label
##
## Animals driven by an AnimationTree leave animation_player empty and manage the tree themselves.

@export_group("Nodes")
## Assign in the inspector. Leave empty for animals driven by an AnimationTree.
@export var animation_player: AnimationPlayer
@onready var agent: NavigationAgent3D = $NavigationAgent3D  # auto-found if empty

@export_group("Movement")
@export var walk_speed := 2.5
@export var acceleration := 8.0
@export var turn_speed := 12.0  # body yaw toward facing direction
@export var max_turn_rate := 5.0  # rad/s heading change; lower = wider curves
## Must stay above the fastest speed / max_turn_rate, or the animal orbits path points it can never reach.
@export var path_advance_distance := 1.0
@export var waypoint_radius := 0.5  # the agent's arrival distance
@export var move_timeout := 15.0  # failsafe: give up on one leg after this long
@export var model_faces_positive_z := true

@export_group("Animation")
@export var blend_time := 0.2
@export var idle_anim := "idle"
@export var walk_anim := "walking"

@export_group("Recovery")
@export var fall_recover_depth := 3.0
@export var slow_tick_interval := 3.0

@export_group("Debug")
@export var debug := false

@onready var debug_label: Label3D = get_node_or_null("DebugLabel3D")

var is_moving := false  # true while horizontal speed is above the walk threshold
var animation_locked := false  # subclasses set this while a one-shot plays (e.g. bark)

var _desired_h := Vector3.ZERO  # wanted horizontal velocity this frame
var _face_dir := Vector3.ZERO  # explicit facing override this frame
var _heading := Vector3.ZERO  # rate-limited travel direction
var _leg_time := 0.0  # time spent on the current route leg
var _slow_tick_timer := 0.0


# === Lifecycle ===

## Margin over the geometric turn radius. Below ~1.2 the animal clips corners into partial orbits.
const TURN_MARGIN := 1.4
var _arrive_radius := 0.0
## The highest speed this animal can ask for. Override when a state runs faster than walk_speed.
func _max_speed() -> float:
	return walk_speed
func _min_lookahead_for(speed: float) -> float:
	return speed / maxf(max_turn_rate, 0.01) * TURN_MARGIN
func _min_lookahead() -> float:
	return _min_lookahead_for(_max_speed())
func _validate_steering() -> void:
	var need := _min_lookahead()
	if path_advance_distance < need:
		push_error("%s: path_advance_distance %.2f < %.2f required by max speed %.1f / max_turn_rate %.1f. Clamped — the animal would orbit its waypoints." % [
			name, path_advance_distance, need, _max_speed(), max_turn_rate])
		path_advance_distance = need
	var arrive_need := need * 0.9
	if waypoint_radius < arrive_need:
		push_error("%s: waypoint_radius %.2f < %.2f required. Clamped — arrival would never register." % [
			name, waypoint_radius, arrive_need])
		waypoint_radius = arrive_need
	agent.path_desired_distance = path_advance_distance
	agent.target_desired_distance = waypoint_radius

func _ready() -> void:
	if agent == null:
		agent = get_node_or_null("NavigationAgent3D")
	if agent == null:
		push_error("%s: needs a NavigationAgent3D" % name)
		set_physics_process(false)
		return
	_validate_steering()
	agent.avoidance_enabled = true
	if animation_player:
		animation_player.playback_default_blend_time = blend_time
	if debug_label:
		debug_label.no_depth_test = true


func _physics_process(delta: float) -> void:
	_desired_h = Vector3.ZERO
	_face_dir = Vector3.ZERO

	if _nav_ready():
		_tick_state(delta)

	_apply_motion(delta)
	_face(delta)
	_after_motion(delta)
	_animate()
	_update_debug_label()

	_slow_tick_timer += delta
	if _slow_tick_timer >= slow_tick_interval:
		_slow_tick_timer = 0.0
		_fall_guard()


# === Overrides ===

## Behaviour. Only called once the navigation map is ready.
func _tick_state(_delta: float) -> void:
	pass


## Optional. Runs after motion and facing have been applied.
func _after_motion(_delta: float) -> void:
	pass


## Clip for AnimationPlayer this frame. Override for extra clips (run, eat, ...).
func _pick_clip() -> String:
	return walk_anim if is_moving else idle_anim


## Extra lines for the debug label. Override to show state.
func _debug_text() -> String:
	return "%s  %s" % [_pick_clip(), "moving" if is_moving else "still"]


# === Steering ===

## Walks the agent's path at the given speed. Call every frame while following a leg.
func _steer_along_path(speed: float) -> void:
	var lookahead := maxf(path_advance_distance, _min_lookahead_for(speed))  # clamp to avoid circular motion entirely, failsafe
	agent.path_desired_distance = lookahead
	agent.target_desired_distance = maxf(_arrive_radius, lookahead * 0.9)
	var to := agent.get_next_path_position() - global_position
	to.y = 0.0
	if to.length() < 0.05:
		var path := agent.get_current_navigation_path()
		var idx := agent.get_current_navigation_path_index() + 1
		if idx < path.size():
			to = path[idx] - global_position
			to.y = 0.0
	if to.length() > 0.05:
		_desired_h = to.normalized() * speed


## Counts the current leg's time. Returns true when the agent reports the path finished or the leg timed out.
func _leg_done(delta: float) -> bool:
	_leg_time += delta
	return _leg_time >= move_timeout or (_leg_time > 0.1 and agent.is_navigation_finished())  # path needs a frame to exist


## Call when a new leg (route point or target) is set.
func _begin_leg() -> void:
	_leg_time = 0.0
	_arrive_radius = agent.target_desired_distance


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
	# Face where we actually move, unless a state asked for something else.
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


# === Animation ===

func _animate() -> void:
	if animation_player == null or animation_locked:
		return
	var clip := _pick_clip()
	if animation_player.current_animation != clip:
		animation_player.play(clip)


# === Recovery ===

## Teleports back onto the nav mesh if the animal has fallen well below it.
func _fall_guard() -> void:
	var p := _closest_nav_point(global_position)
	if p != Vector3.ZERO and global_position.y < p.y - fall_recover_depth:
		global_position = p + Vector3.UP * 0.5
		velocity = Vector3.ZERO


# === Navigation helpers ===

func _nav_ready() -> bool:
	return NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) > 0


func _closest_nav_point(p: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(agent.get_navigation_map(), p)


func _random_nav_point(center: Vector3, radius: float) -> Vector3:
	var a := randf() * TAU
	var r := sqrt(randf()) * radius  # uniform over the disc
	return _closest_nav_point(center + Vector3(cos(a) * r, 0.0, sin(a) * r))


# === Geometry helpers ===

func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func _flat_forward() -> Vector3:
	var f := global_basis.z if model_faces_positive_z else -global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 1e-3 else Vector3.FORWARD


# === Debug ===

func _update_debug_label() -> void:
	if debug_label == null:
		return
	debug_label.visible = debug
	if debug:
		debug_label.text = _debug_text()