## A body of stylized water. Drop stylized_water.tscn into a level, scale/move it over a
## dip in the terrain, and point `camera` at the player camera. When that camera goes
## below the surface it switches on underwater fog, tint, wobble and light shafts.
class_name StylizedWater
extends MeshInstance3D

const FOG_SHADER := preload("res://meadow/water/underwater_fog.gdshader")
const SCREEN_SHADER := preload("res://meadow/water/underwater_screen.gdshader")

## The camera that can dive. Leave empty to use the first active camera found.
@export var camera: Camera3D
@export var underwater_fog_color := Color(0.10, 0.42, 0.58)
@export var underwater_fog_density := 0.08

var _fog_quad: MeshInstance3D
var _screen_layer: CanvasLayer


func _ready() -> void:
	var surface := get_active_material(0) as ShaderMaterial
	if surface:
		surface.set_shader_parameter("underwater_fog_color", underwater_fog_color)
		surface.set_shader_parameter("underwater_fog_density", underwater_fog_density)

	_fog_quad = MeshInstance3D.new()
	_fog_quad.name = "UnderwaterFog"
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	_fog_quad.mesh = quad
	_fog_quad.extra_cull_margin = 16384.0
	_fog_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fog_mat := ShaderMaterial.new()
	fog_mat.shader = FOG_SHADER
	fog_mat.render_priority = -1 # under the water surface, which fogs its own underside
	fog_mat.set_shader_parameter("fog_color", underwater_fog_color)
	fog_mat.set_shader_parameter("fog_density", underwater_fog_density)
	_fog_quad.material_override = fog_mat
	_fog_quad.visible = false

	_screen_layer = CanvasLayer.new()
	_screen_layer.name = "UnderwaterScreen"
	_screen_layer.layer = 10
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var screen_mat := ShaderMaterial.new()
	screen_mat.shader = SCREEN_SHADER
	rect.material = screen_mat
	_screen_layer.add_child(rect)
	_screen_layer.visible = false


func _process(_delta: float) -> void:
	var cam := camera if is_instance_valid(camera) else _find_camera()
	if cam == null:
		return
	# The effects must live in the camera's own viewport (it may be a SubViewport).
	if _fog_quad.get_parent() != cam:
		if _fog_quad.get_parent():
			_fog_quad.get_parent().remove_child(_fog_quad)
		cam.add_child(_fog_quad)
	if _screen_layer.get_parent() != cam.get_viewport():
		if _screen_layer.get_parent():
			_screen_layer.get_parent().remove_child(_screen_layer)
		cam.get_viewport().add_child.call_deferred(_screen_layer)

	var under := is_point_underwater(cam.global_position)
	_fog_quad.visible = under
	_screen_layer.visible = under


## True when `point` is inside the water's footprint and below its (wavy) surface.
func is_point_underwater(point: Vector3) -> bool:
	var local := to_local(point)
	var box := mesh.get_aabb()
	if local.x < box.position.x or local.x > box.end.x or local.z < box.position.z or local.z > box.end.z:
		return false
	var surface := get_active_material(0) as ShaderMaterial
	var height := 0.06
	var speed := 1.0
	if surface: # unset parameters read back as null, so keep the shader defaults then
		var h = surface.get_shader_parameter("wave_height")
		var s = surface.get_shader_parameter("wave_speed")
		height = h if h != null else height
		speed = s if s != null else speed
	var t := Time.get_ticks_msec() / 1000.0 * speed
	return point.y < global_position.y + _wave(Vector2(point.x, point.z), t) * height


# Same as wave() in water_surface.gdshader.
func _wave(p: Vector2, t: float) -> float:
	return sin(p.dot(Vector2(0.8, 0.6)) * 1.3 + t * 1.1) * 0.5 \
		+ sin(p.dot(Vector2(-0.5, 0.9)) * 2.1 + t * 1.7) * 0.3 \
		+ sin(p.dot(Vector2(0.2, -1.0)) * 3.3 + t * 2.3) * 0.2


func _find_camera() -> Camera3D:
	for node in get_tree().root.find_children("*", "Camera3D", true, false):
		var c := node as Camera3D
		if c.is_current():
			return c
	return null


func _exit_tree() -> void:
	# The effect nodes live under the camera, so hide them when the water leaves.
	for node in [_fog_quad, _screen_layer]:
		if is_instance_valid(node):
			node.visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for node in [_fog_quad, _screen_layer]:
			if is_instance_valid(node):
				if node.is_inside_tree():
					node.queue_free()
				else:
					node.free()
