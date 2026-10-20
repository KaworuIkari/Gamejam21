shader_type spatial;
// Soft dusty puff for RegionHaze: a camera-facing quad with a noisy round falloff that
// fades where it touches the ground and the camera. clear_radius sweeps out from the
// region centre and dissolves every puff it passes (the "region cleaned" wave).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 haze_color : source_color = vec4(0.86, 0.72, 0.55, 0.22);
uniform vec4 glow_color : source_color = vec4(1.0, 0.93, 0.78, 1.0);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform float soft_depth = 5.0;   // metres of blending into the ground
uniform float near_fade = 6.0;    // puffs vanish this close to the camera
uniform float far_fade = 260.0;
uniform vec3 clear_center = vec3(0.0);
uniform float clear_radius = -100.0;  // < 0: nothing cleared yet
uniform float clear_edge = 18.0;

varying float v_keep;
varying float v_seed;

void vertex() {
	// Billboard that keeps the particle's scale and spin.
	vec3 centre = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(centre, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * bb * mat4(
			vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	float d = distance(centre.xz, clear_center.xz);
	v_keep = clear_radius < 0.0 ? 1.0 : smoothstep(clear_radius - clear_edge, clear_radius, d);
	v_seed = fract(float(INSTANCE_ID) * 0.6180339);
}

void fragment() {
	vec2 c = UV - 0.5;
	vec2 drift = vec2(v_seed * 7.3, v_seed * 3.1) + TIME * vec2(0.012, 0.007);
	float n = texture(noise_tex, UV * 0.7 + drift).r;
	float round_falloff = 1.0 - smoothstep(0.15, 0.5, length(c) + (n - 0.5) * 0.35);
	float a = haze_color.a * round_falloff * COLOR.a * v_keep;

	// Soft intersection with the ground / props.
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = -scene.z / scene.w;
	float frag_z = -VERTEX.z;
	a *= clamp((scene_z - frag_z) / soft_depth, 0.0, 1.0);
	a *= smoothstep(near_fade * 0.4, near_fade, frag_z) * (1.0 - smoothstep(far_fade * 0.7, far_fade, frag_z));

	// The edge of the clearing wave glows briefly as the dust lifts.
	float rim = v_keep * (1.0 - v_keep) * 4.0;
	ALBEDO = mix(haze_color.rgb * (0.9 + n * 0.2), glow_color.rgb, rim * 0.6);
	ALPHA = clamp(a, 0.0, 1.0);
}
