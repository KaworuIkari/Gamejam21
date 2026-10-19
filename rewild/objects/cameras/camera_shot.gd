class_name CameraPathShot
extends PathFollow3D

@export var quest_name : StringName = &"pump_started"
@export var view_name: StringName = &"pump_shot"
@export var travel_time := 8.0

signal finished

func _ready() -> void:
	Quests.quest_completed.connect(_on_quest_completed)

func _on_quest_completed(quest: Quest) -> void:
	print(quest)
	if quest.title == quest_name:
		play()

func play() -> void:
	progress_ratio = 0.0
	CameraDirector.push(view_name)  # blends from the player view to the shot
	var t := create_tween()
	t.tween_property(self, "progress_ratio", 1.0, travel_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t.finished
	CameraDirector.pop(true)  # instant snap back
	finished.emit()
