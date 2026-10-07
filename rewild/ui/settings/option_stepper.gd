class_name OptionStepper
extends Button
## “◀ 当前值 ▶” 选择器，用来代替设置页里的下拉菜单（OptionButton）。
## 不弹出任何窗口：点左半边 = 上一项，点右半边 / 回车 = 下一项，聚焦时 ←/→ 切换。
## 对手柄友好，也避开了 Godot 4.7 在缩放后的 UI 里下拉菜单不显示的问题。
## 接口与 OptionButton 常用部分一致：add_item / select / selected / item_count / item_selected。

signal item_selected(index: int)

var selected := -1
var _items: PackedStringArray = []


func _init() -> void:
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # 文字由 _refresh_text 手动翻译
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	clip_text = true


func _ready() -> void:
	pressed.connect(_on_pressed)


var item_count: int:
	get:
		return _items.size()


func add_item(label: String) -> void:
	_items.append(label)
	if selected < 0:
		selected = 0
	_refresh_text()


## 清空所有选项（选项随环境变化时重建用）
func clear() -> void:
	_items.clear()
	selected = -1
	_refresh_text()


## 和 OptionButton.select 一样：只改显示，不发 item_selected
func select(index: int) -> void:
	if _items.is_empty():
		return
	selected = clampi(index, 0, _items.size() - 1)
	_refresh_text()


func step(dir: int) -> void:
	if disabled or _items.is_empty():
		return
	selected = wrapi(selected + dir, 0, _items.size())
	_refresh_text()
	item_selected.emit(selected)


func _on_pressed() -> void:
	# 鼠标点在左半边 = 上一项；其余情况（右半边、回车、手柄 A）= 下一项
	var mouse_on_left := _last_click_x < size.x * 0.5
	step(-1 if (_last_press_was_mouse and mouse_on_left) else 1)


var _last_press_was_mouse := false
var _last_click_x := 0.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_last_press_was_mouse = true
		_last_click_x = event.position.x
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_last_press_was_mouse = false
	if disabled:
		return
	if event.is_action_pressed(&"ui_left"):
		accept_event()
		step(-1)
	elif event.is_action_pressed(&"ui_right"):
		accept_event()
		step(1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh_text()


func _refresh_text() -> void:
	if selected < 0 or selected >= _items.size():
		text = ""
		return
	text = "◀   %s   ▶" % tr(_items[selected])
