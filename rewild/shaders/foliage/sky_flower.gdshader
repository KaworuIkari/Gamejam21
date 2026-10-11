// sky_flower.gdshader: "Sky: Children of the Light"-style flowers. A round, puffy,
// softly glowing head on a thin stem, drawn on one upright quad that turns to face
// the camera (cylindrical billboard). Neighbouring flowers share a hue family, so the
// field reads as bands of pink, violet and yellow instead of confetti.
// Used as the mesh material of a Terrain3DParticles node (see objects/foliage/sky_meadow/).
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

#include "res://shaders/common/meadow_palette.gdshaderinc"

group_uniforms placement;
uniform float coverage : hint_range(0.0, 1.0) = 0.55;      // share of the ground that is flower bed
uniform float bed_scale = 0.06;                            // smaller = bigger flower beds
uniform float density : hint_range(0.0, 1.0) = 0.9;        // flowers per spot inside a bed
uniform float lone_density : hint_range(0.0, 1.0) = 0.02;  // stray flowers outside beds

group_uniforms look;
uniform vec4 color_a : source_color = vec4(0.98, 0.62, 0.86, 1.0); // pink
uniform vec4 color_b : source_color = vec4(0.84, 0.40, 0.88, 1.0); // magenta
uniform vec4 color_c : source_color = vec4(0.60, 0.34, 0.95, 1.0); // violet
uniform vec4 color_d : source_color = vec4(0.98, 0.94, 0.52, 1.0); // butter yellow
uniform vec4 color_e : source_color = vec4(0.99, 0.78, 0.56, 1.0); // peach
uniform vec4 stem_color : source_color = vec4(0.30, 0.52, 0.42, 1.0);
uniform float hue_patch_scale = 0.045;                     // size of the same-colour patches
uniform float hue_mix : hint_range(0.0, 1.0) = 0.35;       // how much colours bleed between patches
uniform float head_size : hint_range(0.1, 0.5) = 0.30;     // head radius, as a share of flower height
uniform float glow : hint_range(0.0, 2.0) = 0.35;          // soft self-glow (pairs with Environment glow)

group_uniforms player_glow;
// Flowers light up around this point (set by foliage_glow_follow.gd). Radius 0 = off.
uniform vec3 glow_center = vec3(0.0);
uniform float glow_radius = 0.0;
uniform float glow_boost = 1.5;

varying vec3 petal;
varying vec3 b_right;   // billboard axes in world space, for the puffy normal
varying vec3 b_facing;
varying float near_glow;
varying vec2 flower_xz;  // for cloud shadows

vec3 pick(float i) {
	if (i < 1.0) return color_a.rgb;
	if (i < 2.0) return color_b.rgb;
	if (i < 3.0) return color_c.rgb;
	if (i < 4.0) return color_d.rgb;
	return color_e.rgb;
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 pos = origin.xz;
	flower_xz = pos;

	// Flower beds: big soft noise blobs; a few strays everywhere else.
	float bed = smoothstep(1.0 - coverage, 1.0 - coverage + 0.12, m_fbm(pos * bed_scale + 23.0));
	float chance = max(bed * density, lone_density);
	bool keep = m_hash(pos + 8.8) < chance;

	// Same-hue patches: a slow noise picks the colour family, a little per-flower jitter.
	float zone = m_fbm(pos * hue_patch_scale + 71.0) * 5.0;
	float idx = clamp(floor(zone + (m_hash(pos + 2.7) - 0.5) * hue_mix * 4.0), 0.0, 4.0);
	petal = srgb(pick(idx)) * (0.9 + 0.2 * m_hash(pos + 5.1));

	float s = keep ? length(MODEL_MATRIX[1].xyz) : 0.0;  // particle size; 0 hides the flower
	s *= smoothstep(0.6, 0.9, growth_at(pos));          // GROWTH: flowers come after the grass

	// Gentle sway, strongest at the head (INSTANCE_CUSTOM.b = Terrain3D wind).
	float sway = (sin(TIME * 1.7 + m_hash(pos) * 6.28) * 0.04 + INSTANCE_CUSTOM.b * 0.12) * VERTEX.y * VERTEX.y;

	// Upright billboard: turn around the world Y axis to face the camera.
	b_right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z) + vec3(1e-5, 0.0, 0.0));
	b_facing = cross(b_right, vec3(0.0, 1.0, 0.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(b_right * s, 0.0),
			vec4(0.0, s, 0.0, 0.0),
			vec4(b_facing * s, 0.0),
			vec4(origin + b_right * sway * s, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);

	near_glow = glow_radius > 0.0 ? 1.0 - smoothstep(glow_radius * 0.3, glow_radius, distance(origin, glow_center)) : 0.0;
}

void fragment() {
	// Quad space in metres-per-flower: x across (-0.3..0.3), y up (0..1).
	vec2 p = vec2((UV.x - 0.5) * 0.6, 1.0 - UV.y);
	vec2 head_c = vec2(0.0, 1.0 - head_size);
	vec2 d = (p - head_c) / head_size;                    // -1..1 inside the head
	float r = length(d);
	bool head = r < 1.0;
	bool stem = abs(p.x) < 0.018 && p.y < head_c.y;
	if (!head && !stem) discard;

	vec3 col;
	vec3 n_world;
	if (head) {
		// Puffy ball: fake sphere normal, soft darker underside, light rim like Sky's petals.
		float nz = sqrt(max(1.0 - r * r, 0.0));
		n_world = normalize(b_right * d.x + vec3(0.0, d.y, 0.0) + b_facing * nz);
		col = petal * mix(0.78, 1.05, smoothstep(-0.8, 0.6, d.y));
		col = mix(col, mix(petal, vec3(1.0), 0.45), smoothstep(0.75, 1.0, r) * 0.6);
		EMISSION = petal * (glow + near_glow * glow_boost) * mix(1.0, 0.6, r);
	} else {
		n_world = b_facing;
		col = srgb(stem_color.rgb) * mix(0.6, 1.0, p.y / head_c.y);
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	ALBEDO = apply_cloud_shadow(col, flower_xz, TIME);
	ROUGHNESS = 1.0;
	BACKLIGHT = petal * 0.4;
}
