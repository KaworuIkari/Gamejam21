extends CanvasLayer

## 游戏内暂停菜单（由游戏场景的 main.gd 实例化）。
## 职责：暂停键（Esc）的唯一处理者；打开时暂停场景树并显示鼠标，
## 关闭时按 restore_gameplay_mouse() 的规则恢复鼠标。
const UIScaler = preload("res://ui/layout/ui_scaler.gd")
const LightUI = preload("res://ui/theme/light/light_ui.gd")
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

const TERMINAL_UI = preload("res://ui/in_game/tasks/terminal_ui.tscn")
var _terminal
var _return_confirming := false
var _feedback_version := 0


func _ready() -> void:
	LightUI.apply(_save_screen)
	LightUI.frost(_save_panel)
	LightUI.soften_dim($SaveScreen/Dim)
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
	_terminal = TERMINAL_UI.instantiate()
	_terminal.configure(self)
	get_parent().add_child(_terminal)
	tree_exiting.connect(_terminal.queue_free)


func open() -> void:
	if visible or _terminal.is_open():
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show()
	_overlay.show()
	_settings.hide()
	_save_screen.hide()
	_feedback.hide()
	get_tree().paused = true
	_resume_button.grab_focus()


func close() -> void:
	if not visible:
		return
	_settings.hide()
	_save_screen.hide()
	hide()
	get_tree().paused = false
	_restore_mouse_after_key_release()


## 角色控制器在 Esc 的“松开”事件上也会释放鼠标（它没判断 pressed），
## 用 Esc 关闭菜单时要等按键松开后再锁回鼠标，否则会被立刻解开。
func _restore_mouse_after_key_release() -> void:
	while Input.is_action_pressed(&"pause"):
		await get_tree().process_frame
	await get_tree().process_frame
	if not visible and not _terminal.is_open():
		restore_gameplay_mouse()


## 回到游戏时的鼠标规则：对话中显示鼠标（要点选项），否则锁定给镜头控制。
## 不用“打开前的状态”来恢复：角色控制器在 SubViewport 里，会先于菜单收到 Esc
## 并自行释放鼠标，记下来的永远是“可见”，关闭后玩家得再点一下（还会误触浇水）。
static func restore_gameplay_mouse() -> void:
	var dialogic = Engine.get_main_loop().root.get_node_or_null(^"Dialogic")
	var in_dialogue: bool = dialogic != null and dialogic.current_timeline != null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if in_dialogue else Input.MOUSE_MODE_CAPTURED


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if _return_confirming:
		return
	if not event.is_action_pressed(&"pause"):
		return
	if event.is_echo():
		return
	if _terminal.is_open():
		get_viewport().set_input_as_handled()
		close_terminal()
		return
	if _settings.visible:
		return # 设置页自己处理 Esc（返回上一级）
	get_viewport().set_input_as_handled()
	if _save_screen.visible:
		_close_save_browser()
	elif visible:
		close()
	elif not get_tree().paused:
		open()


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
	_show_feedback(tr("SAVE_FEEDBACK_OK") if saved else tr("SAVE_FEEDBACK_FAIL"))


func _open_settings() -> void:
	_overlay.hide()
	_settings.call(&"open")


func _on_settings_closed() -> void:
	if visible:
		_overlay.show()
		_settings_button.grab_focus()


func _return_to_main_menu() -> void:
	if _return_confirming:
		return
	_return_confirming = true
	var accepted: bool = await ConfirmPopup.ask(self, tr("PAUSE_RETURN_CONFIRM"), "PAUSE_MAIN_MENU", true)
	_return_confirming = false
	if not accepted or not is_inside_tree() or not visible:
		return
	hide()
	SceneRouter.goto_main_menu() # SceneRouter 负责解除暂停和切场景


func _show_feedback(message: String) -> void:
	_feedback_version += 1
	var version := _feedback_version
	_feedback.text = message
	_feedback.show()
	await get_tree().create_timer(2.0, true).timeout
	if version == _feedback_version:
		_feedback.hide()


func _update_responsive_layout() -> void:
	var viewport_size := UIScaler.virtual_viewport_size(get_viewport())
	var compact := UILayoutRules.is_compact(viewport_size)
	var horizontal_padding := 32.0 if compact else 96.0
	_pause_panel.custom_minimum_size.x = minf(500.0, maxf(280.0, viewport_size.x - horizontal_padding))
	_save_panel.custom_minimum_size.x = minf(1100.0, maxf(0.0, viewport_size.x - horizontal_padding))


## Shared modal ownership: the terminal never changes pause or mouse state itself.
func open_terminal() -> void:
	if visible or get_tree().paused or _terminal.is_open():
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	_terminal.open_page()

func close_terminal() -> void:
	if not _terminal.is_open():
		return
	_terminal.close_page()
	get_tree().paused = false
	_restore_mouse_after_key_release()
