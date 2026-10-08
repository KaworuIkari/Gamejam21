class_name FootIKModifier
extends SkeletonModifier3D

@export_group("IK References")
@export var player: CharacterBody3D
@export var ray_left: RayCast3D
@export var ray_right: RayCast3D
@export var marker_left: Marker3D
@export var marker_right: Marker3D
@export var left_foot_ik : TwoBoneIK3D
@export var right_foot_ik : TwoBoneIK3D

const left_foot_bone: StringName = &"foot.l"
const right_foot_bone: StringName = &"foot.r"

@export_group("IK Tuning")
@export var raycast_start_offset: float = 0.3
## Do not change these, unless you are seeing weird leg bending issues!!!
@export var foot_height_offset: float = 0.2
@export var standing_lerp_speed: float = 5.0
@export var airborne_threshold: float = 0.1
@export var debug : bool = false

var left_ik_weight: float = 1.0
var right_ik_weight: float = 1.0

func _ready() -> void:
	ray_left.add_exception(player)
	ray_right.add_exception(player)

func _process_modification_with_delta(delta : float) -> void:
	var is_moving: bool = player.velocity.length_squared() > 0.05

	left_ik_weight = _update_foot(left_foot_bone, ray_left, marker_left, left_ik_weight, is_moving, delta)
	right_ik_weight = _update_foot(right_foot_bone, ray_right, marker_right, right_ik_weight, is_moving, delta)
	left_foot_ik.influence = left_ik_weight
	right_foot_ik.influence = right_ik_weight

func _update_foot(bone_name: StringName,ray: RayCast3D,marker: Marker3D,current_weight: float,is_moving: bool,delta: float) -> float:
	var skeleton: Skeleton3D = get_skeleton()
	var bone_idx: int = skeleton.find_bone(bone_name)
	if bone_idx == -1:
		return 0.0

	# Because _process_modification() runs BEFORE IK overrides are applied,
	# get_bone_global_pose() returns the untransformed, raw AnimationTree pose!
	var anim_pose: Transform3D = skeleton.get_bone_global_pose(bone_idx)
	var anim_global_pos: Vector3 = skeleton.global_transform * anim_pose.origin
	ray.global_position = Vector3(anim_global_pos.x, anim_global_pos.y + raycast_start_offset, anim_global_pos.z)
	ray.force_raycast_update()

	var target_pos: Vector3 = anim_global_pos
	var target_normal: Vector3 = Vector3.UP
	var target_weight: float = 0.0
	var new_weight: float = 0.0

	if ray.is_colliding():
		var ground_point: Vector3 = ray.get_collision_point()
		var ground_y: float = ground_point.y + foot_height_offset
		target_normal = ray.get_collision_normal()

		var delta_y: float = ground_y - anim_global_pos.y
		if not is_moving:
			# STANDING: Snap to ground whether higher or lower
			if abs(delta_y) < airborne_threshold:
				target_pos.y = ground_y
				_set_foot_bone_rotation(skeleton, bone_idx, target_normal, delta)
				target_weight = 1.0
			else:
				target_weight = 0.0
			new_weight = lerp(current_weight, target_weight, delta * standing_lerp_speed)
			marker.global_position = marker.global_position.lerp(target_pos, delta * standing_lerp_speed)
			return new_weight
	new_weight = lerp(current_weight, 0.0, delta * standing_lerp_speed)
	return new_weight

func _set_foot_bone_rotation(skeleton: Skeleton3D, bone_idx: int, normal: Vector3, delta:float) -> void:
	var bone_model_pose: Transform3D = skeleton.get_bone_global_pose(bone_idx)
	var B_anim_model: Basis = bone_model_pose.basis
	var B_skeleton_world: Basis = skeleton.global_transform.basis
	var B_anim_world: Basis = B_skeleton_world * B_anim_model
	
	var anim_forward: Vector3 = B_anim_world.y
	# Project foot forward onto ground plane
	var slope_forward: Vector3 = anim_forward.slide(normal).normalized()
	if slope_forward.length_squared() < 0.001:
		slope_forward = anim_forward
	
	# Build ground slope basis (world space): X=Right, Y=Forward, Z=Up
	var bone_up: Vector3 = normal
	var bone_forward : Vector3 = slope_forward.normalized()
	var bone_right : Vector3 = bone_forward.cross(bone_up).normalized()
	var B_ground_slope_world: Basis = Basis(bone_right, bone_forward, bone_up).orthonormalized()
	
	# Build flat reference ground basis (world space, normal=UP, same forward)
	var flat_up: Vector3 = Vector3.UP
	var flat_forward: Vector3 = anim_forward.slide(Vector3.UP).normalized()
	if flat_forward.length_squared() < 0.001:
		flat_forward = anim_forward
	var flat_right: Vector3 = flat_forward.cross(flat_up).normalized()
	var B_ground_flat_world: Basis = Basis(flat_right, flat_forward, flat_up).orthonormalized()
	
	# The key: get the foot's animated rotation RELATIVE to flat ground
	var relative_rot_world: Basis = B_ground_flat_world.inverse() * B_anim_world
	# Apply that same relative rotation onto sloped ground
	var target_world_basis: Basis = B_ground_slope_world * relative_rot_world
	
	# Basis to snap to if not slerping
	#var target_model_basis: Basis = B_skeleton_world.inverse() * target_world_basis
	
	# slerp to it, note that current_world_basis is after IK, different from B_anim_world
	var current_world_basis: Basis = B_skeleton_world * skeleton.get_bone_global_pose(bone_idx).basis
	var slerped_world_basis: Basis
	slerped_world_basis = current_world_basis.slerp(target_world_basis, delta * standing_lerp_speed).orthonormalized()
	var slerped_model_basis: Basis = B_skeleton_world.inverse() * slerped_world_basis
	var new_pose := Transform3D(slerped_model_basis, bone_model_pose.origin)
	skeleton.set_bone_global_pose(bone_idx, new_pose)

	if debug:
		var origin: Vector3 = skeleton.global_transform * bone_model_pose.origin
		DebugNode.draw_vector(get_tree(), origin, anim_forward, Color.RED, 0.5)
		DebugNode.draw_vector(get_tree(), origin, slope_forward, Color.GREEN, 0.3)
		DebugNode.draw_vector(get_tree(), origin, target_world_basis.y, Color.BLUE, 0.5)
