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


func _process(delta: float) -> void:
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


func attach_terrain(terrain: Terrain3D) -> void:
	terrain.material.set_shader_param("growth_map", texture)
	terrain.material.set_shader_param("wet_map", wet_texture)
	if always_green_slot >= 0:
		seed_from_terrain(terrain, always_green_slot)


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
		return

	var state := {"done": 0}  # buckets below this index are finished
	var tween := create_tween()
	tween.tween_method(_apply_reveal.bind(buckets, delay, target, ramp, state), 0.0, 1.0, duration)


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
