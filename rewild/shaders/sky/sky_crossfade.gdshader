// Two equirectangular panoramas cross-faded by `blend` (0 = sky_from, 1 = sky_to).
// Driven by SkyProgression (systems/world_objects/sky_progression.gd).
shader_type sky;

uniform sampler2D sky_from : source_color, filter_linear, repeat_enable;
uniform sampler2D sky_to : source_color, filter_linear, repeat_enable;
uniform float blend : hint_range(0.0, 1.0) = 0.0;
uniform float energy : hint_range(0.0, 4.0) = 1.0;

void sky() {
	// Lod 0: mip selection jumps at the u wrap and draws a seam.
	vec3 a = textureLod(sky_from, SKY_COORDS, 0.0).rgb;
	vec3 b = textureLod(sky_to, SKY_COORDS, 0.0).rgb;
	COLOR = mix(a, b, blend) * energy;
}
