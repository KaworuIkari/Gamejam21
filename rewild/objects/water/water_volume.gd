# WaterVolume.gd
extends Node3D
class_name WaterVolume

## Reusable water volume: bounds = above seabed terrain, below sea plane surface
## Extracted directly from AnimalShark.gd sea logic for shared use

@export var sea_plane: MeshInstance3D
@export_flags_3d_physics var seabed_mask := 1
@onready var terrain: Terrain3D = get_node_or_null("/root/Node3D/Terrain3D")

var _surface_y := 0.0
var _sea_min := Vector2.ZERO
var _sea_max := Vector2.ZERO
var _terrain_data: Object

func _ready() -> void:
	if sea_plane == null:
		push_error("WaterVolume: assign sea_plane in inspector")
		set_process(false)
		return
	add_to_group(&"water_volumes")   # lets characters find every water body
	_setup_sea()

## Call if sea_plane moves or resizes at runtime.
func refresh_bounds() -> void:
	_setup_sea()

func _setup_sea() -> void:
	var aabb := sea_plane.global_transform * sea_plane.get_aabb()
	_surface_y = sea_plane.global_position.y
	_sea_min = Vector2(aabb.position.x, aabb.position.z)
	_sea_max = _sea_min + Vector2(aabb.size.x, aabb.size.z)
	if terrain:
		_terrain_data = terrain.get("data")
		if _terrain_data == null:
			_terrain_data = terrain.get("storage")

## Seabed height at XZ; returns NAN in holes / outside terrain
func get_seabed_height(xz: Vector2) -> float:
	if _terrain_data and _terrain_data.has_method("get_height"):
		return _terrain_data.get_height(Vector3(xz.x, 0.0, xz.y))
	var from := Vector3(xz.x, _surface_y, xz.y)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1000.0, seabed_mask)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return NAN if r.is_empty() else r.position.y

## Seabed normal at XZ, sampled over radius e
func get_seabed_normal(xz: Vector2, e: float) -> Vector3:
	var hx := get_seabed_height(xz + Vector2(e, 0)) - get_seabed_height(xz - Vector2(e, 0))
	var hz := get_seabed_height(xz + Vector2(0, e)) - get_seabed_height(xz - Vector2(0, e))
	if is_nan(hx) or is_nan(hz):
		return Vector3.UP
	return Vector3(-hx / (2.0 * e), 1.0, -hz / (2.0 * e)).normalized()

## Safe Y range for a creature with given room (radius + clearance)
## Returns Vector2(min_y, max_y); min > max = no valid water at this XZ
func get_safe_band(xz: Vector2, room: float) -> Vector2:
	var floor_y := -INF
	# Sample 9 points to account for body size
	for i in 9:
		var off := Vector2.ZERO if i == 0 else Vector2.from_angle(TAU * i / 8.0) * room
		var h := get_seabed_height(xz + off)
		if is_nan(h):
			return Vector2(1.0, -1.0) # Invalid: hole / out of bounds
		floor_y = maxf(floor_y, h)
	return Vector2(floor_y + room, _surface_y - room)

## Clamp a position to stay within valid water bounds
func clamp_to_water(position: Vector3, room: float) -> Vector3:
	var xz := clamp_xz(Vector2(position.x, position.z), room)
	var band := get_safe_band(xz, room)
	var y := clampf(position.y, band.x, band.y) if band.x <= band.y else _surface_y - room
	return Vector3(xz.x, y, xz.y)

## Clamp XZ to stay within sea plane edges, with margin
func clamp_xz(xz: Vector2, margin: float) -> Vector2:
	return Vector2(
		clampf(xz.x, _sea_min.x + margin, _sea_max.x - margin),
		clampf(xz.y, _sea_min.y + margin, _sea_max.y - margin)
	)

## Player-facing queries. These only read cached bounds and surface height,
## so they never touch the terrain or raycast the physics space.

## XZ point inside the sea plane footprint.
func contains_xz(xz: Vector2) -> bool:
	return xz.x >= _sea_min.x and xz.x <= _sea_max.x and xz.y >= _sea_min.y and xz.y <= _sea_max.y

func get_surface_y() -> float:
	return _surface_y

## Below the surface and inside the footprint.
func is_submerged_point(p: Vector3) -> bool:
	return p.y < _surface_y and contains_xz(Vector2(p.x, p.z))