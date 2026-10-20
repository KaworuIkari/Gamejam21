extends CameraPathShot

var pump: WaterFlowSwitch

func _ready() -> void:
	if pump:
		pump.started.connect(play)
