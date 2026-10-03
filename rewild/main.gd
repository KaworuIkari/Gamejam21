@tool
extends Node3D

@export_tool_button("debug button") var debug_button = debug_func
@onready var crater: MeshInstance3D = $Terrain/Crater/Crater
const CRATER_MAT_DESERT = preload("uid://cbnubeuob4uxv")
const CRATER_MAT_VEG = preload("uid://co3pbxhiwhlqy")
var mat_is_veg : bool = false

func debug_func():
	for i in 3:
		print(i)
	for i in range(3,6):
		print(i)
		
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1:
				get_tree().quit()
			KEY_F2:
				print("DEBUG: player pos: ", global_position)
			KEY_F3:
				if mat_is_veg:
					crater.set_surface_override_material(0, CRATER_MAT_DESERT)
				else:
					crater.set_surface_override_material(0, CRATER_MAT_VEG)

				mat_is_veg = not mat_is_veg

#func _process(delta: float) -> void:
	#directional_light_3d.rotation.y += delta * 3.14
	#directional_light_3d.rotation.x += 0.5 * sin(delta)
