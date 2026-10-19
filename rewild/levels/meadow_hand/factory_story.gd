class_name FactoryStory
extends Node3D
## The factory: rescue the companion bot to get the jetpack (quest 04), everything in one place:
## - litter is scattered around the factory; clearing it counts as "garbage" like any other
##   pile (material for the water-gun upgrades at the terminal);
## - gears lie around from the start, picked up with interact ("factory_gear"): every
##   GearPickup placed in the level scene, or the GEAR_SPOTS fallback when none are placed;
## - the companion bot stands idle in the factory, eye dark, where it is placed in the level.
##   Near it the prompt shows the gear count; with every gear the bot glimmers and can be
##   repaired: it shakes, its eye lights yellow then blue, "core_activated" is reported
##   (quest 04 then grants the jetpack) and the bot follows LIRA.
## The level creates this node and fills in the references below.

## Its SoftSparkles (the soft glimmer marking the first note) is reused on the sleeping bot.
const NOTE := preload("res://objects/interactables/readables/readable_note.tscn")
const LITTER: Array[PackedScene] = [
	preload("res://objects/clearable/garbage_dirty_litter_heap_1.tscn"),
	preload("res://objects/clearable/wreck_garbage_mixed_scrap.tscn"),
	preload("res://objects/clearable/garbage_litter_cluster_2.tscn"),
	preload("res://objects/clearable/wreck_frame_twisted_cables.tscn"),
	preload("res://objects/clearable/garbage_dirty_litter_heap_3.tscn"),
	preload("res://objects/clearable/wreck_slab_snapped_rebar.tscn"),
	preload("res://objects/clearable/garbage_litter_cluster_1.tscn"),
	preload("res://objects/clearable/wreck_tank_ripped_open.tscn"),
]
## Where litter lies, in metres from the factory anchor (outside the building).
const LITTER_SPOTS: Array[Vector2] = [
	Vector2(-14, 32), Vector2(0, 36), Vector2(14, 33), Vector2(28, 30), Vector2(40, 12),
	Vector2(42, -6), Vector2(-10, -30), Vector2(10, -32), Vector2(-40, 8), Vector2(-42, -10),
]
const GEAR := preload("res://objects/pickups/gear/gear_pickup.tscn")
## Fallback when no GearPickup is placed in the level: where gears float, in metres from
## the factory anchor. Collected ones are remembered per index (factory_gear_00..09).
const GEAR_SPOTS: Array[Vector2] = [
	Vector2(-22, 18), Vector2(-6, 24), Vector2(8, 22), Vector2(22, 18), Vector2(28, 2),
	Vector2(24, -18), Vector2(0, -22), Vector2(-24, -20), Vector2(-28, 0), Vector2(-4, 8),
]
const GEAR_HEIGHT := 0.8
## Gears needed to repair the bot; the gear step in quests/04_energy_core.tres asks the same.
const GEARS_NEEDED := 6
const GEAR_EVENT := &"factory_gear"
const ACTIVATED_EVENT := &"core_activated"

## The laboratory: everything is placed relative to it.
var anchor: Node3D
## Terrain3D, to put the litter on the ground.
var terrain: Node
## Sleeps in the factory until repaired, then follows LIRA.
var companion: CubeBotCompanion

var _trigger: InteractTrigger
var _sparkles: CPUParticles3D


func _ready() -> void:
	for i in LITTER_SPOTS.size():
		_spawn_litter(i)
	_place_gears()
	if is_instance_valid(companion):
		if _bot_awake():
			companion.active = true
		else:
			_sleep()
	Quests.changed.connect(_check)
	_check()


func _process(_delta: float) -> void:
	# The bot lives in the pixel SubViewport; its trigger stays here and follows it.
	if is_instance_valid(_trigger) and is_instance_valid(companion):
		_trigger.global_position = companion.to_global(Vector3(0, 0.6, 0))


func _spawn_litter(index: int) -> void:
	var spot := anchor.to_global(Vector3(LITTER_SPOTS[index].x, 0.0, LITTER_SPOTS[index].y))
	var height: float = terrain.data.get_height(spot) if terrain else NAN
	spot.y = anchor.global_position.y if is_nan(height) else height
	var litter: Clearable = LITTER[index % LITTER.size()].instantiate()
	# Placed before it enters the tree: Clearable remembers its start position in _ready
	# (for the hold shake), so moving it afterwards would snap it back to the origin.
	litter.position = to_local(spot)
	litter.rotation.y = index * 1.7
	add_child(litter)


func _bot_awake() -> bool:
	return Quests.event_count(ACTIVATED_EVENT) > 0


func _can_repair() -> bool:
	return Quests.event_count(GEAR_EVENT) >= GEARS_NEEDED


## Near the sleeping bot the prompt shows the gear count (greyed) until it can be repaired;
## then the bot glimmers and the prompt becomes usable.
func _check() -> void:
	if is_instance_valid(_trigger) and not _trigger._used:
		_sparkles.emitting = _can_repair()
	if _trigger or not is_instance_valid(companion) or _bot_awake():
		return
	_trigger = InteractTrigger.new()
	_trigger.name = "RobotRepair"
	_trigger.message_key = "INTERACT_ROBOT_REPAIR"
	_trigger.radius = 3.0
	_trigger.can_interact = _can_repair
	_trigger.locked_text = _repair_locked_text
	add_child(_trigger)
	_trigger.global_position = companion.to_global(Vector3(0, 0.6, 0))
	_trigger.interacted.connect(_repair)
	_sparkles = _make_sparkles()
	_sparkles.emitting = _can_repair()
	_trigger.add_child(_sparkles)


func _repair_locked_text() -> String:
	var gears := mini(Quests.event_count(GEAR_EVENT), GEARS_NEEDED)
	return tr("ROBOT_REPAIR_GEARS").format({"count": gears, "total": GEARS_NEEDED})


## Hand-placed gears are remembered by their path in the level (factory_gear_<path>), so
## renaming or moving one to another parent after a save makes it collectible again.
## With none placed, GEAR_SPOTS is used.
func _place_gears() -> void:
	var placed := get_parent().find_children("*", "GearPickup", true, false)
	for gear: GearPickup in placed:
		gear.event = GEAR_EVENT
		var path := String(get_parent().get_path_to(gear)).to_snake_case().replace("/", "__")
		gear.saved_event = StringName("%s_%s" % [GEAR_EVENT, path])
		if Quests.event_count(gear.saved_event) > 0:
			gear.queue_free()
	if placed.is_empty():
		for i in GEAR_SPOTS.size():
			_spawn_gear(i)


func _spawn_gear(index: int) -> void:
	var saved := StringName("%s_%02d" % [GEAR_EVENT, index])
	if Quests.event_count(saved) > 0:
		return
	var spot := anchor.to_global(Vector3(GEAR_SPOTS[index].x, 0.0, GEAR_SPOTS[index].y))
	var height: float = terrain.data.get_height(spot) if terrain else NAN
	spot.y = (anchor.global_position.y if is_nan(height) else height) + GEAR_HEIGHT
	var gear: GearPickup = GEAR.instantiate()
	gear.name = "Gear%02d" % index
	gear.event = GEAR_EVENT
	gear.saved_event = saved
	gear.position = to_local(spot)
	add_child(gear)


func _bot() -> CubeBot:
	return companion.get_node("CubeBot")


## Before the repair the bot stands still with its eye dark: no glow, no light.
func _sleep() -> void:
	companion.active = false
	var bot := _bot()
	bot.anim_player.pause()
	bot.eye_on = false
	bot.eye_mix = 1.0
	bot.eye_emission = 0.0
	bot.eye_light_energy = 0.0


## The note's soft glimmer, a little bigger so it reads from a distance.
func _make_sparkles() -> CPUParticles3D:
	var note := NOTE.instantiate()
	var sparkles: CPUParticles3D = note.get_node("SoftSparkles")
	note.remove_child(sparkles)
	note.free()
	sparkles.position = Vector3.ZERO
	sparkles.amount = 12
	sparkles.emission_sphere_radius = 0.6
	sparkles.initial_velocity_min *= 4.0
	sparkles.initial_velocity_max *= 4.0
	sparkles.scale_amount_min *= 5.0
	sparkles.scale_amount_max *= 5.0
	return sparkles


## The repair: the bot shakes, its eye lights up yellow and settles to blue, then it wakes
## and follows LIRA. Quest 04 completes on ACTIVATED_EVENT and grants the jetpack.
func _repair() -> void:
	_sparkles.emitting = false
	var bot := _bot()
	var base := bot.position
	var shake := create_tween()
	for i in 12:
		var jolt := Vector3(randf_range(-1, 1), randf_range(0, 0.5), randf_range(-1, 1)) * 0.05 * (1.0 + i / 6.0)
		shake.tween_property(bot, ^"position", base + jolt, 0.05)
	shake.tween_property(bot, ^"position", base, 0.1)
	await shake.finished
	bot.eye_on = true
	var light := create_tween()
	light.tween_property(bot, ^"eye_light_energy", 1.0, 0.3)
	light.parallel().tween_property(bot, ^"eye_emission", companion._base_emission, 0.3)
	light.tween_interval(0.8)
	light.tween_property(bot, ^"eye_mix", 0.0, 1.0).set_trans(Tween.TRANS_SINE)
	await light.finished
	bot.anim_player.play()
	companion.active = true
	Quests.report(ACTIVATED_EVENT)
