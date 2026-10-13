extends Node3D
## Test bench for CubeBot. Keys 1-6 play animations, C toggles blue/yellow eye,
## Space runs a jump (Jump_Start -> Fall -> Land -> Idle). Arrow keys orbit the camera.

const ANIMS := [&"Idle", &"Walk", &"Run", &"Jump_Start", &"Fall", &"Land"]

@onready var bot: CubeBot = $CubeBot
@onready var pivot: Node3D = $CameraPivot
@onready var label: Label = $UI/Label


func _ready() -> void:
	$CameraPivot/Camera3D.look_at(Vector3(0, 0.55, 0))
	bot.animation_finished.connect(_on_anim_finished)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode >= KEY_1 and key.keycode < KEY_1 + ANIMS.size():
		bot.play(ANIMS[key.keycode - KEY_1])
	elif key.keycode == KEY_C:
		bot.glow_to(0.0 if bot.eye_mix > 0.5 else 1.0)
	elif key.keycode == KEY_SPACE:
		bot.play(&"Jump_Start", 0.1)
	_refresh()


func _process(delta: float) -> void:
	pivot.rotation.y += Input.get_axis("ui_left", "ui_right") * delta * 1.5
	pivot.rotation.x = clampf(pivot.rotation.x + Input.get_axis("ui_up", "ui_down") * delta, -1.2, 0.3)


func _on_anim_finished(anim_name: StringName) -> void:
	match anim_name:
		&"Jump_Start":
			bot.play(&"Fall", 0.05)
			get_tree().create_timer(0.6).timeout.connect(func(): bot.play(&"Land", 0.05))
		&"Land":
			bot.play(&"Idle", 0.2)
	_refresh()


func _refresh() -> void:
	label.text = "1 Idle  2 Walk  3 Run  4 Jump_Start  5 Fall  6 Land  |  Space jump  C eye colour  arrows orbit\nplaying: %s" % bot.anim_player.current_animation
