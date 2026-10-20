extends MeshInstance3D
## One patch of standing water: a square grid of water depths over the terrain.
## Made and fed by the Puddles autoload; frees itself once it has dried up.
##
## Each physics frame the water flows to lower neighbours (ground + water height),
## so it runs off slopes and levels out in dips. A few times a second the wet cells
## are grouped into connected bodies; a body whose deepest cell is below
## settings.keep_depth evaporates fast (a film), a deeper one slowly (a pool).

const CALM_STEP := 0.25        # seconds between steps once the water stopped moving
const LABEL_INTERVAL := 0.25   # seconds between regrouping the water into bodies
const WET := 0.002             # metres: thinner water doesn't join bodies
const WALL := 10000.0          # ground height of cells outside the terrain

var settings: Node             # the Puddles autoload (tuning lives there)

var n := 64
var cell := 0.35
var origin := Vector2.ZERO     # world XZ of cell (0, 0)'s centre
var ground := PackedFloat32Array()
var depth := PackedFloat32Array()
var _delta := PackedFloat32Array()
var _evap := PackedFloat32Array()  # metres per second, per cell
var _label := PackedInt32Array()
var _rect := Rect2i()          # cells that hold water
var _calm := 0                 # physics frames in a row with (almost) no flow
var _calm_time := 0.0
var _label_time := 0.0
var _green_time := 0.0
var _ground_img: Image
var _depth_img: Image
var _depth_tex: ImageTexture


func setup(terrain: Terrain3D, world_pos: Vector3) -> void:
	n = settings.cells
	cell = settings.cell_size
	# Snap to the cell grid, so neighbouring puddles' cells line up.
	var c := (Vector2(world_pos.x, world_pos.z) / cell).floor() * cell
	origin = c - Vector2.ONE * (n / 2) * cell
	ground.resize(n * n)
	depth.resize(n * n)
	_delta.resize(n * n)
	_evap.resize(n * n)
	_label.resize(n * n)
	var shown := PackedFloat32Array()  # ground for the shader: no walls, so no spikes
	shown.resize(n * n)
	var data := terrain.data
	var lo := INF
	var hi := -INF
	for y in n:
		for x in n:
			var i := y * n + x
			var h := data.get_height(Vector3(origin.x + x * cell, 0.0, origin.y + y * cell))
			if is_nan(h):
				ground[i] = WALL
				shown[i] = world_pos.y
				continue
			ground[i] = h
			shown[i] = h
			lo = minf(lo, h)
			hi = maxf(hi, h)
	if lo > hi:
		lo = world_pos.y
		hi = world_pos.y

	# Vertices sit on cell centres; the shader lifts each one to its water surface.
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (n - 1) * cell
	plane.subdivide_width = n - 2
	plane.subdivide_depth = n - 2
	mesh = plane
	global_position = Vector3(origin.x + (n - 1) * cell * 0.5, 0.0, origin.y + (n - 1) * cell * 0.5)
	var half := (n - 1) * cell * 0.5
	custom_aabb = AABB(Vector3(-half, lo - 1.0, -half), Vector3(half * 2.0, hi - lo + 3.0, half * 2.0))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_ground_img = Image.create_from_data(n, n, false, Image.FORMAT_RF, shown.to_byte_array())
	_depth_img = Image.create_from_data(n, n, false, Image.FORMAT_RF, depth.to_byte_array())
	_depth_tex = ImageTexture.create_from_image(_depth_img)
	# Textures are per puddle, so each one needs its own copy of the material.
	var mat := material_override.duplicate() as ShaderMaterial
	mat.set_shader_parameter("ground_map", ImageTexture.create_from_image(_ground_img))
	mat.set_shader_parameter("depth_map", _depth_tex)
	mat.set_shader_parameter("half_extent", half)
	mat.set_shader_parameter("cell_size", cell)
	material_override = mat


## True if the world position lies on this grid, at least `margin` cells inside its edge.
func contains(world_pos: Vector3, margin: int) -> bool:
	var p := _to_cell(world_pos)
	return p.x >= margin and p.y >= margin and p.x < n - margin and p.y < n - margin


func depth_at(world_pos: Vector3) -> float:
	var p := _to_cell(world_pos)
	if p.x < 0 or p.y < 0 or p.x >= n or p.y >= n:
		return 0.0
	return depth[p.y * n + p.x]


## Adds `volume` cubic metres of water in a soft disc of `radius` metres.
func pour(world_pos: Vector3, volume: float, radius: float) -> void:
	var c := (Vector2(world_pos.x, world_pos.z) - origin) / cell
	var r := maxf(radius / cell, 1.0)
	var area := Rect2i(int(c.x - r), int(c.y - r), int(r * 2.0) + 2, int(r * 2.0) + 2) \
			.intersection(Rect2i(1, 1, n - 2, n - 2))
	var weights := PackedFloat32Array()
	var total := 0.0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var d := Vector2(x, y).distance_to(c) / r
			var w := maxf(0.0, 1.0 - d * d) if ground[y * n + x] < WALL else 0.0
			weights.append(w)
			total += w
	if total <= 0.0:
		return
	var k := volume / (total * cell * cell)
	var j := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			depth[y * n + x] += weights[j] * k
			j += 1
	_rect = area if not _rect.has_area() else _rect.merge(area)
	_calm = 0
	_label_time = LABEL_INTERVAL  # regroup on the next step: this may have made a pool
	_upload()


func _physics_process(delta: float) -> void:
	if not _rect.has_area():
		queue_free()
		return
	# Settled water only evaporates, so it doesn't need stepping every frame.
	if _calm > 30:
		_calm_time += delta
		if _calm_time < CALM_STEP:
			return
		delta = _calm_time
	_calm_time = 0.0

	var moved := 0.0
	if _calm <= 30:
		for s in settings.substeps:
			moved = maxf(moved, _flow())
	_calm = _calm + 1 if moved < 0.00002 else 0
	_label_time += delta
	if _label_time >= LABEL_INTERVAL:
		_label_time = 0.0
		_group_bodies()
	_evaporate(delta)
	_green_time += delta
	if _green_time >= settings.green_interval:
		_green_time = 0.0
		_moisten_ground()
	_upload()


## One flow substep over the wet area. Returns the most water any cell lost (metres).
func _flow() -> float:
	var k: float = settings.flow
	var r := _rect.grow(1).intersection(Rect2i(1, 1, n - 2, n - 2))
	var most := 0.0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i := y * n + x
			var d := depth[i]
			if d <= 0.0:
				continue
			var h := ground[i] + d
			# How far this cell's surface is above each neighbour's.
			var a := maxf(0.0, h - ground[i - 1] - depth[i - 1])
			var b := maxf(0.0, h - ground[i + 1] - depth[i + 1])
			var c := maxf(0.0, h - ground[i - n] - depth[i - n])
			var e := maxf(0.0, h - ground[i + n] - depth[i + n])
			var s := a + b + c + e
			if s <= 0.0:
				continue
			var move := minf(d, s * k)
			var f := move / s
			_delta[i] -= move
			_delta[i - 1] += a * f
			_delta[i + 1] += b * f
			_delta[i - n] += c * f
			_delta[i + n] += e * f
			most = maxf(most, move)
	# Apply, and track which cells still hold water. Water reaching the grid's edge runs off.
	var x0 := n
	var y0 := n
	var x1 := -1
	var y1 := -1
	var g := r.grow(1).intersection(Rect2i(0, 0, n, n))
	for y in range(g.position.y, g.end.y):
		for x in range(g.position.x, g.end.x):
			var i := y * n + x
			var d := depth[i] + _delta[i]
			_delta[i] = 0.0
			if x == 0 or y == 0 or x == n - 1 or y == n - 1 or d < 0.00005:
				d = 0.0
			depth[i] = d
			if d > 0.0:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	_rect = Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1) if x1 >= 0 else Rect2i()
	return most


## Groups wet cells into connected bodies and gives each body's cells its evaporation
## rate: fast if the body is nowhere deeper than keep_depth, slow if it is a real pool.
func _group_bodies() -> void:
	var keep: float = settings.keep_depth
	var film: float = settings.film_evaporation
	var pool: float = settings.pool_evaporation
	var r := _rect
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_label[y * n + x] = 0
	var next := 1
	var stack := PackedInt32Array()
	var body := PackedInt32Array()
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var start := y * n + x
			if _label[start] != 0:
				continue
			if depth[start] < WET:
				_evap[start] = film
				continue
			# Flood fill one body, remembering its deepest cell.
			body.clear()
			stack.append(start)
			_label[start] = next
			var deepest := 0.0
			while not stack.is_empty():
				var i := stack[stack.size() - 1]
				stack.remove_at(stack.size() - 1)
				body.append(i)
				deepest = maxf(deepest, depth[i])
				for j in [i - 1, i + 1, i - n, i + n]:
					if _label[j] == 0 and depth[j] >= WET and r.has_point(Vector2i(j % n, j / n)):
						_label[j] = next
						stack.append(j)
			var rate := lerpf(film, pool, smoothstep(keep * 0.6, keep, deepest))
			for i in body:
				_evap[i] = rate
			next += 1


## Tells the GrowthMap where the water is now. Many cells share one growth pixel;
## the deepest one decides how wet that pixel gets.
func _moisten_ground() -> void:
	if not settings.green_ground:
		return
	var growth := get_node_or_null(^"/root/GrowthMap")
	if growth == null:
		return
	var full: float = maxf(settings.green_full_depth, 0.0001)
	var wet := {}
	var res: int = growth.RES
	for y in range(_rect.position.y, _rect.end.y):
		for x in range(_rect.position.x, _rect.end.x):
			var d := depth[y * n + x]
			if d < WET:
				continue
			var p: Vector2 = growth.world_to_px(Vector3(origin.x + x * cell, 0.0, origin.y + y * cell))
			if p.x < 0.0 or p.y < 0.0 or p.x >= res or p.y >= res:
				continue
			var i := int(p.y) * res + int(p.x)
			var v := int(clampf(d / full, 0.35, 1.0) * 255.0)
			if v > int(wet.get(i, 0)):
				wet[i] = v
	if not wet.is_empty():
		growth.moisten(wet)


func _evaporate(dt: float) -> void:
	var r := _rect
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i := y * n + x
			if depth[i] > 0.0:
				depth[i] = maxf(0.0, depth[i] - _evap[i] * dt)
	if _calm > 30:
		_shrink_rect()


func _shrink_rect() -> void:
	var x0 := n
	var y0 := n
	var x1 := -1
	var y1 := -1
	for y in range(_rect.position.y, _rect.end.y):
		for x in range(_rect.position.x, _rect.end.x):
			if depth[y * n + x] > 0.0:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	_rect = Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1) if x1 >= 0 else Rect2i()


func _upload() -> void:
	_depth_img.set_data(n, n, false, Image.FORMAT_RF, depth.to_byte_array())
	_depth_tex.update(_depth_img)


func _to_cell(world_pos: Vector3) -> Vector2i:
	return Vector2i(((Vector2(world_pos.x, world_pos.z) - origin) / cell).round())
