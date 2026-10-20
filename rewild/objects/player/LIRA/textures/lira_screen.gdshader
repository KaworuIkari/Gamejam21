// CRT face screen: swaps between faces in a Texture2DArray with a glitchy transition.
shader_type spatial;
render_mode specular_schlick_ggx;

#include "res://objects/player/LIRA/textures/lira_screen.gdshaderinc"

void fragment() {
	vec3 col = screen_color(UV);
	float pulse = 1.0 + pulse_amount * sin(TAU * pulse_speed * TIME);   // same breathing as your old code
	ALBEDO = col * 0.15;
	EMISSION = col * energy * pulse;
	ROUGHNESS = 0.2;
}