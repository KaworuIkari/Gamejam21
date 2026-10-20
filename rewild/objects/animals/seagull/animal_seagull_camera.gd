extends AnimalSeagull

func _ready() -> void:
	super()
	CameraDirector.view_changed.connect(_on_camera_view_changed)

func _physics_process(delta: float) -> void:
	super(delta)
	_update_sing(delta)

@export_group("Camera")
@export var sing_delay := 1.0
var _sing_timer := -1.0
@onready var _sound_emitter: FmodEventEmitter3D = $FmodEventEmitter3D
@onready var _camera_view: CameraView = $PCam_Seagull/CameraView

func _on_camera_view_changed(previous: StringName, current: StringName) -> void:
	var mine := _camera_view.view_name
	if current == mine and previous != mine:
		_sing_timer = sing_delay
	elif current != mine:
		_sing_timer = -1.0  # left the view before the cry landed


func _update_sing(delta: float) -> void:
	if _sing_timer < 0.0:
		return
	_sing_timer -= delta
	if _sing_timer <= 0.0:
		_sing_timer = -1.0
		_sound_emitter.play()