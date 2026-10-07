class_name WorldStages extends Node
## Moves the world through its stages (wasteland -> revival -> golden meadow).
## Call advance() when a quest is completed, or go_to(index) to jump.
## Lighting, sky, fog and distant clouds blend over each stage's
## transition_time while its growth event spreads green over the GrowthMap.

signal stage_changed(index: int, stage: WorldStage)

@export var stages: Array[WorldStage] = []
@export var environment: WorldEnvironment
@export var sun: DirectionalLight3D
## Optional: recolours its cloud banks and raises/lowers its water.
@export var meadow: MeadowWorld
## Where blooms start (e.g. the planted device).
@export var focus: Node3D
@export var start_stage := 0
## Clear the GrowthMap on start. Turn off when loading saved progress.
@export var reset_growth_on_start := true

var current := -1
var _tween: Tween
var _water_rest_y := 0.0


func _ready() -> void:
	_start.call_deferred()  # let MeadowWorld build its clouds and water first


func _start() -> void:
	if meadow and meadow.water:
		_water_rest_y = meadow.water.position.y
	var growth := _growth()
	if growth and reset_growth_on_start:
		growth.clear()
	# Restoring a stage replays every growth event up to it, instantly.
	for i in range(0, start_stage + 1):
		_run_growth(stages[i], true)
	go_to(start_stage, true, false)


func advance() -> void:
	if current < stages.size() - 1:
		go_to(current + 1)


func go_to(index: int, instant := false, run_growth := true) -> void:
	if stages.is_empty():
		return
	index = clampi(index, 0, stages.size() - 1)
	var st := stages[index]
	current = index
	var d := 0.0 if instant else st.transition_time

	if _tween:
		_tween.kill()
		_tween = null
	if d > 0.0:
		_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if sun:
		_blend(sun, "rotation_degrees", st.sun_rotation_degrees, d)
		_blend(sun, "light_color", st.sun_color, d)
		_blend(sun, "light_energy", st.sun_energy, d)

	if environment and environment.environment:
		var env := environment.environment
		_blend(env, "fog_light_color", st.fog_color, d)
		_blend(env, "fog_density", st.fog_density, d)
		_blend(env, "fog_height_density", st.fog_height_density, d)
		_blend(env, "fog_sun_scatter", st.fog_sun_scatter, d)
		_blend(env, "ambient_light_energy", st.ambient_energy, d)
		_blend(env, "tonemap_exposure", st.exposure, d)
		_blend(env, "adjustment_saturation", st.saturation, d)
		if env.sky and env.sky.sky_material is ShaderMaterial:
			var sky := env.sky.sky_material as ShaderMaterial
			_blend_param(sky, "zenith_color", st.sky_zenith, d)
			_blend_param(sky, "horizon_color", st.sky_horizon, d)
			_blend_param(sky, "cloud_light", st.sky_cloud_light, d)
			_blend_param(sky, "cloud_shade", st.sky_cloud_shade, d)
			_blend_param(sky, "cloud_coverage", st.sky_cloud_coverage, d)

	if meadow:
		if meadow.cloud_material:
			_blend_param(meadow.cloud_material, "light_color", st.bank_light, d)
			_blend_param(meadow.cloud_material, "shade_color", st.bank_shade, d)
		if meadow.water:
			_blend(meadow.water, "position:y", _water_rest_y + st.water_offset, d)

	if run_growth:
		_run_growth(st, instant)
	stage_changed.emit(index, st)


func _run_growth(st: WorldStage, instant: bool) -> void:
	var growth := _growth()
	if growth == null:
		return
	var pos := focus.global_position if focus else Vector3.ZERO
	var dur := 0.0 if instant else st.growth_duration
	match st.growth_event:
		WorldStage.GrowthEvent.BLOOM:
			growth.reveal_from(pos, dur, st.growth_radius)
		WorldStage.GrowthEvent.REVEAL_ALL:
			growth.reveal_from(pos, dur, 0.0)
		WorldStage.GrowthEvent.CLEAR:
			growth.clear()


func _growth() -> Node:
	return get_node_or_null("/root/GrowthMap")


func _blend(obj: Object, prop: String, value: Variant, d: float) -> void:
	if d <= 0.0:
		obj.set_indexed(prop, value)
	else:
		_tween.tween_property(obj, prop, value, d)


func _blend_param(mat: ShaderMaterial, param: String, value: Variant, d: float) -> void:
	var from: Variant = mat.get_shader_parameter(param)
	if from == null and mat.shader:
		from = RenderingServer.shader_get_parameter_default(mat.shader.get_rid(), param)
	# Colors in shaders arrive as Color or Vector3 depending on the hint.
	if value is Color and from is Vector3:
		value = Vector3(value.r, value.g, value.b)
	if d <= 0.0 or from == null or typeof(from) != typeof(value):
		mat.set_shader_parameter(param, value)
	else:
		_tween.tween_method(func(v: Variant) -> void: mat.set_shader_parameter(param, v), from, value, d)
