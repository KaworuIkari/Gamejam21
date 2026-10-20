extends Node
## Cabin investigation -> pump flow. Quest resources own step ordering.
var pump: WaterFlowSwitch


func _ready() -> void:
	pump.trigger._used = pump.is_on


## Version 1 moved the pump from 01 into 00; version 2 made cabin reading required;
## version 3 makes it optional again (00 = start the pump). Rebuild only 00 from its one-off
## counters, preserving later progress and equipment.
static func migrate_save(data: Dictionary) -> void:
	var version := int(data.get("cabin_story_version", 0))
	if version >= 3:
		return
	data["cabin_story_version"] = 3
	var saved: Dictionary = data.get("quests", {})
	if version == 2:
		# 00's step indices changed; it is rebuilt from pump_started on load.
		saved.get("quests", {}).erase("00_investigate_cabin")
		return
	var counters: Dictionary = saved.get("counters", {})
	var states: Dictionary = saved.get("quests", {})
	var cabin: Dictionary = states.get("00_investigate_cabin", {})
	var water: Dictionary = states.get("01_restore_water", {})
	var terminal_owned := int(saved.get("abilities", {}).get("task_terminal", 0)) > 0
	var pump_before := int(counters.get("pump_started", 0)) > 0 or terminal_owned \
			or int(water.get("status", 0)) == 2 \
			or (version == 0 and int(water.get("step", 0)) >= 1) \
			or (version >= 1 and (int(water.get("status", 0)) > 0 or int(cabin.get("status", 0)) == 2))
	var read_before := pump_before or int(counters.get("cabin_investigated", 0)) > 0 \
			or int(cabin.get("status", 0)) == 2 \
			or (version == 0 and not data.has("startup_checks") and not saved.is_empty())
	if read_before:
		counters["cabin_delivery_read"] = maxi(1, int(counters.get("cabin_delivery_read", 0)))
		counters["cabin_crew_read"] = maxi(1, int(counters.get("cabin_crew_read", 0)))
	if pump_before:
		counters["pump_started"] = maxi(1, int(counters.get("pump_started", 0)))
		data["act_one_entered"] = true
	states.erase("00_investigate_cabin")
	if version == 0 and not water.is_empty():
		water["step"] = maxi(0, int(water.get("step", 0)) - 1)
		var baselines: Array = water.get("baselines", [])
		water["baselines"] = baselines.slice(1)
		if not pump_before:
			water["status"] = 0
			water["done"] = []
	saved["counters"] = counters
	saved["quests"] = states
	data["quests"] = saved
