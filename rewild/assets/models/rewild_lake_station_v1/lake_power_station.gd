extends Node3D
## Self-contained prop controller. Task manager calls mark_task_completed(id).
## Uses the existing interact action; no project autoload dependencies.
signal activated
signal terminal_requested
signal state_changed(state: int)
enum State { DORMANT, READY, ACTIVE }
const HOLD_PROMPT_SCENE = preload("res://ui/in_game/interaction/clear_hold_prompt.tscn")
const TAP_PROMPT_SCENE = preload("res://ui/in_game/interaction/interaction_prompt.tscn")
const SFX_CHARGE: AudioStreamWAV = preload("res://assets/audio/sfx/station_charge_loop.wav")
const SFX_COMPLETE: AudioStream = preload("res://assets/audio/sfx/station_charge_complete.wav")
const SFX_CANCEL: AudioStream = preload("res://assets/audio/sfx/station_charge_cancel.wav")
@export_enum("Dormant", "Ready", "Active") var initial_state := 0
@export var required_task_ids: Array[StringName] = [&"main_02_spring"]
@export var player_group: StringName = &"player"
@export var interact_action: StringName = &"interact"
## Translation keys of the on-screen prompt; "%s" is replaced by the bound key.
@export var locked_message := "STATION_LOCKED"
@export var hold_message := "STATION_HOLD_PROMPT"
@export var terminal_message := "STATION_TERMINAL_PROMPT"
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
var _hold_prompt: CanvasLayer     # shared prompts: key + charging bar for activation,
var _tap_prompt: CanvasLayer      # plain key prompt for the terminal / locked hint
var _prompt: CanvasLayer          # whichever of the two is in use
var _prompt_key := ""
var _bar_fill: StyleBoxFlat       # the charging bar's fill, brightened as it charges
var _charge: AudioStreamPlayer    # hum that rises in pitch while the key is held
var _sfx: AudioStreamPlayer       # one-shots: complete / cancel

func _ready() -> void:
	$Prompt.visible = false  # old 3D label, replaced by the shared prompt
	_hold_prompt = HOLD_PROMPT_SCENE.instantiate()
	add_child(_hold_prompt)
	_style_charge_bar(_hold_prompt.get_node_or_null(^"Root/Anchor/Panel/HoldColumn/HoldProgress"))
	_tap_prompt = TAP_PROMPT_SCENE.instantiate()
	add_child(_tap_prompt)
	_prompt = _tap_prompt
	_charge = AudioStreamPlayer.new()
	_charge.bus = &"SFX"
	_charge.stream = SFX_CHARGE
	add_child(_charge)
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = &"SFX"
	add_child(_sfx)
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
	if _needs_hold() and held and not _hold_lock and not _nearby.is_empty() and _prompt_shown():
		_hold += delta
		_charge_sound(_hold / hold_time)
		if _hold >= hold_time:
			_hold = 0.0
			_hold_lock = true
			_charge.stop()
			_play_sfx(SFX_COMPLETE)
			_prompt.play_activation()
			interact()
	else:
		if _hold > 0.0 and _charge.playing:
			_charge.stop()
			if _hold > hold_time * 0.15:
				_play_sfx(SFX_CANCEL)  # let go early: the charge winds down
		_hold = 0.0
	_refresh_prompt()


## A thicker energy bar in the core light's teal instead of the thin clearing bar.
func _style_charge_bar(bar: ProgressBar) -> void:
	if bar == null:
		return
	bar.custom_minimum_size = Vector2(260, 12)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.16, 0.2, 0.55)
	bg.border_color = Color(0.55, 0.95, 1.0, 0.45)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", bg)
	_bar_fill = StyleBoxFlat.new()
	_bar_fill.bg_color = Color(0.15, 0.86, 0.92)
	_bar_fill.set_corner_radius_all(6)
	_bar_fill.shadow_color = Color(0.3, 0.95, 1.0, 0.6)
	_bar_fill.shadow_size = 4
	bar.add_theme_stylebox_override("fill", _bar_fill)


## Hum rises in pitch and volume as the charge fills; the bar heats up to white-cyan.
func _charge_sound(k: float) -> void:
	if _bar_fill:
		_bar_fill.bg_color = Color(0.15, 0.86, 0.92).lerp(Color(0.75, 1.0, 1.0), k * k)
		_bar_fill.shadow_size = int(lerpf(3.0, 9.0, k))
	if not _charge.playing:
		_charge.play()
	_charge.pitch_scale = lerpf(0.7, 1.7, k * k * (3.0 - 2.0 * k))
	_charge.volume_db = lerpf(-16.0, -5.0, k)


func _play_sfx(stream: AudioStream) -> void:
	_sfx.stream = stream
	_sfx.play()


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
	# The core battery is taken here, in person, once the land has charged it to 100%.
	if quests and BatteryCharge.ready_to_collect():
		BatteryCharge.collect()
	_show_terminal()
	_terminal_busy = false


## First contact equips both tools immediately; flight awaits the repaired factory bot.
func _first_contact(quests: Node) -> void:
	await _play_timeline(first_contact_timeline)
	quests.receive_starter_equipment()


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

func _prompt_shown() -> bool:
	return not _nearby.is_empty() and not get_tree().paused and not _dialogue_active()


func _refresh_prompt() -> void:
	if _prompt == null:
		return
	var locked := state == State.DORMANT and not activate_from_dormant
	var key := locked_message if locked else hold_message if _needs_hold() else terminal_message
	var want := _hold_prompt if _needs_hold() else _tap_prompt
	if want != _prompt:
		_prompt.set_available(false)
		_prompt = want
		_prompt_key = ""
	if key != _prompt_key:
		_prompt_key = key
		_prompt.configure(interact_action, key)
	_prompt.set_available(_prompt_shown())
	_prompt.set_interactable(not locked)
	_prompt.set_hold_progress(_hold / hold_time if _needs_hold() else 0.0)


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
		_prompt.play_activation()
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
