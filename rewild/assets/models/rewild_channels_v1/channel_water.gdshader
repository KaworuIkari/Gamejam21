shader_type spatial;
render_mode cull_disabled;
uniform vec3 water_color : source_color = vec3(0.06, 0.33, 0.34);
uniform vec2 flow_direction = vec2(0.0, -1.0);
uniform float flow_speed = 0.7;
varying vec3 local_position;
void vertex() { local_position = VERTEX; }
void fragment() {
 float along = dot(local_position.xz, normalize(flow_direction));
 float ripples = sin(along * 14.0 - TIME * flow_speed * 7.0 + sin(local_position.x * 9.0) * 0.8);
 float glints = smoothstep(0.88, 1.0, ripples) * 0.18;
 ALBEDO = water_color + vec3(glints);
 ROUGHNESS = 0.28;
 METALLIC = 0.08;
}
