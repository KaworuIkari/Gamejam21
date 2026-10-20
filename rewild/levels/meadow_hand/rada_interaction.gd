extends "res://objects/interactables/interact_trigger.gd"

const HOLD_PROMPT = preload("res://ui/in_game/interaction/clear_hold_prompt.tscn")
const UI_THEME = preload("res://ui/theme/light/light_theme.tres")
const SFX_CHARGE: AudioStreamWAV = preload("res://assets/audio/sfx/station_charge_loop.wav")
const SFX_COMPLETE: AudioStream = preload("res://assets/audio/sfx/station_charge_complete.wav")
const SFX_CANCEL: AudioStream = preload("res://assets/audio/sfx/station_charge_cancel.wav")

@export var coordinate_target: Node3D
@export var destination_coordinates := Vector3(21, 10, 26)
@export_range(0.1, 10.0, 0.1) var hold_time := 1.0

var _hold := 0.0
var _bar_fill: StyleBoxFlat
var _coordinate_label: Label
var _charge: AudioStreamPlayer
var _sfx: AudioStreamPlayer


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	one_shot = true
	message_key = "长按 %s 插入钥匙启动雷达站"
	can_interact = _has_fox_key
	locked_text = _get_locked_text
	super._ready()

	# Replace the inherited tap prompt with the station's hold prompt.
	remove_child(_prompt)
	_prompt.queue_free()
	_prompt = HOLD_PROMPT.instantiate()
	add_child(_prompt)
	_prompt.configure(&"interact", message_key)
	_style_charge_bar()

	_charge = AudioStreamPlayer.new()
	_charge.bus = &"SFX"
	_charge.stream = SFX_CHARGE
	add_child(_charge)
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = &"SFX"
	add_child(_sfx)

	_create_coordinate_display()
	interacted.connect(_show_coordinates)


func _has_fox_key() -> bool:
	return Quests.has_ability(&"fox_key")


func _get_locked_text() -> String:
	return "需要钥匙启动雷达站"


func _unhandled_input(_event: InputEvent) -> void:
	# Override the inherited tap activation; completion is handled below.
	pass


func _process(delta: float) -> void:
	super._process(delta)
	var usable := _can_use() and not SceneRouter.is_busy()
	if usable and Input.is_action_pressed(&"interact"):
		_hold = minf(_hold + delta, hold_time)
		_charge_sound(_hold / hold_time)
	else:
		if _hold > 0.0:
			_charge.stop()
			if _hold > hold_time * 0.15:
				_play_sfx(SFX_CANCEL)
		_hold = 0.0

	var progress := clampf(_hold / hold_time, 0.0, 1.0)
	_prompt.set_hold_progress(progress)
	_bar_fill.bg_color = Color(0.15, 0.86, 0.92).lerp(
		Color(0.75, 1.0, 1.0), progress * progress
	)
	_bar_fill.shadow_size = int(lerpf(3.0, 9.0, progress))

	if usable and _hold >= hold_time:
		_hold = 0.0
		_charge.stop()
		_play_sfx(SFX_COMPLETE)
		_prompt.play_activation()
		use()
		_prompt.set_available(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_hold = 0.0
		if is_instance_valid(_charge):
			_charge.stop()


func _charge_sound(progress: float) -> void:
	if not _charge.playing:
		_charge.play()
	_charge.pitch_scale = lerpf(
		0.7, 1.7, progress * progress * (3.0 - 2.0 * progress)
	)
	_charge.volume_db = lerpf(-16.0, -5.0, progress)


func _play_sfx(stream: AudioStream) -> void:
	_sfx.stream = stream
	_sfx.play()


func _style_charge_bar() -> void:
	var bar := _prompt.get_node(
		"Root/Anchor/Panel/HoldColumn/HoldProgress"
	) as ProgressBar
	bar.custom_minimum_size = Vector2(260, 12)

	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.06, 0.16, 0.2, 0.55)
	background.border_color = Color(0.55, 0.95, 1.0, 0.45)
	background.set_border_width_all(1)
	background.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", background)

	_bar_fill = StyleBoxFlat.new()
	_bar_fill.bg_color = Color(0.15, 0.86, 0.92)
	_bar_fill.set_corner_radius_all(6)
	_bar_fill.shadow_color = Color(0.3, 0.95, 1.0, 0.6)
	_bar_fill.shadow_size = 4
	bar.add_theme_stylebox_override("fill", _bar_fill)


func _create_coordinate_display() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	canvas.custom_viewport = get_tree().root

	_coordinate_label = Label.new()
	_coordinate_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Use the same theme, size and ink color as the station prompt.
	_coordinate_label.theme = UI_THEME
	_coordinate_label.add_theme_font_size_override("font_size", 26)
	_coordinate_label.add_theme_color_override(
		"font_color", Color(0.22, 0.29, 0.28, 1.0)
	)
	_coordinate_label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	_coordinate_label.add_theme_constant_override("outline_size", 0)
	_coordinate_label.hide()
	canvas.add_child(_coordinate_label)

	_coordinate_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_coordinate_label.offset_left = 24
	_coordinate_label.offset_top = -90
	_coordinate_label.offset_right = 700
	_coordinate_label.offset_bottom = -24

	get_tree().root.add_child.call_deferred(canvas)
	tree_exiting.connect(canvas.queue_free)


func _show_coordinates() -> void:
	var destination := destination_coordinates
	if is_instance_valid(coordinate_target):
		destination = coordinate_target.global_position

	_coordinate_label.text = "雷达站已启动，返航坐标已获取\n坐标: X %.1f   Y %.1f   Z %.1f" % [
		destination.x, destination.y, destination.z,
	]
	_coordinate_label.show()
