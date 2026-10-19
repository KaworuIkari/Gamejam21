extends Node
## The only thing in the game that writes PhantomCamera3D.priority.
## Views register by name; a stack lets cutscenes take over and hand control back.

signal view_changed(previous: StringName, current: StringName)

const BASE_PRIORITY := 0
const ACTIVE_PRIORITY := 100

var _views := {}  # StringName -> PhantomCamera3D
var _stack: Array[StringName] = []
var _current: StringName = &""


func register(view: StringName, pcam: PhantomCamera3D) -> void:
	var existing = _views.get(view)
	if existing != null and existing != pcam:
		push_error("CameraDirector: view '%s' already registered to %s" % [view, (existing as Node).get_path()])
		return
	_views[view] = pcam
	_apply()


func unregister(view: StringName) -> void:
	if _views.erase(view):
		_apply()


## The base view — what you return to once every cutscene has ended.
func activate(view: StringName) -> void:
	if _stack.is_empty():
		_stack.append(view)
	else:
		_stack[0] = view
	_apply()


## Takes over until pop(). Nestable.
func push(view: StringName) -> void:
	_stack.append(view)
	_apply()


## Hands control back to whatever sits beneath. Never empties the base.
func pop(instant := false) -> void:
	if _stack.size() <= 1:
		return
	_stack.pop_back()
	var pcam := _views.get(_resolve()) as PhantomCamera3D
	if instant and pcam != null and is_instance_valid(pcam):
		var saved := pcam.tween_duration
		pcam.tween_duration = 0.0
		_apply()
		await get_tree().process_frame
		pcam.tween_duration = saved
	else:
		_apply()
		
func current() -> StringName:
	return _current


func is_cutscene_active() -> bool:
	return _stack.size() > 1


## Top-most view that actually exists, so load order and freed cameras resolve cleanly.
func _resolve() -> StringName:
	for i in range(_stack.size() - 1, -1, -1):
		var view: StringName = _stack[i]
		if _views.has(view) and is_instance_valid(_views[view]):
			return view
	return &""


func _apply() -> void:
	var target := _resolve()
	for view in _views:
		var pcam: PhantomCamera3D = _views[view]
		if is_instance_valid(pcam):
			pcam.priority = ACTIVE_PRIORITY if view == target else BASE_PRIORITY
	if target != _current:
		var previous := _current
		_current = target
		view_changed.emit(previous, target)


########## switch CD ##########

const SWITCH_COOLDOWN := 5.0
var _locked_until := 0.0
func switch_locked() -> bool:
	return Time.get_ticks_msec() * 0.001 < _locked_until


func switch_lock_remaining() -> float:
	return maxf(_locked_until - Time.get_ticks_msec() * 0.001, 0.0)


## Input-facing toggle. Returns false if still cooling down.
func request_toggle(a: StringName, b: StringName) -> bool:
	if switch_locked():
		return false
	var base: StringName = _stack[0] if not _stack.is_empty() else &""
	activate(b if base == a else a)
	_locked_until = Time.get_ticks_msec() * 0.001 + SWITCH_COOLDOWN
	return true