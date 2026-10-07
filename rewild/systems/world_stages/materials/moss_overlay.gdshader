// Overlay pass that paints moss on the upward-facing parts of a mesh.
// GrowthProp drives moss_amount per instance (0 = bare, 1 = overgrown).
shader_type spatial;
render_mode blend_mix, depth_draw_never, specular_disabled, diffuse_lambert_wrap;

uniform vec3 moss_dark : source_color = vec3(0.30, 0.48, 0.14);
uniform vec3 moss_light : source_color = vec3(0.58, 0.74, 0.24);
uniform float noise_scale = 1.6;
instance uniform float moss_amount = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

float h(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float n3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h(i), h(i + vec3(1, 0, 0)), f.x), mix(h(i + vec3(0, 1, 0)), h(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(h(i + vec3(0, 0, 1)), h(i + vec3(1, 0, 1)), f.x), mix(h(i + vec3(0, 1, 1)), h(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (moss_amount <= 0.001) discard;
	float n = n3(world_pos * noise_scale) * 0.65 + n3(world_pos * noise_scale * 4.0) * 0.35;
	// Moss favours tops and the ground line.
	float up = smoothstep(0.1, 0.8, world_normal.y);
	float cover = up * 0.8 + 0.25;
	float a = smoothstep(1.0 - moss_amount * cover, 1.05 - moss_amount * cover, n);
	if (a < 0.02) discard;
	ALBEDO = mix(moss_dark, moss_light, n3(world_pos * noise_scale * 2.3));
	ALPHA = a;
	ROUGHNESS = 1.0;
}
