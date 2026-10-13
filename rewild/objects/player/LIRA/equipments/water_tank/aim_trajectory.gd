class_name AimTrajectory extends Node3D

@export var blob_scene: PackedScene
@export var speed := 14.0
@export var gravity := 14.0            # cartoon gravity, tune freely
@export var max_time := 3.0            # preview length if nothing is hit
@export var samples := 32
@export var width := 0.1
@export_flags_3d_physics var collision_mask := 1

@export_group("Aiming")
@onready var aim_correction: AimCorrection = $"../Robot/root/Skeleton3D/AimCorrection"
@export var zero_distance := 12.0                        # blob crosses the reticle line here; 0 = no elevation
@export var aim_origin_height := 1.3                     # chest height used for the elevation solve
@export_range(0.0, 1.0) var inherit_velocity := 1.0      # share of the along-barrel player speed added to the throw

@onready var player: LIRA_Character = $".."
@onready var muzzle: Node3D = $"../Robot/root/Skeleton3D/hand_r/WaterGunMuzzle"

var active := false
var world_velocity := Vector3.FORWARD * 10.0   # what the blob gets, and what the preview draws
var landing_point := Vector3.ZERO              # last point of the preview, handy for a marker
var landing_valid := false

var _mesh := ImmediateMesh.new()

func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.top_level = true                # points are in world space
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://objects/player/LIRA/equipments/water_tank/trajectory_dash.gdshader")
	mi.material_override = mat
	add_child(mi)

func _process(_d: float) -> void:
	_mesh.clear_surfaces()
	if not active:
		return
	_update_velocity()
	_draw(_sample(muzzle.global_position, world_velocity), get_viewport().get_camera_3d())

func fire() -> void:
	_update_velocity()                 # use the barrel's direction at this instant
	var blob : WaterBlob = blob_scene.instantiate()
	blob.on_blob_die.connect(player._on_blob_landed)
	get_tree().current_scene.add_child(blob)
	blob.launch(muzzle.global_position, world_velocity, gravity, collision_mask, player.get_rid())

# --- aim ---

## Direction the arm should point (give this to AimCorrection.desired_dir_world).
func arm_direction() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	var d := cam.project_ray_normal(get_viewport().get_visible_rect().size * 0.5)
	if zero_distance <= 0.0:
		return d
	var p0 := player.global_position + Vector3.UP * aim_origin_height
	return _solve(p0, p0 + d * zero_distance).normalized()

func _update_velocity() -> void:
	var dir := aim_correction.aim_dir_world
	var carry := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var s := maxf(speed + carry.dot(dir) * inherit_velocity, speed * 0.5)
	world_velocity = dir * s

# Low-arc launch velocity from p0 reaching target; if out of reach, the max-range throw. Only used for elevation.
func _solve(p0: Vector3, target: Vector3) -> Vector3:
	var d := target - p0
	var flat := Vector3(d.x, 0.0, d.z)
	var x := flat.length()
	if x < 0.01:
		return Vector3.UP * speed
	var v2 := speed * speed
	var disc := v2 * v2 - gravity * (gravity * x * x + 2.0 * d.y * v2)
	var theta: float
	if disc >= 0.0:
		theta = atan((v2 - sqrt(disc)) / (gravity * x))
	else:
		theta = atan(speed / sqrt(v2 + 2.0 * gravity * maxf(-d.y, 0.0)))
	return flat.normalized() * cos(theta) * speed + Vector3.UP * sin(theta) * speed

# --- preview ---

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, collision_mask, [player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q)

func _sample(p0: Vector3, v: Vector3) -> PackedVector3Array:
	var g := Vector3.DOWN * gravity
	var pts := PackedVector3Array([p0])
	var prev := p0
	landing_valid = false
	for i in range(1, samples + 1):
		var t := max_time * i / samples
		var p := p0 + v * t + 0.5 * g * t * t
		var hit := _ray(prev, p)
		if not hit.is_empty():
			pts.append(hit.position)
			landing_valid = true
			break
		pts.append(p)
		prev = p
	landing_point = pts[pts.size() - 1]
	return pts

func _draw(pts: PackedVector3Array, cam: Camera3D) -> void:
	var n := pts.size()
	if n < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var dist := 0.0
	for i in n:
		if i > 0:
			dist += pts[i].distance_to(pts[i - 1])
		var tangent := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := tangent.cross((cam.global_position - pts[i]).normalized()).normalized() * width * 0.5
		_mesh.surface_set_uv(Vector2(dist, 0.0))
		_mesh.surface_add_vertex(pts[i] - side)
		_mesh.surface_set_uv(Vector2(dist, 1.0))
		_mesh.surface_add_vertex(pts[i] + side)
	_mesh.surface_end()