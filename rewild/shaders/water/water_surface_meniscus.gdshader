shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, depth_test_disabled;

uniform float water_level = 0.0;          // world Y, set from StylizedWater
uniform float wave_height = 0.06;         // match the surface material
uniform float wave_speed = 1.0;

uniform vec3 meniscus_color : source_color = vec3(0.55, 0.80, 0.85);
uniform float meniscus_opacity : hint_range(0.0, 1.0) = 0.7;
uniform float meniscus_px = 24.0;   // half-thickness in pixels

uniform vec2 mesh_half = vec2(20.0, 20.0);   // PlaneMesh size * 0.5, in local units
uniform float clipping_plane_bias = 1.0;    // view-space depth of the plane, 1 is exact
// If meniscus is not aligned with actual quad clipping pos on screen, it's a tessellation but caused by low water quad resolution
// to avoid tesselation bug: 
// increase water mesh quad's subdivision to match shader, or increase meniscus width
// flat skips interpolation — all vertices give the same value, and it avoids any float drift across the triangle.
varying flat float plane_y;
varying flat vec3 local_cam;
// not the best practice to get meniscus, other methods awaits...

float wave(vec2 p, float t) {
	return sin(dot(p, vec2(0.8, 0.6)) * 1.3 + t * 1.1) * 0.5
		+ sin(dot(p, vec2(-0.5, 0.9)) * 2.1 + t * 1.7) * 0.3
		+ sin(dot(p, vec2(0.2, -1.0)) * 3.3 + t * 2.3) * 0.2;
}

float surface_y(vec2 xz, float t, float base) {
	return base + wave(xz, t) * wave_height;
}

void vertex() {
	plane_y = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).y;
	local_cam = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment(){
	if (abs(local_cam.x) > mesh_half.x || abs(local_cam.z) > mesh_half.y)
		discard;
	vec2 ndc = SCREEN_UV * 2.0 - 1.0;
	vec4 np = INV_PROJECTION_MATRIX * vec4(ndc, 1.0, 1.0);   // reverse-Z: 1.0 is the near plane
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 dir = normalize((INV_VIEW_MATRIX * vec4(np.xyz / np.w, 1.0)).xyz - cam);
	float t = TIME * wave_speed;

	vec4 nr = INV_PROJECTION_MATRIX * vec4(0.0, 0.0, 1.0, 1.0);
	float near_d = -nr.z / nr.w;
	float d = near_d * clipping_plane_bias;  // camera clipping plane
	vec3 fwd = -INV_VIEW_MATRIX[2].xyz;                  // camera forward in world space
	float tt = d / max(dot(dir, fwd), 1e-4);    // dir is unit; scale to reach the plane
	vec3 P = cam + dir * tt;    // world space pixel position
	
	float s = P.y - surface_y(P.xz, t, plane_y);
	float band = 1.0 - smoothstep(0.0, meniscus_px, abs(s) / max(fwidth(s), 1e-6));
	float m = band * meniscus_opacity;
	ALBEDO = meniscus_color;
	ALPHA = m;
}