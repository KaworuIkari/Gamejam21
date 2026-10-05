class_name GrowthProp extends Node3D
## Makes this node react to the GrowthMap autoload at its position.
## - grow_in: hidden (scale 0) on barren ground, pops up once the ground turns green.
## - moss: adds a moss overlay to every mesh below this node that thickens with growth.
## Put props (bushes, trees, ruins...) as children of a GrowthProp, or attach
## this script to the prop's root.

const MOSS_MATERIAL := preload("res://world_stages/materials/moss_overlay.tres")

@export var grow_in := true
## Growth (0..1) needed before this prop appears.
@export_range(0.0, 1.0) var threshold := 0.55
@export var grow_time := 1.2
## Random extra delay so neighbouring props don't all pop on the same frame.
@export var max_random_delay := 1.5
@export var moss := false

var _full_scale := Vector3.ONE
var _grown := false
var _moss_amount := -1.0
var _meshes: Array[GeometryInstance3D] = []
var _growth: Node


func _ready() -> void:
	_growth = get_node_or_null("/root/GrowthMap")
	_full_scale = scale
	if moss:
		for n in find_children("*", "GeometryInstance3D", true, false):
			var gi := n as GeometryInstance3D
			gi.material_overlay = MOSS_MATERIAL
			_meshes.append(gi)
	if _growth == null:
		return  # No growth system (e.g. a static scene): stay fully grown.
	if grow_in:
		scale = Vector3.ONE * 0.001
		visible = false
	_growth.changed.connect(_refresh)
	_refresh.call_deferred()


func _refresh() -> void:
	var g: float = _growth.sample(global_position)
	if moss:
		var target := smoothstep(0.2, 0.9, g)
		if absf(target - _moss_amount) > 0.01:
			_moss_amount = target
			for gi in _meshes:
				gi.set_instance_shader_parameter("moss_amount", target)
	if grow_in and not _grown and g >= threshold:
		_grown = true
		visible = true
		var t := create_tween()
		t.tween_interval(randf() * max_random_delay)
		t.tween_property(self, "scale", _full_scale, grow_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif grow_in and _grown and g < threshold * 0.5:
		# Growth was cleared (new game / debug reset).
		_grown = false
		scale = Vector3.ONE * 0.001
		visible = false
