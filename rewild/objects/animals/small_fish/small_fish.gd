extends CharacterBody3D
class_name AnimalSmallFish
## Cheap fish: swim to a far, pre-validated waypoint in the water, then pick another.
## No neighbour queries, no physics collision (the seabed band check replaces it), and the
## expensive terrain lookups happen only when picking a waypoint and once per second.
## Moved by direct position changes; the shark's mouth Area3D still detects it.

@export var max_speed := 2.5
@export var turn_speed := 3.0            # rad/s
@export var clearance := 0.3
@export var model_faces_positive_z := true

const ACCEL := 3.0
const MAX_SINPITCH := 0.35               # steepest climb/dive (about 20 degrees)
const ARRIVE := 2.0
const MIN_HOP := 25.0                    # waypoints at least this far away: fish cross the lake
const EDGE_MARGIN := 4.0                 # waypoints stay this far inside the water's edge
const PATH_STEP := 3.0                   # seabed check spacing along a route, metres
const DISPERSE_TIME := 25.0              # after spawning, swim fast so the school spreads out
const DISPERSE_MULT := 2.5
const CHECK_EVERY := 1.0                 # safety clamp check

var water: StylizedWater

var _room := 0.8
var _scale := Vector3.ONE
var _target := Vector3.ZERO
var _heading := Vector3.FORWARD
var _speed := 0.0
var _cruise := 2.5
var _disperse_left := DISPERSE_TIME
var _retry_t := 0.0
var _check_t := 0.0


func _ready() -> void:
	water = StylizedWater.find_closest(global_position)
	if water == null:
		push_error("AnimalSmallFish: no StylizedWater found")
		set_physics_process(false)
		return
	for c in get_children():
		if c is CollisionShape3D and c.shape is CapsuleShape3D:
			_room = c.shape.radius + clearance
			break
	_scale = global_basis.get_scale()
	_cruise = max_speed * randf_range(0.8, 1.2)
	_check_t = randf() * CHECK_EVERY                     # fish don't all check on the same frame
	var a := randf() * TAU
	_heading = Vector3(cos(a), 0.0, sin(a))
	global_position = water.clamp_to_water(global_position, _room)   # the one intended snap
	_target = global_position + _heading * ARRIVE * 2.0
	_pick_target()


func _physics_process(delta: float) -> void:
	_retry_t -= delta
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = CHECK_EVERY
		_safety_check()
	_disperse_left = maxf(_disperse_left - delta, 0.0)

	var to := _target - global_position
	var d := to.length()
	# Arrived, or flew past it (then a tight U-turn is pointless).
	var arrived := d < ARRIVE or (d < ARRIVE * 4.0 and to.dot(_heading) < 0.0)
	if arrived and _retry_t <= 0.0 and _pick_target():
		to = _target - global_position
		d = to.length()
		arrived = false
	if not arrived and d > 0.01:
		var dir := to / d
		dir.y = clampf(dir.y, -MAX_SINPITCH, MAX_SINPITCH)
		_heading = _rotate_toward(_heading, dir.normalized(), turn_speed * delta)

	var goal := _cruise * (DISPERSE_MULT if _disperse_left > 0.0 else 1.0)
	_speed = move_toward(_speed, goal, ACCEL * delta)
	global_position += _heading * _speed * delta
	# The heading is already smooth, so facing it directly can't jitter.
	global_basis = Basis.looking_at(_heading, Vector3.UP, model_faces_positive_z).scaled(_scale)


## A far point in the water whose route is deep enough all the way. False = nothing found.
func _pick_target() -> bool:
	var here := global_position
	for i in 12:
		var xz := water.random_point_xz(_room + EDGE_MARGIN)
		if is_nan(xz.x):
			continue
		var flat := xz.distance_to(Vector2(here.x, here.z))
		if flat < MIN_HOP:
			continue
		var band := water.get_safe_band(xz, _room)
		# The target must also be reachable within the pitch limit.
		var reach := flat * MAX_SINPITCH * 0.8
		var lo := maxf(band.x, here.y - reach)
		var hi := minf(band.y, here.y + reach)
		if band.x > band.y or lo > hi:
			continue
		var p := Vector3(xz.x, randf_range(lo, hi), xz.y)
		if _path_clear(here, p):
			_target = p
			return true
	_retry_t = 1.0   # try again in a second; meanwhile keep cruising
	return false


func _path_clear(a: Vector3, b: Vector3) -> bool:
	var steps := maxi(1, ceili(a.distance_to(b) / PATH_STEP))
	for i in range(1, steps):
		var p := a.lerp(b, float(i) / steps)
		var band := water.get_safe_band(Vector2(p.x, p.z), _room)
		if band.x > band.y or p.y < band.x - 0.3 or p.y > band.y + 0.3:
			return false
	return true


## Should never fire. If it does, the fish is snapped back and gets a new route.
func _safety_check() -> void:
	var p := global_position
	var band := water.get_safe_band(Vector2(p.x, p.z), _room)
	if band.x > band.y or p.y < band.x - 0.5 or p.y > band.y + 0.5 or not water.holds_point(p):
		if OS.is_debug_build():
			push_warning("%s left the water at %v, clamped" % [name, p])
		global_position = water.clamp_to_water(p, _room)
		_retry_t = 0.0
		_pick_target()


func _rotate_toward(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var angle := from.angle_to(to)
	if angle < 1e-4:
		return to
	var axis := from.cross(to)
	axis = axis.normalized() if axis.length() > 1e-4 else Vector3.UP
	return from.rotated(axis, minf(angle, max_angle)).normalized()
