class_name Throwable extends Node
## Lets LIRA pick up and throw a prop (e.g. the little Leon statue). Add this node
## anywhere and point `prop` at the prop's root. Press interact nearby to grab it: it shrinks to `held_size` and sits
## in LIRA's right hand. Press interact again to throw it where the camera looks.
## Collision bodies under the prop are switched off while it's carried or flying.
## If it comes down in `target_water` while there's water in it, `landed` says so.

signal picked_up
signal thrown
## in_target: it came down in target_water.
signal landed(in_target: bool)

## The Node3D that gets carried and thrown.
@export var prop: Node3D
## How close LIRA must be to the middle of the prop's meshes to grab it, in metres.
@export var pickup_radius := 4.0
## Size of the prop's largest side while carried (and after it's thrown), in metres.
@export var held_size := 0.9
@export var throw_speed := 17.0
## Extra upward lift on top of the camera direction (0 = straight along the view).
@export var throw_lift := 0.45
@export var gravity := 14.0
## The water it's meant to be thrown into (a StylizedWater, e.g. the frog lake).
@export var target_water: MeshInstance3D
@export var pickup_key := "THROW_PICKUP_PROMPT"
@export var throw_key := "THROW_THROW_PROMPT"
@export var player_group: StringName = &"player"

const PROMPT_SCENE = preload("res://ui/in_game/interaction/interaction_prompt.tscn")
const HAND_PATH := ^"Robot/root/Skeleton3D/hand_r"

enum State { RESTING, HELD, FLYING }

var state := State.RESTING
## Set when it has come down in target_water; it can't be picked up again then.
var in_target := false

var _player: Node3D
var _prompt: CanvasLayer
var _bodies: Array[Node] = []
var _center := Vector3.ZERO  # middle of the meshes, in the prop's unscaled local space
var _scale := 1.0
var _velocity := Vector3.ZERO
var _terrain: Terrain3D
var _home: Transform3D  # where it rested at start; it goes back there if thrown into the void
var _throw_y := 0.0


func _ready() -> void:
	process_priority = 100  # after LIRA has moved and animated
	var box := _local_aabb(prop, Transform3D.IDENTITY)
	_center = box.get_center()
	var biggest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	_scale = held_size / biggest if biggest > 0.0 else 1.0
	_collect_bodies(prop)
	_home = prop.global_transform
	_prompt = PROMPT_SCENE.instantiate()
	add_child(_prompt)
	_prompt.configure(&"interact", pickup_key)


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(player_group) as Node3D
	match state:
		State.RESTING:
			_prompt.set_available(_can_pick_up())
		State.HELD:
			_prompt.set_available(_can_act())
			_follow_hand()
		State.FLYING:
			_prompt.set_available(false)


func _physics_process(delta: float) -> void:
	if state != State.FLYING:
		return
	var from := prop.global_position + prop.global_basis * _center
	_velocity.y -= gravity * delta
	var to := from + _velocity * delta
	if to.y < _throw_y - 150.0:
		# Missed everything (e.g. off the edge of the island): put it back.
		prop.global_transform = _home
		state = State.RESTING
		_set_bodies_enabled(true)
		_prompt.configure(&"interact", pickup_key)
		landed.emit(false)
		return
	if _in_water(to):
		_land(to, true)
		return
	# Start the ray a little above: skimming a slope, a ray from right at the surface can
	# slip under it, and from underground it never hits anything again.
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.5, to)
	if _player is CollisionObject3D:
		query.exclude = [(_player as CollisionObject3D).get_rid()]
	var hit := prop.get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		_land(hit.position, _in_water(hit.position))
		return
	var ground := _ground_height(to)
	if to.y < ground:  # still went under: put it on the surface
		var on_ground := Vector3(to.x, ground, to.z)
		_land(on_ground, _in_water(on_ground))
		return
	prop.global_position += to - from
	prop.rotate_object_local(Vector3.RIGHT, delta * 4.0)  # tumble


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed(&"interact"):
		return
	if state == State.RESTING and _can_pick_up():
		get_viewport().set_input_as_handled()
		_prompt.play_activation()
		pick_up()
	elif state == State.HELD and _can_act():
		get_viewport().set_input_as_handled()
		_prompt.play_activation()
		throw()


func pick_up() -> void:
	state = State.HELD
	_set_bodies_enabled(false)
	_prompt.configure(&"interact", throw_key)
	# Shrink into the hand instead of popping.
	var t := create_tween()
	t.tween_method(_set_size, prop.scale.x, _scale, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	picked_up.emit()


func throw() -> void:
	var cam := _player.find_child("Camera3D", true, false) as Camera3D
	var dir := -cam.global_basis.z if cam else -_player.global_basis.z
	_velocity = (dir + Vector3.UP * throw_lift).normalized() * throw_speed
	_set_size(_scale)
	_throw_y = (prop.global_transform * _center).y
	state = State.FLYING
	thrown.emit()


func _land(point: Vector3, in_water: bool) -> void:
	state = State.RESTING
	in_target = in_water
	# Stand it upright where it came down.
	prop.global_basis = Basis(Vector3.UP, prop.global_rotation.y).scaled(Vector3.ONE * _scale)
	prop.global_position = point - Vector3(0, _local_aabb(prop, Transform3D.IDENTITY).position.y * _scale, 0)
	_prompt.configure(&"interact", pickup_key)
	if not in_water:
		_set_bodies_enabled(true)
	landed.emit(in_water)


func _follow_hand() -> void:
	var hand := _player.get_node_or_null(HAND_PATH) as Node3D
	var body := _player.get_node_or_null(^"Robot") as Node3D
	if hand == null or body == null:
		return
	# LIRA's model faces its +Z; hold the prop just in front of the palm, upright.
	var facing := body.global_basis.orthonormalized()
	var size := prop.scale.x
	prop.global_basis = facing.scaled(Vector3.ONE * size)
	prop.global_position = hand.global_position + facing.z * 0.25 - facing * (_center * size) + Vector3(0, 0.1, 0)


func _ground_height(point: Vector3) -> float:
	if _terrain == null or not is_instance_valid(_terrain):
		var found := get_tree().root.find_children("*", "Terrain3D", true, false)
		if found.is_empty():
			return -INF
		_terrain = found[0]
	var h: float = _terrain.data.get_height(point)
	return -INF if is_nan(h) else h


func _set_size(s: float) -> void:
	prop.scale = Vector3.ONE * s


func _can_pick_up() -> bool:
	if in_target or _player == null or not _can_act():
		return false
	return _player.global_position.distance_to(prop.global_transform * _center) <= pickup_radius


func _can_act() -> bool:
	if _player == null or get_tree().paused or (&"frozen" in _player and _player.frozen):
		return false
	var dialogic := get_node_or_null(^"/root/Dialogic")
	return dialogic == null or dialogic.current_timeline == null


## Came down in the water: inside its footprint and no higher than its surface right now
## (a drained lake sits far below its bed, so landing on the dry bed doesn't count).
func _in_water(point: Vector3) -> bool:
	return target_water != null and _in_footprint(point) and point.y <= target_water.global_position.y + 0.3


func _in_footprint(point: Vector3) -> bool:
	# Water fitted to its basin knows its exact shape (white = water).
	var img: Image = target_water.get(&"_basin_image")
	if img:
		var r: Vector4 = target_water.get(&"_basin_rect")
		var u := (point.x - r.x + r.z) / (2.0 * r.z)
		var v := (point.z - r.y + r.w) / (2.0 * r.w)
		if u < 0.0 or u >= 1.0 or v < 0.0 or v >= 1.0:
			return false
		return img.get_pixel(int(u * img.get_width()), int(v * img.get_height())).r > 0.5
	var plane := target_water.mesh as PlaneMesh
	var half := plane.size * 0.5 if plane else Vector2(20, 20)
	var p := target_water.to_local(point)
	return absf(p.x) <= half.x and absf(p.z) <= half.y


func _collect_bodies(node: Node) -> void:
	for c in node.get_children():
		if c is CollisionObject3D or c is NavigationObstacle3D:
			_bodies.append(c)
		else:
			_collect_bodies(c)


func _set_bodies_enabled(on: bool) -> void:
	for b in _bodies:
		b.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func _local_aabb(node: Node, xform: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	for c in node.get_children():
		if not c is Node3D:
			continue
		var t: Transform3D = xform * (c as Node3D).transform
		var b := AABB()
		var has := false
		if c is VisualInstance3D:
			b = t * (c as VisualInstance3D).get_aabb()
			has = true
		var sub := _local_aabb(c, t)
		if sub.has_volume():
			b = b.merge(sub) if has else sub
			has = true
		if has:
			box = b if first else box.merge(b)
			first = false
	return box
