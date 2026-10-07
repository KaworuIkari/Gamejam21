shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

#include "res://shaders/common/meadow_common.gdshaderinc"

uniform float far_flower_start = 25.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 wp = world_pos.xz;
	vec2 t = terrain_sample(wp);

	// Slightly darker than the blade tips so the grass reads as depth, not noise.
	float grow = growth_at(wp);
	vec3 col = mix(desert_color(wp), meadow_color(wp) * 0.97, grow);

	// Steep slopes and the pond banks go a little earthy.
	float slope = 1.0 - world_normal.y;
	col = mix(col, srgb(vec3(0.42, 0.50, 0.22)), smoothstep(0.25, 0.55, slope));
	float bank = 1.0 - smoothstep(water_level - 0.2, water_level + 0.6, world_pos.y);
	col = mix(col, mix(srgb(vec3(0.60, 0.48, 0.34)), srgb(vec3(0.55, 0.55, 0.38)), grow), bank);

	col = mix(col, path_color(wp), smoothstep(0.35, 0.75, t.g));

	// Far away, where flower meshes have faded out, paint flowers as speckles.
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float far = smoothstep(far_flower_start, far_flower_start * 1.6, dist);
	// Speckles up close-ish, then an averaged pastel tint where they would shimmer.
	float cluster = flower_cluster(wp) * (1.0 - t.g) * (1.0 - bank) * smoothstep(0.75, 1.0, grow);
	// Round dots, one per cell; once a cell is only a few pixels wide they would
	// shimmer, so they fade into an averaged pastel tint instead.
	vec2 sp = wp * 2.5;
	vec2 cell = floor(sp);
	vec2 jitter = m_hash2(cell + 3.3) * 0.5 + 0.25;
	float px = length(fwidth(sp));
	float dot_mask = 1.0 - smoothstep(0.16 - px * 0.5, 0.16 + px * 0.5, length(fract(sp) - jitter));
	float speck = step(0.62, m_hash(cell)) * cluster * dot_mask;
	float detail = 1.0 - smoothstep(0.12, 0.35, px);
	col = mix(col, flower_palette(m_hash(cell + 7.0)), speck * far * detail * 0.85);
	col = mix(col, srgb(vec3(0.90, 0.78, 0.80)), cluster * (1.0 - detail) * 0.18);

	ALBEDO = apply_cloud_shadow(col, wp, TIME);
	ROUGHNESS = 1.0;
}
