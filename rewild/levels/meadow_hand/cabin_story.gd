extends Node
## Cabin investigation -> pump flow. Quest resources own step ordering.
var pump: WaterFlowSwitch


func _ready() -> void:
	pump.trigger._used = pump.is_on


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
