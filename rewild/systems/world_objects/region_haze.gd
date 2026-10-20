class_name RegionHaze extends Node3D
## Dusty haze hanging over a GrowthRegion while it is still barren: big soft puffs plus
## streaks of sand blowing with `wind`, spread over the terrain inside the region (the part a smaller region
## claims belongs to that one's haze). Once the region is cleaned a wave sweeps out from
## `clear_from`, dissolving the dust with a burst of rising sparkles, and the haze is freed.
## Cleaned = `clear_when` is on (e.g. the pump for the lake), else the region's restoration
## progress reaches `clear_at`. A region already clean when the level loads starts clear.

const HAZE_SHADER := preload("res://shaders/common/region_haze.gdshader")
const STREAK_SHADER := preload("res://shaders/common/sand_streak.gdshader")

@export var region: GrowthRegion
@export var terrain: Terrain3D
## When set, the region is cleaned as soon as this turns on (progress is ignored).
@export var clear_when: WaterFlowSwitch
## Region progress (0..1) at which the haze clears.
@export_range(0.0, 1.0) var clear_at := 0.6
## Where the clearing wave starts; empty = the region centre.
@export var clear_from: Node3D
## Puffs never sit below this height (e.g. the sea surface).
@export var floor_y := -INF
@export var haze_color := Color(0.86, 0.72, 0.55, 0.5)
@export var mote_color := Color(0.78, 0.62, 0.42, 0.8)
## Where the sand blows, in m/s (share it with the SandStorm).
@export var wind := Vector3(7, 0, 3)
@export var sparkle_color := Color(1.0, 0.95, 0.75)
@export var clear_time := 6.0

var _haze: GPUParticles3D
var _motes: GPUParticles3D
var _haze_mat: ShaderMaterial
var _points: ImageTexture
var _point_count := 0
var _clearing := false
var _measured := false


func _ready() -> void:
	if region == null or _is_clean():
		queue_free()
		return
	global_position = region.global_position
	_build_points.call_deferred()  # after Terrain3D has loaded its data
	if clear_when:
		clear_when.started.connect(clear)
	else:
		GrowthMap.progress_changed.connect(_on_progress_changed)


func _is_clean() -> bool:
	if clear_when:
		return clear_when.is_on
	return GrowthMap.region_progress(region.region_id) >= clear_at


## Still barren (not cleaned and not clearing): SandStorm blows at full strength here.
func is_dirty() -> bool:
	return not _clearing


func _on_progress_changed() -> void:
	var first := not _measured
	_measured = true
	if GrowthMap.region_progress(region.region_id) >= clear_at:
		if first:
			queue_free()  # a saved game where this region was already cleaned
		else:
			clear()


## Sweeps the haze away (call it yourself to force it).
func clear() -> void:
	if _clearing or _haze == null:
		return
	_clearing = true
	var origin := clear_from.global_position if clear_from else global_position
	_haze_mat.set_shader_parameter(&"clear_center", origin)
	var reach := region.radius + origin.distance_to(global_position) + 30.0
	_motes.emitting = false
	_haze.emitting = false
	(_haze.process_material as ParticleProcessMaterial).gravity = Vector3(0, 0.6, 0)  # the dust lifts
	_add_sparkles()
	var tween := create_tween().set_parallel()
	tween.tween_method(func(r: float) -> void: _haze_mat.set_shader_parameter(&"clear_radius", r),
			0.0, reach, clear_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	var mote_mat := _motes.material_override as ShaderMaterial
	tween.tween_method(func(v: float) -> void: mote_mat.set_shader_parameter(&"strength", v),
			1.0, 0.0, clear_time * 0.6)
	tween.chain().tween_interval(4.0)  # let the last sparkles rise
	tween.chain().tween_callback(queue_free)


# --- Building -----------------------------------------------------------------

## Random spots over the region's ground, 2..9 m up, as an emission-points texture.
func _build_points() -> void:
	if _is_clean():
		queue_free()
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(region.region_id)
	var smaller: Array[GrowthRegion] = []
	for other in region.get_parent().get_children():
		if other is GrowthRegion and other != region and other.radius < region.radius:
			smaller.append(other)
	var img := Image.create(512, 1, false, Image.FORMAT_RGBF)
	var n := 0
	for attempt in 2048:
		if n == img.get_width():
			break
		var a := rng.randf() * TAU
		var r := region.radius * sqrt(rng.randf())
		var p := global_position + Vector3(cos(a) * r, 0, sin(a) * r)
		if smaller.any(func(o: GrowthRegion) -> bool: return _flat(o.global_position, p) < o.radius):
			continue
		var h: float = terrain.data.get_height(p) if terrain and terrain.data else NAN
		if is_nan(h):
			h = global_position.y
		p.y = maxf(h, floor_y) + rng.randf_range(2.0, 9.0)
		img.set_pixel(n, 0, Color(p.x, p.y, p.z))
		n += 1
	if n == 0:
		queue_free()
		return
	_point_count = n
	_points = ImageTexture.create_from_image(img)
	_add_haze()
	_add_motes()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Particles from the region's points, moving with the wind times `velocity`.
func _process_material(velocity: float, scale_min: float, scale_max: float) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	m.emission_point_texture = _points
	m.emission_point_count = _point_count
	m.direction = wind.normalized() if wind != Vector3.ZERO else Vector3.RIGHT
	m.spread = 15.0
	m.initial_velocity_min = wind.length() * velocity * 0.6
	m.initial_velocity_max = wind.length() * velocity
	m.gravity = Vector3.ZERO
	m.scale_min = scale_min
	m.scale_max = scale_max
	var ramp := Gradient.new()  # fade in and out over each particle's life
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	m.color_ramp = tex
	return m


func _particles(amount: int, lifetime: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime  # already hanging there when the level loads
	p.randomness = 1.0
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var r := region.radius + 20.0
	p.visibility_aabb = AABB(Vector3(-r, -60, -r), Vector3(r * 2, 140, r * 2))
	add_child(p)
	return p


func _add_haze() -> void:
	_haze = _particles(clampi(int(region.radius * region.radius * 0.025), 60, 220), 30.0)
	_haze.name = "Haze"
	_haze.process_material = _process_material(0.25, 14.0, 26.0)
	var noise := NoiseTexture2D.new()
	noise.seamless = true
	noise.width = 128
	noise.height = 128
	noise.noise = FastNoiseLite.new()
	noise.noise.frequency = 0.03
	_haze_mat = ShaderMaterial.new()
	_haze_mat.shader = HAZE_SHADER
	_haze_mat.set_shader_parameter(&"noise_tex", noise)
	_haze_mat.set_shader_parameter(&"haze_color", haze_color)
	var quad := QuadMesh.new()
	quad.material = _haze_mat
	_haze.draw_pass_1 = quad


func _billboard_material(color: Color, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.albedo_texture = _dot_texture()
	return m


func _dot_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 32
	t.height = 32
	return t


func _add_motes() -> void:
	_motes = _particles(clampi(int(region.radius * 20.0), 1200, 2400), 8.0)
	_motes.name = "Sand"
	var m := _process_material(1.0, 0.6, 1.6)
	m.particle_flag_align_y = true  # sand_streak stretches along the velocity
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 2.0
	m.turbulence_noise_scale = 6.0
	m.turbulence_influence_min = 0.05
	m.turbulence_influence_max = 0.15
	_motes.process_material = m
	_motes.material_override = streak_material(mote_color)
	_motes.draw_pass_1 = QuadMesh.new()


static func streak_material(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = STREAK_SHADER
	mat.set_shader_parameter(&"sand_color", color)
	return mat


func _add_sparkles() -> void:
	var sparkles := _particles(clampi(int(region.radius * 3.0), 150, 320), 4.0)
	sparkles.name = "Sparkles"
	sparkles.preprocess = 0.0
	sparkles.one_shot = true
	sparkles.explosiveness = 0.3
	var m := _process_material(1.0, 0.8, 1.8)
	m.direction = Vector3.UP
	m.spread = 25.0
	m.initial_velocity_min = 0.4
	m.initial_velocity_max = 1.0
	m.gravity = Vector3(0, 0.8, 0)
	sparkles.process_material = m
	sparkles.material_override = _billboard_material(sparkle_color, true)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.35, 0.35)
	sparkles.draw_pass_1 = quad
	sparkles.emitting = true
