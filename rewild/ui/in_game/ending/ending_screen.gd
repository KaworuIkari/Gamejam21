extends CanvasLayer
## Layout and black background are authored in ending_screen.tscn.
var route: StringName
var _returning := false


func show_result() -> void:
	%Title.text = "ENDING_DEVICE_TITLE" if route == &"disruptor" else "ENDING_BOAT_TITLE"
	%Result.show()
	%SaveButton.grab_focus.call_deferred()


func _input(event: InputEvent) -> void:
	if not %Result.visible or _returning:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"task_terminal"):
		get_viewport().set_input_as_handled()


func _save_progress() -> void:
	%Feedback.text = "ENDING_SAVE_OK" if SaveManager.save_current() else "ENDING_SAVE_UNAVAILABLE"


func _return_to_menu() -> void:
	if _returning:
		return
	_returning = true
	var accepted: bool = await ConfirmPopup.ask(self,tr("PAUSE_RETURN_CONFIRM"),"PAUSE_MAIN_MENU",true)
	_returning = false
	if accepted and is_inside_tree():
		SceneRouter.goto_main_menu()
