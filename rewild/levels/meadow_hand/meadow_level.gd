extends Node3D


@onready var terrain: Terrain3D = $Terrain3D
@onready var player_camera: Camera3D = $SubViewportContainer/PixelateSubViewport/Character/CameraPivot/SpringArm3D/Camera3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	terrain.set_camera(player_camera)

# Called every frame. 'delta' is the elapsed time since the previous frame.


func _process(delta: float) -> void:
	
	pass
