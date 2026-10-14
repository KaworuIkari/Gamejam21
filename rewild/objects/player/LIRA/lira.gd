extends RealController
class_name LIRA_Character
const JetpackHUD = preload("res://ui/in_game/jetpack/jetpack_hud.gd")
var settings_invert_y: bool:
	get:
		return camera_invert_y
	set(value):
		camera_invert_y = value
var anim_dir := Vector2.ZERO   # character rotation for diagonal walks
@export var stopping_tweak : float = 20.0  # tweak how fast velocity decreases after moving, to match the locomotion -> idle Xfade Time visually

# Called when the node enters the scene tree for the first time.
@onready var spring_arm_3d: SpringArm3D = $CameraPivot/SpringArm3D
@onready var robot: MeshInstance3D = $Robot/root/Skeleton3D/Robot
@onready var animation_script: LIRA_AnimBP = $AnimationScript
@onready var anim_player: AnimationPlayer = $Robot/AnimationPlayer

# emoji
@onready var face: RobotFace = $RobotFace
var _idle_time := 0.0

# trajectory and shooting
@onready var aim_trajectory: AimTrajectory = $AimTrajectory
@export var fire_cooldown := 0.35
var has_water_gun := true
var _fire_cd := 0.0

# abilities: unlocked and upgraded by quest rewards (Quests autoload)
@export_group("Abilities")
## Levels LIRA has from the start; quests can only raise them. 0 = locked.
@export_range(0, 9) var start_water_gun_level := 1
@export_range(0, 9) var start_jetpack_level := 1
## Per level (first entry = level 1): splash radius of one shot, in metres.
@export var water_gun_splash := PackedFloat32Array([4.0, 6.0, 8.0])
## Per level: seconds between shots.
@export var water_gun_cooldown := PackedFloat32Array([0.35, 0.25, 0.18])
## Per level: jetpack energy (fuel).
@export var jetpack_energy := PackedFloat32Array([100.0, 160.0, 240.0])
var water_gun_level := 0
var jetpack_level := 0
## Splash radius of the next shot (set from water_gun_splash).
var splash_radius := 4.0

@export var aim_offset : Vector3 = Vector3(1,0,0)
@export var aim_offset_lerp_speed : float = 20.0
@export var aim_camera_distance : float = 2.5
var _target_pivot_offset := Vector3.ZERO


# jetpack
@export_group("Jetpack")
@onready var jetpack: Jetpack = $Robot/root/Skeleton3D/spine_02_x/Jetpack
@export var max_energy := 100.0
@export var burst_cost := 15.0
@export var burst_velocity := 6.0        # upward speed a tap gives you
@export var thrust_accel := 24.0         # m/s² while held; net lift = this - gravity
@export var max_rise_speed := 5.0        # thrust stops adding speed above this
@export var thrust_drain := 35.0         # energy per second while thrusting
@export var hold_threshold := 0.15       # hold longer than this → sustained thrust
@export var spool_time := 0.25           # thrust ramps 0→100% over this (the "heavy" feel)
@export var regen_delay := 1.0
@export var regen_rate := 30.0
@export_group("Air Control")
@export var air_accel := 8.0
@export var air_max_speed := 6.0
@export var thrust_air_accel_mult := 1.5 # steer a bit better while the jets are firing

var energy := max_energy
var _jet_armed := false     # jump was pressed in the air and is still held
var _thrusting := false
var _hold_time := 0.0
var _spool := 0.0
var _regen_timer := 0.0
var _debug_timer := 0.0
var _last_printed_energy := -1.0



func _ready() -> void:
	super()
	character = $Robot
	character.rotation.y = camera_pivot.rotation.y + PI
	# Walk Speed / Sprint Speed come from the Inspector (Speed is unused: LIRA only walks or runs).
	var quests := get_node_or_null(^"/root/Quests")
	if quests:
		quests.ability_changed.connect(func(_a: StringName, _l: int) -> void: _apply_abilities())
	_apply_abilities()

	spring_arm_3d.add_excluded_object(self)

	face.setup(robot, 4)
	var energy_hud := JetpackHUD.new()
	energy_hud.name = "JetpackHUD"
	energy_hud.configure(self)
	get_tree().root.add_child.call_deferred(energy_hud)
	tree_exiting.connect(energy_hud.queue_free)
	

func _physics_process(delta: float) -> void:
	super(delta)
	
	# udpate face
	_idle_time = _idle_time + delta if velocity.length() < 0.1 else 0.0
	face.base = _pick_base_mood()
	face.stress = 0.0             # e.g. 1.0 - health / max_health

	_fire_cd = maxf(0.0, _fire_cd - delta)

	# move camera sideways when aiming
	var yaw_basis := Basis(Vector3.UP, camera_pivot.rotation.y)
	var target := yaw_basis * _target_pivot_offset
	var t := 1.0 - exp(-aim_offset_lerp_speed * delta)
	camera_pivot.position = camera_pivot.position.lerp(target, t)

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

## Water gun and jetpack levels: the higher of the start level and what quests granted.
func _apply_abilities() -> void:
	var quests := get_node_or_null(^"/root/Quests")
	water_gun_level = maxi(start_water_gun_level, quests.ability_level(&"water_gun") if quests else 0)
	jetpack_level = maxi(start_jetpack_level, quests.ability_level(&"jetpack") if quests else 0)
	set_water_gun(water_gun_level > 0)
	if water_gun_level > 0:
		splash_radius = _per_level(water_gun_splash, water_gun_level, splash_radius)
		fire_cooldown = _per_level(water_gun_cooldown, water_gun_level, fire_cooldown)
	jetpack.visible = jetpack_level > 0
	if jetpack_level > 0:
		max_energy = _per_level(jetpack_energy, jetpack_level, max_energy)
		energy = max_energy


func _per_level(values: PackedFloat32Array, level: int, fallback: float) -> float:
	return values[mini(level, values.size()) - 1] if not values.is_empty() else fallback


## Gives (or takes away) the water gun: shows the tank and gun and allows aiming.
func set_water_gun(enabled: bool) -> void:
	has_water_gun = enabled
	$Robot/root/Skeleton3D/spine_02_x/Tank.visible = enabled
	$Robot/root/Skeleton3D/hand_r/WaterGunPos.visible = enabled
	if not enabled and animation_script.is_aiming:
		on_aim(false)

func try_shoot() -> void:                   # call this from the input code that used to set is_shooting
	if not animation_script.is_aiming or _fire_cd > 0.0:
		return
	_fire_cd = fire_cooldown
	aim_trajectory.fire()
	SettingsManager.play_feedback(0.15, 0.25, 0.08)
	animation_script.aim_correction.kick()

func on_aim(is_aiming : bool) -> void:
	if is_aiming:
		_update_camera_distance(aim_camera_distance)
		_target_pivot_offset = aim_offset
	else:
		_update_camera_distance(default_camera_distance)
		_target_pivot_offset = Vector3.ZERO
	animation_script.is_aiming = is_aiming
	aim_trajectory.active = is_aiming

func _unhandled_input(event: InputEvent) -> void:
	if frozen or get_tree().paused:
		return
	var camera_event := event
	if settings_invert_y and event is InputEventMouseMotion:
		camera_event = event.duplicate()
		camera_event.relative.y = -event.relative.y
	super(camera_event)
	if event.is_action_pressed("use"):
		if animation_script.is_aiming and not animation_script.is_shooting:
			animation_script.is_shooting = true
			try_shoot()
	if event.is_action_pressed("use2") and has_water_gun:
		on_aim(true)
	elif event.is_action_released("use2"):
		on_aim(false)

## Preserve horizontal look and invert only the vertical stick axis.


func _handle_gravity_and_jump(delta: float) -> void:
	super(delta)  # gravity + ground jump
	if is_on_floor():
		_end_thrust()
	else:
		_handle_jetpack(delta)
		_handle_air_control(delta)
	_handle_energy_regen(delta)
	_debug_energy(delta)
	_consume_anim_triggers()
	jetpack.set_thrust(_thrusting, _spool)

func _handle_jetpack(delta: float) -> void:
	if frozen or jetpack_level <= 0:
		_end_thrust()
		return
	# Tap: immediate burst (also the first frame of a hold)
	if Input.is_action_just_pressed("jump") and energy >= burst_cost:
		energy -= burst_cost
		velocity.y = maxf(velocity.y, burst_velocity)  # also arrests a fall
		_jet_armed = true
		_hold_time = 0.0
		_spool = 0.0
		_regen_timer = regen_delay
		animation_script.is_using_double_jump = true
		jetpack.burst()
		SettingsManager.play_feedback(0.35, 0.55, 0.16)
	if not _jet_armed:
		return
	if not Input.is_action_pressed("jump") or energy <= 0.0:
		_end_thrust()
		return
	# Hold: sustained thrust after the threshold
	_hold_time += delta
	if _hold_time < hold_threshold:
		return
	_thrusting = true
	_spool = minf(_spool + delta / spool_time, 1.0)
	if velocity.y < max_rise_speed:
		velocity.y = minf(velocity.y + thrust_accel * _spool * delta, max_rise_speed)
	energy = maxf(energy - thrust_drain * delta, 0.0)
	_regen_timer = regen_delay

func _end_thrust() -> void:
	_jet_armed = false
	_thrusting = false
	_spool = 0.0

func _handle_air_control(delta: float) -> void:
	var wish := Vector3(direction.x, 0.0, direction.z)
	if wish.length_squared() < 0.001:
		return  # no input: keep momentum
	var target := wish.normalized() * air_max_speed * input_strength
	var accel := air_accel * (thrust_air_accel_mult if _thrusting else 1.0)
	var h := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, accel * delta)
	velocity.x = h.x
	velocity.z = h.z


func _handle_energy_regen(delta: float) -> void:
	if _thrusting:
		return
	_regen_timer -= delta
	if _regen_timer <= 0.0:
		energy = minf(energy + regen_rate * delta, max_energy)


func _debug_energy(delta: float) -> void:
	_debug_timer -= delta
	if _debug_timer > 0.0 or is_equal_approx(energy, _last_printed_energy):
		return
	_debug_timer = 0.2
	_last_printed_energy = energy
	# print("Jetpack energy: %.1f / %.0f%s" % [energy, max_energy, "  [THRUST]" if _thrusting else ""])

func _consume_anim_triggers() -> void:
	if not animation_script.is_using_double_jump:
		return
	if animation_script.torso_pb.get_current_node() == "JumpStart":
		animation_script.is_using_double_jump = false

###### Mood ######
func _pick_base_mood() -> RobotFace.Mood:
	if animation_script.is_aiming:                 # use whichever script owns this flag
		return RobotFace.Mood.WATCHING
	if _idle_time > 20.0:
		return RobotFace.Mood.CAT
	return RobotFace.Mood.SMILE

# events
func _on_hurt() -> void:
	face.react(RobotFace.Mood.DISGUST, 2, 1.4)           # urgent: skips the hold

func _on_blob_landed(on_target: bool) -> void:
	if on_target:
		face.react(RobotFace.Mood.CORRECT, 1, 1.0)       # watered something that grows
	else:
		face.react(RobotFace.Mood.QUESTION, 1, 1.2)      # wasted shot
