shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.60, 0.88, 0.95);
uniform vec3 deep_color : source_color = vec3(0.24, 0.56, 0.86);
uniform float depth_range = 1.4;
uniform float foam_width = 0.18;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear;

float w_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1, 0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0, 1), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1, 1), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float scene_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float water_depth = clamp(VERTEX.z - view.z, 0.0, 100.0);

	float d = clamp(water_depth / depth_range, 0.0, 1.0);
	vec3 col = mix(shallow_color, deep_color, d);

	vec2 wp = world_pos.xz;
	float ripple = w_noise(wp * 0.8 + TIME * 0.3) * 0.5 + w_noise(wp * 1.7 - TIME * 0.4) * 0.5;
	float foam = 1.0 - smoothstep(foam_width * 0.5, foam_width * (1.0 + ripple), water_depth);
	col = mix(col, vec3(0.95, 0.98, 1.0), foam * 0.85);

	ALBEDO = col;
	ALPHA = mix(0.55, 0.9, d) + foam * 0.2;
	ROUGHNESS = 0.08;
	SPECULAR = 0.6;
	NORMAL_MAP = normalize(vec3((ripple - 0.5) * 0.25, (w_noise(wp * 1.3 + TIME * 0.2) - 0.5) * 0.25, 1.0)) * 0.5 + 0.5;
}
