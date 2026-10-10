// Stylized jetpack flame: hard-edged, posterized blobs that erode as they age.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec4 core_color : source_color = vec4(1.0, 0.97, 0.78, 1.0);
uniform vec4 mid_color  : source_color = vec4(1.0, 0.62, 0.15, 1.0);
uniform vec4 edge_color : source_color = vec4(0.92, 0.24, 0.10, 1.0);
uniform float noise_strength = 0.45;   // how ragged the silhouette is
uniform float scroll_speed = 2.5;      // noise flow speed
uniform float core_band = 0.55;        // heat above this = core colour
uniform float mid_band = 0.2;          // heat above this = mid colour
uniform float emission_boost = 2.0;    // >1 so WorldEnvironment glow picks it up

varying float age;
varying float seed;

void vertex() {
	age = INSTANCE_CUSTOM.y;               // 0 at spawn → 1 at death
	seed = float(INSTANCE_ID) * 0.137;
	// Camera-facing billboard that keeps per-particle scale
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float n = texture(noise_tex, UV * 0.6 + vec2(seed, TIME * scroll_speed)).r;

	float shape = 1.0 - r + (n - 0.5) * noise_strength;
	float cutoff = mix(0.05, 0.85, age);    // erodes away over lifetime
	if (shape < cutoff) {
		discard;
	}

	float heat = clamp((shape - cutoff) / (1.0 - cutoff), 0.0, 1.0);
	vec3 col = heat > core_band ? core_color.rgb : (heat > mid_band ? mid_color.rgb : edge_color.rgb);
	if (age > 0.5 && heat > core_band) {
		col = mid_color.rgb;                // core cools off in the second half
	}
	ALBEDO = col * emission_boost;
}
