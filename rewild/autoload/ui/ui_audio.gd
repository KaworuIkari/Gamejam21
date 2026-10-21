extends Node

const NON_TERMINAL_CLICK: AudioStream = preload("res://assets/audio/ui/click3.ogg")
const TERMINAL_CLICK: AudioStream = preload("res://assets/audio/ui/click4.ogg")
const TERMINAL_SWITCH: AudioStream = preload("res://assets/audio/ui/switch4.ogg")
const NON_TERMINAL_SWITCH: AudioStream = preload("res://assets/audio/ui/switch27.ogg")
const SETTINGS_TAB_SWITCH: AudioStream = preload("res://assets/audio/ui/switch20.ogg")
const GARBAGE_PICKUP: AudioStream = preload("res://assets/audio/sfx/garbage_pickup.wav")
const GEAR_PICKUP: AudioStream = preload("res://assets/audio/sfx/gear_pickup.wav")
const UPGRADE: AudioStream = preload("res://assets/audio/sfx/upgrade.wav")
const TANK_FULL: AudioStream = preload("res://assets/audio/sfx/tank_full.wav")
const WELL_START: AudioStream = preload("res://assets/audio/sfx/well_start.wav")
const WATER_RUSH: AudioStream = preload("res://assets/audio/sfx/water_rush.wav")
const PROP_GRAB: AudioStream = preload("res://assets/audio/sfx/prop_grab.wav")
const THROW_WHOOSH: AudioStream = preload("res://assets/audio/sfx/throw_whoosh.wav")
const PROP_LAND: AudioStream = preload("res://assets/audio/sfx/prop_land.wav")
const PROP_SPLASH: AudioStream = preload("res://assets/audio/sfx/prop_splash.wav")
const PLANT_POP: AudioStream = preload("res://assets/audio/sfx/plant_pop.wav")
const LEAF_RUSTLE: AudioStream = preload("res://assets/audio/sfx/leaf_rustle.wav")
const ROBOT_WAKE: AudioStream = preload("res://assets/audio/sfx/robot_wake.wav")
## Every long press (the interaction prompt plays them): hum while held, chime when done,
## wind-down when let go early.
const CHARGE_LOOP: AudioStream = preload("res://assets/audio/sfx/station_charge_loop.wav")
const CHARGE_COMPLETE: AudioStream = preload("res://assets/audio/sfx/station_charge_complete.wav")
const CHARGE_CANCEL: AudioStream = preload("res://assets/audio/sfx/station_charge_cancel.wav")
const TERMINAL_THEME_PATH := "res://ui/theme/terminal/terminal_theme.tres"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)
	_register_tree(get_tree().root)

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_register_button(node)

func _register_tree(node: Node) -> void:
	if node is BaseButton:
		_register_button(node)
	for child in node.get_children():
		_register_tree(child)

func _register_button(button: BaseButton) -> void:
	if button.has_meta(&"ui_audio_bound"):
		return
	button.set_meta(&"ui_audio_bound", true)
	button.pressed.connect(_play_button_sound.bind(button))

func _play_button_sound(button: BaseButton) -> void:
	var terminal := _is_terminal_button(button)
	var stream: AudioStream
	if button.toggle_mode:
		stream = TERMINAL_SWITCH if terminal else NON_TERMINAL_SWITCH
	else:
		stream = TERMINAL_CLICK if terminal else NON_TERMINAL_CLICK
	_play_stream(stream)

func play_settings_tab_sound(_tab: int) -> void:
	_play_stream(SETTINGS_TAB_SWITCH)

## Gameplay one-shots (garbage, gears, upgrades, tank full); slight pitch variation
## so repeats don't sound identical.
func play_sfx(stream: AudioStream, pitch_jitter := 0.05, volume_db := 0.0) -> void:
	_play_stream(stream, randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter), volume_db)

## A one-shot heard from a spot in the world (wells, the pump, a thrown prop landing),
## quieter the further it is from LIRA. Not an AudioStreamPlayer3D: the level's 3D world
## sits in the PixelateSubViewport, which isn't a 3D audio listener, so those stay silent.
func play_sfx_at(stream: AudioStream, at: Vector3, pitch_jitter := 0.05, volume_db := 0.0) -> void:
	var listener := get_tree().get_first_node_in_group(&"player") as Node3D
	var distance := listener.global_position.distance_to(at) if listener else 0.0
	if distance > 80.0:
		return
	volume_db += linear_to_db(8.0 / maxf(distance, 8.0))
	_play_stream(stream, randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter), volume_db)

func _play_stream(stream: AudioStream, pitch := 1.0, volume_db := 0.0) -> void:
	var player := AudioStreamPlayer.new()
	player.bus = &"SFX"
	player.volume_db = volume_db
	player.stream = stream
	player.pitch_scale = pitch
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()

func _is_terminal_button(button: BaseButton) -> bool:
	var current: Node = button
	while current != null:
		if current is Control:
			var theme := (current as Control).theme
			if theme != null and theme.resource_path == TERMINAL_THEME_PATH:
				return true
		current = current.get_parent()
	return false