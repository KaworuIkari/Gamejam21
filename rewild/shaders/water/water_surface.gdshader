// Clear stylized water: see-through shallows, caustics on the bed, shoreline foam,
// sun sparkles and gentle waves. Also draws its underside when the camera dives.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_always, specular_schlick_ggx;

group_uniforms colour;
uniform vec3 shallow_color : source_color = vec3(0.45, 0.90, 0.93);
uniform vec3 deep_color : source_color = vec3(0.06, 0.36, 0.72);
uniform vec3 sky_tint : source_color = vec3(0.80, 0.90, 1.00);
uniform float color_depth = 2.5;                       // metres until the water looks fully "deep"
uniform float murkiness : hint_range(0.0, 2.0) = 0.45; // how fast the bed fades out (0 = crystal clear)
group_uniforms surface;
uniform float refraction : hint_range(0.0, 0.1) = 0.025;
uniform float ripple_scale = 0.5;
uniform float wave_height = 0.06;
uniform float wave_speed = 1.0;
group_uniforms foam;
uniform vec3 foam_color : source_color = vec3(1.0);
uniform float foam_width = 0.3;
group_uniforms light;
uniform float caustic_strength = 0.9;
uniform float caustic_scale = 0.6;
uniform float sparkle_strength = 1.2;
group_uniforms underwater; // looking up at the surface from below (StylizedWater keeps these in sync)
uniform vec3 underwater_fog_color : source_color = vec3(0.10, 0.42, 0.58);
uniform float underwater_fog_density = 0.08;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

// Distance to the nearest Voronoi cell border; the bright web of caustics lives on the borders.
float voronoi_edge(vec2 p, float t) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = 0.5 + 0.5 * sin(t + 6.2831 * hash2(i + g));
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

float caustics(vec2 p, float t) {
	float e = min(voronoi_edge(p, t), voronoi_edge(p * 1.37 + 4.1, t * 1.3));
	return 1.0 - smoothstep(0.0, 0.14, e);
}

// Sum of three sines: big slow swell plus smaller chop. Mirrored in stylized_water.gd.
float wave(vec2 p, float t) {
	return sin(dot(p, vec2(0.8, 0.6)) * 1.3 + t * 1.1) * 0.5
		+ sin(dot(p, vec2(-0.5, 0.9)) * 2.1 + t * 1.7) * 0.3
		+ sin(dot(p, vec2(0.2, -1.0)) * 3.3 + t * 2.3) * 0.2;
}

vec3 view_from_depth(vec2 uv, float raw, mat4 inv_proj) {
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, raw, 1.0);
	return v.xyz / v.w;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	float e = 0.1;
	float h = wave(world_pos.xz, t);
	float hx = wave(world_pos.xz + vec2(e, 0.0), t) - h;
	float hz = wave(world_pos.xz + vec2(0.0, e), t) - h;
	VERTEX.y += h * wave_height;
	NORMAL = normalize(vec3(-hx * wave_height / e, 1.0, -hz * wave_height / e));
	world_pos.y += h * wave_height;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 wp = world_pos.xz;

	// Ripple normal from two noise layers drifting in different directions.
	vec2 r1 = wp * ripple_scale * 2.0 + vec2(t * 0.15, t * 0.10);
	vec2 r2 = wp * ripple_scale * 3.1 - vec2(t * 0.12, -t * 0.17);
	float eps = 0.05;
	float n = noise(r1) + noise(r2);
	vec2 ripple = vec2(
		noise(r1 + vec2(eps, 0.0)) + noise(r2 + vec2(eps, 0.0)) - n,
		noise(r1 + vec2(0.0, eps)) + noise(r2 + vec2(0.0, eps)) - n) / eps;
	NORMAL_MAP = normalize(vec3(-ripple * 0.12, 1.0)) * 0.5 + 0.5;

	if (FRONT_FACING) {
		// What is behind the surface, bent slightly by the ripples.
		float raw = texture(depth_tex, SCREEN_UV).r;
		vec2 ruv = SCREEN_UV + ripple * refraction;
		vec3 bed_view = view_from_depth(ruv, texture(depth_tex, ruv).r, INV_PROJECTION_MATRIX);
		if (bed_view.z > VERTEX.z) { // that pixel is in front of the water: don't drag it in
			ruv = SCREEN_UV;
			bed_view = view_from_depth(SCREEN_UV, raw, INV_PROJECTION_MATRIX);
		}
		vec3 bed_world = (INV_VIEW_MATRIX * vec4(bed_view, 1.0)).xyz;
		float depth = max(world_pos.y - bed_world.y, 0.0);  // straight down to the bed
		float path = distance(bed_view, VERTEX);             // how much water the eye looks through

		vec3 bed = textureLod(screen_tex, ruv, 0.0).rgb;
		float caustic_fade = smoothstep(0.02, 0.3, depth) * exp(-depth * 0.6);
		bed += bed * caustics(bed_world.xz * caustic_scale, t * 1.2) * caustic_strength * caustic_fade;
		bed *= mix(vec3(1.0), shallow_color, 0.55);

		vec3 water = mix(deep_color, shallow_color, exp(-depth / color_depth));
		vec3 col = mix(water, bed, exp(-path * murkiness));

		float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
		col = mix(col, sky_tint, fresnel * 0.6);

		float foam_edge = foam_width * (0.5 + noise(wp * 3.0 + t * 0.3));
		float foam = smoothstep(0.55, 0.45, depth / max(foam_edge, 0.001));

		float sparkle = noise(wp * 22.0 + t * 1.5) * noise(wp * 17.0 - t * 1.2);
		sparkle = smoothstep(0.62, 0.72, sparkle) * sparkle_strength * (1.0 - foam);

		ALBEDO = foam_color * foam;              // foam is lit (gets shadows)
		EMISSION = col * (1.0 - foam) + vec3(sparkle);
		ROUGHNESS = mix(0.04, 0.9, foam);
		SPECULAR = 0.5 * (1.0 - foam);
	} else {
		// From below: a bright "window" to the world above, fading to water at grazing angles.
		vec3 above = textureLod(screen_tex, SCREEN_UV + ripple * refraction * 2.0, 0.0).rgb;
		float window = smoothstep(0.45, 0.8, clamp(dot(NORMAL, VIEW), 0.0, 1.0));
		vec3 col = mix(underwater_fog_color * 1.2, above * mix(vec3(1.0), shallow_color, 0.4), window);
		float fog = 1.0 - exp(-length(VERTEX) * underwater_fog_density);
		ALBEDO = vec3(0.0);
		EMISSION = mix(col, underwater_fog_color, fog);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
	}
	ALPHA = 1.0;
}
