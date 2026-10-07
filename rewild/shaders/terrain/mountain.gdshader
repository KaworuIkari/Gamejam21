shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

uniform vec3 rock_color : source_color = vec3(0.52, 0.60, 0.74);
uniform vec3 rock_shadow : source_color = vec3(0.30, 0.40, 0.60);
uniform vec3 snow_color : source_color = vec3(0.95, 0.97, 1.0);
uniform vec3 grass_color : source_color = vec3(0.45, 0.66, 0.30);
uniform float snow_height = 230.0;
uniform float grass_height = 70.0;

varying vec3 world_pos;
varying vec3 world_normal;

float h(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), u.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n = n2(world_pos.xz * 0.02) * 0.6 + n2(world_pos.xz * 0.08) * 0.4;
	vec3 col = mix(rock_shadow, rock_color, smoothstep(0.3, 0.8, n));
	float g = 1.0 - smoothstep(grass_height - 25.0, grass_height + 25.0, world_pos.y + (n - 0.5) * 40.0);
	col = mix(col, grass_color, g * smoothstep(0.55, 0.85, world_normal.y));
	// Snow collects on the flatter faces higher up.
	float s = smoothstep(snow_height - 30.0, snow_height + 30.0, world_pos.y + (n - 0.5) * 80.0);
	s *= smoothstep(0.35, 0.65, world_normal.y + s * 0.2);
	col = mix(col, snow_color, s);
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
