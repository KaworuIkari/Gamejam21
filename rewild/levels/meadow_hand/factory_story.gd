class_name FactoryStory
extends Node3D
const SPEAKER = preload("res://dialogue/characters/CompanionBot.dch")
## The factory part of the energy-core story (quest 04), everything in one place:
## - reaching the factory is reported ("factory_reached");
## - litter is scattered around the factory for LIRA to clear (reported as "garbage", which
##   also counts for the earlier clean-up quests, and as "factory_garbage");
## - the factory area's restoration is reported as "factory_restoration" (percentage points);
## - once enough is cleared and restored and LIRA carries the inactive core, a glimmering use
##   spot appears on the assembly table: using it activates the core ("core_activated") and
##   wakes the companion bot, which tells the transmission-tower key and follows LIRA from then on.
## Handing the core in at the lake terminal is done by the station itself (core_delivered).
## The level creates this node and fills in the references below.

## Its SoftSparkles (the soft glimmer marking the first note) is reused for the use spot.
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
## Needed before the core can be activated. The quest steps (quests/04_energy_core.tres)
## ask for the same numbers: litter cleared, and the factory area's recovery in percent.
const LITTER_NEEDED := 8
const RESTORE_NEEDED := 20
## The use spot: the right-hand assembly table inside the left building, from the anchor.
const CORE_SPOT := Vector3(-16.0, 1.1, -17.0)
const REACH_RADIUS := 45.0
const CORE := &"energy_core"
const LITTER_EVENT := &"factory_garbage"
const RESTORE_EVENT := &"factory_restoration"
const REGION := &"factory"
const ACTIVATED_EVENT := &"core_activated"

## The laboratory: everything is placed relative to it.
var anchor: Node3D
## Terrain3D, to put the litter on the ground.
var terrain: Node
## Wakes the companion bot.
var initial: Node
var companion: CubeBotCompanion
## Dialogue played when the core wakes the bot.
var activation_timeline := "res://dialogue/timelines/Factory/core_activated.dtl"

var _key_trigger: InteractTrigger
var _trigger: InteractTrigger
var _restored_percent := 0


func _ready() -> void:
	# Completed legacy saves already passed the bot's original key dialogue.
	if Quests.event_count(&"core_delivered") > 0 and Quests.event_count(&"robot_key_received") == 0:
		Quests.grant(&"radar_key")
		Quests.report(&"robot_key_received")
	var area := QuestArea.new()
	area.name = "FactoryReached"
	area.event = &"factory_reached"
	area.radius = REACH_RADIUS
	add_child(area)
	area.global_position = anchor.global_position
	for i in LITTER_SPOTS.size():
		_spawn_litter(i)
	Quests.changed.connect(_check)
	GrowthMap.progress_changed.connect(_report_restoration)
	_report_restoration()
	_check()


func _spawn_litter(index: int) -> void:
	var spot := anchor.to_global(Vector3(LITTER_SPOTS[index].x, 0.0, LITTER_SPOTS[index].y))
	var height: float = terrain.data.get_height(spot) if terrain else NAN
	spot.y = anchor.global_position.y if is_nan(height) else height
	var litter: Clearable = LITTER[index % LITTER.size()].instantiate()
	litter.tags.append(LITTER_EVENT)
	# Locked until quest 04 starts: the energy core (reward of quest 03) is the key.
	litter.required_ability = CORE
	litter.locked_key = "CLEAR_LOCKED_CORE"
	# Placed before it enters the tree: Clearable remembers its start position in _ready
	# (for the hold shake), so moving it afterwards would snap it back to the origin.
	litter.position = to_local(spot)
	litter.rotation.y = index * 1.7
	add_child(litter)


## Reports the factory area's recovery as it grows, so the quest counts it in percent points.
func _report_restoration() -> void:
	var percent := int(maxf(GrowthMap.region_progress(REGION), 0.0) * 100.0)
	if percent > _restored_percent:
		Quests.report(RESTORE_EVENT, percent - _restored_percent)
		_restored_percent = percent


## The use spot appears once the grounds are clean, recovered, and LIRA carries the inactive core.
func _check() -> void:
	_check_key_recovery()
	if _trigger or Quests.ability_level(CORE) != 1 or Quests.event_count(LITTER_EVENT) < LITTER_NEEDED \
			or Quests.event_count(RESTORE_EVENT) < RESTORE_NEEDED:
		return
	_trigger = InteractTrigger.new()
	_trigger.name = "CoreActivation"
	_trigger.message_key = "INTERACT_CORE_PROMPT"
	_trigger.quest_event = ACTIVATED_EVENT
	_trigger.radius = 3.0
	add_child(_trigger)
	_trigger.global_position = anchor.to_global(CORE_SPOT)
	_trigger.interacted.connect(_activate_core)
	_trigger.add_child(_make_sparkles())


## The note's soft glimmer, a little bigger so it reads from a distance.
func _make_sparkles() -> CPUParticles3D:
	var note := NOTE.instantiate()
	var sparkles: CPUParticles3D = note.get_node("SoftSparkles")
	note.remove_child(sparkles)
	note.free()
	sparkles.position = Vector3(0.0, 0.3, 0.0)
	sparkles.amount = 12
	sparkles.emission_sphere_radius = 0.7
	sparkles.initial_velocity_min *= 4.0
	sparkles.initial_velocity_max *= 4.0
	sparkles.scale_amount_min *= 5.0
	sparkles.scale_amount_max *= 5.0
	return sparkles


func _activate_core() -> void:
	Quests.grant(CORE, 2)
	if companion:
		if initial:
			initial.wake(companion)
		companion.global_position = _trigger.global_position + Vector3(2.0, 0.5, 0.0)
		companion.active = true
	var dialogic := get_node_or_null(^"/root/Dialogic")
	if dialogic:
		dialogic.start(activation_timeline)

## The bot carries a repeatable recovery interaction until its key dialogue reaches
## the grant event, including saves made while the original dialogue was incomplete.
func _check_key_recovery() -> void:
	if Quests.event_count(&"robot_key_received") > 0:
		if is_instance_valid(_key_trigger):
			_key_trigger._used = true
			_key_trigger.one_shot = true
			_key_trigger._prompt.set_available(false)
		return
	if Quests.ability_level(CORE) < 2 or not is_instance_valid(companion) or is_instance_valid(_key_trigger):
		return
	if not companion.active:
		if initial:
			initial.wake(companion)
		companion.global_position = anchor.to_global(CORE_SPOT) + Vector3(2,0.5,0)
		companion.active = true
	_key_trigger = InteractTrigger.new()
	_key_trigger.name = "RadarKeyConversation"
	_key_trigger.one_shot = false
	_key_trigger.message_key = "INTERACT_ROBOT_KEY"
	_key_trigger.radius = 2.5
	# The bot lives in the pixel SubViewport. Keep the UI-owning trigger in the
	# main viewport and follow the bot, avoiding CanvasLayer teardown conflicts.
	_key_trigger.position = to_local(companion.to_global(Vector3(0,0.6,0)))
	add_child(_key_trigger)
	_key_trigger.interacted.connect(_recover_radar_key)

func _process(_delta: float) -> void:
	if is_instance_valid(_key_trigger) and is_instance_valid(companion):
		_key_trigger.global_position = companion.to_global(Vector3(0,0.6,0))

func _recover_radar_key() -> void:
	var dialogic := get_node_or_null(^"/root/Dialogic")
	if dialogic == null or dialogic.current_timeline != null or Quests.event_count(&"robot_key_received") > 0:
		return
	var timeline := DialogicTimeline.new()
	var text := DialogicTextEvent.new()
	text.character = SPEAKER
	text.text = tr("ROBOT_KEY_RECOVERY")
	timeline.events.append(text)
	for entry in [["grant","radar_key"],["report","robot_key_received"]]:
		var event := DialogicCallEvent.new()
		event.autoload_name = "Quests"
		event.method = entry[0]
		event.arguments = [entry[1]]
		timeline.events.append(event)
	timeline.events_processed = true
	dialogic.start(timeline)
