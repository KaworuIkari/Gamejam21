extends Node
## Growth map over the crater: one byte per pixel, 0 = barren, 255 = fully green.
## Add as an autoload named "GrowthMap". The level calls attach_terrain() once.
##
## A second layer, the wet map, holds watering. Watering never turns ground green
## directly: water() only darkens the soil, then growth catches up over a few
## seconds wherever it is still wet, so a splash reads as damp sand -> sprouts ->
## meadow instead of an instant green stamp.

signal changed
## Emitted for every watering, so tasks and zones can count it.
signal watered(world_pos: Vector3, radius: float)
## Emitted when the restoration percentages (progress_total, progress_regions()) change.
signal progress_changed

const MAP_ORIGIN := Vector2(-512.0, -512.0)  # world XZ of the crater's corner
const MAP_SIZE := 1024.0               # crater size in world metres (not mask pixels)
const RES := 512                       # growth map pixels per side -> 2 m per pixel
const SAVE_PATH := "user://growth_map.png"

## Optional: where growth is allowed (0 = never, e.g. rock or water). RES x RES bytes.
var soil: PackedByteArray = PackedByteArray()

## Terrain3D texture slot that is green from the start: attach_terrain() reads where
## it is painted into the permanent layer (-1 = off). Must match the terrain shader's
## meadow_green_slot.
@export var always_green_slot := 9

var image: Image
var texture: ImageTexture
var wet_image: Image
var wet_texture: ImageTexture

@export_group("Watering")
## Seconds for fully wet ground to go from barren to full meadow (per-pixel speeds vary around this).
@export var grow_time := 3.5
## Seconds for fully wet ground to dry out completely.
@export var dry_time := 20.0
## Wet ground next to existing meadow greens this many times faster, so green creeps in from the edges.
@export var neighbour_boost := 2.0
## Simulation steps per second (cost scales with the wet area only).
@export var tick_rate := 15.0

@export_group("Hole filling")
## Ground whose surroundings are at least this green fills itself in, so nearly
## finished patches don't leave odd little dry specks. Straight or bulging edges
## sit near 50% and never qualify, so green only creeps into gaps and notches.
@export_range(0.5, 1.0) var fill_threshold := 0.7
## Size of the "surroundings" checked around each pixel, in metres.
@export var fill_radius := 8.0
## How wet a filling pixel gets (it then greens like watered ground, damp first).
@export_range(0.0, 1.0) var fill_wetness := 1.0
@export var fill_interval := 0.4

@export_group("Spreading")
## Green patches creep towards each other on their own. An edge moves at up to this
## many metres per second when other green is right in front of it, slower the
## further away that green is. GrowthSpreadRegion nodes override these per area.
@export var spread_speed := 0.3
## Green this close (metres) in front of a patch edge pulls the edge towards it.
@export var attract_distance := 16.0
## Share of spread_speed an edge keeps with no green in range (0 = lone patches stay put).
@export_range(0.0, 1.0) var lone_spread := 0.2
## Speed by growth phase: x = how green the patch is at the edge (0..1), y = speed
## multiplier. Default: sprouting patches barely creep, full meadow spreads at full speed.
@export var spread_by_growth: Curve
## Ground at least this green (0..255) counts as a patch: it spreads and attracts.
@export_range(1, 255) var spread_min_source := 128
## Milliseconds per frame the spreading may use; it catches up over later frames.
@export var spread_budget_ms := 2.0

var _data := PackedByteArray()
var _base := PackedByteArray()  # permanent green (painted slot, GrowthSeeds); clear() returns here
var _wet := PackedByteArray()
var _wet_dirty := false
var _active := PackedInt32Array()   # pixels that are still wet
var _is_active := PackedByteArray()  # 1 if the pixel is in _active
var _tick := 0.0
var _fill_timer := 0.0
var _changed_rect := Rect2i()  # pixels whose growth changed since the last hole-fill pass
var _dirty := false
var _spreading := false
var _noise := FastNoiseLite.new()

const TILE := 16                       # spreading works on tiles of TILE x TILE pixels
const TILES := RES / TILE
const PIXEL_M := MAP_SIZE / RES        # metres per pixel
const DIR_X := [1, -1, 0, 0, 1, 1, -1, -1]
const DIR_Y := [0, 0, 1, -1, 1, -1, 1, -1]
var _tile_active := PackedByteArray()  # 1 if the tile is in _tile_queue
var _tile_queue := PackedInt32Array()  # tiles that have (or may have) moving edges
var _tile_time := PackedFloat32Array() # _clock when the tile was last stepped
var _queue_pos := 0
var _clock := 0.0
var _spread_regions: Array[Node] = []
var _region_of := PackedByteArray()    # per pixel: 0 = map defaults, k = _spread_regions[k - 1]
var _regions_dirty := false
# Per region index (0 = defaults): speed, attraction reach in pixels, lone share, phase table.
var _p_speed := PackedFloat32Array()
var _p_reach := PackedInt32Array()
var _p_lone := PackedFloat32Array()
var _p_lut: Array[PackedFloat32Array] = []
var _lut_cache := {}                   # Curve -> PackedFloat32Array

@export_group("Restoration progress")
## Ground below this terrain height (sea, lake beds) doesn't count towards the percentages.
@export var land_min_height := 20.0
## Seconds between measurements while the ground is changing.
@export var progress_interval := 1.0

## Share of all land that is green, 0..1.
var progress_total := 0.0
var _progress_regions: Array[Node] = []      # GrowthRegion, in scene order
var _progress_values := PackedFloat32Array() # per region, 0..1
var _land := PackedByteArray()               # 1 = land (counts), filled by attach_terrain
var _count_idx := PackedInt32Array()         # sampled land pixels that count
var _count_region := PackedByteArray()       # per sample: 0 = no region, k = _progress_regions[k - 1]
var _progress_layout_dirty := true
var _progress_dirty := true
var _progress_timer := 0.0


func _ready() -> void:
	_data.resize(RES * RES)  # zero-filled: all barren
	_base.resize(RES * RES)
	image = Image.create_from_data(RES, RES, false, Image.FORMAT_R8, _data)
	texture = ImageTexture.create_from_image(image)
	_wet.resize(RES * RES)
	_is_active.resize(RES * RES)
	wet_image = Image.create_from_data(RES, RES, false, Image.FORMAT_R8, _wet)
	wet_texture = ImageTexture.create_from_image(wet_image)
	_noise.frequency = 0.08  # in pixels; lower = larger blobs
	_tile_active.resize(TILES * TILES)
	_tile_time.resize(TILES * TILES)
	_region_of.resize(RES * RES)
	if spread_by_growth == null:
		spread_by_growth = Curve.new()
		spread_by_growth.add_point(Vector2(0.5, 0.15))
		spread_by_growth.add_point(Vector2(0.75, 0.5))
		spread_by_growth.add_point(Vector2(1.0, 1.0))


func _process(delta: float) -> void:
	_clock += delta
	if _regions_dirty:
		_rebuild_regions()
	if not _tile_queue.is_empty():
		_spread_step()
	if not _active.is_empty():
		_tick += delta
		var step := 1.0 / tick_rate
		if _tick >= step:
			_simulate(_tick)
			_tick = 0.0
	if _changed_rect.has_area():
		_fill_timer += delta
		if _fill_timer >= fill_interval:
			_fill_timer = 0.0
			_fill_holes()
	if _wet_dirty:
		_wet_dirty = false
		wet_image.set_data(RES, RES, false, Image.FORMAT_R8, _wet)
		wet_texture.update(wet_image)
	if _dirty:  # upload at most once per frame, however many edits happened
		_dirty = false
		image.set_data(RES, RES, false, Image.FORMAT_R8, _data)
		texture.update(image)
		changed.emit()
		_progress_dirty = true
	_progress_timer += delta
	if (_progress_dirty or _progress_layout_dirty) and _progress_timer >= progress_interval:
		_progress_timer = 0.0
		_measure_progress()


func attach_terrain(terrain: Terrain3D) -> void:
	terrain.material.set_shader_param("growth_map", texture)
	terrain.material.set_shader_param("wet_map", wet_texture)
	if always_green_slot >= 0:
		seed_from_terrain(terrain, always_green_slot)
	_build_land(terrain)
	_wake_all()


# --- 0. Permanent green: ground that is green from the start ---------------------

## Makes everywhere `slot` is painted on the terrain permanently green.
func seed_from_terrain(terrain: Terrain3D, slot: int) -> void:
	var data := terrain.data
	if data == null:
		return
	var px := MAP_SIZE / RES
	for y in RES:
		for x in RES:
			var wp := Vector3(MAP_ORIGIN.x + (x + 0.5) * px, 0.0, MAP_ORIGIN.y + (y + 0.5) * px)
			if not data.has_regionp(wp):
				continue
			var c: int = data.get_control(wp)
			var blend := ((c >> 14) & 0xFF) / 255.0
			var w := (1.0 - blend if ((c >> 27) & 0x1F) == slot else 0.0) \
					+ (blend if ((c >> 22) & 0x1F) == slot else 0.0)
			if w > 0.0:
				_add_base(y * RES + x, int(w * 255.0))
	_dirty = true


## A permanently green blob (see GrowthSeed). Same soft, noisy rim as a bloom.
func seed_circle(world_pos: Vector3, radius: float) -> void:
	var c := world_to_px(world_pos)
	var r := maxf(radius / MAP_SIZE * RES, 0.5)
	for y in range(maxi(int(c.y - r - 1.0), 0), mini(int(c.y + r + 1.0), RES - 1) + 1):
		for x in range(maxi(int(c.x - r - 1.0), 0), mini(int(c.x + r + 1.0), RES - 1) + 1):
			var dn := Vector2(x + 0.5, y + 0.5).distance_to(c) / r + _noise.get_noise_2d(x, y) * 0.3
			if dn < 1.0:
				_add_base(y * RES + x, int(255.0 * (1.0 - smoothstep(0.6, 1.0, dn))))
	_wake_px(c, r)
	_dirty = true


func _add_base(i: int, v: int) -> void:
	_base[i] = maxi(_base[i], v)
	_data[i] = maxi(_data[i], _cap(i, v))


## For other shaders that read growth_map (grass, flowers...). The texture updates
## in place, so one call is enough.
func attach_material(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("growth_map", texture)
	mat.set_shader_parameter("wet_map", wet_texture)


# --- Coordinates ----------------------------------------------------------

func world_to_px(world_pos: Vector3) -> Vector2:
	return (Vector2(world_pos.x, world_pos.z) - MAP_ORIGIN) / MAP_SIZE * RES


## Growth at a world position, 0..1. Useful for gameplay (spawn animals where green).
func sample(world_pos: Vector3) -> float:
	var p := world_to_px(world_pos)
	var x := clampi(int(p.x), 0, RES - 1)
	var y := clampi(int(p.y), 0, RES - 1)
	return _data[y * RES + x] / 255.0


# --- 1. Story: reveal a painted mask (e.g. the lake area) -------------------

## mask: greyscale texture covering the whole crater, white = turns green.
## gain boosts faint masks; values below cutoff (after gain) are ignored as residue.
func reveal_mask(mask: Texture2D, duration: float = 4.0, gain: float = 5.0, cutoff: int = 10) -> void:
	var m := _to_map_image(mask.get_image())
	var mdata := m.get_data()

	# One-time pass: collect only the pixels that will change, with everything
	# the animation needs precomputed (start, target, noise delay).
	var idx := PackedInt32Array()
	var from := PackedByteArray()
	var to := PackedByteArray()
	var delay := PackedFloat32Array()
	for i in RES * RES:
		var v := mini(255, int(mdata[i] * gain))
		if v < cutoff or v <= _data[i]:  # faint residue, or already this green
			continue
		idx.append(i)
		from.append(_data[i])
		to.append(v)
		delay.append((_noise.get_noise_2d(i % RES, float(i) / RES) + 1.0) * 0.5)
	if idx.is_empty():
		return

	var tween := create_tween()
	tween.tween_method(_apply_mask.bind(idx, from, to, delay), 0.0, 1.0, duration)
	tween.finished.connect(_wake_all)


## Called every frame by the tween, t: 0 -> 1. Touches only the precomputed pixels.
func _apply_mask(t: float, idx: PackedInt32Array, from: PackedByteArray,
		to: PackedByteArray, delay: PackedFloat32Array) -> void:
	for k in idx.size():
		# Noise delay staggers the start per pixel, so it greens in patches.
		var local_t := clampf(t * 1.5 - delay[k] * 0.5, 0.0, 1.0)
		var i := idx[k]
		# max() so painting done during the reveal is never undone
		_data[i] = maxi(_data[i], _cap(i, int(lerpf(from[k], to[k], local_t))))
	_dirty = true


## Story: green spreads outward from a point, like a wave from the planted device.
## max_radius in metres (0 = the whole map). The rim of a limited bloom fades out softly.
## duration 0 applies the end state at once (e.g. when restoring a stage).
func reveal_from(world_pos: Vector3, duration: float = 6.0, max_radius: float = 0.0, ramp: float = 0.12) -> void:
	var c := world_to_px(world_pos)
	var r_px := max_radius / MAP_SIZE * RES if max_radius > 0.0 else RES * 1.45
	const BUCKETS := 64
	var buckets: Array[PackedInt32Array] = []
	buckets.resize(BUCKETS)
	var delay := PackedFloat32Array()
	var target := PackedByteArray()
	delay.resize(RES * RES)
	target.resize(RES * RES)
	for y in RES:
		for x in RES:
			var n := _noise.get_noise_2d(x, y)
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / r_px
			# A noisy rim so a limited bloom ends in an organic blob, not a circle.
			var dn := d + n * 0.3 if max_radius > 0.0 else d
			if dn >= 1.0:
				continue
			var i := y * RES + x
			var v := 255 if max_radius <= 0.0 else int(255.0 * (1.0 - smoothstep(0.6, 1.0, dn)))
			if v <= _data[i]:
				continue
			# Mostly distance (an expanding ring), broken up by noise.
			var dl := clampf(minf(dn, 1.0) * 0.85 + (n + 1.0) * 0.075, 0.0, 0.999)
			delay[i] = dl
			target[i] = v
			buckets[int(dl * BUCKETS)].append(i)

	if duration <= 0.0:
		for b in buckets:
			for i in b:
				_data[i] = maxi(_data[i], _cap(i, target[i]))
		_dirty = true
		_wake_all()
		return

	var state := {"done": 0}  # buckets below this index are finished
	var tween := create_tween()
	tween.tween_method(_apply_reveal.bind(buckets, delay, target, ramp, state), 0.0, 1.0, duration)
	tween.finished.connect(_wake_all)


func _apply_reveal(t: float, buckets: Array[PackedInt32Array], delay: PackedFloat32Array,
		target: PackedByteArray, ramp: float, state: Dictionary) -> void:
	# Only touch the band of pixels currently ramping up; finished buckets are skipped.
	var front := t * (1.0 + ramp)
	var n := buckets.size()
	var last := mini(int(front * n), n - 1)
	for b in range(state.done, last + 1):
		for i in buckets[b]:
			var k := clampf((front - delay[i]) / ramp, 0.0, 1.0)
			_data[i] = maxi(_data[i], _cap(i, int(target[i] * k)))
	while state.done < n and (state.done + 1.0) / n + ramp <= front:
		state.done += 1
	_dirty = true


# --- 2. Interaction: watering ----------------------------------------------

## The water gun's splash. Wets a noisy disc; growth follows over the next seconds.
## amount: how wet the centre gets (1 = soaked). Watering the same spot again adds up.
func water(world_pos: Vector3, radius: float, amount: float = 1.0, edge_noise: float = 0.35) -> void:
	_wet_disc(world_pos, radius, amount, edge_noise)
	watered.emit(world_pos, radius)


func _wet_disc(world_pos: Vector3, radius: float, amount: float, edge_noise: float) -> void:
	var c := world_to_px(world_pos)
	var r := maxf(radius / MAP_SIZE * RES, 0.5)
	var x0 := maxi(int(c.x - r - 1.0), 0)
	var y0 := maxi(int(c.y - r - 1.0), 0)
	var x1 := mini(int(c.x + r + 1.0), RES - 1)
	var y1 := mini(int(c.y + r + 1.0), RES - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / r
			d += _noise.get_noise_2d(x, y) * edge_noise
			var shape := 1.0 - smoothstep(0.2, 1.0, d)
			if shape <= 0.0:
				continue
			var i := y * RES + x
			_wet[i] = mini(255, _wet[i] + int(shape * amount * 255.0))
			_activate(i)
	_wet_dirty = true


func _activate(i: int) -> void:
	if _is_active[i] == 0:
		_is_active[i] = 1
		_active.append(i)


## Wet pixels grow green and slowly dry out. Only touches pixels that are wet.
func _simulate(dt: float) -> void:
	var grow := 255.0 * dt / grow_time
	var dry := maxi(1, int(255.0 * dt / dry_time))
	var still := PackedInt32Array()
	for i in _active:
		var w := _wet[i]
		var g := _data[i]
		if g < 255:
			# Per-pixel speed (0.35..1) so a splash fills in unevenly, not as one disc.
			var speed := 0.35 + 0.65 * float(((i * 2654435761) >> 11) & 255) / 255.0
			var x := i % RES
			if x > 0 and x < RES - 1 and i >= RES and i < RES * (RES - 1):
				var m := maxi(maxi(_data[i - 1], _data[i + 1]), maxi(_data[i - RES], _data[i + RES]))
				if m > 200:
					speed *= neighbour_boost
			# Accumulate fractional gains stochastically so slow pixels still move at low tick sizes.
			var gain := grow * speed * w / 255.0
			var whole := int(gain)
			if randf() < gain - whole:
				whole += 1
			if whole > 0:
				_data[i] = _cap(i, g + whole)
				_dirty = true
				_mark_changed(i)
		w = maxi(0, w - dry)
		_wet[i] = w
		if w > 0:
			still.append(i)
		else:
			_is_active[i] = 0
	_active = still
	_wet_dirty = true


func _mark_changed(i: int) -> void:
	var p := Vector2i(i % RES, i / RES)
	_wake_px(Vector2(p), 0.0)
	if _changed_rect.has_area():
		_changed_rect = _changed_rect.expand(p).expand(p + Vector2i.ONE)
	else:
		_changed_rect = Rect2i(p, Vector2i.ONE)


## Wets every pixel that is nearly surrounded by green, using a summed-area table
## over just the region that changed. Filled pixels change growth themselves, so
## the next pass looks again and gaps close from their rims inwards.
func _fill_holes() -> void:
	var r := maxi(1, int(fill_radius / MAP_SIZE * RES))
	var area := _changed_rect.grow(r).intersection(Rect2i(0, 0, RES, RES))
	_changed_rect = Rect2i()
	# Window sums need r more pixels on each side than the pixels we test.
	var outer := area.grow(r).intersection(Rect2i(0, 0, RES, RES))
	var w := outer.size.x
	var h := outer.size.y
	var has_soil := soil.size() == RES * RES
	# Integral images of growth and of countable (soil) pixels, (w+1) x (h+1).
	var sum := PackedInt32Array()
	var cnt := PackedInt32Array()
	sum.resize((w + 1) * (h + 1))
	cnt.resize((w + 1) * (h + 1))
	for y in h:
		var row_s := 0
		var row_c := 0
		var src := (outer.position.y + y) * RES + outer.position.x
		for x in w:
			var i := src + x
			if not has_soil or soil[i] > 0:
				row_s += 1 if _data[i] >= 96 else 0  # counts green pixels, not how green
				row_c += 1
			var k := (y + 1) * (w + 1) + x + 1
			sum[k] = sum[k - w - 1] + row_s
			cnt[k] = cnt[k - w - 1] + row_c
	var wet := int(fill_wetness * 255.0)
	var any := false
	for y in range(area.position.y, area.end.y):
		var y0 := maxi(y - r, outer.position.y) - outer.position.y
		var y1 := mini(y + r + 1, outer.end.y) - outer.position.y
		for x in range(area.position.x, area.end.x):
			var i := y * RES + x
			if _data[i] >= 230 or _wet[i] >= wet or (has_soil and soil[i] == 0):
				continue
			var x0 := maxi(x - r, outer.position.x) - outer.position.x
			var x1 := mini(x + r + 1, outer.end.x) - outer.position.x
			var a := y1 * (w + 1)
			var b := y0 * (w + 1)
			var n := cnt[a + x1] - cnt[a + x0] - cnt[b + x1] + cnt[b + x0]
			if n == 0:
				continue
			var s := sum[a + x1] - sum[a + x0] - sum[b + x1] + sum[b + x0]
			if s >= fill_threshold * n:
				_wet[i] = wet
				_activate(i)
				any = true
	if any:
		_wet_dirty = true


# --- 2b. Story: scattered green patches -----------------------------------------

## Sprinkles patches of green over the world, e.g. when the lake terminal comes
## online. Each patch is watered ground, so it darkens, sprouts and greens like
## the player's own watering, and makes a seed the player's watering joins up with.
## patches: Array of Vector4(x, y, z, radius) in world space.
## duration spreads the patches' start times; 0 applies the end state at once (loading).
func scatter(patches: Array[Vector4], duration: float = 6.0) -> void:
	if duration <= 0.0:
		for p in patches:
			paint(Vector3(p.x, p.y, p.z), p.w, 2.0)
		return
	var order := patches.duplicate()
	order.shuffle()
	for k in order.size():
		var p: Vector4 = order[k]
		var t := get_tree().create_timer(duration * float(k) / order.size())
		t.timeout.connect(_wet_disc.bind(Vector3(p.x, p.y, p.z), p.w, 1.0, 0.45))


## Random patch positions inside a world XZ rect, kept apart and off non-soil ground.
func random_patches(area: Rect2, count: int, radius_min: float, radius_max: float,
		spacing: float, seed_value: int = 1) -> Array[Vector4]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array[Vector4] = []
	var tries := 0
	while out.size() < count and tries < count * 30:
		tries += 1
		var p := Vector3(rng.randf_range(area.position.x, area.end.x), 0.0,
				rng.randf_range(area.position.y, area.end.y))
		var px := world_to_px(p)
		if soil.size() == RES * RES and soil[clampi(int(px.y), 0, RES - 1) * RES + clampi(int(px.x), 0, RES - 1)] == 0:
			continue
		var ok := true
		for q in out:
			if Vector2(q.x, q.z).distance_to(Vector2(p.x, p.z)) < spacing:
				ok = false
				break
		if not ok:
			continue
		# A patch is a few overlapping blobs of different sizes, so it reads as an
		# irregular clump rather than one more dot of the same size.
		var r := rng.randf_range(radius_min, radius_max)
		out.append(Vector4(p.x, 0.0, p.z, r))
		for k in rng.randi_range(1, 3):
			var a := rng.randf() * TAU
			var d := r * rng.randf_range(0.6, 1.3)
			out.append(Vector4(p.x + cos(a) * d, 0.0, p.z + sin(a) * d, r * rng.randf_range(0.4, 0.8)))
	return out


# --- 2c. Instant brush (debug / scripted) -----------------------------------

## Call once for a burst, or every frame with strength * delta for continuous watering.
## edge_noise: how much noise distorts the round falloff (0 = perfect circle).
func paint(world_pos: Vector3, radius: float, strength: float = 1.0, edge_noise: float = 0.35) -> void:
	var c := world_to_px(world_pos)
	var r := maxf(radius / MAP_SIZE * RES, 0.5)
	var x0 := maxi(int(c.x - r - 1.0), 0)
	var y0 := maxi(int(c.y - r - 1.0), 0)
	var x1 := mini(int(c.x + r + 1.0), RES - 1)
	var y1 := mini(int(c.y + r + 1.0), RES - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / r
			d += _noise.get_noise_2d(x, y) * edge_noise
			var shape := 1.0 - smoothstep(0.35, 1.0, d)
			if shape <= 0.0:
				continue
			var i := y * RES + x
			_data[i] = _cap(i, _data[i] + int(shape * strength * 255.0))
	_wake_px(c, r)
	_dirty = true


# --- 3. Procedural: overnight spread -----------------------------------------

## Each iteration, green spreads about one pixel (2 m) into neighbouring ground.
## Async: spread over several frames so the game doesn't freeze. Use with await.
func spread(iterations: int = 4, rate: float = 0.5, min_source: int = 128) -> void:
	if _spreading:
		return
	_spreading = true
	for it in iterations:
		var src := _data.duplicate()  # read old state, write new: fronts move 1 px per pass
		for y in range(1, RES - 1):
			var row := y * RES
			for x in range(1, RES - 1):
				var i := row + x
				var cur := src[i]
				if cur == 255:
					continue
				var m := maxi(maxi(src[i - 1], src[i + 1]), maxi(src[i - RES], src[i + RES]))
				if m < min_source or m <= cur:
					continue
				# Cheap per-pixel randomness so fronts advance raggedly.
				var rnd := float(((i * 73856093) ^ (it * 19349663)) & 255) / 255.0
				var gain := int((m - cur) * rate * (0.4 + 0.6 * rnd))
				_data[i] = _cap(i, cur + gain)
			if y % 32 == 0:
				await get_tree().process_frame
		_dirty = true
	_spreading = false
	_wake_all()


# --- 4. Natural spreading: patches creep towards each other -------------------
# Only tiles with moving edges are stepped, within spread_budget_ms per frame; each
# tile remembers when it last ran, so its edges move by real time however often
# that is. Edits elsewhere (watering, painting, blooms) wake the tiles around them.

## Called by GrowthSpreadRegion when it is added, removed, moved or resized.
func add_spread_region(region: Node) -> void:
	if not _spread_regions.has(region):
		_spread_regions.append(region)
	_regions_dirty = true


func remove_spread_region(region: Node) -> void:
	_spread_regions.erase(region)
	_regions_dirty = true


func update_spread_regions() -> void:
	_regions_dirty = true


func _rebuild_regions() -> void:
	_regions_dirty = false
	_region_of.fill(0)
	_spread_regions = _spread_regions.filter(func(r): return is_instance_valid(r))
	# Whole-map regions first, then big to small, so the most specific region wins.
	var order := _spread_regions.duplicate()
	order.sort_custom(func(a, b):
		if a.everywhere != b.everywhere:
			return a.everywhere
		return a.radius > b.radius)
	for region in order:
		var k := _spread_regions.find(region) + 1
		if k > 255 or not region.enabled:
			continue
		if region.everywhere:
			_region_of.fill(k)
			continue
		var c := world_to_px(region.global_position)
		var r: float = region.radius / PIXEL_M
		for y in range(maxi(int(c.y - r - 1.0), 0), mini(int(c.y + r + 1.0), RES - 1) + 1):
			for x in range(maxi(int(c.x - r - 1.0), 0), mini(int(c.x + r + 1.0), RES - 1) + 1):
				# Noisy rim so the change of speed doesn't draw a circle in the meadow.
				if Vector2(x + 0.5, y + 0.5).distance_to(c) / r + _noise.get_noise_2d(x, y) * 0.15 < 1.0:
					_region_of[y * RES + x] = k
	_wake_all()


## Per-frame copy of the settings of the map and every region, so the hot loop reads arrays.
func _refresh_spread_params() -> void:
	var n := _spread_regions.size() + 1
	_p_speed.resize(n)
	_p_reach.resize(n)
	_p_lone.resize(n)
	_p_lut.resize(n)
	_p_speed[0] = spread_speed
	_p_reach[0] = maxi(1, int(attract_distance / PIXEL_M))
	_p_lone[0] = lone_spread
	_p_lut[0] = _lut(spread_by_growth)
	for k in range(1, n):
		var region = _spread_regions[k - 1]
		if not is_instance_valid(region):
			_p_speed[k] = 0.0
			continue
		_p_speed[k] = region.speed
		_p_reach[k] = maxi(1, int(region.attract_distance / PIXEL_M))
		_p_lone[k] = region.lone_spread
		_p_lut[k] = _lut(region.spread_by_growth if region.spread_by_growth else spread_by_growth)


## Curve sampled at every growth byte (0..255).
func _lut(curve: Curve) -> PackedFloat32Array:
	if _lut_cache.has(curve):
		return _lut_cache[curve]
	var t := PackedFloat32Array()
	t.resize(256)
	for v in 256:
		t[v] = maxf(0.0, curve.sample(v / 255.0)) if curve else 1.0
	_lut_cache[curve] = t
	return t


func _spread_step() -> void:
	_refresh_spread_params()
	var start := Time.get_ticks_usec()
	var limit := int(spread_budget_ms * 1000.0)
	var steps := _tile_queue.size()  # each tile at most once per frame
	while steps > 0 and not _tile_queue.is_empty() and Time.get_ticks_usec() - start < limit:
		steps -= 1
		if _queue_pos >= _tile_queue.size():
			_queue_pos = 0
		var t := _tile_queue[_queue_pos]
		if _spread_tile(t):
			_queue_pos += 1
		else:
			_tile_active[t] = 0
			_tile_queue.remove_at(_queue_pos)


## Advances the patch edges in one tile. Returns false once nothing in it can move.
func _spread_tile(t: int) -> bool:
	var dt := minf(_clock - _tile_time[t], 1.0)
	if dt <= 0.0:
		return true
	_tile_time[t] = _clock
	var src := spread_min_source
	var x0 := (t % TILES) * TILE
	var y0 := (t / TILES) * TILE
	var has_soil := soil.size() == RES * RES
	var moving := false
	var max_reach := 0
	var hit_i := PackedInt32Array()
	var hit_v := PackedInt32Array()
	for y in range(y0, y0 + TILE):
		for x in range(x0, x0 + TILE):
			var i := y * RES + x
			var g := _data[i]
			if g >= 255 or (has_soil and g >= soil[i]):
				continue
			var m := 0
			if x > 0: m = _data[i - 1]
			if x < RES - 1: m = maxi(m, _data[i + 1])
			if y > 0: m = maxi(m, _data[i - RES])
			if y < RES - 1: m = maxi(m, _data[i + RES])
			if m < src:
				continue  # not on a patch edge
			var r := _region_of[i]
			var speed := _p_speed[r] * _p_lut[r][m]
			if speed <= 0.0:
				continue
			var reach := _p_reach[r]
			max_reach = maxi(max_reach, reach)
			speed *= lerpf(_p_lone[r], 1.0, _attraction(x, y, reach))
			if speed <= 0.0:
				continue
			moving = true
			# Uneven per-pixel speed (0.5..1) so edges advance raggedly, not as rings.
			var rnd := 0.5 + 0.5 * float(((i * 2654435761) >> 11) & 255) / 255.0
			# Time for ground to reach patch level = time for the edge to move one pixel.
			var gain := float(src) * speed / PIXEL_M * dt * rnd
			var whole := int(gain)
			if randf() < gain - whole:
				whole += 1
			if whole > 0:
				hit_i.append(i)
				hit_v.append(g + whole)
	# Written after the pass, so an edge moves at most one pixel per step.
	for k in hit_i.size():
		_data[hit_i[k]] = _cap(hit_i[k], hit_v[k])
	if not hit_i.is_empty():
		_dirty = true
		# Ground that just turned green may pull or feed edges in neighbouring tiles.
		_wake_rect(Rect2i(x0, y0, TILE, TILE).grow(max_reach + 1))
	return moving


## 0..1: how strongly other green ahead of this edge pixel pulls it. Looks along
## 8 directions that lead away from the patch it borders; the nearest green wins.
## A ray leaving a convex patch can't hit that patch again, so a lone round patch
## isn't pulled by itself, while gaps, notches and nearby patches are.
func _attraction(x: int, y: int, reach: int) -> float:
	var src := spread_min_source
	var best := 0.0
	for k in 8:
		var dx: int = DIR_X[k]
		var dy: int = DIR_Y[k]
		var bx := x - dx
		var by := y - dy
		if bx < 0 or by < 0 or bx >= RES or by >= RES or _data[by * RES + bx] < src:
			continue  # no patch behind this direction
		var step := 1.4142 if dx != 0 and dy != 0 else 1.0
		var steps := int(reach / step)
		var ax := x
		var ay := y
		for s in range(1, steps + 1):
			ax += dx
			ay += dy
			if ax < 0 or ay < 0 or ax >= RES or ay >= RES:
				break
			if _data[ay * RES + ax] >= src:
				best = maxf(best, 1.0 - (s - 1) * step / reach)
				break
		if best >= 1.0:
			break
	return best


func _wake_px(c: Vector2, r: float) -> void:
	var m := r + float(_p_reach[0] if not _p_reach.is_empty() else int(attract_distance / PIXEL_M)) + 1.0
	_wake_rect(Rect2i(int(c.x - m), int(c.y - m), int(2.0 * m) + 1, int(2.0 * m) + 1))


func _wake_rect(rect: Rect2i) -> void:
	if _tile_active.is_empty():
		return
	rect = rect.intersection(Rect2i(0, 0, RES, RES))
	if not rect.has_area():
		return
	for ty in range(rect.position.y / TILE, (rect.end.y - 1) / TILE + 1):
		for tx in range(rect.position.x / TILE, (rect.end.x - 1) / TILE + 1):
			var t := ty * TILES + tx
			if _tile_active[t] == 0:
				_tile_active[t] = 1
				_tile_time[t] = _clock
				_tile_queue.append(t)


func _wake_all() -> void:
	_wake_rect(Rect2i(0, 0, RES, RES))


# --- Save / load -------------------------------------------------------------

func save_progress(path: String = SAVE_PATH) -> Error:
	var img := Image.create_from_data(RES, RES, false, Image.FORMAT_R8, _data)
	return img.save_png(path)


func load_progress(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var img := Image.load_from_file(path)
	if img == null:
		return false
	_data = _to_map_image(img).get_data()
	_dirty = true
	_wake_all()
	return true


## Back to the start: barren except the permanent green.
func clear() -> void:
	_data = _base.duplicate()
	_wet.fill(0)
	_is_active.fill(0)
	_active.clear()
	_changed_rect = Rect2i()
	_dirty = true
	_wet_dirty = true
	_wake_all()


## Average growth (0..1) inside a circle. Used by GrowthZone to decide when an area is done.
## step: sample every Nth pixel to keep it cheap for big zones.
func coverage(world_pos: Vector3, radius: float, step: int = 2) -> float:
	var c := world_to_px(world_pos)
	var r := maxf(radius / MAP_SIZE * RES, 0.5)
	var total := 0
	var sum := 0
	for y in range(maxi(int(c.y - r), 0), mini(int(c.y + r), RES - 1) + 1, step):
		for x in range(maxi(int(c.x - r), 0), mini(int(c.x + r), RES - 1) + 1, step):
			if Vector2(x + 0.5, y + 0.5).distance_to(c) > r:
				continue
			var i := y * RES + x
			if soil.size() == RES * RES and soil[i] == 0:
				continue  # rock / water never counts against the zone
			total += 1
			sum += _data[i]
	return float(sum) / (total * 255.0) if total > 0 else 1.0


# --- Restoration progress -----------------------------------------------------
# Every second pixel on both axes is sampled (4 m apart): about a tenth of a
# millisecond per thousand land samples, measured at most once per progress_interval.

## Called by GrowthRegion when it is added, removed, moved or resized.
func add_progress_region(region: Node) -> void:
	if not _progress_regions.has(region):
		_progress_regions.append(region)
	update_progress_regions()


func remove_progress_region(region: Node) -> void:
	_progress_regions.erase(region)
	update_progress_regions()


func update_progress_regions() -> void:
	_progress_layout_dirty = true
	_progress_timer = progress_interval  # measure on the next frame


## [{id, title, value}] per GrowthRegion in scene order; value is 0..1.
func progress_regions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k in _progress_regions.size():
		var r = _progress_regions[k]
		if is_instance_valid(r) and k < _progress_values.size():
			out.append({"id": r.region_id, "title": r.title, "value": _progress_values[k]})
	return out


## 0..1 for one region (by GrowthRegion.region_id), -1 if there is no such region.
func region_progress(id: StringName) -> float:
	for d in progress_regions():
		if d.id == id:
			return d.value
	return -1.0


func _build_land(terrain: Terrain3D) -> void:
	var data := terrain.data
	if data == null:
		return
	_land.resize(RES * RES)
	_land.fill(0)
	for y in range(0, RES, 2):
		for x in range(0, RES, 2):
			var wp := Vector3(MAP_ORIGIN.x + (x + 0.5) * PIXEL_M, 0.0, MAP_ORIGIN.y + (y + 0.5) * PIXEL_M)
			if not data.has_regionp(wp):
				continue
			var h := data.get_height(wp)
			if not is_nan(h) and h >= land_min_height:
				_land[y * RES + x] = 1
	_progress_layout_dirty = true


func _build_progress_layout() -> void:
	_progress_layout_dirty = false
	_progress_regions = _progress_regions.filter(func(r): return is_instance_valid(r))
	var region_of := PackedByteArray()
	region_of.resize(RES * RES)
	# Big to small, so the smaller region wins where two overlap.
	var order := _progress_regions.duplicate()
	order.sort_custom(func(a, b): return a.radius > b.radius)
	for region in order:
		var k := _progress_regions.find(region) + 1
		var c := world_to_px(region.global_position)
		var r: float = region.radius / PIXEL_M
		for y in range(maxi(int(c.y - r - 1.0), 0), mini(int(c.y + r + 1.0), RES - 1) + 1):
			for x in range(maxi(int(c.x - r - 1.0), 0), mini(int(c.x + r + 1.0), RES - 1) + 1):
				if Vector2(x + 0.5, y + 0.5).distance_to(c) < r:
					region_of[y * RES + x] = k
	var has_land := _land.size() == RES * RES
	var has_soil := soil.size() == RES * RES
	_count_idx.clear()
	_count_region.clear()
	for y in range(0, RES, 2):
		for x in range(0, RES, 2):
			var i := y * RES + x
			if (has_land and _land[i] == 0) or (has_soil and soil[i] == 0):
				continue
			_count_idx.append(i)
			_count_region.append(region_of[i])


func _measure_progress() -> void:
	if _progress_layout_dirty:
		_build_progress_layout()
	_progress_dirty = false
	var n := _progress_regions.size() + 1
	var sums := PackedInt64Array()
	var counts := PackedInt64Array()
	sums.resize(n)
	counts.resize(n)
	var total := 0
	for k in _count_idx.size():
		var g := _data[_count_idx[k]]
		var r := _count_region[k]
		sums[r] += g
		counts[r] += 1
		total += g
	var values := PackedFloat32Array()
	values.resize(n - 1)
	for k in range(1, n):
		values[k - 1] = float(sums[k]) / (counts[k] * 255.0) if counts[k] > 0 else 0.0
	var t := float(total) / (_count_idx.size() * 255.0) if not _count_idx.is_empty() else 0.0
	if values == _progress_values and is_equal_approx(t, progress_total):
		return
	_progress_values = values
	progress_total = t
	progress_changed.emit()


# --- Helpers -------------------------------------------------------------------

## Any image -> exactly RES x RES, one byte per pixel, no mipmaps.
func _to_map_image(img: Image) -> Image:
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()  # get_data() would otherwise append every mip level
	img.convert(Image.FORMAT_R8)
	if img.get_width() != RES or img.get_height() != RES:
		img.resize(RES, RES, Image.INTERPOLATE_BILINEAR)
	return img


func _cap(i: int, v: int) -> int:
	v = clampi(v, 0, 255)
	return mini(v, soil[i]) if soil.size() == RES * RES else v
