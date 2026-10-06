shader_type spatial;
render_mode blend_mix, depth_prepass_alpha;
uniform bool billboard = false;
uniform sampler2D shape_texture;
uniform sampler2D shape_atlas;
uniform bool use_atlas = false;
group_uniforms Colors;
uniform sampler2D noise_texture;
uniform sampler2D color_gradient;
uniform float random_variation : hint_range(0.0, 1.0, 0.001) = 0.002;
group_uniforms Wind;
uniform sampler2D wind_texture;
uniform float wind_speed = 1;
uniform float wind_frequency = 1;
// New controls for big wave
uniform float big_wave_strength : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float big_wave_frequency : hint_range(0.002, 0.3, 0.001) = 0.012;
uniform float big_wave_speed : hint_range(0.0,2.0,0.01) = 0.7;
// gerstner_wave
uniform float swell_wavelength = 20.0;
uniform float swell_speed = 1.0;
uniform vec2 swell_direction = vec2(1.0,0.4);

group_uniforms Transparency;
uniform float alpha_cut_start : hint_range(0.0, 1.0, 0.05) = 0.1;
uniform float alpha_cut_end : hint_range(0.0, 1.0, 0.05) = 0.9;
uniform int alpha_mode : hint_enum("Smooth", "Dithered", "Cut") = 0;
varying flat int id;
varying vec3 world_pos;
#include "util/dither.gdshaderinc"

vec2 atlas_uv(vec2 uv, int index, int size){
	int tile_count = size * size;
	int i = index % tile_count;
	float x = float(i % size);
	float y = float(i / size);
	vec2 tile_size = 1.0 / vec2(float(size));
	return uv* tile_size + (vec2(x, y) * tile_size);
}

float randomf(int index, int seed){
	float value = sin(float(index + seed)) * 0.5 + 0.5;
	return value;
}

float wind_noise(vec2 uv_blade)
{
    // Original small local wind
    float local = texture(wind_texture, (world_pos.xz*0.03) - (wind_speed)).r;

    // Huge large-scale wave
    float wave_scale = 0.008;
    float wave_speed = 0.008;
    float instance_phase = randomf(id, 5) * TAU;
    vec2 wave_uv = world_pos.xz * wave_scale + vec2(TIME * wave_speed) + vec2(sin(TIME * 0.4 + instance_phase));
    float big_wave = texture(wind_texture, wave_uv).r;

    return local * 0.6 + big_wave * 0.4;
}

vec3 gerstner_wave(vec2 world_xz, float time)
{
    vec2 wave_dir = normalize(swell_direction);
    float wave_len = swell_wavelength;
    float wave_speed = swell_speed;
    float amp = big_wave_strength;

    float k = 2.0 * PI / wave_len;
    float phase = k * dot(world_xz, wave_dir) - time * wave_speed;

    vec2 disp = wave_dir * sin(phase) * amp;
    return vec3(disp.x, 0.0, disp.y);
}

vec3 wind(vec2 uv)
{
    float combined_noise = wind_noise(uv);
    float wind_affect = pow(1.0 - uv.y, 2.0);

    // Original local sway
    vec3 small_sway = vec3(
        combined_noise * wind_speed * sin(wind_frequency * TIME + combined_noise),
        0.0,
        combined_noise * wind_speed * cos(wind_frequency * TIME + combined_noise)
    ) * 0.25;

    // Huge rolling wave overlay
    // ===== Huge sweeping wave (fixed: 2D noise for rotation, no single global tilt) =====
    float big_scale = 0.008; // smaller = larger, broader gusts
    float big_speed = 0.006;
    vec2 big_uv = world_pos.xz * big_scale - vec2(TIME * big_speed);
    float big_noise_r = texture(wind_texture, big_uv).r;
    float big_noise_g = texture(wind_texture, big_uv + vec2(0.15,0.15)).r;

    // Noise → angle, direction varies across terrain
    float big_angle = (big_noise_r - 0.5) * 2.2;
    // Slow rotation over time, plus per-instance phase offset to break sync
    big_angle += TIME * 0.25 + randomf(id, 2) * TAU;

    vec2 big_dir = vec2(cos(big_angle), sin(big_angle));
    vec3 big_wave_sway = vec3(big_dir, 0.0) * big_wave_strength * big_noise_g;
	
	vec3 swell = gerstner_wave(world_pos.xz, TIME);
	
    vec3 total = (small_sway + big_wave_sway + swell) * wind_affect;
    return total;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	id = INSTANCE_ID;
	if(billboard){
		mat4 billboard_matrix = mat4(
				MAIN_CAM_INV_VIEW_MATRIX[0],
				MAIN_CAM_INV_VIEW_MATRIX[1],
				MAIN_CAM_INV_VIEW_MATRIX[2],
				MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = VIEW_MATRIX * billboard_matrix;
		VERTEX += (VIEW_MATRIX * vec4(wind(UV), 0.0)).xyz;
	} else {
		VERTEX += wind(UV);
	}
	NORMAL = vec3(0.0,1.0,0.0);
}

void fragment() {
	float shape_value = texture(shape_texture, UV).r;
	if(use_atlas){
		vec2 atlas_uv = atlas_uv(UV, id, 2);
		shape_value = texture(shape_atlas, atlas_uv).r;
	}
	float noise_value = texture(noise_texture, world_pos.xz * 0.1).r;
	if(randomf(id,1) < random_variation) noise_value += 0.4;
	vec4 color = texture(color_gradient, vec2(noise_value, 0.0));
	ALBEDO = color.rgb;

	float alpha = shape_value;
	if(alpha_mode == 0){
		ALPHA = alpha;
	} else {
		alpha = clamp((shape_value - alpha_cut_start) / (alpha_cut_end - alpha_cut_start), 0.0, 1.0);
		if(alpha_mode == 1){
			alpha = step(bayer4(FRAGCOORD.xy) + 0.01, alpha);
		}
		if(alpha < 0.1) discard;
	}
}