@tool
extends EditorScript

## 1.0 = standard Catmull-Rom. Lower = tighter, higher = rounder.
const TENSION := 1.0
## Treat the first and last point as neighbours (a loop).
const CLOSED := false


func _run() -> void:
	var sel := get_editor_interface().get_selection().get_selected_nodes()
	if sel.is_empty() or not sel[0] is Path3D:
		push_warning("Select a Path3D first.")
		return
	var curve: Curve3D = (sel[0] as Path3D).curve
	var n := curve.point_count
	if n < 3:
		return

	var pts: Array[Vector3] = []
	for i in n:
		pts.append(curve.get_point_position(i))

	for i in n:
		var prev: Vector3
		var next: Vector3
		if CLOSED:
			prev = pts[(i - 1 + n) % n]
			next = pts[(i + 1) % n]
		else:
			prev = pts[maxi(i - 1, 0)]
			next = pts[mini(i + 1, n - 1)]
		var tangent := (next - prev) / 6.0 * TENSION
		# End points of an open curve: one-sided, so they don't overshoot.
		if not CLOSED and i == 0:
			tangent = (pts[1] - pts[0]) / 3.0 * TENSION
			curve.set_point_in(i, Vector3.ZERO)
			curve.set_point_out(i, tangent)
		elif not CLOSED and i == n - 1:
			tangent = (pts[i] - pts[i - 1]) / 3.0 * TENSION
			curve.set_point_in(i, -tangent)
			curve.set_point_out(i, Vector3.ZERO)
		else:
			curve.set_point_in(i, -tangent)
			curve.set_point_out(i, tangent)

	print("Smoothed %d points." % n)