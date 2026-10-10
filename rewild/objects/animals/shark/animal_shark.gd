extends CharacterBody3D
class_name AnimalShark
## Patrols a water volume, hunts Edible creatures when hungry, bites what enters its mouth,
## sleeps when fed. Never dies; with no food it just stays hungry and keeps patrolling.

enum State { PATROL, HUNT, DESCEND, SLEEP }

@export_group("Nodes")
@onready var animation_tree: AnimationTree = $AnimationTree     # auto-found among children if empty
@onready var mouth_area: Area3D = $shark_anim1/MouthArea3D                 # auto-found as "MouthArea3D" if empty

@export_group("Sea")
@export var sea_plane: MeshInstance3D           # water surface; its mesh bounds the sea horizontally
@export var terrain: Node3D                     # the Terrain3D node
@export var patrol_radius := 25.0               # patrol points are picked around the shark
@export var min_depth := 2.0                    # ignore spots shallower than this
@export var terrain_lookahead := 3.0            # check this far ahead for rising seabed
@export var climb_speed := 1.2                  # vertical escape speed over rising seabed
@export_flags_3d_physics var seabed_mask := 1   # raycast fallback only

@export_group("Sleep Spot")
@export var max_sleep_slope_deg := 20.0         # only lie down on gentler slopes than this
@export var sleep_search_radius := 20.0
@export var rest_height := 0.3                  # root origin height above the seabed when lying
@export var land_radius := 1.0
@export var descend_speed := 1.5
@export var descend_pitch_deg := 25.0
@export var settle_time := 0.8
@export var wake_lift := 0.8

@export_group("Movement")
@export var patrol_speed := 2.0
@export var chase_speed := 5.0
@export var acceleration := 2.5                # m/s²: sharks don't stop on a dime
@export var turn_speed := 1.8                  # rad/s heading change
@export var max_pitch_deg := 30.0
@export var face_smoothing := 6.0
@export var arrive_radius := 1.5
@export var min_patrol_hop := 6.0              # new patrol points at least this far away
@export var side_margin := 1.0                 # keep away from the volume's side walls
@export var surface_margin := 0.8              # stay this far under the surface
@export var bottom_margin := 0.5
@export var stuck_time := 4.0
@export var model_faces_positive_z := true     # untick if the shark swims backwards

@export_group("Hunger")
@export var hunger := 0.6                      # 0 = full, 1 = starving
@export var hunger_rate := 0.02                # per second awake
@export var sleep_hunger_rate := 0.005         # per second asleep
@export var hunt_threshold := 0.5              # hunts above this
@export var fed_threshold := 0.15              # at or below this after eating → sleep
@export var sleep_duration := 12.0
@export var sense_radius := 15.0
@export var lose_radius := 25.0

@export_group("Bite")
@export var head_state_name := "bite"          # state inside the Head state machine
@export var bite_anim_name := "bite"           # animation in the AnimationPlayer (for its length)
@export var bite_length := 0.0                 # 0 = read from the animation
@export var bite_hit_fraction := 0.4           # when the jaws close, as a fraction of the bite
@export var bite_cooldown := 0.6
@export var head_blend_speed := 12.0
@export var head_blend_out := 0.15             # start blending out this long before the bite ends
@export var head_blend_param := "parameters/HeadBlend/blend_amount"
@export var head_playback_param := "parameters/Head/playback"

var _settle_t := 1.0
var _settle_from := Transform3D.IDENTITY
var _seabed_point := Vector3.ZERO
var _seabed_normal := Vector3.UP

@export_group("Debug")
@export var debug_print := true

var is_moving := true            # read by the Body state machine's Advance Expressions
var state := State.PATROL

var _target_point := Vector3.ZERO
var _prey: Edible
var _in_mouth: Array[Edible] = []
var _sleep_timer := 0.0
var _retarget_timer := 0.0
var _stuck_timer := 0.0
var _last_dist := INF
var _biting := false
var _bite_t := 0.0
var _bite_hit_done := false
var _bite_cd := 0.0
var _head_blend := 0.0
var _head_pb: AnimationNodeStateMachinePlayback
var _spawn := Vector3.ZERO

var _surface_y := 0.0
var _sea_min := Vector2.ZERO
var _sea_max := Vector2.ZERO
var _terrain_data: Object
var _sleep_spot := {}
var _sleep_retry := 0.0

func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING   # no floor/gravity logic underwater
	_spawn = global_position

	if animation_tree == null:
		var found := find_children("*", "AnimationTree", true, false)
		animation_tree = found[0] if found.size() > 0 else null
	if mouth_area == null:
		mouth_area = get_node_or_null("MouthArea3D")
	if animation_tree == null or mouth_area == null:
		push_error("AnimalShark: needs an AnimationTree and a MouthArea3D")
		set_physics_process(false)
		return

	_head_pb = animation_tree.get(head_playback_param)
	_detect_bite_length()
	_setup_sea()

	mouth_area.body_entered.connect(_on_mouth_entered)
	mouth_area.body_exited.connect(_on_mouth_exited)
	mouth_area.area_entered.connect(_on_mouth_entered)
	mouth_area.area_exited.connect(_on_mouth_exited)

	_pick_patrol_point()


func _physics_process(delta: float) -> void:
	_update_hunger(delta)
	match state:
		State.PATROL: _tick_patrol(delta)
		State.HUNT: _tick_hunt(delta)
		State.DESCEND: _tick_descend(delta)
		State.SLEEP: _tick_sleep(delta)
	_update_bite(delta)
	_update_head_blend(delta)
	if state == State.SLEEP:
		return
	_depth_guards()
	move_and_slide()
	_face_motion(delta)

	print(is_moving, state)


# --- states ------------------------------------------------------------------

func _tick_patrol(delta: float) -> void:
	if hunger > hunt_threshold:
		var p := _find_prey()
		if p:
			_prey = p
			_set_state(State.HUNT)
			return
	_patrol_move(delta)

func _patrol_move(delta: float) -> void:
	var d := global_position.distance_to(_target_point)
	if d < arrive_radius:
		_pick_patrol_point()
	else:
		_stuck_timer = _stuck_timer + delta if d > _last_dist - 0.005 else 0.0
		_last_dist = d
		if _stuck_timer > stuck_time:
			_pick_patrol_point()
	_steer_toward(_target_point, patrol_speed, delta)


func _tick_hunt(delta: float) -> void:
	if not _prey_valid(_prey) or hunger <= hunt_threshold:
		_lose_prey()
		return
	var pos := _prey.get_body().global_position
	if global_position.distance_to(pos) > lose_radius:
		_lose_prey()
		return

	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = 0.5
		var nearer := _find_prey()
		if nearer:
			_prey = nearer

	# Prey that leaps out of the water: loiter underneath it instead of following
	_steer_toward(_clamp_to_water(pos), chase_speed, delta)


func _enter_descend() -> void:
	_prey = null
	_sleep_spot = _find_sleep_spot()
	_sleep_retry = 1.0
	_set_state(State.DESCEND)            # still swimming: is_moving stays true


func _tick_descend(delta: float) -> void:
	if _sleep_spot.is_empty():
		# Nowhere flat enough nearby: keep patrolling and look again from the new position
		_sleep_retry -= delta
		if _sleep_retry <= 0.0:
			_sleep_retry = 1.0
			_sleep_spot = _find_sleep_spot()
		_patrol_move(delta)
		return
	var hover: Vector3 = _sleep_spot.position + _sleep_spot.normal * rest_height
	if global_position.distance_to(hover) < land_radius:
		_begin_settle()
		return
	_steer_toward(hover, descend_speed, delta, descend_pitch_deg)

func _begin_settle() -> void:
	_seabed_point = _sleep_spot.position
	_seabed_normal = _sleep_spot.normal
	_settle_from = global_transform
	_settle_t = 0.0
	velocity = Vector3.ZERO
	is_moving = false                    # Body state machine → sleep
	_sleep_timer = sleep_duration
	_set_state(State.SLEEP)

func _find_sleep_spot() -> Dictionary:
	var best := {}
	var best_d := INF
	var min_up := cos(deg_to_rad(max_sleep_slope_deg))
	for i in 16:
		var ang := randf() * TAU
		var rad := 0.0 if i == 0 else sqrt(randf()) * sleep_search_radius   # first try: straight below
		var xz := _clamp_xz(Vector2(global_position.x + cos(ang) * rad, global_position.z + sin(ang) * rad))
		var floor_y := _seabed_height(xz)
		if is_nan(floor_y) or _surface_y - floor_y < min_depth:
			continue
		var n := _get_seabed_normal(xz)
		if n.dot(Vector3.UP) < min_up:
			continue
		var p := Vector3(xz.x, floor_y, xz.y)
		var d := global_position.distance_to(p)
		if d < best_d:
			best_d = d
			best = {"position": p, "normal": n}
	return best

func _tick_sleep(delta: float) -> void:
	velocity = Vector3.ZERO
	if _settle_t < 1.0:
		_settle_t = minf(_settle_t + delta / settle_time, 1.0)
		var w := smoothstep(0.0, 1.0, _settle_t)
		global_transform = _settle_from.interpolate_with(_rest_transform(), w)
	_sleep_timer -= delta
	if _sleep_timer <= 0.0:
		is_moving = true
		velocity = Vector3.UP * wake_lift + _forward() * 0.3   # lift off before swimming away
		_set_state(State.PATROL)
		_pick_patrol_point()


func _rest_transform() -> Transform3D:
	var n := _seabed_normal
	var f := _settle_from.basis.z if model_faces_positive_z else -_settle_from.basis.z
	f = (f - n * f.dot(n))           # keep heading, lie flat on the slope
	if f.length() < 1e-3:
		f = n.cross(Vector3.RIGHT)
	var b := Basis.looking_at(f.normalized(), n, model_faces_positive_z)
	return Transform3D(b, _seabed_point + n * rest_height)

func _lose_prey() -> void:
	_prey = null
	_set_state(State.PATROL)
	_pick_patrol_point()


func _set_state(s: State) -> void:
	if s == state:
		return
	state = s
	if debug_print:
		print("[Shark] %s  hunger %.2f" % [State.keys()[s], hunger])


func _update_hunger(delta: float) -> void:
	var rate := sleep_hunger_rate if state == State.SLEEP else hunger_rate
	hunger = minf(hunger + rate * delta, 1.0)


# --- prey & biting -----------------------------------------------------------

func _find_prey() -> Edible:
	var best: Edible = null
	var best_d := sense_radius
	for n in get_tree().get_nodes_in_group(Edible.GROUP):
		var e := n as Edible
		if e == null or e.is_eaten:
			continue
		var b := e.get_body()
		if b == null or b == self or b is AnimalShark:
			continue
		if not _in_water(b.global_position):
			continue
		var d := global_position.distance_to(b.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _prey_valid(e: Edible) -> bool:
	return is_instance_valid(e) and not e.is_eaten and e.get_body() != null


func _on_mouth_entered(n: Node) -> void:
	var e := Edible.find_on(n)
	if e == null or e.is_eaten:
		return
	var b := e.get_body()
	if b == self or b is AnimalShark:
		return
	if not _in_mouth.has(e):
		_in_mouth.append(e)


func _on_mouth_exited(n: Node) -> void:
	var e := Edible.find_on(n)
	if e:
		_in_mouth.erase(e)


func _update_bite(delta: float) -> void:
	_bite_cd = maxf(_bite_cd - delta, 0.0)
	for i in range(_in_mouth.size() - 1, -1, -1):
		var e := _in_mouth[i]
		if not is_instance_valid(e) or e.is_eaten:
			_in_mouth.remove_at(i)

	if _biting:
		_bite_t += delta
		if not _bite_hit_done and _bite_t >= bite_length * bite_hit_fraction:
			_bite_hit_done = true
			if not _in_mouth.is_empty():
				_eat(_in_mouth[0])
		if _bite_t >= bite_length:
			_biting = false
			_bite_cd = bite_cooldown
	elif state != State.SLEEP and _bite_cd <= 0.0 and hunger > fed_threshold and not _in_mouth.is_empty():
		_start_bite()


func _start_bite() -> void:
	_biting = true
	_bite_t = 0.0
	_bite_hit_done = false
	if _head_pb:
		_head_pb.start(head_state_name, true)   # restart the one-shot from frame 0


func _eat(e: Edible) -> void:
	var gained := e.eat(self)
	hunger = maxf(hunger - gained, 0.0)
	_in_mouth.erase(e)
	if _prey == e:
		_prey = null
	if debug_print:
		print("[Shark] ate something, hunger %.2f" % hunger)
	if hunger <= fed_threshold:
		_enter_descend()
	elif state == State.HUNT and hunger <= hunt_threshold:
		_lose_prey()


func _update_head_blend(delta: float) -> void:
	var target := 1.0 if _biting and _bite_t < bite_length - head_blend_out else 0.0
	_head_blend = lerpf(_head_blend, target, 1.0 - exp(-head_blend_speed * delta))
	animation_tree.set(head_blend_param, _head_blend)


func _detect_bite_length() -> void:
	if bite_length > 0.0:
		return
	var ap := animation_tree.get_node_or_null(animation_tree.anim_player) as AnimationPlayer
	if ap:
		for anim_name in ap.get_animation_list():
			if anim_name == bite_anim_name or String(anim_name).ends_with("/" + bite_anim_name):
				bite_length = ap.get_animation(anim_name).length
				return
	bite_length = 0.8
	push_warning("AnimalShark: '%s' not found, using bite_length 0.8s" % bite_anim_name)


# --- steering ----------------------------------------------------------------

func _steer_toward(target: Vector3, speed: float, delta: float, pitch_limit_deg := -1.0) -> void:
	var to := target - global_position
	if to.length() < 0.01:
		return
	to = to.normalized()

	# Limit pitch: sharks cruise mostly level
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() < 1e-3:
		flat = _forward()
		flat.y = 0.0
	flat = flat.normalized()
	var max_p := deg_to_rad(pitch_limit_deg if pitch_limit_deg > 0.0 else max_pitch_deg)
	var pitch := clampf(asin(clampf(to.y, -1.0, 1.0)), -max_p, max_p)
	var desired := flat * cos(pitch) + Vector3.UP * sin(pitch)

	# Turn the heading at a limited rate, so it swims in arcs instead of strafing
	var spd := velocity.length()
	var fwd := velocity / spd if spd > 0.1 else _forward()
	fwd = _rotate_toward(fwd, desired, turn_speed * delta)
	spd = move_toward(spd, speed, acceleration * delta)
	velocity = fwd * spd


func _rotate_toward(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var angle := from.angle_to(to)
	if angle < 1e-4:
		return to
	var axis := from.cross(to)
	axis = axis.normalized() if axis.length() > 1e-4 else Vector3.UP
	return from.rotated(axis, minf(angle, max_angle)).normalized()


func _face_motion(delta: float) -> void:
	var dir := velocity
	if dir.length() < 0.1:
		dir = _forward()
		dir.y = 0.0            # level out when slow or asleep
	if dir.length() < 0.01:
		return
	var target := Basis.looking_at(dir.normalized(), Vector3.UP, model_faces_positive_z)
	global_basis = global_basis.orthonormalized().slerp(target, 1.0 - exp(-face_smoothing * delta))


func _forward() -> Vector3:
	return (global_basis.z if model_faces_positive_z else -global_basis.z).normalized()

# --- water volume ------------------------------------------------------------

func _setup_sea() -> void:
	if sea_plane == null:
		push_error("AnimalShark: assign sea_plane")
		return
	var aabb := sea_plane.global_transform * sea_plane.get_aabb()
	_surface_y = sea_plane.global_position.y
	_sea_min = Vector2(aabb.position.x, aabb.position.z)
	_sea_max = _sea_min + Vector2(aabb.size.x, aabb.size.z)
	if terrain:
		_terrain_data = terrain.get("data")            # Terrain3D 1.x
		if _terrain_data == null:
			_terrain_data = terrain.get("storage")     # Terrain3D 0.9.x


func _seabed_height(xz: Vector2) -> float:
	if _terrain_data and _terrain_data.has_method("get_height"):
		return _terrain_data.get_height(Vector3(xz.x, 0.0, xz.y))   # NAN in holes / outside regions
	var from := Vector3(xz.x, _surface_y, xz.y)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1000.0, seabed_mask, [get_rid()])
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return NAN if r.is_empty() else r.position.y


func _get_seabed_normal(xz: Vector2, e := 0.5) -> Vector3:
	var hx := _seabed_height(xz + Vector2(e, 0)) - _seabed_height(xz - Vector2(e, 0))
	var hz := _seabed_height(xz + Vector2(0, e)) - _seabed_height(xz - Vector2(0, e))
	if is_nan(hx) or is_nan(hz):
		return Vector3.UP
	return Vector3(-hx / (2.0 * e), 1.0, -hz / (2.0 * e)).normalized()


func _clamp_xz(xz: Vector2) -> Vector2:
	return Vector2(
		clampf(xz.x, _sea_min.x + side_margin, _sea_max.x - side_margin),
		clampf(xz.y, _sea_min.y + side_margin, _sea_max.y - side_margin))


func _in_water(p: Vector3) -> bool:
	if p.x < _sea_min.x or p.x > _sea_max.x or p.z < _sea_min.y or p.z > _sea_max.y:
		return false
	if p.y > _surface_y:
		return false
	var floor_y := _seabed_height(Vector2(p.x, p.z))
	return is_nan(floor_y) or p.y > floor_y


func _clamp_to_water(p: Vector3) -> Vector3:
	var xz := _clamp_xz(Vector2(p.x, p.z))
	var top := _surface_y - surface_margin
	var floor_y := _seabed_height(xz)
	var bottom := top if is_nan(floor_y) else minf(floor_y + bottom_margin, top)
	return Vector3(xz.x, clampf(p.y, bottom, top), xz.y)


func _pick_patrol_point() -> void:
	var fallback := _clamp_to_water(global_position + _forward() * min_patrol_hop)
	_target_point = fallback
	for i in 12:
		var ang := randf() * TAU
		var rad := sqrt(randf()) * patrol_radius
		var xz := _clamp_xz(Vector2(global_position.x + cos(ang) * rad, global_position.z + sin(ang) * rad))
		var floor_y := _seabed_height(xz)
		if is_nan(floor_y) or _surface_y - floor_y < min_depth:
			continue                                   # land, hole, or too shallow
		var lo := floor_y + bottom_margin
		var hi := _surface_y - surface_margin
		if hi <= lo:
			continue
		var p := Vector3(xz.x, randf_range(lo, hi), xz.y)
		_target_point = p
		if p.distance_to(global_position) >= min_patrol_hop:
			break
	_last_dist = INF
	_stuck_timer = 0.0


func _depth_guards() -> void:
	if global_position.y > _surface_y - surface_margin:
		velocity.y = minf(velocity.y, -0.5)            # never breach the surface
	if state == State.DESCEND:
		return                                         # it's supposed to approach the seabed
	var dir := velocity.normalized() if velocity.length() > 0.1 else _forward()
	for probe in [global_position, global_position + dir * terrain_lookahead]:
		var floor_y := _seabed_height(Vector2(probe.x, probe.z))
		if not is_nan(floor_y) and probe.y < floor_y + bottom_margin:
			velocity.y = maxf(velocity.y, climb_speed)   # climb over rising seabed
			break