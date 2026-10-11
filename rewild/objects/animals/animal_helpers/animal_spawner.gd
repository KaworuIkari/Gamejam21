@tool
extends Node3D
class_name AnimalSpawner
## Spawns animals at random navigable points within `radius` of this node.
## In the editor, shows the spawn radius as a red circle while selected.

@export var animal_scene: PackedScene
@export var count := 10
@export var radius := 50.0:
	set(v):
		radius = v
		_rebuild_circle()
@export var height_offset := 0.2      # drop in slightly above the nav mesh
@export var spawn_on_ready := true

@export_group("Editor Debug")
@export var debug_color := Color.RED
@export var debug_segments := 64

var _circle: MeshInstance3D


func _ready() -> void:
	if Engine.is_editor_hint():
		_rebuild_circle()
		return                         # never spawn animals in the editor
	set_process(false)
	if spawn_on_ready:
		spawn_all()


func _process(_delta: float) -> void:
	if _circle == null:
		return
	var ei = Engine.get_singleton("EditorInterface")   # looked up dynamically: safe in exported builds
	_circle.visible = ei != null and self in ei.get_selection().get_selected_nodes()


func _rebuild_circle() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _circle == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = debug_color
		mat.no_depth_test = true                         # visible through the terrain
		_circle = MeshInstance3D.new()
		_circle.material_override = mat
		_circle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_circle, false, Node.INTERNAL_MODE_BACK)   # internal + no owner: never saved
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in debug_segments + 1:
		var a := TAU * i / debug_segments
		im.surface_add_vertex(Vector3(cos(a) * radius, 0.0, sin(a) * radius))
	im.surface_end()
	_circle.mesh = im


func spawn_all() -> void:
	var map := get_world_3d().navigation_map
	var waited := 0.0
	while NavigationServer3D.map_get_iteration_id(map) == 0 \
			or not NavigationServer3D.map_get_closest_point_owner(map, global_position).is_valid():
		if waited > 5.0:
			push_error("AnimalSpawner: no navigation mesh on the map (regions: %d)" \
					% NavigationServer3D.map_get_regions(map).size())
			return
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	for i in count:
		spawn_one(map)


func spawn_one(map: RID) -> Node3D:
	var a := randf() * TAU
	var r := sqrt(randf()) * radius
	var guess := global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
	var p := NavigationServer3D.map_get_closest_point(map, guess)

	var animal := animal_scene.instantiate() as Node3D
	animal.position = to_local(p + Vector3.UP * height_offset)
	animal.rotation.y = randf() * TAU
	add_child(animal)
	# print(animal, " added at ", p, "!")
	return animal
