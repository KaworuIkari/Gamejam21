@tool
class_name Grassland extends MultiMeshInstance3D
@export var pavement_group_name:String = "pavement"
@onready var ground: MeshInstance3D = $Ground
@export var grass_blade:Mesh = null
@export_range(1.0, 10000.0, 1.0) var instance_count:int = 256
@export_range(0.1, 4.0, 1.0) var grass_height:float = 1.0
@export_range(0.5, 10.0, 0.1) var spatial_cell_size:float = 2.0
@export_range(0.0, 0.1) var AABB_padding: float = 0.05
@export_tool_button("Populate Grass") var populate_button = populate

class Pavement:
	var world_aabb:AABB
	var pave_mi:MeshInstance3D

func populate():
	if grass_blade == null:
		push_error("Assign grass_blade")
		return

	var mm = MultiMesh.new()
	mm.mesh = grass_blade
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var instances:Array[Transform3D] = []
	var attempts:int = 0
	var max_attempts:int = instance_count * 8

	var pavement_nodes:Array[Node] = get_tree().get_nodes_in_group(pavement_group_name)
	var spatial_hash:Dictionary = {}

	for pave_root in pavement_nodes:
		if pave_root is not MeshInstance3D:
			continue
		var mi:MeshInstance3D = pave_root
		if mi.mesh == null:
			continue

		var local_aabb = mi.mesh.get_aabb().grow(AABB_padding)
		var world_aabb = mi.global_transform * local_aabb
		if not world_aabb.has_volume():
			continue

		var min_cell = Vector2i(int(floor(world_aabb.position.x / spatial_cell_size)), int(floor(world_aabb.position.z / spatial_cell_size)))
		var max_cell = Vector2i(int(floor((world_aabb.position.x + world_aabb.size.x) / spatial_cell_size)), int(floor((world_aabb.position.z + world_aabb.size.z) / spatial_cell_size)))

		var entry = Pavement.new()
		entry.world_aabb = world_aabb
		entry.pave_mi = mi

		for cx in range(min_cell.x, max_cell.x + 1):
			for cz in range(min_cell.y, max_cell.y + 1):
				var key = Vector2i(cx, cz)
				if not spatial_hash.has(key):
					spatial_hash[key] = []
				spatial_hash[key].append(entry)

	while instances.size() < instance_count and attempts < max_attempts:
		attempts += 1
		var sample = get_random_point_on_mesh(ground)
		if sample.is_empty():
			continue

		var world_pos:Vector3 = sample["pos"]
		var world_normal:Vector3 = sample["normal"]
		var grass_tip:Vector3 = world_pos + world_normal * grass_height
		var skip:bool = false

		var cell_key = Vector2i(int(floor(world_pos.x / spatial_cell_size)), int(floor(world_pos.z / spatial_cell_size)))
		if spatial_hash.has(cell_key):
			for entry in spatial_hash[cell_key]:
				if entry.world_aabb.intersects_segment(world_pos, grass_tip):
					skip = true
					break
		if skip:
			continue
		# watch out for the normal!
		# -world_normal in this case, not world_normal!!!
		var grass_basis = Basis.looking_at(-Vector3.FORWARD, -world_normal)
		var local_relative_pos = global_transform.affine_inverse() * world_pos
		instances.append(Transform3D(grass_basis, local_relative_pos))

	mm.instance_count = instances.size()
	for i in range(instances.size()):
		mm.set_instance_transform(i, instances[i])
	multimesh = mm
	print("Grass populated, count: ", instances.size())

func get_random_point_on_mesh(mesh_instance:MeshInstance3D) -> Dictionary:
	var mesh:Mesh = mesh_instance.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return {"position":Vector3.ZERO, "normal":Vector3.UP}

	# 只取第0个surface，如果多surface要循环处理
	var surf_idx = 0
	var arrays = mesh.surface_get_arrays(surf_idx)
	var vertices:PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices:PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	if vertices.is_empty():
		return {"position":Vector3.ZERO, "normal":Vector3.UP}

	# 计算所有三角形面积，加权采样
	var triangle_areas:PackedFloat32Array = []
	var total_area = 0.0
	for i in range(0, indices.size(), 3):
		var i0 = indices[i]
		var i1 = indices[i+1]
		var i2 = indices[i+2]
		var v0 = vertices[i0]
		var v1 = vertices[i1]
		var v2 = vertices[i2]
		var area = 0.5 * (v1-v0).cross(v2-v0).length()
		triangle_areas.append(area)
		total_area += area

	if total_area <= 0.0:
		return {"position":Vector3.ZERO, "normal":Vector3.UP}

	# 按面积权重随机选三角形
	var r = randf() * total_area
	var acc = 0.0
	var selected_tri = 0
	for idx in range(triangle_areas.size()):
		acc += triangle_areas[idx]
		if acc >= r:
			selected_tri = idx
			break

	# 获取选中三角的三个顶点
	var tri_start = selected_tri * 3
	var i0 = indices[tri_start]
	var i1 = indices[tri_start+1]
	var i2 = indices[tri_start+2]
	var v0 = vertices[i0]
	var v1 = vertices[i1]
	var v2 = vertices[i2]

	# barycentric 随机点
	var u = sqrt(randf())
	var v = randf()
	var a = 1.0 - u
	var b = u * (1.0 - v)
	var c = u * v
	var local_pos = a*v0 + b*v1 + c*v2

	# 计算三角形法线
	var tri_normal = (v1-v0).cross(v2-v0).normalized()

	# 转世界空间（MeshInstance的transform）
	var world_pos = mesh_instance.global_transform * local_pos
	var world_normal = mesh_instance.global_transform.basis * tri_normal

	return {
		"pos": world_pos,
		"normal": world_normal
	}

func get_random_point_in_triangle(a:Vector3, b:Vector3, c:Vector3) -> Vector3:
	var r1 = sqrt(randf())
	var r2 = randf()
	return (1.0 - r1) * a + (r1 * (1.0 - r2)) * b + (r1 * r2) * c
