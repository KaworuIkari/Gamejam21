extends Control
## Presentation only: progress is supplied by the interaction owner.
var progress := 0.0

func _draw() -> void:
	if progress <= 0.0:
		return
	var rect := Rect2(Vector2(-5, -5), size + Vector2(10, 10))
	var radius := 12.0
	var points := PackedVector2Array()
	var centers := [Vector2(rect.end.x-radius, rect.position.y+radius), rect.end-Vector2.ONE*radius, Vector2(rect.position.x+radius,rect.end.y-radius), rect.position+Vector2.ONE*radius]
	for corner in 4:
		for step in 9:
			var angle := -PI/2 + corner*PI/2 + step*PI/16
			points.append(centers[corner] + Vector2(cos(angle),sin(angle))*radius)
	points.append(points[0])
	draw_polyline(points, Color(0.15,0.19,0.16,0.6), 4, true)
	var length := 0.0
	for index in range(1, points.size()):
		length += points[index-1].distance_to(points[index])
	var remaining := length * clampf(progress,0,1)
	var filled := PackedVector2Array([points[0]])
	for index in range(1, points.size()):
		var segment := points[index-1].distance_to(points[index])
		if remaining <= segment:
			filled.append(points[index-1].lerp(points[index], remaining/maxf(segment,0.001)))
			break
		filled.append(points[index])
		remaining -= segment
	draw_polyline(filled, Color("ffe3a0"), 3, true)
