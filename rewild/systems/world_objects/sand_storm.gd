class_name SandStorm extends Node3D
## Blowing sand around the active camera: thin streaks of sand and big drifting dust sheets
## carried by `wind`. Its strength follows where the camera is: full inside a region whose
## RegionHaze is still there (barren), none once that region is cleaned; outside every region
## it calms as the whole island's progress reaches `clear_at`. Green ground underfoot calms it
## too, and so does a roof overhead (indoors). Changes blend in over a few seconds, so a region being cleaned settles the storm.
## It also turns the environment's fog thick and sandy while it blows (nothing else in the
## level drives the fog; the scene's own values are what it returns to).
## Ambience follows it too: wind howls as loud as the storm blows, and once the air is clear
## (outdoors) a distant bird chirps now and then.

const HAZE_SHADER := preload("res://shaders/common/region_haze.gdshader")
const WIND_LOOP := preload("res://assets/audio/sfx/wind_loop.wav")
const BIRD_CHIRPS: Array[AudioStream] = [
	preload("res://assets/audio/sfx/bird_chirp_1.wav"),
	preload("res://assets/audio/sfx/bird_chirp_2.wav"),
	preload("res://assets/audio/sfx/bird_chirp_3.wav"),
]

## Any camera in the world the storm should follow; the active camera of its viewport is used.
@export var camera: Camera3D
@export var environment: WorldEnvironment
## GrowthRegion -> its RegionHaze (freed once that region is clean).
@export var hazes: Dictionary = {}
@export var wind := Vector3(7, 0, 3)
## Island progress (outside the regions) at which the storm there dies down.
@export_range(0.0, 1.0) var clear_at := 0.6
## How much fully green ground underfoot calms the storm.
@export_range(0.0, 1.0) var green_calm := 0.8
@export var sand_color := Color(0.88, 0.73, 0.52, 0.8)
@export var dust_color := Color(0.86, 0.72, 0.55, 0.45)
## Fog at full storm: colour, extra density and how much of the sky it veils.
@export var fog_color := Color(0.86, 0.71, 0.52)
@export var fog_density := 0.008
@export var fog_sky_affect := 0.35
@export_group("Ambience")
## Wind volume at full storm.
@export var wind_volume_db := -8.0
@export var bird_volume_db := -22.0
## Seconds between bird chirps (random within this range) while the air is clear.
@export var bird_gap := Vector2(8.0, 20.0)

const CHECK_INTERVAL := 0.3
const BLEND_SPEED := 0.3  # strength per second

var strength := 0.0
var _target := 0.0
var _timer := CHECK_INTERVAL
var _settled := false  # the first reading applies at once (no storm rolling in on load)
var _sand: GPUParticles3D
var _dust: GPUParticles3D
var _sand_mat: ShaderMaterial
var _dust_mat: ShaderMaterial
var _fog_base := {}
var _wind: AudioStreamPlayer
var _birds: AudioStreamPlayer
var _bird_timer := 0.0
var _indoors := false


func _ready() -> void:
	add_to_group(&"sand_storm")   # LIRA's face reads strength (lira.gd)
	top_level = true
	if environment and environment.environment:
		var env := environment.environment
		_fog_base = {color = env.fog_light_color, density = env.fog_density, sky = env.fog_sky_affect}
	_sand = _emitter(4500, 2.0, Vector3(24, 8, 24))
	_sand.name = "Sand"
	var m := _sand.process_material as ParticleProcessMaterial
	m.particle_flag_align_y = true
	m.initial_velocity_min = wind.length() * 1.2
	m.initial_velocity_max = wind.length() * 2.2
	m.scale_min = 0.5
	m.scale_max = 1.2
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 3.0
	m.turbulence_noise_scale = 5.0
	m.turbulence_influence_min = 0.05
	m.turbulence_influence_max = 0.2
	_sand_mat = RegionHaze.streak_material(sand_color)
	_sand_mat.set_shader_parameter(&"streak_length", 0.9)
	_sand_mat.set_shader_parameter(&"streak_width", 0.06)
	_sand_mat.set_shader_parameter(&"near_fade", 4.0)
	_sand.material_override = _sand_mat
	_sand.draw_pass_1 = QuadMesh.new()

	_dust = _emitter(160, 7.0, Vector3(50, 6, 50))
	_dust.name = "Dust"
	m = _dust.process_material as ParticleProcessMaterial
	m.initial_velocity_min = wind.length() * 0.8
	m.initial_velocity_max = wind.length() * 1.4
	m.scale_min = 10.0
	m.scale_max = 20.0
	_dust_mat = ShaderMaterial.new()
	_dust_mat.shader = HAZE_SHADER
	var noise := NoiseTexture2D.new()
	noise.seamless = true
	noise.noise = FastNoiseLite.new()
	noise.noise.frequency = 0.03
	_dust_mat.set_shader_parameter(&"noise_tex", noise)
	_dust_mat.set_shader_parameter(&"near_fade", 2.5)
	var quad := QuadMesh.new()
	quad.material = _dust_mat
	_dust.draw_pass_1 = quad

	_wind = AudioStreamPlayer.new()
	_wind.bus = &"SFX"
	_wind.stream = WIND_LOOP
	add_child(_wind)
	_birds = AudioStreamPlayer.new()
	_birds.bus = &"SFX"
	add_child(_birds)
	_bird_timer = randf_range(bird_gap.x, bird_gap.y)
	_apply()


## Particles spawned in a box around the camera, upwind of it, blowing with the wind.
func _emitter(amount: int, lifetime: float, box: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(-box * 3.0, box * 6.0)
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = box
	m.direction = wind.normalized()
	m.spread = 8.0
	m.gravity = Vector3(0, -0.5, 0)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	m.color_ramp = tex
	p.process_material = m
	add_child(p)
	return p


func _process(delta: float) -> void:
	var cam := camera.get_viewport().get_camera_3d() if camera else null
	if cam == null:
		return
	# Spawn upwind so the sand has blown in by the time it reaches the camera.
	global_position = cam.global_position - wind * 1.0
	_timer += delta
	if _timer >= CHECK_INTERVAL:
		_timer = 0.0
		_indoors = _under_roof(cam.global_position)
		_target = 0.0 if _indoors else _barren(cam.global_position)
		if not _settled:
			_settled = true
			strength = _target
			_apply()
	if not is_equal_approx(strength, _target):
		strength = move_toward(strength, _target, BLEND_SPEED * delta)
		_apply()
	_bird_timer -= delta
	if _bird_timer <= 0.0:
		_bird_timer = randf_range(bird_gap.x, bird_gap.y)
		if strength < 0.05 and not _indoors and not _birds.playing:
			_birds.stream = BIRD_CHIRPS.pick_random()
			_birds.pitch_scale = randf_range(0.9, 1.1)
			_birds.volume_db = bird_volume_db + randf_range(-4.0, 0.0)  # some nearer, some further
			_birds.play()


func _under_roof(p: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(p, p + Vector3.UP * 25.0)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## 0..1: how stormy it is at p.
func _barren(p: Vector3) -> float:
	var out := 1.0 - smoothstep(clear_at * 0.6, clear_at, GrowthMap.progress_total)
	# Bigger regions first so smaller ones (which own their overlap) win.
	var regions := hazes.keys().filter(func(r) -> bool: return is_instance_valid(r))
	regions.sort_custom(func(a, b) -> bool: return a.radius > b.radius)
	for region: GrowthRegion in regions:
		var d := Vector2(p.x - region.global_position.x, p.z - region.global_position.z).length()
		var inside := 1.0 - smoothstep(region.radius - 15.0, region.radius + 15.0, d)
		var haze: Variant = hazes[region]  # freed once the region is clean
		var dirty := 1.0 if is_instance_valid(haze) and haze.is_dirty() else 0.0
		out = lerpf(out, dirty, inside)
	return out * (1.0 - GrowthMap.coverage(p, 12.0) * green_calm)


func _apply() -> void:
	_sand.emitting = strength > 0.01
	_dust.emitting = strength > 0.01
	_sand.amount_ratio = strength
	_wind.volume_db = wind_volume_db + linear_to_db(maxf(strength, 0.001))
	if _wind.playing != (strength > 0.01):
		_wind.playing = strength > 0.01
	_dust.amount_ratio = strength
	_sand_mat.set_shader_parameter(&"strength", strength)
	var c := dust_color
	c.a *= strength
	_dust_mat.set_shader_parameter(&"haze_color", c)
	if not _fog_base.is_empty():
		var env := environment.environment
		env.fog_light_color = (_fog_base.color as Color).lerp(fog_color, strength)
		env.fog_density = _fog_base.density + fog_density * strength
		env.fog_sky_affect = lerpf(_fog_base.sky, fog_sky_affect, strength)
