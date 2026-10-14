extends Node3D
var _status: Label
func _ready() -> void:
 var player = CharacterBody3D.new()
 player.name = "DemoPlayer"
 player.add_to_group("player")
 player.position = Vector3(0, 0.9, 2.4)
 player.collision_layer = 1
 var shape = CollisionShape3D.new()
 var capsule = CapsuleShape3D.new()
 capsule.radius = 0.3
 capsule.height = 1.7
 shape.shape = capsule
 player.add_child(shape)
 add_child(player)
 var canvas = CanvasLayer.new()
 add_child(canvas)
 _status = Label.new()
 _status.position = Vector2(24, 24)
 _status.add_theme_font_size_override("font_size", 20)
 canvas.add_child(_status)
 _status.text = "POWER STATION DEMO\nU: complete prerequisite   E: interact   R: reset\nCurrent: Dormant"
 $Station.activated.connect(func(): _status.text = "Activated — activation signal emitted once.\nPress E again to request terminal. R resets.")
 $Station.terminal_requested.connect(func(): _status.text = "Terminal requested — connect this signal to your terminal UI.\nR resets.")
func _unhandled_input(event: InputEvent) -> void:
 if not event is InputEventKey or not event.pressed or event.echo:
  return
 if event.physical_keycode == KEY_U:
  $Station.mark_task_completed(&"main_02_spring")
  _status.text = "Prerequisite completed — Ready.\nPress your interact key (default E) to activate. R resets."
 elif event.physical_keycode == KEY_R:
  $Station.restore_save_data({"state":0,"completed_task_ids":[]})
  _status.text = "Dormant — U completes the prerequisite.\nPress your interact key after unlocking."
