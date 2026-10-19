class_name BatteryCharge
extends Node
## The main goal once the terminal is awake: the core battery charges as the four measured
## regions (GrowthRegion in restoration_regions.tscn) turn green. Charge is their average;
## at 100% LIRA receives the battery (ability "battery"), needed for the boat ending.

const BATTERY := &"battery"
## Same rule as the terminal's percentages: 100% only once it is really all green.
const FULL := 0.995


## 0..1: the average recovery of the measured regions.
static func charge() -> float:
	var regions: Array[Dictionary] = GrowthMap.progress_regions()
	if regions.is_empty():
		return 0.0
	var total := 0.0
	for region in regions:
		total += region.value
	return total / regions.size()


static func full() -> bool:
	return charge() >= FULL


func _ready() -> void:
	GrowthMap.progress_changed.connect(_check)
	Quests.changed.connect(_check)
	_check()


func _check() -> void:
	if Quests.terminal_unlocked() and not Quests.has_ability(BATTERY) and full():
		Quests.grant(BATTERY)
