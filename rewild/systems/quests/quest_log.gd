extends Node
## Autoload "Quests": runs every Quest in res://quests/, counts world events and holds the
## player's abilities (water_gun, jetpack... with levels).
##
## World objects only ever call report(&"event_name"); quests decide what that means.
## Progress lives in SaveManager.current_data["quests"], so saving the game saves it.
## Debug builds: F9 completes the current step of the tracked quest.

signal changed
signal quest_started(quest: Quest)
signal quest_completed(quest: Quest)
signal ability_changed(ability: StringName, level: int)

enum Status { LOCKED, ACTIVE, DONE }

const FOLDER := "res://quests/"
## The action terminal (and the HUD readouts it drives) is an ability: the player
## finds it at the lake station, so a new game starts without it.
const TERMINAL := &"task_terminal"

var quests: Array[Quest] = []
## The quest the HUD shows. Empty = the first active one.
var tracked: StringName = &""

var _counters: Dictionary = {}   # event -> times reported
var _abilities: Dictionary = {}  # ability -> level
## quest id -> {status, step, baselines, done}. step: the open step of a one-after-another
## quest. baselines: event count when each step opened. done: steps of a parallel quest finished.
var _states: Dictionary = {}


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


func terminal_unlocked() -> bool:
	return has_ability(TERMINAL)


func unlock_terminal() -> void:
	grant(TERMINAL)


## The station hands over the action terminal and the water gun. The jetpack is in the
## factory's power room; the repaired bot fetches it (FactoryStory).
func receive_starter_equipment() -> void:
	unlock_terminal()
	grant(&"water_gun")


func event_count(event: StringName) -> int:
	return int(_counters.get(event, 0))


# --- What the UI reads ---------------------------------------------------------------

func status(q: Quest) -> Status:
	return _state(q).status


## The step to show: the open one, or for a parallel quest the first unfinished one.
func current_step(q: Quest) -> int:
	var s := _state(q)
	if s.status != Status.ACTIVE:
		return s.step
	var first: int = 0 if q.parallel else s.step
	var last: int = q.steps.size() - 1 if q.parallel else _group_end(q, s.step)
	for i in range(first, last + 1):
		if not _is_done(q, i):
			return i
	return q.steps.size() if q.parallel else s.step


## The steps that can be worked on now and are not done yet (several for a parallel quest).
func open_steps(q: Quest) -> Array[int]:
	var out: Array[int] = []
	var s := _state(q)
	if s.status != Status.ACTIVE:
		return out
	var first: int = 0 if q.parallel else s.step
	var last: int = q.steps.size() - 1 if q.parallel else _group_end(q, s.step)
	for i in range(first, last + 1):
		if not _is_done(q, i):
			out.append(i)
	return out


## How many steps are finished.
func done_steps(q: Quest) -> int:
	if status(q) == Status.DONE and not (q.parallel and q.complete_any):
		return q.steps.size()
	var n := 0
	for i in q.steps.size():
		if _is_done(q, i):
			n += 1
	return n


## How far a step is: x = done so far, y = needed.
func step_progress(q: Quest, index: int) -> Vector2i:
	var st := q.steps[index]
	var s := _state(q)
	if _is_done(q, index):
		return Vector2i(st.count, st.count)
	if s.status == Status.LOCKED or (not q.parallel and index > _group_end(q, s.step)):
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
	for k in data.get("counters", {}):
		_counters[StringName(k)] = int(data.counters[k])
	for k in data.get("abilities", {}):
		_abilities[StringName(k)] = int(data.abilities[k])
	for k in data.get("quests", {}):
		var s: Dictionary = data.quests[k]
		_states[StringName(k)] = {"status": int(s.get("status", 0)), "step": int(s.get("step", 0)),
				"baselines": Array(s.get("baselines", [])).map(func(v): return int(v)),
				"done": Array(s.get("done", [])).map(func(v): return int(v))}
	# Sequential quests can gain new trailing story steps. A save completed against
	# the older resource must continue from those new steps (05 formerly ended at 40%).
	for quest in quests:
		var restored := _state(quest)
		if not quest.parallel and restored.status == Status.DONE and restored.step < quest.steps.size():
			restored.status = Status.ACTIVE
			_begin_step(quest)
	tracked = StringName(data.get("tracked", ""))
	_evaluate()
	# Older first-contact saves may have received the terminal before closing its
	# page. Give them the water gun too.
	if terminal_unlocked():
		_abilities[&"water_gun"] = maxi(1, ability_level(&"water_gun"))
	_abilities.erase(&"jetpack_equipped")  # the old unpowered backpack no longer exists
	for a in _abilities:
		ability_changed.emit(a, _abilities[a])
	_changed()


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
		_states[id] = {"status": Status.LOCKED, "step": 0, "baselines": [], "done": []}
	return _states[id]


func _step_count(q: Quest, index: int) -> int:
	var st := q.steps[index]
	var n := event_count(st.event)
	if st.count_earlier:
		return n
	var baselines: Array = _state(q).baselines
	return n - (int(baselines[index]) if index < baselines.size() else 0)


## Has this step been finished (a parallel quest: counted enough; otherwise: passed)?
func _is_done(q: Quest, index: int) -> bool:
	var s := _state(q)
	if s.status == Status.DONE:
		return index in s.done if q.parallel and q.complete_any else true
	if s.status != Status.ACTIVE:
		return false
	if q.parallel:
		return index in s.done
	if index < s.step:
		return true
	return index <= _group_end(q, s.step) and _step_count(q, index) >= q.steps[index].count


## Last step of the group that starts at `first` (steps marked with_previous join it).
func _group_end(q: Quest, first: int) -> int:
	var last := first
	while last + 1 < q.steps.size() and q.steps[last + 1].with_previous:
		last += 1
	return last


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
				s.done = []
				_start_quest(q)
				quest_started.emit(q)
				again = true
			if s.status != Status.ACTIVE:
				continue
			if q.parallel:
				for i in q.steps.size():
					if not i in s.done and _step_count(q, i) >= q.steps[i].count:
						s.done.append(i)
			else:
				while s.step < q.steps.size():
					var last := _group_end(q, s.step)
					var open := false
					for i in range(s.step, last + 1):
						open = open or _step_count(q, i) < q.steps[i].count
					if open:
						break
					s.step = last + 1
					_begin_step(q)
			if (q.parallel and q.complete_any and not s.done.is_empty()) or (s.done.size() if q.parallel else s.step) >= q.steps.size():
				s.status = Status.DONE
				for a in q.rewards:
					grant(a, q.rewards[a])
				quest_completed.emit(q)
				again = true


## Remembers the event counts at the start, for steps that only count what happens later.
func _start_quest(q: Quest) -> void:
	var s := _state(q)
	s.baselines = []
	for st in q.steps:
		s.baselines.append(event_count(st.event))


## One-after-another quests: the next step starts counting now.
func _begin_step(q: Quest) -> void:
	var s := _state(q)
	while s.baselines.size() < q.steps.size():
		s.baselines.append(0)
	if s.step < q.steps.size():
		for i in range(s.step, _group_end(q, s.step) + 1):
			s.baselines[i] = event_count(q.steps[i].event)


func _changed() -> void:
	_save()
	changed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_F9:
		var q := tracked_quest()
		if q and not q.complete_any: # A finale choice requires its world interaction and confirmation.
			var st := q.steps[current_step(q)]
			var p := step_progress(q, current_step(q))
			report(st.event, maxi(1, p.y - p.x))

## Display progress independently of a final route's completion event.
func step_label(q: Quest, index: int) -> String:
	var step := q.steps[index]
	var text := tr(step.text)
	if step.progress_event != &"" and step.progress_target > 0:
		text += "  (%d/%d)" % [clampi(event_count(step.progress_event),0,step.progress_target),step.progress_target]
	elif step.count > 1:
		var progress := step_progress(q,index)
		text += "  (%d/%d)" % [progress.x,progress.y]
	return text

## Consume and commit a single mutually exclusive outcome before emitting changes.
## Keeping these mutations together prevents the other route taking the same module.
func complete_choice(q: Quest, index: int, item: StringName) -> bool:
	if not q.parallel or not q.complete_any or status(q) != Status.ACTIVE \
			or index < 0 or index >= q.steps.size() or not has_ability(item):
		return false
	_abilities.erase(item)
	var event := q.steps[index].event
	_counters[event] = event_count(event) + q.steps[index].count
	_evaluate()
	ability_changed.emit(item,0)
	_changed()
	return true
