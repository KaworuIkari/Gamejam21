shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform vec3 fog_color : source_color = vec3(0.063, 0.302, 0.42);
uniform float fog_density = 0.22;
uniform float max_fog : hint_range(0.0, 1.0) = 0.95;
uniform float max_distance = 1024.0;        // distance used for sky pixels
uniform float above_fade = 0.3;             // metres above the plane over which the effect fades out
uniform vec2 mesh_half = vec2(20.0, 20.0);
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

varying flat float plane_y;
varying flat vec3 local_cam;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
	plane_y = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).y;
	local_cam = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
}

void fragment() {
	if (abs(local_cam.x) > mesh_half.x || abs(local_cam.z) > mesh_half.y)
		discard;

	vec3 cam = CAMERA_POSITION_WORLD;
	float fade = 1.0 - smoothstep(0.0, above_fade, cam.y - plane_y);
	if (fade <= 0.0)
		discard;

	vec2 ndc = SCREEN_UV * 2.0 - 1.0;
	vec4 np = INV_PROJECTION_MATRIX * vec4(ndc, 1.0, 1.0);
	vec3 dir = normalize((INV_VIEW_MATRIX * vec4(np.xyz / np.w, 1.0)).xyz - cam);

	// Distance along the ray to the pixel's real geometry (sky = max_distance).
	float raw = texture(depth_tex, SCREEN_UV).r;
	float dist = max_distance;
	if (raw > 0.0) {
		vec4 v = INV_PROJECTION_MATRIX * vec4(ndc, raw, 1.0);
		dist = min(length(v.xyz / v.w), max_distance);
	}

	// Height of the camera and of the pixel relative to the plane.
	float y0 = cam.y - plane_y + 1000.;
	float y1 = y0 + dir.y * dist;

	// Length of the segment that is below the plane.
	float submerged;
	if (y1 <= 0.0 && y0 <= 0.0) {
		submerged = dist;                          // pixel underwater, whole ray is wet
	} else if (y0 <= 0.0) {
		submerged = dist * (-y0 / (y1 - y0));      // ray exits the water before reaching the pixel
	} else {
		submerged = 0.0;                           // camera above water (mostly caught by fade)
	}
	if (submerged <= 0.0)
		discard;

	ALBEDO = fog_color * mix(0.5, 1.0, 1.0 - SCREEN_UV.y);
	ALPHA = (1.0 - exp(-submerged * fog_density)) * max_fog * fade;
}