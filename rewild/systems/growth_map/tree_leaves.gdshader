shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Tree leaves that grow back with the ground under the tree.
// Reads the GrowthMap texture at the tree's origin (works per instance in Proton
// Scatter multimeshes too), then dissolves leaf clumps in with 3D noise and fades
// the tint from dry to fresh. GrowthMap.attach_material() binds growth_map at runtime;
// without it (editor) the map defaults to white, so trees show fully leafed.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.2;

uniform sampler2D growth_map : hint_default_white, filter_linear, repeat_disable;
uniform vec2 map_origin = vec2(-512.0);  // must match GrowthMap.MAP_ORIGIN
uniform float map_size = 1024.0;         // must match GrowthMap.MAP_SIZE

group_uniforms growth;
// Ground growth where the first leaves appear / the canopy is full.
uniform float leaf_start : hint_range(0.0, 1.0) = 0.3;
uniform float leaf_full : hint_range(0.0, 1.0) = 0.85;
// Per-tree random shift of those thresholds, so neighbours don't leaf out in sync.
uniform float tree_jitter : hint_range(0.0, 0.5) = 0.12;
// Size of the leaf clumps that appear together, in model metres.
uniform float clump_size = 1.2;
// Tint of the first, sparse leaves; fades to white (the texture's own colour) when full.
uniform vec4 sparse_tint : source_color = vec4(0.72, 0.68, 0.38, 1.0);
// Brightening of the leaves right at the growing edge.
uniform float fresh_glow : hint_range(0.0, 1.0) = 0.25;

varying flat float v_leaf;   // 0 = bare, 1 = full canopy
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
	vec2 uv = (origin.xz - map_origin) / map_size;
	float g = textureLod(growth_map, uv, 0.0).r;
	float j = (hash(floor(origin * 0.5)) - 0.5) * 2.0 * tree_jitter;
	v_leaf = smoothstep(leaf_start + j, max(leaf_full + j, leaf_start + j + 0.01), g);
	v_model_pos = VERTEX;
}


void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	// Two octaves: big clumps plus a little breakup at their edges.
	float n = value_noise(v_model_pos / clump_size) * 0.75
			+ value_noise(v_model_pos / clump_size * 3.7) * 0.25;
	n = smoothstep(0.25, 0.75, n);  // value noise bunches around 0.5: spread it so leaves fill in evenly
	// Remap so 0 hides everything and 1 shows everything.
	float reveal = v_leaf * 1.1 - 0.05;
	float edge = reveal - n;  // > 0 = visible

	vec3 col = tex.rgb * albedo_color.rgb * COLOR.rgb;
	col *= mix(sparse_tint.rgb, vec3(1.0), v_leaf);
	col *= 1.0 + fresh_glow * (1.0 - smoothstep(0.0, 0.08, edge)) * (1.0 - v_leaf);

	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.5;
	ALPHA = edge > 0.0 ? tex.a * albedo_color.a : 0.0;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
}
