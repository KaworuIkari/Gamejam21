extends CanvasLayer
## Attached to the player; shows LIRA's face screen live in the top-right corner.
## The screen material comes from RobotFace, so moods, transitions and glitches match the 3D screen.
const UIScaler = preload("res://ui/layout/ui_scaler.gd")
const SIZE := 112.0     # screen edge, in 1080p design pixels
const BEZEL := 8.0
const MARGIN := 24.0

var _player: CharacterBody3D
var _frame: Panel
var _alpha := 0.0

func configure(player: CharacterBody3D) -> void:
	_player = player

func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_viewport = get_tree().root
	_frame = Panel.new()
	_frame.name = "FaceFrame"
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.size = Vector2.ONE * (SIZE + BEZEL * 2.0)
	var bezel := StyleBoxFlat.new()
	bezel.bg_color = Color(0.07, 0.09, 0.1, 0.92)
	bezel.border_color = Color(0.55, 0.62, 0.6, 0.7)
	bezel.set_border_width_all(2)
	bezel.set_corner_radius_all(14)
	bezel.shadow_color = Color(0, 0, 0, 0.25)
	bezel.shadow_size = 6
	_frame.add_theme_stylebox_override("panel", bezel)
	add_child(_frame)

	var screen := ColorRect.new()   # ColorRect gives the shader 0..1 UVs over the rect
	screen.name = "Screen"
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.position = Vector2.ONE * BEZEL
	screen.size = Vector2.ONE * SIZE
	screen.material = _player.face.make_hud_material()
	_frame.add_child(screen)

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		_frame.hide()
		return
	var camera: Camera3D = _player.camera_3d
	var shown: bool = not get_tree().paused and not SceneRouter.is_busy() \
		and is_instance_valid(camera) and camera.is_current()
	_alpha = move_toward(_alpha, 1.0 if shown else 0.0, delta * 6.0)
	_frame.modulate.a = _alpha
	_frame.visible = _alpha > 0.001
	if not _frame.visible:
		return
	var factor := UIScaler.factor()
	_frame.scale = Vector2.ONE * factor
	var screen := get_tree().root.get_visible_rect().size
	_frame.position = Vector2(screen.x - (_frame.size.x + MARGIN) * factor, MARGIN * factor)
