class_name SaveSlotList
extends VBoxContainer
## 存档位列表（主菜单与游戏内暂停菜单共用）。
## mode = NEW    : 选择存档位开始新游戏（已有进度时确认覆盖）
## mode = LOAD   : 只能读取已有存档
## mode = MANAGE : 读取 + 删除
## mode = BROWSE : 主菜单使用：读取 + 空位新建 + 删除
## mode = SAVE   : 仅保存到空位或确认覆盖已有存档
## mode = IN_GAME: 游戏内存档管理：读取 + 保存/覆盖 + 删除

enum Mode { NEW, LOAD, MANAGE, BROWSE, SAVE, IN_GAME }

## 即将进入游戏时发出（外部可借此关闭菜单、播放音效等）
signal game_starting(slot: int)
## 选择一个存档位保存时发出；具体游戏状态由外部调用者写入。
signal save_requested(slot: int)

const UIScaler = preload("res://ui/layout/ui_scaler.gd")
const UILayoutRules = preload("res://ui/layout/ui_layout.gd")

var _compact_layout := false

@export var mode: Mode = Mode.MANAGE:
	set(value):
		mode = value
		if is_inside_tree():
			refresh()


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	SaveManager.slots_changed.connect(queue_refresh)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_compact_layout = _is_compact_layout()
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		queue_refresh()


var _refresh_queued := false

## 合并同一帧内的多次刷新请求（也避免在节点树通知传播期间增删子节点）
func queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	(func():
		_refresh_queued = false
		refresh()).call_deferred()


func _on_viewport_size_changed() -> void:
	var compact := _is_compact_layout()
	if compact == _compact_layout:
		return
	_compact_layout = compact
	queue_refresh()


func _is_compact_layout() -> bool:
	return UILayoutRules.is_compact(UIScaler.virtual_viewport_size(get_viewport()))


## 聚焦第一个可用按钮
func focus_first() -> void:
	for card in get_children():
		for b in card.find_children("*", "Button", true, false):
			if not b.disabled and b.visible:
				b.grab_focus()
				return


func refresh() -> void:
	var had_focus := false
	var focus_owner := get_viewport().gui_get_focus_owner() if get_viewport() else null
	if focus_owner and is_ancestor_of(focus_owner):
		had_focus = true
	for c in get_children():
		remove_child(c)
		c.queue_free()
	for i in SaveManager.SLOT_COUNT:
		add_child(_build_card(SaveManager.get_slot_info(i)))
	if had_focus:
		focus_first.call_deferred()


func _build_card(info: Dictionary) -> Control:
	var slot: int = info.slot
	var card := PanelContainer.new()
	card.theme_type_variation = &"SlotCard"

	var row: BoxContainer
	if _compact_layout:
		row = VBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
	else:
		row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 24)
	card.add_child(row)

	# 缩略图
	var thumb_frame := PanelContainer.new()
	thumb_frame.custom_minimum_size = Vector2(SaveManager.THUMB_SIZE) * 0.75
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1b1f23")
	thumb_frame.add_theme_stylebox_override("panel", sb)
	row.add_child(thumb_frame)
	if info.thumbnail:
		var tex := TextureRect.new()
		tex.texture = info.thumbnail
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		thumb_frame.add_child(tex)
	else:
		var ph := Label.new()
		ph.text = "SLOT_NO_THUMB" if info.exists else ""
		ph.theme_type_variation = &"HintLabel"
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		thumb_frame.add_child(ph)

	# 信息
	var info_box := VBoxContainer.new()
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_box.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(info_box)

	var title := Label.new()
	title.text = tr("SLOT_TITLE") % (slot + 1)
	title.theme_type_variation = &"HeaderLabel"
	info_box.add_child(title)

	if info.exists:
		var loc := Label.new()
		loc.text = tr(info.location) if info.location != "" else "—"
		info_box.add_child(loc)
		var meta := Label.new()
		meta.theme_type_variation = &"HintLabel"
		var date := Time.get_datetime_string_from_unix_time(
			int(info.saved_at) + _utc_offset_seconds(), true).substr(0, 16)
		meta.text = "%s    %s" % [
			tr("SLOT_SAVED_AT") % date,
			tr("SLOT_PLAY_TIME") % SaveManager.format_play_time(info.play_time)]
		info_box.add_child(meta)
	else:
		var empty := Label.new()
		empty.text = "SLOT_EMPTY"
		empty.theme_type_variation = &"HintLabel"
		info_box.add_child(empty)

	# 按钮
	var actions := VBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 10)
	if _compact_layout:
		actions.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_child(actions)

	match mode:
		Mode.NEW:
			var b := _make_button("SLOT_OVERWRITE" if info.exists else "SLOT_START_HERE", actions)
			b.pressed.connect(_on_new_pressed.bind(slot, info.exists))
		Mode.LOAD:
			var b := _make_button("SLOT_LOAD", actions)
			b.disabled = not info.exists
			b.pressed.connect(_on_load_pressed.bind(slot))
		Mode.MANAGE:
			var b := _make_button("SLOT_LOAD", actions)
			b.disabled = not info.exists
			b.pressed.connect(_on_load_pressed.bind(slot))
			var d := _make_button("SLOT_DELETE", actions)
			d.theme_type_variation = &"DangerButton"
			d.disabled = not info.exists
			d.pressed.connect(_on_delete_pressed.bind(slot))
		Mode.BROWSE:
			if info.exists:
				var load_button := _make_button("SLOT_LOAD", actions)
				load_button.pressed.connect(_on_load_pressed.bind(slot))
				var delete_button := _make_button("SLOT_DELETE", actions)
				delete_button.theme_type_variation = &"DangerButton"
				delete_button.pressed.connect(_on_delete_pressed.bind(slot))
			else:
				var new_button := _make_button("SLOT_START_HERE", actions)
				new_button.pressed.connect(_on_new_pressed.bind(slot, false))
		Mode.SAVE:
			var save_button := _make_button("SLOT_OVERWRITE_SAVE" if info.exists else "SLOT_SAVE_HERE", actions)
			save_button.pressed.connect(_on_save_pressed.bind(slot, info.exists))
		Mode.IN_GAME:
			if info.exists:
				var load_button := _make_button("SLOT_LOAD", actions)
				load_button.pressed.connect(_on_load_pressed.bind(slot))
				var save_button := _make_button("SLOT_OVERWRITE_SAVE", actions)
				save_button.pressed.connect(_on_save_pressed.bind(slot, true))
				var delete_button := _make_button("SLOT_DELETE", actions)
				delete_button.theme_type_variation = &"DangerButton"
				delete_button.pressed.connect(_on_delete_pressed.bind(slot))
			else:
				var new_save_button := _make_button("SLOT_SAVE_HERE", actions)
				new_save_button.pressed.connect(_on_save_pressed.bind(slot, false))
	# 各卡片按钮数量不同（已存档 3 个 / 空位 1 个）会让卡片高矮不一：补不可见占位按钮对齐高度
	var want: int = {Mode.IN_GAME: 3, Mode.BROWSE: 2, Mode.MANAGE: 2}.get(mode, 1)
	while actions.get_child_count() < want:
		var ph_btn := Button.new()
		ph_btn.text = "·"
		ph_btn.set_meta(&"no_glass", true)
		ph_btn.disabled = true
		ph_btn.focus_mode = Control.FOCUS_NONE
		ph_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ph_btn.modulate.a = 0.0
		ph_btn.custom_minimum_size.x = 220
		actions.add_child(ph_btn)
	return card


func _make_button(key: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = key
	b.custom_minimum_size.x = 220
	parent.add_child(b)
	return b


func _on_new_pressed(slot: int, exists: bool) -> void:
	if exists and not await ConfirmPopup.ask(self, tr("SLOT_CONFIRM_OVERWRITE") % (slot + 1), "SLOT_OVERWRITE", true):
		return
	SaveManager.start_new_game(slot)
	game_starting.emit(slot)
	SceneRouter.goto_game()


func _on_load_pressed(slot: int) -> void:
	if SaveManager.load_slot(slot):
		game_starting.emit(slot)
		SceneRouter.goto_game()


func _on_delete_pressed(slot: int) -> void:
	if await ConfirmPopup.ask(self, tr("SLOT_CONFIRM_DELETE") % (slot + 1), "SLOT_DELETE", true):
		SaveManager.delete_slot(slot)


func _on_save_pressed(slot: int, exists: bool) -> void:
	if exists and not await ConfirmPopup.ask(self, tr("SLOT_CONFIRM_OVERWRITE") % (slot + 1), "SLOT_OVERWRITE_SAVE", true):
		return
	save_requested.emit(slot)


static func _utc_offset_seconds() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60
