extends CameraPathShot

@export var pump: WaterFlowSwitch

func _ready() -> void:
	pump.started.connect(_play_water_switch)

func _play_water_switch() -> void:
	play(1)