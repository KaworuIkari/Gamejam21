extends Node3D
## Demo of the three world stages. In the real game, call
## $WorldStages.advance() when a quest completes instead of using these keys.
##   N = next stage   1/2/3 = jump to a stage   R = reset to wasteland

@onready var stages: WorldStages = $WorldStages
@onready var label: Label = $UI/Label


func _ready() -> void:
	# Sit the device on the generated ground.
	var device := $SeedDevice as Node3D
	device.position.y = ($MeadowWorld as MeadowWorld).get_height(device.position.x, device.position.z)
	stages.stage_changed.connect(func(i: int, st: WorldStage) -> void:
		label.text = "Stage %d: %s   [N] next  [1-3] jump  [R] reset" % [i + 1, st.stage_name])


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_N:
			stages.advance()
		KEY_1, KEY_2, KEY_3:
			var target: int = event.keycode - KEY_1
			if target < stages.current:
				stages.go_to(0, false)  # going back: clear, then replay up to target
			for i in range(stages.current + 1, target + 1):
				stages.go_to(i)
		KEY_R:
			stages.go_to(0)
