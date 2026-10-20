@tool
class_name WaterTank extends MeshInstance3D

#### Water refill ####
@export var refill_time := 1.0   ## seconds, empty to full, while holding interact at a water source
@export var capacity := 10.0   ## shots in a full tank; set per level by the player
@export var smooth := 8.0        ## visual catch-up rate

@onready var tank_water: MeshInstance3D = $TankWater
@onready var fill_sound: FmodEventEmitter3D = $TankFillUpSound

var level := 1.0      ## 0..1, authoritative
var _shown := 1.0     ## smoothed, drives the mesh
var _mesh: CylinderMesh
var _full_height := 0.0
var _top_y := 0.0
var _top_r := 0.0
var _bottom_r := 0.0
var _filling := false

#### procedural tube ####
@export var anchor_start:Node3D
@export var anchor_end:Node3D
@export var mid_offset := Vector3(0, 0.3, -0.1)   # in this node's local space
@export_range(0.0, 1.0) var tension := 0.35

@export_group("Noise")
@export var noise_amplitude := Vector3(0.03, 0.02, 0.03)   # metres per axis
@export var noise_frequency := 1.5                         # roughly cycles per second
@export var noise_seed := 0:
	set(v):
		noise_seed = v
		noise.seed = v
var noise := FastNoiseLite.new()

@onready var path: Path3D = $Path3D
@onready var csg: CSGPolygon3D = $CSGPolygon3D

func _ready():
	_ready_tube()
	_ready_tank_water()

func _process(delta):
	update_tube()
	update_tank_water(delta)

func _ready_tube() -> void:
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = noise_seed
	# we want to use point's global position!
	# path.top_level = true
	path.global_transform = Transform3D.IDENTITY
	# csg.top_level = true
	csg.global_transform = Transform3D.IDENTITY
	csg.path_local = true

func _ready_tank_water() -> void:
	_mesh = tank_water.mesh.duplicate()   # don't mutate a shared resource
	tank_water.mesh = _mesh
	_full_height = _mesh.height
	_top_r = _mesh.top_radius
	_bottom_r = _mesh.bottom_radius
	_top_y = tank_water.position.y + _full_height * 0.5
	_shown = level
	_apply(level)

func update_tube():
	if !anchor_start or !anchor_end:
		return
	var p0 = anchor_start.global_position
	var p2 = anchor_end.global_position

	# Middle point: midpoint + your offset (in character space) + wind
	var t = Time.get_ticks_msec() * 0.001 * noise_frequency
	var wobble = Vector3(
		noise.get_noise_1d(t),
		noise.get_noise_1d(t + 100.0),
		noise.get_noise_1d(t + 200.0)) * noise_amplitude
	var p1 = (p0 + p2) * 0.5 + global_basis * (mid_offset + wobble)

	var c := path.curve
	if c.point_count != 3:
		c.clear_points()
		for i in 3:
			c.add_point(Vector3.ZERO)

	var pts = [p0, p1, p2]
	var dirs = [
		-anchor_start.global_basis.y,
		(p2 - p0).normalized(),          # Catmull-Rom tangent at the middle
		-anchor_end.global_basis.z,
	]
	var inv = path.global_basis.inverse()
	for i in 3:
		var len_in  = pts[i].distance_to(pts[i - 1]) if i > 0 else 0.0
		var len_out = pts[i].distance_to(pts[i + 1]) if i < 2 else 0.0
		c.set_point_position(i, path.to_local(pts[i]))
		c.set_point_in(i,  inv * (-dirs[i] * len_in  * tension))
		c.set_point_out(i, inv * ( dirs[i] * len_out * tension))


# tank water
func is_empty() -> bool:
	return level <= 0.0
## Spends one shot's worth. Returns false and spends nothing if the tank can't cover it.
func consume_shot() -> bool:
	var cost := 1.0 / maxf(capacity, 1.0)
	if level < cost:
		return false
	level -= cost
	return true
func shots_left() -> int:            # wire this to UI if any
	return floori(level * capacity)
func refill(delta: float) -> void:
	level = minf(level + delta / refill_time, 1.0)
func set_filling(on: bool) -> void:
	if on == _filling:
		return   # only act on change: restarting a loop each frame retriggers it
	_filling = on
	if on:
		fill_sound.play()
	else:
		fill_sound.stop()
func _apply(v: float) -> void:
	var h := maxf(_full_height * v, 0.0001)
	_mesh.height = h
	_mesh.bottom_radius = lerpf(_top_r, _bottom_r, v)
	tank_water.position.y = _top_y - h * 0.5
	tank_water.visible = v > 0.002

func update_tank_water(delta : float) -> void:
	if Engine.is_editor_hint(): return
	_shown = lerpf(_shown, level, 1.0 - exp(-smooth * delta))
	_apply(_shown)