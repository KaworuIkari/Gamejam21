extends CanvasLayer
## Non-blocking chapter card; normal pause freezes the presentation too.
@export var fade_seconds := 0.6
@export var hold_seconds := 2.0


func _ready() -> void:
	var title: Label = $Title
	title.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(title, "modulate:a", 1.0, fade_seconds)
	tween.tween_interval(hold_seconds)
	tween.tween_property(title, "modulate:a", 0.0, fade_seconds)
	tween.tween_callback(queue_free)
