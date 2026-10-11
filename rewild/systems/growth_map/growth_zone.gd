class_name GrowthZone extends Node3D
## An area the player revives by watering (e.g. the east oasis, the summit).
## Watering only ever leaves patches; once enough of the zone is green, the zone
## blooms from its centre and closes the gaps, so it ends as one continuous meadow
## instead of a patchwork of splashes.

signal progress_changed(zone_id: StringName, coverage: float)
signal completed(zone_id: StringName)

@export var zone_id: StringName = &""
@export var radius := 30.0
## Share of the zone (0..1) that must be green before it blooms closed.
@export_range(0.05, 1.0) var complete_at := 0.45
@export var bloom_duration := 5.0
## Off until a task enables it (e.g. the summit can't be finished before the jetpack).
@export var active := true

var coverage := 0.0
var done := false

var _check_pending := false


func _ready() -> void:
	GrowthMap.changed.connect(_queue_check)


func _queue_check() -> void:
	if _check_pending or done or not active:
		return
	_check_pending = true
	# Growth changes every simulation tick; measuring twice a second is plenty.
	await get_tree().create_timer(0.5).timeout
	_check_pending = false
	_check()


func _check() -> void:
	var c := GrowthMap.coverage(global_position, radius)
	if absf(c - coverage) > 0.005:
		coverage = c
		progress_changed.emit(zone_id, coverage)
	if coverage >= complete_at:
		complete()


## Blooms the whole zone at once. Tasks may also call this directly.
func complete(duration: float = -1.0) -> void:
	if done:
		return
	done = true
	GrowthMap.reveal_from(global_position, bloom_duration if duration < 0.0 else duration, radius)
	coverage = 1.0
	progress_changed.emit(zone_id, coverage)
	completed.emit(zone_id)
