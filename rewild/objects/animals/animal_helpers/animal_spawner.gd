class_name AnimalSpawner
extends Node3D
## Keeps each species at a target count that follows the restoration progress.
## Circles (AnimalCircle children) say where; the SPECIES table says what, when and how many.
## No _process: two timers do everything.

const K := AnimalCircle.Kind
const FREEZE_SQ := 120.0 * 120.0   # farther than this from the camera: frozen
const WAKE_SQ := 90.0 * 90.0       # closer than this: running again
const HEIGHT_OFFSET := 1.0

## scene: path | nav: snap to navmesh | region: GrowthRegion id (&"" = whole world)

## ramp: Vector2(progress, count) points, linear in between, flat after the last
# Order of appearance: the ramp points in SPECIES are the progress-to-count curve for each species. 
# Counts rise linearly between points and stay flat after the last one. Edit that table to tune the order. 
# The defaults run crab, fish, chicken, seagull, fox, shark, and fish come before the shark so it has prey.

## every: seconds between spawns of this species (slow for fish so sharks can thin them)
const SPECIES := {
	K.CRAB: {scene = "res://objects/animals/crab/animal_crab.tscn", nav = true, region = &"",
			ramp = [Vector2(0.05, 0), Vector2(0.4, 5)], every = 0.5, freeze = true},
	K.SMALL_FISH: {scene = "res://objects/animals/small_fish/small_fish_tropical.tscn", nav = false, region = &"lake",
			ramp = [Vector2(0.1, 0), Vector2(0.5, 8)], every = 1.5, freeze = true},
	K.CHICKEN: {scene = "res://objects/animals/chicken/animal_chicken.tscn", nav = true, region = &"",
			ramp = [Vector2(0.2, 0), Vector2(0.6, 6)], every = 0.5, freeze = true},
	K.SEAGULL: {scene = "res://objects/animals/seagull/animal_seagull.tscn", nav = false, region = &"",
			ramp = [Vector2(0.3, 0), Vector2(0.7, 4)], every = 0.5, freeze = false},
	K.FOX: {scene = "res://objects/animals/fox/animal_fox.tscn", nav = true, region = &"",
			ramp = [Vector2(0.5, 0), Vector2(0.9, 3)], every = 0.5, freeze = true},
	K.SHARK: {scene = "res://objects/animals/shark/animal_shark.tscn", nav = false, region = &"",
			ramp = [Vector2(0.6, 0), Vector2(0.9, 1)], every = 5.0, freeze = true},
}

var _circles := {}   # Kind -> Array[AnimalCircle]
var _alive := {}     # Kind -> Array[Node3D]
var _scenes := {}    # Kind -> PackedScene
var _next_ok := {}   # Kind -> msec when the next spawn is allowed
var _spawn_timer := Timer.new()
var _lod_timer := Timer.new()
var _spawn_count := {}   # Kind -> how many were ever spawned (names keep counting up after deaths)

func _ready() -> void:
	for kind in SPECIES:
		_circles[kind] = []
		_alive[kind] = []
		_next_ok[kind] = 0
		_spawn_count[kind] = 0
	for c in find_children("*", "AnimalCircle", true, false):
		_circles[c.kind].append(c)
	_spawn_timer.wait_time = 0.5
	_spawn_timer.timeout.connect(_reconcile)
	add_child(_spawn_timer)
	_lod_timer.wait_time = 1.0
	_lod_timer.timeout.connect(_lod_tick)
	add_child(_lod_timer)
	_lod_timer.start()
	GrowthMap.progress_changed.connect(_wake_spawner)
	_wake_spawner()  # a loaded save may already be past some thresholds

func _wake_spawner() -> void:
	if _spawn_timer.is_stopped():
		_spawn_timer.start()


# --- Targets -----------------------------------------------------------------

func _progress(region: StringName) -> float:
	var p := GrowthMap.world_greenness()
	if region != &"":
		var r := GrowthMap.region_progress(region)
		if r >= 0.0:
			p = r
	return clampf(p + _debug_bonus, 0.0, 1.0)


func _target(kind: int) -> int:
	if _circles[kind].is_empty():
		return 0  # no circle = never spawns
	var s: Dictionary = SPECIES[kind]
	var p := _progress(s.region)
	var pts: Array = s.ramp
	var n := 0.0
	for i in pts.size():
		if p < pts[i].x:
			break
		n = pts[i].y
		if i + 1 < pts.size() and p < pts[i + 1].x:
			n = lerpf(pts[i].y, pts[i + 1].y, (p - pts[i].x) / (pts[i + 1].x - pts[i].x))
			break
	return int(n)


# --- Spawning (runs only while some species is off target) -----------------------

func _reconcile() -> void:
	var busy := false
	var now := Time.get_ticks_msec()
	for kind in SPECIES:
		var alive: Array = _alive[kind]
		var target := _target(kind)
		if alive.size() > target:
			_shed_farthest(alive)
			busy = true
		elif alive.size() < target:
			busy = true
			if now >= _next_ok[kind] and _spawn_one(kind):
				_next_ok[kind] = now + int(SPECIES[kind].every * 1000.0)
	if not busy:
		_spawn_timer.stop()  # nothing to do until the next progress change


func _spawn_one(kind: int) -> bool:
	var s: Dictionary = SPECIES[kind]
	var circles: Array = _circles[kind]
	var c: AnimalCircle = circles[randi() % circles.size()]
	var a := randf() * TAU
	var r := sqrt(randf()) * c.radius
	var p := c.global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
	if s.nav:
		var map := get_world_3d().navigation_map
		if NavigationServer3D.map_get_iteration_id(map) == 0:
			return false  # navmesh not baked yet, try next tick
		var snapped := NavigationServer3D.map_get_closest_point(map, p)
		if Vector2(snapped.x - c.global_position.x, snapped.z - c.global_position.z).length() > c.radius * 1.5:
			return false  # circle is not over the navmesh
		p = snapped + Vector3.UP * HEIGHT_OFFSET
	if not _scenes.has(kind):
		_scenes[kind] = load(s.scene)

	var animal := (_scenes[kind] as PackedScene).instantiate() as Node3D
	_spawn_count[kind] += 1
	animal.name = "%s_%d" % [AnimalCircle.Kind.keys()[kind].capitalize(), _spawn_count[kind]]
	animal.position = to_local(p)
	animal.rotation.y = randf() * TAU
	add_child(animal)
	_alive[kind].append(animal)

	# debug
	if OS.is_debug_build():
		print("[AnimalSpawner] spawned %s at %v (alive %d / target %d), circle global pos at %v" \
				% [animal.name, p, _alive[kind].size(), _target(kind), c.global_position])
				
	# Also fires when a shark eats a fish (queue_free), so the count refills by itself.
	animal.tree_exited.connect(_on_gone.bind(kind, animal))
	return true


func _on_gone(kind: int, animal: Node3D) -> void:
	_alive[kind].erase(animal)
	_wake_spawner()


func _shed_farthest(alive: Array) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or alive.is_empty():
		return
	var worst: Node3D = alive[0]
	for a in alive:
		if a.global_position.distance_squared_to(cam.global_position) \
				> worst.global_position.distance_squared_to(cam.global_position):
			worst = a
	worst.queue_free()


# --- Freezing far animals and performance scaling (1 Hz) ----------------------

func _lod_tick() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for kind in _alive:
		if not SPECIES[kind].get("freeze", true):
			continue
		for a: Node3D in _alive[kind]:
			var d := a.global_position.distance_squared_to(cam.global_position)
			if a.process_mode == Node.PROCESS_MODE_DISABLED:
				if d < WAKE_SQ:
					a.process_mode = Node.PROCESS_MODE_INHERIT
			elif d > FREEZE_SQ:
				a.process_mode = Node.PROCESS_MODE_DISABLED


var _debug_bonus := 0.0

#func _unhandled_input(event: InputEvent) -> void:
	#if not OS.is_debug_build() or not (event is InputEventKey and event.pressed and not event.echo):
		#return
	#if event.keycode == KEY_F10:
		#_debug_bonus = clampf(_debug_bonus + (-0.1 if event.shift_pressed else 0.1), 0.0, 1.0)
		#print("[AnimalSpawner] debug progress bonus: +%.1f" % _debug_bonus)
		#_wake_spawner()
