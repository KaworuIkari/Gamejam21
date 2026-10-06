shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

// Greyscale 2x2 atlas: white = blade, black = empty.
uniform sampler2D alpha_atlas : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform vec3 root_color : source_color = vec3(0.32, 0.45, 0.22);
uniform vec3 tip_color : source_color = vec3(0.72, 0.84, 0.48);
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.35;
// How much the atlas brightness shades the blades (soft centres, darker edges).
uniform float detail_strength : hint_range(0.0, 1.0) = 0.3;
// 1 = normals point straight up, so the clump is lit like one fluffy mass.
uniform float up_normal_blend : hint_range(0.0, 1.0) = 0.8;
// Per-clump brightness / dryness variation.
uniform float variation : hint_range(0.0, 0.5) = 0.15;
uniform float wind_strength = 0.08;
uniform float wind_speed = 1.5;
uniform vec2 wind_direction = vec2(1.0, 0.3);

varying flat vec2 tile_offset;
varying flat float tint;
varying float tipness;

// Sine-free hash (stable on mobile GPUs).
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	// Instance origin: the same for every vertex of a clump and for all its LODs,
	// so each clump keeps its tile as LODs swap.
	vec3 origin = MODEL_MATRIX[3].xyz;

	int t = min(int(hash12(origin.xz * 3.7) * 4.0), 3);
	tile_offset = vec2(float(t % 2), float(t / 2)) * 0.5;
	tint = hash12(origin.xz * 1.3 + 17.0);

	// 0 at the root, 1 at the tip. Flip to UV.y if your card's UVs are upside down.
	tipness = 1.0 - UV.y;

	float phase = dot(origin.xz, wind_direction) * 0.2 + TIME * wind_speed;
	float sway = (sin(phase) + 0.5 * sin(phase * 2.3 + 1.7)) * wind_strength;
	VERTEX.xz += normalize(wind_direction) * sway * tipness * tipness;
}

void fragment() {
	// Small inset keeps samples off the tile borders.
	vec2 uv = tile_offset + clamp(UV, 0.002, 0.998) * 0.5;
	float a = texture(alpha_atlas, uv).r;

	// Crisp, stable cut-out edge at any distance and mip level.
	ALPHA = clamp((a - alpha_cutoff) / max(fwidth(a), 1e-4) + 0.5, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;

	vec3 col = mix(root_color, tip_color, tipness);
	col *= mix(1.0 - detail_strength, 1.0, a);
	col *= 1.0 + (tint - 0.5) * 2.0 * variation;
	col = mix(col, col * vec3(1.15, 1.05, 0.7), tint * variation); // slight dry tint

	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;

	vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	NORMAL = normalize(mix(NORMAL, up_view, up_normal_blend));
}
