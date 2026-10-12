# Permanent industrial landmarks — three world stages

Three large environmental landmarks, each with Wasteland, Revival and Golden variants (nine GLBs and nine Godot scenes). Drag `.tscn` scenes into the map. Open `sample.tscn` to view the whole set at actual scale. Units: meters, Godot Y up. Detailed dimensions are in `manifest.json`.

| Landmark | Approximate size | Suggested placement |
|---|---|---|
| Ruined_Concrete_Tower | 22m tall, 10m footprint including stairs | Eastern skyline, western foothills; keep outside progression routes |
| Twin_Ruptured_Silos | 19m tall including exposed rods, 12m footprint | North waterworks or basin perimeter |
| Broken_Industrial_Viaduct | 24m wide, 12m tall | Background transport ruin, east or basin; leave navigation corridors underneath |

## Stage variants

- **Wasteland (index 0):** bare broken concrete, dusty industrial enamel, rusted reinforcement and severed cables.
- **Revival (index 1):** same ruin, sparse shrubs and short emerging vines.
- **Golden (index 2):** same ruin, longer vines, denser foliage and flowers. Warm golden-hour illumination comes from the existing WorldStages environment; it is not baked into the meshes.

Structure and origin stay fixed across each set. Collision covers only the permanent architecture, never foliage. Swapping stages should not change physical layout. The assets are not clearable; `category=Permanent` metadata is descriptive and does not add gameplay logic.

The supplied game uses `WorldStages.stage_changed(index, stage)` with indices 0–2. These are independent scene variants: replace the scene at the same parent transform when your code receives that signal, or select the desired version manually. No changes to your WorldStages scripts or level files were made. Later stage indices, if added, can keep the Golden variant.

The broken tower stairs, silo ladders, and viaduct gap are visual environment details, not validated traversal routes. Keep these landmarks off the critical path until player navigation is tested. Permanent structural collision is on layer 1.

## Files and production notes

GLBs have embedded material colors and no external textures. Each contains one joined Structure mesh plus a separate Growth mesh in the vegetated versions. This keeps scene node counts small. The illustration-style low-poly finish continues the previous wreckage pack, with no baked photorealistic textures.

The contact sheet normalizes each landmark's display size for comparison; the Godot sample retains meter scale. Blender source and generation script are retained in the working output folder. Godot 4.7.2 loading, collision checks, and sample runtime are validated separately; final map placement remains yours.
