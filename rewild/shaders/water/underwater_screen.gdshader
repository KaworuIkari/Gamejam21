// Screen overlay while submerged: wobble, blue-green tint, light shafts and vignette.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.78, 0.95, 1.0);
uniform float distortion = 0.004;
uniform float ray_strength = 0.16;
uniform float vignette : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	vec2 uv = SCREEN_UV;
	uv += vec2(sin(uv.y * 25.0 + TIME * 2.0), cos(uv.x * 20.0 + TIME * 1.7)) * distortion;
	vec3 c = texture(screen_tex, uv).rgb * tint;

	// Slanted shafts of light coming down from the surface.
	float x = uv.x + (1.0 - uv.y) * 0.25;
	float rays = (sin(x * 18.0 + TIME * 0.4) * 0.5 + 0.5) * (sin(x * 31.0 - TIME * 0.3) * 0.5 + 0.5);
	c += pow(rays, 3.0) * smoothstep(1.0, 0.0, uv.y) * ray_strength * vec3(0.85, 1.0, 1.0);

	c *= mix(1.0 - vignette, 1.0, smoothstep(0.85, 0.3, length(uv - 0.5)));
	COLOR = vec4(c, 1.0);
}
