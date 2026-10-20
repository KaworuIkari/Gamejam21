shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_always, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.12, 0.45, 0.95, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.55, 0.88, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.9, 0.98, 1.0, 1.0);
uniform float rim_power = 2.5;
uniform float alpha = 0.82;
uniform float glow = 0.35;

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, rim_power);
	// Lighter toward the top of the drop, deeper at the round belly.
	float height = clamp((inverse(VIEW_MATRIX) * vec4(VERTEX, 1.0)).y - NODE_POSITION_WORLD.y + 0.5, 0.0, 1.0);
	vec3 base = mix(deep_color.rgb, shallow_color.rgb, facing * 0.6 + height * 0.4);
	ALBEDO = mix(base, rim_color.rgb, rim);
	EMISSION = base * glow + rim_color.rgb * rim * 0.6;
	ROUGHNESS = 0.05;
	SPECULAR = 0.9;
	ALPHA = mix(alpha, 1.0, rim);
}
