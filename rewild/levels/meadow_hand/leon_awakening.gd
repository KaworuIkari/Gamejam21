extends Node
## Once the pump has filled the lake, throw the little Leon statue into it and the giant
## Leon rises out of the sea: the ground rumbles, the camera and controller shake, then
## the giant slowly climbs up to where it's placed in the editor. Until then it waits
## hidden below the sea.

## The little Leon LIRA carries and throws.
@export var statue: Node3D
## The water to throw it into.
@export var lake: MeshInstance3D
@export var giant: Node3D
## Only works once this is on (e.g. the pumphouse's WaterFlowSwitch that fills the lake).
@export var requires: Node
## The sea it rises out of: it waits with its top this far below the surface.
@export var sea: Node3D
@export var hidden_margin := 5.0
## How far below its placed position the giant waits, in metres (0 = just under `sea`).
@export var rise_depth := 0.0
## Seconds of rumbling before the giant starts to move.
@export var rumble_lead := 2.0
@export var rise_time := 25.0
## Camera shake at full strength, in metres of camera offset.
@export var shake_strength := 0.25
@export_range(-40.0, 12.0) var rumble_volume_db := 0.0
## Reported to the quests once the giant has risen. Empty = nothing.
@export var quest_event: StringName = &"leon_awakened"

const MIX_RATE := 22050.0

var awakened := false
var throwable: Throwable

var _target: Transform3D
var _bodies: Array[Node] = []
var _time := -1.0  # seconds since the rumble began; < 0 = not started
var _camera: Camera3D
var _audio: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _brown := 0.0
var _low := 0.0
var _phase := 0.0


func _ready() -> void:
	if giant == null:
		return
	_target = giant.global_transform
	var depth := rise_depth
	if depth <= 0.0 and sea:
		depth = maxf(_target.origin.y + _top_above_origin() - sea.global_position.y + hidden_margin, 0.0)
	giant.global_position = _target.origin - Vector3(0, depth, 0)
	giant.visible = false
	_collect_bodies(giant)
	_set_bodies_enabled(false)
	if statue:
		throwable = Throwable.new()
		throwable.name = "StatueThrowable"
		throwable.prop = statue
		throwable.target_water = lake
		add_child(throwable)
		throwable.landed.connect(_on_statue_landed)


func _on_statue_landed(in_target: bool) -> void:
	if not in_target or awakened:
		return
	if requires and not requires.get(&"is_on"):
		throwable.in_target = false  # no water yet: it can be picked up again
		return
	awakened = true
	# The statue sinks out of sight.
	var t := create_tween()
	t.tween_property(statue, "global_position", statue.global_position - Vector3(0, 3, 0), 1.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(statue.hide)
	awaken()


## Also callable from code (cutscenes, debug skip).
func awaken() -> void:
	awakened = true
	_time = 0.0
	var player := get_tree().get_first_node_in_group(&"player")
	if player:
		_camera = player.find_child("Camera3D", true, false) as Camera3D
	_start_rumble_sound()
	var settings := get_node_or_null(^"/root/SettingsManager")
	if settings:
		settings.play_feedback(0.5, 0.8, rumble_lead + rise_time)
	var t := create_tween()
	t.tween_interval(rumble_lead)
	t.tween_callback(func():
		giant.visible = true
		_set_bodies_enabled(true))
	t.tween_property(giant, "global_position", _target.origin, rise_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(_finish)


func _process(delta: float) -> void:
	if _time < 0.0:
		return
	_time += delta
	var k := _intensity()
	# Slight rocking while it pushes up through the water.
	if giant.visible and _time < rumble_lead + rise_time:
		var w := _time * 1.7
		giant.global_basis = _target.basis * Basis.from_euler(Vector3(sin(w) * 0.02, 0, cos(w * 0.8) * 0.02) * k)
	if _camera:
		_camera.h_offset = randf_range(-1.0, 1.0) * shake_strength * k
		_camera.v_offset = randf_range(-1.0, 1.0) * shake_strength * k
	_fill_rumble(k)


## 0..1: builds up over the lead-in, holds while rising, fades over the last 2.5 s.
func _intensity() -> float:
	var total := rumble_lead + rise_time
	var fade_in := clampf(_time / maxf(rumble_lead, 0.01), 0.0, 1.0)
	var fade_out := clampf((total + 1.0 - _time) / 2.5, 0.0, 1.0)
	return fade_in * fade_in * fade_out


func _finish() -> void:
	giant.global_transform = _target
	await get_tree().create_timer(1.2).timeout  # let the rumble die down
	_time = -1.0
	if _camera:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
	if _audio:
		_audio.queue_free()
		_audio = null
	var quests := get_node_or_null(^"/root/Quests")
	if quests and quest_event != &"":
		quests.report(quest_event)


## No rumble in the FMOD banks yet, so make one: filtered brown noise with a slow roll
## and a sub-bass hum, streamed into an AudioStreamGenerator on the SFX bus.
func _start_rumble_sound() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.3
	_audio = AudioStreamPlayer.new()
	_audio.stream = gen
	_audio.volume_db = rumble_volume_db
	if AudioServer.get_bus_index(&"SFX") >= 0:
		_audio.bus = &"SFX"
	add_child(_audio)
	_audio.play()
	_playback = _audio.get_stream_playback()


func _fill_rumble(k: float) -> void:
	if _playback == null:
		return
	var n := _playback.get_frames_available()
	var t := _time
	for i in n:
		_brown = clampf(_brown + randf_range(-1.0, 1.0) * 0.05, -1.0, 1.0) * 0.995
		_low += (_brown - _low) * 0.08  # low-pass: keep it a deep growl
		_phase = fmod(_phase + TAU * (34.0 + 6.0 * sin(t * 0.7)) / MIX_RATE, TAU)
		var roll := 0.65 + 0.35 * sin(t * TAU * 0.45) * sin(t * TAU * 0.13)
		var s := (_low * 2.2 + sin(_phase) * 0.35) * roll * k
		_playback.push_frame(Vector2(s, s) * 0.8)
		t += 1.0 / MIX_RATE


## Height of the giant's highest mesh point above its origin, in metres.
func _top_above_origin() -> float:
	var top := 0.0
	for v in giant.find_children("*", "VisualInstance3D", true, false):
		var box: AABB = (v as VisualInstance3D).global_transform * (v as VisualInstance3D).get_aabb()
		top = maxf(top, box.end.y - giant.global_position.y)
	return top


func _collect_bodies(node: Node) -> void:
	for c in node.get_children():
		if c is CollisionObject3D or c is NavigationObstacle3D:
			_bodies.append(c)
		else:
			_collect_bodies(c)


func _set_bodies_enabled(on: bool) -> void:
	for b in _bodies:
		b.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
