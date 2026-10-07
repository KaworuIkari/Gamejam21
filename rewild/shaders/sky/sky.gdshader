// Bright painted sky with soft cumulus banks near the horizon.
shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.14, 0.52, 0.92);
uniform vec3 horizon_color : source_color = vec3(0.70, 0.86, 0.97);
uniform vec3 cloud_light : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.66, 0.76, 0.90);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.5;
uniform float cloud_speed = 0.004;

float s_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float s_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(s_hash(i), s_hash(i + vec2(1, 0)), u.x), mix(s_hash(i + vec2(0, 1)), s_hash(i + vec2(1, 1)), u.x), u.y);
}

float s_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * s_noise(p);
		p = p * 2.1 + 3.7;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float up = max(dir.y, 0.0);
	vec3 col = mix(horizon_color, zenith_color, pow(up, 0.55));

	if (dir.y < 0.0) {
		COLOR = mix(horizon_color, horizon_color * 0.9, clamp(-dir.y * 3.0, 0.0, 1.0));
	} else {
		// Project onto a cloud plane; clouds bunch up toward the horizon.
		vec2 uv = dir.xz / (dir.y + 0.12) * 1.3 + TIME * cloud_speed * vec2(1.0, 0.3);
		float n = s_fbm(uv);
		float band = mix(1.0, 0.45, smoothstep(0.05, 0.6, up)); // more cloud near horizon
		float c = smoothstep(1.0 - cloud_coverage * band, 1.05 - cloud_coverage * band * 0.6, n);
		// Fake self-shadowing: sample slightly "below" the cloud.
		float n_low = s_fbm(uv + vec2(0.0, -0.06));
		vec3 cloud = mix(cloud_shade, cloud_light, smoothstep(0.35, 0.75, n - n_low * 0.4 + 0.25));
		col = mix(col, cloud, c * smoothstep(0.0, 0.04, dir.y));

		if (LIGHT0_ENABLED) {
			float sun = dot(dir, LIGHT0_DIRECTION);
			col += LIGHT0_COLOR * smoothstep(0.9995, 0.9998, sun) * 4.0 * (1.0 - c);
			col += LIGHT0_COLOR * pow(max(sun, 0.0), 64.0) * 0.25;
		}
		COLOR = col;
	}
}
