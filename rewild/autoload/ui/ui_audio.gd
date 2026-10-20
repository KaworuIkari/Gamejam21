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
func play_sfx(stream: AudioStream, pitch_jitter := 0.05) -> void:
	_play_stream(stream, randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter))

func _play_stream(stream: AudioStream, pitch := 1.0) -> void:
	var player := AudioStreamPlayer.new()
	player.bus = &"SFX"
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