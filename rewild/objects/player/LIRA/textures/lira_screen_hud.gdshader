// The face screen for the HUD corner: same faces and glitches as the 3D screen, without lighting.
shader_type canvas_item;

#include "res://objects/player/LIRA/textures/lira_screen.gdshaderinc"

uniform float hud_pulse = 0.15;   // the 3D screen's emission pulse, toned down for flat UI

void fragment() {
	vec3 col = screen_color(UV);
	float pulse = 1.0 + hud_pulse * sin(TAU * pulse_speed * TIME);
	COLOR = vec4(col * energy * pulse, 1.0);
}
