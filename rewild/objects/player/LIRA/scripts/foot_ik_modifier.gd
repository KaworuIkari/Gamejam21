class_name FootIKModifier
extends SkeletonModifier3D

@export_group("IK References")
@export var player: CharacterBody3D
@export var ray_left: RayCast3D
@export var ray_right: RayCast3D
@export var marker_left: Marker3D
@export var marker_right: Marker3D
@export var left_foot_ik: TwoBoneIK3D
@export var right_foot_ik: TwoBoneIK3D

const left_foot_bone: StringName = &"foot.l"
const right_foot_bone: StringName = &"foot.r"

@export_group("IK Tuning")
@export var raycast_start_offset: float = 0.3
@export var foot_height_offset: float = 0.2
@export var standing_lerp_speed: float = 5.0
@export var airborne_threshold: float = 0.1

var left_ik_weight := 0.0
var right_ik_weight := 0.0
var _tilt := {}   # bone_idx -> Quaternion (world-space tilt, persists across frames)

func _ready() -> void:
	ray_left.add_exception(player)
	ray_right.add_exception(player)

func _process_modification_with_delta(delta: float) -> void:
	var k := 1.0 - exp(-standing_lerp_speed * delta)   # frame-rate independent, never overshoots
	var is_moving : bool = player.velocity.length()>0.1
	left_ik_weight  = _update_foot(left_foot_bone,  ray_left,  marker_left,  left_ik_weight,  is_moving, k)
	right_ik_weight = _update_foot(right_foot_bone, ray_right, marker_right, right_ik_weight, is_moving, k)
	left_foot_ik.influence  = left_ik_weight
	right_foot_ik.influence = right_ik_weight

func _update_foot(bone_name: StringName, ray: RayCast3D, marker: Marker3D,
		current_weight: float, is_moving: bool, k: float) -> float:
	var skeleton := get_skeleton()
	var bone_idx := skeleton.find_bone(bone_name)
	if bone_idx == -1:
		push_warning("Foot bone not found: %s" % bone_name)
		return 0.0

	# Raw animated pose (this modifier must run before the IK nodes)
	var anim_pose := skeleton.get_bone_global_pose(bone_idx)
	var anim_global_pos := skeleton.global_transform * anim_pose.origin

	ray.global_position = anim_global_pos + Vector3.UP * raycast_start_offset
	ray.force_raycast_update()

	# Decide this frame's targets; the defaults mean "fade out"
	var target_pos := anim_global_pos
	var target_weight := 0.0
	var target_tilt := Quaternion.IDENTITY

	if not is_moving and ray.is_colliding():
		var ground_y := ray.get_collision_point().y + foot_height_offset
		if abs(ground_y - anim_global_pos.y) < airborne_threshold:
			target_pos.y = ground_y
			target_weight = 1.0
			target_tilt = Quaternion(Vector3.UP, ray.get_collision_normal().normalized())

	# Smooth all three with the same factor so they stay in sync
	marker.global_position = marker.global_position.lerp(target_pos, k)
	var tilt: Quaternion = _tilt.get(bone_idx, Quaternion.IDENTITY)
	tilt = tilt.slerp(target_tilt, k)
	_tilt[bone_idx] = tilt

	_apply_tilt(skeleton, bone_idx, anim_pose, tilt)
	return lerpf(current_weight, target_weight, k)

func _apply_tilt(skeleton: Skeleton3D, bone_idx: int, anim_pose: Transform3D, tilt: Quaternion) -> void:
	var B_skel := skeleton.global_basis
	var world_basis := Basis(tilt) * (B_skel * anim_pose.basis)   # tilt on top of the animation
	var model_basis := B_skel.inverse() * world_basis
	skeleton.set_bone_global_pose(bone_idx, Transform3D(model_basis, anim_pose.origin))
