// sky_grass.gdshader: "Sky: Children of the Light"-style grass. Broad, round-tipped
// blades that read like paint strokes: dark teal at the root, luminous mint at the
// tip, faint brush streaks along each blade and a soft glow.
// Mesh material of a Terrain3DParticles node (see objects/foliage/sky_meadow/).
// The wind and placement come from the Terrain3D particle example, like meadow_grass.
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_lambert_wrap, specular_disabled;

#include "res://shaders/common/meadow_palette.gdshaderinc"

uniform vec4 root_color : source_color = vec4(0.17, 0.34, 0.33, 1.0);
uniform vec4 tip_color : source_color = vec4(0.64, 0.87, 0.77, 1.0);
uniform vec4 patch_color : source_color = vec4(0.56, 0.82, 0.84, 1.0); // second tip colour, in patches
uniform float patch_scale = 0.03;
uniform float meadow_tint : hint_range(0.0, 1.0) = 0.0;  // pull towards the meadow green under the blade
uniform float tip_roundness : hint_range(0.0, 1.0) = 0.85;
uniform float streaks : hint_range(0.0, 1.0) = 0.25;      // brush-stroke stripes along the blade
uniform float glow : hint_range(0.0, 1.0) = 0.12;
uniform vec2 wind_direction = vec2(1.0, 1.0);

varying float blade_t;   // 0 at the root, 1 at the tip
varying vec2 blade_xz;
varying vec3 tint;       // Terrain3D colour map (C tool)
varying float seed;

void vertex() {
	blade_xz = MODEL_MATRIX[3].xz;
	seed = m_hash(blade_xz * 3.17);
	tint = COLOR.rgb;
	// Ribbon mesh spans y = -0.45..0.45 (5 sections of 0.18).
	blade_t = clamp(VERTEX.y / 0.9 + 0.5, 0.0, 1.0);

	// Wide paint stroke: full width most of the way, then a rounded tip.
	float tip = smoothstep(0.55, 1.0, blade_t);
	VERTEX.x *= 1.0 - tip_roundness * tip * tip;

	// Wind (same recipe as the Terrain3D example): bend grows towards the tip.
	vec3 w_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float bend = blade_t * blade_t;
	float scale = pow(INSTANCE_CUSTOM[3] * INSTANCE_CUSTOM[3], 0.707);
	float force = pow(INSTANCE_CUSTOM[2] * bend * scale, 0.707);
	float wobble = sin(TIME * 2.0 * (1.0 + INSTANCE_CUSTOM.r + INSTANCE_CUSTOM.g)) * 0.25 * (1.0 - INSTANCE_CUSTOM[2]);
	vec2 dir = normalize(wind_direction);
	w_vertex.xz -= (vec2(-dir.y, dir.x) * wobble + dir) * force;
	w_vertex.y -= INSTANCE_CUSTOM[2] * force * bend;

	VERTEX = (VIEW_MATRIX * vec4(w_vertex, 1.0)).xyz;
	NORMAL = MODELVIEW_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	vec3 tip_c = mix(srgb(tip_color.rgb), srgb(patch_color.rgb),
			smoothstep(0.4, 0.7, m_fbm(blade_xz * patch_scale + 13.0)));
	vec3 root_c = srgb(root_color.rgb);
	if (meadow_tint > 0.0) {
		vec3 g = meadow_color(blade_xz);
		tip_c = mix(tip_c, g * 1.1, meadow_tint);
		root_c = mix(root_c, g * 0.6, meadow_tint);
	}
	vec3 col = mix(root_c, tip_c, smoothstep(0.0, 0.95, blade_t));

	// Brush streaks: a few stripes along the blade, different per blade.
	float stripe = m_noise(vec2(UV.x * 5.0 + seed * 40.0, blade_t * 1.2));
	col *= 1.0 + (stripe - 0.5) * streaks;
	col *= 0.92 + 0.16 * seed;
	col *= pow(tint, vec3(2.2));

	ALBEDO = apply_cloud_shadow(col, blade_xz, TIME);
	EMISSION = tip_c * glow * smoothstep(0.5, 1.0, blade_t);
	ROUGHNESS = 1.0;
	BACKLIGHT = tip_c * 0.35;
	// Up-facing normal on both sides, so the field lights like one soft surface.
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
