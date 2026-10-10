// CRT face screen: swaps between faces in a Texture2DArray with a glitchy transition.
shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2DArray faces : source_color, filter_nearest, repeat_disable;
uniform int face_count = 6;
uniform int from_layer = 0;
uniform int to_layer = 0;
uniform float transition : hint_range(0.0, 1.0) = 1.0;   // 0 = swap starts, 1 = finished; the script tweens it

group_uniforms glitch;
uniform float glitch_amount : hint_range(0.0, 2.0) = 1.0; // strength of the swap glitch
uniform float idle_glitch : hint_range(0.0, 1.0) = 0.0;   // constant background glitch
uniform float flash_rate = 24.0;                          // glitch "frames" per second
uniform float block_rows = 24.0;
uniform float rgb_split = 0.03;

group_uniforms crt;
uniform vec3 tint : source_color = vec3(1.0);
uniform float energy = 1.0;
uniform float pulse_amount = 0.8;
uniform float pulse_speed = 0.5;
uniform float scanline_count = 80.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.3;
uniform float vignette : hint_range(0.0, 1.0) = 0.5;

float h11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 face(vec2 uv, int layer) {
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return vec3(0.0);
	}
	return textureLod(faces, vec3(uv, float(layer)), 0.0).rgb;
}

void fragment() {
	float step_t = floor(TIME * flash_rate);
	float g = pow(sin(transition * PI), 0.7) * glitch_amount;   // 0 at both ends, 1 in the middle
	float G = clamp(g + idle_glitch, 0.0, 1.5);

	vec2 uv = UV;

	// occasional vertical roll
	float roll = step(0.85, h11(step_t * 1.3 + 5.0)) * G * 0.12;
	uv.y = fract(uv.y + roll);

	// torn rows
	float row = floor(uv.y * block_rows);
	float n = h21(vec2(row, step_t));
	float torn = step(1.0 - G * 0.45, n);
	uv.x += (h21(vec2(row, step_t + 17.0)) - 0.5) * 0.35 * G * torn;

	// which face: old, then new, with quick flashes through the other faces in between
	int layer = transition < 0.5 ? from_layer : to_layer;
	float window = smoothstep(0.2, 0.35, transition) * (1.0 - smoothstep(0.65, 0.8, transition));
	if (h21(vec2(step_t, 3.0)) < window * 0.85) {
		layer = int(floor(h21(vec2(step_t, 11.0)) * float(face_count))) % face_count;
	}

	// colour channels split sideways
	float split = rgb_split * G * (0.4 + h11(step_t * 0.7));
	vec3 col;
	col.r = face(uv + vec2(split, 0.0), layer).r;
	col.g = face(uv, layer).g;
	col.b = face(uv - vec2(split, 0.0), layer).b;
	col *= tint;

	// static, flicker, scanlines, vignette
	col += (h21(UV * vec2(160.0, 90.0) + step_t) - 0.5) * 0.4 * G;
	col *= 1.0 + (h11(step_t * 0.37) - 0.5) * 0.7 * G;
	col *= 1.0 - scanline_strength * (0.5 + 0.5 * sin((UV.y + TIME * 0.03) * scanline_count * TAU));
	col *= mix(1.0, smoothstep(0.8, 0.25, length(UV - 0.5)), vignette);
	col = max(col, vec3(0.0));

	float pulse = 1.0 + pulse_amount * sin(TAU * pulse_speed * TIME);   // same breathing as your old code
	ALBEDO = col * 0.15;
	EMISSION = col * energy * pulse;
	ROUGHNESS = 0.2;
}