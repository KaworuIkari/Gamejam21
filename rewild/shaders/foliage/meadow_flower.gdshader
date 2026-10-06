// meadow_flower.gdshader: a round flower head on a camera-facing quad.
// Used as the mesh material of a second Terrain3DParticles node.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

#include "res://shaders/common/meadow_palette.gdshaderinc"

uniform float cluster_density : hint_range(0.0, 1.0) = 0.8; // inside clusters
uniform float lone_density : hint_range(0.0, 1.0) = 0.04;    // scattered everywhere else

varying vec3 petal_color;

void vertex() {
	vec2 pos = MODEL_MATRIX[3].xz;   // where this flower stands; also its random seed
	petal_color = flower_palette(m_hash(pos));

	// Clusters: big soft noise blobs decide where flowers bunch up.
	float cluster = smoothstep(0.52, 0.66, m_fbm(pos * 0.035 + 41.0));
	float chance = max(cluster * cluster_density, lone_density);
	bool keep = m_hash(pos + 8.8) < chance;

	// Billboard: keep the particle's position and size, but use the camera's rotation.
	// (This is the same thing Godot's built-in "Billboard" material mode does.)
	float size = keep ? length(MODEL_MATRIX[0].xyz) : 0.0; // size 0 = invisible
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0] * size,
			INV_VIEW_MATRIX[1] * size,
			INV_VIEW_MATRIX[2] * size,
			MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float r = length(UV - 0.5);          // distance from the centre of the quad
	if (r > 0.5) discard;                // cut the square into a circle
	vec3 col = mix(petal_color, petal_color * 0.75, smoothstep(0.15, 0.5, r));
	col = mix(srgb(vec3(1.0, 0.82, 0.3)), col, smoothstep(0.08, 0.14, r)); // yellow centre
	ALBEDO = col;
	EMISSION = col * 0.15;               // a little glow so they pop in shade
	ROUGHNESS = 1.0;
}
