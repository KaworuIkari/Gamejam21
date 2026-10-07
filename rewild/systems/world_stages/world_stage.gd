class_name WorldStage extends Resource
## One look of the world (e.g. "Wasteland", "Revival", "Golden hour").
## WorldStages blends from the current stage to this one, then runs its growth event.

enum GrowthEvent {
	NONE,       ## leave the growth map as it is
	BLOOM,      ## green spreads from the focus node out to growth_radius
	REVEAL_ALL, ## green spreads from the focus node across the whole map
	CLEAR,      ## back to barren (useful for debugging / a new game)
}

@export var stage_name := "Stage"
@export var transition_time := 6.0

@export_group("Sun")
@export var sun_rotation_degrees := Vector3(-45, -30, 0)
@export var sun_color := Color(1, 0.96, 0.88)
@export var sun_energy := 1.4

@export_group("Sky")
@export var sky_zenith := Color(0.14, 0.52, 0.92)
@export var sky_horizon := Color(0.70, 0.86, 0.97)
@export var sky_cloud_light := Color(1, 1, 1)
@export var sky_cloud_shade := Color(0.66, 0.76, 0.90)
@export_range(0.0, 1.0) var sky_cloud_coverage := 0.5

@export_group("Atmosphere")
@export var fog_color := Color(0.74, 0.85, 0.97)
@export var fog_density := 0.0006
@export var fog_height_density := 0.006
@export var fog_sun_scatter := 0.08
@export var ambient_energy := 1.0
@export var exposure := 1.0
@export var saturation := 1.05

@export_group("Distant clouds")
@export var bank_light := Color(1, 1, 1)
@export var bank_shade := Color(0.70, 0.80, 0.93)

@export_group("Water")
## Water plane height relative to its resting level. Negative hides it below
## the pond beds (dry basins); 0 = full ponds.
@export var water_offset := 0.0

@export_group("Growth")
@export var growth_event := GrowthEvent.NONE
@export var growth_radius := 40.0
@export var growth_duration := 6.0
