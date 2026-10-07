@tool
class_name MountainRing extends MeshInstance3D
## A ring of distant mountains around the map, made from noise.
## Change the settings, then press "Build" in the Inspector.

@export_tool_button("Build") var build_button = build

@export var inner_radius := 5000.0  ## where the mountains start (just outside your map)
@export var outer_radius := 550.0 ## far edge of the ring
@export var peak_height := 300.0   ## tallest possible peak
@export var base_height := 0.0     ## height of the ring's flat edges
@export var noise_seed := 17
@export var noise_frequency := 0.0022 ## higher = more, narrower peaks
## 0 = equally tall all around. 1 = only the -Z side has big peaks.
@export_range(0.0, 1.0) var tall_side := 0.45
@export var segments := 512 ## vertices around the ring
@export var rings := 80     ## vertices from the inner to the outer edge


func build() -> void:
	# Ridged noise gives sharp crests instead of round blobs.
	var ridge := FastNoiseLite.new()
	ridge.seed = noise_seed
	ridge.frequency = noise_frequency
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 5

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Vertices: a polar grid (rings x segments), lifted by the noise.
	for ri in rings + 1:
		var t := float(ri) / rings
		var r := lerpf(inner_radius, outer_radius, t * t) # more detail near the map
		for si in segments + 1:
			var angle := TAU * si / segments
			var x := cos(angle) * r
			var z := sin(angle) * r
			# Envelope: 0 at both edges of the ring, 1 in between.
			var rise := smoothstep(inner_radius, lerpf(inner_radius, outer_radius, 0.3), r)
			var fall := 1.0 - smoothstep(lerpf(inner_radius, outer_radius, 0.75), outer_radius, r)
			var side := 1.0 - tall_side + tall_side * maxf(-sin(angle), 0.0)
			var n := ridge.get_noise_2d(x, z) * 0.5 + 0.5
			st.add_vertex(Vector3(x, base_height + n * peak_height * rise * fall * side, z))

	# 2. Triangles: two per grid square.
	for ri in rings:
		for si in segments:
			var i := ri * (segments + 1) + si
			var next_ring := i + segments + 1
			st.add_index(i)
			st.add_index(next_ring)
			st.add_index(i + 1)
			st.add_index(i + 1)
			st.add_index(next_ring)
			st.add_index(next_ring + 1)

	# 3. Normals for lighting, then hand the mesh to this MeshInstance3D.
	st.generate_normals()
	mesh = st.commit()
