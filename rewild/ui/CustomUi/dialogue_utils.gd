class_name DialogueUtils
extends RefCounted
## 对话 UI 的小工具。
##
## 暂停对话统一走“暂停原因”登记，不要直接写 Dialogic.paused：
##   DialogueUtils.push_pause(&"history")   # 打开历史面板
##   DialogueUtils.pop_pause(&"history")    # 关闭历史面板
## 只要还有任意一个原因，对话就保持暂停。这样“历史面板 / 跳过确认 / 游戏暂停菜单”
## 互相叠加、以任意顺序关闭时，都不会把别人的暂停提前解除。

static var _pause_reasons: Dictionary = {}


## Translate an active page without restarting its typing animation while paused.
static func refresh_current_text(text: String) -> void:
	var dialogic := DialogicUtil.autoload()
	var textboxes: Array = dialogic.Text.get_textboxes()
	if textboxes.is_empty():
		return
	var label: RichTextLabel = textboxes[0]
	var ratio := label.visible_ratio
	label.text = text
	label.visible_ratio = ratio
	dialogic.Text.dialog_text = text
	dialogic.Text.dialog_text_parsed = label.get_parsed_text()


## 登记一个暂停原因（重复登记同一原因无副作用）
static func push_pause(reason: StringName) -> void:
	_pause_reasons[reason] = true
	_apply()


## 撤销一个暂停原因；没有其他原因时对话继续
static func pop_pause(reason: StringName) -> void:
	_pause_reasons.erase(reason)
	_apply()


## 新时间线开始 / 对话布局销毁时清空，避免残留原因让下一段对话卡住
static func clear_pauses() -> void:
	_pause_reasons.clear()
	_apply()


static func is_pause_reason_active(reason: StringName) -> bool:
	return _pause_reasons.has(reason)


static func _apply() -> void:
	_set_dialogic_paused(not _pause_reasons.is_empty())


## Dialogic 2.0-Alpha 的已知问题：角色入场动画结束后，动画节点被释放，
## 但角色节点上仍留着 "animation_node" 标记，此时设置 paused 会报
## “Nonexistent function 'pause' in base 'previously freed'”（编辑器里运行会卡在调试器）。
## 这里先清理失效标记再设置。
static func _set_dialogic_paused(value: bool) -> void:
	var dialogic := DialogicUtil.autoload()
	if dialogic == null:
		return
	if dialogic.has_subsystem("Portraits"):
		for node in dialogic.Portraits.character_nodes.values():
			if is_instance_valid(node) and node.has_meta("animation_node") \
					and not is_instance_valid(node.get_meta("animation_node")):
				node.remove_meta("animation_node")
	if dialogic.paused != value:
		dialogic.paused = value
