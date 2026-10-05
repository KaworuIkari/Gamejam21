extends Control
## 主菜单：继续 / 存档浏览 / 设置 / 退出

const UILayoutRules = preload("res://ui/layout/ui_layout.gd")

@onready var _content: Control = %Content
@onready var _continue: Button = %ContinueButton
@onready var _load: Button = %LoadButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit: Button = %QuitButton
@onready var _slot_screen: Control = %SlotScreen
@onready var _slot_list: SaveSlotList = %SlotList
@onready var _settings: Control = %SettingsMenu
@onready var _buttons: VBoxContainer = %Buttons
@onready var _slot_panel: PanelContainer = $SlotScreen/Center/Panel
@onready var _slot_title: Label = %SlotScreenTitle

var _return_focus: Control


func _ready() -> void:
	_continue.pressed.connect(_on_continue)
	_load.pressed.connect(_open_save_browser)
	_settings_button.pressed.connect(_on_settings)
	_quit.pressed.connect(_on_quit)
	%SlotBackButton.pressed.connect(_close_slot_screen)
	_settings.closed.connect(_on_submenu_closed)
	SaveManager.slots_changed.connect(_refresh_buttons)
	resized.connect(_update_responsive_layout)
	_refresh_buttons()
	_update_responsive_layout()
	_focus_default.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if _slot_screen.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close_slot_screen()


func _refresh_buttons() -> void:
	var has_save := SaveManager.has_any_save()
	_continue.disabled = not has_save
	_continue.focus_mode = Control.FOCUS_ALL if has_save else Control.FOCUS_NONE


func _focus_default() -> void:
	(_load if _continue.disabled else _continue).grab_focus()


func _on_continue() -> void:
	var slot := SaveManager.get_latest_slot()
	if slot >= 0 and SaveManager.load_slot(slot):
		SceneRouter.goto_game()


func _open_save_browser() -> void:
	_return_focus = get_viewport().gui_get_focus_owner()
	%SlotScreenTitle.text = "SLOT_SCREEN_BROWSE"
	_slot_list.mode = SaveSlotList.Mode.BROWSE
	_content.hide()
	_slot_screen.show()
	_slot_list.focus_first()


func _close_slot_screen() -> void:
	_slot_screen.hide()
	_on_submenu_closed()


func _on_settings() -> void:
	_return_focus = _settings_button
	_content.hide()
	_settings.open()


func _on_submenu_closed() -> void:
	_content.show()
	_refresh_buttons()
	if is_instance_valid(_return_focus) and _return_focus.is_visible_in_tree() and _return_focus.focus_mode != Control.FOCUS_NONE:
		_return_focus.grab_focus()
	else:
		_focus_default()


func _on_quit() -> void:
	if await ConfirmPopup.ask(self, tr("MENU_QUIT_CONFIRM"), "MENU_QUIT"):
		get_tree().quit()


func _update_responsive_layout() -> void:
	var compact := UILayoutRules.is_compact(size)
	var margin := 32 if compact else 160
	_content.add_theme_constant_override("margin_left", margin)
	_content.add_theme_constant_override("margin_right", margin)
	_content.add_theme_constant_override("margin_top", 48 if compact else 140)
	_content.add_theme_constant_override("margin_bottom", 40 if compact else 120)
	_buttons.custom_minimum_size.x = minf(440.0, maxf(300.0, size.x - margin * 2.0))
	_slot_panel.custom_minimum_size.x = minf(1100.0, maxf(0.0, size.x - margin * 2.0))
	_slot_title.add_theme_font_size_override(&"font_size", 36 if compact else 48)
