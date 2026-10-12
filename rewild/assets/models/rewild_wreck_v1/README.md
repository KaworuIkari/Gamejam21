# Rewild wreckage v1

Seven original stylized 3D wreckage assets: broken concrete and exposed reinforcement, rusted steel, dusty yellow sheet metal, and hanging wires. Intended to evoke the abandoned industrial atmosphere requested, using low-poly geometry and material colors rather than baked surface textures.

Drag the `.tscn` files into the map. Each includes static collision, an editable GLB visual, and descriptive zone/category metadata. Metadata does not implement clearing, saves, or task progress. Connect these scenes to your existing Clearable system. Collision uses layer 1 and includes thin wires; adjust or simplify it if those snag the player.

| Asset | Suggested use |
|---|---|
| Wall_Jagged_Rebar | Basin rubbish wall, eastern ruined construction; 4.4m base |
| Slab_Snapped_Rebar | Collapsed floor debris in east or summit; protruding bent mesh |
| Column_Burst_Rebar | Ruined concrete supports with exposed reinforcement cages |
| Frame_Twisted_Cables | Broken industrial frame and dangling electrical cables |
| Garbage_Mixed_Scrap | General clearable rubbish: bent sheets, wheel rims, rods and rubble |
| Tank_Ripped_Open | North water-source obstruction or basin industrial scrap |
| Fence_Sagging_Wire | Garbage-wall filler or eastern enclosure remains |

Open `sample.tscn` to inspect all models at actual scale. The rendered contact sheet normalizes display size for readability. Godot Y is up; units are meters. GLBs contain geometry and materials with no external texture dependencies. Use `manifest.json` for dimensions.

No objects were automatically placed in your map. These are static wrecks, not fracture simulations or animated destruction. Intended placements follow the supplied game flow; gameplay behavior remains separate.
