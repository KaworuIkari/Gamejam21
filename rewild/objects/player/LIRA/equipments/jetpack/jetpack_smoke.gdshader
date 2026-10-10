// Stylized smoke puffs: two-tone cel shading on a fake sphere, warm tint at birth, dissolves out.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec4 light_color  : source_color = vec4(0.86, 0.86, 0.90, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.46, 0.46, 0.54, 1.0);
uniform vec4 hot_color    : source_color = vec4(1.0, 0.55, 0.25, 1.0);  // just left the nozzle
uniform vec3 light_dir = vec3(-0.5, 0.7, 0.5);   // in billboard space: x right, y up, z toward camera
uniform float shade_threshold = 0.15;
uniform float noise_strength = 0.35;
uniform float hot_fraction = 0.18;               // portion of lifetime with the warm tint

varying float age;
varying float seed;

void vertex() {
	age = INSTANCE_CUSTOM.y;
	seed = float(INSTANCE_ID) * 0.291;
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
	float n = texture(noise_tex, UV * 0.5 + vec2(seed, seed * 1.7 + TIME * 0.3)).r;

	float shape = 1.0 - r + (n - 0.5) * noise_strength;
	float cutoff = mix(0.08, 0.95, pow(age, 1.5));  // holds its shape, then breaks up
	if (shape < cutoff) {
		discard;
	}

	// Fake sphere normal from the quad (UV y points down)
	vec3 sn = normalize(vec3(p.x, -p.y, sqrt(max(0.0, 1.0 - r * r))));
	float ndl = dot(sn, normalize(light_dir));
	vec3 col = ndl > shade_threshold ? light_color.rgb : shadow_color.rgb;
	col = mix(hot_color.rgb, col, step(hot_fraction, age));
	ALBEDO = col;
}
