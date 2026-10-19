extends Node3D

## temp: for testing only
@onready var world_bgm : FmodEventEmitter2D = $WorldBGM
## temp: debug height fade. Remove when done.
const DBG_LOW_Y := 30.0    # SFX full, BGM silent
const DBG_HIGH_Y := 40.0   # SFX silent, BGM full

func _debug_height_volumes() -> void:
	var t := clampf(inverse_lerp(DBG_LOW_Y, DBG_HIGH_Y, player.global_position.y), 0.0, 1.0)
	_debug_set_bus_volume("bus:/SFX", 1.0 - t)
	_debug_set_bus_volume("bus:/BGM", t)

## temp: debug. Check the bus path and set_volume name against your GDExtension docs.
func _debug_set_bus_volume(path: String, v: float) -> void:
	# Keep the height test; multiply its gain by the user's audio setting.
	SettingsManager.set_fmod_mix(path, v)


const PAUSE_MENU = preload("res://ui/in_game/pause_menu.tscn")
## Leaf materials of the stylized_nature trees (set as external materials in their
## .gltf imports): their leaves grow in with the GrowthMap under each tree.
const TREE_LEAVES: Array[ShaderMaterial] = [
	preload("res://assets/models/stylized_nature/Materials/leaves_normal_tree.tres"),
	preload("res://assets/models/stylized_nature/Materials/leaves_pine.tres"),
	preload("res://assets/models/stylized_nature/Materials/leaves_twisted_tree.tres"),
]
## Petal_*.gltf material: hand-placed or scattered petals only appear on green ground.
const GROW_IN_FLOWERS := preload("res://assets/models/stylized_nature/Materials/flowers_grow_in.tres")
## Lake / forest / mountain / factory areas measured for the restoration percentages
## (open the scene to move or resize them).
const RESTORATION_REGIONS := preload("res://levels/meadow_hand/restoration_regions.tscn")
## Throwing little Leon (Leon2) into the frog lake raises the giant Leon from the sea.
const LeonAwakening := preload("res://levels/meadow_hand/leon_awakening.gd")
## Green ground around the pump house at the start of a new game, in metres.
const PUMP_HOUSE_GREEN_RADIUS := 25.0
## Plain trees report "tree_restored" too, once the ground under them is green.
const TreeRegrowth := preload("res://systems/world_objects/tree_regrowth.gd")
## Radar mission progression and cabinet interaction.
const FinaleStory = preload("res://levels/meadow_hand/finale_story.gd")
@export var finale_disruptor_camera: Camera3D
@export var finale_boat_camera: Camera3D
## The jetpack prop in the factory power room; the repaired bot fetches it. Empty = the node
## named "Jetpack" directly in this level (not LIRA's).
@export var factory_jetpack: Node3D
## Optional way into the power room: a Node3D whose child Marker3Ds are points in order,
## from the ground outside to the jetpack (ground → window sill → floor inside). Empty =
## the bot finds the window itself.
@export var factory_jetpack_route: Node3D
const RadarStory = preload("res://levels/meadow_hand/radar_story.gd")
## Permanent green patches at the start of a new game (nothing is kept dormant now: animals
## are live from the start; the fox lies hurt until rescued, the bot sleeps in FactoryStory).
const InitialState := preload("res://levels/meadow_hand/initial_state.gd")
const OpeningSequence := preload("res://levels/meadow_hand/opening_sequence.gd")
const StartupChecks := preload("res://levels/meadow_hand/startup_checks.gd")
const CabinStory := preload("res://levels/meadow_hand/cabin_story.gd")
const PUMP_PATH := ^"Enviroment/North_water_source/Ruined_Pump_House_Golden/WaterFlowSwitch"
@onready var terrain: Terrain3D = $NavigationRegion3D/Terrain3D
@onready var player_camera: Camera3D = $SubViewportContainer/PixelateSubViewport/LIRA/Camera3D
@onready var player: Node3D = $SubViewportContainer/PixelateSubViewport/LIRA

func _enter_tree() -> void:
	# Before the player's _ready, so LIRA starts with the saved abilities.
	var quests := get_node_or_null(^"/root/Quests")
	if quests:
		CabinStory.migrate_save(SaveManager.current_data)
		quests.load_from_save()
	get_node(PUMP_PATH).start_on = quests.event_count(&"pump_started") > 0

func _ready() -> void:
	var opening := OpeningSequence.new()
	opening.name = "OpeningSequence"
	opening.player = player
	add_child(opening)
	var startup := StartupChecks.new()
	startup.name = "StartupChecks"
	startup.player = player
	add_child(startup)
	var cabin := CabinStory.new()
	cabin.name = "CabinStory"
	cabin.pump = get_node(PUMP_PATH)
	add_child(cabin)
	terrain.set_camera(player_camera)
	GrowthMap.attach_terrain(terrain)
	GrowthMap.attach_material($Plants/Grass.mesh_material_override)
	GrowthMap.attach_material($Plants/Flowers.mesh_material_override)
	for mat in TREE_LEAVES:
		GrowthMap.attach_material(mat)
	GrowthMap.attach_material(GROW_IN_FLOWERS)

	var restoration_regions := RESTORATION_REGIONS.instantiate()
	add_child(restoration_regions)
	# The playable mountain is the radar hill. Follow its placed anchor each load.
	restoration_regions.get_node("Mountain").global_position = $Enviroment/East_Mountain/RadioObservatory.global_position
	var awakening := LeonAwakening.new()
	awakening.name = "LeonAwakening"
	awakening.statue = $Enviroment/North_frog_lake/Leon2
	awakening.lake = $SubViewportContainer/PixelateSubViewport/Water/Froglake
	awakening.giant = $Enviroment/North_frog_lake/Leon
	awakening.sea = $SubViewportContainer/PixelateSubViewport/Water/Sea
	awakening.requires = $Enviroment/North_water_source/Ruined_Pump_House_Golden/WaterFlowSwitch
	add_child(awakening)
	var initial := InitialState.new()
	initial.name = "InitialState"
	initial.green_spots = {$Enviroment/North_water_source/Ruined_Pump_House_Golden: PUMP_HOUSE_GREEN_RADIUS}
	add_child(initial)
	var factory := FactoryStory.new()
	factory.name = "FactoryStory"
	factory.anchor = $Enviroment/East_Robot_factory/DesertRoboticsLaboratory
	factory.terrain = terrain
	factory.companion = $SubViewportContainer/PixelateSubViewport/CubeBotCompanion
	factory.jetpack_prop = factory_jetpack if factory_jetpack else _find_jetpack_prop()
	factory.route = factory_jetpack_route
	add_child(factory)
	var radar := RadarStory.new()
	radar.name = "RadarStory"
	radar.anchor = $Enviroment/East_Mountain/RadioObservatory
	radar.terrain = terrain
	add_child(radar)
	var finale := FinaleStory.new()
	finale.name = "FinaleStory"
	finale.radar = $Enviroment/East_Mountain/RadioObservatory
	finale.harbor = $Enviroment/South_Harbour/IslandHarbor
	finale.terrain = terrain
	finale.cameras = {&"disruptor":finale_disruptor_camera,&"boat":finale_boat_camera}
	add_child(finale)
	var battery := BatteryCharge.new()
	battery.name = "BatteryCharge"
	add_child(battery)
	var regrowth := TreeRegrowth.new()
	regrowth.name = "TreeRegrowth"
	add_child(regrowth)
	add_child(PAUSE_MENU.instantiate())
	_debug_height_volumes()
	SettingsManager.refresh_fmod_audio()
	world_bgm.play()

func _process(delta: float) -> void:
	# UI 补丁：存档里的游戏时长
	SaveManager.add_play_time(delta)
	_debug_height_volumes()

func _exit_tree() -> void:
	SettingsManager.reset_fmod_mix()


## The power-room jetpack when the export is empty: a node named "Jetpack" outside LIRA.
func _find_jetpack_prop() -> Node3D:
	for node in find_children("Jetpack", "Node3D", true, false):
		if not player.is_ancestor_of(node):
			return node
	return null
