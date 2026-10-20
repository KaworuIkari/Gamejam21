extends Node
## Water the gun leaves on the ground. Add as an autoload named "Puddles".
##
## Each splash pours into a small water grid (a Puddle) laid over the Terrain3D
## heights. The water runs downhill and levels out, then evaporates by depth:
## a connected body of water that is nowhere deeper than keep_depth is just a wet
## film and dries in seconds, while water that collects in a dip at least that
## deep stays as a pool. So carve small pits in the terrain wherever water should stay.

const Puddle := preload("res://systems/puddles/puddle.gd")

@export var enabled := true
## Cubic metres of water one blob leaves on the ground.
@export var blob_volume := 1
## Metres around the hit point the blob's water lands on.
@export var pour_radius := 0.8
## Blobs that hit something this far (metres) above the terrain (rocks, props) leave no water.
@export var max_ground_gap := 0.6

@export_group("Grid")
## Metres per water cell. Smaller = finer shorelines, more cost.
@export var cell_size := 0.35
## Cells per side of one puddle grid (cell_size * cells = metres covered).
@export var cells := 64

@export_group("Evaporation")
## A body of water this deep somewhere (metres) counts as a pool and stays.
@export var keep_depth := 0.08
## Metres of depth per second a shallow film loses (0.006 = a 1 cm film dries in under 2 s).
@export var film_evaporation := 0.004
## Metres of depth per second a pool loses. 0 = pools never dry up.
@export var pool_evaporation := 0.0002

@export_group("Flow")
## Share of the height difference that moves per substep (max 0.25 for stability).
@export_range(0.01, 0.25) var flow := 0.15
## Flow substeps per physics frame. More = water runs faster.
@export var substeps := 1

@export_group("Greening")
## Ground under the water gets wet on the GrowthMap, so it greens wherever the water
## runs or pools, not only where the blob landed.
@export var green_ground := true
## Water this deep (metres) soaks the ground fully; shallower water wets it less.
@export var green_full_depth := 0.01
## Seconds between handing the wet ground to the GrowthMap.
@export var green_interval := 0.3

@export_group("Look")
@export var material: ShaderMaterial = preload("res://systems/puddles/puddle_material.tres")

var _terrain: Terrain3D
var _puddles: Array[Node] = []


## Pours water onto the ground at a world position. volume < 0 uses blob_volume.
func pour(world_pos: Vector3, volume: float = -1.0, radius: float = -1.0) -> void:
	if not enabled:
		return
	var terrain := _find_terrain()
	if terrain == null:
		return
	var h := terrain.data.get_height(world_pos)
	if is_nan(h) or absf(world_pos.y - h) > max_ground_gap:
		return
	if volume < 0.0:
		volume = blob_volume
	if radius < 0.0:
		radius = pour_radius
	_puddle_at(world_pos, terrain).pour(world_pos, volume, radius)


## Water depth (metres) at a world position, 0 if dry. For gameplay (plants, animals drinking).
func depth_at(world_pos: Vector3) -> float:
	for p in _puddles:
		if is_instance_valid(p) and p.contains(world_pos, 0):
			return p.depth_at(world_pos)
	return 0.0


## Removes all standing water.
func clear() -> void:
	for p in _puddles:
		if is_instance_valid(p):
			p.queue_free()
	_puddles.clear()


func _puddle_at(world_pos: Vector3, terrain: Terrain3D) -> Node:
	_puddles = _puddles.filter(func(p): return is_instance_valid(p))
	for p in _puddles:
		if p.contains(world_pos, 3):
			return p
	var p := Puddle.new()
	p.settings = self
	p.material_override = material
	get_tree().current_scene.add_child(p)
	p.setup(terrain, world_pos)
	_puddles.append(p)
	return p


func _find_terrain() -> Terrain3D:
	if _terrain == null or not is_instance_valid(_terrain) or not _terrain.is_inside_tree():
		_terrain = null
		var found := get_tree().root.find_children("*", "Terrain3D", true, false)
		if not found.is_empty() and found[0].data != null:
			_terrain = found[0]
	return _terrain
