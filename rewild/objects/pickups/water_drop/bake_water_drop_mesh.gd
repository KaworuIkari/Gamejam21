extends SceneTree
## Bakes water_drop_mesh.res. Run:
## Godot --headless --path rewild --script res://objects/pickups/water_drop/bake_water_drop_mesh.gd

const HEIGHT := 0.9
const RADIUS := 0.32
const RINGS := 24
const SEGMENTS := 24


func _init() -> void:
	# Teardrop as a surface of revolution: h = cos t, r = sin t * sin(t/2)^1.2.
	# t = 0 is the pointed tip (top), t = PI the round bottom.
	var profile: Array[Vector2] = []
	for i in RINGS + 1:
		var t := PI * i / RINGS
		profile.append(Vector2(sin(t) * pow(sin(t * 0.5), 1.2) * RADIUS / 0.77, cos(t) * 0.5 * HEIGHT))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in RINGS + 1:
		var tangent := profile[mini(i + 1, RINGS)] - profile[maxi(i - 1, 0)]
		var n2 := Vector2(-tangent.y, tangent.x).normalized()
		if i == 0:
			n2 = Vector2(0, 1)
		elif i == RINGS:
			n2 = Vector2(0, -1)
		for s in SEGMENTS + 1:
			var a := TAU * s / SEGMENTS
			var dir := Vector3(cos(a), 0, sin(a))
			st.set_normal((dir * n2.x + Vector3.UP * n2.y).normalized())
			st.set_uv(Vector2(float(s) / SEGMENTS, float(i) / RINGS))
			st.add_vertex(dir * profile[i].x + Vector3.UP * profile[i].y)
	for i in RINGS:
		for s in SEGMENTS:
			var a := i * (SEGMENTS + 1) + s
			var b := a + SEGMENTS + 1
			for idx in [a, b, a + 1, a + 1, b, b + 1]:
				st.add_index(idx)
	var err := ResourceSaver.save(st.commit(), "res://objects/pickups/water_drop/water_drop_mesh.res")
	print("saved water_drop_mesh.res: ", error_string(err))
	quit()
