shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Ivy, moss, grass and flowers that overgrow a structure as the ground under it turns
// green; same idea as tree_leaves.gdshader. Each mesh reads the GrowthMap texture at
// its own origin (or at sample_xz, set per instance by GrowingGreenery), then
// dissolves in with 3D noise clumps while the tint fades from dry to fresh.
// GrowthMap.attach_material() binds growth_map at runtime; without it (editor) the
// map defaults to white, so the overgrowth shows fully grown.

uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.2;

uniform sampler2D growth_map : hint_default_white, filter_linear, repeat_disable;
uniform vec2 map_origin = vec2(-512.0, -640.0);  // must match GrowthMap.MAP_ORIGIN
uniform float map_size = 1024.0;         // must match GrowthMap.MAP_SIZE

group_uniforms growth;
// Ground growth where the first bits appear / the overgrowth is full.
uniform float grow_start : hint_range(0.0, 1.0) = 0.45;
uniform float grow_full : hint_range(0.0, 1.0) = 0.85;
// Per-patch random shift of those thresholds, so patches don't fill in in sync.
uniform float jitter : hint_range(0.0, 0.5) = 0.1;
// Size of the clumps that appear together, in model metres.
uniform float clump_size = 0.6;
// Tint of the first, sparse growth; fades to white (the texture's own colour) when full.
uniform vec4 sparse_tint : source_color = vec4(0.72, 0.68, 0.38, 1.0);
// Brightening right at the growing edge.
uniform float fresh_glow : hint_range(0.0, 1.0) = 0.25;

// Ground point to read instead of the mesh origin (y > 0.5 = use it), e.g. for a
// roof over the sea that should follow the shore next to it.
instance uniform vec3 sample_xz = vec3(0.0);

varying flat float v_grow;   // 0 = bare, 1 = fully overgrown
varying vec3 v_model_pos;


float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float value_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}


void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 at = sample_xz.y > 0.5 ? vec2(sample_xz.x, sample_xz.z) : origin.xz;
	vec2 uv = (at - map_origin) / map_size;
	float g = textureLod(growth_map, uv, 0.0).r;
	float j = (hash(floor(origin * 0.5)) - 0.5) * 2.0 * jitter;
	v_grow = smoothstep(grow_start + j, max(grow_full + j, grow_start + j + 0.01), g);
	v_model_pos = VERTEX;
}


void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	// Two octaves: big clumps plus a little breakup at their edges.
	float n = value_noise(v_model_pos / clump_size) * 0.75
			+ value_noise(v_model_pos / clump_size * 3.7) * 0.25;
	n = smoothstep(0.25, 0.75, n);  // value noise bunches around 0.5: spread it so it fills in evenly
	// Remap so 0 hides everything and 1 shows everything.
	float reveal = v_grow * 1.1 - 0.05;
	float edge = reveal - n;  // > 0 = visible

	vec3 col = tex.rgb * albedo_color.rgb * COLOR.rgb;
	col *= mix(sparse_tint.rgb, vec3(1.0), v_grow);
	col *= 1.0 + fresh_glow * (1.0 - smoothstep(0.0, 0.08, edge)) * (1.0 - v_grow);

	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.5;
	ALPHA = edge > 0.0 ? tex.a * albedo_color.a : 0.0;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
}
