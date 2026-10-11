shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled;

group_uniforms Texture;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform bool flip_v = true;

group_uniforms Look;
uniform float emission_boost = 3.0;                       // HDR multiplier; >1 blooms with glow
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float additive : hint_range(0.0, 1.0) = 0.7;      // 0 = normal alpha blend, 1 = pure additive
uniform float core_boost = 2.0;                           // extra brightness in the dense centre
uniform float core_power = 3.0;                           // how tight that hot core is
uniform float dim_at_low_intensity : hint_range(0.0, 1.0) = 0.4;

group_uniforms Noise;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec2 noise_scale = vec2(1.0, 1.5);
uniform float noise_flow_speed = 2.5;
uniform float noise_strength : hint_range(0.0, 1.0) = 0.6;
uniform float noise_contrast = 1.5;
uniform float tip_breakup : hint_range(0.0, 1.0) = 0.5;

group_uniforms Flicker;
uniform float flicker_speed = 0.8;
uniform float flicker_amount : hint_range(0.0, 1.0) = 0.15;

group_uniforms Debug;
uniform bool debug_force_visible = false;

instance uniform float intensity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 tex_uv = flip_v ? vec2(UV.x, 1.0 - UV.y) : UV;
	vec4 tex = texture(texture_albedo, tex_uv);

	if (debug_force_visible) {
		ALBEDO = tex.rgb * tex.a;
		ALPHA = tex.a;
	} else {
		vec2 nuv = UV * noise_scale - vec2(0.0, noise_flow_speed * TIME);
		float n = texture(noise_tex, nuv).r;
		n = clamp((n - 0.5) * noise_contrast + 0.5, 0.0, 1.0);
		float strength = noise_strength * mix(1.0 - tip_breakup, 1.0, UV.y);
		float noise_mul = mix(1.0, n, strength);

		float f = texture(noise_tex, vec2(TIME * flicker_speed, 0.37)).r;
		float flicker = 1.0 + (f - 0.5) * 2.0 * flicker_amount;

		float a = albedo.a * tex.a * noise_mul * opacity * smoothstep(0.0, 0.15, intensity);
		float core = 1.0 + core_boost * pow(tex.a, core_power);   // dense pixels burn hotter
		float bright = mix(dim_at_low_intensity, 1.0, intensity) * flicker * emission_boost * core;

		ALBEDO = albedo.rgb * tex.rgb * bright * a;   // premultiplied: colour already scaled by coverage
		ALPHA = a * (1.0 - additive);                  // how much of the background it blocks
	}
}