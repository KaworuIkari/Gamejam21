class_name WaterFlowSwitch
extends Node3D
## Turns a chain of water on, one piece after another, like water reaching each part of the
## river. List the pieces in `water` in upstream-to-downstream order (StylizedWater, WaterFall,
## WaterCascade, or any Node3D). They are hidden at start and come on when `turn_on()` runs,
## which happens when `trigger` is used (or call it from code / a signal yourself).
## Rivers and pools rise up from below their placed height; everything else just appears.
## Particles (spray, mist) under each piece restart when it comes on.
## With `irrigate` on, the ground along each piece is watered through GrowthMap as it
## comes on, spreading out from where the water enters, so the banks green up by themselves.

signal finished

## Using this trigger turns the water on (no signal wiring needed).
@export var trigger: InteractTrigger
@export var water: Array[Node3D] = []
## Reported to the quests once the water has finished flowing (e.g. "pump_started").
@export var quest_event: StringName = &""
## Start already flowing (handy for testing the level without interacting).
@export var start_on := false
## Seconds between one piece starting and the next.
@export var stagger := 1.2
## How long a river takes to fill up.
@export var fill_time := 2.0
## How far below its placed height a river starts.
@export var fill_depth := 1.5
## Shown/hidden when the water comes on, e.g. swap Ruined_Pump_House_Wasteland for _Revival.
@export var show_on_flow: Array[Node3D] = []
@export var hide_on_flow: Array[Node3D] = []

@export_group("Rising water")
## Water that is already there but low (e.g. the lake). It starts `rise_height` below its
## placed height and rises to it once the chain above has started. Place it at the full level.
@export var rise: Array[Node3D] = []
@export var rise_height := 6.0
@export var rise_time := 8.0
## Green spreading out from the centre of each rising water while it rises, in metres
## (0 = off). Unlike irrigation it ignores height, so it also climbs the slopes.
@export var rise_bloom_radius := 0.0

@export_group("Irrigation")
@export var irrigate := true
## Ground up to this many metres above the water surface counts as bank and gets watered.
## Raise it to green more of the slopes, lower it to keep the green to the shoreline.
@export var bank_height := 2.5
## How far past the edge of each water mesh to look for bank, in metres.
@export var bank_width := 8.0
## Distance between watering splashes, in metres. Smaller = smoother edge, more work.
@export var bank_spacing := 4.0
## Seconds for the watering to sweep across one piece of water.
@export var irrigate_time := 4.0
## Leave empty to use the first Terrain3D in the scene.
@export var terrain: Terrain3D

var is_on := false
var _rest_y := {}


func _ready() -> void:
	if trigger and not trigger.interacted.is_connected(turn_on):
		trigger.interacted.connect(turn_on)
	for piece in water + rise:
		if piece:
			_rest_y[piece] = piece.position.y
	if start_on:
		is_on = true
		_apply_swaps()
		if irrigate:
			_irrigate_all_now.call_deferred() # after Terrain3D has loaded its data
		return
	for piece in water:
		if piece:
			piece.visible = false
			_set_particles(piece, false)
	for piece in rise:
		if piece:
			if piece is StylizedWater: # its basin is traced at the full height
				piece.full_level = piece.global_position.y
			piece.position.y = _rest_y[piece] - rise_height


func turn_on() -> void:
	if is_on:
		return
	is_on = true
	_apply_swaps()
	var tween := create_tween()
	var from := global_position # the first piece is fed from the switch (the pump)
	for i in water.size():
		var piece := water[i]
		if piece == null:
			continue
		if i > 0:
			tween.tween_interval(stagger)
		tween.tween_callback(_start_piece.bind(piece, from))
		from = _outlet(piece)
	if not rise.is_empty():
		tween.tween_callback(_start_rise.bind(from))
	tween.tween_interval(maxf(maxf(fill_time, irrigate_time), rise_time if not rise.is_empty() else 0.0))
	tween.tween_callback(finished.emit)
	tween.tween_callback(_report_quest)


func _start_piece(piece: Node3D, from: Vector3) -> void:
	if irrigate:
		_irrigate(piece, from, irrigate_time) # before the river is lowered: uses its rest height
	piece.visible = true
	_set_particles(piece, true)
	if piece is StylizedWater:
		var rest: float = _rest_y[piece]
		piece.position.y = rest - fill_depth
		create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT) \
				.tween_property(piece, "position:y", rest, fill_time)


func _start_rise(from: Vector3) -> void:
	for piece in rise:
		if piece == null:
			continue
		var rest: float = _rest_y[piece]
		if irrigate: # the banks of the full lake, measured at its full height
			var low := piece.position.y
			piece.position.y = rest
			_irrigate(piece, from, rise_time)
			piece.position.y = low
		if rise_bloom_radius > 0.0:
			GrowthMap.reveal_from(piece.global_position, rise_time, rise_bloom_radius)
		create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT) \
				.tween_property(piece, "position:y", rest, rise_time)


func _report_quest() -> void:
	var quests := get_node_or_null(^"/root/Quests")
	if quests:
		quests.report(quest_event)


func _apply_swaps() -> void:
	for n in show_on_flow:
		if n:
			n.visible = true
	for n in hide_on_flow:
		if n:
			n.visible = false


func _set_particles(root: Node, on: bool) -> void:
	for p in root.find_children("*", "GPUParticles3D", true, false):
		p.emitting = on
		if on:
			p.restart()


# --- Irrigation ----------------------------------------------------------------

func _irrigate_all_now() -> void:
	var from := global_position
	for piece in water + rise:
		if piece:
			_irrigate(piece, from, 0.0)
			from = _outlet(piece)


## Waters the bank around one piece, nearest-to-`from` first, over `duration` seconds.
func _irrigate(piece: Node3D, from: Vector3, duration: float) -> void:
	var points := _bank_points(piece)
	if points.is_empty():
		return
	points.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.distance_squared_to(from) < b.distance_squared_to(from))
	if duration <= 0.0:
		for p in points:
			GrowthMap.water(p, bank_spacing)
		return
	var state := {"next": 0}
	create_tween().tween_method(_water_up_to.bind(points, state), 0.0, float(points.size()), duration)


func _water_up_to(count: float, points: Array[Vector3], state: Dictionary) -> void:
	var end := mini(ceili(count), points.size())
	while state.next < end:
		GrowthMap.water(points[state.next], bank_spacing)
		state.next += 1


## Spots to water: for a water surface, a grid over its footprint (plus `bank_width`)
## wherever the ground is no higher than `bank_height` above the water; for a fall or
## cascade, a line from its Top to its Bottom marker plus a wider ring at the bottom.
func _bank_points(piece: Node3D) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var mi := piece as MeshInstance3D
	if mi and mi.mesh:
		var t := _get_terrain()
		var xf := mi.global_transform
		var sx := maxf(xf.basis.x.length(), 0.001)
		var sz := maxf(xf.basis.z.length(), 0.001)
		var box := mi.mesh.get_aabb()
		var surface := xf.origin.y
		var x := box.position.x - bank_width / sx
		while x <= box.end.x + bank_width / sx:
			var z := box.position.z - bank_width / sz
			while z <= box.end.z + bank_width / sz:
				var p := xf * Vector3(x, 0.0, z)
				if t == null:
					points.append(p)
				else:
					var h: float = t.data.get_height(p)
					if not is_nan(h) and h <= surface + bank_height:
						points.append(Vector3(p.x, h, p.z))
				z += bank_spacing / sz
			x += bank_spacing / sx
		return points

	var top := piece.get_node_or_null(^"Top") as Node3D
	var bottom := piece.get_node_or_null(^"Bottom") as Node3D
	var a := top.global_position if top else piece.global_position
	var b := bottom.global_position if bottom else piece.global_position
	var steps := maxi(1, int(a.distance_to(b) / bank_spacing))
	for i in steps + 1:
		points.append(a.lerp(b, float(i) / steps))
	for k in 8: # the plunge pool / landing splashes wider
		var ang := TAU * k / 8.0
		points.append(b + Vector3(cos(ang), 0.0, sin(ang)) * bank_width * 0.6)
	return points


## Where water leaves a piece, so the next piece greens outward from there.
func _outlet(piece: Node3D) -> Vector3:
	var bottom := piece.get_node_or_null(^"Bottom") as Node3D
	return bottom.global_position if bottom else piece.global_position


func _get_terrain() -> Terrain3D:
	if terrain == null or not is_instance_valid(terrain):
		var found := get_tree().root.find_children("*", "Terrain3D", true, false)
		terrain = found[0] if not found.is_empty() else null
	return terrain if terrain and terrain.data else null
