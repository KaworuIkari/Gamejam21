@tool
class_name AnimalCircle
extends Node3D
## Where one species may spawn. Place as a child of the AnimalSpawner; one is picked at random.
## Land animals snap to the navmesh. Seagulls, sharks and fish spawn at this node's height,
## so put the circle at flying altitude or water depth.

enum Kind { CRAB, CHICKEN, FOX, SEAGULL, SHARK, SMALL_FISH }
const COLORS := [Color.ORANGE, Color.YELLOW, Color.RED, Color.WHITE, Color.BLUE, Color.CYAN]

@export var kind := Kind.CRAB:
	set(v):
		kind = v
		_rebuild()
@export var radius := 20.0:
	set(v):
		radius = maxf(v, 0.5)
		_rebuild()

var _mesh: MeshInstance3D


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_mesh.material_override = StandardMaterial3D.new()
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh, false, Node.INTERNAL_MODE_BACK)  # never saved
	var mat := _mesh.material_override as StandardMaterial3D
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.albedo_color = COLORS[kind]
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in 49:
		var a := TAU * i / 48.0
		im.surface_add_vertex(Vector3(cos(a), 0.0, sin(a)) * radius)
	im.surface_end()
	_mesh.mesh = im