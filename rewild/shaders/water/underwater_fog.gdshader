// Full-screen quad shown while the camera is below the surface: distance fog that
// hides far-away things in blue, brighter towards the top of the screen.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform vec3 fog_color : source_color = vec3(0.10, 0.42, 0.58);
uniform float fog_density = 0.08;
uniform float max_fog : hint_range(0.0, 1.0) = 0.95;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0); // QuadMesh of size 2 covers the whole screen
}

void fragment() {
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	float dist = length(v.xyz / v.w);
	ALBEDO = fog_color * mix(0.75, 1.35, 1.0 - SCREEN_UV.y);
	ALPHA = (1.0 - exp(-dist * fog_density)) * max_fog;
}
