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
## Behaviour: wait -> (maybe) play one track for a random portion -> fade out -> long silence -> repeat.

enum State { WAITING, PLAYING, SUPPRESSED }
var _state : State = State.WAITING
var _timer : Timer

@export_group("Timing (seconds)")
@export var first_delay := Vector2(15.0, 40.0)      ## silence after game start
@export var play_time := Vector2(80.0, 160.0)       ## how long a track actually plays before fading out
@export var silence_time := Vector2(60.0, 180.0)    ## gap between tracks
@export var track_length := 180.0                   ## real track length, caps play_time
@export var release_margin := 10.0                  ## keep stop() this far before the track's natural end

@export_group("Variety")
@export_range(0.0, 1.0) var skip_chance := 0.25     ## chance a whole slot stays silent
@export var no_repeat_window := 3                   ## don't replay any of the last N tracks

@export_group("Debug")
@export var time_divisor := 1.0                     ## set to 10 to test the cycle quickly

@export var track_count := 6
@export var parameter_name := "track"

@onready var _world_bgm_emitter: FmodEventEmitter2D = $WorldBGM
var _history: Array[int] = []

func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_timer)
	add_child(_timer)
	_wait(_roll(first_delay))

func _start_track() -> void:
	var idx := _pick_track()
	_world_bgm_emitter.set_parameter(parameter_name, idx)
	_world_bgm_emitter.play()
	_remember(idx)
	_state = State.PLAYING
	var max_play := minf(play_time.y, track_length - release_margin)
	var min_play := minf(play_time.x, max_play)
	_timer.start(maxf(randf_range(min_play, max_play) / time_divisor, 0.1))

func _stop_track() -> void:
	_world_bgm_emitter.stop()  # AHDSR release handles the fade

func _pick_track() -> int:
	var pool: Array = range(track_count).filter(func(i): return not _history.has(i))
	if pool.is_empty():
		pool = range(track_count)
	return pool.pick_random()

func _remember(idx: int) -> void:
	_history.append(idx)
	while _history.size() > mini(no_repeat_window, track_count - 1):
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
		State.WAITING:
			if randf() < skip_chance:
				_wait(_roll(silence_time))
			else:
				_start_track()
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
