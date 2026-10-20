extends CameraPathShot

@export var bgm_idx : int = 0
@onready var trigger_area : Area3D = $"../Area3D"
var triggered : bool = false

func _on_area_3d_body_entered(body: Node3D) -> void:
	if body is LIRA_Character:
		if triggered:
			return
		triggered = true
		trigger_area.set_deferred("monitoring", false)
		play(bgm_idx)
