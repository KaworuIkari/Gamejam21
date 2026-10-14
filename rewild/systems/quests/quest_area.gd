class_name QuestArea extends Area3D
## Reports `event` to the quests the first time the player walks in, e.g. "reached_spring".
## Give it a CollisionShape3D child, or it makes a sphere of `radius`.

@export var event: StringName = &""
@export var radius := 6.0
@export var once := true
@export var player_group: StringName = &"player"

var _done := false


func _ready() -> void:
	var has_shape := false
	for c in get_children():
		if c is CollisionShape3D or c is CollisionPolygon3D:
			has_shape = true
	if not has_shape:
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = radius
		shape.shape = sphere
		add_child(shape)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if (once and _done) or not (body.is_in_group(player_group) or (body is CharacterBody3D and &"frozen" in body)):
		return
	_done = true
	var quests := get_node_or_null(^"/root/Quests")
	if quests:
		quests.report(event)
