extends Node
## 存档管理（Autoload: SaveManager）—— 目前是“桩”实现
## 存档格式：user://saves/slot_N.json（元数据 + data 字典），缩略图 slot_N.png
## 以后接入真实游戏数据时，只需往 current_data 里读写内容，接口保持不变。

signal slots_changed
signal game_saved(slot: int)
signal game_loaded(slot: int)

const SLOT_COUNT := 3
const SAVE_DIR := "user://saves"
const SAVE_VERSION := 1
const THUMB_SIZE := Vector2i(320, 180)

## 当前正在游玩的存档位（-1 表示未进入游戏）
var current_slot: int = -1
## 游戏数据（由各游戏系统自由读写）
var current_data: Dictionary = {}
## 当前存档累计游玩时长（秒）
var play_time: float = 0.0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]


func thumb_path(slot: int) -> String:
	return "%s/slot_%d.png" % [SAVE_DIR, slot]


func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func has_any_save() -> bool:
	for i in SLOT_COUNT:
		if slot_exists(i):
			return true
	return false


func first_empty_slot() -> int:
	for i in SLOT_COUNT:
		if not slot_exists(i):
			return i
	return -1


## 返回最近一次保存的存档位，没有则 -1
func get_latest_slot() -> int:
	var best := -1
	var best_time := -1
	for i in SLOT_COUNT:
		var info := get_slot_info(i)
		if info.exists and int(info.saved_at) > best_time:
			best_time = int(info.saved_at)
			best = i
	return best


## { slot, exists, saved_at(unix 秒), play_time(秒), location(翻译 key), thumbnail(Texture2D 或 null) }
func get_slot_info(slot: int) -> Dictionary:
	var info := {"slot": slot, "exists": false, "saved_at": 0, "play_time": 0.0, "location": "", "thumbnail": null}
	var raw := _read_json(slot_path(slot))
	if raw.is_empty():
		return info
	info.exists = true
	info.saved_at = int(raw.get("saved_at", 0))
	info.play_time = float(raw.get("play_time", 0.0))
	info.location = str(raw.get("data", {}).get("location", ""))
	if FileAccess.file_exists(thumb_path(slot)):
		var img := Image.load_from_file(thumb_path(slot))
		if img:
			info.thumbnail = ImageTexture.create_from_image(img)
	return info


func start_new_game(slot: int) -> void:
	delete_slot(slot, false)
	current_slot = slot
	play_time = 0.0
	current_data = {"location": "LOC_CRASH_SITE"}
	save_current()


func load_slot(slot: int) -> bool:
	var raw := _read_json(slot_path(slot))
	if raw.is_empty():
		push_warning("SaveManager: 存档位 %d 不存在或已损坏" % slot)
		return false
	current_slot = slot
	play_time = float(raw.get("play_time", 0.0))
	current_data = raw.get("data", {})
	game_loaded.emit(slot)
	return true


## 保存当前进度；thumbnail 可传入截图（会被缩放到 THUMB_SIZE）
func save_current(thumbnail: Image = null) -> bool:
	if current_slot < 0:
		return false
	var payload := {
		"version": SAVE_VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"play_time": play_time,
		"data": current_data,
	}
	var f := FileAccess.open(slot_path(current_slot), FileAccess.WRITE)
	if f == null:
		push_warning("SaveManager: 无法写入存档 (%s)" % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	if thumbnail and not thumbnail.is_empty():
		var img := thumbnail.duplicate() as Image
		img.resize(THUMB_SIZE.x, THUMB_SIZE.y, Image.INTERPOLATE_BILINEAR)
		img.save_png(thumb_path(current_slot))
	game_saved.emit(current_slot)
	slots_changed.emit()
	return true


## 将当前游戏状态写入指定存档位，并把该位置设为后续自动保存使用的存档位。
func save_to_slot(slot: int, thumbnail: Image = null) -> bool:
	if slot < 0 or slot >= SLOT_COUNT:
		push_warning("SaveManager: 无效存档位 %d" % slot)
		return false
	if current_data.is_empty():
		current_data = {"location": "LOC_CRASH_SITE"}
	current_slot = slot
	return save_current(thumbnail)


func delete_slot(slot: int, notify := true) -> void:
	for p in [slot_path(slot), thumb_path(slot)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	if slot == current_slot and notify:
		current_slot = -1
	if notify:
		slots_changed.emit()


func add_play_time(delta: float) -> void:
	if current_slot >= 0:
		play_time += delta


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## 工具：把秒数格式化为 “H:MM:SS”
func format_play_time(seconds: float) -> String:
	var s := int(seconds)
	@warning_ignore("integer_division")
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
