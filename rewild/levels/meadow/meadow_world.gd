@tool
class_name MeadowWorld extends Node3D
## Builds a Ghibli-style meadow at load time: rolling hills with ponds and a
## dirt path, GPU grass and flowers that follow the camera, a mountain ring,
## water and a few props. Everything is regenerated from the exported
## settings, so tweak them and press "Rebuild" in the inspector.
## Coordinates in the exports (ponds, stream, path) are relative to this node,
## so move the node to place the whole meadow anywhere.

const GROUND_SHADER := preload("res://shaders/terrain/ground.gdshader")
const GRASS_SHADER := preload("res://shaders/foliage/grass.gdshader")
const FLOWER_SHADER := preload("res://shaders/foliage/flower.gdshader")
const WATER_SHADER := preload("res://shaders/water/water.gdshader")
const MOUNTAIN_SHADER := preload("res://shaders/terrain/mountain.gdshader")
const CLOUD_SHADER := preload("res://shaders/sky/cloud_bank.gdshader")

const TREES := [
	"res://assets/models/stylized_nature/CommonTree_1.gltf",
	"res://assets/models/stylized_nature/CommonTree_2.gltf",
	"res://assets/models/stylized_nature/CommonTree_3.gltf",
	"res://assets/models/stylized_nature/CommonTree_4.gltf",
]
const BUSHES := [
	"res://assets/models/stylized_nature/Bush_Common.gltf",
	"res://assets/models/stylized_nature/Bush_Common_Flowers.gltf",
]
const DEAD_TREES := [
	"res://assets/models/stylized_nature/DeadTree_1.gltf",
	"res://assets/models/stylized_nature/DeadTree_2.gltf",
	"res://assets/models/stylized_nature/DeadTree_3.gltf",
	"res://assets/models/stylized_nature/DeadTree_4.gltf",
	"res://assets/models/stylized_nature/DeadTree_5.gltf",
]
const SLABS := [
	"res://assets/models/stylized_nature/RockPath_Square_Wide.gltf",
	"res://assets/models/stylized_nature/RockPath_Square_Thin.gltf",
	"res://assets/models/stylized_nature/RockPath_Round_Wide.gltf",
]
const ROCKS := [
	"res://assets/models/stylized_nature/Rock_Medium_1.gltf",
	"res://assets/models/stylized_nature/Rock_Medium_2.gltf",
	"res://assets/models/stylized_nature/Rock_Medium_3.gltf",
]

@export_tool_button("Rebuild") var rebuild_button = rebuild
@export var world_seed: int = 7

@export_group("Terrain")
@export var terrain_size: float = 1024.0
@export var resolution: int = 512 ## quads per side
@export var hill_height: float = 9.0
@export var rim_height: float = 70.0
@export var water_level: float = 0.0
## x, z, radius of each pond (world units).
@export var ponds: Array[Vector3] = [
	Vector3(10, -55, 14), Vector3(34, -66, 11), Vector3(58, -58, 16),
	Vector3(82, -70, 10), Vector3(-6, -72, 8),
]
## Meandering stream linking the ponds (polyline on the xz plane).
@export var stream_points: PackedVector2Array = [
	Vector2(-40, -95), Vector2(-6, -72), Vector2(10, -55), Vector2(34, -66),
	Vector2(58, -58), Vector2(82, -70), Vector2(130, -62), Vector2(170, -85),
]
@export var stream_width: float = 4.5
## Dirt path as a polyline on the xz plane.
@export var path_points: PackedVector2Array = [
	Vector2(-6, 120), Vector2(-14, 70), Vector2(-26, 30), Vector2(-22, -5),
	Vector2(-34, -40), Vector2(-48, -70), Vector2(-50, -110),
]
@export var path_width: float = 1.8

@export_group("Grass")
@export var grass_radius: float = 36.0 ## raise for high cameras (costs more blades)
@export var grass_spacing: float = 0.2
@export var flower_radius: float = 30.0
@export var flower_spacing: float = 0.3

@export_group("Clouds")
@export var cloud_count: int = 22
@export var cloud_distance := Vector2(340, 760) ## min/max distance from the centre

@export_group("Props")
@export var bush_count: int = 70
@export var rock_count: int = 40
@export var lone_tree_count: int = 14
@export var dead_tree_count: int = 0
@export var ruin_count: int = 0 ## clusters of broken stone slabs

@export_group("Growth")
## Drive the ground, grass, flowers and props from the GrowthMap autoload:
## barren desert where growth is 0, meadow where it is 1. Living props
## (trees, bushes) grow in, dead trees, ruins and rocks get moss.
@export var use_growth_map := false

## Shared material of the cloud banks, so a stage director can recolour them.
var cloud_material: ShaderMaterial
var water: MeshInstance3D

var heights := PackedFloat32Array()
var path_mask := PackedFloat32Array()
var heightmap_texture: ImageTexture

var _generated: Node3D
var _grass: MultiMeshInstance3D
var _flowers: MultiMeshInstance3D
var _broad := FastNoiseLite.new()
var _roll := FastNoiseLite.new()
var _rim := FastNoiseLite.new()
var _warp := FastNoiseLite.new()


func _ready() -> void:
	rebuild()


func _process(_delta: float) -> void:
	var cam := _active_camera()
	if cam == null:
		return
	# Centre the patches on the ground the camera looks at, not under it, so a
	# high top-down camera still sees grass all the way across the screen.
	var p := cam.global_position
	var fwd := -cam.global_basis.z
	var flat := Vector2(fwd.x, fwd.z)
	if flat.length() > 0.01 and fwd.y < -0.05:
		var above := maxf(p.y - get_height(p.x, p.z), 0.0)
		var reach := minf(above / -fwd.y * flat.length(), grass_radius * 0.6)
		var ahead := flat.normalized() * reach
		p += Vector3(ahead.x, 0.0, ahead.y)
	if _grass:
		_grass.global_position = _snap(p, grass_spacing)
	if _flowers:
		_flowers.global_position = _snap(p, flower_spacing)


func rebuild() -> void:
	if _generated:
		_generated.queue_free()
	_generated = Node3D.new()
	_generated.name = "Generated"
	add_child(_generated)

	_setup_noise()
	_build_heights()
	_build_terrain()
	_build_water()
	_build_mountains()
	_build_clouds()
	_grass = _build_patch("Grass", GRASS_SHADER, _blade_mesh(), grass_radius, grass_spacing)
	_flowers = _build_patch("Flowers", FLOWER_SHADER, _quad_mesh(), flower_radius, flower_spacing)
	_build_props()


## Height of the generated ground at a world xz position (bilinear).
func get_height(x: float, z: float) -> float:
	return _height_local(x - global_position.x, z - global_position.z) + global_position.y


func _height_local(x: float, z: float) -> float:
	var n := resolution + 1
	var step := terrain_size / resolution
	var fx := clampf((x + terrain_size * 0.5) / step, 0.0, resolution - 0.001)
	var fz := clampf((z + terrain_size * 0.5) / step, 0.0, resolution - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := lerpf(heights[iz * n + ix], heights[iz * n + ix + 1], tx)
	var b := lerpf(heights[(iz + 1) * n + ix], heights[(iz + 1) * n + ix + 1], tx)
	return lerpf(a, b, tz)


func get_path_mask(x: float, z: float) -> float:
	return _path_local(x - global_position.x, z - global_position.z)


func _path_local(x: float, z: float) -> float:
	var n := resolution + 1
	var step := terrain_size / resolution
	var ix := clampi(roundi((x + terrain_size * 0.5) / step), 0, resolution)
	var iz := clampi(roundi((z + terrain_size * 0.5) / step), 0, resolution)
	return path_mask[iz * n + ix]


func _setup_noise() -> void:
	_broad.seed = world_seed
	_broad.frequency = 0.004
	_broad.fractal_octaves = 2
	_roll.seed = world_seed + 1
	_roll.frequency = 0.013
	_roll.fractal_octaves = 3
	_rim.seed = world_seed + 2
	_rim.frequency = 0.006
	_warp.seed = world_seed + 3
	_warp.frequency = 0.035


func _height_at(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var h := _broad.get_noise_2d(x, z) * hill_height + _roll.get_noise_2d(x, z) * hill_height * 0.35
	# Keep the central meadow gentle and above the water.
	var calm := 1.0 - smoothstep(70.0, 180.0, r)
	h = lerpf(h, h * 0.45, calm) + 3.0
	# Hills that rise toward the edge frame the meadow like a bowl.
	h += pow(smoothstep(170.0, 500.0, r), 1.6) * rim_height * (0.65 + 0.35 * _rim.get_noise_2d(x, z))
	for pond in ponds:
		var d := Vector2(x - pond.x, z - pond.y).length() + _warp.get_noise_2d(x, z) * pond.z * 0.35
		var m := smoothstep(pond.z, pond.z * 0.35, d)
		h = minf(h, lerpf(h, water_level - 1.6, m))
	return h


func _build_heights() -> void:
	var n := resolution + 1
	var step := terrain_size / resolution
	var half := terrain_size * 0.5
	heights.resize(n * n)
	path_mask.resize(n * n)
	path_mask.fill(0.0)
	for iz in n:
		var z := iz * step - half
		for ix in n:
			heights[iz * n + ix] = _height_at(ix * step - half, z)

	# Stream: carve a channel of varying width below the water line.
	_for_polyline_cells(stream_points, stream_width * 2.5, func(i: int, p: Vector2, d: float) -> void:
		var w := stream_width * (0.6 + 0.8 * (_rim.get_noise_2d(p.x * 6.0, p.y * 6.0) * 0.5 + 0.5))
		d += _warp.get_noise_2d(p.x, p.y) * w * 0.5
		var m := smoothstep(w, w * 0.3, d)
		heights[i] = minf(heights[i], lerpf(heights[i], water_level - 1.2, m)))

	# Path: soft mask from the distance to the polyline.
	_for_polyline_cells(path_points, path_width * 2.0, func(i: int, p: Vector2, d: float) -> void:
		d += _warp.get_noise_2d(p.x * 3.0, p.y * 3.0) * 0.5
		path_mask[i] = maxf(path_mask[i], smoothstep(path_width, path_width * 0.4, d)))

	var data := PackedFloat32Array()
	data.resize(n * n * 2)
	for i in n * n:
		data[i * 2] = heights[i]
		data[i * 2 + 1] = path_mask[i]
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RGF, data.to_byte_array())
	heightmap_texture = ImageTexture.create_from_image(img)


## Calls fn(index, world_xz, distance) for every grid cell within reach of the polyline.
func _for_polyline_cells(points: PackedVector2Array, reach: float, fn: Callable) -> void:
	var n := resolution + 1
	var step := terrain_size / resolution
	var half := terrain_size * 0.5
	for s in points.size() - 1:
		var a := points[s]
		var b := points[s + 1]
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * reach
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * reach
		for iz in range(clampi(int((lo.y + half) / step), 0, resolution), clampi(int((hi.y + half) / step) + 1, 0, n)):
			for ix in range(clampi(int((lo.x + half) / step), 0, resolution), clampi(int((hi.x + half) / step) + 1, 0, n)):
				var p := Vector2(ix * step - half, iz * step - half)
				var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
				if d < reach:
					fn.call(iz * n + ix, p, d)


func _common_params(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("heightmap", heightmap_texture)
	mat.set_shader_parameter("terrain_origin", Vector2(global_position.x, global_position.z) - Vector2.ONE * terrain_size * 0.5)
	mat.set_shader_parameter("terrain_size", terrain_size)
	mat.set_shader_parameter("heightmap_res", float(resolution + 1))
	mat.set_shader_parameter("water_level", water_level + global_position.y)
	var growth := _growth_map()
	if growth:
		mat.set_shader_parameter("growth_map", growth.texture)
		mat.set_shader_parameter("growth_origin", growth.MAP_ORIGIN)
		mat.set_shader_parameter("growth_size", growth.MAP_SIZE)


func _growth_map() -> Node:
	if not use_growth_map or not is_inside_tree():
		return null
	return get_node_or_null("/root/GrowthMap")


func _build_terrain() -> void:
	var n := resolution + 1
	var step := terrain_size / resolution
	var half := terrain_size * 0.5
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	verts.resize(n * n)
	normals.resize(n * n)
	for iz in n:
		for ix in n:
			var i := iz * n + ix
			verts[i] = Vector3(ix * step - half, heights[i], iz * step - half)
			var hl := heights[iz * n + maxi(ix - 1, 0)]
			var hr := heights[iz * n + mini(ix + 1, resolution)]
			var hd := heights[maxi(iz - 1, 0) * n + ix]
			var hu := heights[mini(iz + 1, resolution) * n + ix]
			normals[i] = Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
	indices.resize(resolution * resolution * 6)
	var k := 0
	for iz in resolution:
		for ix in resolution:
			var i := iz * n + ix
			indices[k] = i
			indices[k + 1] = i + 1
			indices[k + 2] = i + n
			indices[k + 3] = i + 1
			indices[k + 4] = i + n + 1
			indices[k + 5] = i + n
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	_common_params(mat)
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	mi.material_override = mat
	_generated.add_child(mi)

	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = heights
	var body := StaticBody3D.new()
	body.name = "GroundCollision"
	var col := CollisionShape3D.new()
	col.shape = shape
	col.scale = Vector3(step, 1.0, step)
	body.add_child(col)
	_generated.add_child(body)


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(420, 420)
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = plane
	mi.position = Vector3(0, water_level, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_generated.add_child(mi)
	water = mi


func _build_mountains() -> void:
	var seg := 640
	var rings := 90
	var r0 := 480.0
	var r1 := 1900.0
	var ridge := FastNoiseLite.new()
	ridge.seed = world_seed + 10
	ridge.frequency = 0.0022
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ri in rings + 1:
		var t := float(ri) / rings
		var r := lerpf(r0, r1, t * t)
		for si in seg + 1:
			var ang := TAU * si / seg
			var x := cos(ang) * r
			var z := sin(ang) * r
			var env := smoothstep(r0, 900.0, r) * (1.0 - smoothstep(1500.0, r1, r))
			# Tallest peaks behind the ponds (-z), lower ranges elsewhere.
			env *= 0.55 + 0.45 * maxf(-sin(ang), 0.0)
			var y := 30.0 + (ridge.get_noise_2d(x, z) * 0.5 + 0.5) * 340.0 * env
			st.set_uv(Vector2(si, ri))
			st.add_vertex(Vector3(x, y, z))
	for ri in rings:
		for si in seg:
			var i := ri * (seg + 1) + si
			st.add_index(i)
			st.add_index(i + seg + 1)
			st.add_index(i + 1)
			st.add_index(i + 1)
			st.add_index(i + seg + 1)
			st.add_index(i + seg + 2)
	st.generate_normals()
	var mat := ShaderMaterial.new()
	mat.shader = MOUNTAIN_SHADER
	var mi := MeshInstance3D.new()
	mi.name = "Mountains"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_generated.add_child(mi)


func _build_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 20
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.center_offset = Vector3(0, 0.5, 0) # pivot at the base
	var mat := ShaderMaterial.new()
	mat.shader = CLOUD_SHADER
	cloud_material = mat
	var clouds := Node3D.new()
	clouds.name = "Clouds"
	_generated.add_child(clouds)
	for i in cloud_count:
		var ang := TAU * (i + rng.randf_range(-0.3, 0.3)) / cloud_count
		var r := rng.randf_range(cloud_distance.x, cloud_distance.y)
		var w := rng.randf_range(140.0, 300.0)
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(cos(ang) * r, rng.randf_range(-5.0, 35.0) + r * 0.05, sin(ang) * r)
		mi.scale = Vector3(w, w * rng.randf_range(0.35, 0.55), 1.0)
		mi.set_instance_shader_parameter("seed", rng.randf() * 100.0)
		clouds.add_child(mi)


func _blade_mesh() -> ArrayMesh:
	# Tapered strip in [-0.5, 0.5] x [0, 1]; the shader scales and bends it.
	var segments := 3
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for s in segments + 1:
		var y := float(s) / segments
		var w := 0.5 * (1.0 - y * 0.85)
		verts.append(Vector3(-w, y, 0))
		verts.append(Vector3(w, y, 0))
		uvs.append(Vector2(0, 1.0 - y))
		uvs.append(Vector2(1, 1.0 - y))
	var indices := PackedInt32Array()
	for s in segments:
		var i := s * 2
		indices.append_array([i, i + 1, i + 2, i + 1, i + 3, i + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _quad_mesh() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	return q


func _build_patch(patch_name: String, shader: Shader, mesh: Mesh, radius: float, spacing: float) -> MultiMeshInstance3D:
	var per_side := int(ceil(radius * 2.0 / spacing))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = per_side * per_side
	var buf := PackedFloat32Array()
	buf.resize(per_side * per_side * 12)
	var k := 0
	for iz in per_side:
		for ix in per_side:
			# Basis is identity; only the translation column changes.
			buf[k] = 1.0
			buf[k + 3] = (ix - per_side / 2) * spacing
			buf[k + 5] = 1.0
			buf[k + 10] = 1.0
			buf[k + 11] = (iz - per_side / 2) * spacing
			k += 12
	mm.buffer = buf

	var mat := ShaderMaterial.new()
	mat.shader = shader
	_common_params(mat)
	mat.set_shader_parameter("spacing", spacing)
	mat.set_shader_parameter("fade_radius", radius)

	var mmi := MultiMeshInstance3D.new()
	mmi.name = patch_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Vertices are moved onto the terrain in the shader, so culling needs room.
	mmi.custom_aabb = AABB(Vector3(-radius, -200, -radius), Vector3(radius * 2, 600, radius * 2))
	_generated.add_child(mmi)
	return mmi


func _build_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var props := Node3D.new()
	props.name = "Props"
	_generated.add_child(props)

	var growing := use_growth_map
	# A small grove at the end of the path, like the spot by the mill.
	for i in 7:
		var p := Vector2(-62, -88) + Vector2(rng.randf_range(-14, 14), rng.randf_range(-10, 10))
		_place(props, TREES[rng.randi() % TREES.size()], p, rng.randf_range(0.9, 1.4), rng, 0.0, growing)
	for i in lone_tree_count:
		var p := _random_spot(rng, 60.0, 220.0)
		if p != Vector2.INF:
			_place(props, TREES[rng.randi() % TREES.size()], p, rng.randf_range(0.9, 1.5), rng, 0.0, growing)
	for i in bush_count:
		var p := _random_spot(rng, 8.0, 180.0)
		if p != Vector2.INF:
			_place(props, BUSHES[rng.randi() % BUSHES.size()], p, rng.randf_range(0.8, 1.6), rng, 0.0, growing)
	for i in dead_tree_count:
		var p := _random_spot(rng, 10.0, 200.0)
		if p != Vector2.INF:
			_place(props, DEAD_TREES[rng.randi() % DEAD_TREES.size()], p, rng.randf_range(1.0, 1.8), rng, -0.2, false, growing)
	# Ruins: a few broken slabs tilted and half sunk, like an old foundation.
	for i in ruin_count:
		var c := _random_spot(rng, 15.0, 160.0)
		if c == Vector2.INF:
			continue
		for j in rng.randi_range(4, 9):
			var p := c + Vector2(rng.randf_range(-7, 7), rng.randf_range(-7, 7))
			var slab := _place(props, SLABS[rng.randi() % SLABS.size()], p, rng.randf_range(2.5, 4.0), rng, -0.15, false, growing)
			if slab:
				slab.rotation.x = rng.randf_range(-0.08, 0.08)
				slab.rotation.z = rng.randf_range(-0.08, 0.08)
	# Rocks gather around the ponds and a few lie loose in the grass.
	for i in rock_count:
		var p: Vector2
		if i % 2 == 0:
			var pond: Vector3 = ponds[rng.randi() % ponds.size()]
			var a := rng.randf() * TAU
			p = Vector2(pond.x, pond.y) + Vector2(cos(a), sin(a)) * pond.z * rng.randf_range(0.9, 1.3)
		else:
			p = _random_spot(rng, 10.0, 160.0)
		if p != Vector2.INF and _height_local(p.x, p.y) > water_level - 0.3:
			_place(props, ROCKS[rng.randi() % ROCKS.size()], p, rng.randf_range(0.6, 1.8), rng, -0.3, false, growing)


func _random_spot(rng: RandomNumberGenerator, r_min: float, r_max: float) -> Vector2:
	for attempt in 12:
		var a := rng.randf() * TAU
		var p := Vector2(cos(a), sin(a)) * sqrt(rng.randf_range(r_min * r_min, r_max * r_max))
		if _height_local(p.x, p.y) > water_level + 0.8 and _path_local(p.x, p.y) < 0.05:
			return p
	return Vector2.INF


## grow_in / moss wrap the prop in a GrowthProp so it reacts to the GrowthMap.
func _place(parent: Node3D, path: String, p: Vector2, s: float, rng: RandomNumberGenerator,
		sink := 0.0, grow_in := false, moss := false) -> Node3D:
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var inst := scene.instantiate() as Node3D
	var holder: Node3D = inst
	if grow_in or moss:
		var gp := GrowthProp.new()
		gp.grow_in = grow_in
		gp.moss = moss
		gp.add_child(inst)
		holder = gp
	# Transform first: GrowthProp remembers its scale in _ready as the grown size.
	holder.position = Vector3(p.x, _height_local(p.x, p.y) + sink, p.y)
	holder.rotation.y = rng.randf() * TAU
	holder.scale = Vector3.ONE * s
	parent.add_child(holder)
	return holder


func _active_camera() -> Camera3D:
	if Engine.is_editor_hint():
		# Looked up dynamically so exported builds (no editor classes) still compile.
		var vp: SubViewport = Engine.get_singleton("EditorInterface").get_editor_viewport_3d(0)
		return vp.get_camera_3d() if vp else null
	return get_viewport().get_camera_3d()


func _snap(p: Vector3, spacing: float) -> Vector3:
	return Vector3(roundf(p.x / spacing) * spacing, 0.0, roundf(p.z / spacing) * spacing)
