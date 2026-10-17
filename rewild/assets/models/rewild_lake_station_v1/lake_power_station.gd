extends Node3D
## Self-contained prop controller. Task manager calls mark_task_completed(id).
## Uses the existing interact action; no project autoload dependencies.
signal activated
signal terminal_requested
signal state_changed(state: int)
enum State { DORMANT, READY, ACTIVE }
@export_enum("Dormant", "Ready", "Active") var initial_state := 0
@export var required_task_ids: Array[StringName] = [&"main_02_spring"]
@export var player_group: StringName = &"player"
@export var interact_action: StringName = &"interact"
@export_multiline var locked_message := "Restore the water source\nto unlock this station"
## Interacting while Dormant activates it straight away (no tasks needed).
@export var activate_from_dormant := false
## Seconds the interact key must be held to activate (0 = a tap). Once active, a tap
## opens the terminal.
@export var hold_time := 1.0
## Once active, interacting opens the task terminal (instead of only pressing Tab).
@export var open_terminal := true
## Played the first time the terminal is used; the player gets the action terminal when
## it ends. Empty = hand it over without a dialogue.
@export_file("*.dtl") var first_contact_timeline := "res://dialogue/timelines/LakeTerminal/first_contact.dtl"
## The player gets the water gun when they close the terminal opened here. Usually
## better done as a quest reward (step event = terminal_event).
@export var give_water_gun := false
## Played when the player hands in the activated energy core (quest 04); then
## `core_delivered_event` is reported and the terminal opens as usual.
@export_file("*.dtl") var core_delivery_timeline := "res://dialogue/timelines/LakeTerminal/core_delivery.dtl"
@export var core_delivered_event: StringName = &"core_delivered"
@export_group("Quest events")
## Reported to the quests when the station is activated.
@export var activate_event: StringName = &"station_activated"
## Reported when the player closes the terminal opened here.
@export var terminal_event: StringName = &"station_terminal"
## Optional: becomes Ready once this WaterFlowSwitch (e.g. the pump) has finished flowing.
@export var unlock_when: Node
@export_group("Bloom on activation")
## Green spreads out from the station when it is activated, in metres (0 = none).
@export var bloom_radius := 0.0
## Seconds the green takes to reach the edge.
@export var bloom_time := 6.0
var state: int = State.DORMANT
var _completed: Array[StringName] = []
var _nearby: Array[Node3D] = []
var _restored := false
var _hold := 0.0
var _hold_lock := false   # after a hold completes, wait for release before the next use
var _terminal_busy := false
var _terminal_open := false
@onready var _zone: Area3D = $InteractionZone
@onready var _prompt: Label3D = $Prompt

func _ready() -> void:
	_zone.body_entered.connect(_body_entered)
	_zone.body_exited.connect(_body_exited)
	if unlock_when and unlock_when.has_signal(&"finished"):
		unlock_when.finished.connect(set_tasks_complete.bind(true))
	activated.connect(_bloom)
	activated.connect(_report.bind(activate_event))
	terminal_requested.connect(_open_terminal)
	if not _restored:
		state = clampi(initial_state, State.DORMANT, State.ACTIVE)
	_apply_state()

func mark_task_completed(task_id: StringName) -> void:
	if task_id not in _completed:
		_completed.append(task_id)
	if required_task_ids.is_empty():
		return # Explicit manual unlock via set_tasks_complete(true).
	for required in required_task_ids:
		if required not in _completed:
			return
	set_tasks_complete(true)

func set_tasks_complete(complete: bool = true) -> void:
	if state == State.ACTIVE:
		return
	_restored = true
	_set_state(State.READY if complete else State.DORMANT)

## May be called by another interaction controller or a cutscene.
## Returns false while locked. Activation emits once; later uses request the terminal.
func interact() -> bool:
	if get_tree().paused or _dialogue_active():
		return false
	if state == State.DORMANT and not activate_from_dormant:
		return false
	if state != State.ACTIVE:
		_set_state(State.ACTIVE)
		activated.emit()
	else:
		terminal_requested.emit()
	return true

func _set_state(value: int) -> void:
	if state == value:
		return
	state = value
	if is_node_ready():
		_apply_state()
	state_changed.emit(state)

func _apply_state() -> void:
	$Visuals/Dormant.visible = state == State.DORMANT
	$Visuals/Ready.visible = state == State.READY
	$Visuals/Active.visible = state == State.ACTIVE
	$CoreLight.light_energy = [0.0, 0.35, 0.85][state]
	_refresh_prompt()

func _process(delta: float) -> void:
	_nearby = _nearby.filter(func(body): return is_instance_valid(body))
	if _terminal_open and not get_tree().paused: # the terminal opened here was just closed
		_terminal_open = false
		_on_terminal_closed()
	var held := InputMap.has_action(interact_action) and Input.is_action_pressed(interact_action)
	if not held:
		_hold_lock = false
	if _needs_hold() and held and not _hold_lock and not _nearby.is_empty():
		_hold += delta
		if _hold >= hold_time:
			_hold = 0.0
			_hold_lock = true
			interact()
	else:
		_hold = 0.0
	_refresh_prompt()


## Activation is a long press; using it once active is a tap.
func _needs_hold() -> bool:
	return hold_time > 0.0 and state != State.ACTIVE \
			and (state == State.READY or activate_from_dormant)


func _open_terminal() -> void:
	if not open_terminal or _terminal_busy:
		return
	_terminal_busy = true
	var quests := get_node_or_null(^"/root/Quests")
	if quests and not quests.terminal_unlocked():
		await _first_contact(quests)
	if quests and quests.ability_level(&"energy_core") >= 2 and quests.has_ability(&"radar_key") and quests.event_count(core_delivered_event) == 0:
		await _play_timeline(core_delivery_timeline)
		_report(core_delivered_event)
	if quests:
		await _submit_radar_information(quests)
	_show_terminal()
	_terminal_busy = false


## The first use: a dialogue, then the player owns the action terminal.
func _first_contact(quests: Node) -> void:
	await _play_timeline(first_contact_timeline)
	quests.unlock_terminal()


func _play_timeline(path: String) -> void:
	var dialogic := get_node_or_null(^"/root/Dialogic")
	if dialogic and not path.is_empty():
		dialogic.start(path)
		await dialogic.timeline_ended


func _show_terminal() -> void:
	var menu := get_tree().get_first_node_in_group(&"pause_menu")
	if menu and menu.has_method(&"open_terminal"):
		menu.open_terminal()
		_terminal_open = get_tree().paused # it refuses while another menu is open


func _on_terminal_closed() -> void:
	_report(terminal_event)
	if not give_water_gun:
		return
	var quests := get_node_or_null(^"/root/Quests")
	if quests:
		quests.grant(&"water_gun", 1)
		return
	for body in _nearby:
		if body.has_method(&"set_water_gun"):
			body.set_water_gun(true)


func _report(event: StringName) -> void:
	var quests := get_node_or_null(^"/root/Quests")
	if quests:
		quests.report(event)

func _refresh_prompt() -> void:
	_prompt.visible = not _nearby.is_empty() and not get_tree().paused and not _dialogue_active()
	if state == State.DORMANT and not activate_from_dormant:
		_prompt.text = tr(locked_message)
		return
	var binding := "Interact"
	if InputMap.has_action(interact_action):
		var events = InputMap.action_get_events(interact_action)
		if not events.is_empty():
			binding = events[0].as_text().replace(" (Physical)", "").replace(" - Physical", "")
	if state == State.ACTIVE:
		_prompt.text = "[%s] %s" % [binding, tr("Open terminal")]
	elif hold_time > 0.0:
		var bar := int(clampf(_hold / hold_time, 0.0, 1.0) * 10.0)
		_prompt.text = "%s [%s] %s\n%s" % [tr("Hold"), binding, tr("Activate station"),
				"■".repeat(bar) + "□".repeat(10 - bar)]
	else:
		_prompt.text = "[%s] %s" % [binding, tr("Activate station")]


func _bloom() -> void:
	var growth := get_node_or_null(^"/root/GrowthMap")
	if growth and bloom_radius > 0.0:
		growth.reveal_from(global_position, bloom_time, bloom_radius)

func _unhandled_input(event: InputEvent) -> void:
	if _nearby.is_empty() or event.is_echo() or not InputMap.has_action(interact_action):
		return
	if _needs_hold():
		return # handled as a long press in _process
	if event.is_action_pressed(interact_action) and not _hold_lock and interact():
		get_viewport().set_input_as_handled()

func _body_entered(body: Node3D) -> void:
	if (body.is_in_group(player_group) or (body is CharacterBody3D and &"frozen" in body)) and body not in _nearby:
		_nearby.append(body)

func _body_exited(body: Node3D) -> void:
	_nearby.erase(body)

func _dialogue_active() -> bool:
	var dialogic = get_node_or_null("/root/Dialogic")
	return dialogic != null and dialogic.get("current_timeline") != null

func get_save_data() -> Dictionary:
	var ids: Array[String] = []
	for id in _completed:
		ids.append(String(id))
	return {"version": 1, "state": state, "completed_task_ids": ids}

## Save manager owns disk persistence. Restoring never re-emits activation.
func restore_save_data(data: Dictionary) -> void:
	_completed.clear()
	var ids = data.get("completed_task_ids", [])
	if ids is Array:
		for id in ids:
			if (id is String or id is StringName) and StringName(id) not in _completed:
				_completed.append(StringName(id))
	state = clampi(int(data.get("state", State.DORMANT)), State.DORMANT, State.ACTIVE)
	_restored = true
	if is_node_ready():
		_apply_state()


## Only a physical return to the lake terminal can deliver quest 05.
## Tab remains a task viewer and cannot grant this reward remotely.
func _submit_radar_information(quests: Node) -> void:
	var quest: Quest = load("res://quests/05_radar_station.tres")
	if quests.status(quest) != quests.Status.ACTIVE or quests.current_step(quest) != quest.steps.size() - 1:
		return
	if quests.event_count(&"radar_coordinates") < 1 or quests.event_count(&"radar_started") < 1 \
			or quests.event_count(&"mountain_restoration") < 30:
		return
	var dialogic := get_node_or_null(^"/root/Dialogic")
	if dialogic == null or dialogic.current_timeline != null:
		return
	var scene := get_tree().current_scene
	var timeline := DialogicTimeline.new()
	for key in ["RADAR_DELIVERY_RECEIVED", "RADAR_DELIVERY_REWARD", "FINALE_BRIEFING_DEVICE", "FINALE_BRIEFING_BOAT"]:
		var event := DialogicTextEvent.new()
		event.text = tr(key)
		timeline.events.append(event)
	timeline.events_processed = true
	dialogic.start(timeline)
	await dialogic.timeline_ended
	if is_inside_tree() and get_tree().current_scene == scene and not SceneRouter.is_busy() \
			and quests.event_count(&"radar_delivered") == 0:
		quests.report(&"radar_delivered")
