extends MeshInstance3D
## 碰到小球不再直接开始对话：改为靠近后显示“按 F 交谈”，按 F 才开始（见 CustomUi/dialogue_trigger.gd）

@export var timeline: String = "XBot_timeline"


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_setup_trigger.call_deferred()


func _setup_trigger() -> void:
	var area := _find_area()
	if area:
		DialogueTrigger.attach_to(area, timeline)
	else:
		push_warning("icoshpere: 没找到 Area3D，无法创建对话触发器")


## 找到 body_entered 连到本脚本的那个 Area3D（找不到就用第一个子 Area3D）
func _find_area() -> Area3D:
	var root := owner if owner else get_parent()
	for a in root.find_children("*", "Area3D", true, false):
		for con in a.body_entered.get_connections():
			if con.callable.get_object() == self:
				return a
	var areas := find_children("*", "Area3D", true, false)
	return areas[0] if not areas.is_empty() else null


func _on_area_3d_body_entered(_body: Node3D) -> void:
	pass # 旧的“碰到就开始对话”，已由 DialogueTrigger 接管


func _process(delta: float) -> void:
	rotation.y += delta * 3.14 / 4.
