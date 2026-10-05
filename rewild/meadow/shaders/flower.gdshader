// Camera-facing flower heads, scattered with the same cell-hash trick as the
// grass but only inside flower_cluster() islands.
shader_type spatial;
render_mode cull_disabled, world_vertex_coords, specular_disabled;

#include "meadow_common.gdshaderinc"

uniform float spacing = 0.3;
uniform float fade_radius = 30.0;
uniform float head_size = 0.10;
uniform float density : hint_range(0.0, 1.0) = 0.65;

varying vec3 petal_color;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec2 cell = floor(origin.xz / spacing + 0.5);
	vec2 wp = (cell + m_hash2(cell + 2.2) - 0.5) * spacing;
	vec2 t = terrain_sample(wp);

	float dist = length(wp - NODE_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(fade_radius * 0.6, fade_radius, dist);
	// A sprinkle of lone flowers everywhere, dense in the clusters.
	float chance = max(flower_cluster(wp) * density, 0.05);
	float keep = step(0.8, growth_at(wp)) * step(m_hash(cell + 8.8), chance) * fade * (1.0 - step(0.4, t.g))
			* step(water_level + 0.3, t.r);

	vec3 local = VERTEX - origin;
	float size = head_size * (0.7 + 0.6 * m_hash(cell + 4.4)) * keep;
	float stem = mix(0.22, 0.55, m_hash(cell + 6.6)) * (0.7 + 0.6 * m_fbm(wp * 0.08));
	vec2 sway = vec2(sin(TIME * 1.7 + wp.x), cos(TIME * 1.3 + wp.y)) * 0.02;

	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	VERTEX = vec3(wp.x + sway.x, t.r + stem * keep, wp.y + sway.y) + (right * local.x + up * local.y) * size;
	NORMAL = vec3(0.0, 1.0, 0.0);
	petal_color = flower_palette(m_hash(cell + 7.0));
}

void fragment() {
	vec2 d = UV - 0.5;
	float r = length(d);
	if (r > 0.5) discard;
	vec3 col = mix(petal_color, petal_color * 0.75, smoothstep(0.15, 0.5, r));
	// Warm centre dot.
	col = mix(srgb(vec3(1.0, 0.82, 0.3)), col, smoothstep(0.08, 0.14, r));
	ALBEDO = col;
	EMISSION = col * 0.15;
	ROUGHNESS = 1.0;
}
