extends CharacterBody3D
class_name AnimalShark
## PATROL: swim between random points in the sea; hungry + prey in range → HUNT
## HUNT: chase the nearest Edible; bite whatever enters the mouth
## fed → DESCEND to a flat seabed spot → SLEEP lying on it → PATROL
## Never dies: with no food it stays hungry and keeps patrolling.
## Body size comes from the CollisionShape3D capsule (lying along the swim direction).

enum State { PATROL, HUNT, DESCEND, SLEEP }

@onready var animation_tree: AnimationTree = get_node_or_null("AnimationTree")
@onready var mouth_area: Area3D = get_node_or_null("shark_anim1/MouthArea3D")
@onready var debug_label: Label3D = get_node_or_null("DebugLabel3D")

@export_group("Sea")
@export var sea_plane: MeshInstance3D  # water surface; its mesh bounds the sea horizontally
@export var terrain: Node3D  # the Terrain3D node
@export_flags_3d_physics var seabed_mask := 1  # raycast fallback if the Terrain3D API is missing
@export var clearance := 0.75  # extra space kept between the body and surface / terrain
@export var climb_speed := 4.0  # vertical escape speed over rising seabed

@export_group("Movement")
@export var patrol_speed := 4.0
@export var chase_speed := 7.0
@export var acceleration := 2.5  # m/s²: sharks don't stop on a dime
@export var turn_speed := 2.5  # rad/s heading change
@export var max_pitch_deg := 30.0
@export var face_smoothing := 6.0
@export var patrol_radius := 40.0  # patrol points are picked around the shark
@export var min_patrol_hop := 8.0  # patrol points at least this far away
@export var stuck_time := 4.0
@export var model_faces_positive_z := true

@export_group("Hunger")
@export var hunger := 0.6  # 0 = full, 1 = starving
@export var hunger_rate := 0.02  # per second awake
@export var sleep_hunger_rate := 0.005  # per second asleep
@export var hunt_threshold := 0.5  # hunts above this
@export var fed_threshold := 0.15  # at or below this after eating → sleep
@export var sense_radius := 15.0
@export var lose_radius := 25.0

@export_group("Sleep")
@export var sleep_duration := 12.0
@export var max_sleep_slope_deg := 20.0  # averaged over the body length
@export var sleep_search_radius := 20.0
@export var descend_speed := 3.0
@export var descend_pitch_deg := 25.0
@export var settle_time := 0.8
@export var wake_lift := 0.8

@export_group("Bite")
@export var head_state_name := "bite"  # state inside the Head state machine
@export var bite_anim_name := "bite"  # animation in the AnimationPlayer (for its length)
@export var bite_length := 0.0  # 0 = read from the animation
@export var bite_hit_fraction := 0.4  # when the jaws close, as a fraction of the bite
@export var bite_cooldown := 0.6
@export var head_blend_speed := 12.0
@export var head_blend_out := 0.15
@export var head_blend_param := "parameters/HeadBlend/blend_amount"
@export var head_playback_param := "parameters/Head/playback"

@export_group("Debug")
@export var debug := true
@export var debug_print := false
@export var debug_history := 8  # past patrol points to draw

var is_moving := true  # Body state machine: swim ⇄ sleep
var state := State.PATROL

var _radius := 1.0  # from the capsule
var _half_len := 2.0  # from the capsule
var _room := 1.75  # radius + clearance: how far the centre stays from surface / terrain

var _target := Vector3.ZERO  # current patrol point
var _last_dist := INF
var _stuck_timer := 0.0
var _prey: Edible
var _retarget_timer := 0.0

var _sleep_spot := {}  # {position, normal}; empty = none found yet
var _sleep_retry := 0.0
var _sleep_timer := 0.0
var _settle_t := 1.0
var _settle_from := Transform3D.IDENTITY

var _in_mouth: Array[Edible] = []
var _biting := false
var _bite_t := 0.0
var _bite_hit_done := false
var _bite_cd := 0.0
var _head_pb: AnimationNodeStateMachinePlayback

var _surface_y := 0.0
var _sea_min := Vector2.ZERO
var _sea_max := Vector2.ZERO
var _terrain_data: Object

var _debug_mesh: MeshInstance3D
var _waypoint_history := PackedVector3Array()

# === Lifecycle ===

func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING  # no floor/gravity logic underwater
	if animation_tree == null or mouth_area == null:
		push_error("AnimalShark: needs AnimationTree and shark_anim1/MouthArea3D")
		set_physics_process(false)
		return
	_read_body_size()
	_head_pb = animation_tree.get(head_playback_param)
	_detect_bite_length()
	_setup_sea()
	mouth_area.body_entered.connect(_on_mouth_entered)
	mouth_area.body_exited.connect(_on_mouth_exited)
	mouth_area.area_entered.connect(_on_mouth_entered)
	mouth_area.area_exited.connect(_on_mouth_exited)
	_setup_debug()
	_enter_patrol()

func _physics_process(delta: float) -> void:
	var rate := sleep_hunger_rate if state == State.SLEEP else hunger_rate
	hunger = minf(hunger + rate * delta, 1.0)
	match state:
		State.PATROL: _tick_patrol(delta)
		State.HUNT: _tick_hunt(delta)
		State.DESCEND: _tick_descend(delta)
		State.SLEEP: _tick_sleep(delta)
	_update_bite(delta)
	_update_debug()
	if state == State.SLEEP:
		return  # lying still: no physics motion, no re-facing
	_depth_guards()
	move_and_slide()
	_face_motion(delta)

func _read_body_size() -> void:
	for c in get_children():
		if c is CollisionShape3D and c.shape is CapsuleShape3D:
			_radius = c.shape.radius
			_half_len = c.shape.height * 0.5
			break
	_room = _radius + clearance

# === States ===

func _set_state(s: State) -> void:
	if s != state and debug_print:
		print("[Shark] %s  hunger %.2f" % [State.keys()[s], hunger])
	state = s

func _enter_patrol() -> void:
	_prey = null
	_pick_patrol_point()
	_set_state(State.PATROL)

func _tick_patrol(delta: float) -> void:
	if hunger > hunt_threshold:
		var prey := _find_prey()
		if prey:
			_enter_hunt(prey)
			return
	_swim_patrol(delta)

func _enter_hunt(prey: Edible) -> void:
	_prey = prey
	_retarget_timer = 0.5
	_set_state(State.HUNT)

func _tick_hunt(delta: float) -> void:
	if not _prey_reachable(_prey) or hunger <= hunt_threshold:
		_enter_patrol()
		return
	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = 0.5
		var nearer := _find_prey()
		if nearer:
			_prey = nearer
	_steer_toward(_clamp_to_water(_prey.get_body().global_position), chase_speed, delta)

func _enter_descend() -> void:
	_prey = null
	_sleep_spot = _find_sleep_spot()
	_sleep_retry = 1.0
	_set_state(State.DESCEND)  # still swimming: is_moving stays true

func _tick_descend(delta: float) -> void:
	if _sleep_spot.is_empty():  # nowhere flat enough nearby: keep patrolling, look again
		_sleep_retry -= delta
		if _sleep_retry <= 0.0:
			_sleep_retry = 1.0
			_sleep_spot = _find_sleep_spot()
		_swim_patrol(delta)
		return
	var hover := _sleep_hover()
	if global_position.distance_to(hover) < _radius:
		_enter_sleep()
	else:
		_steer_toward(hover, descend_speed, delta, descend_pitch_deg)

func _enter_sleep() -> void:
	_settle_from = global_transform
	_settle_t = 0.0
	velocity = Vector3.ZERO
	is_moving = false  # Body state machine → sleep
	_sleep_timer = sleep_duration
	_set_state(State.SLEEP)

func _tick_sleep(delta: float) -> void:
	if _settle_t < 1.0:  # glide onto the seabed
		_settle_t = minf(_settle_t + delta / settle_time, 1.0)
		global_transform = _settle_from.interpolate_with(_rest_transform(), smoothstep(0.0, 1.0, _settle_t))
	_sleep_timer -= delta
	if _sleep_timer <= 0.0:
		is_moving = true
		velocity = Vector3.UP * wake_lift + _forward() * 0.3  # lift off before swimming away
		_enter_patrol()

## Patrol movement, shared by PATROL and a DESCEND that hasn't found a sleep spot yet.
func _swim_patrol(delta: float) -> void:
	var d := global_position.distance_to(_target)
	if d < _half_len:
		_pick_patrol_point()
	else:
		_stuck_timer = _stuck_timer + delta if d > _last_dist - 0.005 else 0.0
		_last_dist = d
		if _stuck_timer > stuck_time:
			_pick_patrol_point()
	_steer_toward(_target, patrol_speed, delta)

# === Sleep spot ===

func _find_sleep_spot() -> Dictionary:
	var best := {}
	var best_d := INF
	var min_up := cos(deg_to_rad(max_sleep_slope_deg))
	for i in 16:
		var xz := _clamp_xz(Vector2(global_position.x, global_position.z)) if i == 0 \
				else _random_xz(global_position, sleep_search_radius)  # first try: straight below
		var floor_y := _seabed_height(xz)
		if is_nan(floor_y) or _surface_y - floor_y < 2.0 * _room:
			continue  # too shallow to get down there
		var n := _seabed_normal(xz, _half_len)  # slope averaged over the body length
		if n.dot(Vector3.UP) < min_up:
			continue
		var p := Vector3(xz.x, floor_y, xz.y)
		var d := global_position.distance_to(p)
		if d < best_d:
			best_d = d
			best = {"position": p, "normal": n}
	return best

func _sleep_hover() -> Vector3:
	return _sleep_spot.position + _sleep_spot.normal * _radius

## Lying pose: keep the heading, lie flat on the seabed slope with the belly touching.
func _rest_transform() -> Transform3D:
	var n: Vector3 = _sleep_spot.normal
	var f := _settle_from.basis.z if model_faces_positive_z else -_settle_from.basis.z
	f -= n * f.dot(n)
	if f.length() < 1e-3:
		f = n.cross(Vector3.RIGHT)
	return Transform3D(Basis.looking_at(f.normalized(), n, model_faces_positive_z), _sleep_hover())

# === Prey & bite ===

func _find_prey() -> Edible:
	var best: Edible = null
	var best_d := sense_radius
	for n in get_tree().get_nodes_in_group(Edible.GROUP):
		var e := n as Edible
		if not _prey_reachable(e):
			continue
		var d := global_position.distance_to(e.get_body().global_position)
		if d < best_d:
			best_d = d
			best = e
	return best

## Valid, not a shark, within lose_radius, and in water deep enough for the shark to follow.
func _prey_reachable(e: Edible) -> bool:
	if not (is_instance_valid(e) and not e.is_eaten and e.get_body() != null):
		return false
	var b := e.get_body()
	if b == self or b is AnimalShark or global_position.distance_to(b.global_position) > lose_radius:
		return false
	var band := _safe_band(Vector2(b.global_position.x, b.global_position.z))
	return band.x <= band.y and b.global_position.y < _surface_y

func _on_mouth_entered(n: Node) -> void:
	var e := Edible.find_on(n)
	if e and not e.is_eaten and not (e.get_body() == self or e.get_body() is AnimalShark) and not _in_mouth.has(e):
		_in_mouth.append(e)

func _on_mouth_exited(n: Node) -> void:
	var e := Edible.find_on(n)
	if e:
		_in_mouth.erase(e)

func _update_bite(delta: float) -> void:
	_bite_cd = maxf(_bite_cd - delta, 0.0)
	for i in range(_in_mouth.size() - 1, -1, -1):  # drop eaten / freed prey
		if not is_instance_valid(_in_mouth[i]) or _in_mouth[i].is_eaten:
			_in_mouth.remove_at(i)
	if _biting:
		_bite_t += delta
		if not _bite_hit_done and _bite_t >= bite_length * bite_hit_fraction:
			_bite_hit_done = true  # jaws close now
			if not _in_mouth.is_empty():
				_eat(_in_mouth[0])
		if _bite_t >= bite_length:
			_biting = false
			_bite_cd = bite_cooldown
	elif state != State.SLEEP and _bite_cd <= 0.0 and hunger > fed_threshold and not _in_mouth.is_empty():
		_biting = true
		_bite_t = 0.0
		_bite_hit_done = false
		if _head_pb:
			print("playing eating animation")
			_head_pb.start(head_state_name, true)  # restart the one-shot from frame 0

func _eat(e: Edible) -> void:
	hunger = maxf(hunger - e.eat(self), 0.0)
	_in_mouth.erase(e)
	if _prey == e:
		_prey = null
	if debug_print:
		print("[Shark] ate something, hunger %.2f" % hunger)
	if hunger <= fed_threshold:
		_enter_descend()
	elif state == State.HUNT and hunger <= hunt_threshold:
		_enter_patrol()

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

# === Sea queries ===

func _setup_sea() -> void:
	if sea_plane == null:
		push_error("AnimalShark: assign sea_plane")
		return
	var aabb := sea_plane.global_transform * sea_plane.get_aabb()
	_surface_y = sea_plane.global_position.y
	_sea_min = Vector2(aabb.position.x, aabb.position.z)
	_sea_max = _sea_min + Vector2(aabb.size.x, aabb.size.z)
	if terrain:
		_terrain_data = terrain.get("data")  # Terrain3D 1.x
		if _terrain_data == null:
			_terrain_data = terrain.get("storage")  # Terrain3D 0.9.x

## Seabed height at xz; NAN in holes / outside terrain regions.
func _seabed_height(xz: Vector2) -> float:
	if _terrain_data and _terrain_data.has_method("get_height"):
		return _terrain_data.get_height(Vector3(xz.x, 0.0, xz.y))
	var from := Vector3(xz.x, _surface_y, xz.y)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1000.0, seabed_mask, [get_rid()])
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return NAN if r.is_empty() else r.position.y

func _seabed_normal(xz: Vector2, e: float) -> Vector3:
	var hx := _seabed_height(xz + Vector2(e, 0)) - _seabed_height(xz - Vector2(e, 0))
	var hz := _seabed_height(xz + Vector2(0, e)) - _seabed_height(xz - Vector2(0, e))
	if is_nan(hx) or is_nan(hz):
		return Vector3.UP
	return Vector3(-hx / (2.0 * e), 1.0, -hz / (2.0 * e)).normalized()

## Heights at xz where the shark's centre fits: _room below the surface and _room above the
## highest seabed within half a body length (the body may point any way). x > y means no room.
func _safe_band(xz: Vector2) -> Vector2:
	var floor_y := -INF
	for i in 9:
		var off := Vector2.ZERO if i == 0 else Vector2.from_angle(TAU * i / 8.0) * _half_len
		var h := _seabed_height(xz + off)
		if is_nan(h):
			return Vector2(1.0, -1.0)  # hole / outside terrain: not usable water
		floor_y = maxf(floor_y, h)
	return Vector2(floor_y + _room, _surface_y - _room)

## True if the water is deep enough for the body all along the straight line a → b.
func _path_clear(a: Vector3, b: Vector3) -> bool:
	var steps := maxi(1, ceili(a.distance_to(b) / 2.0))
	for i in range(1, steps + 1):
		var p := a.lerp(b, float(i) / steps)
		var band := _safe_band(Vector2(p.x, p.z))
		if band.x > band.y:
			return false
	return true

func _pick_patrol_point() -> void:
	for i in 16:
		var xz := _random_xz(global_position, patrol_radius)
		var band := _safe_band(xz)
		if band.x > band.y:
			continue  # land, too shallow, or too close to terrain
		var p := Vector3(xz.x, randf_range(band.x, band.y), xz.y)
		if p.distance_to(global_position) >= min_patrol_hop and _path_clear(global_position, p):
			_set_target(p)
			return
	_set_target(_clamp_to_water(global_position - _forward() * min_patrol_hop))  # nothing good: turn back

func _set_target(p: Vector3) -> void:
	_target = p
	_last_dist = INF
	_stuck_timer = 0.0
	_waypoint_history.append(p)
	if _waypoint_history.size() > debug_history:
		_waypoint_history.remove_at(0)

## Nearest point to p where the shark fits (or just under the surface if nowhere fits).
func _clamp_to_water(p: Vector3) -> Vector3:
	var xz := _clamp_xz(Vector2(p.x, p.z))
	var band := _safe_band(xz)
	var y := minf(p.y, _surface_y - _room) if band.x > band.y else clampf(p.y, band.x, band.y)
	return Vector3(xz.x, y, xz.y)

func _clamp_xz(xz: Vector2) -> Vector2:
	var m := _half_len + clearance  # keep the whole body inside the sea plane
	return Vector2(clampf(xz.x, _sea_min.x + m, _sea_max.x - m), clampf(xz.y, _sea_min.y + m, _sea_max.y - m))

func _random_xz(center: Vector3, radius: float) -> Vector2:
	var a := randf() * TAU
	var r := sqrt(randf()) * radius  # uniform over the disc
	return _clamp_xz(Vector2(center.x + cos(a) * r, center.z + sin(a) * r))

# === Steering ===

func _steer_toward(target: Vector3, speed: float, delta: float, pitch_limit_deg := -1.0) -> void:
	var to := target - global_position
	if to.length() < 0.01:
		return
	to = to.normalized()
	var flat := Vector3(to.x, 0.0, to.z)  # limit pitch: sharks cruise mostly level
	if flat.length() < 1e-3:
		flat = _forward()
		flat.y = 0.0
	flat = flat.normalized()
	var max_p := deg_to_rad(pitch_limit_deg if pitch_limit_deg > 0.0 else max_pitch_deg)
	var pitch := clampf(asin(clampf(to.y, -1.0, 1.0)), -max_p, max_p)
	var desired := flat * cos(pitch) + Vector3.UP * sin(pitch)
	var spd := velocity.length()  # turn at a limited rate: arcs, not strafing
	var fwd := velocity / spd if spd > 0.1 else _forward()
	velocity = _rotate_toward(fwd, desired, turn_speed * delta) * move_toward(spd, speed, acceleration * delta)

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
		dir.y = 0.0  # level out when slow
	if dir.length() < 0.01:
		return
	var target := Basis.looking_at(dir.normalized(), Vector3.UP, model_faces_positive_z)
	global_basis = global_basis.orthonormalized().slerp(target, 1.0 - exp(-face_smoothing * delta))

func _forward() -> Vector3:
	return (global_basis.z if model_faces_positive_z else -global_basis.z).normalized()

## Keeps the whole body (nose, centre, tail) out of the surface and the seabed.
func _depth_guards() -> void:
	if global_position.y > _surface_y - _room:
		velocity.y = minf(velocity.y, -0.5)  # never breach the surface
	if state == State.DESCEND:
		return  # it's supposed to approach the seabed
	var fwd := _forward()
	for probe in [global_position + fwd * (_half_len + clearance), global_position, global_position - fwd * _half_len]:
		var h := _seabed_height(Vector2(probe.x, probe.z))
		if not is_nan(h) and probe.y - h < _room:
			velocity.y = maxf(velocity.y, climb_speed)  # climb over rising seabed
			return

# === Debug ===

func _setup_debug() -> void:
	if debug_label:
		debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		debug_label.no_depth_test = true
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true  # visible through water and terrain
	mat.use_point_size = true
	mat.point_size = 8.0
	_debug_mesh = MeshInstance3D.new()
	_debug_mesh.top_level = true  # draw in world space
	_debug_mesh.material_override = mat
	_debug_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_debug_mesh.mesh = ImmediateMesh.new()
	add_child(_debug_mesh)

## Where the shark is heading right now, or null.
func _debug_goal() -> Variant:
	match state:
		State.PATROL:
			return _target
		State.HUNT:
			return _clamp_to_water(_prey.get_body().global_position) if _prey_reachable(_prey) else null
		State.DESCEND:
			return _target if _sleep_spot.is_empty() else _sleep_hover()
	return null

func _update_debug() -> void:
	if debug_label:
		debug_label.visible = debug
		debug_label.text = "%s\nhunger %d%%" % [State.keys()[state], roundi(hunger * 100.0)]
	_debug_mesh.visible = debug
	if not debug:
		return
	var im := _debug_mesh.mesh as ImmediateMesh
	im.clear_surfaces()
	var goal = _debug_goal()
	if _waypoint_history.size() >= 2 or goal != null:  # lines: history yellow, heading red
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		for i in _waypoint_history.size() - 1:
			im.surface_set_color(Color.YELLOW)
			im.surface_add_vertex(_waypoint_history[i])
			im.surface_add_vertex(_waypoint_history[i + 1])
		if goal != null:
			im.surface_set_color(Color.RED)
			im.surface_add_vertex(global_position)
			im.surface_add_vertex(goal)
		im.surface_end()
	if not _waypoint_history.is_empty() or goal != null:  # dots
		im.surface_begin(Mesh.PRIMITIVE_POINTS)
		im.surface_set_color(Color.YELLOW)
		for p in _waypoint_history:
			im.surface_add_vertex(p)
		if goal != null:
			im.surface_set_color(Color.RED)
			im.surface_add_vertex(goal)
		im.surface_end()