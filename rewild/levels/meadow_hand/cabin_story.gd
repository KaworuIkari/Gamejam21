extends Node
## Cabin investigation -> pump flow -> Act I. Quest resources own step ordering.
signal act_one_started
const TITLE = preload("res://ui/in_game/story/act_title.tscn")
var pump: WaterFlowSwitch
var _title_pending := false


func _ready() -> void:
	pump.trigger.can_interact = _can_start_pump
	pump.trigger._used = pump.is_on
	Quests.quest_completed.connect(_on_quest_completed)
	for quest in Quests.quests:
		if quest.get_id() == &"00_investigate_cabin" and Quests.status(quest) == Quests.Status.DONE:
			_on_quest_completed(quest)


func _can_start_pump() -> bool:
	return Quests.event_count(&"cabin_delivery_read") > 0 and Quests.event_count(&"cabin_crew_read") > 0


func _on_quest_completed(quest: Quest) -> void:
	if quest.get_id() == &"00_investigate_cabin" and not SaveManager.current_data.get("act_one_entered", false):
		_title_pending = true


func _process(_delta: float) -> void:
	if not _title_pending or get_tree().paused or SceneRouter.is_busy() or Dialogic.current_timeline != null:
		return
	_title_pending = false
	SaveManager.current_data["act_one_entered"] = true
	add_child(TITLE.instantiate())
	act_one_started.emit()


## The pump moved from 01 into 00. Migrate once, preserving later progress/equipment.
static func migrate_save(data: Dictionary) -> void:
	if data.has("cabin_story_version"):
		return
	data["cabin_story_version"] = 1
	var saved: Dictionary = data.get("quests", {})
	var counters: Dictionary = saved.get("counters", {})
	var states: Dictionary = saved.get("quests", {})
	var cabin: Dictionary = states.get("00_investigate_cabin", {})
	var water: Dictionary = states.get("01_restore_water", {})
	var read_before := not data.has("startup_checks") or int(counters.get("cabin_investigated", 0)) > 0 \
			or int(cabin.get("status", 0)) == 2
	var pump_before := int(counters.get("pump_started", 0)) > 0 or int(water.get("step", 0)) >= 1 \
			or int(water.get("status", 0)) == 2
	if read_before or pump_before:
		counters["cabin_delivery_read"] = 1
		counters["cabin_crew_read"] = 1
	if pump_before:
		counters["pump_started"] = maxi(1, int(counters.get("pump_started", 0)))
		data["act_one_entered"] = true
	states.erase("00_investigate_cabin")
	if not water.is_empty():
		water["step"] = maxi(0, int(water.get("step", 0)) - 1)
		var baselines: Array = water.get("baselines", [])
		water["baselines"] = baselines.slice(1)
		if not pump_before:
			water["status"] = 0
			water["done"] = []
	saved["counters"] = counters
	saved["quests"] = states
	data["quests"] = saved
