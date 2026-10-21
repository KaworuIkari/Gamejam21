class_name FactoryStory
extends Node3D
## The factory: rescue the companion bot to get the jetpack (quest 04), everything in one place:
## - litter is scattered around the factory; clearing it counts as "garbage" like any other
##   pile (material for the water-gun upgrades at the terminal);
## - gears lie around from the start, picked up with interact ("factory_gear"): every
##   GearPickup placed in the level scene, or the GEAR_SPOTS fallback when none are placed;
## - the companion bot stands idle in the factory, eye dark, where it is placed in the level.
##   Near it the prompt shows the gear count; with every gear the bot glimmers and can be
##   repaired: it shakes, its eye lights yellow then blue ("core_activated");
## - the jetpack (`jetpack_prop`, placed in the locked power room, glimmering like the
##   tablets) is then fetched by the bot: it runs around buildings (a grid path checked
##   against colliders) to the outside of the power-room window, hops onto the sill and in,
##   picks the jetpack up, hops back out the same way and follows LIRA. The window is found by
##   casting rays from the jetpack (a wall at floor height, open higher up) unless `route`
##   gives the way in; once beside her it hands it over ("jetpack_delivered",
##   quest 04 grants the jetpack) and the jetpack fires a burst.
## The level creates this node and fills in the references below.

## Its SoftSparkles (the soft glimmer marking the first note) is reused on the sleeping bot.
const NOTE := preload("res://objects/interactables/readables/readable_note.tscn")
const LITTER: Array[PackedScene] = [
	preload("res://objects/clearable/garbage_dirty_litter_heap_1.tscn"),
	preload("res://objects/clearable/wreck_garbage_mixed_scrap.tscn"),
	preload("res://objects/clearable/garbage_litter_cluster_2.tscn"),
	preload("res://objects/clearable/wreck_frame_twisted_cables.tscn"),
	preload("res://objects/clearable/garbage_dirty_litter_heap_3.tscn"),
	preload("res://objects/clearable/wreck_slab_snapped_rebar.tscn"),
	preload("res://objects/clearable/garbage_litter_cluster_1.tscn"),
	preload("res://objects/clearable/wreck_tank_ripped_open.tscn"),
]
## Where litter lies, in metres from the factory anchor (outside the building).
const LITTER_SPOTS: Array[Vector2] = [
	Vector2(-14, 32), Vector2(0, 36), Vector2(14, 33), Vector2(28, 30), Vector2(40, 12),
	Vector2(42, -6), Vector2(-10, -30), Vector2(10, -32), Vector2(-40, 8), Vector2(-42, -10),
]
const GEAR := preload("res://objects/pickups/gear/gear_pickup.tscn")
## Fallback when no GearPickup is placed in the level: where gears float, in metres from
## the factory anchor. Collected ones are remembered per index (factory_gear_00..09).
const GEAR_SPOTS: Array[Vector2] = [
	Vector2(-22, 18), Vector2(-6, 24), Vector2(8, 22), Vector2(22, 18), Vector2(28, 2),
	Vector2(24, -18), Vector2(0, -22), Vector2(-24, -20), Vector2(-28, 0), Vector2(-4, 8),
]
const GEAR_HEIGHT := 0.8
## Gears needed to repair the bot; the gear step in quests/04_energy_core.tres asks the same.
const GEARS_NEEDED := 6
const GEAR_EVENT := &"factory_gear"
const ACTIVATED_EVENT := &"core_activated"
const DELIVERED_EVENT := &"jetpack_delivered"
## The bot hands the jetpack over this close to LIRA, in metres.
const HAND_OVER_DISTANCE := 2.5
## Where the carried jetpack sits on the bot, in the bot's space.
const CARRY_OFFSET := Vector3(0, 0.9, 0)
## Scripted fetch: run speed (m/s) on the ground, then hops (speed m/s, arc height m).
const RUN_SPEED := 4.8
const HOP_SPEED := 3.0
const HOP_HEIGHT := 0.6
## Window search: how far rays reach from the jetpack, the heights above the floor tried for
## the opening, the nearest a wall may be (closer = furniture) and how far outside it the
## bot lands.
const WINDOW_SCAN := 8.0
const WINDOW_HEIGHTS: Array[float] = [0.6, 0.9, 1.2, 1.5, 1.8]
const MIN_WINDOW_DEPTH := 2.5
const OUTSIDE_STEP := 1.5
## Ground path: grid cell size (m), extra margin around start and goal (cells), and the
## clearance the bot needs (radius of the probe sphere, m).
const PLAN_CELL := 1.0
const PLAN_MARGIN := 12
const BOT_RADIUS := 0.35

## The laboratory: everything is placed relative to it.
var anchor: Node3D
## Terrain3D, to put the litter on the ground.
var terrain: Node
## Sleeps in the factory until repaired, then follows LIRA.
var companion: CubeBotCompanion
## The jetpack prop in the power room (set by the level). Freed once handed over.
var jetpack_prop: Node3D
## Optional way in: Node3D whose children are points in order, from the ground outside to
## the jetpack (e.g. ground outside → window sill → floor inside). Empty = found by rays.
var route: Node3D

var _trigger: InteractTrigger
var _sparkles: CPUParticles3D
var _carrying := false


func _ready() -> void:
	for i in LITTER_SPOTS.size():
		_spawn_litter(i)
	_place_gears()
	if is_instance_valid(jetpack_prop):
		if Quests.event_count(DELIVERED_EVENT) > 0:
			jetpack_prop.queue_free()
		else:
			jetpack_prop.add_child(_note_sparkles())
	if is_instance_valid(companion):
		if _bot_awake():
			companion.active = true
			if Quests.event_count(DELIVERED_EVENT) == 0:
				_carry()  # a save made during the fetch: it already holds the jetpack
		else:
			_sleep()
	Quests.changed.connect(_check)
	_check()


func _process(_delta: float) -> void:
	# The bot lives in the pixel SubViewport; its trigger stays here and follows it.
	if is_instance_valid(_trigger) and is_instance_valid(companion):
		_trigger.global_position = companion.to_global(Vector3(0, 0.6, 0))
	if _carrying and companion.active:
		var lira := get_tree().get_first_node_in_group(&"player") as Node3D
		if lira and companion.global_position.distance_to(lira.global_position) < HAND_OVER_DISTANCE:
			_hand_over(lira)


func _spawn_litter(index: int) -> void:
	var spot := anchor.to_global(Vector3(LITTER_SPOTS[index].x, 0.0, LITTER_SPOTS[index].y))
	var height: float = terrain.data.get_height(spot) if terrain else NAN
	spot.y = anchor.global_position.y if is_nan(height) else height
	var litter: Clearable = LITTER[index % LITTER.size()].instantiate()
	# Placed before it enters the tree: Clearable remembers its start position in _ready
	# (for the hold shake), so moving it afterwards would snap it back to the origin.
	litter.position = to_local(spot)
	litter.rotation.y = index * 1.7
	add_child(litter)


func _bot_awake() -> bool:
	return Quests.event_count(ACTIVATED_EVENT) > 0


func _can_repair() -> bool:
	return Quests.event_count(GEAR_EVENT) >= GEARS_NEEDED


## Near the sleeping bot the prompt shows the gear count (greyed) until it can be repaired;
## then the bot glimmers and the prompt becomes usable.
func _check() -> void:
	if is_instance_valid(_trigger) and not _trigger._used:
		_sparkles.emitting = _can_repair()
	if _trigger or not is_instance_valid(companion) or _bot_awake():
		return
	_trigger = InteractTrigger.new()
	_trigger.name = "RobotRepair"
	_trigger.message_key = "INTERACT_ROBOT_REPAIR"
	_trigger.radius = 3.0
	_trigger.can_interact = _can_repair
	_trigger.locked_text = _repair_locked_text
	add_child(_trigger)
	_trigger.global_position = companion.to_global(Vector3(0, 0.6, 0))
	_trigger.interacted.connect(_repair)
	_sparkles = _make_sparkles()
	_sparkles.emitting = _can_repair()
	_trigger.add_child(_sparkles)


func _repair_locked_text() -> String:
	var gears := mini(Quests.event_count(GEAR_EVENT), GEARS_NEEDED)
	return tr("ROBOT_REPAIR_GEARS").format({"count": gears, "total": GEARS_NEEDED})


## Hand-placed gears are remembered by their path in the level (factory_gear_<path>), so
## renaming or moving one to another parent after a save makes it collectible again.
## With none placed, GEAR_SPOTS is used.
func _place_gears() -> void:
	var placed := get_parent().find_children("*", "GearPickup", true, false)
	for gear: GearPickup in placed:
		gear.event = GEAR_EVENT
		var path := String(get_parent().get_path_to(gear)).to_snake_case().replace("/", "__")
		gear.saved_event = StringName("%s_%s" % [GEAR_EVENT, path])
		if Quests.event_count(gear.saved_event) > 0:
			gear.queue_free()
	if placed.is_empty():
		for i in GEAR_SPOTS.size():
			_spawn_gear(i)


func _spawn_gear(index: int) -> void:
	var saved := StringName("%s_%02d" % [GEAR_EVENT, index])
	if Quests.event_count(saved) > 0:
		return
	var spot := anchor.to_global(Vector3(GEAR_SPOTS[index].x, 0.0, GEAR_SPOTS[index].y))
	var height: float = terrain.data.get_height(spot) if terrain else NAN
	spot.y = (anchor.global_position.y if is_nan(height) else height) + GEAR_HEIGHT
	var gear: GearPickup = GEAR.instantiate()
	gear.name = "Gear%02d" % index
	gear.event = GEAR_EVENT
	gear.saved_event = saved
	gear.position = to_local(spot)
	add_child(gear)


func _bot() -> CubeBot:
	return companion.get_node("CubeBot")


## Before the repair the bot stands still with its eye dark: no glow, no light.
func _sleep() -> void:
	companion.active = false
	var bot := _bot()
	bot.anim_player.pause()
	bot.eye_on = false
	bot.eye_mix = 1.0
	bot.eye_emission = 0.0
	bot.eye_light_energy = 0.0


## The readables' soft glimmer (the tablet effect), as is.
func _note_sparkles() -> CPUParticles3D:
	var note := NOTE.instantiate()
	var sparkles: CPUParticles3D = note.get_node("SoftSparkles")
	note.remove_child(sparkles)
	note.free()
	return sparkles


## The note's soft glimmer, a little bigger so it reads from a distance.
func _make_sparkles() -> CPUParticles3D:
	var sparkles := _note_sparkles()
	sparkles.position = Vector3.ZERO
	sparkles.amount = 12
	sparkles.emission_sphere_radius = 0.6
	sparkles.initial_velocity_min *= 4.0
	sparkles.initial_velocity_max *= 4.0
	sparkles.scale_amount_min *= 5.0
	sparkles.scale_amount_max *= 5.0
	return sparkles


## The repair: the bot shakes, its eye lights up yellow and settles to blue, then it wakes
## and follows LIRA. Quest 04 completes on ACTIVATED_EVENT and grants the jetpack.
func _repair() -> void:
	_sparkles.emitting = false
	var bot := _bot()
	UIAudio.play_sfx_at(UIAudio.ROBOT_WAKE, bot.global_position, 0.0)
	var base := bot.position
	var shake := create_tween()
	for i in 12:
		var jolt := Vector3(randf_range(-1, 1), randf_range(0, 0.5), randf_range(-1, 1)) * 0.05 * (1.0 + i / 6.0)
		shake.tween_property(bot, ^"position", base + jolt, 0.05)
	shake.tween_property(bot, ^"position", base, 0.1)
	await shake.finished
	bot.eye_on = true
	var light := create_tween()
	light.tween_property(bot, ^"eye_light_energy", 1.0, 0.3)
	light.parallel().tween_property(bot, ^"eye_emission", companion._base_emission, 0.3)
	light.tween_interval(0.8)
	light.tween_property(bot, ^"eye_mix", 0.0, 1.0).set_trans(Tween.TRANS_SINE)
	await light.finished
	bot.anim_player.play()
	Quests.report(ACTIVATED_EVENT)
	await _fetch_jetpack()
	companion.active = true


## Scripted: around buildings to the window, hop in, pick up the jetpack, hop back out.
## Then it follows LIRA (companion.active) and _process hands the jetpack over when close.
func _fetch_jetpack() -> void:
	if not is_instance_valid(jetpack_prop):
		Quests.report(DELIVERED_EVENT)  # nothing placed: hand it over straight away
		return
	await get_tree().physics_frame
	var way := _way_in()
	if not way.is_empty():
		for point in _ground_path(companion.global_position, way[0]):
			await _run_to(point)
		for i in range(1, way.size()):
			await _hop_to(way[i])
	await _hop_to(jetpack_prop.global_position)
	_carry()
	for i in range(way.size() - 1, -1, -1):
		await _hop_to(way[i])
	await _return_to_lira()
	_bot().play(&"Idle")


## Back beside LIRA on the ground path: the navmesh does not know the factory walls.
func _return_to_lira() -> void:
	var lira := get_tree().get_first_node_in_group(&"player") as Node3D
	if lira == null:
		return
	var away := companion.global_position - lira.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.BACK
	var goal := lira.global_position + away * companion.follow_distance
	var ground := _ground_at(companion.get_world_3d().direct_space_state, goal, goal.y + 1.5)
	if not is_nan(ground.y):
		goal = ground
	for point in _ground_path(companion.global_position, goal):
		await _run_to(point)


## [ground outside, sill, ...] from `route`, else the window found by rays (may be empty).
func _way_in() -> Array[Vector3]:
	var way: Array[Vector3] = []
	if is_instance_valid(route):
		for point in route.get_children():
			if point is Node3D:
				way.append(point.global_position)
	return way if not way.is_empty() else _find_window()


## A window is a wall (at least MIN_WINDOW_DEPTH away) that blocks near the floor but is open
## at some height above it, with clear ground just outside. The lowest, nearest one wins.
func _find_window() -> Array[Vector3]:
	var space := companion.get_world_3d().direct_space_state
	var target := jetpack_prop.global_position
	var below := _ray(space, target + Vector3.UP * 0.2, target + Vector3.DOWN * 4.0)
	var floor_y: float = below.position.y if not below.is_empty() else target.y
	var best: Array[Vector3] = []
	var best_cost := INF
	for i in 48:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 48.0)
		var low := Vector3(target.x, floor_y + 0.15, target.z)
		var wall := _ray(space, low, low + dir * WINDOW_SCAN)
		if wall.is_empty():
			continue  # open at floor height: a doorway, not a window
		var depth := Vector2(wall.position.x - low.x, wall.position.z - low.z).length()
		if depth < MIN_WINDOW_DEPTH:
			continue  # furniture, not the room's wall
		for h in WINDOW_HEIGHTS:
			var from := Vector3(target.x, floor_y + h, target.z)
			if not _ray(space, from, from + dir * WINDOW_SCAN).is_empty():
				continue
			var ground := _ground_at(space, from + dir * (depth + OUTSIDE_STEP), from.y + 1.0)
			if is_nan(ground.y) or _blocked(space, ground):
				continue
			# Really outside: walking back toward the jetpack meets the wall first.
			var back := _ray(space, ground + Vector3.UP * 0.4, low + Vector3.UP * (ground.y + 0.25 - low.y))
			if back.is_empty():
				continue
			var cost := depth + h * 2.0
			if cost < best_cost:
				best_cost = cost
				best.assign([ground, from + dir * depth + Vector3.DOWN * 0.1])
			break
	return best


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = _plan_exclude()
	return space.intersect_ray(query)


## The bot and LIRA never count as obstacles.
func _plan_exclude() -> Array[RID]:
	var out: Array[RID] = [companion.get_rid()]
	var lira := get_tree().get_first_node_in_group(&"player") as CollisionObject3D
	if lira:
		out.append(lira.get_rid())
	return out


## Ground under a point (casting down from `top`); y is NAN when there is none.
func _ground_at(space: PhysicsDirectSpaceState3D, at: Vector3, top: float) -> Vector3:
	var hit := _ray(space, Vector3(at.x, top, at.z), Vector3(at.x, top - 12.0, at.z))
	return hit.position if not hit.is_empty() else Vector3(at.x, NAN, at.z)


## Something solid where the bot would stand (a sphere just above the ground).
func _blocked(space: PhysicsDirectSpaceState3D, ground: Vector3) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = BOT_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), ground + Vector3.UP * (BOT_RADIUS + 0.3))
	query.exclude = _plan_exclude()
	return not space.intersect_shape(query, 1).is_empty()


## Horizontal distance from `a` to the first wall on the way to `b`, or -1 when clear.
func _wall_distance(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> float:
	for h in [0.4, 0.9]:
		var hit := _ray(space, a + Vector3.UP * h, b + Vector3.UP * h)
		if not hit.is_empty():
			return Vector2(hit.position.x - a.x, hit.position.z - a.z).length()
	return -1.0


## A collider-free path over the ground from `from` to `to`: A* on a grid of cells whose
## ground was probed with rays, then shortened where the straight line is clear.
func _ground_path(from: Vector3, to: Vector3) -> Array[Vector3]:
	var space := companion.get_world_3d().direct_space_state
	var start := Vector2i(floori(from.x / PLAN_CELL), floori(from.z / PLAN_CELL))
	var goal := Vector2i(floori(to.x / PLAN_CELL), floori(to.z / PLAN_CELL))
	var region := Rect2i(Vector2i(mini(start.x, goal.x), mini(start.y, goal.y)), (start - goal).abs() + Vector2i.ONE).grow(PLAN_MARGIN)
	var grid := AStarGrid2D.new()
	grid.region = region
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	var top := maxf(from.y, to.y) + 1.5
	var ground := {}
	for x in range(region.position.x, region.end.x):
		for z in range(region.position.y, region.end.y):
			var cell := Vector2i(x, z)
			var g := _ground_at(space, Vector3((x + 0.5) * PLAN_CELL, 0, (z + 0.5) * PLAN_CELL), top)
			ground[cell] = g
			if is_nan(g.y) or absf(g.y - from.y) > 6.0 or _blocked(space, g):
				grid.set_point_solid(cell)
	# A wall between neighbours cuts the link: the cell nearer it becomes solid. This also
	# catches cells inside thin walls, where the sphere above finds nothing (from inside a
	# collider no query hits its faces), as the ray from the neighbour does.
	for cell: Vector2i in ground:
		for step: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var next: Vector2i = cell + step
			if not ground.has(next) or is_nan(ground[cell].y) or is_nan(ground[next].y):
				continue
			for pair in [[cell, next], [next, cell]]:
				var d := _wall_distance(space, ground[pair[0]], ground[pair[1]])
				if d >= 0.0:
					grid.set_point_solid(pair[1] if d > PLAN_CELL * 0.5 else pair[0])
	grid.set_point_solid(start, false)
	grid.set_point_solid(goal, false)
	var cells := grid.get_id_path(start, goal)
	if cells.is_empty():
		push_warning("FactoryStory: no clear ground path to the power-room window; going straight.")
		return [to]
	var points: Array[Vector3] = []
	for i in range(1, cells.size() - 1):
		points.append(ground[cells[i]])
	points.append(to)
	# Skip corners while the straight line between points stays clear.
	var out: Array[Vector3] = []
	var at := from
	var i := 0
	while i < points.size():
		var far := i
		while far + 1 < points.size() and _clear_line(space, at, points[far + 1]):
			far += 1
		out.append(points[far])
		at = points[far]
		i = far + 1
	return out


func _clear_line(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	for h in [0.4, 0.9]:
		if not _ray(space, a + Vector3.UP * h, b + Vector3.UP * h).is_empty():
			return false
	return true


## Runs straight to a point (the ground path keeps these legs clear).
func _run_to(point: Vector3) -> void:
	var flat := Vector3(point.x - companion.global_position.x, 0, point.z - companion.global_position.z)
	if flat.length() < 0.05:
		return
	companion.rotation.y = atan2(flat.x, flat.z)
	_bot().play(&"Run")
	var leg := create_tween()
	leg.tween_property(companion, ^"global_position", point, companion.global_position.distance_to(point) / RUN_SPEED)
	await leg.finished


func _hop_to(point: Vector3) -> void:
	var bot := _bot()
	var from := companion.global_position
	var flat := Vector3(point.x - from.x, 0, point.z - from.z)
	if flat.length() > 0.01:
		companion.rotation.y = atan2(flat.x, flat.z)
	# The arc rides on the straight line from -> point, so half the rise clears the sill
	# without the bot's head hitting the top of the window.
	var height := HOP_HEIGHT + absf(point.y - from.y) * 0.5
	bot.play(&"Jump_Start")
	var hop := create_tween()
	hop.tween_method(func(t: float) -> void:
		companion.global_position = from.lerp(point, t) + Vector3.UP * sin(t * PI) * height,
		0.0, 1.0, maxf(from.distance_to(point) / HOP_SPEED, 0.4))
	await hop.finished
	bot.play(&"Land")


## The jetpack rides on the bot's head until it is handed over.
func _carry() -> void:
	if not is_instance_valid(jetpack_prop):
		return
	jetpack_prop.reparent(_bot(), true)
	jetpack_prop.position = CARRY_OFFSET
	_carrying = true


func _hand_over(lira: Node3D) -> void:
	_carrying = false
	if is_instance_valid(jetpack_prop):
		jetpack_prop.queue_free()
	Quests.report(DELIVERED_EVENT)  # quest 04 grants the jetpack
	var pack = lira.get(&"jetpack")
	if pack and pack.has_method(&"burst"):
		pack.burst()
