extends Node

func _init() -> void:
	RenderingServer.set_debug_generate_wireframes(true)
	
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F4:
		var root := get_tree().root
		var mode := (Viewport.DEBUG_DRAW_DISABLED
				if root.debug_draw == Viewport.DEBUG_DRAW_WIREFRAME
				else Viewport.DEBUG_DRAW_WIREFRAME)
		root.debug_draw = mode
		for vp: SubViewport in root.find_children("*", "SubViewport", true, false):
			vp.debug_draw = mode
