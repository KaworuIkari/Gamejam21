extends Node3D
class_name AnimalSeagull
## Flying seagull: Node3D only, no collision, no navigation.
## Loose flock with other seagulls (group "seagulls"), hovers over the island,
## climbs over terrain, steers around building colliders, and sometimes dives
## to 3 m above the player's head when about to fly past.
## Neighbour scans, terrain look-ahead and obstacle rays run every think_interval.
## Per frame only the cached steering is applied.

enum State { FLOCK, DIVE, RECOVER }

@export_group("Island")
@export var flight_center := Vector3.ZERO  ## world-space island centre
@export var island_radius := 150.0  ## soft boundary; gulls turn back past 80% of this
@export var hover_min := 10.0  ## metres above terrain, per seagull random between min and max
@export var hover_max := 30.0

@export_group("Flight")
@export var max_speed := 14.0
@export var min_speed := 8.0
@export var max_accel := 10.0  ## m/s² speed change
@export var turn_rate := 2.0  ## rad/s heading change while flocking
@export var face_smoothing := 6.0
@export var model_faces_positive_z := true
@export var min_ground_clearance := 6.0  ## steer up when this close to terrain ahead
@export var hard_floor_clearance := 2.0  ## never go below this above terrain
@export var terrain_lookahead := 2.0  ## seconds of flight checked for ridges

@export_group("Flock")
@export var think_interval := 0.25
@export var neighbor_radius := 30.0
@export var separation_radius := 6.0
@export var alignment_radius := 20.0
@export var cohesion_radius := 30.0
@export var separation_weight := 2.0
@export var alignment_weight := 0.6
@export var cohesion_weight := 0.4  ## low on purpose: loose groups, not formation
@export var island_weight := 1.5
@export var altitude_weight := 1.0
@export var terrain_weight := 3.0
@export var obstacle_weight := 4.0
@export var wander_weight := 0.8
@export var wander_jitter := 0.6  ## rad change of wander heading per think tick
@export var breakaway_chance := 0.05  ## per think tick: chance to leave the flock for a while
@export var breakaway_time := Vector2(4.0, 8.0)

@export_group("Obstacles")
@export_flags_3d_physics var obstacle_mask := 1  ## buildings only; leave terrain out
@export var obstacle_probe_distance := 12.0

@export_group("Dive")
@export var head_offset := 1.8  ## player's head height above their origin
@export var dive_clearance := 3.0  ## dive target: this far above the head
@export var dive_detect_radius := 40.0
@export var dive_lookahead := 2.5  ## seconds: only react when the pass is this soon
@export var dive_pass_radius := 4.0  ## horizontal miss distance that counts as "about to pass"
@export var dive_chance := 0.35  ## per detected pass
@export var dive_cooldown := Vector2(15.0, 35.0)
@export var dive_speed_mult := 1.5
@export var dive_turn_rate := 4.0
@export var dive_max_time := 3.0
@export var recover_time := 2.5

@export_group("Wings")
@export var wings_blend_param := "parameters/WingsBlend/blend_amount"
@export var flap_interval_mean := 5.0  ## mean seconds of gliding between flap bursts
@export var flap_interval_sd := 5.0  ## standard deviation of that gap
@export var flap_interval_min := 1.0  ## floor: the gaussian tail would otherwise go negative
@export var flap_duration := Vector2(0.8, 2.0)  ## how long one burst lasts
@export var wings_blend_speed := 6.0  ## lerp rate toward the target blend
var _flap_timer := 0.0
var _flapping := false
var _wings_blend := 0.0

@export_group("Camera")
@export var sing_delay := 2.0
var _sing_timer := -1.0

@onready var terrain: Terrain3D = get_tree().root.find_child("Terrain3D", true, false)
@onready var _player: LIRA_Character = get_tree().get_first_node_in_group("player")
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var _sound_emitter: FmodEventEmitter3D = $FmodEventEmitter3D
@onready var _camera_view: CameraView = $PCam_Seagull/CameraView

var velocity := Vector3.ZERO
var _state := State.FLOCK
var _state_timer := 0.0
var _think_timer := 0.0
var _dive_cooldown := 0.0
var _affinity := 1.0
var _hover_height := 15.0
var _wander_angle := 0.0
var _breakaway_timer := 0.0
var _solo_target := Vector3.ZERO
var _flock_steer := Vector3.ZERO
var _forward := Vector3.FORWARD


func _ready() -> void:
	add_to_group("seagulls")
	if terrain == null:
		push_error("%s: no node named Terrain3D in the tree" % get_path())
	if _player == null:
		push_error("%s: no node in group 'player'" % get_path())
	_affinity = randf_range(0.3, 1.0)
	_hover_height = randf_range(hover_min, hover_max)
	_wander_angle = randf() * TAU
	_forward = Vector3(cos(_wander_angle), 0.0, sin(_wander_angle))
	velocity = _forward * randf_range(min_speed, max_speed)
	_think_timer = randf() * think_interval
	_dive_cooldown = randf() * dive_cooldown.y
	animation_tree.active = true
	animation_tree.set(wings_blend_param, 0.0)
	_flap_timer = randf() * flap_interval_mean
	CameraDirector.view_changed.connect(_on_camera_view_changed)
	_think()


func _physics_process(delta: float) -> void:
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = think_interval
		_think()
	match _state:
		State.FLOCK:
			_apply_motion(_current_dir() * _cruise_speed() + _flock_steer * max_speed, turn_rate, max_accel, max_speed, delta)
		State.DIVE:
			_update_dive(delta)
		State.RECOVER:
			_update_recover(delta)
	_state_timer -= delta
	_clamp_to_floor()
	_update_facing(delta)
	_update_wings(delta)
	_update_sing(delta)

func _think() -> void:
	_dive_cooldown = maxf(_dive_cooldown - think_interval, 0.0)
	if _state != State.FLOCK:
		return
	if _try_dive():
		return
	_update_breakaway()
	_flock_steer = _compute_flock_steer()


func _try_dive() -> bool:
	if _dive_cooldown > 0.0 or not is_instance_valid(_player):
		return false
	var to_player : Vector3 = _player.global_position - global_position
	var flat_to_player := Vector3(to_player.x, 0.0, to_player.z)
	var flat_vel := Vector3(velocity.x, 0.0, velocity.z)
	var speed_sq := flat_vel.length_squared()
	if flat_to_player.length() > dive_detect_radius or speed_sq < 0.01:
		return false
	var t := flat_to_player.dot(flat_vel) / speed_sq
	if t <= 0.0 or t > dive_lookahead:
		return false
	var miss := (flat_to_player - flat_vel * t).length()
	if miss > dive_pass_radius:
		return false
	_dive_cooldown = randf_range(dive_cooldown.x, dive_cooldown.y)
	if randf() > dive_chance:
		return false
	_state = State.DIVE
	_state_timer = dive_max_time
	return true


func _update_dive(delta: float) -> void:
	if not is_instance_valid(_player):
		_start_recover()
		return
	var target : Vector3 = _player.global_position + Vector3.UP * (head_offset + dive_clearance)
	var to_target := target - global_position
	var flat_to_player := Vector3(_player.global_position.x - global_position.x, 0.0, _player.global_position.z - global_position.z)
	var flat_vel := Vector3(velocity.x, 0.0, velocity.z)
	if to_target.length() < 2.0 or flat_to_player.dot(flat_vel) < 0.0 or _state_timer <= 0.0:
		_start_recover()
		return
	var top := max_speed * dive_speed_mult
	_apply_motion(to_target.normalized() * top, dive_turn_rate, max_accel * 2.0, top, delta)


func _start_recover() -> void:
	_state = State.RECOVER
	_state_timer = recover_time


func _update_recover(delta: float) -> void:
	if _state_timer <= 0.0:
		_state = State.FLOCK
		_think()
		return
	_apply_motion(_current_dir() * max_speed + Vector3.UP * max_speed * 0.3, turn_rate * 1.5, max_accel, max_speed, delta)


func _apply_motion(desired: Vector3, rate: float, accel: float, top_speed: float, delta: float) -> void:
	var cur := _current_dir()
	var new_dir := cur
	if desired.length() > 0.01:
		new_dir = _rotate_toward(cur, desired.normalized(), rate * delta)
	var want := clampf(desired.length(), min_speed, top_speed)
	var new_speed := move_toward(velocity.length(), want, accel * delta)
	velocity = new_dir * new_speed
	_forward = new_dir
	global_position += velocity * delta


func _compute_flock_steer() -> Vector3:
	var nearby := _neighbors()
	var steer := Vector3.ZERO
	if _breakaway_timer > 0.0:
		steer += _seek(_solo_target)
	else:
		steer += _separation(nearby) * separation_weight
		steer += _alignment(nearby) * alignment_weight * _affinity
		steer += _cohesion(nearby) * cohesion_weight * _affinity
	steer += _island_steer() * island_weight
	steer += _altitude_steer() * altitude_weight
	steer += _terrain_steer() * terrain_weight
	steer += _obstacle_steer() * obstacle_weight
	steer += _wander_steer() * wander_weight
	return steer


func _neighbors() -> Array[AnimalSeagull]:
	var out: Array[AnimalSeagull] = []
	for node in get_tree().get_nodes_in_group("seagulls"):
		var other := node as AnimalSeagull
		if other == null or other == self or other._state != State.FLOCK:
			continue
		if global_position.distance_squared_to(other.global_position) <= neighbor_radius * neighbor_radius:
			out.append(other)
	return out


func _separation(nearby: Array[AnimalSeagull]) -> Vector3:
	var steer := Vector3.ZERO
	for other in nearby:
		var offset := global_position - other.global_position
		var d := offset.length()
		if d < separation_radius and d > 0.01:
			steer += offset / d * (1.0 - d / separation_radius)
	return steer.normalized()


func _alignment(nearby: Array[AnimalSeagull]) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for other in nearby:
		if global_position.distance_to(other.global_position) <= alignment_radius:
			sum += other.velocity
			n += 1
	return (sum / float(n)).normalized() if n > 0 else Vector3.ZERO


func _cohesion(nearby: Array[AnimalSeagull]) -> Vector3:
	var center := Vector3.ZERO
	var n := 0
	for other in nearby:
		if global_position.distance_to(other.global_position) <= cohesion_radius:
			center += other.global_position
			n += 1
	if n == 0:
		return Vector3.ZERO
	return (center / float(n) - global_position).normalized()


func _island_steer() -> Vector3:
	var flat := Vector3(flight_center.x - global_position.x, 0.0, flight_center.z - global_position.z)
	var dist := flat.length()
	var soft := island_radius * 0.8
	if dist < soft:
		return Vector3.ZERO
	return flat.normalized() * clampf((dist - soft) / (island_radius - soft), 0.0, 2.0)


func _altitude_steer() -> Vector3:
	var target_y := _ground_at(global_position) + _hover_height
	return Vector3.UP * clampf((target_y - global_position.y) / hover_max, -1.0, 1.0)


func _terrain_steer() -> Vector3:
	var ahead := global_position + velocity * terrain_lookahead
	var needed := maxf(_ground_at(ahead), _ground_at(global_position)) + min_ground_clearance
	var lift := needed - global_position.y
	if lift <= 0.0:
		return Vector3.ZERO
	return Vector3.UP * clampf(lift / min_ground_clearance, 0.0, 2.0)


func _obstacle_steer() -> Vector3:
	var space := get_world_3d().direct_space_state
	var dir := _current_dir()
	var steer := Vector3.ZERO
	for angle in [0.0, 0.6, -0.6]:
		var d: Vector3 = dir.rotated(Vector3.UP, angle)
		var query := PhysicsRayQueryParameters3D.create(global_position, global_position + d * obstacle_probe_distance, obstacle_mask)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var closeness := 1.0 - global_position.distance_to(hit["position"]) / obstacle_probe_distance
		steer += (hit["normal"] as Vector3) * closeness
	return steer


func _wander_steer() -> Vector3:
	_wander_angle += randf_range(-wander_jitter, wander_jitter)
	return Vector3(cos(_wander_angle), 0.0, sin(_wander_angle))


func _update_breakaway() -> void:
	if _breakaway_timer > 0.0:
		_breakaway_timer -= think_interval
	elif randf() < breakaway_chance:
		_breakaway_timer = randf_range(breakaway_time.x, breakaway_time.y)
		var a := randf() * TAU
		var r := sqrt(randf()) * island_radius * 0.7
		_solo_target = flight_center + Vector3(cos(a) * r, 0.0, sin(a) * r)
		_solo_target.y = _ground_at(_solo_target) + _hover_height


func _seek(target: Vector3) -> Vector3:
	var d := target - global_position
	return d.normalized() if d.length() > 0.01 else Vector3.ZERO


func _ground_at(p: Vector3) -> float:
	if terrain == null or terrain.data == null:
		return 0.0
	var h: float = terrain.data.get_height(Vector3(p.x, 0.0, p.z))
	return 0.0 if is_nan(h) else h


func _clamp_to_floor() -> void:
	var floor_y := _ground_at(global_position) + hard_floor_clearance
	if global_position.y < floor_y:
		global_position.y = floor_y
		velocity.y = maxf(velocity.y, 0.0)


func _current_dir() -> Vector3:
	return velocity.normalized() if velocity.length() > 0.1 else _forward


func _cruise_speed() -> float:
	return (min_speed + max_speed) * 0.5


func _rotate_toward(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var angle := from.angle_to(to)
	if angle < 1e-4:
		return to
	var axis := from.cross(to)
	axis = axis.normalized() if axis.length() > 1e-4 else Vector3.UP
	return from.rotated(axis, minf(angle, max_angle)).normalized()


func _update_facing(delta: float) -> void:
	var dir := _current_dir().normalized()
	var up_vec := Vector3.UP
	if absf(dir.dot(Vector3.UP)) > 0.999:
		up_vec = Vector3.RIGHT
	var target_basis := Basis.looking_at(dir, up_vec, model_faces_positive_z)
	global_basis = global_basis.orthonormalized().slerp(target_basis, 1.0 - exp(-face_smoothing * delta))

func _update_wings(delta: float) -> void:
	_flap_timer -= delta
	if _flap_timer <= 0.0:
		_flapping = not _flapping
		if _flapping:
			_flap_timer = randf_range(flap_duration.x, flap_duration.y)
		else:
			_flap_timer = maxf(randfn(flap_interval_mean, flap_interval_sd), flap_interval_min)
	var target := 1.0 if _flapping else 0.0
	_wings_blend = lerpf(_wings_blend, target, 1.0 - exp(-wings_blend_speed * delta))
	animation_tree.set(wings_blend_param, _wings_blend)

func _on_camera_view_changed(previous: StringName, current: StringName) -> void:
	var mine := _camera_view.view_name
	if current == mine and previous != mine:
		_sing_timer = sing_delay
	elif current != mine:
		_sing_timer = -1.0  # left the view before the cry landed


func _update_sing(delta: float) -> void:
	if _sing_timer < 0.0:
		return
	_sing_timer -= delta
	if _sing_timer <= 0.0:
		_sing_timer = -1.0
		_sound_emitter.play()