extends Node3D


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
@onready var terrain: Terrain3D = $NavigationRegion3D/Terrain3D
@onready var player_camera: Camera3D = $SubViewportContainer/PixelateSubViewport/LIRA/CameraPivot/SpringArm3D/Camera3D


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
	for mat in TREE_LEAVES:
		GrowthMap.attach_material(mat)
	GrowthMap.attach_material(GROW_IN_FLOWERS)
	add_child(PAUSE_MENU.instantiate())

func _process(delta: float) -> void:
	# UI 补丁：存档里的游戏时长
	SaveManager.add_play_time(delta)
