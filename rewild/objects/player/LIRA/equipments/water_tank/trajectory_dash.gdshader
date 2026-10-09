shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 color : source_color = vec4(0.2, 1.0, 0.4, 0.6);
uniform float dash_length = 0.5;   // metres per dash+gap
uniform float duty = 0.55;         // fraction that is dash
uniform float scroll_speed = 2.0;

void fragment() {
	float d = fract(UV.x / dash_length - TIME * scroll_speed);
	float dash = step(d, duty);
	float edge = 1.0 - smoothstep(0.5, 1.0, abs(UV.y * 2.0 - 1.0));  // soft edges read as a tube
	ALBEDO = color.rgb;
	ALPHA = color.a * dash * edge;
}