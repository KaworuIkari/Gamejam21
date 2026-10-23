class_name GrassTrample extends Node
## Grass bends away from the player's feet and springs back behind them. Feeds the recent
## footprints to meadow_grass.gdshader (trample_points); add it under the level.

const POINTS := 8  # must match TRAMPLE_POINTS in meadow_grass.gdshader

@export var material: ShaderMaterial
@export var player: Node3D
@export var spacing := 0.6       # metres walked before a new footprint is left behind
@export var recover_time := 2.0  # seconds a footprint takes to spring back

var _points := PackedVector4Array()
var _head := 0


func _ready() -> void:
	_points.resize(POINTS)


func _process(delta: float) -> void:
	if material == null or not is_instance_valid(player):
		return
	var fade := delta / recover_time
	for i in POINTS:
		_points[i].w = maxf(0.0, _points[i].w - fade)
	var p := player.global_position
	var grounded: bool = player.is_on_floor() if player is CharacterBody3D else true
	var head := _points[_head]
	if grounded:
		if head.w > 0.0 and Vector2(p.x - head.x, p.z - head.z).length() > spacing:
			_head = (_head + 1) % POINTS  # leave this footprint behind to recover
		_points[_head] = Vector4(p.x, p.y, p.z, 1.0)
	material.set_shader_parameter(&"trample_points", _points)
