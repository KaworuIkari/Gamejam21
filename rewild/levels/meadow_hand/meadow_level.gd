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
	var bus = FmodServer.get_bus(path)
	if bus:
		bus.set_volume(v)


const PAUSE_MENU = preload("res://ui/in_game/pause_menu.tscn")
@onready var terrain: Terrain3D = $NavigationRegion3D/Terrain3D
@onready var player_camera: Camera3D = $SubViewportContainer/PixelateSubViewport/LIRA/CameraPivot/SpringArm3D/Camera3D
@onready var player: Node3D = $SubViewportContainer/PixelateSubViewport/LIRA

func _enter_tree() -> void:
	# Before the player's _ready, so LIRA starts with the saved abilities.
	var quests := get_node_or_null(^"/root/Quests")
	if quests:
		quests.load_from_save()

func _ready() -> void:
	terrain.set_camera(player_camera)
	GrowthMap.attach_terrain(terrain)
	GrowthMap.attach_material($Plants/Grass.mesh_material_override)
	GrowthMap.attach_material($Plants/Flowers.mesh_material_override)
	add_child(PAUSE_MENU.instantiate())
	world_bgm.play()

func _process(delta: float) -> void:
	# UI 补丁：存档里的游戏时长
	SaveManager.add_play_time(delta)
	_debug_height_volumes()