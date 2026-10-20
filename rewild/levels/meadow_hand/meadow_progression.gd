extends Node3D
## Main-line progression for meadow_hand (docs/story/game_flow.md, trimmed to this map):
##   1 clear litter near spawn      2 reach the north spring
##   3 clear the spring intake      4 free the trapped animal
##   5 start the pump               6 activate the lake station  -> stage 2 Revival
##   7 revive the east oasis        8 revive the summit          -> stage 3 Golden + demolition auth
##   9 tear down the sea wall       -> ending bloom
## Props listen on their own: StageVariant swaps with the world stage, GrowthVariant
## with the ground under it, Clearable reports to us by tag.
## Debug builds: F7 skips the current objective, F8 jumps to the next world stage.

enum Step { BASIN_LITTER, REACH_SPRING, CLEAR_SPRING, RESCUE_SPRING, START_PUMP, ACTIVATE_STATION,
		REVIVE_EAST, REVIVE_PEAK, BEACH_WALL, DONE }

const STEP_KEYS := {
	Step.BASIN_LITTER: "OBJ_BASIN_LITTER",
	Step.REACH_SPRING: "OBJ_REACH_SPRING",
	Step.CLEAR_SPRING: "OBJ_CLEAR_SPRING",
	Step.RESCUE_SPRING: "OBJ_RESCUE_SPRING",
	Step.START_PUMP: "OBJ_START_PUMP",
	Step.ACTIVATE_STATION: "OBJ_ACTIVATE_STATION",
	Step.REVIVE_EAST: "OBJ_REVIVE_EAST",
	Step.REVIVE_PEAK: "OBJ_REVIVE_PEAK",
	Step.BEACH_WALL: "OBJ_BEACH_WALL",
	Step.DONE: "OBJ_DONE",
}
## Clearable tag each clearing step counts (all of them must go).
const STEP_TAGS := {
	Step.BASIN_LITTER: &"basin_litter",
	Step.CLEAR_SPRING: &"spring_blockage",
	Step.RESCUE_SPRING: &"rescue_spring",
	Step.BEACH_WALL: &"beach_wall",
}

@export_group("Level nodes")
@export var environment: WorldEnvironment
@export var sun: DirectionalLight3D
## The pump's interact zone; kept switched off until the intake is cleared.
@export var pump_trigger: InteractTrigger
## Its water chain; the station unlocks when the water has arrived.
@export var pump_flow: WaterFlowSwitch

@export_group("Own nodes")
@export var world_stages: WorldStages
@export var station: Node3D
@export var spring_area: Area3D
@export var east_zone: GrowthZone
@export var peak_zone: GrowthZone
@export var east_rescue: Clearable
@export var peak_rescue: Clearable
@export var beach_center: Node3D

var step := Step.BASIN_LITTER

var _totals := {}   # tag -> how many existed at start
var _counts := {}   # tag -> how many are cleared
var _label: Label
var _toast: Label
var _toast_tween: Tween


func _ready() -> void:
	if world_stages:
		world_stages.environment = environment
		world_stages.sun = sun
		world_stages.stage_changed.connect(_on_stage_changed)
	Clearable.abilities.clear()
	for c in get_tree().get_nodes_in_group(&"clearable"):
		for t in c.tags:
			_totals[t] = _totals.get(t, 0) + 1
		c.cleared.connect(_on_cleared)
	if spring_area:
		spring_area.body_entered.connect(func(b: Node) -> void:
			if step == Step.REACH_SPRING and _is_player(b):
				_advance())
	if pump_trigger:
		pump_trigger.monitoring = false
		pump_trigger.interacted.connect(func() -> void:
			if pump_flow == null:
				_pump_done())
	if pump_flow:
		pump_flow.finished.connect(_pump_done)
	if station:
		station.activated.connect(func() -> void:
			if step == Step.ACTIVATE_STATION:
				_advance())
	for z: GrowthZone in [east_zone, peak_zone]:
		if z:
			z.active = false
			z.completed.connect(func(_id: StringName) -> void: _check_zone_step())
			z.progress_changed.connect(func(_id: StringName, _c: float) -> void: _refresh_label())
	for r: Clearable in [east_rescue, peak_rescue]:
		if r:
			r.cleared.connect(func(_c: Clearable) -> void: _check_zone_step.call_deferred())
	_build_hud()
	_enter(step)


func _on_cleared(c: Clearable) -> void:
	for t in c.tags:
		_counts[t] = _counts.get(t, 0) + 1
	var tag: StringName = STEP_TAGS.get(step, &"")
	if tag != &"" and c.has_tag(tag) and _remaining(tag) == 0:
		_advance()
	else:
		_refresh_label()


func _remaining(tag: StringName) -> int:
	return _totals.get(tag, 0) - _counts.get(tag, 0)


func _advance() -> void:
	if step == Step.DONE:
		return
	_leave(step)
	step = (step + 1) as Step
	_enter(step)


## Side effects of finishing a step.
func _leave(s: Step) -> void:
	match s:
		Step.ACTIVATE_STATION:
			world_stages.advance()  # Revival: bloom around the station, gates open
		Step.REVIVE_PEAK:
			world_stages.advance()  # Golden: green spreads over the whole map
			Clearable.abilities[&"demolition_auth"] = true
			_show_toast(tr("TOAST_DEMOLITION_AUTH"))
		Step.BEACH_WALL:
			var growth := get_node_or_null(^"/root/GrowthMap")
			if growth and beach_center:
				growth.reveal_from(beach_center.global_position, 6.0, 60.0)


## Set-up for a new step; skips steps that are already satisfied.
func _enter(s: Step) -> void:
	match s:
		Step.START_PUMP:
			if pump_trigger:
				pump_trigger.monitoring = true
			else:
				_pump_done.call_deferred()
		Step.REVIVE_EAST:
			if east_zone:
				east_zone.active = true
				east_zone._check()
			_check_zone_step.call_deferred()
		Step.REVIVE_PEAK:
			if peak_zone:
				peak_zone.active = true
				peak_zone._check()
			_check_zone_step.call_deferred()
		Step.DONE:
			_show_toast(tr("OBJ_DONE"))
	var tag: StringName = STEP_TAGS.get(s, &"")
	if tag != &"" and _remaining(tag) <= 0:
		_advance.call_deferred()
	_refresh_label()


func _pump_done() -> void:
	if station and station.has_method(&"mark_task_completed"):
		station.mark_task_completed(&"main_02_spring")
	if step == Step.START_PUMP:
		_advance()


func _check_zone_step() -> void:
	var zone: GrowthZone
	var rescue: Clearable
	if step == Step.REVIVE_EAST:
		zone = east_zone
		rescue = east_rescue
	elif step == Step.REVIVE_PEAK:
		zone = peak_zone
		rescue = peak_rescue
	else:
		return
	var zone_ok := zone == null or zone.done
	var rescue_ok := rescue == null or not is_instance_valid(rescue) or rescue.is_cleared
	if zone_ok and rescue_ok:
		_advance()
	else:
		_refresh_label()


func _on_stage_changed(_i: int, st: WorldStage) -> void:
	_show_toast(tr("TOAST_STAGE") % tr(st.stage_name))


# --- HUD ---------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_label = _make_label(22)
	_label.position = Vector2(28, 24)
	layer.add_child(_label)
	_toast = _make_label(30)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.position.y = 90
	_toast.modulate.a = 0.0
	layer.add_child(_toast)


func _make_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", Color(1, 0.98, 0.92))
	l.add_theme_color_override(&"font_outline_color", Color(0.1, 0.12, 0.1, 0.85))
	l.add_theme_constant_override(&"outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _refresh_label() -> void:
	if _label == null:
		return
	var text := tr(STEP_KEYS[step])
	var tag: StringName = STEP_TAGS.get(step, &"")
	if tag != &"":
		text += "  (%d/%d)" % [_counts.get(tag, 0), _totals.get(tag, 0)]
	elif step == Step.REVIVE_EAST and east_zone:
		text += "  %d%%" % int(minf(east_zone.coverage / east_zone.complete_at, 1.0) * 100.0)
	elif step == Step.REVIVE_PEAK and peak_zone:
		text += "  %d%%" % int(minf(peak_zone.coverage / peak_zone.complete_at, 1.0) * 100.0)
	_label.text = text


func _show_toast(text: String) -> void:
	_toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.4)
	_toast_tween.tween_interval(3.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.8)


# --- Debug -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F7:
			_debug_skip()
		KEY_F8:
			world_stages.advance()


func _debug_skip() -> void:
	var tag: StringName = STEP_TAGS.get(step, &"")
	if tag != &"":
		if tag == &"beach_wall":
			Clearable.abilities[&"demolition_auth"] = true
		for c: Clearable in get_tree().get_nodes_in_group(&"clearable"):
			if c.has_tag(tag) and not c.is_cleared:
				c.clear()
		return
	match step:
		Step.REACH_SPRING:
			_advance()
		Step.START_PUMP:
			if pump_trigger:
				pump_trigger.use()
			else:
				_pump_done()
		Step.ACTIVATE_STATION:
			if station:
				station.set_tasks_complete(true)
				station.interact()
		Step.REVIVE_EAST, Step.REVIVE_PEAK:
			var zone := east_zone if step == Step.REVIVE_EAST else peak_zone
			var rescue := east_rescue if step == Step.REVIVE_EAST else peak_rescue
			if rescue and is_instance_valid(rescue):
				rescue.clear()
			if zone:
				zone.complete()


func _is_player(body: Node) -> bool:
	return body.is_in_group(&"player") or (body is CharacterBody3D and &"frozen" in body)
