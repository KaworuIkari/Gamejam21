extends Node3D


const PAUSE_MENU = preload("res://ui/in_game/pause_menu.tscn")
@onready var terrain: Terrain3D = $Terrain3D
@onready var player_camera: Camera3D = $SubViewportContainer/PixelateSubViewport/LIRA/CameraPivot/SpringArm3D/Camera3D


func _ready() -> void:
	terrain.set_camera(player_camera)
	add_child(PAUSE_MENU.instantiate())

func _process(delta: float) -> void:
	# UI 补丁：存档里的游戏时长
	SaveManager.add_play_time(delta)
