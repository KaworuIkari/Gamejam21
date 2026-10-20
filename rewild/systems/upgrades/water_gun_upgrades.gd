class_name WaterGunUpgrades
## Water-gun upgrades bought at the terminal with material from cleared garbage.
## Every cleared pile tagged "garbage" is one material; spending is counted separately
## ("garbage_spent"), so clearing never conflicts with upgrading. Levels are abilities in
## the Quests autoload and saved with it; LIRA reads them (see LIRA → Abilities).

const COST := 5
const MAX_LEVEL := 3
const RATE := &"water_gun_rate"
const TANK := &"water_tank"
const TRACKS: Array[StringName] = [RATE, TANK]
const GARBAGE := &"garbage"
const SPENT := &"garbage_spent"


## Not a node, so the Quests autoload is looked up rather than named directly.
static func _quests() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"Quests")


static func material() -> int:
	return maxi(_quests().event_count(GARBAGE) - _quests().event_count(SPENT), 0)


static func level(track: StringName) -> int:
	return _quests().ability_level(track)


static func can_buy(track: StringName) -> bool:
	return level(track) < MAX_LEVEL and material() >= COST


static func buy(track: StringName) -> bool:
	if not can_buy(track):
		return false
	var next := level(track) + 1
	_quests().report(SPENT, COST)
	_quests().grant(track, next)
	return true
