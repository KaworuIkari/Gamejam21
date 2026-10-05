class_name DialogueUtils
extends RefCounted
## 对话 UI 的小工具。


## 安全地暂停 / 继续 Dialogic。
## Dialogic 2.0-Alpha 的已知问题：角色入场动画结束后，动画节点被释放，
## 但角色节点上仍留着 "animation_node" 标记，此时设置 paused 会报
## “Nonexistent function 'pause' in base 'previously freed'”（编辑器里运行会卡在调试器）。
## 这里先清理失效标记再设置。
static func set_paused(value: bool) -> void:
	var dialogic := DialogicUtil.autoload()
	if dialogic == null:
		return
	if dialogic.has_subsystem("Portraits"):
		for node in dialogic.Portraits.character_nodes.values():
			if is_instance_valid(node) and node.has_meta("animation_node") \
					and not is_instance_valid(node.get_meta("animation_node")):
				node.remove_meta("animation_node")
	dialogic.paused = value
