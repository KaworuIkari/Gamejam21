extends CanvasLayer
## Persistent across scenes, including the main menu and paused gameplay.
var _elapsed := 0.0

func _ready() -> void:
	SettingsManager.setting_changed.connect(_on_setting_changed)
	_on_setting_changed("video", "show_fps", SettingsManager.get_value("video", "show_fps"))

func _on_setting_changed(section: String, key: String, value: Variant) -> void:
	if section != "video" or key != "show_fps":
		return
	visible = bool(value)
	set_process(visible)
	_elapsed = 0.0
	%Value.text = "FPS: %d" % Engine.get_frames_per_second()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.25:
		_elapsed = 0.0
		%Value.text = "FPS: %d" % Engine.get_frames_per_second()
