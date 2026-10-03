extends MeshInstance3D

func _on_area_3d_body_entered(body: Node3D) -> void:
	Dialogic.start("XBot_timeline")
	
func _process(delta: float) -> void:
	rotation.y += delta * 3.14 / 4.
