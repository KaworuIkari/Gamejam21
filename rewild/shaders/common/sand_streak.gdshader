shader_type spatial;
// One grain of blown sand for SandStorm: a thin quad stretched along the particle's
// velocity (needs ParticleProcessMaterial.particle_flag_align_y) and turned to face the
// camera around that axis. Fades with the particle's colour alpha and near the camera.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 sand_color : source_color = vec4(0.9, 0.76, 0.56, 0.75);
uniform float streak_length = 1.4;
uniform float streak_width = 0.05;
uniform float strength = 1.0;   // SandStorm fades the whole storm with this
uniform float near_fade = 1.5;

varying float v_fade;

void vertex() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	float scale = length(MODEL_MATRIX[1].xyz);
	vec3 axis = MODEL_MATRIX[1].xyz / max(scale, 0.0001);
	vec3 to_cam = CAMERA_POSITION_WORLD - centre;
	vec3 side = normalize(cross(axis, to_cam));
	vec3 world = centre + axis * VERTEX.y * streak_length * scale + side * VERTEX.x * streak_width * scale;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	v_fade = smoothstep(near_fade * 0.5, near_fade, length(to_cam));
}

void fragment() {
	float across = 1.0 - abs(UV.x - 0.5) * 2.0;
	float along = sin(UV.y * PI);  // tapered ends
	ALBEDO = sand_color.rgb;
	ALPHA = clamp(sand_color.a * across * along * COLOR.a * strength * v_fade, 0.0, 1.0);
}
