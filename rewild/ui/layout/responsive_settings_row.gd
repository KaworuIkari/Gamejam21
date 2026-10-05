class_name ResponsiveSettingsRow
extends Container
## 设置页的一行内容：宽屏为左右两列，窄屏/竖屏为上下两列。

var label: Label
var controls: HBoxContainer
var compact := false:
	set(value):
		if compact == value:
			return
		compact = value
		queue_sort()
		update_minimum_size()

var label_width := 460.0
var separation := 24.0
var row_height := 64.0


func _init() -> void:
	label = Label.new()
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label)
	controls = HBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.alignment = BoxContainer.ALIGNMENT_END
	add_child(controls)


func apply_metrics(metrics: Dictionary) -> void:
	separation = float(metrics.row_gap)
	row_height = float(metrics.row_height)
	label.add_theme_font_size_override(&"font_size", int(metrics.body_size))
	queue_sort()
	update_minimum_size()


func _get_minimum_size() -> Vector2:
	var label_min := label.get_combined_minimum_size()
	var controls_min := controls.get_combined_minimum_size()
	if compact:
		return Vector2(maxf(label_min.x, controls_min.x), label_min.y + separation + controls_min.y)
	return Vector2(label_width + separation + controls_min.x, maxf(row_height, maxf(label_min.y, controls_min.y)))


func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN:
		return
	var area := Rect2(Vector2.ZERO, size)
	var label_min := label.get_combined_minimum_size()
	if compact:
		label.position = area.position
		label.size = Vector2(area.size.x, label_min.y)
		controls.position = Vector2(area.position.x, area.position.y + label_min.y + separation)
		controls.size = Vector2(area.size.x, maxf(row_height, controls.get_combined_minimum_size().y))
	else:
		label.position = area.position
		label.size = Vector2(label_width, area.size.y)
		controls.position = Vector2(area.position.x + label_width + separation, area.position.y)
		controls.size = Vector2(maxf(0.0, area.size.x - label_width - separation), area.size.y)
