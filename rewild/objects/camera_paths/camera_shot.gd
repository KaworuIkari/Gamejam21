extends PathFollow3D
class_name CameraPathShot

@export var travel_time := 8.0
@export_group("if use quest step")
@export var quest: Quest
@export var step_index := 0
@export var step_name: StringName = &"pump_shot"


signal finished

var _playing := false

func _ready() -> void:
	Quests.step_completed.connect(_on_step_completed)

func _on_step_completed(q: Quest, index: int) -> void:
	if q.get_id() == quest.get_id() and index == step_index:
		play()

func play() -> void:
	if _playing:
		return
	_playing = true
	progress_ratio = 0.0
	CameraDirector.push(step_name)
	var t := create_tween()
	t.tween_property(self, "progress_ratio", 1.0, travel_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t.finished
	CameraDirector.pop(true)
	_playing = false
	finished.emit()
