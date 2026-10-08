extends Node
## Growth map over the crater: one byte per pixel, 0 = barren, 255 = fully green.
## Add as an autoload named "GrowthMap". The level calls attach_terrain() once.

signal changed

const MAP_ORIGIN := Vector2(0.0, 0.0)  # world XZ of the crater's corner
const MAP_SIZE := 1024.0               # crater size in world metres (not mask pixels)
const RES := 512                       # growth map pixels per side -> 2 m per pixel
const SAVE_PATH := "user://growth_map.png"

## Optional: where growth is allowed (0 = never, e.g. rock or water). RES x RES bytes.
var soil: PackedByteArray = PackedByteArray()

var image: Image
var texture: ImageTexture

var _data := PackedByteArray()
var _dirty := false
var _spreading := false
var _noise := FastNoiseLite.new()


func _ready() -> void:
	_data.resize(RES * RES)  # zero-filled: all barren
	image = Image.create_from_data(RES, RES, false, Image.FORMAT_R8, _data)
	texture = ImageTexture.create_from_image(image)
	_noise.frequency = 0.08  # in pixels; lower = larger blobs


func _process(_delta: float) -> void:
	if _dirty:  # upload at most once per frame, however many edits happened
		_dirty = false
		image.set_data(RES, RES, false, Image.FORMAT_R8, _data)
		texture.update(image)
		changed.emit()


func attach_terrain(terrain: Terrain3D) -> void:
	terrain.material.set_shader_param("growth_map", texture)


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


# --- 2. Interaction: noisy brush ------------------------------------------

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


func clear() -> void:
	_data.fill(0)
	_dirty = true


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
