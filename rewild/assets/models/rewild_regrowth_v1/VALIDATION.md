# Validation

- All 20 base scenes, 20 separate overlay scenes, and 20 combined Restorable scenes loaded and instantiated in Godot 4.7.2.
- Base collision exists once; greenery contains no collision; combined scenes contain no duplicate base geometry.
- Patch counts match the exported meshes, with identity transforms on attached overlays.
- Real project GrowthMap test passed: barren initial state, delayed growth after water, threshold crossing, existing tree restoring alongside new foliage, animated plant scale, fixed base scale, distant dry prop remaining barren, instant restoration when loaded on green ground, reset hiding growth, and local rather than whole-landmark growth.
- Inherited meadow scene resolves all three overlays under the correct landmark parents.
- Rendered the actual watering demo in Godot and inspected barren and grown frames. The bundled MP4 records that run; it applies water through GrowthMap directly rather than simulating player inputs.
- Visually reviewed prop sheets and landmark overlays. Entrance ramps and floor meshes are excluded from landmark surface sampling.

Existing project shutdown logs include resource/ObjectDB leak warnings, also seen before this pack. No parse errors or script runtime errors were observed in the successful growth and demo checks.

The vegetation uses world XZ ground growth, as existing trees do. It does not independently simulate moisture spreading up vertical walls. The landmark overlays are now attached directly in meadow_hand.tscn.
