extends Node
class_name LIRA_AnimBP

@onready var tree: AnimationTree = $"../AnimationTree"
@onready var player: LIRA_Character = $".."
@onready var character: Node3D = $"../Robot"
@onready var collision_shape_3d: CollisionShape3D = $"../CollisionShape3D"
@onready var skeleton: Skeleton3D = $"../Robot/root/Skeleton3D"

# path references
const torso_pb_pos = "parameters/Torso/playback"
const idle_pb_pos = "parameters/Torso/Idle/playback"
const idle_stand_pb_pos = "parameters/Torso/Idle/Stand/playback"
const turn_pb_pos = "parameters/Torso/Idle/Turn/playback"
const walk_blend_pos = "parameters/Torso/Locomotion/WalkBlend/blend_position"
const run_blend_pos = "parameters/Torso/Locomotion/RunBlend/blend_position"
const aim_blend_pos = "parameters/Aim/blend_amount"
const ear_pb_pos = "parameters/Ear/playback"

var torso_pb: AnimationNodeStateMachinePlayback
var idle_pb: AnimationNodeStateMachinePlayback
var idle_stand_pb: AnimationNodeStateMachinePlayback
var idle_turn_pb: AnimationNodeStateMachinePlayback
var ear_pb: AnimationNodeStateMachinePlayback

# Advanced Expression
var is_moving : bool = false
var is_walking : bool = false
var is_running : bool = false
var is_jumping : bool = false
var is_using_double_jump : bool = false
var is_falling : bool = false
var is_swimming : bool = false

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

# shooting
var is_shooting : bool = false
var is_aiming : bool = false
var aim_blend_tweak : float = 15
@onready var aim_correction: AimCorrection = $"../Robot/root/Skeleton3D/AimCorrection"
@onready var aim_trajectory: AimTrajectory = $"../AimTrajectory"

# swimming
const swim_blend_pos = "parameters/Swim/blend_amount"   # the Blend2 that takes Swimming as its blend input
var swim_moving := false     # hysteresis-filtered; read by transition expressions
@export var swim_blend_tweak := 8.0
@export var swim_start_speed := 0.5   # speed needed to switch from swim_idle to swim
@export var swim_stop_speed := 0.2    # speed below which swim returns to swim_idle

# ear
@export var ear_twitch_chance := 0.3
var twitch_ear := false
var _ear_elapsed := 0.0

func _ready():
	tree.advance_expression_base_node = get_path()
	torso_pb = tree.get(torso_pb_pos)
	idle_pb = tree.get(idle_pb_pos)
	idle_stand_pb = tree.get(idle_stand_pb_pos)
	idle_turn_pb = tree.get(turn_pb_pos)
	ear_pb = tree.get(ear_pb_pos)

func _process(delta: float) -> void:
	if player == null or tree == null:
		return
	_update_ear(delta)
	is_swimming = player.in_water
	_update_swim_blend(delta)
	if player.in_water:
		update_aim_anim(delta)
		_update_swim_states()
		return
	is_walking = player.is_walking
	is_running = player.is_sprinting
	is_moving = is_walking or is_running
	is_jumping = player.is_jumping
	is_falling = not player.is_on_floor() and player.velocity.y <= 0
	
	debounce(delta)
	random_idle(delta)
	update_aim_anim(delta)
	
	if player.input_dir != Vector2.ZERO:
		var anim_dir := get_anim_direction(player.input_dir)
		set_blend_vec(delta, get_anim_direction(player.input_dir) * _speed_fraction())
	rotate_toward_camera(delta, player.input_dir)

## How much of the commanded speed we're actually achieving. 0 against a wall.
func _speed_fraction() -> float:
	var v := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var ref: float = player.sprint_speed if is_running else player.walk_speed
	return clampf(v.length() / maxf(ref, 0.01), 0.0, 1.0)
	
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
	var is_idle_default := torso_pb.get_current_node() == &"Idle" \
		and idle_stand_pb.get_current_node() == &"Idle_default"
	if not is_idle_default:
		idle_default_active = false
		return
	if not idle_default_active:
		# just entered: start counting from zero
		idle_default_active = true
		idle_default_elapsed = 0.0
		return
	idle_default_elapsed += delta
	var idle_default_length := idle_stand_pb.get_current_length()
	if idle_default_length > 0.0 and idle_default_elapsed >= idle_default_length:
		idle_default_elapsed -= idle_default_length   # one loop completed
		if randf() < idle_variant_chance:
			idle_stand_pb.travel(idle_variants.pick_random())
	
# Snap input to 45° sectors, return which of the 4 animations to blend.
func get_anim_direction(input_dir: Vector2) -> Vector2:
	var s := roundi(atan2(input_dir.x, -input_dir.y) / (PI / 4.0))   # -4..4
	var side := signi(s)
	match absi(s):
		0, 1: return Vector2(0, 1)        # forward and forward-diagonals
		2:    return Vector2(side, 0)     # strafe
		_:    return Vector2(0, -1)       # back-diagonals and backward (3, 4)

############# player rotation ##############
func rotate_toward_camera(delta: float, input_dir: Vector2) -> void:
	var moving := input_dir != Vector2.ZERO
	var cam_yaw := player.camera_pivot.rotation.y + PI
	var off := 0
	if moving:
		_cancel_turn()
	_update_turn(delta)               # always, so an active turn finishes even if aiming is released
	if is_aiming:
		# proceudural aiming for arm
		aim_correction.desired_dir_world = aim_trajectory.arm_direction()
		if not moving:
			var err := absf(angle_difference(character.rotation.y, cam_yaw))
			if not _is_turning() and err > turn_start:
				_begin_turn(cam_yaw)
			return
	else:
		if not moving:
			return
		var s := roundi(atan2(input_dir.x, -input_dir.y) / (PI / 4.0))
		var side := signi(s)
		match absi(s):
			1: off = s
			3: off = s - 4 * side
	var target := cam_yaw - off * PI / 4.0
	character.rotation.y = lerp_angle(character.rotation.y, target, player.rotation_speed * delta)

func update_aim_anim(delta : float) -> void:
	var target_blend : float = 1 if is_aiming else 0
	var current_aim : float = tree.get(aim_blend_pos)
	var smooth_aim = lerp(current_aim, target_blend, delta * aim_blend_tweak)
	tree.set(aim_blend_pos, smooth_aim)
	aim_correction.weight = smooth_aim
	aim_trajectory.active = is_aiming and not aim_correction.is_recoiling()
	is_shooting = aim_correction.is_recoiling()


########### Turn in place ##############
@export var turn_start := deg_to_rad(35.0)
@export var turn_rate := 0.8                       # global play-rate tweak for every turn clip
@export var turn_scale_range := Vector2(0.6, 2.5)  # keeps tiny turns from becoming a blur
@export var turn_exit_blend := 0.1                 # match the Turn -> Stand xfade
@export var turn_cooldown := 0.2
# real angle each clip rotates; use the totals your Blender script printed
const TURN_ANGLES := { &"TurnL90": 90.0, &"TurnR90": 90.0, &"TurnR180": 180.0 }

enum TurnPhase { NONE, ENTERING, PLAYING }
var _turn_phase := TurnPhase.NONE
var _turn_clip: StringName
var _turn_scale := 1.0
var _turn_t := 0.0
var _turn_dur := 0.0
var _turn_guard := 0.0
var _turn_cd := 0.0
var _turn_from := 0.0
var _turn_delta := 0.0

func _turn_scale_path(clip: StringName) -> String:
	return "parameters/Torso/Idle/Turn/%s/TimeScale/scale" % clip

func _is_turning() -> bool:
	return _turn_phase != TurnPhase.NONE \
		or (torso_pb.get_current_node() == &"Idle" and idle_pb.get_current_node() == &"Turn")

func _begin_turn(cam_yaw: float) -> void:
	if _turn_cd > 0.0:
		return
	if torso_pb.get_current_node() != &"Idle" or idle_pb.get_current_node() != &"Stand":
		return
	var d := angle_difference(character.rotation.y, cam_yaw)   # + means the camera is to the left
	if absf(d) > deg_to_rad(135.0):
		_turn_clip = &"TurnR180"
		_turn_delta = d if d < 0.0 else d - TAU                # the clip turns right, so a left-side error goes the long way
	else:
		_turn_clip = &"TurnL90" if d > 0.0 else &"TurnR90"
		_turn_delta = d
	var ratio := absf(_turn_delta) / deg_to_rad(TURN_ANGLES[_turn_clip])
	_turn_scale = clampf(turn_rate / maxf(ratio, 0.01), turn_scale_range.x, turn_scale_range.y)
	tree.set(_turn_scale_path(_turn_clip), _turn_scale)
	_turn_from = character.rotation.y
	_turn_t = 0.0
	_turn_dur = 0.0
	_turn_guard = 0.5
	_turn_phase = TurnPhase.ENTERING
	idle_pb.travel(&"Turn")

func _cancel_turn() -> void:
	_turn_phase = TurnPhase.NONE      # whatever left Idle (e.g. Idle -> Locomotion) owns the exit

func _finish_turn() -> void:
	_turn_phase = TurnPhase.NONE
	_turn_cd = turn_cooldown
	idle_pb.travel(&"Stand")

# Re-aim at the live camera so a moving mouse can't leave a leftover error.
func _live_delta() -> float:
	var cam_yaw := player.camera_pivot.rotation.y + PI
	var d := angle_difference(_turn_from, cam_yaw)
	var dir := signf(_turn_delta)
	if signf(d) != dir:
		d += dir * TAU                # keep the clip's turning direction
	if absf(d) > deg_to_rad(250.0):   # the camera swung back past the start: no turn left
		d = 0.0
	return d

func _update_turn(delta: float) -> void:
	_turn_cd = maxf(0.0, _turn_cd - delta)
	if _turn_phase == TurnPhase.NONE:
		return
	if torso_pb.get_current_node() != &"Idle":
		_cancel_turn()
		return

	_turn_guard -= delta
	if _turn_guard <= 0.0:
		_finish_turn()
		return

	if _turn_phase == TurnPhase.ENTERING:
		if idle_pb.get_current_node() == &"Turn":
			idle_turn_pb.start(_turn_clip, true)
			_turn_phase = TurnPhase.PLAYING
		return

	if idle_turn_pb.get_current_node() != _turn_clip:
		return
	if _turn_dur <= 0.0:
		var l := idle_turn_pb.get_current_length()
		if l <= 0.01:
			return
		_turn_dur = maxf(l / _turn_scale - turn_exit_blend, 0.05)
		_turn_guard = _turn_dur + 0.6
		# print("turn ", _turn_clip, " len ", l, " scale ", _turn_scale, " dur ", _turn_dur)

	_turn_t += delta
	_turn_delta = _live_delta()
	var k := smoothstep(0.0, 1.0, clampf(_turn_t / _turn_dur, 0.0, 1.0))
	character.rotation.y = _turn_from + _turn_delta * k
	if _turn_t >= _turn_dur:
		_finish_turn()

func _update_swim_blend(delta: float) -> void:
	var target := 1.0 if player.in_water else 0.0
	var cur: float = tree.get(swim_blend_pos)
	tree.set(swim_blend_pos, lerpf(cur, target, delta * swim_blend_tweak))

func _update_swim_states() -> void:
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	if swim_moving:
		if speed < swim_stop_speed:
			swim_moving = false
	elif speed > swim_start_speed:
		swim_moving = true

func _update_ear(delta: float) -> void:
	if ear_pb.get_current_node() != &"ear_idle":
		twitch_ear = false          # consumed: we're in ear_twitch now
		_ear_elapsed = 0.0
		return
	_ear_elapsed += delta
	var l := ear_pb.get_current_length()
	if l > 0.0 and _ear_elapsed >= l:
		_ear_elapsed -= l           # one loop completed
		twitch_ear = randf() < ear_twitch_chance