extends Control
## Five curved cells; partial cells preserve the exact remaining energy.
var ratio := 1.0
var thrusting := false
var clock := 0.0
var _cached_icon_style := _icon_style()

func _draw() -> void:
	var color := Color("ffd46a")
	if ratio <= 0.2:
		color = Color("ff8756")
		color.a = 0.8 + 0.2 * sin(clock * 7.0)
	var center := Vector2(-100, 84)
	var radius := 160.0
	var span := 0.96 / 5.0
	for cell in 5:
		var bottom := 0.48 - cell * span - 0.018
		var top := bottom - span + 0.036
		draw_arc(center, radius, top, bottom, 16, Color(0.04, 0.07, 0.07, 0.78), 13, true)
		draw_arc(center, radius, top, bottom, 16, Color(0.65, 0.68, 0.62, 0.6), 10, true)
		draw_arc(center, radius, top, bottom, 16, Color(0.12, 0.16, 0.15, 0.88), 8, true)
		var fill := clampf(ratio * 5.0 - cell, 0.0, 1.0)
		if fill > 0.001:
			draw_arc(center, radius, lerpf(bottom, top, fill), bottom, 16, color, 7, true)
	# Small twin-nozzle backpack icon, beneath the arc.
	var icon := Color("fff1bf")
	draw_style_box(_cached_icon_style, Rect2(33, 172, 24, 24))
	draw_line(Vector2(39, 178), Vector2(39, 190), icon, 2, true)
	draw_line(Vector2(51, 178), Vector2(51, 190), icon, 2, true)
	if thrusting:
		for x in [39.0, 51.0]:
			draw_colored_polygon(PackedVector2Array([Vector2(x - 3, 197), Vector2(x + 3, 197), Vector2(x, 204 + 2 * sin(clock * 15))]), color)

func _icon_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.1, 0.1, 0.65)
	style.border_color = Color("d8c998")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	return style
