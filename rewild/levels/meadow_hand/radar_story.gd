extends Node3D
## Quest 05 framework. Regional recovery is its ONLY completion requirement.
## Visit/start are saved hooks for later story details, not additional quest gates.
const QUEST = preload("res://quests/05_radar_station.tres")
const PREVIOUS = preload("res://quests/04_energy_core.tres")
const NOTE = preload("res://objects/interactables/readables/readable_note.tscn")
const LITTER: Array[PackedScene] = [
	preload("res://objects/clearable/garbage_dirty_litter_heap_1.tscn"),
	preload("res://objects/clearable/wreck_garbage_mixed_scrap.tscn"),
	preload("res://objects/clearable/garbage_litter_cluster_2.tscn"),
]
const LITTER_SPOTS: Array[Vector2] = [Vector2(-30,24),Vector2(-15,35),Vector2(5,36),Vector2(30,22),Vector2(34,-12),Vector2(-28,-22)]
const REGION := &"mountain"
const RESTORE_EVENT := &"mountain_restoration"
const START_EVENT := &"radar_started"

var anchor: Node3D
var terrain: Node
var _trigger: InteractTrigger
var _sparkles: CPUParticles3D
var _litter: Array[Clearable] = []

func _ready() -> void:
	if not is_instance_valid(anchor):
		push_error("RadarStory requires the placed RadioObservatory anchor")
		return
	for index in LITTER_SPOTS.size():
		_spawn_litter(index)
	var area := QuestArea.new()
	area.name = "RadarReached"
	area.event = &"radar_reached"
	area.radius = 38
	add_child(area)
	area.global_position = anchor.global_position
	_make_console()
	GrowthMap.progress_changed.connect(_report_restoration)
	Quests.changed.connect(_refresh)
	_refresh()

func _spawn_litter(index: int) -> void:
	var spot := anchor.to_global(Vector3(LITTER_SPOTS[index].x,0,LITTER_SPOTS[index].y))
	var height: float = terrain.data.get_height(spot) if terrain and terrain.data else NAN
	spot.y = anchor.global_position.y if is_nan(height) else height
	var litter: Clearable = LITTER[index % LITTER.size()].instantiate()
	litter.tags.append(&"radar_garbage")
	litter.required_ability = &"radar_access"
	litter.locked_key = "CLEAR_LOCKED_RADAR"
	litter.position = to_local(spot)
	litter.rotation.y = index * 1.7
	add_child(litter)
	_litter.append(litter)

func _make_console() -> void:
	_trigger = InteractTrigger.new()
	_trigger.name = "RadarStartup"
	_trigger.message_key = "INTERACT_RADAR_START"
	_trigger.quest_event = START_EVENT
	_trigger.radius = 3
	add_child(_trigger)
	# Put the use zone at the existing cabinet's visible front, not at the dish centre.
	var cabinet := anchor.get_node_or_null("Model/Auxiliary_Cabinet") as MeshInstance3D
	if cabinet:
		var box := cabinet.get_aabb()
		_trigger.global_position = cabinet.to_global(Vector3(box.get_center().x,box.position.y+1.0,box.end.z+0.6))
	else:
		_trigger.global_position = anchor.to_global(Vector3(0,1,10))
	var prototype := NOTE.instantiate()
	_sparkles = prototype.get_node("SoftSparkles")
	prototype.remove_child(_sparkles)
	prototype.free()
	_sparkles.position = Vector3(0,0.2,0)
	_sparkles.emission_sphere_radius = 0.3
	_trigger.add_child(_sparkles)

func access_unlocked() -> bool:
	return Quests.status(PREVIOUS) == Quests.Status.DONE

func _refresh() -> void:
	var allowed := access_unlocked()
	if allowed and not Quests.has_ability(&"radar_access"):
		Quests.grant(&"radar_access")
	_report_restoration()
	if not is_instance_valid(_trigger):
		return
	var started := Quests.event_count(START_EVENT) > 0
	_trigger._used = started
	_trigger.set_process(allowed and not started)
	_trigger.set_process_unhandled_input(allowed and not started)
	if not allowed or started:
		_trigger._prompt.set_available(false)
	_sparkles.emitting = allowed and not started

func _report_restoration() -> void:
	if not access_unlocked():
		return
	record_restoration(GrowthMap.region_progress(REGION))

## Separate conversion makes threshold and save/reload semantics testable.
func record_restoration(fraction: float) -> void:
	if fraction < 0 or not access_unlocked():
		return
	var percent := floori(clampf(fraction,0,1)*100.0 + 0.00001)
	var reported := Quests.event_count(RESTORE_EVENT)
	# Report only new percentage points. Reloading the same map must never add them twice.
	if percent > reported:
		Quests.report(RESTORE_EVENT,percent-reported)
