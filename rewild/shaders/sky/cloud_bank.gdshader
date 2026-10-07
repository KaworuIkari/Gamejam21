// Soft painted cloud bank on a camera-facing (Y-locked) quad. Used for the
// puffy clouds that rest on the distant hills.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 light_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 shade_color : source_color = vec3(0.70, 0.80, 0.93);
instance uniform float seed = 0.0;

float c_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float c_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(c_hash(i), c_hash(i + vec2(1, 0)), u.x), mix(c_hash(i + vec2(0, 1)), c_hash(i + vec2(1, 1)), u.x), u.y);
}

float c_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * c_noise(p);
		p = p * 2.07 + 5.3;
		a *= 0.5;
	}
	return v / 0.9375;
}

void vertex() {
	// Face the camera but stay upright.
	vec3 to_cam = CAMERA_POSITION_WORLD - NODE_POSITION_WORLD;
	vec3 fwd = normalize(vec3(to_cam.x, 0.0, to_cam.z));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
	vec2 size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	vec3 world = NODE_POSITION_WORLD + right * VERTEX.x * size.x + vec3(0.0, VERTEX.y * size.y, 0.0);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
}

void fragment() {
	float x = UV.x * 2.0 - 1.0;
	float y = 1.0 - UV.y; // 0 at the base, 1 at the top
	float drift = TIME * 0.004;
	// Puffy silhouette: a domed profile broken up into billows.
	// Two octaves of bumps along the top edge read as stacked cumulus puffs.
	float billow = c_fbm(vec2(x * 2.0 + seed * 13.0 + drift, seed * 7.0));
	float puffs = abs(sin((x + seed) * 7.0 + billow * 3.0));
	float top = sqrt(max(1.0 - x * x, 0.0)) * (0.30 + 0.45 * billow + 0.15 * puffs);
	float n = c_fbm(UV * vec2(7.0, 4.0) + seed * 3.0 + drift);
	float inside = top - y + (n - 0.5) * 0.12;
	float alpha = smoothstep(0.0, 0.06, inside) * smoothstep(0.0, 0.25, y);
	if (alpha < 0.01) discard;

	float lit = clamp(y / max(top, 0.05), 0.0, 1.0);
	vec3 col = mix(shade_color, light_color, smoothstep(0.1, 0.9, lit + (n - 0.5) * 0.4));
	ALBEDO = col;
	ALPHA = alpha * 0.95;
}
