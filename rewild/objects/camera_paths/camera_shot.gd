extends PathFollow3D
class_name CameraPathShot

@export var travel_time := 8.0
@export var step_event_name: StringName = &""  # this should also be the name of CameraView, set it even if step is not used
@export_group("if use quest step")
@export var quest: Quest
## The index refers to Quest.optional_steps instead of Quest.steps.
@export var optional := false

signal finished

var _playing := false

func _ready() -> void:
	if quest:
		Quests.step_completed.connect(_on_step_completed)
	if $PhantomCamera3D/CameraView.view_name != step_event_name:
		push_error("CameraView view_name must be identical to step_event_name!")

func _on_step_completed(q: Quest, index: int, is_optional: bool) -> void:
	var quest_step : QuestStep
	if is_optional:
		quest_step = q.optional_steps[index]
	else:
		quest_step = q.steps[index]
	print(quest_step.event == step_event_name, " ", quest_step.event, " ", step_event_name)
	print(q.get_id() == quest.get_id(), " ", q.get_id(), " ", quest.get_id())
	if quest_step.event == step_event_name and q.get_id() == quest.get_id():
		play()

func play(bgm_index: int = 0) -> void:
	if _playing:
		return
	_playing = true
	progress_ratio = 0.0
	if bgm_index >= 0:  # -1 = keep the current music
		BgmPlayer._play_quests_bgm(bgm_index)
	CameraDirector.push(step_event_name)
	var t := create_tween()
	t.tween_property(self, "progress_ratio", 1.0, travel_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t.finished
	CameraDirector.pop(true)
	_playing = false
	finished.emit()
