@tool
class_name Restorable extends Node3D
## Something that recovers with the ground under it (GrowthMap). Give it one scene per look,
## from barren to lush, and it switches look as the ground turns green:
##   a dead tree that comes back:  stages = [DeadTree_1, CommonTree_1]
##   a bush that appears on green: stages = [<empty>, Bush_Common]
## Ready-made ones are in res://objects/restorable/. With no stages set, its own child
## nodes are used instead (one per stage, in order).

## One scene per look, barren first. Leave an entry empty for "nothing here yet".
@export var stages: Array[PackedScene] = []:
	set(v):
		stages = v
		_update_preview()
## Ground greenness (0..1) needed for each stage after the first. Missing values are
## spread evenly, e.g. two stages with no thresholds switch at 0.5.
@export var thresholds := PackedFloat32Array([0.6])
## Seconds a new look takes to grow in.
@export var pop_time := 0.8
## Random extra delay, so neighbours don't all change on the same frame.
@export var max_delay := 1.2
## Reported to the quests when it reaches its last stage (e.g. "tree_restored").
@export var quest_event: StringName = &""
## Ground greenness that reports quest_event instead, when 0 or more. Lets a tree swap to its
## bare leafy model early (its leaf shader then grows the canopy in) but still count late.
@export var quest_threshold := -1.0
## Which stage the editor shows.
@export var preview_stage := 0:
	set(v):
		preview_stage = maxi(v, 0)
		_update_preview()

var stage := -1

## Only petals and flowers pop as they grow in (folders of their models).
const POP_FOLDERS: Array[String] = [
	"res://assets/models/stylized_nature/Petal/",
	"res://assets/models/stylized_nature/Flower/",
]
## Watering a patch grows many at once; this keeps their pops to a light patter.
static var _last_pop_msec := 0

var _variants: Array = []   # Node3D or null per stage
var _scales: Array[Vector3] = []
var _growth: Node
var _pending := false
var _reported := false
var _preview: Node3D


func _ready() -> void:
	if Engine.is_editor_hint():
		_update_preview()
		return
	if stages.is_empty():
		for c in get_children():
			if c is Node3D:
				_variants.append(c)
	else:
		for s in stages:
			_variants.append(s.instantiate() if s else null)
	for v in _variants:
		_scales.append(v.scale if v else Vector3.ONE)
		if v and v.get_parent() == self:
			remove_child(v)
	_show(0, true)
	_growth = get_node_or_null(^"/root/GrowthMap")
	if _growth:
		_growth.changed.connect(_queue_refresh)
		_refresh.call_deferred(true)


func _queue_refresh() -> void:
	if _pending or not is_inside_tree():
		return
	_pending = true
	# Growth changes every simulation tick; a few checks a second is plenty.
	await get_tree().create_timer(0.3).timeout
	_pending = false
	_refresh(false)


func _refresh(instant: bool) -> void:
	if not is_inside_tree():
		return
	var g: float = _growth.sample(global_position)
	var i := 0
	while i < _variants.size() - 1 and g >= _threshold(i + 1):
		i += 1
	_show(i, instant)
	if quest_threshold >= 0.0 and not _reported and g >= quest_threshold:
		_reported = true
		if not instant:  # already green when first seen: doesn't count
			_report()


func _threshold(index: int) -> float:
	if index - 1 < thresholds.size():
		return thresholds[index - 1]
	return float(index) / _variants.size()


func _show(index: int, instant: bool) -> void:
	index = clampi(index, 0, _variants.size() - 1)
	if index == stage or _variants.is_empty():
		return
	if stage >= 0 and _variants[stage] and _variants[stage].get_parent() == self:
		remove_child(_variants[stage])
	var first_time := index == _variants.size() - 1 and stage < index
	stage = index
	var v: Node3D = _variants[index]
	if v:
		v.visible = true
		add_child(v)
		if not instant:
			var full := _scales[index]
			v.scale = full * (0.05 if index == 0 or _variants[index - 1] == null else 0.6)
			var t := create_tween()
			t.tween_interval(randf() * max_delay)
			if POP_FOLDERS.any(func(folder: String) -> bool: return v.scene_file_path.begins_with(folder)):
				t.tween_callback(_play_pop)
			t.tween_property(v, "scale", full, pop_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if first_time and not instant and quest_threshold < 0.0:
		_report()


func _play_pop() -> void:
	var audio := get_node_or_null(^"/root/UIAudio")
	if audio == null or Time.get_ticks_msec() - _last_pop_msec < 70:
		return
	_last_pop_msec = Time.get_ticks_msec()
	audio.play_sfx_at(audio.PLANT_POP, global_position, 0.15)


func _report() -> void:
	var quests := get_node_or_null(^"/root/Quests")
	if quests:
		quests.report(quest_event)


# --- Editor preview -----------------------------------------------------------------

func _update_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _preview:
		_preview.queue_free()
		_preview = null
	if stages.is_empty():
		return
	var scene := stages[mini(preview_stage, stages.size() - 1)]
	if scene == null:  # an empty stage: show the next look instead, so it can be placed
		for s in stages:
			if s:
				scene = s
				break
	if scene:
		_preview = scene.instantiate()
		add_child(_preview, false, Node.INTERNAL_MODE_FRONT)  # internal: never saved


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and not Engine.is_editor_hint():
		for v in _variants:
			if is_instance_valid(v) and v.get_parent() == null:
				v.free()
