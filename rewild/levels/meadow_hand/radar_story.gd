extends Node3D
## Quest 05: start the radar and read the coordinates, available from the start (no key,
## recovery or earlier quest needed). The coordinates are for the boat ending.
const CONSOLE = preload("res://levels/meadow_hand/radar_console.gd")
const FinaleStory = preload("res://levels/meadow_hand/finale_story.gd")
const NOTE = preload("res://objects/interactables/readables/readable_note.tscn")
const LITTER: Array[PackedScene] = [
	preload("res://objects/clearable/garbage_dirty_litter_heap_1.tscn"),
	preload("res://objects/clearable/wreck_garbage_mixed_scrap.tscn"),
	preload("res://objects/clearable/garbage_litter_cluster_2.tscn"),
]
const LITTER_SPOTS: Array[Vector2] = [Vector2(-30,24),Vector2(-15,35),Vector2(5,36),Vector2(30,22),Vector2(34,-12),Vector2(-28,-22)]
const START_EVENT := &"radar_started"
const INFO_EVENT := &"radar_coordinates"

var anchor: Node3D
var terrain: Node
var busy := false
var _trigger: InteractTrigger
var _sparkles: CPUParticles3D

func _ready() -> void:
	if not is_instance_valid(anchor):
		push_error("RadarStory requires the placed RadioObservatory anchor")
		return
	for index in LITTER_SPOTS.size():
		_spawn_litter(index)
	_make_console()
	Quests.changed.connect(_refresh)
	_refresh()

func _spawn_litter(index: int) -> void:
	var cleared_event := StringName("radar_litter_%02d" % index)
	if Quests.event_count(cleared_event) > 0:
		return
	var spot := anchor.to_global(Vector3(LITTER_SPOTS[index].x,0,LITTER_SPOTS[index].y))
	var height: float = terrain.data.get_height(spot) if terrain and terrain.data else NAN
	spot.y = anchor.global_position.y if is_nan(height) else height
	var litter: Clearable = LITTER[index % LITTER.size()].instantiate()
	litter.name = "RadarLitter%02d" % index
	litter.tags.append(&"radar_garbage")
	litter.tags.append(cleared_event)
	litter.position = to_local(spot)
	litter.rotation.y = index * 1.7
	add_child(litter)

func _make_console() -> void:
	# Parent the use point to the actual cabinet: moving either the building or
	# cabinet also moves the interaction sphere and light, including at runtime.
	var cabinet := anchor.get_node_or_null("Model/Auxiliary_Cabinet") as MeshInstance3D
	var point := Marker3D.new()
	point.name = "RadarConsolePoint"
	if cabinet:
		var box := cabinet.get_aabb()
		point.position = Vector3(box.get_center().x,box.position.y+1.0,box.end.z+0.6)
		cabinet.add_child(point)
	else:
		point.position = Vector3(0,1,10)
		anchor.add_child(point)
	_trigger = CONSOLE.new()
	_trigger.name = "RadarStartup"
	_trigger.story = self
	_trigger.radius = 3
	point.add_child(_trigger)
	var prototype := NOTE.instantiate()
	_sparkles = prototype.get_node("SoftSparkles")
	prototype.remove_child(_sparkles)
	prototype.free()
	_sparkles.position = Vector3(0,0.2,0)
	_sparkles.emission_sphere_radius = 0.3
	_trigger.add_child(_sparkles)

func finished_reading() -> bool:
	return Quests.event_count(INFO_EVENT) > 0

func can_operate() -> bool:
	return not finished_reading() and not busy

func prompt_key() -> String:
	return "INTERACT_RADAR_READ" if Quests.event_count(START_EVENT) > 0 else "INTERACT_RADAR_START"

func _refresh() -> void:
	if is_instance_valid(_sparkles):
		_sparkles.emitting = not finished_reading()

func activate_radar() -> void:
	if not can_operate():
		return
	var dialogic := get_node_or_null(^"/root/Dialogic")
	if dialogic == null or dialogic.current_timeline != null or get_tree().paused:
		return
	busy = true
	if Quests.event_count(START_EVENT) == 0:
		Quests.report(START_EVENT)
	_trigger._prompt.set_available(false)
	var scene := get_tree().current_scene
	dialogic.start(make_readout_timeline())
	await dialogic.timeline_ended
	# A scene transition cancels reading. Startup is saved, so a later visit can
	# read the coordinates again instead of leaving the mission stuck.
	if is_inside_tree() and get_tree().current_scene == scene and not SceneRouter.is_busy():
		if not finished_reading():
			Quests.report(INFO_EVENT)
	busy = false
	_refresh()

func make_readout_timeline() -> DialogicTimeline:
	var timeline := DialogicTimeline.new()
	var event := DialogicTextEvent.new()
	event.text = tr("RADAR_READOUT_COORDINATES") % FinaleStory.COORDINATES
	timeline.events.append(event)
	timeline.events_processed = true
	return timeline
