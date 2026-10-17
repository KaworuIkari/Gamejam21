extends Camera3D

@export var player_view: StringName = &"player"
@export var bird_view: StringName = &"seagull"

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_bird_view"):
		CameraDirector.request_toggle(player_view, bird_view)