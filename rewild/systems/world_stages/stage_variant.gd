class_name StageVariant extends Node3D
## Shows one child per world stage: child 0 in Wasteland, 1 in Revival, 2 in Golden.
## Stages past the last child keep the last one, so a two-child node (closed / open
## sluice gate) stays open from Revival on. `stage_map` remaps stages to children
## when that isn't enough, e.g. [0, 0, 1] switches only at Golden.
## Hidden variants are taken out of the tree so their collision doesn't linger.

## Empty = the first node in the "world_stages" group.
@export var stages: WorldStages
@export var stage_map: PackedInt32Array = []
## Seconds the new variant takes to grow in when the stage changes.
@export var pop_time := 0.6

var _variants: Array[Node3D] = []
var _shown := -1
var _scales: Array[Vector3] = []


func _ready() -> void:
	for c in get_children():
		if c is Node3D:
			_variants.append(c)
	for v in _variants:
		_scales.append(v.scale)
		remove_child(v)
	_show(0, true)
	_connect.call_deferred()


func _connect() -> void:
	if stages == null:
		stages = get_tree().get_first_node_in_group(&"world_stages") as WorldStages
	if stages == null:
		return
	stages.stage_changed.connect(func(i: int, _st: WorldStage) -> void: _show(_child_for(i), false))
	if stages.current >= 0:
		_show(_child_for(stages.current), true)


func _child_for(stage: int) -> int:
	if stage >= 0 and stage < stage_map.size():
		return stage_map[stage]
	return stage


func _show(index: int, instant: bool) -> void:
	if _variants.is_empty():
		return
	index = clampi(index, 0, _variants.size() - 1)
	if index == _shown:
		return
	if _shown >= 0:
		remove_child(_variants[_shown])
	_shown = index
	var v := _variants[index]
	v.visible = true
	add_child(v)
	if not instant and pop_time > 0.0:
		var full := _scales[index]
		v.scale = full * 0.92
		create_tween().tween_property(v, "scale", full, pop_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _notification(what: int) -> void:
	# Variants out of the tree aren't freed with us; free them ourselves.
	if what == NOTIFICATION_PREDELETE:
		for v in _variants:
			if is_instance_valid(v) and v.get_parent() == null:
				v.free()
