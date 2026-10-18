# Nature style choices

Three placeable 3D samples for choosing a visual direction:

- **A — Woodland log:** hollow, irregular broken rim, branching roots, painted nature-pack bark.
- **B — Woodland ruin:** asymmetrical wall assembled from the nature pack's UV-mapped stones, with fallen rubble.
- **C — Salvaged bench:** uneven timber boards, painted bark, natural stone supports and small rusted iron straps.

All use the original nature pack's stone, bark, fern, clover and flower materials. Each has a separate `_Barren.tscn` base with collision, a collision-free `_Greenery.tscn`, and a ready-to-place `_Restorable.tscn` with both combined. The stone texture retains its original subtle lichen colouring; additional growing plants are separate.

Place `_Restorable.tscn` to follow the existing GrowthMap watering system. Threshold 0.6, grow time 0.8 seconds, stagger up to 1.2 seconds. Each patch grows from its own surface anchor. No materials or scenes in the previous packs were replaced.

Open `sample.tscn` to compare all three in Godot. `A.png`, `B.png`, `C.png` show each at full growth. The 3D models use actual UV-mapped material textures, not render-only procedural effects.
