extends Node3D

const PAUSE_MENU = preload("res://ui/in_game/pause_menu.tscn")
## Leaf materials of the stylized_nature trees (set as external materials in their
## .gltf imports) and the FantasyForest giant tree: their leaves grow in with the
## GrowthMap under each tree.
const TREE_LEAVES: Array[ShaderMaterial] = [
	preload("res://assets/models/stylized_nature/Materials/leaves_normal_tree.tres"),
	preload("res://assets/models/stylized_nature/Materials/leaves_pine.tres"),
	preload("res://assets/models/stylized_nature/Materials/leaves_twisted_tree.tres"),
	preload("res://assets/models/fantasy_forest_sample/textures/mytex/tree_leaves_mat.tres"),
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
## The jetpack prop in the factory power room; the repaired bot fetches it (with everything
## under it). Empty = the node named "Jetpack_root", else "Jetpack", in this level (not LIRA's).
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
	add_child(LeafRustle.new())
	var trample := GrassTrample.new()
	trample.material = $Plants/Grass.mesh_material_override
	trample.player = player
	add_child(trample)
	GrowthMap.attach_material(GROW_IN_FLOWERS)

	var restoration_regions := RESTORATION_REGIONS.instantiate()
	add_child(restoration_regions)
	# The playable mountain is the radar hill. Follow its placed anchor each load.
	restoration_regions.get_node("Mountain").global_position = $Enviroment/East_Mountain/RadioObservatory.global_position
	_add_region_haze(restoration_regions)
	var awakening := LeonAwakening.new()
	awakening.name = "LeonAwakening"
	awakening.statue = $Enviroment/North_frog_lake/Leon2
	awakening.lake = $SubViewportContainer/PixelateSubViewport/Water/Froglake
	awakening.giant = $Enviroment/North_frog_lake/Leon
	awakening.sea = $SubViewportContainer/PixelateSubViewport/Water/Sea
	awakening.requires = $Enviroment/North_water_source/Ruined_Pump_House_Golden/WaterFlowSwitch
	add_child(awakening)
	awakening.awakening_started.connect(_on_leon_awakening_started)
	awakening.awakening_finished.connect(_on_leon_awakening_finished)
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
	finale.harbor = get_node_or_null("Enviroment/South_Harbour/IslandHarbor2")
	if finale.harbor == null:
		finale.harbor = get_node_or_null("Enviroment/South_Harbour/IslandHarbor")
	finale.cameras = {&"disruptor":finale_disruptor_camera,&"boat":finale_boat_camera}
	add_child(finale)
	# Every well can be started and then used to fill the tank; lakes and rivers fill it too.
	_set_up_wells($Enviroment/Global/Wells)
	$SubViewportContainer/PixelateSubViewport/Water/Sea.drinkable = false
	var refill := WaterRefill.new()
	refill.name = "WaterRefill"
	add_child(refill)
	var regrowth := TreeRegrowth.new()
	regrowth.name = "TreeRegrowth"
	add_child(regrowth)
	var sky := SkyProgression.new()
	sky.name = "SkyProgression"
	sky.environment = $WorldEnvironment
	sky.pump = get_node(PUMP_PATH)
	add_child(sky)
	add_child(PAUSE_MENU.instantiate())
	SettingsManager.refresh_fmod_audio()

func _process(delta: float) -> void:
	# UI 补丁：存档里的游戏时长
	SaveManager.add_play_time(delta)

func _exit_tree() -> void:
	SettingsManager.reset_fmod_mix()


## Dust haze over every restoration region until it is cleaned (the lake's clears when the
## pump fills it, sweeping out from the lake station), and a sandstorm around the camera
## that blows wherever the ground is still barren.
func _add_region_haze(regions: Node) -> void:
	var storm := SandStorm.new()
	storm.name = "SandStorm"
	storm.camera = player_camera
	storm.environment = $WorldEnvironment
	for region in regions.get_children():
		var haze := RegionHaze.new()
		haze.name = "Haze_%s" % region.name
		haze.region = region
		haze.terrain = terrain
		haze.floor_y = $SubViewportContainer/PixelateSubViewport/Water/Sea.global_position.y
		if region.region_id == &"lake":
			haze.clear_when = get_node(PUMP_PATH)
			haze.clear_from = $Enviroment/Central_lake/LakePowerStation
		haze.wind = storm.wind
		storm.hazes[region] = haze
		add_child(haze)
	add_child(storm)


## The power-room jetpack when the export is empty: "Jetpack_root" (the jetpack and its
## extras), else a node named "Jetpack", outside LIRA.
func _find_jetpack_prop() -> Node3D:
	for prop_name in ["Jetpack_root", "Jetpack"]:
		for node in find_children(prop_name, "Node3D", true, false):
			if not player.is_ancestor_of(node):
				return node
	return null


func _on_leon_awakening_started() -> void:
	BgmPlayer._play_epic_bgm()

func _on_leon_awakening_finished() -> void:
	BgmPlayer.release(5.0)  # optional: bring world music back after a long silence


## A WaterWell on every well, with the water that rises when it starts: each MeshInstance3D
## placed directly under any well goes to the well it actually sits in (nearest); wells
## without one get a copy of the first, at the same spot relative to the well.
func _set_up_wells(wells_root: Node3D) -> void:
	var wells: Array[Node3D] = []
	var waters: Array[MeshInstance3D] = []
	var controllers := {}
	for well in wells_root.get_children():
		if not well is Node3D:
			continue
		wells.append(well)
		var existing := well.find_children("*", "WaterWell", false, false)
		var controller: WaterWell = existing[0] if not existing.is_empty() else WaterWell.new()
		controller.name = "WaterWell"
		controllers[well] = controller
		for child in well.get_children():
			if child is MeshInstance3D:
				waters.append(child)
	var template: MeshInstance3D = null
	var template_offset := Transform3D()
	for water in waters:
		var nearest: Node3D = wells[0]
		for well in wells:
			if _flat_distance(well, water) < _flat_distance(nearest, water):
				nearest = well
		controllers[nearest].rise.append(water)
		if template == null:
			template = water
			template_offset = nearest.global_transform.affine_inverse() * water.global_transform
	for well in wells:
		var controller: WaterWell = controllers[well]
		if controller.rise.is_empty() and template:
			var copy := template.duplicate() as MeshInstance3D
			copy.name = "WellWater"
			well.add_child(copy)
			copy.global_transform = well.global_transform * template_offset
			controller.rise.append(copy)
		if not controller.is_inside_tree():
			well.add_child(controller)


func _flat_distance(a: Node3D, b: Node3D) -> float:
	return Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()
