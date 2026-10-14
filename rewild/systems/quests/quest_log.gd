extends Node
## Autoload "Quests": runs every Quest in res://quests/, counts world events and holds the
## player's abilities (water_gun, jetpack... with levels).
##
## World objects only ever call report(&"event_name"); quests decide what that means.
## Progress lives in SaveManager.current_data["quests"], so saving the game saves it.
## Debug builds: F9 completes the current step of the tracked quest.

signal changed
signal quest_started(quest: Quest)
signal step_completed(quest: Quest, index: int)
signal quest_completed(quest: Quest)
signal ability_changed(ability: StringName, level: int)

enum Status { LOCKED, ACTIVE, DONE }

const FOLDER := "res://quests/"

var quests: Array[Quest] = []
## The quest the HUD shows. Empty = the first active one.
var tracked: StringName = &""

var _counters: Dictionary = {}   # event -> times reported
var _abilities: Dictionary = {}  # ability -> level
var _states: Dictionary = {}     # quest id -> {status, step, baseline}


func _ready() -> void:
	_load_quests()
	reset()


# --- What the world calls ------------------------------------------------------------

## Something happened in the world, e.g. report(&"garbage") when a piece is cleared.
func report(event: StringName, amount: int = 1) -> void:
	if event == &"":
		return
	_counters[event] = int(_counters.get(event, 0)) + amount
	if OS.is_debug_build():
		print("[Quests] %s (%d)" % [event, _counters[event]])
	_evaluate()
	_changed()


## Raises an ability to at least `level`. Quests do this through their rewards.
func grant(ability: StringName, level: int = 1) -> void:
	if level <= ability_level(ability):
		return
	_abilities[ability] = level
	ability_changed.emit(ability, level)
	_changed()


func ability_level(ability: StringName) -> int:
	return int(_abilities.get(ability, 0))


func has_ability(ability: StringName) -> bool:
	return ability_level(ability) > 0


func event_count(event: StringName) -> int:
	return int(_counters.get(event, 0))


# --- What the UI reads ---------------------------------------------------------------

func status(q: Quest) -> Status:
	return _state(q).status


func current_step(q: Quest) -> int:
	return _state(q).step


## How far a step is: x = done so far, y = needed.
func step_progress(q: Quest, index: int) -> Vector2i:
	var st := q.steps[index]
	var s := _state(q)
	if s.status == Status.DONE or index < s.step:
		return Vector2i(st.count, st.count)
	if s.status == Status.LOCKED or index > s.step:
		return Vector2i(0, st.count)
	return Vector2i(clampi(_step_count(q, index), 0, st.count), st.count)


func tracked_quest() -> Quest:
	for q in quests:
		if q.get_id() == tracked and status(q) == Status.ACTIVE:
			return q
	for q in quests:
		if status(q) == Status.ACTIVE:
			return q
	return null


func track(q: Quest) -> void:
	tracked = q.get_id() if q else &""
	_changed()


# --- Saving ----------------------------------------------------------------------------

## Back to a new game: nothing reported, no abilities, quests re-checked from the start.
func reset() -> void:
	var had := _abilities.keys()
	_counters.clear()
	_abilities.clear()
	_states.clear()
	tracked = &""
	for a in had:
		ability_changed.emit(a, 0)
	_evaluate()
	changed.emit()


## Called by the level when it starts: picks up the loaded save, or a new game.
func load_from_save() -> void:
	reset()
	var save := get_node_or_null(^"/root/SaveManager")
	var data: Dictionary = save.current_data.get("quests", {}) if save else {}
	if data.is_empty():
		return
	for k in data.get("counters", {}):
		_counters[StringName(k)] = int(data.counters[k])
	for k in data.get("abilities", {}):
		_abilities[StringName(k)] = int(data.abilities[k])
	for k in data.get("quests", {}):
		var s: Dictionary = data.quests[k]
		_states[StringName(k)] = {"status": int(s.get("status", 0)), "step": int(s.get("step", 0)),
				"baseline": int(s.get("baseline", 0))}
	tracked = StringName(data.get("tracked", ""))
	_evaluate()
	for a in _abilities:
		ability_changed.emit(a, _abilities[a])
	changed.emit()


func _save() -> void:
	var save := get_node_or_null(^"/root/SaveManager")
	if save == null:
		return
	var qs := {}
	for id in _states:
		qs[String(id)] = _states[id]
	var counters := {}
	for e in _counters:
		counters[String(e)] = _counters[e]
	var abilities := {}
	for a in _abilities:
		abilities[String(a)] = _abilities[a]
	save.current_data["quests"] = {"counters": counters, "abilities": abilities, "quests": qs,
			"tracked": String(tracked)}


# --- Internals --------------------------------------------------------------------------

func _load_quests() -> void:
	quests.clear()
	if not DirAccess.dir_exists_absolute(FOLDER):
		return
	var files := Array(ResourceLoader.list_directory(FOLDER))
	files.sort()
	for f: String in files:
		if not (f.ends_with(".tres") or f.ends_with(".res")):
			continue
		var q := load(FOLDER + f) as Quest
		if q:
			quests.append(q)


func _state(q: Quest) -> Dictionary:
	var id := q.get_id()
	if not _states.has(id):
		_states[id] = {"status": Status.LOCKED, "step": 0, "baseline": 0}
	return _states[id]


func _step_count(q: Quest, index: int) -> int:
	var st := q.steps[index]
	var n := event_count(st.event)
	return n if st.count_earlier else n - int(_state(q).baseline)


## Starts quests whose requirements are met and moves active ones along, until nothing
## changes (one event can finish a step, a quest, and start the next quest).
func _evaluate() -> void:
	var again := true
	while again:
		again = false
		for q in quests:
			var s := _state(q)
			if s.status == Status.LOCKED and q.requires.all(func(r: Quest) -> bool: return r != null and status(r) == Status.DONE):
				s.status = Status.ACTIVE
				s.step = 0
				_begin_step(q)
				quest_started.emit(q)
				again = true
			if s.status != Status.ACTIVE:
				continue
			while s.step < q.steps.size() and _step_count(q, s.step) >= q.steps[s.step].count:
				step_completed.emit(q, s.step)
				s.step += 1
				_begin_step(q)
			if s.step >= q.steps.size():
				s.status = Status.DONE
				for a in q.rewards:
					grant(a, q.rewards[a])
				quest_completed.emit(q)
				again = true


func _begin_step(q: Quest) -> void:
	var s := _state(q)
	if s.step < q.steps.size():
		s.baseline = event_count(q.steps[s.step].event)


func _changed() -> void:
	_save()
	changed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_F9:
		var q := tracked_quest()
		if q:
			var st := q.steps[current_step(q)]
			var p := step_progress(q, current_step(q))
			report(st.event, maxi(1, p.y - p.x))
