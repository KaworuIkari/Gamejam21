// Copyright © 2023-2026 Cory Petkovsek, Roope Palmroos, and Contributors.

shader_type spatial;

// MEADOW: matte, wrap-lit blades like res://shaders/foliage/grass.gdshader (generated meadow).
render_mode skip_vertex_transform, cull_disabled, blend_mix, depth_draw_always, diffuse_lambert_wrap, specular_disabled;

#include "res://shaders/common/meadow_palette.gdshaderinc"

uniform vec2 wind_direction = vec2(1.0, 1.0);
// BARREN: dead grass on the desert. Lower coverage = more clumps; density = share of
// blades inside a clump; height = how tall they are compared with full meadow grass.
uniform float dry_coverage : hint_range(0.0, 1.0) = 0.36;
uniform float dry_density : hint_range(0.0, 1.0) = 0.6;
uniform float dry_height : hint_range(0.0, 1.0) = 0.75;

varying vec4 data;

varying vec3 meadow_col; // MEADOW: ground colour under this blade
varying vec2 blade_xz;   // MEADOW: blade position, for cloud shadows
varying vec3 tint;       // MEADOW: Terrain3D colour map (C tool) under this blade
varying float blade_t;   // MEADOW: 0 at the root, 1 at the tip


// A lot of hard coded things here atm.
void vertex() {
	// Wind effect from model data, in this case no vertex colors,
	// so just use vertex Y component, including mesh offset
	data[2] = (VERTEX.y + 0.55);
	data[2] *= data[2]; // make non-linear

	// Ribbon used as a grass mesh.. so pinch the top.
	VERTEX.xz *= (1.0 - data[2]);

	// Save red/green shift for fragment
	data.rg = INSTANCE_CUSTOM.rg;

	// MEADOW: MODEL_MATRIX[3] is this blade's position on the terrain.
	blade_xz = MODEL_MATRIX[3].xz;
	tint = COLOR.rgb;
	blade_t = clamp(VERTEX.y + 0.55, 0.0, 1.0);
	// A few blades catch more light than their neighbours.
	// GROWTH: how green the ground under this blade is (0 = desert, 1 = full meadow).
	float g = growth_at(blade_xz);
	meadow_col = meadow_color(blade_xz) * (0.9 + 0.25 * m_hash(blade_xz * 7.31 + 1.3));
	// Half-grown grass is still dry and yellow.
	meadow_col = mix(srgb(vec3(0.72, 0.70, 0.30)), meadow_col, smoothstep(0.3, 0.9, g));
	// BARREN: sparse clumps of dead, straw-coloured grass survive on the desert.
	// They are the same blades, so they green up and grow tall when the ground revives.
	float clumps = smoothstep(dry_coverage, dry_coverage + 0.18, m_fbm(blade_xz * 0.11 + 31.0));
	float dry = clumps * step(1.0 - dry_density, m_hash(blade_xz * 3.17 + 8.1));
	vec3 straw = mix(srgb(vec3(0.62, 0.50, 0.30)), srgb(vec3(0.84, 0.74, 0.48)), m_hash(blade_xz * 5.3));
	meadow_col = mix(straw, meadow_col, smoothstep(0.0, 0.35, g));
	// Taller, lusher tufts in patches (the base of the ribbon sits at y = -0.55).
	VERTEX.y = (VERTEX.y + 0.55) * (0.7 + 0.6 * m_fbm(blade_xz * 0.08)) - 0.55;
	// GROWTH: blades rise out of the ground as it greens; dry tufts stay short.
	float height = max(g, dry * dry_height * (0.6 + 0.6 * m_hash(blade_xz * 9.7)));
	VERTEX.y = (VERTEX.y + 0.55) * height - 0.55;
	VERTEX.xz *= step(0.02, height); // bare ground: collapse the blade so nothing is drawn

	// World space vertex
	vec3 w_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Get wind force and scale from process()
	float scale = pow(INSTANCE_CUSTOM[3] * INSTANCE_CUSTOM[3], 0.707);
	float force = INSTANCE_CUSTOM[2] * data[2] * scale;
	// Add some cheap jitter at high wind values
	force -= fract(force * 256.0) * force * 0.05;
	// Curve the result
	force = pow(force, 0.707);

	// These 2 combined result in a decent bend without resorting to matrices or pivot data.
	// Lateral move and wobble
	float lateral_wobble = sin(TIME * 2.0 * (1.0 + data.r + data.g)) * 0.25 * (1.0 - INSTANCE_CUSTOM[2]);
	vec2 direction = normalize(wind_direction);
	w_vertex.xz -= (vec2(-direction.y, direction.x) * lateral_wobble + direction) * force;
	// Flatten
	w_vertex.y -= INSTANCE_CUSTOM[2] * force * data[2];

	// Save final wind force value for fragment.
	data[3] = force;

	VERTEX = (VIEW_MATRIX * vec4(w_vertex, 1.0)).xyz;
	// MEADOW: normals point up so the field lights like a soft carpet instead of flat cards.
	NORMAL = normalize(mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0));
	BINORMAL = MODELVIEW_NORMAL_MATRIX * BINORMAL;
	TANGENT = MODELVIEW_NORMAL_MATRIX * TANGENT;
}

void fragment() {
	// MEADOW: same green as the ground, darker at the root, brighter at the tip.
	vec3 root = meadow_col * 0.72;
	vec3 tip = meadow_col * 1.06 + srgb(vec3(0.05, 0.04, 0.0));
	vec3 col = mix(root, tip, smoothstep(0.0, 1.0, blade_t));
	col *= pow(tint, vec3(2.2));                // Terrain3D colour map (C tool)
	ALBEDO = apply_cloud_shadow(col, blade_xz, TIME);
	ROUGHNESS = 1.0;
	ALPHA = 0.999;  // transparent pass: stays out of the depth/normal buffers, so no outline
	BACKLIGHT = vec3(0.25, 0.3, 0.1);
	// Up-facing normal on both sides: Godot flips NORMAL on back faces of double-sided
	// meshes, which would point it down and leave half of every blade dark.
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ALBEDO = pow(ALBEDO, vec3(0.4));
	#endif
}
