class_name BatteryCharge
extends Node
## The main goal once the terminal is awake: the core battery charges as the four measured
## regions (GrowthRegion in restoration_regions.tscn) turn green. Charge is their average.
## At 100% the battery is ready; LIRA takes it by interacting with the lake station
## (lake_power_station.gd), which grants the ability "battery" for the boat ending.

const BATTERY := &"battery"
const COLLECTED := &"battery_collected"
## Same rule as the terminal's percentages: 100% only once it is really all green.
const FULL := 0.995


## Also compiled early (the debug menu uses it), so autoloads are looked up, not named.
static func _autoload(autoload_name: String) -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node(autoload_name)


## 0..1: the average recovery of the measured regions.
static func charge() -> float:
	var regions: Array[Dictionary] = _autoload("GrowthMap").progress_regions()
	if regions.is_empty():
		return 0.0
	var total := 0.0
	for region in regions:
		total += region.value
	return total / regions.size()


static func full() -> bool:
	return charge() >= FULL


static func collected() -> bool:
	return _autoload("Quests").event_count(COLLECTED) > 0


## Fully charged and still waiting at the station.
static func ready_to_collect() -> bool:
	return _autoload("Quests").terminal_unlocked() and full() and not collected()


## Hands the battery over (once). The lake station calls this when LIRA uses it.
static func collect() -> void:
	if collected():
		return
	_autoload("Quests").report(COLLECTED)
	_autoload("Quests").grant(BATTERY)
