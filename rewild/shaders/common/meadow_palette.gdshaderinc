// meadow_palette.gdshaderinc
// One place that decides "what colour is the meadow here?".
// The terrain and the grass both call meadow_color(), so they always match.

uniform float cloud_shadow_strength : hint_range(0.0, 1.0) = 0.28;
uniform vec2 cloud_shadow_wind = vec2(4.0, 1.5);

// --- Noise helpers ---------------------------------------------------------
float m_hash(vec2 p) {              // random 0..1 from a 2D position
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 m_hash2(vec2 p) {              // two independent randoms 0..1
	return vec2(m_hash(p), m_hash(p + 17.31));
}

float m_noise(vec2 p) {             // smooth "value noise", 0..1
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(m_hash(i), m_hash(i + vec2(1.0, 0.0)), u.x),
			mix(m_hash(i + vec2(0.0, 1.0)), m_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float m_fbm(vec2 p) {               // 4 layers of noise = natural-looking blobs
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * m_noise(p);
		p = p * 2.03 + vec2(13.7, 7.1);
		a *= 0.5;
	}
	return v / 0.9375;
}

vec3 srgb(vec3 c) {                 // colour picker values -> linear (what ALBEDO wants)
	return pow(c, vec3(2.2));
}

// --- The look --------------------------------------------------------------
// Big soft patches of deep / mid / sunny green, by world position (x, z).
vec3 meadow_color(vec2 wp) {
	float big = m_fbm(wp * 0.012);          // ~80 m patches
	float mid = m_fbm(wp * 0.045 + 3.1);    // ~20 m variation inside them
	vec3 deep  = srgb(vec3(0.28, 0.56, 0.14));
	vec3 base  = srgb(vec3(0.47, 0.73, 0.20));
	vec3 sunny = srgb(vec3(0.68, 0.84, 0.30));
	vec3 c = mix(deep, base, smoothstep(0.30, 0.55, big + (mid - 0.5) * 0.25));
	return mix(c, sunny, smoothstep(0.55, 0.78, big + (mid - 0.5) * 0.35));
}

// --- Growth (see GrowthMap autoload) -----------------------------------------
// 0 = barren desert, 1 = full meadow. Defaults to white, so shaders without a
// growth map assigned stay fully green.
uniform sampler2D growth_map : hint_default_white, filter_linear, repeat_disable;
uniform vec2 growth_origin = vec2(-512.0); // must match GrowthMap.MAP_ORIGIN
uniform float growth_size = 1024.0;        // must match GrowthMap.MAP_SIZE
// 0 = dry, 1 = soaked (GrowthMap.wet_texture). Black by default: nothing is wet.
uniform sampler2D wet_map : hint_default_black, filter_linear, repeat_disable;

vec3 desert_color(vec2 wp) {
	float big = m_fbm(wp * 0.015 + 7.0);
	// Wind-streaked dunes: stretch the noise along one axis.
	float streak = m_fbm(vec2(wp.x * 0.02, wp.y * 0.12) + 19.0);
	vec3 dark = srgb(vec3(0.66, 0.47, 0.25));
	vec3 base = srgb(vec3(0.80, 0.61, 0.34));
	vec3 pale = srgb(vec3(0.90, 0.76, 0.50));
	vec3 c = mix(dark, base, smoothstep(0.30, 0.55, big));
	return mix(c, pale, smoothstep(0.55, 0.75, streak) * 0.8);
}

float growth_raw(vec2 wp) {
	vec2 uv = (wp - growth_origin) / growth_size;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) return 1.0;
	return texture(growth_map, uv).r;
}

// Growth with a patchy, noise-broken edge so green spreads in clumps, not circles.
float growth_at(vec2 wp) {
	float g = growth_raw(wp);
	float n = m_fbm(wp * 0.15 + 5.0) * 0.7 + m_noise(wp * 0.9) * 0.3;
	return smoothstep(0.25, 0.75, g + (n - 0.5) * 0.55 * (1.0 - g * g));
}

// How wet the ground is (0..1), with a soft noisy rim like soaked sand.
float wet_at(vec2 wp) {
	vec2 uv = (wp - growth_origin) / growth_size;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) return 0.0;
	float w = texture(wet_map, uv).r;
	float n = m_fbm(wp * 0.4 + 11.0);
	return smoothstep(0.05, 0.45, w + (n - 0.5) * 0.25);
}

// Barren -> damp -> sprouting -> meadow. Each stage has its own noisy threshold,
// so a watered patch darkens first, then greens in clumps from its wettest middle
// and an existing meadow's edge, instead of switching texture in one hard step.
vec3 ground_blend(vec2 wp, vec3 meadow) {
	float g = growth_raw(wp);
	float n = m_fbm(wp * 0.15 + 5.0) * 0.7 + m_noise(wp * 0.9) * 0.3;
	float edge = (n - 0.5) * 0.55 * (1.0 - g * g);
	vec3 col = desert_color(wp);
	// Damp sand: darker and a little cooler; stays visible under the first sprouts.
	vec3 damp = col * srgb(vec3(0.66, 0.60, 0.56));
	col = mix(col, damp, wet_at(wp) * 0.9);
	// Sprouts: an olive haze that arrives early and patchy.
	vec3 sprout = mix(col, srgb(vec3(0.56, 0.60, 0.28)), 0.75);
	float s = smoothstep(0.08, 0.40, g + edge * 1.4 + (m_noise(wp * 2.3) - 0.5) * 0.2);
	col = mix(col, sprout, s);
	// Full meadow, same threshold growth_at() uses so grass blades match.
	return mix(col, meadow, smoothstep(0.25, 0.75, g + edge));
}

// Darkens the colour under big drifting cloud shadows.
vec3 apply_cloud_shadow(vec3 col, vec2 wp, float time) {
	float n = m_fbm((wp + time * cloud_shadow_wind) * 0.0045);
	float shadow = smoothstep(0.52, 0.68, n) * cloud_shadow_strength;
	return col * mix(vec3(1.0), vec3(0.45, 0.55, 0.72), shadow);
}

// Flower clusters: soft islands of colour scattered through the grass (0..1).
float flower_cluster(vec2 wp) {
	return smoothstep(0.52, 0.66, m_fbm(wp * 0.035 + 41.0));
}

// Five pastel flower colours, picked by a 0..1 random number.
vec3 flower_palette(float r) {
	if (r < 0.30) return srgb(vec3(0.98, 0.58, 0.72)); // pink
	if (r < 0.50) return srgb(vec3(0.97, 0.96, 0.92)); // white
	if (r < 0.68) return srgb(vec3(0.68, 0.62, 0.98)); // lavender
	if (r < 0.84) return srgb(vec3(1.00, 0.86, 0.32)); // yellow
	return srgb(vec3(1.00, 0.48, 0.38));               // coral
}
