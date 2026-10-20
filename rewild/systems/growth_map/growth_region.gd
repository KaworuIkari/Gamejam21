@tool
class_name GrowthRegion extends Node3D
## A named area whose share of green ground is measured for the restoration
## progress (terminal page and HUD), e.g. the lake, the forest. Smaller regions win
## where they overlap bigger ones; land outside every region still counts towards
## the total. Sea and lake beds (below GrowthMap.land_min_height) never count.
## The editor shows the area as a green disc (not visible in game).

## Stable key for code, e.g. &"lake".
@export var region_id: StringName = &""
## Shown name; a translation key or plain text.
@export var title := ""
## Radius of the area in metres.
@export var radius := 60.0:
	set(v):
		radius = maxf(v, 1.0)
		_changed()

var _preview: MeshInstance3D


func _ready() -> void:
	if Engine.is_editor_hint():
		_update_preview()
		return
	set_notify_transform(true)
	var growth := get_node_or_null(^"/root/GrowthMap")
	if growth:
		growth.add_progress_region(self)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	var growth := get_node_or_null(^"/root/GrowthMap")
	if growth:
		growth.remove_progress_region(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_changed()


func _changed() -> void:
	if Engine.is_editor_hint():
		_update_preview()
		return
	if is_inside_tree():
		var growth := get_node_or_null(^"/root/GrowthMap")
		if growth:
			growth.update_progress_regions()


func _update_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _preview == null:
		_preview = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.35, 0.9, 0.4, 0.2)
		mat.no_depth_test = true
		_preview.material_override = mat
		add_child(_preview)  # no owner: never saved into the scene
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.2
	_preview.mesh = disc
