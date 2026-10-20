class_name WaterRefill
extends Node
## Filling LIRA's water tank: beside a water source (an activated WaterWell, or a lake, pond
## or river: any visible StylizedWater with `drinkable` on), hold interact and the tank
## fills (empty to full in WaterTank.refill_time, 1 s); its water rises while held.
## The level creates one of these.

const HOLD_PROMPT_SCENE = preload("res://ui/in_game/interaction/clear_hold_prompt.tscn")

@export var prompt_key := "WATER_REFILL_PROMPT"
## Standing this close to the water's edge counts as beside it, in metres.
@export var shore_reach := 1.5
## Feet at most this far above the water surface (and up to `depth` below it).
@export var shore_height := 1.5
@export var depth := 4.0

var _prompt: CanvasLayer
var _filling := false
## E must be pressed while already at a source (not still held from starting a well).
var _armed := false


func _ready() -> void:
	_prompt = HOLD_PROMPT_SCENE.instantiate()
	add_child(_prompt)
	_prompt.configure(&"interact", prompt_key)


func _process(delta: float) -> void:
	var lira := get_tree().get_first_node_in_group(&"player") as LIRA_Character
	var dialogic := get_node_or_null(^"/root/Dialogic")
	var can := lira != null and lira.has_water_gun and lira.tank.level < 1.0 \
			and not get_tree().paused and (dialogic == null or dialogic.current_timeline == null) \
			and near_source(lira.global_position)
	_prompt.set_available(can)
	var held := Input.is_action_pressed(&"interact")
	if not can or not held:
		_armed = can
	var filling := can and held and _armed
	if filling:
		lira.tank.refill(delta)
	if filling != _filling:
		_filling = filling
		if lira:
			lira.tank.set_filling(filling)  # the fill sound
		if not filling and lira and lira.tank.level >= 1.0:
			_prompt.play_activation()
	_prompt.set_hold_progress(lira.tank.level if filling else 0.0)


## Beside an activated well or the edge of a drinkable water.
func near_source(at: Vector3) -> bool:
	for well in get_tree().get_nodes_in_group(&"water_sources"):
		if well is WaterWell and well.player_near():
			return true
	for water in get_tree().get_nodes_in_group(&"water_surfaces"):
		if water is StylizedWater and water.visible and water.drinkable and _at_edge(water, at):
			return true
	return false


func _at_edge(water: StylizedWater, at: Vector3) -> bool:
	var above := at.y - water.get_plane_surface_y()
	if above > shore_height or above < -depth:
		return false
	if water.holds_point(at):
		return true
	for i in 8:
		var offset := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 8.0) * shore_reach
		if water.holds_point(at + offset):
			return true
	return false
