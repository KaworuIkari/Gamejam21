extends Node3D
class_name JetpackFX
## Stylized jetpack flame + smoke. Place at a nozzle (e.g. under a BoneAttachment3D),
## with local -Y pointing out of the nozzle. Drive it with burst() and set_thrust().

@export var flame_shader: Shader
@export var smoke_shader: Shader

@export_group("Flame")
@export var flame_amount := 48
@export var flame_lifetime := 0.22
@export var flame_size := Vector2(0.18, 0.26)      # min/max quad size (m)
@export var flame_speed_idle := 1.5                 # exhaust speed at low intensity → short flame
@export var flame_speed_full := 6.0                 # exhaust speed at full thrust → long flame

@export_group("Smoke")
@export var smoke_amount := 40
@export var smoke_lifetime := 1.1
@export var smoke_size := Vector2(0.25, 0.4)
@export var smoke_rise := 0.6                       # upward drift (m/s²)

@export_group("Response")
@export var burst_duration := 0.25                  # how long a tap keeps the jets lit
@export var response_speed := 18.0                  # how fast intensity follows its target

var _flame: GPUParticles3D
var _smoke: GPUParticles3D
var _flame_pm: ParticleProcessMaterial
var _thrust_target := 0.0
var _burst := 0.0
var _intensity := 0.0

func _ready() -> void:
	var noise_tex := _make_noise()
	_flame = _build_flame(noise_tex)
	_smoke = _build_smoke(noise_tex)
	add_child(_smoke)
	add_child(_flame)


## Tap: short flare.
func burst() -> void:
	_burst = 1.0


## Hold: call every frame with the jetpack's state; spool 0..1 scales flame length.
func set_thrust(active: bool, spool: float = 1.0) -> void:
	_thrust_target = clampf(spool, 0.0, 1.0) if active else 0.0


func _process(delta: float) -> void:
	_burst = maxf(_burst - delta / burst_duration, 0.0)
	var target := maxf(_thrust_target, _burst)
	_intensity = lerpf(_intensity, target, 1.0 - exp(-response_speed * delta))

	var on := _intensity > 0.02
	_flame.emitting = on
	_smoke.emitting = on
	_flame.amount_ratio = clampf(_intensity, 0.1, 1.0)
	_smoke.amount_ratio = clampf(_intensity * 1.2, 0.1, 1.0)

	var v := lerpf(flame_speed_idle, flame_speed_full, _intensity)
	_flame_pm.initial_velocity_min = v * 0.8
	_flame_pm.initial_velocity_max = v


# --- builders ---------------------------------------------------------------

func _build_flame(noise_tex: Texture2D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Flame"
	p.amount = flame_amount
	p.lifetime = flame_lifetime
	p.local_coords = true          # flame stays glued to the nozzle
	p.emitting = false

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.03
	pm.direction = Vector3.DOWN
	pm.spread = 6.0
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = flame_speed_idle * 0.8
	pm.initial_velocity_max = flame_speed_idle
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	pm.scale_min = flame_size.x
	pm.scale_max = flame_size.y
	pm.scale_curve = _curve([Vector2(0.0, 0.7), Vector2(0.15, 1.0), Vector2(1.0, 0.0)])
	p.process_material = pm
	_flame_pm = pm

	p.draw_pass_1 = _quad(flame_shader, noise_tex)
	return p


func _build_smoke(noise_tex: Texture2D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Smoke"
	p.amount = smoke_amount
	p.lifetime = smoke_lifetime
	p.local_coords = false         # smoke trails behind in world space
	p.emitting = false

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.05
	pm.direction = Vector3.DOWN
	pm.spread = 20.0
	pm.gravity = Vector3(0.0, smoke_rise, 0.0)
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.0
	pm.damping_min = 2.0
	pm.damping_max = 3.0
	pm.scale_min = smoke_size.x
	pm.scale_max = smoke_size.y
	pm.scale_curve = _curve([Vector2(0.0, 0.3), Vector2(0.4, 1.0), Vector2(1.0, 0.75)])
	p.process_material = pm

	p.draw_pass_1 = _quad(smoke_shader, noise_tex)
	return p


func _quad(shader: Shader, noise_tex: Texture2D) -> QuadMesh:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("noise_tex", noise_tex)
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = mat
	return q


func _curve(points: Array[Vector2]) -> CurveTexture:
	var c := Curve.new()
	for pt in points:
		c.add_point(pt)
	var ct := CurveTexture.new()
	ct.curve = c
	return ct


func _make_noise() -> NoiseTexture2D:
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.05
	var tex := NoiseTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.seamless = true
	tex.noise = fn
	return tex