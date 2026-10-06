# Meadow look on a hand-sculpted Terrain3D map

How to give a Terrain3D map the Ghibli-style meadow look (soft green ground, grass that only grows near the player, flower clusters, cloud shadows) using standard Terrain3D and Godot features. You write every file yourself; all code below is copy-pasteable and was tested on `meadow_hand.tscn` with Godot 4.7.2 + Terrain3D 1.0.2.

## The idea in one picture

```
meadow_palette.gdshaderinc   <- ONE function: meadow_color(x, z) = "which green is here"
        |                         (+ cloud shadows, flower colours)
        +--> meadow_terrain.gdshader    Terrain3D ground (shader override)
        +--> meadow_grass.gdshader      grass blades     (Terrain3D particle example)
        +--> meadow_flower.gdshader     flower heads     (Terrain3D particle example)
```

Because ground, grass and flowers all ask the same function for their colour, they always match, and the field reads as one painted surface.

Grass is not stored anywhere. Terrain3D's **particle example** (`addons/terrain_3d/extras/particle_example/`) spawns a grid of grass around the camera every frame, reading the terrain's height/texture/colour maps on the GPU. Only grass near the player exists, so it's cheap, and it follows whatever you sculpt or paint instantly.

Files you will create:

```
res://shaders/common/meadow_palette.gdshaderinc   (Step 1, new)
res://shaders/terrain/meadow_terrain.gdshader      (Step 2, saved from Terrain3D, then edited)
res://shaders/foliage/meadow_particles.gdshader      (Step 3, copy of the example, 1 edit)
res://shaders/foliage/meadow_grass.gdshader          (Step 3, copy of the example, 3 edits)
res://shaders/foliage/meadow_flower.gdshader         (Step 4, new)
```

Never edit files inside `addons/`; copy them first, so updating Terrain3D doesn't wipe your work.

---

## Step 0: Terrain3D texture slots (the "paint layers")

Terrain3D paints **texture slots** with the B (paint) / V (spray) tools. We give the slots meaning:

| Slot | Name | Ground looks like | Grass? |
|---|---|---|---|
| 0 | Meadow | `meadow_color()` (the texture is ignored) | yes |
| 1 | Path | its texture | no |
| 2+ | Rock, sand, ... | its texture | no |

1. Select Terrain3D. In the bottom **Terrain3D** dock → Textures, make sure slot 0 has a texture (any; it gets recoloured). Add slot 1 "Path" and slot 2 "Rock" with textures from `assets/textures/ground/`. **All textures must be the same size and format.**
2. If you see a **checkerboard**, Terrain3D has no textures. Add one to slot 0.
3. If the Output says *"free_editor_textures requires Assets be saved to a file"*: Terrain3D → Assets → right-click → Save As `res://levels/meadow_hand/meadow_assets.tres`. Otherwise your textures can disappear when the game runs.

---

## Step 1: The shared palette

Create `res://shaders/common/meadow_palette.gdshaderinc`:

```glsl
// meadow_palette.gdshaderinc
// One place that decides "what colour is the meadow here?".
// The terrain and the grass both call meadow_color(), so they always match.

uniform float cloud_shadow_strength : hint_range(0.0, 1.0) = 0.28;
uniform vec2 cloud_shadow_wind = vec2(4.0, 1.5);

// --- Noise helpers ---------------------------------------------------------
float m_hash(vec2 p) {              // random 0..1 from a 2D position
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float m_noise(vec2 p) {             // smooth "value noise", 0..1
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(m_hash(i), m_hash(i + vec2(1.0, 0.0)), u.x),
			mix(m_hash(i + vec2(0.0, 1.0)), m_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float m_fbm(vec2 p) {               // 4 layers of noise = natural-looking blobs
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * m_noise(p);
		p = p * 2.03 + vec2(13.7, 7.1);
		a *= 0.5;
	}
	return v / 0.9375;
}

vec3 srgb(vec3 c) {                 // colour picker values -> linear (what ALBEDO wants)
	return pow(c, vec3(2.2));
}

// --- The look --------------------------------------------------------------
// Big soft patches of deep / mid / sunny green, by world position (x, z).
vec3 meadow_color(vec2 wp) {
	float big = m_fbm(wp * 0.012);          // ~80 m patches
	float mid = m_fbm(wp * 0.045 + 3.1);    // ~20 m variation inside them
	vec3 deep  = srgb(vec3(0.28, 0.56, 0.14));
	vec3 base  = srgb(vec3(0.47, 0.73, 0.20));
	vec3 sunny = srgb(vec3(0.68, 0.84, 0.30));
	vec3 c = mix(deep, base, smoothstep(0.30, 0.55, big + (mid - 0.5) * 0.25));
	return mix(c, sunny, smoothstep(0.55, 0.78, big + (mid - 0.5) * 0.35));
}

// Darkens the colour under big drifting cloud shadows.
vec3 apply_cloud_shadow(vec3 col, vec2 wp, float time) {
	float n = m_fbm((wp + time * cloud_shadow_wind) * 0.0045);
	float shadow = smoothstep(0.52, 0.68, n) * cloud_shadow_strength;
	return col * mix(vec3(1.0), vec3(0.45, 0.55, 0.72), shadow);
}

// Five pastel flower colours, picked by a 0..1 random number.
vec3 flower_palette(float r) {
	if (r < 0.30) return srgb(vec3(0.98, 0.58, 0.72)); // pink
	if (r < 0.50) return srgb(vec3(0.97, 0.96, 0.92)); // white
	if (r < 0.68) return srgb(vec3(0.68, 0.62, 0.98)); // lavender
	if (r < 0.84) return srgb(vec3(1.00, 0.86, 0.32)); // yellow
	return srgb(vec3(1.00, 0.48, 0.38));               // coral
}
```

**What to learn:** `fbm` (layered noise) is the workhorse of stylized terrain. Changing the three `srgb(...)` colours in `meadow_color` re-colours the whole world, ground and grass together.

---

## Step 2: The ground (Terrain3D shader override)

Terrain3D lets you replace its shader with your own copy. That's the official way to customise it. The rule from its own header comment: **don't touch `vertex()` or the normal maths; only change the final colour.**

1. Select Terrain3D → Inspector → **Material** → tick **Shader Override Enabled**. Terrain3D fills **Shader Override** with its default code.
2. Click the Shader Override resource → **Save As** → `res://shaders/terrain/meadow_terrain.gdshader`.
3. Open it and make **four edits**:

**Edit A:** line 2, softer lighting. Change `diffuse_burley` to `diffuse_lambert_wrap`:

```glsl
render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_lambert_wrap,specular_schlick_ggx,skip_vertex_transform;
```

**Edit B:** right after the line `#define DECODE_HOLE(control) ...`, add:

```glsl
#include "res://shaders/common/meadow_palette.gdshaderinc"
```

**Edit C:** directly above `void fragment() {`, add this function:

```glsl
// MEADOW: how much of texture slot `id` is painted at this pixel (0..1).
float slot_weight(int id, uvec4 control, vec4 corner_weights, bool bilerp) {
	float total = 0.0;
	for (int i = 0; i < 4; i++) {
		if (!bilerp && i != 3) continue;      // up close Terrain3D blends 4 corners, far away just 1
		float blend = DECODE_BLEND(control[i]); // how much the overlay texture covers the base
		float w = (DECODE_BASE(control[i]) == id ? 1.0 - blend : 0.0)
				+ (DECODE_OVER(control[i]) == id ? blend : 0.0);
		total += w * (bilerp ? corner_weights[i] : 1.0);
	}
	return clamp(total, 0.0, 1.0);
}
```

**Edit D:** near the end of `fragment()`, find the block that starts with `// Apply PBR` and ends just before `// Higher and/or facing up, less occluded.`. Replace that whole block (the `ALBEDO = ...` to `NORMAL_MAP_DEPTH = ...` lines) with:

```glsl
	// MEADOW: slot 0 is painted with meadow_color(); other slots (path, rock...) keep their texture.
	float meadow_w = slot_weight(0, control, weights, bilerp);
	bool has_tex = mat.total_weight > 0.0;
	vec3 textured = has_tex ? mat.albedo_height.rgb * macrov : vec3(0.5);
	vec3 tex_normal = has_tex ? fma(normalize(mat.normal_rough.xzy), vec3(0.5), vec3(0.5)) : vec3(0.5, 0.5, 1.0);

	vec3 col = mix(textured, meadow_color(v_vertex.xz), meadow_w);
	col *= color_map.rgb;                       // Paint Color tool (C) tints everything
	ALBEDO = apply_cloud_shadow(col, v_vertex.xz, TIME);
	ROUGHNESS = mix(roughness, 1.0, meadow_w);  // meadow is fully matte
	SPECULAR = mix(1. - mat.normal_rough.a, 0.0, meadow_w);
	NORMAL_MAP = mix(tex_normal, vec3(0.5, 0.5, 1.0), meadow_w); // flat normal = soft painted look
	NORMAL_MAP_DEPTH = mat.normal_map_depth;
```

Keep the AO lines after it as they are.

**What to learn:** Terrain3D stores *which texture is painted where* in a "control map" (one 32-bit number per vertex). `DECODE_BASE` / `DECODE_OVER` / `DECODE_BLEND` unpack it. `slot_weight` turns it into "how much Meadow is here", and the rest is a simple `mix`.

**Using it:** paint paths with B on slot 1. Press **C** (Paint Color) with a big soft brush and low strength to paint sunny patches or darker hollows by hand.

---

## Step 3: Grass only near the player (Terrain3D particle example)

1. In the FileSystem dock, copy `addons/terrain_3d/extras/particle_example/particles.gdshader` and `grass.gdshader` into `res://shaders/foliage/`. Rename them `meadow_particles.gdshader` and `meadow_grass.gdshader`.
2. Drag `addons/terrain_3d/extras/particle_example/Terrain3DParticles.tscn` onto your **Terrain3D** node, so it becomes a child. Rename it `Grass`.
3. On the `Grass` node, in the Inspector:
   - **Process Material** → right-click → **Make Unique**, then set its **Shader** to `meadow_particles.gdshader`.
   - **Mesh Material Override** → right-click → **Make Unique**, then set its **Shader** to `meadow_grass.gdshader`.

   ("Make Unique" makes the material yours, so the addon's file stays untouched.)

**Edit `meadow_particles.gdshader`:** the example *removes* grass on slot 0. We want the opposite. Find:

```glsl
	// Hardcoded example, hand painted texture id 0 is filtered out.
	if (!auto && ((base == 0 && blend < 0.7) || (over == 0 && blend >= 0.3))) {
		pos.y = 0. / 0.;
		pos.xz = vec2(100000.0);
	}
```

and replace it with:

```glsl
	// MEADOW: grass only grows where texture slot 0 ("Meadow") is painted.
	// Paths, rock, sand (slots 1+) stay bare. Dithering keeps the edge ragged.
	float meadow = (base == 0 ? 1.0 - blend : 0.0) + (over == 0 ? blend : 0.0);
	if (meadow < 0.5 + (r.y - 0.5) * condition_dither_range) {
		pos.y = 0. / 0.;
		pos.xz = vec2(100000.0);
	}
```

(`pos.y = 0./0.` makes a NaN position, the standard trick to "delete" a particle on the GPU.)

**Edit `meadow_grass.gdshader`** (3 small edits):

(a) Under `render_mode ...;`, add:

```glsl
#include "res://shaders/common/meadow_palette.gdshaderinc"
```

(b) Under `varying vec4 data;`, add:

```glsl
varying vec3 meadow_col; // MEADOW: ground colour under this blade
varying vec2 blade_xz;   // MEADOW: blade position, for cloud shadows
```

and in `vertex()`, just above `// World space vertex`, add:

```glsl
	// MEADOW: MODEL_MATRIX[3] is this blade's position on the terrain.
	blade_xz = MODEL_MATRIX[3].xz;
	meadow_col = meadow_color(blade_xz);
```

(c) In `fragment()`, replace the four "Hard coded color" lines:

```glsl
	// Hard coded color.
	ALBEDO = vec3(0.20, 0.22, 0.05) * (data[2] * 0.5 + 0.5);
	ALBEDO.rg *= (data.rg * 0.3 + 0.9);
	ALBEDO *= pow(COLOR.rgb, vec3(2.2));
```

with:

```glsl
	// MEADOW: same green as the ground, darker at the root, brighter at the tip.
	vec3 col = meadow_col * mix(0.75, 1.15, data[2]);
	col.rg *= (data.rg * 0.12 + 0.94);          // tiny per-blade variation
	col *= pow(COLOR.rgb, vec3(2.2));           // COLOR = Terrain3D colour map (C tool)
	ALBEDO = apply_cloud_shadow(col, blade_xz, TIME);
```

**Tuning (all in the Inspector):**

| Want | Change |
|---|---|
| Grass reaches further | `Grass` → Cell Width or Grid Width (draw distance ≈ cell_width × grid_width ÷ 2) |
| Denser / sparser | `Grass` → Instance Spacing (smaller = denser, more GPU) |
| Shorter / taller blades | Process Material → `min_scale` / `max_scale` (the Y value) |
| More / less wind | Process Material → `wind_strength`, `wind_speed` |
| No grass on cliffs | Process Material → `surface_slope_min` (higher = only flat ground) |

**What to learn:** the GDScript (`terrain_3D_particles.gd`) only moves a grid of `GPUParticles3D` nodes along with the camera and passes Terrain3D's map textures to the shader. All placement happens in `start()` of the particle shader. Read it top to bottom; it's well commented.

---

## Step 4: Flowers (a second particle layer)

Create `res://shaders/foliage/meadow_flower.gdshader`:

```glsl
// meadow_flower.gdshader: a round flower head on a camera-facing quad.
// Used as the mesh material of a second Terrain3DParticles node.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

#include "res://shaders/common/meadow_palette.gdshaderinc"

uniform float cluster_density : hint_range(0.0, 1.0) = 0.8; // inside clusters
uniform float lone_density : hint_range(0.0, 1.0) = 0.04;    // scattered everywhere else

varying vec3 petal_color;

void vertex() {
	vec2 pos = MODEL_MATRIX[3].xz;   // where this flower stands; also its random seed
	petal_color = flower_palette(m_hash(pos));

	// Clusters: big soft noise blobs decide where flowers bunch up.
	float cluster = smoothstep(0.52, 0.66, m_fbm(pos * 0.035 + 41.0));
	float chance = max(cluster * cluster_density, lone_density);
	bool keep = m_hash(pos + 8.8) < chance;

	// Billboard: keep the particle's position and size, but use the camera's rotation.
	// (This is the same thing Godot's built-in "Billboard" material mode does.)
	float size = keep ? length(MODEL_MATRIX[0].xyz) : 0.0; // size 0 = invisible
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0] * size,
			INV_VIEW_MATRIX[1] * size,
			INV_VIEW_MATRIX[2] * size,
			MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float r = length(UV - 0.5);          // distance from the centre of the quad
	if (r > 0.5) discard;                // cut the square into a circle
	vec3 col = mix(petal_color, petal_color * 0.75, smoothstep(0.15, 0.5, r));
	col = mix(srgb(vec3(1.0, 0.82, 0.3)), col, smoothstep(0.08, 0.14, r)); // yellow centre
	ALBEDO = col;
	EMISSION = col * 0.15;               // a little glow so they pop in shade
	ROUGHNESS = 1.0;
}
```

Then:

1. Drag another `Terrain3DParticles.tscn` onto Terrain3D and rename it `Flowers`.
2. **Mesh** → New **QuadMesh** (size 1 × 1).
3. **Mesh Material Override** → New **ShaderMaterial** → Shader: `meadow_flower.gdshader`.
4. **Process Material** → Make Unique → Shader: `meadow_particles.gdshader` (the same one as the grass). Then set:
   - `min_scale` = (0.10, 0.10, 0.10), `max_scale` = (0.16, 0.16, 0.16): flower head size
   - `position_offset` = (0, 3, 0): lifts the heads above the grass
   - `clod_scale_boost` = 0, `patch_min_threshold` = 0, `patch_max_threshold` = 0.01: so the shader, not the noise texture, decides clusters
5. On the `Flowers` node: Instance Spacing 0.5, Cell Width 16, Grid Width 5 (flowers out to about 40 m).

Because it reuses `meadow_particles.gdshader`, flowers also stay off paths automatically.

---

## Step 5: Water, clouds, props, sky

These already exist as standalone shaders in `res://shaders/` (`sky/`, `water/`, `terrain/`, `foliage/`). Read them as examples; no script needed.

- **Water:** add a MeshInstance3D → Mesh: PlaneMesh (covering the pond) at your water height → Material Override: new ShaderMaterial → `meadow/shaders/water.gdshader`. It uses the depth texture to fade shallow → deep colour and draw foam where the water meets the shore.
- **Clouds on the far hills:** add a MeshInstance3D → QuadMesh (Center Offset y = 0.5) → ShaderMaterial `meadow/shaders/cloud_bank.gdshader`. Scale it to about (200, 90, 1) and place it 300–700 m away. Duplicate it, and give each copy a different **seed** under *Geometry → Instance Shader Parameters*.
- **Trees, bushes, rocks:** drag `stylized_nature/imported_assets/*.gltf` under a `Props` node. They stay normal nodes, so you can add collision. For many at once, use ProtonScatter (`addons/proton_scatter`).
- **Sky / fog / sun:** already in `meadow_hand.tscn` (`WorldEnvironment` + `Sun`). Tweak `fog_density` and the sun angle by eye.

---

## Later: hook into the growth system

`terrain/growth_map/growth_map.gd` → `attach_terrain()` already sends a `growth_map` texture to the Terrain3D material. To make the ground turn from desert to meadow, add a `uniform sampler2D growth_map : hint_default_white;` to `meadow_terrain.gdshader` and blend `mix(desert_color, meadow_color, growth)`. The demo's `meadow/shaders/meadow_common.gdshaderinc` (`growth_at()`, `desert_color()`) shows how.

## Troubleshooting

| Symptom | Cause |
|---|---|
| Checkerboard ground | No texture in slot 0 (Step 0) |
| Painted path is black | Slot 1 has no texture assigned |
| Shader error mentioning `meadow_color` | The `#include` path is wrong, or Step 1's file is missing |
| No grass at all | `Grass` isn't a child of Terrain3D (or Terrain is unset), or everything is painted with slot 1+ |
| Grass on the path | You edited the addon's `particles.gdshader` instead of your copy, or forgot "Make Unique" |
| Grass stays at the world origin, never near the player; error *"Cannot find the active camera"* | The player camera is inside a SubViewport, so Terrain3D can't find it. Call `terrain.set_camera(player_camera)` in the level's `_ready()` |
| No grass anywhere, but no errors | The Process Material has no `main_noise` texture (then every blade gets scale 0). Start from the example's `process_material.tres` and Make Unique, not from a blank or unrelated material |
| Error *"Texture ID 1 albedo format ... doesn't match"* | All Terrain3D textures must share size and format: reimport them the same way (see Terrain3D's "Texture Prep" docs) |
