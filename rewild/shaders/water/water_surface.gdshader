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
uniform float ripple_strength : hint_range(0.0, 0.5) = 0.12;
uniform float wave_height = 0.06;
uniform float wave_speed = 1.0;
group_uniforms noise;
// Off: noise is fixed in the world (flat water). On: noise is fixed to the mesh, so it travels with a
// moving blob. Local mode also turns the vertex waves off, since they assume a flat, Y-up surface.
uniform bool use_local_coords = false;
uniform float local_noise_scale = 1.0;                 // local mode only: raise it for small meshes
group_uniforms foam;
uniform vec3 foam_color : source_color = vec3(1.0);
uniform float foam_width = 0.3;
group_uniforms flow; // rapids: noise slides along the mesh instead of drifting in place
uniform vec3 flow_direction = vec3(0.0, 0.0, 1.0);    // in mesh space; +Z = downstream
uniform float flow_speed = 0.0;                        // metres per second, 0 = still water
uniform float flow_foam : hint_range(0.0, 1.0) = 0.0;  // streaky whitewater stretched along the flow
group_uniforms light;
uniform float caustic_strength = 0.9;
uniform float caustic_scale = 0.6;
uniform float sparkle_strength = 1.2;
uniform float sparkle_threshold : hint_range(0.0, 1.0) = 0.6; // higher = fewer sparkles
group_uniforms underwater; // looking up at the surface from below (StylizedWater keeps these in sync)
uniform vec3 underwater_fog_color : source_color = vec3(0.10, 0.42, 0.58);
uniform float underwater_fog_density = 0.08;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

varying vec3 world_pos;
varying vec3 noise_pos;
varying vec3 flow_dir;

group_uniforms blob;                                   // local-coords mode only
instance uniform float time_offset = 0.0;   // per-blob phase in seconds, set from code at spawn
// Holes: world XZ rects (centre.xy, half size.zw) where this surface isn't drawn, e.g. the
// sea under an inland lake that has its own water. Set by StylizedWater.cutouts.
instance uniform vec4 cutout_0 = vec4(0.0);
instance uniform vec4 cutout_1 = vec4(0.0);
instance uniform vec4 cutout_2 = vec4(0.0);
instance uniform vec4 cutout_3 = vec4(0.0);
// Exact hole shapes over those rects (white = hole). Unset = the whole rect.
uniform sampler2D cutout_mask_0 : hint_default_white, filter_linear, repeat_disable;
uniform sampler2D cutout_mask_1 : hint_default_white, filter_linear, repeat_disable;
uniform sampler2D cutout_mask_2 : hint_default_white, filter_linear, repeat_disable;
uniform sampler2D cutout_mask_3 : hint_default_white, filter_linear, repeat_disable;
// This water's own shape over its footprint (white = water), from StylizedWater.fit_to_basin.
uniform bool use_basin_mask = false;
uniform sampler2D basin_mask : hint_default_white, filter_linear, repeat_disable;
instance uniform vec4 basin_rect = vec4(0.0);  // centre xz, half size

float cutout_mask(int i, vec2 uv) {
	if (i == 0) return textureLod(cutout_mask_0, uv, 0.0).r;
	if (i == 1) return textureLod(cutout_mask_1, uv, 0.0).r;
	if (i == 2) return textureLod(cutout_mask_2, uv, 0.0).r;
	return textureLod(cutout_mask_3, uv, 0.0).r;
}
uniform float blob_density : hint_range(0.0, 3.0) = 1.2;   // how quickly the colour goes from shallow to deep toward the centre
uniform float blob_clarity : hint_range(0.0, 1.0) = 0.25;  // how much of the scene shows through
uniform float blob_foam : hint_range(0.0, 1.0) = 0.6;      // rim foam strength (0 = none)

// --- sin-free hashes (no precision loss at large coordinates) ---
vec3 hash33(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yxx) * p3.zyx);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// 3D gradient noise, roughly -0.5..0.5, quintic fade (no grid seams in the slope).
float gnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(hash33(i) * 2.0 - 1.0, f);
	float b = dot(hash33(i + vec3(1, 0, 0)) * 2.0 - 1.0, f - vec3(1, 0, 0));
	float c = dot(hash33(i + vec3(0, 1, 0)) * 2.0 - 1.0, f - vec3(0, 1, 0));
	float d = dot(hash33(i + vec3(1, 1, 0)) * 2.0 - 1.0, f - vec3(1, 1, 0));
	float e = dot(hash33(i + vec3(0, 0, 1)) * 2.0 - 1.0, f - vec3(0, 0, 1));
	float g = dot(hash33(i + vec3(1, 0, 1)) * 2.0 - 1.0, f - vec3(1, 0, 1));
	float h = dot(hash33(i + vec3(0, 1, 1)) * 2.0 - 1.0, f - vec3(0, 1, 1));
	float k = dot(hash33(i + vec3(1, 1, 1)) * 2.0 - 1.0, f - vec3(1, 1, 1));
	return mix(mix(mix(a, b, u.x), mix(c, d, u.x), u.y), mix(mix(e, g, u.x), mix(h, k, u.x), u.y), u.z);
}

// gnoise remapped to 0..1, for thresholds and masks.
float gn01(vec3 p) {
	return clamp(gnoise(p) * 1.2 + 0.5, 0.0, 1.0);
}

// Gradient of gnoise by tetrahedron sampling (4 taps).
vec3 gnoise_grad(vec3 p) {
	const vec2 k = vec2(1.0, -1.0);
	const float h = 0.05;
	return (k.xyy * gnoise(p + k.xyy * h)
		+ k.yyx * gnoise(p + k.yyx * h)
		+ k.yxy * gnoise(p + k.yxy * h)
		+ k.xxx * gnoise(p + k.xxx * h)) / (4.0 * h);
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
			vec2 o = 0.5 + 0.5 * sin(t + 6.2831 * hash22(i + g));
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

float wave3(vec3 p, float t) {
	return sin(dot(p, vec3(0.7, 0.5, 0.5)) * 1.3 + t * 1.1) * 0.5
		+ sin(dot(p, vec3(-0.5, 0.6, 0.6)) * 2.1 + t * 1.7) * 0.3
		+ sin(dot(p, vec3(0.3, -0.7, 0.6)) * 3.3 + t * 2.3) * 0.2;
}

vec3 view_from_depth(vec2 uv, float raw, mat4 inv_proj) {
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, raw, 1.0);
	return v.xyz / v.w;
}

void vertex() {
	vec3 lp = VERTEX * local_noise_scale;                  // local-space coordinates, before any displacement
	vec3 wp0 = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	noise_pos = use_local_coords ? lp : wp0;
	vec3 fd = use_local_coords ? flow_direction : mat3(MODEL_MATRIX) * flow_direction;
	flow_dir = length(fd) > 0.0001 ? normalize(fd) : vec3(0.0, 0.0, 1.0);
	float t = (TIME + time_offset) * wave_speed;

	if (use_local_coords) {
		// Displace along the surface normal; the wave moves with the mesh.
		float e = 0.05;
		float h = wave3(lp, t);
		vec3 g = vec3(wave3(lp + vec3(e, 0.0, 0.0), t) - h,
			wave3(lp + vec3(0.0, e, 0.0), t) - h,
			wave3(lp + vec3(0.0, 0.0, e), t) - h) / e;       // slope in local space
		vec3 n = normalize(NORMAL);
		vec3 gt = g - dot(g, n) * n;                         // only the part along the surface tilts the normal
		VERTEX += n * h * wave_height;
		NORMAL = normalize(n - gt * wave_height * local_noise_scale);
		world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	} else {
		float e = 0.1;
		float h = wave(wp0.xz, t);
		float hx = wave(wp0.xz + vec2(e, 0.0), t) - h;
		float hz = wave(wp0.xz + vec2(0.0, e), t) - h;
		VERTEX.y += h * wave_height;
		NORMAL = normalize(vec3(-hx * wave_height / e, 1.0, -hz * wave_height / e));
		world_pos = wp0;
		world_pos.y += h * wave_height;
	}
}

void fragment() {
	vec4 cuts[4] = vec4[4](cutout_0, cutout_1, cutout_2, cutout_3);
	for (int i = 0; i < 4; i++) {
		if (cuts[i].z > 0.0 && all(lessThan(abs(world_pos.xz - cuts[i].xy), cuts[i].zw))
				&& cutout_mask(i, (world_pos.xz - cuts[i].xy) / (2.0 * cuts[i].zw) + 0.5) > 0.5)
			discard;
	}
	if (use_basin_mask && basin_rect.z > 0.0
			&& textureLod(basin_mask, (world_pos.xz - basin_rect.xy) / (2.0 * basin_rect.zw) + 0.5, 0.0).r < 0.5)
		discard;
	float t = TIME * wave_speed;
	vec3 np = noise_pos - flow_dir * flow_speed * TIME;    // noise position, sliding downstream when flowing

	// Ripples: two gradient-noise layers drifting in different directions, as a height field.
	vec3 p1 = np * ripple_scale * 2.0 + vec3(t * 0.15, 3.7, t * 0.10);
	vec3 p2 = np * ripple_scale * 3.1 - vec3(t * 0.12, 8.2, -t * 0.17);
	vec3 g = gnoise_grad(p1) + gnoise_grad(p2);           // slope in noise space

	mat3 to_view = mat3(VIEW_MATRIX);
	if (use_local_coords) {
		to_view = to_view * mat3(MODEL_MATRIX);
	}
	vec3 gv = to_view * g;                                 // slope in view space

	vec3 n0 = normalize(NORMAL);                           // wave normal, before ripples
	vec3 gt = gv - dot(gv, n0) * n0;                       // keep only the part along the surface
	NORMAL = normalize(n0 - gt * ripple_strength);
	vec2 ripple = gv.xy;                                   // screen-space push for refraction

		if (FRONT_FACING) {
		vec3 col;
		float foam;

		if (use_local_coords) {
			// Blob: no scene depth. Thickness comes from the viewing angle instead.
			float rim = 1.0 - clamp(dot(n0, VIEW), 0.0, 1.0);          // 0 facing the camera, 1 at the silhouette
			vec3 behind = textureLod(screen_tex, SCREEN_UV + ripple * refraction, 0.0).rgb;
			vec3 water = mix(shallow_color, deep_color, 1.0 - exp(-(1.0 - rim) * blob_density * 2.0));
			col = mix(water, behind * mix(vec3(1.0), shallow_color, 0.55), blob_clarity);
			float fn = gn01(np * 3.0 + vec3(t * 0.3, 5.1, 0.0)) - 0.5;
			foam = blob_foam * smoothstep(0.7, 0.9, rim + fn * 0.35);
		} else {
			// Flat water: depth and thickness come from the scene behind the surface.
			float raw = texture(depth_tex, SCREEN_UV).r;
			vec2 ruv = SCREEN_UV + ripple * refraction;
			vec3 bed_view = view_from_depth(ruv, texture(depth_tex, ruv).r, INV_PROJECTION_MATRIX);
			if (bed_view.z > VERTEX.z) {
				ruv = SCREEN_UV;
				bed_view = view_from_depth(SCREEN_UV, raw, INV_PROJECTION_MATRIX);
			}
			vec3 bed_world = (INV_VIEW_MATRIX * vec4(bed_view, 1.0)).xyz;
			float depth = max(world_pos.y - bed_world.y, 0.0);
			float path = distance(bed_view, VERTEX);

			vec3 bed = textureLod(screen_tex, ruv, 0.0).rgb;
			float caustic_fade = smoothstep(0.02, 0.3, depth) * exp(-depth * 0.6);
			bed += bed * caustics(bed_world.xz * caustic_scale, t * 1.2) * caustic_strength * caustic_fade;
			bed *= mix(vec3(1.0), shallow_color, 0.55);

			vec3 water = mix(deep_color, shallow_color, exp(-depth / color_depth));
			col = mix(water, bed, exp(-path * murkiness));

			float foam_edge = foam_width * (0.5 + gn01(np * 3.0 + vec3(t * 0.3, 5.1, 0.0)));
			foam = smoothstep(0.55, 0.45, depth / max(foam_edge, 0.001));
		}

		if (flow_foam > 0.0) {
			// Squash the noise along the flow so it turns into long white streaks.
			vec3 streak_pos = np - flow_dir * dot(np, flow_dir) * 0.92;
			float streaks = gn01(streak_pos * 3.0 + vec3(0.0, 2.3, 0.0));
			streaks *= 0.75 + 0.5 * gn01(np * 0.8 - vec3(4.1, 0.0, 0.0)); // break the lines up along their length
			float cut = 0.85 - 0.4 * flow_foam;                  // more flow_foam = more of the surface is white
			foam = max(foam, smoothstep(cut, cut + 0.08, streaks));
		}

		float fresnel = pow(1.0 - clamp(dot(n0, VIEW), 0.0, 1.0), 4.0);
		col = mix(col, sky_tint, fresnel * 0.6);

		float sparkle = gn01(np * 22.0 + vec3(t * 1.5, 1.3, 0.0))
			* gn01(np * 17.0 - vec3(t * 1.2, 7.9, 0.0));
		sparkle = smoothstep(sparkle_threshold, sparkle_threshold + 0.1, sparkle) * sparkle_strength * (1.0 - foam);

		ALBEDO = foam_color * foam;
		EMISSION = col * (1.0 - foam) + vec3(sparkle);
		ROUGHNESS = mix(0.04, 0.9, foam);
		SPECULAR = 0.5 * (1.0 - foam);
	} else {
		// From below: a bright "window" to the world above, fading to water at grazing angles.
		vec3 above = textureLod(screen_tex, SCREEN_UV + ripple * refraction * 2.0, 0.0).rgb;
		float window = smoothstep(0.45, 0.8, clamp(dot(n0, VIEW), 0.0, 1.0));
		vec3 col = mix(underwater_fog_color * 1.2, above * mix(vec3(1.0), shallow_color, 0.4), window);
		float fog = 1.0 - exp(-length(VERTEX) * underwater_fog_density);
		ALBEDO = vec3(0.0);
		EMISSION = mix(col, underwater_fog_color, fog);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
	}
	ALPHA = 1.0;
}