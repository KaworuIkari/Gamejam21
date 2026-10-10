@tool
extends MeshInstance3D
# gun attachment
@export var water_gun_pos:Node3D
@onready var water_gun: MeshInstance3D = $WaterGun

# procedural tube
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

func _process(_delta):
	set_gun_pos()
	update_tube()

func set_gun_pos():
	if water_gun and water_gun_pos:
		water_gun.global_transform = water_gun_pos.global_transform

func _ready_tube() -> void:
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = noise_seed
	# we want to use point's global position!
	path.top_level = true
	path.global_transform = Transform3D.IDENTITY
	csg.top_level = true
	csg.global_transform = Transform3D.IDENTITY
	csg.path_local = true

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