# Nature style choices

Three placeable 3D samples for choosing a visual direction:

- **A — Woodland log:** hollow, irregular broken rim, branching roots, painted nature-pack bark.
- **B — Woodland ruin:** asymmetrical wall assembled from the nature pack's UV-mapped stones, with fallen rubble.
- **C — Salvaged bench:** uneven timber boards, painted bark, natural stone supports and small rusted iron straps.

All use the original nature pack's stone, bark, fern, clover and flower materials. Each has a separate `_Barren.tscn` base with collision, a collision-free `_Greenery.tscn`, and a ready-to-place `_Restorable.tscn` with both combined. The stone texture retains its original subtle lichen colouring; additional growing plants are separate.

Place `_Restorable.tscn` to follow the existing GrowthMap watering system. Threshold 0.6, grow time 0.8 seconds, stagger up to 1.2 seconds. Each patch grows from its own surface anchor. No materials or scenes in the previous packs were replaced.

Open `sample.tscn` to compare all three in Godot. `A.png`, `B.png`, `C.png` show each at full growth. The 3D models use actual UV-mapped material textures, not render-only procedural effects.

## Simple collision maintenance

The woodland log's `_Barren.tscn` and `_Restorable.tscn` use a single horizontal CapsuleShape3D at `Collision/TrunkShape` (radius 0.58 m, length 3.5 m). Its transform and shape are authored in the scenes; the greenery remains collision-free. No runtime collider generation is used.

The placed trail bike uses the existing `stylised_bike/bike.tscn` wrapper with three BoxShape3Ds under `Body` (frame, handlebar, saddle). The main level retains the original placement and its existing ObjectText reading interaction; the obsolete missing TextInteraction dependency in the wrapper is not used. Adjust collision dimensions in that scene rather than the imported GLB or a script.

The factory's rubble-fronted Site4 has two BoxShape3D guards in `assets/models/desert_robotics_laboratory/laboratory.tscn`, under `Site4WindowCollision/LeftWindowWall` and `RightWindowWall`. They stop passage through the front window walls without adding mesh collision. The central doorway remains outside these boxes; Site2's window used to fetch the jetpack and the FactoryStory script are unchanged. Adjust these scene shapes in the editor; do not generate them at runtime.
