class_name WaterBlob extends MeshInstance3D

var _p0: Vector3
var _v0: Vector3
var _g: float
var _mask: int
var _exclude: RID
var _t := 0.0

signal on_blob_die(on_target: bool)
## Metres of ground one blob wets.
@export var splash_radius := 4.0
var _dead := false

@onready var sound_emitter : FmodEventEmitter3D = $FmodEventEmitter3D

func _ready() -> void:
	set_instance_shader_parameter("time_offset", randf_range(0.0, 60.0))

func launch(p0: Vector3, v0: Vector3, g: float, mask: int, exclude: RID) -> void:
	_p0 = p0; _v0 = v0; _g = g; _mask = mask; _exclude = exclude
	global_position = p0

func _physics_process(delta: float) -> void:
	_t += delta
	var next := _p0 + _v0 * _t + Vector3.DOWN * 0.5 * _g * _t * _t
	var q := PhysicsRayQueryParameters3D.create(global_position, next, _mask, [_exclude])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit.position
		# spawn splash here
		blob_die(_is_good_target(hit.collider))
		return
	global_position = next
	if _t > 6.0 or global_position.y < -50.0:
		blob_die()
		
func blob_die(on_target : bool = false) -> void:
	sound_emitter.play_one_shot()
	if _dead:
		return
	_dead = true
	on_blob_die.emit(on_target)
	GrowthMap.water(global_position, splash_radius)
	WorldEvents.report(global_position, &"water_blob", 0.7 if on_target else 0.35)
	queue_free()

func _is_good_target(collider: Object) -> bool:
	if collider == null:
		return false
	# TODO: decide what counts as a good shot, e.g.:
	# return collider is Node and (collider as Node).is_in_group("plant")
	return false
