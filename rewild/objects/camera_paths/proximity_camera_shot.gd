extends CameraPathShot
class_name ProximityCameraShot
## Plays the path shot the first time the player walks into `trigger`.
## Optionally keeps the camera aimed at `look_at` (e.g. the fox) instead of along the path.

@export var trigger: Area3D
## Leave empty to face along the path, like the pump shot.
@export var look_at: Node3D
@export var look_at_offset := Vector3(0.0, 0.3, 0.0)
## Index into BgmPlayer.QUEST_BGM_VAR; -1 keeps the current music.
@export var bgm_index := -1
@export var once := true
## Stops LIRA walking off while the camera is away.
@export var freeze_player := true

var _done := false


func _ready() -> void:
	super()
	if look_at:
		var pcam := $PhantomCamera3D as PhantomCamera3D
		pcam.look_at_mode = PhantomCamera3D.LookAtMode.SIMPLE
		pcam.look_at_target = look_at
		pcam.look_at_offset = look_at_offset
	if trigger:
		trigger.body_entered.connect(_on_body_entered)
	else:
		push_error("%s: ProximityCameraShot needs a trigger Area3D" % get_path())


func _on_body_entered(body: Node) -> void:
	if (once and _done) or not (body.is_in_group(&"player") or (body is CharacterBody3D and &"frozen" in body)):
		return
	_done = true
	var freeze: bool = freeze_player and &"frozen" in body and not body.get(&"frozen")
	if freeze:
		body.set(&"frozen", true)
	await play(bgm_index)
	if freeze and is_instance_valid(body):
		body.set(&"frozen", false)
