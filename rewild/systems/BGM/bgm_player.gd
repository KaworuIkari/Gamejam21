extends Node
class_name BGM_Player
## bgm_player.gd: ambient-style music scheduler for FMOD (Godot 4 + FMOD GDExtension).
##
## Setup:
##   - Put it in your main scene
##   - Add one FmodEventEmitter2D child
##   - On every emitter: Autoplay OFF, Allow Fadeout ON.
##   - In FMOD Studio, on each music event's master track add an AHDSR modulator on volume:
##     Attack ~6-10 s (slow fade-in), Release ~6-10 s (slow fade-out).
##     Allow Fadeout only does something if the event has a release to fade through.
##
## WorldBGM "track" values: 0 guitar_loop, 1 VibeDepot - Ambient, 2 午前二時のラジオ,
## 3 時果ての野, 4 花の喜び, 5 雨情.
##
## Behaviour: main menu loops menu_track. Entering the game fades it out, then silence until the
## player first moves; start_delay later the cycle begins over the unlocked pool:
## play one track for a random portion -> fade out -> long silence -> (maybe) next track -> repeat.
## The pool grows with the story (see "Story stages"); the boat departure switches to
## finale_track for good. After any ending the main menu keeps whatever is playing.

enum State { MENU, AWAIT_MOVE, STARTING, WAITING, PLAYING, FINALE, SUPPRESSED }
var _state : State = State.AWAIT_MOVE  # a level launched directly (F6) also waits for the first move
var _timer : Timer

@export_group("Menu & game start")
@export var menu_track := 1                         ## WorldBGM track for the main menu (1 = "VibeDepot - Ambient", the gentlest)
@export var menu_fade_time := 2.5                   ## menu music fade-out when the game starts
@export var start_delay := 5.0                      ## music starts this long after the player first moves

@export_group("Story stages")
@export var start_tracks: Array[int] = [5]          ## the pool at game start
@export var terminal_track := 3                     ## plays at once when the terminal is unlocked, then joins the pool
@export var cleaned_tracks: Array[int] = [2, 4]     ## join the pool once the cleaning progress reaches cleaned_threshold
@export_range(0.0, 1.0) var cleaned_threshold := 0.7  ## BatteryCharge.charge(), the terminal's restoration %
@export var finale_event := &"ending_boat"          ## Quests event of the final step: departing on the boat (after coordinates + battery)
@export var finale_track := 1                       ## loops from the final station on, into the main menu
@export var ending_events: Array[StringName] = [&"ending_boat", &"ending_disruptor"]  ## after any of these, the menu keeps the current music
@export var switch_fade_time := 2.0                ## fade-out of the current track before a story switch

@export_group("Timing (seconds)")
@export var play_time := Vector2(80.0, 160.0)       ## how long a track actually plays before fading out
@export var silence_time := Vector2(60.0, 180.0)    ## gap between tracks
@export var track_length := 180.0                   ## real track length, caps play_time
@export var release_margin := 10.0                  ## keep stop() this far before the track's natural end

@export_group("Variety")
@export_range(0.0, 1.0) var skip_chance := 0.25     ## chance a whole slot stays silent
@export var no_repeat_window := 3                   ## don't replay any of the last N tracks

@export_group("Debug")
@export var time_divisor := 1.0                     ## set to 10 to test the cycle quickly

@export var parameter_name := "track"

@onready var _world_bgm_emitter: FmodEventEmitter2D = $WorldBGM
@onready var _world_volume := _world_bgm_emitter.volume
var _history: Array[int] = []
var _pool: Array[int] = []
var _terminal := false
var _finale := false
var _fade: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # terminals/coordinate pad pause the tree; music keeps playing
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_timer)
	add_child(_timer)
	Quests.changed.connect(_sync_stage)
	GrowthMap.progress_changed.connect(_sync_stage)
	_sync_stage()


## Main menu: loop the gentle menu track. After an ending, whatever plays simply carries on.
func play_menu_music() -> void:
	if _state == State.MENU:
		return
	_timer.stop()
	var ended := ending_events.any(func(e): return Quests.event_count(e) > 0)
	var audible := _state == State.FINALE or _state == State.PLAYING
	if not (ended and audible):
		_cancel_fade()
		_world_bgm_emitter.set_parameter(parameter_name, menu_track)
		_world_bgm_emitter.play()
	_state = State.MENU


## Game start: fade the menu music to silence, then wait for the player's first move.
func enter_game() -> void:
	_timer.stop()
	_state = State.AWAIT_MOVE
	_cancel_fade()
	_fade = create_tween()
	_fade.tween_property(_world_bgm_emitter, "volume", 0.0, menu_fade_time)
	_fade.tween_callback(_stop_now)


## Called by the player while it moves; only the first call after enter_game() counts.
func notify_player_moved() -> void:
	if _state == State.AWAIT_MOVE:
		_state = State.STARTING
		_timer.start(maxf(start_delay / time_divisor, 0.1))


## Story progress -> pool. Switches only happen while the cycle runs; before the first track
## or under suppress() the flags just update (the first track honours the finale).
func _sync_stage() -> void:
	var terminal: bool = Quests.terminal_unlocked()
	var finale: bool = Quests.event_count(finale_event) > 0
	_pool = start_tracks.duplicate()
	if terminal:
		_pool.append(terminal_track)
	if BatteryCharge.charge() >= cleaned_threshold:
		_pool.append_array(cleaned_tracks)
	var running := _state == State.WAITING or _state == State.PLAYING
	if running and finale and not _finale:
		_switch_to(finale_track)
	elif running and terminal and not _terminal:
		_switch_to(terminal_track)
	_terminal = terminal
	_finale = finale


## Fade out whatever plays, then start idx right away.
func _switch_to(idx: int) -> void:
	_timer.stop()
	_cancel_fade()
	if _state != State.PLAYING:
		_start_track(idx)
		return
	_state = State.STARTING  # holds off further switches until the new track starts
	_fade = create_tween()
	_fade.tween_property(_world_bgm_emitter, "volume", 0.0, switch_fade_time)
	_fade.tween_callback(_stop_now)
	_fade.tween_callback(_start_track.bind(idx))


func _cancel_fade() -> void:
	if _fade and _fade.is_valid():
		_fade.kill()
	_world_bgm_emitter.volume = _world_volume


func _stop_now() -> void:
	# The tween already faded it; skip the AHDSR release so restoring the volume can't make it swell back.
	_world_bgm_emitter.allow_fadeout = false
	_world_bgm_emitter.stop()
	_world_bgm_emitter.allow_fadeout = true
	_world_bgm_emitter.volume = _world_volume

func _start_track(idx := -1) -> void:
	if _finale:
		idx = finale_track
	elif idx < 0:
		idx = _pick_track()
	_cancel_fade()
	_world_bgm_emitter.set_parameter(parameter_name, idx)
	_world_bgm_emitter.play()
	if _finale:
		_state = State.FINALE  # stays on this track; no timer
		return
	_remember(idx)
	_state = State.PLAYING
	var max_play := minf(play_time.y, track_length - release_margin)
	var min_play := minf(play_time.x, max_play)
	_timer.start(maxf(randf_range(min_play, max_play) / time_divisor, 0.1))

func _stop_track() -> void:
	_world_bgm_emitter.stop()  # AHDSR release handles the fade

func _pick_track() -> int:
	var pool := _pool.filter(func(i): return not _history.has(i))
	if pool.is_empty():
		pool = _pool
	return pool.pick_random()

func _remember(idx: int) -> void:
	_history.append(idx)
	while _history.size() > mini(no_repeat_window, _pool.size() - 1):
		_history.pop_front()

## Fade the current track out and hold the scheduler (cutscene, boss fight, important dialogue...).
func suppress() -> void:
	if _timer == null:
		return
	_timer.stop()
	_stop_track()
	_state = State.SUPPRESSED


## Resume the normal cycle after suppress(). Starts with a silence so music doesn't snap back in.
func release(delay := 20.0) -> void:
	if _state == State.SUPPRESSED:
		_wait(delay / time_divisor)


func _on_timer() -> void:
	match _state:
		State.STARTING:
			_start_track()
		State.WAITING:
			if _finale or randf() >= skip_chance:
				_start_track()
			else:
				_wait(_roll(silence_time))
		State.PLAYING:
			_stop_track()
			_wait(_roll(silence_time))


func _wait(seconds: float) -> void:
	_state = State.WAITING
	_timer.start(maxf(seconds, 0.1))

func _roll(range_s: Vector2) -> float:
	return randf_range(range_s.x, range_s.y) / time_divisor

@onready var _ending_bgm_emitter: FmodEventEmitter2D = $EndingBGM
const ENDING_INDEX := ["happy", "neutral", "sad"]
func _play_ending_bgm(ending_type: int) -> void:
	suppress()
	_ending_bgm_emitter.set_parameter("Ending", ENDING_INDEX[ending_type])
	_ending_bgm_emitter.play()


@onready var _epic_bgm_emitter: FmodEventEmitter2D = $EpicBGM
func _play_epic_bgm() -> void:
	_epic_bgm_emitter.play()

@onready var _quests_bgm_emitter: FmodEventEmitter2D = $QuestsBGM
const QUEST_BGM_VAR = ["cabin_crew", "water_switch", "forest_fox", "radio_station"]
func _play_quests_bgm(quest_bgm_var_index: int) -> void:
	_quests_bgm_emitter.set_parameter("Quest", QUEST_BGM_VAR[quest_bgm_var_index])
	_quests_bgm_emitter.play()
