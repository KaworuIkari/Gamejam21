extends Control
## Main menu: start a fresh session, settings, quit.
const LightUI = preload("res://ui/theme/light/light_ui.gd")
const UILayoutRules = preload("res://ui/layout/ui_layout.gd")

@onready var _content: Control = %Content
@onready var _new_game: Button = %NewGameButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit: Button = %QuitButton
@onready var _settings: Control = %SettingsMenu
@onready var _buttons: VBoxContainer = %Buttons
var _starting := false


func _ready() -> void:
	LightUI.apply(self)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_new_game.pressed.connect(_start_game)
	_settings_button.pressed.connect(_on_settings)
	_quit.pressed.connect(_on_quit)
	_settings.closed.connect(_on_settings_closed)
	resized.connect(_update_responsive_layout)
	_update_responsive_layout()
	_new_game.grab_focus.call_deferred()
	BgmPlayer.play_menu_music()


func _start_game() -> void:
	if _starting or SceneRouter.is_busy():
		return
	_starting = true
	SaveManager.start_new_game()
	BgmPlayer.enter_game()
	SceneRouter.goto_game()


func _on_settings() -> void:
	_content.hide()
	_settings.open()


func _on_settings_closed() -> void:
	_content.show()
	_settings_button.grab_focus()


func _on_quit() -> void:
	if await ConfirmPopup.ask(self, tr("MENU_QUIT_CONFIRM"), "MENU_QUIT"):
		get_tree().quit()


func _update_responsive_layout() -> void:
	var compact := UILayoutRules.is_compact(size) or size.y < 900.0
	var margin := 32 if compact else 160
	_content.add_theme_constant_override("margin_left", margin)
	_content.add_theme_constant_override("margin_right", margin)
	_content.add_theme_constant_override("margin_top", 48 if compact else 140)
	_content.add_theme_constant_override("margin_bottom", 40 if compact else 120)
	_buttons.custom_minimum_size.x = minf(440.0, maxf(300.0, size.x - margin * 2.0))
