extends StaticBody3D
## Geometry stays in island_boundary.tscn; warning distance follows the edited boxes.
@export_range(0.0, 100.0, 0.5, "suffix:m") var warning_distance := 12.0
@export_range(0.0, 100.0, 0.5, "suffix:m") var release_distance := 18.0


func is_near_boundary(world_position: Vector3, was_near: bool = false) -> bool:
	var distance := maxf(warning_distance, release_distance) if was_near else warning_distance
	for child in get_children():
		if not child is CollisionShape3D or child.disabled or not child.shape is BoxShape3D:
			continue
		var point: Vector3 = child.to_local(world_position)
		var half: Vector3 = child.shape.size * 0.5
		var offset := Vector3(maxf(absf(point.x) - half.x, 0.0), 0.0, maxf(absf(point.z) - half.z, 0.0))
		if (child.global_basis * offset).length_squared() <= distance * distance:
			return true
	return false
