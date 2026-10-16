extends RealController
class_name LIRA_Character
const SafeCameraArm = preload("res://objects/player/LIRA/scripts/safe_camera_arm.gd")
const JetpackHUD = preload("res://ui/in_game/jetpack/jetpack_hud.gd")
var settings_invert_y: bool:
	get:
		return camera_invert_y
	set(value):
		camera_invert_y = value
var anim_dir := Vector2.ZERO   # character rotation for diagonal walks
@export var stopping_tweak : float = 20.0  # tweak how fast velocity decreases after moving, to match the locomotion -> idle Xfade Time visually

# Called when the node enters the scene tree for the first time.
@onready var spring_arm_3d: SafeCameraArm = $CameraPivot/SpringArm3D
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

# swimming
@export_group("Water")
@export var chest_ratio := 0.7                          # water this deep (fraction of capsule height) starts swimming
@export var swim_speed := 3.5
@export var swim_accel := 10.0
@export var swim_drag := 6.0
@export var float_stiffness := 8.0                      # pulls chest to the waterline
@export var float_max_speed := 3.0
@export var dive_depth := 1.5                           # chest depth below the waterline that counts as underwater (m)
@export_range(0.0, 1.0) var resurface_fraction := 0.5   # a dive ends when chest depth is below dive_depth * this
@export var dive_vertical_speed := 2.5                  # Space rises, Ctrl sinks
@export var dive_accel := 8.0

var in_water := false
var is_floating := false
var is_diving := false
var is_head_underwater := false

var _water_list: Array[StylizedWater] = []
var _current_water: StylizedWater
var _water_rescan := 0.0
var _water_surface_y := 0.0
var _ctrl_was_down := false
var _dive_reached_depth := false                        # the dive has gone below dive_depth at least once

@onready var _body_shape: CollisionShape3D = $CollisionShape3D
@onready var _foot_ik: Node = $Robot/root/Skeleton3D/FootIKModifier
@onready var _sound_emitter_water: FmodEventEmitter3D = $Robot/root/Skeleton3D/WaterSoundEmitter
@onready var _sound_emitter_swim: FmodEventEmitter3D = $Robot/root/Skeleton3D/SwimSoundEmitter
@onready var _sound_emitter_swim_idle: FmodEventEmitter3D = $Robot/root/Skeleton3D/SwimIdleSoundEmitter
@onready var _sound_emitter_big_splash: FmodEventEmitter3D = $Robot/root/Skeleton3D/BigSplashSoundEmitter


func _ready() -> void:
	super()
	character = $Robot
	character.rotation.y = camera_pivot.rotation.y + PI
	# Walk Speed / Sprint Speed come from the Inspector (Speed is unused: LIRA only walks or runs).
	var quests := get_node_or_null(^"/root/Quests")
	if quests:
		quests.ability_changed.connect(func(_a: StringName, _l: int) -> void: _apply_abilities())
	_apply_abilities()

	spring_arm_3d.add_excluded_object(get_rid())

	face.setup(robot, 4)
	var energy_hud := JetpackHUD.new()
	energy_hud.name = "JetpackHUD"
	energy_hud.configure(self)
	get_tree().root.add_child.call_deferred(energy_hud)
	tree_exiting.connect(energy_hud.queue_free)
	_refresh_water_list()
	_setup_swim_idle_pool()
	

func _physics_process(delta: float) -> void:
	_update_water(delta)
	super(delta)
	_swim_sound(in_water and velocity.length_squared() > 0.25)   # loop plays while moving in water
	
	# udpate face
	_idle_time = _idle_time + delta if velocity.length() < 0.1 else 0.0
	face.base = _pick_base_mood()
	face.stress = 0.0             # e.g. 1.0 - health / max_health

	_fire_cd = maxf(0.0, _fire_cd - delta)

	# move camera sideways when aiming
	var yaw_basis := Basis(Vector3.UP, camera_pivot.rotation.y)
	var target := yaw_basis * _target_pivot_offset
	spring_arm_3d.update_pivot_offset(target, delta, aim_offset_lerp_speed)

func _apply_movement(delta : float) -> void:
	if in_water:
		_water_horizontal(delta)
		return
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
	if in_water:
		_water_rotation(delta)
		return
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
	if is_aiming and in_water:
		return
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
	if in_water:
		_water_vertical(delta)
		_handle_energy_regen(delta)
		_debug_energy(delta)
		_consume_anim_triggers()
		jetpack.set_thrust(_thrusting, _spool)
		return
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
	if frozen or jetpack_level <= 0 or is_diving:   # <- add "or is_diving"
		_end_thrust()
		return
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


# footsteps
@onready var sound_emitter_footstep : FmodEventEmitter3D = $Robot/root/Skeleton3D/FootstepEmitter
var surface_type : int = 0

@onready var terrain: Terrain3D = %Terrain3D
@export var sand_texture_ids: PackedInt32Array = [3]  # Terrain3D texture slot(s) that are sand
@export var grass_threshold := 0.5

@onready var left_foot_ray: RayCast3D = $Robot/root/Skeleton3D/FootIKModifier/LeftFootRay
@onready var right_foot_ray: RayCast3D = $Robot/root/Skeleton3D/FootIKModifier/RightFootRay

const SURFACE_LABELS := ["Gobi", "Grass", "Sand", "Water"]
enum Surface { GOBI, GRASS, SAND, WATER }

func _footstep() -> void:
	surface_type = _detect_surface()
	# print(SURFACE_LABELS[surface_type])
	sound_emitter_footstep.set_parameter("SurfaceType", SURFACE_LABELS[surface_type])
	sound_emitter_footstep.play()

func _detect_surface() -> int:
	# Shallow water: the feet are below the waterline. Deep water is skipped entirely, since footsteps don't play while swimming.
	var vol := _find_water()
	if vol and vol.get_surface_y() > _feet_y():
		return Surface.WATER
	# The planted foot is the lower one, and that is the foot the animation event fires for
	var ray := left_foot_ray
	if right_foot_ray.global_position.y < left_foot_ray.global_position.y:
		ray = right_foot_ray
	if not ray.is_colliding():
		return surface_type  # airborne or swimming: keep the previous surface
	var p := ray.get_collision_point()
	# Painted terrain texture wins (permanent sand, even where GrowthMap is white)
	if terrain:
		var id: Vector3 = terrain.data.get_texture_id(p)  # x = base, y = overlay, z = blend
		if not is_nan(id.z):
			var dominant := int(id.y) if id.z > 0.5 else int(id.x)
			if dominant in sand_texture_ids:
				return Surface.SAND
	# Grass where the growth map is green
	if GrowthMap.sample(p) > grass_threshold:
		return Surface.GRASS
	# Default
	return Surface.GOBI

# ---------- water ----------
func _refresh_water_list() -> void:
	_water_list.clear()
	for n in get_tree().get_nodes_in_group(&"water_surfaces"):
		if n is StylizedWater:
			_water_list.append(n)

func _update_water(delta: float) -> void:
	_handle_touchdown()   # before _track_air_height, which overwrites the peak
	_track_air_height()
	_water_rescan -= delta
	if _water_rescan <= 0.0:
		_water_rescan = 0.5
		_refresh_water_list()

	var vol := _find_water()
	var h := _capsule_height()
	var feet := _feet_y()
	var ratio := chest_ratio if not in_water else chest_ratio - 0.15   # hysteresis
	var deep := vol != null and (vol.get_surface_y() - feet) >= ratio * h

	if deep and not in_water:
		_enter_water()
	elif not deep and in_water:
		_exit_water()
	if not in_water:
		return

	_water_surface_y = vol.get_surface_y()
	is_head_underwater = feet + h < _water_surface_y
	_check_dive_input()
	if is_diving:
		var depth := _water_surface_y - _chest_y()  # chest depth
		if depth >= dive_depth:
			_dive_reached_depth = true
		if _dive_reached_depth and depth <= dive_depth * resurface_fraction:
			_end_dive()

func _find_water() -> StylizedWater:
	if is_instance_valid(_current_water) and _current_water.holds_point(global_position):
		return _current_water
	_current_water = null
	for v in _water_list:
		if is_instance_valid(v) and v.holds_point(global_position):
			_current_water = v
			break
	return _current_water

func _capsule_height() -> float:
	var s := _body_shape.shape
	var h = s.get("height") if s else null
	return float(h) if h != null else 2.0

func _feet_y() -> float:
	return _body_shape.global_position.y - _capsule_height() * 0.5

func _chest_y() -> float:
	return _feet_y() + chest_ratio * _capsule_height()

func _check_dive_input() -> void:
	var ctrl := Input.is_key_pressed(KEY_CTRL)
	if ctrl and not _ctrl_was_down and is_floating:
		_start_dive()
	_ctrl_was_down = ctrl

func _start_dive() -> void:
	is_floating = false
	is_diving = true
	_dive_reached_depth = false
	_play_sound_water(true)
	_sound_emitter_water.play()

func _end_dive() -> void:
	is_diving = false
	is_floating = true
	_play_sound_water(false)
	_sound_emitter_water.play()

func _enter_water() -> void:
	in_water = true
	is_floating = true
	is_diving = false
	_dive_reached_depth = false
	_end_thrust()
	on_aim(false)
	_set_foot_ik(false)
	_sound_emitter_water.play()

func _exit_water() -> void:
	in_water = false
	is_floating = false
	is_diving = false
	is_head_underwater = false
	_dive_reached_depth = false
	_set_foot_ik(true)
	_swim_sound(false)
	surface_type = Surface.GOBI

func _play_sound_water(emerge : bool = false) -> void:  # false 0, true 1
	_sound_emitter_water.set_parameter("Emerge", emerge)
	_sound_emitter_water.play()

func _set_foot_ik(on: bool) -> void:
	if _foot_ik:
		_foot_ik.set("active", on)   # SkeletonModifier3D property; adjust if your modifier differs

func _water_horizontal(delta: float) -> void:
	var wish := Vector3(direction.x, 0.0, direction.z)
	var target := Vector3.ZERO
	if wish.length_squared() > 0.001:
		target = wish.normalized() * swim_speed * input_strength
	var rate := swim_accel if target.length_squared() > 0.0001 else swim_drag
	var h := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, rate * delta)
	velocity.x = h.x
	velocity.z = h.z
	is_sprinting = false
	is_walking = false

func _water_vertical(delta: float) -> void:
	if is_diving:
		var v := 0.0
		if Input.is_action_pressed("jump"):
			v += 1.0
		if Input.is_key_pressed(KEY_CTRL):
			v -= 1.0
		velocity.y = move_toward(velocity.y, v * dive_vertical_speed, dive_accel * delta)
		return
	# Floating: jetpack can lift us out. Otherwise a spring holds the chest at the waterline.
	_handle_jetpack(delta)
	if not _thrusting and not _jet_armed:
		var err := _water_surface_y - _chest_y()
		velocity.y = clampf(err * float_stiffness, -float_max_speed, float_max_speed)

func _water_rotation(delta: float) -> void:
	var dir := Vector3(direction.x, 0.0, direction.z)
	if dir.length_squared() < 0.001:
		return   # no input: keep last facing, so vertical-only dives don't spin the mesh
	character.rotation.y = lerp_angle(character.rotation.y, atan2(dir.x, dir.z), rotation_speed * delta)

# swim sound loops
var _swim_loop_on := false
func _swim_sound(active: bool) -> void:
	if active == _swim_loop_on:
		return   # only act on change, since calling start() on a playing loop may restart it
	_swim_loop_on = active
	if active:
		_sound_emitter_swim.play()
	else:
		_sound_emitter_swim.stop()

# several (two for now) emitters pooled for idle swim sound!
const SWIM_VOICES := 2
var _swim_idle_pool: Array[FmodEventEmitter3D] = []
var _swim_idle_pool_next := 0
func _setup_swim_idle_pool() -> void:
	_swim_idle_pool.append(_sound_emitter_swim_idle)
	var parent := _sound_emitter_swim_idle.get_parent()
	for i in SWIM_VOICES - 1:
		var e := _sound_emitter_swim_idle.duplicate() as FmodEventEmitter3D
		parent.add_child(e)
		e.transform = _sound_emitter_swim_idle.transform
		_swim_idle_pool.append(e)
func _swim_sound_idle() -> void:
	var e := _swim_idle_pool[_swim_idle_pool_next]
	_swim_idle_pool_next = (_swim_idle_pool_next + 1) % _swim_idle_pool.size()
	e.play()

# water splash when drop from above, and falling sound (footstep) without water
@export var big_splash_drop := 1.5     # fall distance (m) before entering water that counts as a big splash
@export var big_splash_speed := 2.0    # impact speed (m/s) that counts as a big splash
var _air_peak_y := -INF                # highest feet height since last landing or entering water
func _play_sound_water_big_splash() -> void:
	_sound_emitter_big_splash.play()

# Records the highest feet height since the last landing. Resets on land or in water.
func _track_air_height() -> void:
	if in_water or is_on_floor():
		_air_peak_y = _feet_y()
	else:
		_air_peak_y = maxf(_air_peak_y, _feet_y())

# Runs once per landing. Water takes priority over ground.
func _handle_touchdown() -> void:
	var feet := _feet_y()
	if _air_peak_y <= feet:
		return   # not falling: walking, idle, or still rising
	var drop := _air_peak_y - feet
	var vol := _find_water()
	if vol != null and vol.get_surface_y() > feet:
		if drop >= big_splash_drop:
			_play_sound_water_big_splash()
	elif is_on_floor():
		if drop >= big_splash_drop:
			_footstep()
		else:
			return   # ground bump: keep tracking
	else:
		return   # still airborne
	_air_peak_y = feet   # consume the fall