class_name RobotFace extends Node

enum Mood { SMILE, CORRECT, DISGUST, QUESTION, WATCHING, CAT }   # order = layer index
const DIR := "res://objects/player/LIRA/textures/screen/"
const HUD_SHADER := preload("res://objects/player/LIRA/textures/lira_screen_hud.gdshader")
const FILES := ["smile", "correct", "disgust", "question_mark", "watching", "cat"]
const STYLE := {                       # per-mood character of the screen
	Mood.SMILE:    {"pulse": 0.5, "glitch": 0.0},
	Mood.CORRECT:  {"pulse": 0.8, "glitch": 0.0},
	Mood.DISGUST:  {"pulse": 1.4, "glitch": 0.18},
	Mood.QUESTION: {"pulse": 0.9, "glitch": 0.05},
	Mood.WATCHING: {"pulse": 0.3, "glitch": 0.0},
	Mood.CAT:      {"pulse": 0.4, "glitch": 0.0},
}

@export var screen_shader: Shader
@export var transition_time := 0.45
@export var min_hold := 0.8            # shortest time a face stays up; reaction durations should be longer

var base: Mood = Mood.SMILE            # sustained mood, set every frame from game state
var stress := 0.0                      # 0..1, extra constant glitching (low health, etc.)

var _mat: ShaderMaterial
var _mats: Array[ShaderMaterial] = []   # the 3D screen plus any HUD copies; all get the same parameters
var _tween: Tween
var _shown: Mood = Mood.SMILE
var _style_glitch := 0.0
var _react: Mood = Mood.SMILE
var _react_prio := 0
var _react_left := 0.0
var _hold := 0.0

func setup(mesh_instance: MeshInstance3D, surface: int) -> void:
	var images: Array[Image] = []
	var size := Vector2i.ZERO
	for f in FILES:
		var img: Image = (load(DIR + f + ".png") as Texture2D).get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		if size == Vector2i.ZERO:
			size = img.get_size()
		elif img.get_size() != size:
			img.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
		images.append(img)
	var arr := Texture2DArray.new()
	arr.create_from_images(images)

	_mat = ShaderMaterial.new()
	_mat.shader = screen_shader
	_mat.set_shader_parameter("faces", arr)
	_mat.set_shader_parameter("face_count", FILES.size())
	_mat.set_shader_parameter("from_layer", 0)
	_mat.set_shader_parameter("to_layer", 0)
	_mat.set_shader_parameter("transition", 1.0)
	_mat.set_shader_parameter("scanline_count", 15)
	_mats.append(_mat)
	mesh_instance.set_surface_override_material(surface, _mat)   # belongs to this node only

# A 2D material that mirrors the 3D screen live, for UI (see ui/in_game/face/face_hud.gd).
func make_hud_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = HUD_SHADER
	for p in ["faces", "face_count", "from_layer", "to_layer", "transition", "scanline_count", "pulse_speed", "idle_glitch"]:
		m.set_shader_parameter(p, _mat.get_shader_parameter(p))
	_mats.append(m)
	return m

func _set_param(param: StringName, value: Variant) -> void:
	for m in _mats:
		m.set_shader_parameter(param, value)

# A short-lived reaction. Higher priority wins; priority >= 2 skips the hold and shows immediately.
func react(mood: Mood, priority := 1, duration := 1.2) -> void:
	if _react_left > 0.0 and priority < _react_prio:
		return
	_react = mood
	_react_prio = priority
	_react_left = duration

func _process(delta: float) -> void:
	if _mat == null:
		return
	_hold -= delta
	_react_left = maxf(_react_left - delta, 0.0)
	var want: Mood = _react if _react_left > 0.0 else base
	var urgent := _react_left > 0.0 and _react_prio >= 2
	if want != _shown and (_hold <= 0.0 or urgent):
		_show(want)
	_set_param("idle_glitch", maxf(_style_glitch, stress * 0.6))

func _show(mood: Mood) -> void:
	_set_param("from_layer", int(_shown))
	_set_param("to_layer", int(mood))
	_shown = mood
	_hold = min_hold
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_transition, 0.0, 1.0, transition_time)
	var st: Dictionary = STYLE[mood]
	_set_param("pulse_speed", st.pulse)
	_style_glitch = st.glitch

func _set_transition(v: float) -> void:
	_set_param("transition", v)