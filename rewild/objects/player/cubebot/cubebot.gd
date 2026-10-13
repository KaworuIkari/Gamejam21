@tool
class_name CubeBot
extends Node3D
## Wraps cubebot.glb: owns the eye glow (blue <-> yellow) and plays the baked animations.
## Animations: Idle, Walk, Run, Fall (looping), Jump_Start, Land (one-shot).
## Rebuild the model with source/build_cubebot.py (see README.md).

signal animation_finished(anim_name: StringName)

const EYE_BLUE := Color(0.25, 0.65, 1.0)
const EYE_YELLOW := Color(1.0, 0.75, 0.12)

## 0 = blue, 1 = yellow. Animate it, tween it, or call glow_to().
@export_range(0.0, 1.0) var eye_mix := 0.0:
	set(v):
		eye_mix = clampf(v, 0.0, 1.0)
		_apply_eye()
@export_range(0.0, 16.0) var eye_emission := 2.5:
	set(v):
		eye_emission = v
		_apply_eye()
## Energy of the light the eye casts on the world (0 disables it).
@export_range(0.0, 8.0) var eye_light_energy := 1.0:
	set(v):
		eye_light_energy = v
		_apply_eye()
@export var cast_beam := true:
	set(v):
		cast_beam = v
		_apply_eye()
@export var autoplay := &"Idle"

@onready var model: Node3D = $Model
@onready var anim_player: AnimationPlayer = $Model/AnimationPlayer

var _glow_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _eye_light: OmniLight3D
var _beam: SpotLight3D
var _tween: Tween


func _ready() -> void:
	_setup_eye()
	_apply_eye()
	anim_player.animation_finished.connect(func(n): animation_finished.emit(n))
	if autoplay != &"" and anim_player.has_animation(autoplay):
		anim_player.play(autoplay)


## Cross-fades to an animation. Returns false if it doesn't exist.
func play(anim_name: StringName, blend := 0.15, speed := 1.0) -> bool:
	if not anim_player.has_animation(anim_name):
		return false
	if anim_player.current_animation == anim_name:
		anim_player.speed_scale = speed
		return true
	anim_player.play(anim_name, blend, speed)
	return true


## Smoothly shifts the eye colour. target 0 = blue, 1 = yellow.
func glow_to(target: float, duration := 0.4) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "eye_mix", target, duration).set_trans(Tween.TRANS_SINE)


func eye_color() -> Color:
	return EYE_BLUE.lerp(EYE_YELLOW, eye_mix)


func _setup_eye() -> void:
	var mesh_inst := model.find_child("CubeBot", true, false) as MeshInstance3D
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if mesh_inst == null or skeleton == null:
		push_warning("CubeBot: model structure changed, eye glow disabled")
		return
	# per-instance copies so several robots can have different eye colours
	for i in mesh_inst.mesh.get_surface_count():
		var mat := mesh_inst.mesh.surface_get_material(i) as StandardMaterial3D
		if mat == null:
			continue
		match mat.resource_name:
			"EyeGlow":
				_glow_mat = mat.duplicate()
				mesh_inst.set_surface_override_material(i, _glow_mat)
			"EyeCore":
				_core_mat = mat.duplicate()
				mesh_inst.set_surface_override_material(i, _core_mat)

	var socket := BoneAttachment3D.new()
	socket.name = "EyeSocket"
	skeleton.add_child(socket)
	socket.bone_name = "eye"
	_eye_light = OmniLight3D.new()
	_eye_light.omni_range = 2.5
	_eye_light.omni_attenuation = 1.5
	_eye_light.position = Vector3(0, 0.12, 0)  # bone +Y = forward
	socket.add_child(_eye_light)
	_beam = SpotLight3D.new()
	_beam.spot_range = 8.0
	_beam.spot_angle = 22.0
	_beam.shadow_enabled = true
	# the eye bone points forward along +Y; face the spotlight (-Z) the same way
	_beam.rotation = Vector3(PI / 2, 0, 0)
	socket.add_child(_beam)


func _apply_eye() -> void:
	if _glow_mat == null:
		return
	var c := eye_color()
	_glow_mat.albedo_color = c
	_glow_mat.emission = c
	_glow_mat.emission_energy_multiplier = eye_emission
	_core_mat.albedo_color = c.lerp(Color.WHITE, 0.75)
	_core_mat.emission = c.lerp(Color.WHITE, 0.6)
	_core_mat.emission_energy_multiplier = eye_emission * 1.4
	_eye_light.light_color = c
	_eye_light.light_energy = eye_light_energy
	_eye_light.visible = eye_light_energy > 0.0
	_beam.light_color = c
	_beam.light_energy = eye_light_energy * 2.0
	_beam.visible = cast_beam and eye_light_energy > 0.0