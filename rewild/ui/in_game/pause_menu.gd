extends CanvasLayer

## 只在游戏场景运行时创建的基础暂停菜单。
const UILayoutRules = preload("res://ui/layout/ui_layout.gd")

@onready var _resume_button: Button = %ResumeButton
@onready var _save_button: Button = %SaveButton
@onready var _settings_button: Button = %SettingsButton
@onready var _main_menu_button: Button = %MainMenuButton
@onready var _overlay: Control = $Overlay
@onready var _settings: Control = %SettingsMenu
@onready var _save_screen: Control = %SaveScreen
@onready var _save_slot_list: SaveSlotList = %SaveSlotList
@onready var _save_back_button: Button = $SaveScreen/Center/Panel/VBox/Footer/BackButton
@onready var _feedback: Label = %SaveFeedback
@onready var _pause_panel: PanelContainer = $Overlay/Center/Panel
@onready var _save_panel: PanelContainer = $SaveScreen/Center/Panel

var _feedback_version := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resume_button.pressed.connect(close)
	_save_button.pressed.connect(_open_save_browser)
	_settings_button.pressed.connect(_open_settings)
	_main_menu_button.pressed.connect(_return_to_main_menu)
	_settings.connect(&"closed", _on_settings_closed)
	_save_slot_list.save_requested.connect(_on_save_slot_requested)
	_save_back_button.pressed.connect(_close_save_browser)
	get_viewport().size_changed.connect(_update_responsive_layout)
	_update_responsive_layout()
	_feedback.hide()
	hide()


func open() -> void:
	show()
	_overlay.show()
	_settings.hide()
	_save_screen.hide()
	_feedback.hide()
	get_tree().paused = true
	_resume_button.grab_focus()


func close() -> void:
	_settings.hide()
	_save_screen.hide()
	hide()
	get_tree().paused = false


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if _settings.visible:
		return
	if _save_screen.visible:
		if event.is_action_pressed("pause"):
			get_viewport().set_input_as_handled()
			_close_save_browser()
		return
	if visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()


func _open_save_browser() -> void:
	_overlay.hide()
	_save_slot_list.mode = SaveSlotList.Mode.IN_GAME
	_save_screen.show()
	_save_slot_list.focus_first()


func _close_save_browser() -> void:
	_save_screen.hide()
	_overlay.show()
	_save_button.grab_focus()


func _on_save_slot_requested(slot: int) -> void:
	if not SaveManager.current_data.has("location"):
		SaveManager.current_data["location"] = "LOC_CRASH_SITE"
	SaveManager.current_data["scene_path"] = get_tree().current_scene.scene_file_path
	var saved := SaveManager.save_to_slot(slot)
	_close_save_browser()
	_show_feedback("进度已保存" if saved else "保存失败")


func _open_settings() -> void:
	_overlay.hide()
	_settings.call(&"open")


func _on_settings_closed() -> void:
	if visible:
		_overlay.show()
		_settings_button.grab_focus()


func _return_to_main_menu() -> void:
	get_tree().paused = false
	SceneRouter.goto_main_menu()


func _show_feedback(message: String) -> void:
	_feedback_version += 1
	var version := _feedback_version
	_feedback.text = message
	_feedback.show()
	await get_tree().create_timer(2.0, true).timeout
	if version == _feedback_version:
		_feedback.hide()


func _update_responsive_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var compact := UILayoutRules.is_compact(viewport_size)
	var horizontal_padding := 32.0 if compact else 96.0
	_pause_panel.custom_minimum_size.x = minf(500.0, maxf(280.0, viewport_size.x - horizontal_padding))
	_save_panel.custom_minimum_size.x = minf(1100.0, maxf(0.0, viewport_size.x - horizontal_padding))
