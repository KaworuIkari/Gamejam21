@tool
class_name GrowthSeed extends Node3D
## Ground that is always green, from the first frame (e.g. the spawn clearing).
## Drop it anywhere in the level and set radius; it adds itself to the GrowthMap's
## permanent layer, which survives resets. Use several overlapping seeds for
## non-round shapes.
## The editor shows the area as a green disc (not visible in game).

## Fully green inside ~60% of this, fading out to a noisy rim at the full radius.
@export var radius := 15.0:
	set(v):
		radius = maxf(v, 1.0)
		_update_preview()

var _preview: MeshInstance3D


func _ready() -> void:
	if Engine.is_editor_hint():
		_update_preview()
		return
	var growth := get_node_or_null(^"/root/GrowthMap")
	if growth:
		growth.seed_circle(global_position, radius)


func _update_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _preview == null:
		_preview = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.3, 1.0, 0.3, 0.3)
		mat.no_depth_test = true
		_preview.material_override = mat
		add_child(_preview)  # no owner: never saved into the scene
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.2
	_preview.mesh = disc
