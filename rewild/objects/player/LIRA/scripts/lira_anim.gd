extends Node

@onready var tree: AnimationTree = $"../AnimationTree"
@onready var player: RealController = $".."
@onready var character: Node3D = $"../Robot"
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
@onready var left_foot_ik: SkeletonIK3D = $"../Robot/root/Skeleton3D/LeftFootIK"
@onready var left_foot_target: Marker3D = $LeftFootTarget
@onready var left_foot_ray: RayCast3D = $LeftFootRay

# path references
var top_pb_pos = "parameters/AnimationNodeStateMachine/playback"
var idle_pb_pos = "parameters/AnimationNodeStateMachine/Idle/playback"
var walk_blend_pos = "parameters/AnimationNodeStateMachine/Locomotion/WalkBlend/blend_position"
var run_blend_pos = "parameters/AnimationNodeStateMachine/Locomotion/RunBlend/blend_position"


func _ready():
	tree.advance_expression_base_node = get_path()
	
	top_pb = tree.get(top_pb_pos)
	idle_pb = tree.get(idle_pb_pos)
	
	

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
	
