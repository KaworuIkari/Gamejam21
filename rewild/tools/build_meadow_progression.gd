extends Node
## Generates levels/meadow_hand/meadow_progression.tscn: every progression prop for
## meadow_hand, snapped to the Terrain3D height, wired to meadow_progression.gd.
## Re-run after moving terrain (this overwrites the scene, so hand edits to it are lost):
##   Godot --headless --path rewild res://tools/build_meadow_progression.tscn

const OUT := "res://levels/meadow_hand/meadow_progression.tscn"
const SEA_LEVEL := 24.75

const LITTER := "res://assets/models/rewild_litter_v1/"
const DIRTY := "res://assets/models/rewild_dirty_litter_v1/"
const WRECK := "res://assets/models/rewild_wreck_v1/"
const RELAY := "res://assets/models/industrial_relay/"
const CRASH := "res://assets/models/crashsite_outpost/"
const FLOW := "res://assets/models/rewild_flow_v1/"
const VEG := "res://assets/models/rewild_vegetation_v1/"
const CHAN := "res://assets/models/rewild_channels_v1/"
const MARKS := "res://assets/models/rewild_landmarks_v1/"
const WALL := "res://assets/models/rewild_coastal_wall_v1/"
const CHICKEN := "res://objects/animals/chicken/animal_chicken.tscn"

var terrain: Terrain3D
var scene_root: Node3D
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	terrain = Terrain3D.new()
	terrain.data_directory = "res://levels/meadow_hand/terrain_data"
	add_child(terrain)
	await get_tree().process_frame
	rng.seed = 21
	_build()
	var packed := PackedScene.new()
	var err := packed.pack(scene_root)
	if err == OK:
		err = ResourceSaver.save(packed, OUT)
	print("saved %s: %s" % [OUT, error_string(err)])
	scene_root.free()
	get_tree().quit(0 if err == OK else 1)


func _build() -> void:
	scene_root = Node3D.new()
	scene_root.name = "MeadowProgression"
	scene_root.set_script(load("res://levels/meadow_hand/meadow_progression.gd"))

	var stages := Node.new()
	stages.name = "WorldStages"
	stages.set_script(load("res://systems/world_stages/world_stages.gd"))
	var list: Array[WorldStage] = [
		load("res://systems/world_stages/stages/stage_1_wasteland.tres"),
		load("res://systems/world_stages/stages/stage_2_revival.tres"),
		load("res://systems/world_stages/stages/stage_3_golden.tres"),
	]
	stages.stages = list
	_add(scene_root, stages)
	stages.add_to_group(&"world_stages", true)
	scene_root.world_stages = stages

	_basin()
	_spring()
	_lake(stages)
	_east()
	_peak()
	_beach()


# --- Zones ---------------------------------------------------------------------

## Tutorial litter around the spawn point (LIRA starts at about (-10, -92)).
func _basin() -> void:
	var g := _group("Basin")
	var spots := [Vector2(-2, -78), Vector2(8, -70), Vector2(-14, -68), Vector2(4, -60)]
	var scenes := [DIRTY + "Dirty_Litter_Heap_1", LITTER + "Litter_Cluster_2",
			DIRTY + "Dirty_Litter_Heap_3", LITTER + "Litter_Cluster_1"]
	for i in spots.size():
		_clearable(g, scenes[i], spots[i], [&"basin_litter"], 0.8, 2.5)


## North island: the pump house sits on the summit at (-66, 45, -335) (placed by hand).
func _spring() -> void:
	var g := _group("Spring")
	_prop(g, FLOW + "Spring_Intake", Vector2(-56, -322), 200.0)
	var blockage := [
		[RELAY + "Rubble_Cluster_1", Vector2(-55, -315)],
		[RELAY + "Rubble_Cluster_2", Vector2(-50, -320)],
		[RELAY + "Pipe_Broken_3m", Vector2(-59, -311)],
		[RELAY + "Tank_Ruptured", Vector2(-48, -313)],
		[RELAY + "Rubble_Cluster_3", Vector2(-62, -316)],
	]
	for b in blockage:
		_clearable(g, b[0], b[1], [&"spring_blockage"], 1.0, 3.5)
	_rescue(g, Vector2(-48, -346), &"rescue_spring")

	var area := Area3D.new()
	area.name = "SpringArea"
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 70.0
	shape.shape = sphere
	_add(g, area)
	_add(area, shape)
	area.position = _at(Vector2(-60, -300))
	scene_root.spring_area = area

	_stage_variant(g, "Twin_Ruptured_Silos", MARKS + "Twin_Ruptured_Silos_", ["Wasteland", "Revival", "Golden"],
			Vector2(-102, -268), 30.0)


## Central lake: the station sits on the islet; sluice gates and channels lead east and west.
func _lake(stages: Node) -> void:
	var g := _group("Lake")
	var station := _prop(g, "res://assets/models/rewild_lake_station_v1/Lake_Power_Station", _islet_top(), 180.0)
	station.name = "LakeStation"
	scene_root.station = station
	stages.focus = station
	# East outlet: gate on the rim, three straight channel pieces running east (+X).
	_outlet(g, "East", Vector2(4, 66), 1.0)
	_outlet(g, "West", Vector2(-104, 66), -1.0)


func _outlet(g: Node3D, side: String, gate_xz: Vector2, dir: float) -> void:
	# Channel modules run along local Z; a 90 degree turn lays them along X.
	var yaw := 90.0
	var gate := _stage_variant(g, "SluiceGate" + side, FLOW + "Sluice_Gate_", ["Closed", "Open"], gate_xz, yaw)
	gate.position.y += 0.05
	for i in 3:
		var xz := gate_xz + Vector2(dir * (4.5 + 6.0 * i), 0)
		_stage_variant(g, "Channel%s%d" % [side, i + 1], CHAN + "Channel_Straight_", ["Dry", "Flowing", "Reclaimed"], xz, yaw)


## East oasis: a GrowthZone the player waters, plants that recover with it, a cage.
func _east() -> void:
	var g := _group("East")
	var center := Vector2(75, 30)
	var zone := GrowthZone.new()
	zone.name = "EastZone"
	zone.zone_id = &"east"
	zone.radius = 30.0
	zone.complete_at = 0.45
	_add(g, zone)
	zone.position = _at(center)
	scene_root.east_zone = zone
	_plants(g, center, 26.0, [
		"Shrub_Cluster", "Shrub_Cluster", "Shrub_Cluster", "Shrub_Cluster",
		"Skeletal_Tree", "Skeletal_Tree", "Skeletal_Tree",
		"Reed_Bed", "Reed_Bed", "Fern_Cluster", "Fern_Cluster", "Cracked_Planter", "Cracked_Planter",
	])
	var debris := [RELAY + "Machine_Wreck", RELAY + "Truss_Broken", WRECK + "Slab_Snapped_Rebar",
			RELAY + "Cargo_Crate", CRASH + "Debris_Cluster_2"]
	for i in debris.size():
		var a := TAU * i / debris.size() + 0.4
		_clearable(g, debris[i], center + Vector2(cos(a), sin(a)) * 16.0, [&"east_debris"], 1.0, 3.5)
	scene_root.east_rescue = _rescue(g, center + Vector2(10, 14), &"rescue_east")
	_prop(g, FLOW + "Jetpack_Pickup", center + Vector2(-8, -10), 30.0)
	_stage_variant(g, "Broken_Industrial_Viaduct", MARKS + "Broken_Industrial_Viaduct_",
			["Wasteland", "Revival", "Golden"], Vector2(118, -22), 90.0)


## The hill north of spawn, the highest ground on the main island.
func _peak() -> void:
	var g := _group("Peak")
	var center := Vector2(-37, -106)
	var zone := GrowthZone.new()
	zone.name = "PeakZone"
	zone.zone_id = &"peak"
	zone.radius = 14.0
	zone.complete_at = 0.45
	_add(g, zone)
	zone.position = _at(center)
	scene_root.peak_zone = zone
	_plants(g, center, 9.0, ["Skeletal_Tree", "Skeletal_Tree", "Fern_Cluster", "Fern_Cluster", "Shrub_Cluster"])
	scene_root.peak_rescue = _rescue(g, center + Vector2(4, 3), &"rescue_peak")


## South shore: the garbage wall (needs demolition auth), loose litter, the tower.
func _beach() -> void:
	var g := _group("Beach")
	var marker := Marker3D.new()
	marker.name = "WallCenter"
	_add(g, marker)
	marker.position = _at(Vector2(-15, 246))
	scene_root.beach_center = marker
	var wall: Node3D = load(WALL + "Coastal_Wall_Intact.tscn").instantiate()
	var k := 0
	for set_x in [-44.0, -15.0, 14.0]:
		for piece in wall.get_children():
			if piece.scene_file_path.is_empty():
				continue
			var xz := Vector2(set_x + piece.position.x, 246)
			var c := _clearable(g, piece.scene_file_path.get_basename(), xz, [&"beach_wall"], 1.5, 6.0, 0.0)
			c.name = "Wall%02d_%s" % [k, piece.name]
			c.required_ability = &"demolition_auth"
			c.bloom_radius = 10.0
			k += 1
	wall.free()
	var litter := [DIRTY + "Bottle_Collapsed_Uncapped", DIRTY + "Can_Flattened_Dirty", DIRTY + "Bag_Shredded_Muddy",
			DIRTY + "Dirty_Litter_Heap_2", LITTER + "Litter_Cluster_3", DIRTY + "Tray_Filthy_Broken"]
	for i in litter.size():
		_clearable(g, litter[i], Vector2(-40 + 14 * i, 228 + rng.randf_range(-6, 6)), [&"beach_litter"], 0.8, 2.5)
	_stage_variant(g, "Ruined_Concrete_Tower", MARKS + "Ruined_Concrete_Tower_", ["Wasteland", "Revival", "Golden"],
			Vector2(-86, 209), 0.0)


# --- Helpers -------------------------------------------------------------------

func _group(n: String) -> Node3D:
	var g := Node3D.new()
	g.name = n
	_add(scene_root, g)
	return g


func _add(parent: Node, n: Node) -> void:
	parent.add_child(n, true)
	n.owner = scene_root


func _height(xz: Vector2) -> float:
	var h := terrain.data.get_height(Vector3(xz.x, 0, xz.y))
	if is_nan(h):
		push_warning("no terrain at %s" % xz)
		return SEA_LEVEL
	if h < SEA_LEVEL + 0.2:
		push_warning("%s is at/below sea level (h=%.1f)" % [xz, h])
	return h


func _at(xz: Vector2) -> Vector3:
	return Vector3(xz.x, _height(xz), xz.y)


func _scene(path: String) -> PackedScene:
	if not path.ends_with(".tscn"):
		path += ".tscn"
	return load(path)


## A static prop (not interactive), yaw in degrees (random when NAN).
func _prop(parent: Node3D, path: String, xz: Vector2, yaw := NAN) -> Node3D:
	var n: Node3D = _scene(path).instantiate()
	_add(parent, n)
	n.position = _at(xz)
	n.rotation_degrees.y = rng.randf_range(0, 360) if is_nan(yaw) else yaw
	return n


func _clearable(parent: Node3D, path: String, xz: Vector2, tags: Array[StringName], hold: float,
		reach: float, yaw := NAN) -> Clearable:
	var c := Clearable.new()
	c.name = path.get_file()
	c.tags = tags
	c.hold_time = hold
	c.radius = reach
	_add(parent, c)
	c.position = _at(xz)
	c.rotation_degrees.y = rng.randf_range(0, 360) if is_nan(yaw) else yaw
	var n: Node3D = _scene(path).instantiate()
	_add(c, n)
	return c


## A closed enclosure that opens (and lets a chicken out) when cleared.
func _rescue(parent: Node3D, xz: Vector2, tag: StringName) -> Clearable:
	var c := _clearable(parent, FLOW + "Rescue_Enclosure_Closed", xz, [tag, &"rescue"], 1.2, 3.0)
	c.name = "Rescue_" + String(tag)
	c.replace_with = _scene(FLOW + "Rescue_Enclosure_Open")
	c.release = load(CHICKEN)
	c.release_offset = Vector3(0, 0.3, 2.2)
	c.bloom_radius = 8.0
	return c


## One child per stage, e.g. prefix "…/Tower_" + ["Wasteland", "Revival", "Golden"].
func _stage_variant(parent: Node3D, n: String, prefix: String, suffixes: Array, xz: Vector2, yaw: float) -> Node3D:
	var v := StageVariant.new()
	v.name = n
	_add(parent, v)
	v.position = _at(xz)
	v.rotation_degrees.y = yaw
	for i in suffixes.size():
		var child: Node3D = _scene(prefix + suffixes[i]).instantiate()
		_add(v, child)
		child.visible = i == 0  # editor shows the wasteland look; StageVariant handles runtime
	return v


func _plants(parent: Node3D, center: Vector2, spread: float, kinds: Array) -> void:
	var placed: Array[Vector2] = []
	for kind in kinds:
		var xz := center
		for attempt in 30:
			var a := rng.randf() * TAU
			xz = center + Vector2(cos(a), sin(a)) * spread * sqrt(rng.randf())
			var ok := _height(xz) > SEA_LEVEL + 1.0
			for p in placed:
				if p.distance_to(xz) < 4.5:
					ok = false
			if ok:
				break
		placed.append(xz)
		var v := GrowthVariant.new()
		v.name = kind
		_add(parent, v)
		v.position = _at(xz)
		v.rotation_degrees.y = rng.randf_range(0, 360)
		for i in 3:
			var state: String = ["Withered", "Sprouting", "Flourishing"][i]
			var child: Node3D = _scene(VEG + kind + "_" + state).instantiate()
			_add(v, child)
			child.visible = i == 0


## Highest point near the lake centre: the islet the station stands on.
func _islet_top() -> Vector2:
	var best := Vector2(-45, 75)
	var best_h := -INF
	for x in range(-60, -30, 2):
		for z in range(55, 95, 2):
			var h := terrain.data.get_height(Vector3(x, 0, z))
			if not is_nan(h) and h > best_h:
				best_h = h
				best = Vector2(x, z)
	print("islet top %s h=%.1f" % [best, best_h])
	return best
