extends RealController
var anim_dir := Vector2.ZERO   # character rotation for diagonal walks
@export var stopping_tweak : float = 20.0  # tweak how fast velocity decreases after moving, to match the locomotion -> idle Xfade Time visually
# Called when the node enters the scene tree for the first time.
@onready var spring_arm_3d: SpringArm3D = $CameraPivot/SpringArm3D


func _ready() -> void:
	super()
	character = $Robot
	character.rotation.y = camera_pivot.rotation.y + PI
	
	speed = 2.5 * scale.x          # unused slot, keep it consistent
	walk_speed = speed             # my "walk"
	sprint_speed = 8.0 * scale.x   # my "run"
	pass # Replace with function body.
	
	spring_arm_3d.add_excluded_object(self)


func _physics_process(delta: float) -> void:
	super(delta)

func _apply_movement(delta : float) -> void:
	var is_moving = input_dir != Vector2.ZERO and is_on_floor()
	if not is_on_floor():
		return  # no air control: keep the velocity from take-off
	is_sprinting = Input.is_action_pressed("sprint") and is_moving
	#is_walking = is_moving and not Input.is_action_pressed("sprint") and can_walk
	is_walking = is_moving and not is_sprinting
	
	var current_speed := walk_speed
	if is_sprinting:
		current_speed = sprint_speed
		
	if direction:
		velocity.x = direction.x * current_speed * input_strength
		velocity.z = direction.z * current_speed * input_strength
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed * delta * stopping_tweak)
		velocity.z = move_toward(velocity.z, 0, current_speed * delta * stopping_tweak)
		
func _handle_character_rotation(delta: float) -> void:
	if input_dir == Vector2.ZERO:
		anim_dir = Vector2.ZERO
		return                                   # idle: keep last facing
		
	if not is_on_floor(): return

	var s := roundi(atan2(input_dir.x, -input_dir.y) / (PI / 4.0))   # -4..4
	var side := signi(s)
	var off := 0                                  # in 45° steps, positive = toward the right
	match absi(s):
		0: anim_dir = Vector2(0, 1)
		1: off = s;              anim_dir = Vector2(0, 1)
		2: anim_dir = Vector2(side, 0)
		3: off = s - 4 * side;   anim_dir = Vector2(0, -1)
		4: anim_dir = Vector2(0, -1)

	# camera yaw + PI = camera-forward; turning toward the right is a negative yaw
	var target := camera_pivot.rotation.y + PI - off * PI / 4.0
	character.rotation.y = lerp_angle(character.rotation.y, target, rotation_speed * delta)
