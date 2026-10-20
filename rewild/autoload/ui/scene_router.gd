extends CanvasLayer
## 场景切换（Autoload: SceneRouter）—— 带淡入淡出

signal transition_started(path: String)
signal transition_finished(path: String)

const MAIN_MENU := "res://ui/main_menu/main_menu.tscn"
@export var GAME_WORLD : String= "res://levels/meadow_hand/meadow_hand.tscn"
const FADE_TIME := 0.25

var _fade: ColorRect
var _busy := false


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	add_child(_fade)


func is_busy() -> bool:
	return _busy


func goto(path: String) -> void:
	if _busy:
		return
	_busy = true
	transition_started.emit(path)
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	await _tween_alpha(1.0)
	get_tree().paused = false
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("SceneRouter: 无法切换到 %s (%s)" % [path, error_string(err)])
	else:
		await get_tree().scene_changed
	await _tween_alpha(0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
	transition_finished.emit(path)


func goto_main_menu() -> void:
	goto(MAIN_MENU)


func goto_game() -> void:
	goto(GAME_WORLD)


func _tween_alpha(target: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", target, FADE_TIME)
	await tw.finished
