extends Node3D
## Orbit preview / simple first-person collision inspection. No addons required.
var camera: Camera3D
var player: CharacterBody3D
var orbit_yaw := 0.65
var orbit_pitch := -0.35
var distance := 32.0
var target := Vector3(-1, 7, 0)
var walking := false
var dragging := false
var label: Label

func _ready() -> void:
	camera = Camera3D.new()
	camera.far = 300.0
	add_child(camera)
	camera.current = true
	player = CharacterBody3D.new()
	player.position = Vector3(0, 0.02, 13)
	player.floor_snap_length = 0.35
	add_child(player)
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.8
	collider.shape = capsule
	collider.position.y = 0.9
	player.add_child(collider)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.19, 0.25, 0.14)
	$Ground.material_override = ground_material
	var canvas := CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	label.position = Vector2(20, 18)
	label.add_theme_font_size_override("font_size", 18)
	canvas.add_child(label)
	_update_label()
	_update_camera()

func _update_label() -> void:
	label.text = "FANTASY FOREST / SAMPLE 01\nDrag LMB: orbit | Wheel: zoom | Tab: walk/orbit\nWalk: WASD + mouse | Space: jump (stairs) | Esc: release mouse\n1: overview  2: house  3: arch  R: reset walk position\nMode: " + ("WALK" if walking else "ORBIT")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			walking = not walking
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if walking else Input.MOUSE_MODE_VISIBLE
			_update_label()
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if event.keycode == KEY_R:
			player.position = Vector3(0, 0.02, 13)
			player.velocity = Vector3.ZERO
		if not walking:
			if event.keycode == KEY_1:
				target = Vector3(-1, 7, 0); distance = 32
			if event.keycode == KEY_2:
				target = Vector3(3.55, 5, 0); distance = 12
			if event.keycode == KEY_3:
				target = Vector3(-8, 2.4, 1); distance = 10
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if walking and event.pressed: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if not walking and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP: distance = maxf(4, distance * 0.9)
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = minf(70, distance * 1.1)
	if event is InputEventMouseMotion:
		if (walking and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED) or (not walking and dragging):
			orbit_yaw -= event.relative.x * 0.005
			orbit_pitch = clampf(orbit_pitch - event.relative.y * 0.005, -1.35, 1.15)

func _physics_process(delta: float) -> void:
	if walking:
		var input := Vector3.ZERO
		if Input.is_physical_key_pressed(KEY_W): input.z -= 1
		if Input.is_physical_key_pressed(KEY_S): input.z += 1
		if Input.is_physical_key_pressed(KEY_A): input.x -= 1
		if Input.is_physical_key_pressed(KEY_D): input.x += 1
		var direction := Basis(Vector3.UP, orbit_yaw) * input.normalized()
		player.velocity.x = direction.x * 4
		player.velocity.z = direction.z * 4
		if not player.is_on_floor(): player.velocity.y -= 18 * delta
		elif Input.is_physical_key_pressed(KEY_SPACE): player.velocity.y = 5.5
		else: player.velocity.y = -0.2
		# Lift onto a .2m stair only if a forward move is blocked and space above is clear.
		var motion := Vector3(player.velocity.x, 0, player.velocity.z) * delta
		if player.is_on_floor() and motion.length_squared() > 0:
			if player.test_move(player.global_transform, motion):
				var raised := player.global_transform
				raised.origin.y += 0.24
				if not player.test_move(player.global_transform, Vector3.UP * 0.24) and not player.test_move(raised, motion):
					player.position.y += 0.24
		player.move_and_slide()
		if player.position.y < -10: player.position = Vector3(0, 0.02, 13)
	_update_camera()

func _update_camera() -> void:
	if walking:
		camera.position = player.position + Vector3(0, 1.65, 0)
		camera.rotation = Vector3(orbit_pitch, orbit_yaw, 0)
	else:
		camera.position = target + Basis.from_euler(Vector3(orbit_pitch, orbit_yaw, 0)) * Vector3(0, 0, distance)
		camera.look_at(target)
