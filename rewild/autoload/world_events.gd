extends Node
signal happened(pos: Vector3, kind: StringName, interest: float)

@export var max_range := 60.0  # events farther than this from the player are dropped

func report(pos: Vector3, kind: StringName, interest := 0.5) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and pos.distance_to(player.global_position) > max_range * interest:
		return
	happened.emit(pos, kind, interest)