class_name WaterBlob extends MeshInstance3D

var _p0: Vector3
var _v0: Vector3
var _g: float
var _mask: int
var _exclude: RID
var _t := 0.0

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
		blob_die()
		return
	global_position = next
	if _t > 6.0 or global_position.y < -50.0:
		blob_die()
		
func blob_die() -> void:
	print("blob died")
	queue_free()
