extends Node3D
## Mutually exclusive finale. The boat uses recorded coordinates and the lake battery.
## Future cinematics can connect ending_selected and use get_ending_focus().
signal ending_selected(route: StringName, focus: Node3D)
const QUEST = preload("res://quests/06_final_choice.tres")
const PREVIOUS = preload("res://quests/05_radar_station.tres")
const INTERACTION = preload("res://levels/meadow_hand/finale_interaction.gd")
const ENDING_SCREEN = preload("res://ui/in_game/ending/ending_screen.gd")
const NOTE = preload("res://objects/interactables/readables/readable_note.tscn")
const MODULE := &"chaos_energy_module"
const DEVICE := &"disruptor"
const BOAT := &"boat"
## Navigation coordinates read at the radar and typed on the boat's pad (digits 1–9 only).
const COORDINATES := "3729"
var radar: Node3D
var harbor: Node3D
var cameras: Dictionary = {}
var busy := false
var _refreshing := false
var _presented := false
var _triggers: Dictionary = {}
var _lights: Dictionary = {}
var _ending_screen: CanvasLayer

func _ready() -> void:
	if not is_instance_valid(radar) or not is_instance_valid(harbor):
		push_error("FinaleStory requires the existing radar and harbor")
		return
	_make_disruptor()
	_make_boat()
	Quests.changed.connect(_refresh)
	_refresh()

func _make_disruptor() -> void:
	var platform := radar.get_node("Model/Service_Platform") as MeshInstance3D
	var box := platform.get_aabb()
	var spot := Vector3(box.get_center().x,box.end.y+0.5,box.get_center().z)
	_make_interaction(DEVICE,platform,spot,1.7)

func _make_boat() -> void:
	var core := harbor.get_node("DepartureCore") as Node3D
	_make_interaction(BOAT,core.get_node("InteractionPoint"),Vector3.ZERO,2.4)

func boat_available() -> bool:
	return ending_route() == &""

func boat_powered() -> bool:
	return Quests.event_count(&"boat_battery_installed") > 0

## First use: type the coordinates on the pad. Then: install the battery.
func advance_boat_setup() -> void:
	if not can_choose(BOAT):
		return
	if Quests.event_count(&"boat_coordinates_loaded") == 0:
		busy = true
		var entered: bool = await CoordinatePad.ask(self, COORDINATES)
		busy = false
		if entered and is_inside_tree():
			Quests.report(&"boat_coordinates_loaded")
		return
	if not boat_powered():
		Quests.consume_and_report(&"battery",&"boat_battery_installed")

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

func ending_route() -> StringName:
	if Quests.event_count(&"ending_disruptor") > 0:
		return DEVICE
	if Quests.event_count(&"ending_boat") > 0:
		return BOAT
	return &""

func available() -> bool:
	return Quests.status(QUEST) == Quests.Status.ACTIVE and ending_route() == &""

func can_choose(route: StringName) -> bool:
	if busy or ending_route() != &"":
		return false
	if route == BOAT:
		if Quests.event_count(&"radar_coordinates") == 0:
			return false
		if Quests.event_count(&"boat_coordinates_loaded") == 0:
			return true
		if not boat_powered():
			return Quests.has_ability(&"battery")
		return available()
	return route == DEVICE and available() and Quests.has_ability(MODULE)

func prompt_key(route: StringName) -> String:
	if route == BOAT:
		# Same order as the setup: coordinates first, then the battery.
		if Quests.event_count(&"radar_coordinates") == 0:
			return "HARBOR_COORDINATES_REQUIRED"
		if Quests.event_count(&"boat_coordinates_loaded") == 0:
			return "HARBOR_LOAD_COORDINATES"
		if not boat_powered():
			return "HARBOR_INSERT_BATTERY" if Quests.has_ability(&"battery") else "HARBOR_BATTERY_REQUIRED"
		return "HARBOR_DEPART"
	return "FINALE_START_DEVICE" if Quests.has_ability(MODULE) else "FINALE_MODULE_LOCKED"

func _refresh() -> void:
	if _refreshing:
		return
	_refreshing = true
	harbor.get_node("DepartureCore").activated = boat_powered() or ending_route() == BOAT
	for route in _lights:
		_lights[route].emitting = boat_available() if route == BOAT else available()
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
	if route == BOAT and (Quests.event_count(&"boat_coordinates_loaded") == 0 or not boat_powered()):
		advance_boat_setup()
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
	# Revalidate after the modal closes. Cancel leaves the powered boat ready.
	busy = false
	var chosen := accepted and commit_ending(route)
	if not chosen:
		get_tree().paused = was_paused
		Input.mouse_mode = mouse_mode

func commit_ending(route: StringName) -> bool:
	if not can_choose(route) or (route == BOAT and (not boat_powered() or Quests.event_count(&"boat_coordinates_loaded") == 0)):
		return false
	var index := 0 if route == DEVICE else 1
	if not Quests.complete_choice(QUEST,index,MODULE if route == DEVICE else &""):
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
