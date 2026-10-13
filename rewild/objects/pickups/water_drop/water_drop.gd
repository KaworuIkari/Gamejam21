extends Area3D
## Floating, bobbing water drop pickup. Emits `collected` when the player touches it.

signal collected(drop: Node3D)

@export var bob_height := 0.15
@export var bob_speed := 2.0
@export var spin_speed := 1.2
@export var player_group := &"player"

@onready var _visual: Node3D = $Visual

var _time := randf() * TAU
var _taken := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _taken:
		return
	_time += delta
	_visual.position.y = sin(_time * bob_speed) * bob_height
	_visual.rotation.y += spin_speed * delta


func _on_body_entered(body: Node3D) -> void:
	if _taken:
		return
	# Same player check as dialogue_trigger.gd.
	if not (body.is_in_group(player_group) or (body is CharacterBody3D and &"frozen" in body)):
		return
	_taken = true
	collected.emit(self)
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(_visual, "scale", Vector3.ONE * 1.3, 0.1)
	tween.tween_property(_visual, "scale", Vector3.ZERO, 0.2)
	tween.tween_callback(queue_free)
