extends MeshInstance3D
class_name Jetpack
## Jetpack with two quad flames as children. Each flame yaws around its own rest
## local Y to face the camera, and stretches/fades with intensity.
## Flames: QuadMesh + jetpack_flame.gdshader. Drive with burst() and set_thrust().

@export_group("Shape")
@export var length_idle := 0.35        # fraction of full length at low intensity (1.0 = no stretch)

@export_group("Response")
@export var burst_duration := 0.25     # how long a tap keeps the flame lit
@export var response_speed := 18.0     # how fast intensity follows its target

var intensity := 0.0
var _thrust_target := 0.0
var _burst := 0.0

@onready var flames: Array[MeshInstance3D] = [$Flame, $Flame2]
var _rest: Array[Transform3D] = []


func _ready() -> void:
	for flame in flames:
		_rest.append(flame.transform)          # placement you set in the editor
		if flame.mesh is QuadMesh:             # pivot at the top edge → grows away from the nozzle
			var q := flame.mesh as QuadMesh
			q.center_offset = Vector3(0.0, -q.size.y * 0.5, 0.0)
		flame.visible = false


@onready var thrust_sound: FmodEventEmitter3D = $FmodEventEmitter3D
var _thrust_playing := false

func burst() -> void:
	_burst = 1.0

## Hold: call every frame with the jetpack's state; spool 0..1 scales the flame.
func set_thrust(active: bool, spool: float = 1.0) -> void:
	_thrust_target = clampf(spool, 0.0, 1.0) if active else 0.0


func _process(delta: float) -> void:
	_burst = maxf(_burst - delta / burst_duration, 0.0)
	var target := maxf(_thrust_target, _burst)
	intensity = lerpf(intensity, target, 1.0 - exp(-response_speed * delta))

	var on := intensity > 0.01
	var cam := get_viewport().get_camera_3d()
	var length := lerpf(length_idle, 1.0, intensity)

	# audio
	if on and not _thrust_playing:
		_thrust_playing = true
		thrust_sound.play()
	elif not on and _thrust_playing:
		_thrust_playing = false
		thrust_sound.stop()

	for i in flames.size():
		var flame := flames[i]
		flame.visible = on
		if not on or cam == null:
			continue
		flame.set_instance_shader_parameter("intensity", intensity)

		# Camera in the flame's rest frame (no yaw), so the angle doesn't feed back on itself
		var rest_global := global_transform * _rest[i]
		var cam_local := rest_global.affine_inverse() * cam.global_position
		var yaw := atan2(cam_local.x, cam_local.z)    # quad faces local +Z

		var b := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(1.0, length, 1.0))
		flame.transform = _rest[i] * Transform3D(b, Vector3.ZERO)
