extends AnimalBase
class_name AnimalFox
## Starts lying hurt on its side (DOWN) until LIRA holds interact beside it; the rescue is
## saved as `rescue_event`. It then gets up, hops and howls, gives LIRA `reward_item` (a key,
## listed on the terminal), and lives:
## IDLE ⇄ WANDER when the player is far; WATCH (stand still, face the player) at middle
## distance; player close → FRIENDLY: it trots over, keeps about follow_distance away and
## now and then hops, spins or howls (HAPPY). It stays friendly until the player is beyond
## calm_radius.
## WorldEvents always win over watching the player: INVESTIGATE faces the event for a while.
##
## Waypoint advancement is owned entirely by NavigationAgent3D: one target at a
## time, arrival decided by agent.is_navigation_finished().

enum State { DOWN, IDLE, WANDER, WATCH, FRIENDLY, HAPPY, INVESTIGATE }

const HOLD_PROMPT_SCENE = preload("res://ui/in_game/interaction/clear_hold_prompt.tscn")

@export_group("Distance Bands")
@export var friendly_radius := 10.0  # closer than this: come over and play
@export var calm_radius := 30.0  # farther than this: roam freely (and stop following)

@export_group("Movement")
@export var run_speed := 7.0  # catching up with the player
@export var tick_interval := 2.0  # how often decisions are made

@export_group("Idle & Wander")
@export var idle_time := Vector2(3.0, 9.0)
@export var wander_radius := 15.0

@export_group("Friendly")
@export var follow_distance := 3.0
@export var follow_slack := 1.5  # dead zone, so the fox is not re-targeting constantly
## Chance per decision, while standing beside the player, to hop, spin or howl.
@export_range(0.0, 1.0) var happy_chance := 0.35
@export var hop_height := 0.35
@export var howl_speed := 0.85  # bark clip played slower, nose up
@export var howl_tilt_deg := 25.0

@export_group("Rescue")
## Saved when rescued; give each fox its own if there are several.
@export var rescue_event: StringName = &"fox_rescued"
## Given after the rescue howl; an ability in Quests, named by ITEM_<NAME>_1 in strings.csv.
@export var reward_item: StringName = &"fox_key"
@export var rescue_hold := 1.5  # seconds interact must be held
@export var rescue_radius := 2.5
@export var rescue_prompt := "FOX_RESCUE_PROMPT"
@export var down_roll_deg := 90.0  # lying on its side
@export var down_height := 0.15  # lifts the side-lying body out of the ground

@export_group("Events")
@export var curiosity_threshold := 0.6
@export var investigate_time := 3.0

@export_group("Animation Clips")
@export var run_anim := "running_rig"
@export var bark_anim := "bark_rig"

var state := State.IDLE

var _target := Vector3.ZERO
var _has_target := false
var _running := false

var _idle_timer := 0.0
var _investigate_timer := 0.0
var _event_pos := Vector3.ZERO
var _tick_timer := 0.0

var _prompt: CanvasLayer
var _player_near := false
var _hold := 0.0

@onready var lira: LIRA_Character = get_tree().get_first_node_in_group("player")
@onready var bark_sound: FmodEventEmitter3D = $fox_rigged/root/Skeleton3D/Retopo_fox_002/FmodEventEmitter3DBark
@onready var _model: Node3D = $fox_rigged


# === Lifecycle ===
func _max_speed() -> float:
	return maxf(walk_speed, run_speed)

func _ready() -> void:
	super._ready()
	# avoid circular motion
	var follow_need := _min_lookahead() * 0.9
	if follow_slack * 0.5 < follow_need:
		follow_slack = follow_need * 2.0

	if animation_player == null:
		push_error("AnimalFox: assign an AnimationPlayer in the inspector")
		set_physics_process(false)
		return
	walk_anim = "walking_rig"
	idle_anim = "idle_rig"

	WorldEvents.happened.connect(_on_world_event)
	_tick_timer = randf() * tick_interval  # stagger foxes so they do not all think on one frame
	if Quests.event_count(rescue_event) > 0:
		_give_reward()  # in case a save happened during the rescue sequence
		_enter_idle()
	else:
		_lie_down()


func _nav_ready() -> bool:
	return is_instance_valid(lira) and super._nav_ready()


# === State machine ===

func _tick_state(delta: float) -> void:
	if state == State.DOWN:
		return
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = tick_interval
		_decide()

	match state:
		State.IDLE: _tick_idle(delta)
		State.WANDER: _tick_wander(delta)
		State.WATCH, State.HAPPY: _face_dir = lira.global_position - global_position
		State.FRIENDLY: _tick_friendly(delta)
		State.INVESTIGATE: _tick_investigate(delta)


# === Decisions (every tick_interval seconds) ===

func _decide() -> void:
	# These run to completion and cannot be interrupted.
	if state == State.HAPPY or state == State.INVESTIGATE:
		return

	var dist := _player_distance()
	if dist < friendly_radius or (state == State.FRIENDLY and dist < calm_radius):
		_decide_friendly(dist)
	elif state == State.FRIENDLY:
		_enter_idle()  # the player left
	elif dist < calm_radius:
		_clear_target()
		state = State.WATCH
	elif state == State.WATCH:
		_enter_idle()


# === Down and rescue ===

func _lie_down() -> void:
	state = State.DOWN
	animation_locked = true
	animation_player.play(idle_anim)
	animation_player.seek(0.0, true)
	animation_player.pause()
	_model.rotation.z = deg_to_rad(down_roll_deg)
	_model.position.y = down_height
	var area := Area3D.new()
	area.name = "RescueRange"
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = rescue_radius
	shape.shape = sphere
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(func(body: Node) -> void: if body == lira: _player_near = true)
	area.body_exited.connect(func(body: Node) -> void: if body == lira: _player_near = false)
	# The fox lives in the pixel SubViewport; a CanvasLayer parented there breaks on
	# teardown, so the prompt lives under the root and goes away with the fox.
	_prompt = HOLD_PROMPT_SCENE.instantiate()
	get_tree().root.add_child.call_deferred(_prompt)
	tree_exiting.connect(_prompt.queue_free)
	_prompt.configure(&"interact", rescue_prompt)


func _process(delta: float) -> void:
	if state != State.DOWN or _prompt == null:
		return
	var dialogic := get_node_or_null(^"/root/Dialogic")
	var can := _player_near and not get_tree().paused \
			and (dialogic == null or dialogic.current_timeline == null)
	_prompt.set_available(can)
	if can and Input.is_action_pressed(&"interact"):
		_hold += delta
		if _hold >= rescue_hold:
			_prompt.play_activation()
			_rescue()
	else:
		_hold = 0.0
	_prompt.set_hold_progress(_hold / rescue_hold)


## Gets up, hops twice and howls, then carries on as a living fox.
func _rescue() -> void:
	state = State.HAPPY
	_hold = 0.0
	_prompt.set_available(false)
	Quests.report(rescue_event)
	animation_player.play(idle_anim)
	var up := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	up.tween_property(_model, ^"rotation:z", 0.0, 0.7)
	up.parallel().tween_property(_model, ^"position:y", 0.0, 0.7)
	await up.finished
	animation_locked = false
	await _hop(2)
	await _howl()
	if is_inside_tree():
		_give_reward()
		_enter_idle()


func _give_reward() -> void:
	if reward_item != &"":
		Quests.grant(reward_item)


# === States ===

func _enter_idle() -> void:
	_clear_target()
	_idle_timer = randf_range(idle_time.x, idle_time.y)
	state = State.IDLE


func _tick_idle(delta: float) -> void:
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_set_target(_random_nav_point(global_position, wander_radius))
		state = State.WANDER


func _tick_wander(delta: float) -> void:
	if _follow_target(delta, walk_speed):
		_enter_idle()


## Decided on the tick: stand beside the player (sometimes playing), or trot over.
func _decide_friendly(dist: float) -> void:
	state = State.FRIENDLY
	if dist < follow_distance + follow_slack:
		_clear_target()
		if randf() < happy_chance:
			_play_happy()
		return
	var out := global_position - lira.global_position
	out.y = 0.0
	out = out.normalized() if out.length() > 0.01 else Vector3.BACK
	_running = dist > follow_distance * 3.0
	_set_target(_closest_nav_point(lira.global_position + out * follow_distance), follow_slack * 0.5)


func _tick_friendly(delta: float) -> void:
	if _has_target:
		_follow_target(delta, run_speed if _running else walk_speed)
	else:
		_face_dir = lira.global_position - global_position


func _tick_investigate(delta: float) -> void:
	_face_dir = _event_pos - global_position
	_investigate_timer -= delta
	if _investigate_timer <= 0.0:
		_enter_idle()


# === Happy moves ===

func _play_happy() -> void:
	state = State.HAPPY
	match randi() % 3:
		0: await _hop(2)
		1: await _spin()
		2: await _howl()
	if state == State.HAPPY:
		state = State.FRIENDLY


func _hop(times: int) -> void:
	var t := create_tween()
	for i in times:
		t.tween_property(_model, ^"position:y", hop_height, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.tween_property(_model, ^"position:y", 0.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await t.finished


func _spin() -> void:
	var t := create_tween()
	t.tween_property(_model, ^"rotation:y", TAU, 0.7).from(0.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t.finished
	_model.rotation.y = 0.0


## The bark clip, slower and with the nose up, plus the fox call.
func _howl() -> void:
	animation_locked = true
	bark_sound.play()
	animation_player.play(bark_anim, -1, howl_speed)
	var tilt := create_tween()
	tilt.tween_property(_model, ^"rotation:x", -deg_to_rad(howl_tilt_deg), 0.25)
	await animation_player.animation_finished
	tilt = create_tween()
	tilt.tween_property(_model, ^"rotation:x", 0.0, 0.25)
	await tilt.finished
	animation_locked = false


# === Targets ===

func _set_target(p: Vector3, arrive := -1.0) -> void:
	_target = p
	_has_target = true
	var want := waypoint_radius if arrive < 0.0 else arrive
	agent.target_desired_distance = maxf(want, _min_lookahead() * 0.9)
	agent.target_position = p
	_begin_leg()


func _clear_target() -> void:
	_has_target = false
	_running = false


## Steers toward the current target. Returns true once the leg is done.
func _follow_target(delta: float, speed: float) -> bool:
	if not _has_target:
		return true
	if _leg_done(delta):
		_clear_target()
		return true
	_steer_along_path(speed)
	return false


# === Animation ===

func _pick_clip() -> String:
	if not is_moving:
		return idle_anim
	return run_anim if _running else walk_anim


# === World events ===

func _on_world_event(pos: Vector3, _kind: StringName, interest: float) -> void:
	if interest < curiosity_threshold or state == State.DOWN or state == State.HAPPY:
		return
	# Events outrank watching or playing with the player.
	_clear_target()
	_event_pos = pos
	_investigate_timer = investigate_time
	state = State.INVESTIGATE


# === Helpers ===

func _player_distance() -> float:
	return global_position.distance_to(lira.global_position)


func _debug_text() -> String:
	var lines := "%s  %.0fm" % [State.keys()[state], _player_distance()]
	if _has_target:
		lines += "\ntarget %.2fm (arrive %.2f)" % [_flat_dist(_target), agent.target_desired_distance]
		lines += "\nleg    %.1fs / %.0fs" % [_leg_time, move_timeout]
	else:
		lines += "\nno target"
	return lines
