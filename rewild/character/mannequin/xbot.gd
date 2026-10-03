extends CharacterBody3D
const SPEED = 30.0
const ROT_SPEED = 8.0 # tune turn smoothness
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var target_armature: Node3D = $TargetArmature

func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta
	var input_dir := Input.get_vector("right", "left", "down", "up")
	var input_flat = Vector3(input_dir.x, 0, input_dir.y)
	var iso_rot = Basis.from_euler(Vector3(0, deg_to_rad(45.0), 0))
	var direction := (iso_rot * input_flat).normalized()

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		animation_player.play("Walk")
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		animation_player.play("Idle")

	# Smoothly rotate TargetArmature toward movement direction (FIX: no 180° wrap bug)
	if direction != Vector3.ZERO:
		var target_basis = Basis.looking_at(-direction, Vector3.UP)
		var target_yaw = target_basis.get_euler().y
		var current_yaw = target_armature.rotation.y
		var angle_diff = angle_difference(current_yaw, target_yaw)
		target_armature.rotation.y += angle_diff * ROT_SPEED * delta

	move_and_slide()
