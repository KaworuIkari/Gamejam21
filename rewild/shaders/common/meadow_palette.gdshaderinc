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

// Darkens the colour under big drifting cloud shadows.
vec3 apply_cloud_shadow(vec3 col, vec2 wp, float time) {
	float n = m_fbm((wp + time * cloud_shadow_wind) * 0.0045);
	float shadow = smoothstep(0.52, 0.68, n) * cloud_shadow_strength;
	return col * mix(vec3(1.0), vec3(0.45, 0.55, 0.72), shadow);
}

// Five pastel flower colours, picked by a 0..1 random number.
vec3 flower_palette(float r) {
	if (r < 0.30) return srgb(vec3(0.98, 0.58, 0.72)); // pink
	if (r < 0.50) return srgb(vec3(0.97, 0.96, 0.92)); // white
	if (r < 0.68) return srgb(vec3(0.68, 0.62, 0.98)); // lavender
	if (r < 0.84) return srgb(vec3(1.00, 0.86, 0.32)); // yellow
	return srgb(vec3(1.00, 0.48, 0.38));               // coral
}
