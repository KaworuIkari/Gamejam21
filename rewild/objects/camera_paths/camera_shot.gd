extends PathFollow3D
class_name CameraPathShot

@export var travel_time := 8.0
@export_group("if use quest step")
@export var quest: Quest
@export var step_index := 0
## The index refers to Quest.optional_steps instead of Quest.steps.
@export var optional := false
@export var step_name: StringName = &""

signal finished

var _playing := false

func _ready() -> void:
	if quest:
		Quests.step_completed.connect(_on_step_completed)

func _on_step_completed(q: Quest, index: int, is_optional: bool) -> void:
	if is_optional == optional and index == step_index and q.get_id() == quest.get_id():
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