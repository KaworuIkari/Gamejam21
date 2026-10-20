extends Control
## Decorative background only. No input, gameplay state or per-character nodes.
@export_range(0.0, 0.3, 0.01) var intensity := 0.26
@export_range(0.0, 160.0, 1.0) var fall_speed := 64.0
const FONT = preload("res://ui/fonts/fusion-pixel-12px.ttf")
var _phase := 0.0
var _redraw_time := 0.0
var _rng := RandomNumberGenerator.new()
var _streams: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_rng.randomize()
	visibility_changed.connect(_update_processing)
	resized.connect(_build_streams)
	_build_streams()
	_update_processing()

func _build_streams() -> void:
	_streams.clear()
	var x := _rng.randf_range(8.0, 32.0)
	while x < size.x:
		var length := _rng.randi_range(7, 17)
		var glyphs: Array[String] = []
		for row in length:
			glyphs.append(str(_rng.randi_range(0, 1)))
		_streams.append({"x": x, "head": _rng.randf_range(0.0, size.y + 480.0),
			"speed": _rng.randf_range(0.65, 1.45), "spacing": _rng.randf_range(25.0, 31.0),
			"brightness": _rng.randf_range(0.55, 1.0), "glyphs": glyphs,
			"change_in": _rng.randf_range(0.15, 0.8)})
		x += _rng.randf_range(30.0, 62.0)
	queue_redraw()

func _update_processing() -> void:
	set_process(is_visible_in_tree())
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_phase += delta * fall_speed
	for stream in _streams:
		stream["head"] = fmod(float(stream["head"]) + delta * fall_speed * float(stream["speed"]), size.y + 480.0)
		stream["change_in"] = float(stream["change_in"]) - delta
		if float(stream["change_in"]) <= 0.0:
			var glyphs: Array[String] = stream["glyphs"]
			glyphs[_rng.randi_range(0, glyphs.size() - 1)] = str(_rng.randi_range(0, 1))
			stream["change_in"] = _rng.randf_range(0.15, 0.8)
	_redraw_time += delta
	if _redraw_time >= 1.0 / 30.0:
		_redraw_time = 0.0
		queue_redraw()

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	for stream in _streams:
		var glyphs: Array[String] = stream["glyphs"]
		for row in glyphs.size():
			var y := float(stream["head"]) - row * float(stream["spacing"])
			if y < 24.0 or y > size.y - 4.0:
				continue
			var fade := pow(1.0 - float(row) / glyphs.size(), 1.3)
			draw_string(FONT, Vector2(float(stream["x"]), y), glyphs[row], HORIZONTAL_ALIGNMENT_LEFT, -1, 24,
				Color(0.57, 0.72, 0.46, intensity * fade * float(stream["brightness"])))
