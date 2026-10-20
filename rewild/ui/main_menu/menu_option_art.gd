extends TextureRect
## Localized menu lettering; geometry and textures stay editable in the scene.
## 文字图贴按钮右侧，高度由 art_height 决定，宽度按图片比例自动算。
@export var chinese: Texture2D
@export var english: Texture2D
@export var art_height := 72.0
@export var right_pad := 20.0
@export var selected_tint := Color(1.04, 1.02, 0.90, 1)
@export var pressed_tint := Color(0.84, 0.80, 0.72, 1)
@onready var _button: BaseButton = get_parent()
var _keyboard_navigation := false


func _ready() -> void:
	for event in [_button.mouse_entered, _button.mouse_exited, _button.focus_entered,
			_button.focus_exited, _button.button_down, _button.button_up]:
		event.connect(_update_feedback)
	_update_language()
	_update_feedback()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_keyboard_navigation = false
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") \
			or event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev") \
			or event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_keyboard_navigation = true
	else:
		return
	_update_feedback()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_language()


func _update_language() -> void:
	texture = chinese if TranslationServer.get_locale().begins_with("zh") else english
	_fit_right()


func _fit_right() -> void:
	if texture == null:
		return
	var width := art_height * texture.get_width() / texture.get_height()
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -right_pad - width
	offset_right = -right_pad
	offset_top = -art_height * 0.5
	offset_bottom = art_height * 0.5


func _update_feedback() -> void:
	if _button.is_pressed():
		self_modulate = pressed_tint
	else:
		var selected := _button.has_focus() if _keyboard_navigation else _button.is_hovered()
		self_modulate = selected_tint if selected else Color.WHITE
