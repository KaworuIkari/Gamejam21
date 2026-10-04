// GPU grass. The MultiMesh is a fixed grid that follows the camera in
// spacing-sized steps; every blade derives its jitter, height and yaw from a
// hash of its world cell, so blades stay put while the patch moves.
shader_type spatial;
render_mode cull_disabled, world_vertex_coords, diffuse_lambert_wrap, specular_disabled;

#include "meadow_common.gdshaderinc"

uniform float spacing = 0.25;
uniform float fade_radius = 36.0;
uniform float blade_height_min = 0.18;
uniform float blade_height_max = 0.45;
uniform float blade_width = 0.10;
uniform float wind_strength = 0.25;
uniform vec2 wind_direction = vec2(1.0, 0.35);

varying vec3 base_color;
varying float blade_t;

void vertex() {
	// Instance origin in world space (instance transforms are pure translations).
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec2 cell = floor(origin.xz / spacing + 0.5);
	vec2 rnd = m_hash2(cell);
	vec2 wp = (cell + rnd - 0.5) * spacing;

	vec2 t = terrain_sample(wp);
	float ground_h = t.r;

	float dist = length(wp - NODE_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(fade_radius * 0.55, fade_radius, dist);
	float keep = fade * (1.0 - smoothstep(0.3, 0.6, t.g)) * smoothstep(water_level + 0.05, water_level + 0.35, ground_h);
	// Taller, lusher tufts in patches.
	float lush = m_fbm(wp * 0.08);
	float h = mix(blade_height_min, blade_height_max, m_hash(cell + 3.7)) * (0.7 + 0.6 * lush) * keep;

	// Local blade vertex: x across the blade, y in [0,1] along it.
	vec3 local = VERTEX - origin;
	blade_t = local.y;
	float yaw = m_hash(cell + 9.1) * TAU;
	vec2 side = vec2(cos(yaw), sin(yaw));
	vec2 facing = vec2(-side.y, side.x);

	float y = local.y;
	vec2 lean = facing * (m_hash(cell + 5.3) - 0.3) * 0.35;
	float gust = m_fbm(wp * 0.05 - TIME * wind_direction * 0.25);
	vec2 sway = normalize(wind_direction) * (gust * 1.4 - 0.25) * wind_strength
			+ normalize(wind_direction) * sin(TIME * 2.3 + rnd.x * 6.0) * 0.04;
	vec2 bend = (lean + sway) * y * y * h;

	vec3 p;
	p.xz = wp + side * local.x * blade_width + bend;
	p.y = ground_h + y * h * (1.0 - 0.25 * dot(bend, bend));
	VERTEX = p;
	// Point normals up so the field lights like a soft carpet instead of flat cards.
	NORMAL = normalize(vec3(bend.x * 0.5, 1.0, bend.y * 0.5));

	base_color = meadow_color(wp);
	// A few blades catch more light than their neighbours.
	base_color *= 0.9 + 0.25 * m_hash(cell + 1.3);
}

void fragment() {
	vec3 root = base_color * 0.72;
	vec3 tip = base_color * 1.12 + srgb(vec3(0.06, 0.05, 0.0));
	vec3 col = mix(root, tip, smoothstep(0.0, 1.0, blade_t));
	ALBEDO = apply_cloud_shadow(col, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz, TIME);
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.25, 0.3, 0.1);
}
