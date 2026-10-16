@tool
class_name ThrowTarget extends Node3D
## Where a Throwable should be thrown, e.g. the lake little Leon goes into. Put it at the
## water surface over the basin and size `radius` to cover it. A throw counts when it
## comes down within the radius at or below this node's height (on the water, or on the
## lake bed while it's drained). The editor shows the area as a blue disc (not in game).

## Radius of the area in metres.
@export var radius := 30.0:
	set(v):
		radius = maxf(v, 1.0)
		_update_preview()

var _preview: MeshInstance3D


func _ready() -> void:
	_update_preview()


## True if `point` is inside the area and no higher than the surface (+ `slack` metres).
func contains(point: Vector3, slack := 0.0) -> bool:
	var d := Vector2(point.x - global_position.x, point.z - global_position.z)
	return d.length() <= radius and point.y <= global_position.y + slack


func _update_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _preview == null:
		_preview = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.3, 0.6, 1.0, 0.25)
		mat.no_depth_test = true
		_preview.material_override = mat
		add_child(_preview)  # no owner: never saved into the scene
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.2
	_preview.mesh = disc
