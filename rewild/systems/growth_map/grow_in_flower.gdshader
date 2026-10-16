shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Small props (petals, flowers) that only appear on green ground.
// Reads the GrowthMap texture at the prop's origin (works per instance in Proton
// Scatter multimeshes too, and for hand-placed props) and scales the whole mesh
// up from its origin once the ground there is green and dry.
// GrowthMap.attach_material() binds growth_map/wet_map at runtime; without it
// (editor) growth defaults to white and wet to black, so props show fully grown.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.5;

uniform sampler2D growth_map : hint_default_white, filter_linear, repeat_disable;
uniform sampler2D wet_map : hint_default_black, filter_linear, repeat_disable;
uniform vec2 map_origin = vec2(-512.0);  // must match GrowthMap.MAP_ORIGIN
uniform float map_size = 1024.0;         // must match GrowthMap.MAP_SIZE

group_uniforms growth;
// Ground growth where the prop starts to appear / is full size.
uniform float grow_start : hint_range(0.0, 1.0) = 0.6;
uniform float grow_full : hint_range(0.0, 1.0) = 0.9;
// Per-prop random shift of those thresholds, so neighbours don't pop in sync.
uniform float jitter : hint_range(0.0, 0.5) = 0.08;
// Stay closed while the watered ground is still wet (like the particle flowers).
uniform bool wait_for_dry = true;


float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}


void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 uv = (origin.xz - map_origin) / map_size;
	bool inside = all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)));
	float g = inside ? textureLod(growth_map, uv, 0.0).r : 1.0;
	float j = (hash(floor(origin * 2.0)) - 0.5) * 2.0 * jitter;
	float s = smoothstep(grow_start + j, max(grow_full + j, grow_start + j + 0.01), g);
	if (wait_for_dry && inside) {
		s *= 1.0 - smoothstep(0.05, 0.45, textureLod(wet_map, uv, 0.0).r);
	}
	// Ease-out-back: a little overshoot so they pop open.
	float t = s - 1.0;
	s = 1.0 + 2.2 * t * t * t + 1.2 * t * t;
	VERTEX *= max(s, 0.0);  // scale 0 = invisible
}


void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = tex.rgb * albedo_color.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.5;
	ALPHA = tex.a * albedo_color.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
}
