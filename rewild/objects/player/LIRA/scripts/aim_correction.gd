class_name AimCorrection extends SkeletonModifier3D

@export var hand := &"hand.r"
@export var chain: Array[StringName] = [&"spine_02.x", &"arm_stretch.r"]   # root to tip
@export var chain_weights_right: Array[float] = [0.4, 0.6]   # aim correction swings right
@export var chain_weights_left: Array[float] = [0.6, 0.4]    # aim correction swings left
@export var side_blend_angle := deg_to_rad(10.0)             # blend zone around straight ahead
@export var max_angle := deg_to_rad(120.0)

@export_group("Recoil")
@export var recoil_pitch := deg_to_rad(12.0)         # peak barrel rise, split across recoil_bones
@export var recoil_bones: Array[StringName] = [&"arm_stretch.r", &"forearm_stretch.r"]
@export var recoil_bone_weights: Array[float] = [0.4, 0.6]
@export var recoil_spine := &"spine_02.x"
@export var recoil_spine_yaw := deg_to_rad(5.0)      # peak twist, positive = clockwise seen from above
@export var recoil_omega := 28.0                     # spring speed; higher = snappier
@export var recoil_damping := 0.35                   # below 1 = overshoot and settle

@export_group("Debug")
@export var debug_draw := true
@export var debug_length := 2.0

@onready var water_gun_pos: Node3D = $"../hand_r/WaterGunPos"
@onready var muzzle_local := water_gun_pos.transform
@export var barrel_axis := Vector3.UP                # barrel direction in muzzle space

var desired_dir_world := Vector3.FORWARD
var weight := 0.0
var aim_dir_world := Vector3.FORWARD                 # corrected barrel direction, recoil excluded

var _x := 0.0                                        # recoil position, about 1.0 at the peak of a kick
var _v := 0.0

func kick(strength := 1.0) -> void:
	_v += strength * recoil_omega * 1.6              # chosen so the peak of one kick is about strength

func is_recoiling() -> bool:
	return absf(_x) > 0.02 or absf(_v) > 0.3

func _process(delta: float) -> void:
	delta = minf(delta, 1.0 / 30.0)
	var accel := -recoil_omega * recoil_omega * _x - 2.0 * recoil_damping * recoil_omega * _v
	_v += accel * delta
	_x = clampf(_x + _v * delta, -0.5, 1.6)
	if absf(_x) < 0.001 and absf(_v) < 0.01:
		_x = 0.0
		_v = 0.0
	if debug_draw:
		_debug()

# -1 = correction swings right, +1 = left, blended within side_blend_angle of zero yaw.
func _side_factor(a: Vector3, b: Vector3, up: Vector3) -> float:
	var ah := (a - up * a.dot(up))
	var bh := (b - up * b.dot(up))
	if ah.length() < 1e-4 or bh.length() < 1e-4:
		return 0.0
	var yaw := atan2(up.dot(ah.cross(bh)), ah.dot(bh))     # + about up = counter-clockwise = left
	return clampf(yaw / maxf(side_blend_angle, 1e-4), -1.0, 1.0)


func _chain_weight(i: int, side: float) -> float:
	var r := chain_weights_right[i] if i < chain_weights_right.size() else 0.0
	var l := chain_weights_left[i] if i < chain_weights_left.size() else 0.0
	return lerpf(r, l, (side + 1.0) * 0.5)

func _process_modification() -> void:
	var skel := get_skeleton()
	var hand_i := skel.find_bone(hand)
	if hand_i < 0:
		return
	var a := ((skel.get_bone_global_pose(hand_i) * muzzle_local).basis * barrel_axis).normalized()
	aim_dir_world = (skel.global_basis * a).normalized()
	if weight <= 0.001:
		return

	# 1. aim correction, shared along the chain
	var q_total := Quaternion.IDENTITY
	var b := (skel.global_basis.inverse() * desired_dir_world).normalized()
	var angle := a.angle_to(b)
	if angle > 0.0001:
		var up := (skel.global_basis.inverse() * Vector3.UP).normalized()
		var side := _side_factor(a, b, up)
		var q := Quaternion.IDENTITY.slerp(Quaternion(a, b), weight * minf(1.0, max_angle / angle))
		for i in chain.size():
			var bi := skel.find_bone(chain[i])
			if bi < 0:
				continue
			var qi := Quaternion.IDENTITY.slerp(q, _chain_weight(i, side))
			_rotate_bone(skel, bi, qi)
			q_total = qi * q_total
	var d := q_total * a                      # barrel direction after correction, skeleton space
	aim_dir_world = (skel.global_basis * d).normalized()

	# 2. recoil on top, after the aim direction has been published
	var k := _x * weight
	if absf(k) > 0.0001:
		_apply_recoil(skel, d, k)

func _apply_recoil(skel: Skeleton3D, d: Vector3, k: float) -> void:
	var up := (skel.global_basis.inverse() * Vector3.UP).normalized()
	var si := skel.find_bone(recoil_spine)
	if si >= 0:
		var q_spine := Quaternion(up, -recoil_spine_yaw * k)   # negative about +Y = clockwise from above
		_rotate_bone(skel, si, q_spine)
		d = q_spine * d
	var axis := d.cross(up)                    # rotating d about this axis lifts it toward up
	if axis.length() < 0.001:
		return
	var q_pitch := Quaternion(axis.normalized(), recoil_pitch * k)
	for i in recoil_bones.size():
		var bi := skel.find_bone(recoil_bones[i])
		if bi >= 0:
			_rotate_bone(skel, bi, Quaternion.IDENTITY.slerp(q_pitch, recoil_bone_weights[i]))

# Rotate a bone by q (skeleton space) about its own origin.
func _rotate_bone(skel: Skeleton3D, bone: int, q: Quaternion) -> void:
	var g := skel.get_bone_global_pose(bone)
	var new_g := Transform3D(Basis(q) * g.basis, g.origin)
	var p := skel.get_bone_parent(bone)
	var parent_g := skel.get_bone_global_pose(p) if p >= 0 else Transform3D.IDENTITY
	var pose := skel.get_bone_rest(bone).affine_inverse() * parent_g.affine_inverse() * new_g
	skel.set_bone_pose_rotation(bone, pose.basis.get_rotation_quaternion())

func _debug() -> void:
	var skel := get_skeleton()
	var hand_i := skel.find_bone(hand)
	if hand_i < 0:
		return
	var origin := (skel.global_transform * skel.get_bone_global_pose(hand_i) * muzzle_local).origin
	DebugNode.draw_vector(get_tree(), origin, desired_dir_world.normalized(), Color.GREEN, debug_length)
	DebugNode.draw_vector(get_tree(), origin, aim_dir_world, Color.RED, debug_length)
