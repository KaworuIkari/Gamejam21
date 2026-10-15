extends SpringArm3D
## Keep the sweep origin at shoulder height, even when looking up/down.
@export var focus_height: float = 1.65
@export var camera_radius: float = 0.20
@export var wall_clearance: float = 0.05

var _pivot: Node3D
var _body: PhysicsBody3D
var _probe: SphereShape3D

func _ready() -> void:
	_pivot = get_parent() as Node3D
	_body = _pivot.get_parent() as PhysicsBody3D
	_probe = SphereShape3D.new()
	_probe.radius = camera_radius
	shape = _probe
	margin = wall_clearance
	position = Vector3.ZERO
	_pivot.position = Vector3(0.0, focus_height, 0.0)
	if _body != null:
		add_excluded_object(_body.get_rid())
	for child in get_children():
		if child is Camera3D:
			child.near = 0.05

func update_pivot_offset(offset: Vector3, delta: float, speed: float) -> void:
	var focus := Vector3(0.0, focus_height, 0.0)
	var desired := _pivot.position.lerp(focus + offset, 1.0 - exp(-speed * delta))
	if _body == null:
		_pivot.position = desired
		return
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe
	query.collision_mask = collision_mask
	query.exclude = [_body.get_rid()]
	query.margin = wall_clearance
	query.transform = Transform3D(Basis.IDENTITY, _body.to_global(focus))
	var space := get_world_3d().direct_space_state
	# A shape sweep ignores initial overlaps; don't move the origin further
	# into a wall when the character is already squeezed against one.
	if not space.intersect_shape(query, 1).is_empty():
		_pivot.position = focus
		return
	query.motion = _body.global_basis * (desired - focus)
	var travel := space.cast_motion(query)
	_pivot.position = focus + (desired - focus) * travel[0]
