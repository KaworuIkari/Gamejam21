extends Node
signal happened(pos: Vector3, kind: StringName, interest: float)

func report(pos: Vector3, kind: StringName, interest := 0.5) -> void:
	happened.emit(pos, kind, interest)