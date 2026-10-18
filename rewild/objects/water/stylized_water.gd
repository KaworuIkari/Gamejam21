## A body of stylized water. Drop stylized_water.tscn into a level, scale/move it over a
## dip in the terrain, and point `camera` at the player camera. When that camera goes
## below the surface it switches on underwater fog, tint, wobble and light shafts.
class_name StylizedWater
extends MeshInstance3D

const FOG_SHADER := preload("res://shaders/water/underwater_fog.gdshader")
const SCREEN_SHADER := preload("res://shaders/water/underwater_screen.gdshader")

## The camera that can dive. Leave empty to use the first active camera found.
@export var camera: Camera3D
@export var underwater_fog_color := Color(0.10, 0.42, 0.58)
@export var underwater_fog_density := 0.08
## Other water bodies (e.g. an inland lake) this surface is not drawn under, so each keeps
## its own level. The hole is the other water's basin if it uses fit_to_basin, otherwise
## its whole footprint. Keep those unrotated. Max 4.
@export var cutouts: Array[StylizedWater] = []
## Only draw this water over the dip it sits in: ground below its surface that is connected
## to the low spot nearest its centre, traced from the terrain when the game starts. Water
## listing this one in `cutouts` then cuts out exactly that shape. Keep it unrotated.
@export var fit_to_basin := false
## Metres per pixel of the traced shape. Smaller = closer fit, slower to build.
@export var basin_resolution := 1.0
## Leave empty to use the first Terrain3D in the scene.
@export var terrain: Terrain3D

## Water surface height the basin is traced at. Defaults to the placed height; a
## WaterFlowSwitch that lowers this water at start sets it to the full height first.
var full_level := NAN
## The traced shape (white = water) once built, else null.
var basin_mask: ImageTexture

var _basin_image: Image
var _basin_rect := Vector4.ZERO
var _cut_masks: Array = [null, null, null, null]

var _fog_quad: MeshInstance3D
var _screen_layer: CanvasLayer


func _ready() -> void:
	add_to_group(&"water_surfaces")
	print(name, " is ready")
	if is_nan(full_level):
		full_level = global_position.y
	if fit_to_basin or not cutouts.is_empty():
		# Masks are per water body, so stop sharing the scene's material.
		var mat := get_active_material(0)
		if mat:
			set_surface_override_material(0, mat.duplicate())
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
	if fit_to_basin and basin_mask == null:
		_build_basin()
	_update_cutouts()
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

	# Hidden water (e.g. not switched on yet by WaterFlowSwitch) can't be dived into.
	var under := is_point_underwater(cam.global_position)
	_fog_quad.visible = under
	_screen_layer.visible = under


## True when `point` is inside the water's footprint and below its (wavy) surface.
func is_point_underwater(point: Vector3) -> bool:
	if not holds_point(point):
		return false
	if not covers(point):
		return false
	for w in cutouts:
		if is_instance_valid(w) and w.covers(point):
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


## True when `point` is inside this water's footprint (its basin, if traced), at any height.
func covers(point: Vector3) -> bool:
	var r := _footprint()
	if absf(point.x - r.x) >= r.z or absf(point.z - r.y) >= r.w:
		return false
	if _basin_image == null:
		return true
	var u := (point.x - r.x) / (2.0 * r.z) + 0.5
	var v := (point.z - r.y) / (2.0 * r.w) + 0.5
	var px := clampi(int(u * _basin_image.get_width()), 0, _basin_image.get_width() - 1)
	var py := clampi(int(v * _basin_image.get_height()), 0, _basin_image.get_height() - 1)
	return _basin_image.get_pixel(px, py).r > 0.5


## Traces the basin: every pixel of the footprint whose ground is below full_level and
## connected to the low pixel nearest the centre, grown a little so the water tucks
## under the shore instead of stopping short of it.
func _build_basin() -> void:
	var t := _get_terrain()
	if t == null:
		return
	var r := _footprint()
	var w := clampi(ceili(r.z * 2.0 / basin_resolution), 2, 1024)
	var h := clampi(ceili(r.w * 2.0 / basin_resolution), 2, 1024)
	var cell := Vector2(r.z * 2.0 / w, r.w * 2.0 / h)
	var origin := Vector2(r.x - r.z, r.y - r.w)
	var low := PackedByteArray()
	low.resize(w * h)
	var seed := -1
	var seed_d := INF
	var centre := Vector2(r.x, r.y)
	for y in h:
		for x in w:
			var p := origin + Vector2(x + 0.5, y + 0.5) * cell
			var gh: float = t.data.get_height(Vector3(p.x, 0.0, p.y))
			if is_nan(gh) or gh >= full_level:
				continue
			low[y * w + x] = 1
			var d := p.distance_squared_to(centre)
			if d < seed_d:
				seed_d = d
				seed = y * w + x
	var fill := PackedByteArray()
	fill.resize(w * h)
	if seed >= 0:
		var stack := PackedInt32Array([seed])
		fill[seed] = 255
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var x := i % w
			for n in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w, i + w]:
				if n >= 0 and n < w * h and low[n] == 1 and fill[n] == 0:
					fill[n] = 255
					stack.append(n)
	for pass_i in 2: # grow by two pixels
		var src := fill.duplicate()
		for i in w * h:
			if src[i] == 0:
				var x := i % w
				if (x > 0 and src[i - 1]) or (x < w - 1 and src[i + 1]) \
						or (i >= w and src[i - w]) or (i < w * (h - 1) and src[i + w]):
					fill[i] = 255
	_basin_image = Image.create_from_data(w, h, false, Image.FORMAT_L8, fill)
	basin_mask = ImageTexture.create_from_image(_basin_image)
	_basin_rect = r
	var surface := get_active_material(0) as ShaderMaterial
	if surface:
		surface.set_shader_parameter("use_basin_mask", true)
		surface.set_shader_parameter("basin_mask", basin_mask)
	set_instance_shader_parameter("basin_rect", r)


func _get_terrain() -> Terrain3D:
	if terrain == null or not is_instance_valid(terrain):
		var found := get_tree().root.find_children("*", "Terrain3D", true, false)
		terrain = found[0] if not found.is_empty() else null
	return terrain if terrain and terrain.data else null


## World XZ footprint as (centre x, centre z, half width, half depth).
func _footprint() -> Vector4:
	var box := global_transform * mesh.get_aabb()
	var c := box.get_center()
	return Vector4(c.x, c.z, box.size.x * 0.5, box.size.z * 0.5)


func _update_cutouts() -> void:
	for i in 4:
		var w: StylizedWater = cutouts[i] if i < cutouts.size() else null
		var v := w._footprint() if is_instance_valid(w) else Vector4.ZERO
		set_instance_shader_parameter("cutout_%d" % i, v)
		var m: Texture2D = w.basin_mask if is_instance_valid(w) else null
		if m != _cut_masks[i]:
			_cut_masks[i] = m
			var surface := get_active_material(0) as ShaderMaterial
			if surface:
				surface.set_shader_parameter("cutout_mask_%d" % i, m)


# Same as wave() in water_surface.gdshader.
func _wave(p: Vector2, t: float) -> float:
	return sin(p.dot(Vector2(0.8, 0.6)) * 1.3 + t * 1.1) * 0.5 \
		+ sin(p.dot(Vector2(-0.5, 0.9)) * 2.1 + t * 1.7) * 0.3 \
		+ sin(p.dot(Vector2(0.2, -1.0)) * 3.3 + t * 2.3) * 0.2


func _find_camera() -> Camera3D:
	for node in get_tree().root.find_children("*", "Camera3D", true, false):
		var c := node as Camera3D
		# Skip cameras made in code (no owner), such as Terrain3D's MouseCamera: it sits at the
		# origin, often below the water, and shares this world, so its fog would cover every view.
		if c.is_current() and c.owner != null:
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

func get_surface_y() -> float:
	return global_position.y

## True when the point is in this water's basin (or footprint) and not inside a cutout.
func holds_point(point: Vector3) -> bool:
	if not covers(point):
		return false
	for w in cutouts:
		if is_instance_valid(w) and w.covers(point):
			return false
	return true
