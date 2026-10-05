// Shared helpers for the meadow look. Ground, grass and flowers all call
// meadow_color() so the blades always match the ground under them, which is
// what makes the field read as one soft painted surface from a distance.

uniform sampler2D heightmap : filter_linear, repeat_disable; // R = height (m), G = path mask
uniform vec2 terrain_origin = vec2(-512.0);
uniform float terrain_size = 1024.0;
uniform float heightmap_res = 513.0; // texels per side; texel i sits on vertex i
uniform float water_level = 0.0;
uniform float cloud_shadow_strength : hint_range(0.0, 1.0) = 0.28;
uniform vec2 cloud_shadow_wind = vec2(4.0, 1.5);

// Growth (see GrowthMap autoload): 0 = barren desert, 1 = full meadow.
// Defaults to white, so scenes without a growth map are fully green.
uniform sampler2D growth_map : hint_default_white, filter_linear, repeat_disable;
uniform vec2 growth_origin = vec2(0.0);
uniform float growth_size = 1024.0;

float m_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 m_hash2(vec2 p) {
	return vec2(m_hash(p), m_hash(p + 17.31));
}

float m_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(m_hash(i), m_hash(i + vec2(1.0, 0.0)), u.x),
			mix(m_hash(i + vec2(0.0, 1.0)), m_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float m_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * m_noise(p);
		p = p * 2.03 + vec2(13.7, 7.1);
		a *= 0.5;
	}
	return v / 0.9375;
}

vec3 srgb(vec3 c) {
	return pow(c, vec3(2.2));
}

vec2 terrain_uv(vec2 world_xz) {
	return ((world_xz - terrain_origin) / terrain_size * (heightmap_res - 1.0) + 0.5) / heightmap_res;
}

vec2 terrain_sample(vec2 world_xz) {
	return texture(heightmap, terrain_uv(world_xz)).rg;
}

// Linear-space meadow albedo: big soft patches of deep/mid/sunny green.
vec3 meadow_color(vec2 wp) {
	float big = m_fbm(wp * 0.012);
	float mid = m_fbm(wp * 0.045 + 3.1);
	vec3 deep = srgb(vec3(0.28, 0.56, 0.14));
	vec3 base = srgb(vec3(0.47, 0.73, 0.20));
	vec3 sunny = srgb(vec3(0.68, 0.84, 0.30));
	vec3 c = mix(deep, base, smoothstep(0.30, 0.55, big + (mid - 0.5) * 0.25));
	c = mix(c, sunny, smoothstep(0.55, 0.78, big + (mid - 0.5) * 0.35));
	return c;
}

vec3 path_color(vec2 wp) {
	return srgb(mix(vec3(0.70, 0.60, 0.42), vec3(0.80, 0.72, 0.52), m_noise(wp * 0.7)));
}

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

// 0 = full sun, 1 = under a cloud. Big soft blobs drifting across the field.
float cloud_shadow(vec2 wp, float time) {
	float n = m_fbm((wp + time * cloud_shadow_wind) * 0.0045);
	return smoothstep(0.52, 0.68, n);
}

vec3 apply_cloud_shadow(vec3 albedo, vec2 wp, float time) {
	float s = cloud_shadow(wp, time) * cloud_shadow_strength;
	return albedo * mix(vec3(1.0), vec3(0.45, 0.55, 0.72), s);
}

// Flower clusters: soft islands of colour scattered through the grass.
float flower_cluster(vec2 wp) {
	return smoothstep(0.52, 0.66, m_fbm(wp * 0.035 + 41.0));
}

vec3 flower_palette(float r) {
	if (r < 0.30) return srgb(vec3(0.98, 0.58, 0.72)); // pink
	if (r < 0.50) return srgb(vec3(0.97, 0.96, 0.92)); // white
	if (r < 0.68) return srgb(vec3(0.68, 0.62, 0.98)); // lavender
	if (r < 0.84) return srgb(vec3(1.00, 0.86, 0.32)); // yellow
	return srgb(vec3(1.00, 0.48, 0.38));               // coral
}
