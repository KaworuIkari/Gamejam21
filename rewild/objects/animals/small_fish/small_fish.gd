# AnimalSmallFish.gd
extends CharacterBody3D
class_name AnimalSmallFish
## Small schooling fish with dual‑state behaviour: BOID / ROAM
## Required children: CollisionShape3D (capsule) + Edible node

enum FishState { BOID, ROAM }

@export var water_volume: WaterVolume
@export var boids_refresh_interval := 1.0  # seconds; how often we search neighbors / recalc boid forces
var _boids_refresh_timer := 0.0

# Cached boid steering vectors (re‑used across multiple physics frames)
var _cached_separation := Vector3.ZERO
var _cached_alignment := Vector3.ZERO
var _cached_cohesion := Vector3.ZERO
var _cached_bounds := Vector3.ZERO

@export_group("Boids")
@export var max_speed := 2.5 # Reduced per requirement
@export var acceleration := 3.0
@export var turn_speed := 3.5 # rad/s heading change
@export var separation_radius := 1.5
@export var alignment_radius := 4.0
@export var cohesion_radius := 6.0
@export var separation_weight := 1.5
@export var alignment_weight := 1.0
@export var cohesion_weight := 1.0
@export var bounds_weight := 2.5

@export_group("Roaming")
@export var roam_duration_min := 2.0
@export var roam_duration_max := 5.0
@export var boid_duration_min := 3.0
@export var boid_duration_max := 7.0
var _fish_state: FishState = FishState.ROAM
var _state_timer := 0.0
var _roam_target_dir: Vector3

@export_group("Body")
@export var clearance := 0.3
@export var model_faces_positive_z := true
@export var face_smoothing := 8.0
var _radius := 0.5
var _room := 0.8
var _forward_dir := Vector3.FORWARD

@export var target_group_size := 3          # desired fish per school
@export var partner_repick_interval := 2.5  # seconds: how often fish pick new group partners
var _group_partners: Array[CharacterBody3D] = []
var _repick_timer := 0.0

@export var wander_strength := 0.4
@export var wander_change_rate := 0.2
var _wander_dir: Vector3
var _cached_wander := Vector3.ZERO

@export_group("Debug")
@export var debug := true
@onready var debug_label: Label3D = $DebugLabel3D
@export var boundary_margin := 6.0  # start repelling when within this distance from water limits

# === Lifecycle ===
func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING # Underwater: no gravity
	add_to_group("small_fish") # For boids neighbor queries
	_read_body_size()
	_room = _radius + clearance

	if water_volume == null:
		push_error("AnimalSmallFish: WaterVolume not found")
		set_physics_process(false)
		return

	# Random initial horizontal direction
	var xy = Vector2.from_angle(randf() * TAU)
	_forward_dir = Vector3(xy.x, 0.0, xy.y).normalized()
	velocity = _forward_dir * max_speed * randf_range(0.7, 1.0)
	xy = Vector2.from_angle(randf()*TAU)
	_wander_dir = Vector3(xy.x, 0.0, xy.y).normalized()

	# initial state
	_switch_state(FishState.BOID)

func _physics_process(delta: float) -> void:
	# State machine timer
	_state_timer -= delta
	if _state_timer <= 0.0:
		if _fish_state == FishState.BOID:
			_switch_state(FishState.ROAM)
		else:
			_switch_state(FishState.BOID)

	# Throttle expensive boids neighbor search / partner picking
	_boids_refresh_timer -= delta
	var need_refresh := _boids_refresh_timer <= 0.0
	if need_refresh:
		_boids_refresh_timer = boids_refresh_interval
		_repick_timer -= boids_refresh_interval
		var nearby := _get_nearby_fish()
		# repick partners only when repick timer expires
		if _repick_timer <= 0.0:
			_pick_new_group_partners()
			_repick_timer = partner_repick_interval
		# Re‑compute all heavy boid forces ONCE every refresh interval
		_cached_separation = _separation(nearby)
		_cached_alignment = _alignment(nearby)
		_cached_cohesion = _cohesion(nearby)
		_cached_bounds = _bounds_steering()
		# add random horizontal wander noise
		var z: float = randf_range(-1.0, 1.0)
		var phi: float = randf_range(0.0, TAU)
		var r: float = sqrt(1.0 - z * z)
		_cached_wander = Vector3(r * cos(phi), r * sin(phi), z)
	var desired_vel := Vector3.ZERO
	if _fish_state == FishState.BOID:
		desired_vel = (
			_cached_separation * separation_weight +
			_cached_alignment * alignment_weight +
			_cached_cohesion * cohesion_weight +
			_cached_bounds * bounds_weight +
			_cached_wander
		)
		# Important fix: low boid force → use wander direction
		if desired_vel.length() < 0.1:
			desired_vel = _cached_wander * max_speed
		else:
			desired_vel = desired_vel.normalized() * max_speed
	else: # ROAM state
		# Base roam direction
		desired_vel = _roam_target_dir * max_speed
		# Add boundary repulsion force for roaming fish
		desired_vel += _cached_bounds * bounds_weight

		# After adding repulsion, re‑normalize to preserve max_speed
		if desired_vel.length() > 0.001:
			desired_vel = desired_vel.normalized() * max_speed
		else:
			# Fallback if vector collapses to zero
			desired_vel = _roam_target_dir * max_speed

	var current_dir := velocity.normalized() if velocity.length() > 0.1 else _forward_dir
	var new_dir := _rotate_toward(current_dir, desired_vel.normalized(), turn_speed * delta)
	var target_speed := desired_vel.length()
	var current_speed := velocity.length()
	var new_speed := move_toward(current_speed, target_speed, acceleration * delta)

	velocity = new_dir * new_speed
	_forward_dir = new_dir

	# Keep only as absolute emergency safety; avoid per‑frame positional teleport driving fish to shore
	var safe_pos := water_volume.clamp_to_water(global_position, _room)
	if global_position.distance_squared_to(safe_pos) > 4.0:
		global_position = safe_pos

	move_and_slide()
	_update_facing(delta)
	_update_debug(delta)

func _switch_state(new_state: FishState) -> void:
	_fish_state = new_state
	if _fish_state == FishState.BOID:
		_state_timer = randf_range(boid_duration_min, boid_duration_max)
	else:
		_state_timer = randf_range(roam_duration_min, roam_duration_max)
		_roam_target_dir = _cached_wander

# === Body Size Detection ===
func _read_body_size() -> void:
	for c in get_children():
		if c is CollisionShape3D and c.shape is CapsuleShape3D:
			_radius = c.shape.radius
			break
	_room = _radius + clearance

# === Boids Core ===
func _get_nearby_fish() -> Array[CharacterBody3D]:
	var nearby : Array[CharacterBody3D] = []
	for node in get_tree().get_nodes_in_group("small_fish"):
		if node == self:
			continue
		if global_position.distance_to(node.global_position) <= cohesion_radius:
			nearby.append(node)
	return nearby

func _separation(nearby: Array[CharacterBody3D]) -> Vector3:
	var steer := Vector3.ZERO
	var count := 0
	for fish in nearby:
		var dist := global_position.distance_to(fish.global_position)
		if dist < separation_radius and dist > 0.001:
			var away := global_position - fish.global_position
			away /= dist
			steer += away
			count +=1
	if count > 0:
		steer /= count
	steer.y = 0.0
	return steer

func _alignment(_nearby: Array[CharacterBody3D]) -> Vector3:
	_group_partners = _filter_valid_fish(_group_partners)
	var avg_vel := Vector3.ZERO
	var count := 0
	for fish in _group_partners:
		avg_vel += fish.velocity
		count +=1
	if count > 0:
		avg_vel /= count
		avg_vel.y = 0.0
		return avg_vel.normalized()
	return Vector3.ZERO

func _cohesion(_nearby: Array[CharacterBody3D]) -> Vector3:
	_group_partners = _filter_valid_fish(_group_partners)
	var center := Vector3.ZERO
	var count :=0
	for fish in _group_partners:
		center += fish.global_position
		count +=1
	if count > 0:
		center /= count
		var to_center := center - global_position
		to_center.y = 0.0
		return to_center.normalized()
	return Vector3.ZERO

func _bounds_steering() -> Vector3:
	var xz := Vector2(global_position.x, global_position.z)
	var band := water_volume.get_safe_band(xz, _room)
	if band.x > band.y:
		return Vector3.ZERO
	var steer := Vector3.ZERO
	# Vertical repel: near surface
	var dist_to_surface := (water_volume._surface_y - _room) - global_position.y
	if dist_to_surface < boundary_margin:
		steer.y -= remap(dist_to_surface, boundary_margin, 0.0, 0.0, 1.0)
	# Vertical repel: near seabed
	var dist_to_floor := global_position.y - (band.x)
	if dist_to_floor < boundary_margin:
		steer.y += remap(dist_to_floor, boundary_margin, 0.0, 0.0, 1.0)
	# Horizontal lake‑plane edges repulsion
	var clamped_xz := water_volume.clamp_xz(xz, _room + boundary_margin)
	var dx := xz.x - clamped_xz.x
	var dz := xz.y - clamped_xz.y
	if abs(dx) > 0.001:
		steer.x += remap(abs(dx), boundary_margin, 0.0, 0.0, sign(dx))
	if abs(dz) > 0.001:
		steer.z += remap(abs(dz), boundary_margin, 0.0, 0.0, sign(dz))
	return steer

# === Movement Helpers ===
func _rotate_toward(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var angle := from.angle_to(to)
	if angle < 1e-4:
		return to
	var axis := from.cross(to)
	axis = axis.normalized() if axis.length() > 1e-4 else Vector3.UP
	return from.rotated(axis, minf(angle, max_angle)).normalized()

func _update_facing(delta: float) -> void:
	var dir := velocity
	if dir.length() < 0.1:
		dir = _forward_dir
	dir = dir.normalized()
	# Detect when forward is nearly parallel to UP
	var dot : float = abs(dir.dot(Vector3.UP))
	var up_vec := Vector3.UP
	if dot > 0.999:
		# near straight up/down → switch fallback up vector to RIGHT to avoid singularity
		up_vec = Vector3.RIGHT
	var target_basis := Basis.looking_at(dir, up_vec, model_faces_positive_z)
	global_basis = global_basis.orthonormalized().slerp(target_basis, 1.0 - exp(-face_smoothing * delta))

func _update_debug(_delta:float) -> void:
	if not debug or debug_label == null:
		debug_label.visible = false
		return
	debug_label.visible = true
	var nearby := _get_nearby_fish()
	var spd := velocity.length()
	var state_name = "BOID" if _fish_state == FishState.BOID else "ROAM"
	debug_label.text = """%s
Speed: %.2f
Neighbors: %d
Sep: %.2f  Ali: %.2f  Coh: %.2f""" % [
		state_name,
		spd,
		nearby.size(),
		_separation(nearby).length(),
		_alignment(nearby).length(),
		_cohesion(nearby).length()
	]
	debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	debug_label.no_depth_test = true

# Select up to target_group_size random nearby fish as alignment/cohesion partners
func _pick_new_group_partners():
	var all_neighbors := _get_nearby_fish()
	# filter out any already‑freed fish
	all_neighbors = _filter_valid_fish(all_neighbors)
	if all_neighbors.is_empty():
		return
	# sort neighbors by distance (closer fish preferred for group)
	all_neighbors.sort_custom(func(a,b):
		return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position)
	)
	# take closest N fish as group partners
	var take : int = min(target_group_size, all_neighbors.size())
	for i in range(take):
		_group_partners.append(all_neighbors[i])

# Remove any freed / invalid fish from an array
func _filter_valid_fish(list: Array[CharacterBody3D]) -> Array[CharacterBody3D]:
	var out : Array[CharacterBody3D]= []
	for f in list:
		if is_instance_valid(f):
			out.append(f)
	return out
