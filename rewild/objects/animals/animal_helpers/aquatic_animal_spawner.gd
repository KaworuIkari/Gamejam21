@tool
extends AnimalSpawner
class_name AquaticAnimalSpawner

## Aquatic variant of AnimalSpawner.
## Inherits ALL editor behavior (debug radius circle, selection visibility, radius rebuild) from parent.
## Only replaces navigation mesh spawn logic with WaterVolume-based underwater sampling.

@export var water_volume: WaterVolume
@export var min_spawn_depth := 2.0   # min distance below water surface
@export var max_spawn_depth := 12.0  # max distance below water surface
@export var max_spawn_retries := 20  # fail-safe: prevent infinite loop on landlocked spots

# Override parent: remove nav mesh wait, use WaterVolume validation
func spawn_all() -> void:
	if water_volume == null:
		push_error("AquaticAnimalSpawner: assign WaterVolume in inspector")
		return
	for i in count:
		spawn_one()

# Override parent: sample random valid underwater point instead of nav mesh
func spawn_one(_map: RID = RID()) -> Node3D:
	for retry in max_spawn_retries:
		# Random horizontal point within radius disc
		var angle := randf() * TAU
		var dist := sqrt(randf()) * radius
		var world_xz := Vector2(
			global_position.x + cos(angle) * dist,
			global_position.z + sin(angle) * dist
		)

		# Validate water column at this XZ
		var band := water_volume.get_safe_band(world_xz, 0.1)
		if band.x > band.y:
			continue  # invalid: land, hole, or too shallow

		var surface_y := water_volume._surface_y
		var spawn_min_y := maxf(band.x, surface_y - max_spawn_depth)
		var spawn_max_y := minf(band.y, surface_y - min_spawn_depth)

		if spawn_min_y > spawn_max_y:
			continue  # depth range doesn't fit

		# Pick random depth in valid range
		var spawn_pos := Vector3(
			world_xz.x,
			randf_range(spawn_min_y, spawn_max_y),
			world_xz.y
		)

		# Spawn and place
		var animal := animal_scene.instantiate() as AnimalSmallFish
		animal.rotation.y = randf() * TAU
		animal.water_volume = water_volume
		add_child(animal)
		animal.global_position = spawn_pos
		return animal

	# No valid spot found after retries
	push_warning("AquaticAnimalSpawner: no valid water spot found after %d retries" % max_spawn_retries)
	return null
