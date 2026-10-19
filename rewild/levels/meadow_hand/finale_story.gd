extends Node3D
## Mutually exclusive finale. Only confirmed startup consumes the unique module.
## Future cinematics can connect ending_selected and use get_ending_focus().
signal ending_selected(route: StringName, focus: Node3D)
const QUEST = preload("res://quests/06_final_choice.tres")
const PREVIOUS = preload("res://quests/05_radar_station.tres")
const INTERACTION = preload("res://levels/meadow_hand/finale_interaction.gd")
const ENDING_SCREEN = preload("res://ui/in_game/ending/ending_screen.gd")
const NOTE = preload("res://objects/interactables/readables/readable_note.tscn")
const MODULE := &"chaos_energy_module"
const PARTS := &"harbor_parts"
const DEVICE := &"disruptor"
const BOAT := &"boat"
const PARTS_NEEDED := 6
const LITTER: Array[PackedScene] = [
	preload("res://objects/clearable/garbage_dirty_litter_heap_1.tscn"),
	preload("res://objects/clearable/wreck_garbage_mixed_scrap.tscn"),
	preload("res://objects/clearable/garbage_litter_cluster_2.tscn"),
]
# On the existing yard/apron, away from the shed/office/boat and main access ramp.
const PILE_SPOTS: Array[Vector2] = [Vector2(-14,6),Vector2(-14,11),Vector2(-14,19),Vector2(0,6),Vector2(2,9),Vector2(2,13),Vector2(2,19),Vector2(13,6),Vector2(7,-4),Vector2(-10,-2)]
var radar: Node3D
var harbor: Node3D
var terrain: Node
var cameras: Dictionary = {}
var busy := false
var _refreshing := false
var _presented := false
var _triggers: Dictionary = {}
var _lights: Dictionary = {}
var _piles: Array[Clearable] = []
var _ending_screen: CanvasLayer

func _ready() -> void:
	if not is_instance_valid(radar) or not is_instance_valid(harbor):
		push_error("FinaleStory requires the existing radar and harbor")
		return
	_make_disruptor()
	_make_boat()
	for index in PILE_SPOTS.size():
		_spawn_pile(index)
	Quests.changed.connect(_refresh)
	_refresh()

func _make_disruptor() -> void:
	var platform := radar.get_node("Model/Service_Platform") as MeshInstance3D
	var box := platform.get_aabb()
	var spot := Vector3(box.get_center().x,box.end.y+0.5,box.get_center().z)
	_make_interaction(DEVICE,platform,spot,1.7)

func _make_boat() -> void:
	var hull := harbor.get_node("island_harbour_edit/Boat") as MeshInstance3D
	var box := hull.get_aabb()
	# Beside the hull, reachable from the yard without entering its solid collider.
	_make_interaction(BOAT,hull,Vector3(box.end.x+0.8,box.position.y+0.1,box.get_center().z),2.4)

func _make_interaction(route: StringName, target: Node3D, spot: Vector3, radius: float) -> void:
	var marker := Marker3D.new()
	marker.name = "DisruptorPoint" if route == DEVICE else "BoatModulePoint"
	marker.position = spot
	target.add_child(marker)
	var trigger = INTERACTION.new()
	trigger.name = "FinaleInteraction"
	trigger.story = self
	trigger.route = route
	trigger.radius = radius
	marker.add_child(trigger)
	_triggers[route] = trigger
	var prototype := NOTE.instantiate()
	var light: CPUParticles3D = prototype.get_node("SoftSparkles")
	prototype.remove_child(light)
	prototype.free()
	light.position = Vector3(0,0.3,0)
	light.amount = 10
	light.emission_sphere_radius = 0.35
	trigger.add_child(light)
	_lights[route] = light

func pile_event(index: int) -> StringName:
	return StringName("harbor_pile_%02d" % index)

func _spawn_pile(index: int) -> void:
	if Quests.event_count(pile_event(index)) > 0:
		return
	var local_spot := Vector3(PILE_SPOTS[index].x,0.02,PILE_SPOTS[index].y)
	# The yard/apron are horizontal authored surfaces. Following the harbor keeps
	# litter above those surfaces rather than burying it in the terrain beneath.
	var world_spot := harbor.to_global(local_spot)
	var height: float = terrain.data.get_height(world_spot) if terrain and terrain.data else NAN
	if not is_nan(height):
		world_spot.y = maxf(world_spot.y,height+0.02)
	var pile: Clearable = LITTER[index % LITTER.size()].instantiate()
	pile.name = "HarborScrap%02d" % index
	pile.required_ability = &"finale_access"
	pile.locked_key = "FINALE_PILE_LOCKED"
	pile.message_key = "FINALE_COLLECT_PART"
	pile.position = to_local(world_spot)
	pile.rotation.y = index * 1.7
	pile.cleared.connect(_on_pile_cleared.bind(index))
	add_child(pile)
	_piles.append(pile)

func _on_pile_cleared(_pile: Clearable, index: int) -> void:
	if not available() or Quests.event_count(pile_event(index)) > 0:
		return
	Quests.report(pile_event(index))
	if Quests.event_count(PARTS) < PARTS_NEEDED:
		Quests.report(PARTS)

func ending_route() -> StringName:
	if Quests.event_count(&"ending_disruptor") > 0:
		return DEVICE
	if Quests.event_count(&"ending_boat") > 0:
		return BOAT
	return &""

func available() -> bool:
	return Quests.status(QUEST) == Quests.Status.ACTIVE and ending_route() == &""

func can_choose(route: StringName) -> bool:
	return route in [DEVICE,BOAT] and available() and not busy and Quests.has_ability(MODULE) \
		and (route == DEVICE or Quests.event_count(PARTS) >= PARTS_NEEDED)

func prompt_key(route: StringName) -> String:
	if not Quests.has_ability(MODULE):
		return "FINALE_MODULE_LOCKED"
	if route == BOAT and Quests.event_count(PARTS) < PARTS_NEEDED:
		return "FINALE_PARTS_LOCKED"
	return "FINALE_START_DEVICE" if route == DEVICE else "FINALE_START_BOAT"

func _refresh() -> void:
	if _refreshing:
		return
	_refreshing = true
	if available():
		Quests.grant(&"finale_access")
	for route in _lights:
		_lights[route].emitting = available()
	if ending_route() != &"" and not _presented:
		_presented = true
		_present_ending.call_deferred()
	_refreshing = false

func request_ending(route: StringName) -> void:
	if not can_choose(route) or get_tree().paused or SceneRouter.is_busy():
		return
	var dialogic := get_node_or_null(^"/root/Dialogic")
	if dialogic and dialogic.current_timeline != null:
		return
	busy = true
	var scene := get_tree().current_scene
	var was_paused := get_tree().paused
	var mouse_mode := Input.mouse_mode
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var key := "FINALE_CONFIRM_DEVICE" if route == DEVICE else "FINALE_CONFIRM_BOAT"
	var accepted: bool = await ConfirmPopup.ask(self,tr(key),"FINALE_CONFIRM_START",true)
	if not is_inside_tree() or get_tree().current_scene != scene or SceneRouter.is_busy():
		busy = false
		return
	# Revalidate after the modal closes. Cancel never spends the module or parts.
	busy = false
	var chosen := accepted and commit_ending(route)
	if not chosen:
		get_tree().paused = was_paused
		Input.mouse_mode = mouse_mode

func commit_ending(route: StringName) -> bool:
	if not can_choose(route):
		return false
	var index := 0 if route == DEVICE else 1
	if not Quests.complete_choice(QUEST,index,MODULE):
		return false
	if route == BOAT and Quests.event_count(&"boat_module_installed") == 0:
		Quests.report(&"boat_module_installed")
	return true

func get_ending_focus(route: StringName) -> Node3D:
	return _triggers.get(route)

func _present_ending() -> void:
	var route := ending_route()
	if route == &"" or not is_inside_tree():
		return
	var camera = cameras.get(route)
	if is_instance_valid(camera):
		camera.make_current()
	ending_selected.emit(route,get_ending_focus(route))
	_ending_screen = ENDING_SCREEN.new()
	_ending_screen.route = route
	get_tree().root.add_child(_ending_screen)
	tree_exiting.connect(_ending_screen.queue_free)
