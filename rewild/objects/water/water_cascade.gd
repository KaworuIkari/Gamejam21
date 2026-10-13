@tool
class_name WaterCascade
extends Node3D
## Rapids between two rivers. Drag the `Top` and `Bottom` markers onto the upper and lower
## water; the flowing surface stretches between them and a splash sits at each end.

@export var width := 4.0:
	set(v):
		width = v
		_last_key = ""
## Raise the surface a little so it doesn't sink into the terrain along the slope.
@export var lift := 0.15:
	set(v):
		lift = v
		_last_key = ""

@onready var _top: Marker3D = $Top
@onready var _bottom: Marker3D = $Bottom
@onready var _surface: MeshInstance3D = $Surface
@onready var _top_splash: Node3D = $TopSplash
@onready var _bottom_splash: Node3D = $BottomSplash

var _last_key := ""


func _ready() -> void:
	_update()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_update() # follow the markers while they're dragged


func _update() -> void:
	var key := "%s|%s" % [_top.position, _bottom.position]
	if key == _last_key:
		return
	_last_key = key
	var span := _bottom.position - _top.position
	if span.length() < 0.01:
		return
	var z := span.normalized()
	var x := Vector3.UP.cross(z)
	x = x.normalized() if x.length() > 0.001 else Vector3.RIGHT
	var y := z.cross(x)
	# The surface mesh is a 1x1 plane, so scale stretches it to width x length.
	_surface.transform = Transform3D(Basis(x * width, y, z * span.length()),
			(_top.position + _bottom.position) * 0.5 + y * lift)
	_top_splash.position = _top.position
	_bottom_splash.position = _bottom.position
	for splash in [_top_splash, _bottom_splash]:
		var emitter := splash.get_node_or_null("Spray") as GPUParticles3D
		if emitter:
			(emitter.process_material as ParticleProcessMaterial).emission_box_extents.x = width * 0.4
