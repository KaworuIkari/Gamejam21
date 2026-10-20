extends CanvasLayer
## Attached to the player; renders in the main viewport above pixelated 3D.
const Gauge = preload("res://ui/in_game/jetpack/jetpack_gauge.gd")
const UIScaler = preload("res://ui/layout/ui_scaler.gd")
const FULL_LINGER := 0.8

var _player: CharacterBody3D
var _gauge: Control
var _linger := 0.0
var _alpha := 0.0
var _display_ratio := 1.0
var _clock := 0.0

func configure(player: CharacterBody3D) -> void:
	_player = player

func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_viewport = get_tree().root
	_gauge = Gauge.new()
	_gauge.name = "EnergyGauge"
	_gauge.size = Vector2(88, 210)
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gauge)
	_gauge.hide()

func _process(delta: float) -> void:
	if not is_instance_valid(_player) or not _player.jetpack.visible:
		_gauge.hide()
		return
	var dialogic := get_node_or_null("/root/Dialogic")
	var blocked: bool = get_tree().paused or _player.frozen or SceneRouter.is_busy()
	blocked = blocked or (dialogic != null and dialogic.current_timeline != null)
	if blocked:
		_gauge.hide()
		_alpha = 0.0
		return
	var camera: Camera3D = _player.camera_3d
	if not is_instance_valid(camera) or not camera.is_current():
		_gauge.hide()
		return
	var world_point := _player.global_position + Vector3.UP * 0.9
	if camera.is_position_behind(world_point):
		_gauge.hide()
		return
	var actual: float = clampf(_player.energy / maxf(_player.max_energy, 0.001), 0.0, 1.0)
	var active: bool = _player._jet_armed or _player._thrusting
	if active or actual < 0.999:
		_linger = FULL_LINGER
	else:
		_linger = maxf(0.0, _linger - delta)
	_alpha = move_toward(_alpha, 1.0 if active or actual < 0.999 or _linger > 0 else 0.0, delta * 6.0)
	_display_ratio = move_toward(_display_ratio, actual, delta * 4.0)
	# Empty must read empty immediately, rather than suggesting usable energy.
	if actual <= 0.0:
		_display_ratio = 0.0
	_clock += delta
	_gauge.ratio = _display_ratio
	_gauge.thrusting = active
	_gauge.clock = _clock
	_gauge.modulate.a = _alpha
	_gauge.visible = _alpha > 0.001
	_place(camera, world_point)
	if _gauge.visible:
		_gauge.queue_redraw()

func _place(camera: Camera3D, world_point: Vector3) -> void:
	var point := camera.unproject_position(world_point)
	var viewport := camera.get_viewport()
	var container := viewport.get_parent() as SubViewportContainer
	if container:
		point *= container.size / Vector2(viewport.size)
		point = container.get_global_transform_with_canvas() * point
	var factor := UIScaler.factor()
	# Prevent exaggerated HUD sizes on very small windows.
	factor = minf(factor, get_tree().root.get_visible_rect().size.y / 420.0)
	_gauge.scale = Vector2.ONE * factor
	var extent := _gauge.size * factor
	var screen := get_tree().root.get_visible_rect().size
	var desired := point + Vector2(36, -105) * factor
	_gauge.position = Vector2(clampf(desired.x, 12, maxf(12, screen.x - extent.x - 12)), clampf(desired.y, 12, maxf(12, screen.y - extent.y - 12)))
