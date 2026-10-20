class_name AutoBlocker
extends Node
## Makes the object it is placed under (its parent) a blocker: optional solid collision built
## from its meshes, plus a navigation obstacle covering its footprint.
## The parent should also be in the "nav_blockers" group so the navmesh bake treats it as solid.

## Build trimesh collision for every mesh below the parent. Turn off when the object already
## has its own colliders.
@export var solid := true
## Add a NavigationObstacle3D matching the parent's footprint.
@export var obstacle := true


func _ready() -> void:
	# The parent is still setting up its children; wait one frame before adding to it.
	_build.call_deferred()


func _build() -> void:
	var root := get_parent() as Node3D
	if root == null:
		return
	var meshes: Array[MeshInstance3D] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh != null and mesh.visible:
			meshes.append(mesh)
	if solid:
		for mesh in meshes:
			mesh.create_trimesh_collision()
	if obstacle and not meshes.is_empty():
		_add_obstacle(root, meshes)


func _add_obstacle(root: Node3D, meshes: Array[MeshInstance3D]) -> void:
	var to_local := root.global_transform.affine_inverse()
	var box := to_local * meshes[0].global_transform * meshes[0].get_aabb()
	for mesh in meshes:
		box = box.merge(to_local * mesh.global_transform * mesh.get_aabb())
	var low := box.position
	var high := box.end
	var ob := NavigationObstacle3D.new()
	ob.name = "NavigationObstacle3D"
	ob.position = Vector3(0.0, low.y, 0.0)
	ob.height = maxf(box.size.y, 1.0)
	# Clockwise seen from above: the obstacle pushes agents out of the footprint.
	ob.vertices = PackedVector3Array([
		Vector3(low.x, 0.0, low.z), Vector3(high.x, 0.0, low.z),
		Vector3(high.x, 0.0, high.z), Vector3(low.x, 0.0, high.z)])
	root.add_child(ob)
