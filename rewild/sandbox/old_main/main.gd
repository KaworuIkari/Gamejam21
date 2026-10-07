@tool
extends Node3D

@export_tool_button("debug button") var debug_button = debug_func
@onready var terrain_3d: Terrain3D = $SubViewportContainer/PixelateSubViewport/Terrain/Terrain3D
const PAUSE_MENU = preload("res://ui/in_game/pause_menu.tscn")
var pause_menu

func _ready() -> void:
	GrowthMap.attach_terrain(terrain_3d)
	GrowthMap.load_progress()  # returns false on a new game, so the map stays barren
	if Engine.is_editor_hint():
		return
	# 暂停菜单自己处理 Esc，这里只负责创建
	pause_menu = PAUSE_MENU.instantiate()
	add_child(pause_menu)

func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		SaveManager.add_play_time(delta)

func lake_mission_complete() -> void:
	GrowthMap.reveal_mask(preload("res://systems/growth_map/masks/LakeMask.png"), 5.0)

func player_sleep() -> void:
	# plants grow
	await GrowthMap.spread(4)
	
func _unhandled_input(event: InputEvent) -> void:
	# used for debugging
	if event is InputEventKey:
		if event.physical_keycode == KEY_O:
			lake_mission_complete()
		elif event.physical_keycode == KEY_P:
			player_sleep()

func debug_func():
	for i in 3:
		print(i)
	for i in range(3,6):
		print(i)

#func _process(delta: float) -> void:
	#directional_light_3d.rotation.y += delta * 3.14
	#directional_light_3d.rotation.x += 0.5 * sin(delta)
