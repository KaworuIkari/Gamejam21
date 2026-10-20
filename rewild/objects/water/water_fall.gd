@tool
class_name WaterFall
extends Node3D
## A waterfall over a ledge. Put `Top` on the lip of the upper river and `Bottom` in the plunge
## pool; the curtain arcs between them like thrown water, with splash and mist at the base.
## The curtain mesh is rebuilt from the markers and never saved into the level.

@export var material: ShaderMaterial:
	set(v):
		material = v
		_dirty = true
@export var width := 4.0:
	set(v):
		width = v
		_dirty = true
## Extra width at the bottom, as a fraction (water fans out as it falls).
@export_range(0.0, 1.0) var spread := 0.2:
	set(v):
		spread = v
		_dirty = true
## How far the curtain reaches back into the upper river, so the lip has no visible start.
@export var lip_length := 1.5:
	set(v):
		lip_length = v
		_dirty = true

@onready var _top: Marker3D = $Top
@onready var _bottom: Marker3D = $Bottom
@onready var _lip_splash: Node3D = $LipFoam
@onready var _base_splash: Node3D = $BaseSplash

var _curtain: MeshInstance3D
var _dirty := true
var _last_key := ""


func _ready() -> void:
	_curtain = MeshInstance3D.new()
	_curtain.name = "Curtain"
	_curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_curtain, false, Node.INTERNAL_MODE_FRONT) # internal + unowned: not saved
	_rebuild()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_rebuild() # follow the markers while they're dragged


func _rebuild() -> void:
	if _curtain == null:
		return
	var key := "%s|%s" % [_top.position, _bottom.position]
	if key == _last_key and not _dirty:
		return
	_last_key = key
	_dirty = false

	var drop := _top.position.y - _bottom.position.y
	var reach := Vector3(_bottom.position.x - _top.position.x, 0, _bottom.position.z - _top.position.z)
	var forward := reach.normalized() if reach.length() > 0.01 else Vector3.FORWARD
	var side := Vector3.UP.cross(forward).normalized()
	_lip_splash.position = _top.position + forward * 0.3
	_base_splash.position = _bottom.position
	if drop < 0.1:
		_curtain.mesh = null
		return

	# Profile: a short lip lying in the upper river, then a projectile arc
	# (horizontal reach grows with sqrt of the fall, so water leaves the lip level).
	var profile: Array[Vector3] = []
	var widths: Array[float] = []
	const LIP_STEPS := 4
	const FALL_STEPS := 40
	const COLUMNS := 8
	for i in LIP_STEPS:
		var f := float(i) / LIP_STEPS
		profile.append(_top.position - forward * lip_length * (1.0 - f) + Vector3.DOWN * 0.15 * (1.0 - f))
		widths.append(width)
	for i in FALL_STEPS + 1:
		var s := float(i) / FALL_STEPS
		profile.append(_top.position + reach * sqrt(s) + Vector3.DOWN * drop * s)
		widths.append(width * (1.0 + spread * s))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v := 0.0
	for i in profile.size():
		if i > 0:
			v += profile[i].distance_to(profile[i - 1])
		var tangent := profile[mini(i + 1, profile.size() - 1)] - profile[maxi(i - 1, 0)]
		var normal := tangent.cross(side).normalized() # faces up on the lip, outward on the fall
		for j in COLUMNS + 1:
			var u := float(j) / COLUMNS
			st.set_normal(normal)
			st.set_uv(Vector2(u, v))
			st.add_vertex(profile[i] + side * widths[i] * (u - 0.5))
	for i in profile.size() - 1:
		for j in COLUMNS:
			var a := i * (COLUMNS + 1) + j
			var b := a + COLUMNS + 1
			for idx in [a, a + 1, b, a + 1, b + 1, b]:
				st.add_index(idx)
	var mesh := st.commit()
	mesh.surface_set_material(0, material)
	_curtain.mesh = mesh
