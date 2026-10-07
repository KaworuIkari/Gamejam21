extends Node

@onready var tree: AnimationTree = $"../AnimationTree"
@onready var player: RealController = $".."
@onready var character: Node3D = $"../Robot"
@onready var collision_shape_3d: CollisionShape3D = $"../CollisionShape3D"

var top_pb: AnimationNodeStateMachinePlayback
var idle_pb: AnimationNodeStateMachinePlayback

# Advanced Expression
var is_moving : bool = false
var is_walking : bool = false
var is_running : bool = false
var is_jumping : bool = false
var is_falling : bool = false

# locomotion
var target_direction: Vector2 = Vector2.ZERO
var blendspace_tweak : float = 12.0

# random idle
@export var idle_variant_chance := 1.0
var idle_variants: Array[StringName] = [&"V1", &"V2", &"V3", &"V4"]
var idle_default_active := false   # true while top = Idle and nested = Idle_default
var idle_default_elapsed := 0.0    # seconds since Idle_default started playing

# Anti-input spamming / jamming
@export var idle_debounce_time: float = 0.12 # tweak this value, e.g. 0.1~0.2
var idle_debounce_timer: float = 0.0
var can_enter_idle: bool = false

# foot IK
@onready var skeleton : Skeleton3D = $"../Robot/root/Skeleton3D"
@onready var left_foot_ik: SkeletonIK3D = $"../Robot/root/Skeleton3D/LeftFootIK"
@onready var left_foot_target: Marker3D = $LeftFootTarget
@onready var left_foot_ray: RayCast3D = $LeftFootRay
@onready var right_foot_ik: SkeletonIK3D = $"../Robot/root/Skeleton3D/RightFootIK"
@onready var right_foot_target: Marker3D = $RightFootTarget
@onready var right_foot_ray: RayCast3D = $RightFootRay

@export_group("IK Tuning")
@export var raycast_start_offset : float = 0.3  # Height above foot origin where ray starts
@export var foot_height_offset : float = 0.05  # Distance from foot bone origin to sole bottom
@export var lerp_speed : float = 5.0

@export var airborne_threshold : float = 0.15
@export_group("Foot Anchors")
@onready var left_foot_anchor : BoneAttachment3D = $"../Robot/root/Skeleton3D/LeftFootAnchor"
@onready var right_foot_anchor : BoneAttachment3D = $"../Robot/root/Skeleton3D/RightFootAnchor"
var left_ik_weight : float = 1.0
var right_ik_weight : float = 1.0

# path references
var top_pb_pos = "parameters/AnimationNodeStateMachine/playback"
var idle_pb_pos = "parameters/AnimationNodeStateMachine/Idle/playback"
var walk_blend_pos = "parameters/AnimationNodeStateMachine/Locomotion/WalkBlend/blend_position"
var run_blend_pos = "parameters/AnimationNodeStateMachine/Locomotion/RunBlend/blend_position"


func _ready():
	tree.advance_expression_base_node = get_path()
	top_pb = tree.get(top_pb_pos)
	idle_pb = tree.get(idle_pb_pos)
	
	if left_foot_ik:
		left_foot_ik.start()
	left_foot_ray.add_exception(player)
	if right_foot_ik:
		right_foot_ik.start()
	right_foot_ray.add_exception(player)

func _process(delta: float) -> void:
	if player == null or tree == null:
		return
		
	is_walking = player.is_walking
	is_running = player.is_sprinting
	is_moving = is_walking or is_running
	is_jumping = player.is_jumping
	is_falling = not player.is_on_floor() and player.velocity.y <= 0
	
	debounce(delta)
	random_idle(delta)
	
	if player.input_dir != Vector2.ZERO:
		var anim_dir := get_anim_direction(player.input_dir)
		rotate_toward_camera(delta, player.input_dir)
		set_blend_vec(delta, anim_dir)
	
	left_ik_weight = _update_foot_ik(left_foot_ray, left_foot_target, left_foot_anchor, left_foot_ik, left_ik_weight, delta)
	right_ik_weight = _update_foot_ik(right_foot_ray, right_foot_target, right_foot_anchor, right_foot_ik, right_ik_weight, delta)

func debounce(delta: float) -> void:
	# in case player tap left and right quickly
	if is_moving:
		idle_debounce_timer = 0.0
		can_enter_idle = false
	else:
		idle_debounce_timer += delta
		can_enter_idle = idle_debounce_timer >= idle_debounce_time

func set_blend_vec(delta : float, target_blend : Vector2) -> void:
	var current_walk = tree.get(walk_blend_pos)
	var smooth_walk = current_walk.lerp(target_blend, delta * blendspace_tweak)
	tree.set(walk_blend_pos, smooth_walk)
	
	var current_run = tree.get(run_blend_pos)
	var smooth_run = current_run.lerp(target_blend, delta * blendspace_tweak)
	tree.set(run_blend_pos, smooth_run)
	
func random_idle(delta: float) -> void:
	var is_idle_default := top_pb.get_current_node() == &"Idle" \
		and idle_pb.get_current_node() == &"Idle_default"

	if not is_idle_default:
		idle_default_active = false
		return

	if not idle_default_active:
		# just entered: start counting from zero
		idle_default_active = true
		idle_default_elapsed = 0.0
		return

	idle_default_elapsed += delta
	var idle_default_length := idle_pb.get_current_length()
	if idle_default_length > 0.0 and idle_default_elapsed >= idle_default_length:
		idle_default_elapsed -= idle_default_length   # one loop completed
		if randf() < idle_variant_chance:
			idle_pb.travel(idle_variants.pick_random())
	
# Snap input to 45° sectors, return which of the 4 animations to blend.
func get_anim_direction(input_dir: Vector2) -> Vector2:
	var s := roundi(atan2(input_dir.x, -input_dir.y) / (PI / 4.0))   # -4..4
	var side := signi(s)
	match absi(s):
		0, 1: return Vector2(0, 1)        # forward and forward-diagonals
		2:    return Vector2(side, 0)     # strafe
		_:    return Vector2(0, -1)       # back-diagonals and backward (3, 4)
	
func rotate_toward_camera(delta: float, input_dir: Vector2) -> void:
	var s := roundi(atan2(input_dir.x, -input_dir.y) / (PI / 4.0))
	var side := signi(s)
	var off := 0
	match absi(s):
		1: off = s
		3: off = s - 4 * side
	var target := player.camera_pivot.rotation.y + PI - off * PI / 4.0
	character.rotation.y = lerp_angle(character.rotation.y, target, player.rotation_speed * delta)
	
func _update_foot_ik(ray: RayCast3D, marker: Marker3D, anchor: BoneAttachment3D, ik_solver: SkeletonIK3D, current_weight: float, delta: float) -> float:
	var anim_pos : Vector3 = anchor.global_position if anchor else marker.global_position
	var anim_basis : Basis = anchor.global_transform.basis if anchor else marker.global_transform.basis

	ray.global_position = Vector3(anim_pos.x, anim_pos.y + raycast_start_offset, anim_pos.z)
	ray.force_raycast_update()

	var target_pos : Vector3 = anim_pos
	var target_normal : Vector3 = Vector3.UP
	var target_weight : float = 0.0

	if ray.is_colliding():
		var hit_point : Vector3 = ray.get_collision_point()
		var ground_y : float = hit_point.y + foot_height_offset
		target_normal = ray.get_collision_normal()
		var delta_y : float = ground_y - anim_pos.y
		if is_moving:
			# MOVING: Only allow foot to raise above raw animation position
			if delta_y > 0.0 and delta_y < airborne_threshold:
				target_pos.y = ground_y
				target_weight = 1.0
			else:
				target_pos.y = anim_pos.y
				target_weight = 0.0
		else:
			# STANDING STILL: Snap to ground whether higher or lower
			if abs(delta_y) < airborne_threshold:
				target_pos.y = ground_y
				target_weight = 1.0
			else:
				target_weight = 0.0
	
	var new_weight : float = lerp(current_weight, target_weight, delta * lerp_speed)
	if ik_solver:
		ik_solver.interpolation = new_weight
	marker.global_position = marker.global_position.lerp(target_pos, delta * lerp_speed)
	_align_marker_to_normal(marker, anim_basis, target_normal, delta)
	return new_weight

func _align_marker_to_normal(marker: Marker3D, anim_basis: Basis, normal: Vector3, delta: float) -> void:
	var tilt_rotation: Quaternion = Quaternion(Vector3.UP, normal)
	var target_basis: Basis = Basis(tilt_rotation) * anim_basis
	marker.global_transform.basis = marker.global_transform.basis.slerp(target_basis, delta * lerp_speed)
