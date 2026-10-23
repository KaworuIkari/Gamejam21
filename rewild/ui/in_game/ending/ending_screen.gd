extends CanvasLayer
## Layout and black background are authored in ending_screen.tscn.
const ISLAND_DELAY := 0
const ISLAND_FADE := 5
const CREDITS_HOLD := 6.0
const CREDITS_FADE := 2.0
const BUTTON_FADE := 0.8
## Pixel lettering for the credits, matching the terminal UI; 48 px keeps the 12 px grid crisp.
const CREDITS_FONT = preload("res://ui/fonts/fusion-pixel-12px.ttf")
## Shown instead of the scene's default island once the giant Leon has been woken.
const ISLAND_WITH_FROG = preload("res://ui/in_game/ending/ending_island_with_frog.png")

var route: StringName
var _returning := false


func show_result() -> void:
	%Title.text = "ENDING_DEVICE_TITLE" if route == &"disruptor" else "ENDING_BOAT_TITLE"
	%Result.show()
	if route == &"disruptor":
		%MenuButton.grab_focus.call_deferred()
	else:
		_reveal_island()


## The island illustration fades in under the credits; the credits hold, fade out,
## and only then does the menu button appear.
func _reveal_island() -> void:
	%Title.add_theme_font_override("font", CREDITS_FONT)
	%Title.add_theme_constant_override("outline_size", 3)
	%Title.add_theme_color_override("font_outline_color", Color(0.1, 0.16, 0.2, 0.85))
	%MenuButton.hide()
	%MenuButton.modulate.a = 0.0
	if Quests.event_count(&"leon_awakened") > 0:
		%Island.texture = ISLAND_WITH_FROG
	%Island.show()
	var tween := create_tween().set_parallel()
	tween.tween_property(%Island, "modulate:a", 1.0, ISLAND_FADE).set_delay(ISLAND_DELAY)
	tween.tween_property(%Title, "modulate:a", 0.0, CREDITS_FADE).set_delay(CREDITS_HOLD)
	tween.chain().tween_callback(func() -> void:
		%MenuButton.show()
		%MenuButton.grab_focus())
	tween.tween_property(%MenuButton, "modulate:a", 1.0, BUTTON_FADE)


func _input(event: InputEvent) -> void:
	if not %Result.visible or _returning:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"task_terminal"):
		get_viewport().set_input_as_handled()


func _return_to_menu() -> void:
	if _returning:
		return
	_returning = true
	var accepted: bool = await ConfirmPopup.ask(self,tr("PAUSE_RETURN_CONFIRM"),"PAUSE_MAIN_MENU",true)
	_returning = false
	if accepted and is_inside_tree():
		SceneRouter.goto_main_menu()
