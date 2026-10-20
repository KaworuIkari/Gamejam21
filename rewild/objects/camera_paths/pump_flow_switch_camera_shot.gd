extends CameraPathShot

var pump: WaterFlowSwitch
@export var pump_group: StringName = &"pump_switch"   # same as in water_flow_switch.gd

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if node is WaterFlowSwitch and node.is_in_group(pump_group):
		node.started.connect(play)
		get_tree().node_added.disconnect(_on_node_added)