class_name SkyProgression extends Node
## Swaps the environment's sky for a panorama that follows the story, cross-fading softly:
## night until the pump is switched on, then morning; noon at 40% battery charge, afternoon at
## 70%, and the end sky once it is full (BatteryCharge.charge(), the terminal's percentage).
## On load the sky jumps straight to where the save is, without a fade.

const SHADER := preload("res://shaders/sky/sky_crossfade.gdshader")
const SKIES: Array[Texture2D] = [
	preload("res://assets/sky/0_night.png"),
	preload("res://assets/sky/1_morning.png"),
	preload("res://assets/sky/2_noon.png"),
	preload("res://assets/sky/3_afternoon.png"),
	preload("res://assets/sky/4_end.png"),
]
const PUMP_EVENT := &"pump_started"

@export var environment: WorldEnvironment
## The pump's water chain: morning comes in the moment it starts, not when the water arrives.
@export var pump: WaterFlowSwitch
## Battery charge (0..1) at which noon and afternoon come in; the end sky waits for full.
@export_range(0.0, 1.0) var noon_at := 0.4
@export_range(0.0, 1.0) var afternoon_at := 0.7
## Seconds one sky takes to fade into the next.
@export var fade_time := 8.0
## Changes in the first seconds snap instead of fading (the save's progress arriving).
@export var settle_time := 2.0

var _material := ShaderMaterial.new()
var _from := 0
var _to := 0
var _target := 0
var _t := 1.0
var _age := 0.0


func _ready() -> void:
	_material.shader = SHADER
	if environment and environment.environment and environment.environment.sky:
		environment.environment.sky.sky_material = _material
	Quests.changed.connect(_refresh)
	GrowthMap.progress_changed.connect(_refresh)
	if pump:
		pump.started.connect(_refresh)
	_refresh()
	_show(_target, _target, 0.0)


func _process(delta: float) -> void:
	_age += delta
	if _t >= 1.0:
		if _target == _from:
			set_process(_age < settle_time)
			return
		if _age < settle_time:
			_from = _target
			_show(_from, _from, 0.0)
			return
		# Head straight for the newest target, even if it skipped a step.
		_to = _target
		_t = 0.0
	_t = minf(_t + delta / fade_time, 1.0)
	_show(_from, _to, smoothstep(0.0, 1.0, _t))
	if _t >= 1.0:
		_from = _to
		_show(_from, _from, 0.0)


func _refresh() -> void:
	_target = _sky_for_progress()
	if _target != _from or _t < 1.0:
		set_process(true)


func _sky_for_progress() -> int:
	var pump_on := pump != null and pump.is_on
	if not pump_on and Quests.event_count(PUMP_EVENT) <= 0:
		return 0
	if BatteryCharge.full():
		return 4
	var charge := BatteryCharge.charge()
	if charge >= afternoon_at:
		return 3
	if charge >= noon_at:
		return 2
	return 1


func _show(from: int, to: int, blend: float) -> void:
	_material.set_shader_parameter(&"sky_from", SKIES[from])
	_material.set_shader_parameter(&"sky_to", SKIES[to])
	_material.set_shader_parameter(&"blend", blend)
