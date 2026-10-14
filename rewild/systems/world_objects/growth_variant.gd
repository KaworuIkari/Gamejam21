class_name GrowthVariant extends Node3D
## A plant that recovers with the ground under it: child 0 withered, 1 sprouting,
## 2 flourishing, picked from GrowthMap at this position. Watering the spot (or a
## bloom reaching it) brings it back; it never depends on the world stage directly.

## Growth (0..1) needed for each child after the first.
@export var thresholds := PackedFloat32Array([0.3, 0.7])

var _variants: Array[Node3D] = []
var _shown := -1
var _scales: Array[Vector3] = []
var _growth: Node
var _pending := false


func _ready() -> void:
	for c in get_children():
		if c is Node3D:
			_variants.append(c)
	for v in _variants:
		_scales.append(v.scale)
		remove_child(v)
	_show(0, true)
	_growth = get_node_or_null(^"/root/GrowthMap")
	if _growth:
		_growth.changed.connect(_queue_refresh)
		_refresh.call_deferred()


func _queue_refresh() -> void:
	# Out of the tree (e.g. inside a StageVariant child that's hidden): refresh on re-entry instead.
	if _pending or not is_inside_tree():
		return
	_pending = true
	# Growth changes every simulation tick; a few checks a second is plenty.
	await get_tree().create_timer(0.3).timeout
	_pending = false
	_refresh()


func _refresh() -> void:
	var g: float = _growth.sample(global_position)
	var i := 0
	while i < thresholds.size() and g >= thresholds[i]:
		i += 1
	_show(i, false)


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
	if not instant:
		var full := _scales[index]
		v.scale = full * 0.5
		var t := create_tween()
		t.tween_interval(randf() * 0.6)
		t.tween_property(v, "scale", full, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and _growth:
		_refresh.call_deferred()
	elif what == NOTIFICATION_PREDELETE:
		for v in _variants:
			if is_instance_valid(v) and v.get_parent() == null:
				v.free()
