@tool
class_name GrowthSpreadRegion extends Node3D
## Sets how fast green patches creep towards each other inside a circle (or the
## whole map), overriding the GrowthMap defaults there. Smaller regions win where
## they overlap bigger ones. speed 0 stops spreading in the area (e.g. a desert
## that must stay barren until watered).
## The editor shows the area as a blue disc (not visible in game).

## Radius of the area in metres (ignored when everywhere is on).
@export var radius := 30.0:
	set(v):
		radius = maxf(v, 1.0)
		_changed()
## Covers the whole map, below every other region: use it for the level's defaults.
@export var everywhere := false:
	set(v):
		everywhere = v
		_changed()
## Can be switched from code, e.g. let a zone spread once its quest is done.
@export var enabled := true:
	set(v):
		enabled = v
		_changed()

@export_group("Spreading")
## Metres per second a patch edge moves when other green is right in front of it.
@export var speed := 0.3
## Green this close (metres) in front of an edge pulls it; the closer, the faster.
@export var attract_distance := 16.0
## Share of speed an edge keeps with no green in range (0 = lone patches stay put).
@export_range(0.0, 1.0) var lone_spread := 0.0
## Speed by growth phase (x = how green the patch is at its edge, y = multiplier).
## Empty = the GrowthMap default (sprouting patches barely creep, meadow at full speed).
@export var spread_by_growth: Curve

var _preview: MeshInstance3D


func _ready() -> void:
	if Engine.is_editor_hint():
		_update_preview()
		return
	set_notify_transform(true)
	var growth := get_node_or_null(^"/root/GrowthMap")
	if growth:
		growth.add_spread_region(self)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	var growth := get_node_or_null(^"/root/GrowthMap")
	if growth:
		growth.remove_spread_region(self)


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
			growth.update_spread_regions()


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
	_preview.visible = not everywhere
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.2
	_preview.mesh = disc
