# Woodland Well

Place Woodland_Well_Restorable.tscn for a complete well with watering-driven greenery. Woodland_Well_Barren.tscn is the fixed stone/timber structure with collision; Woodland_Well_Greenery.tscn is the separate collision-free plant overlay. No duplicate base is needed for the greened state.

Uses the approved nature-pack rock, bark, fern, clover and flower style. Stone retains subtle lichen baked into its original texture. The opening, crank, rope and bucket are decorative; no water collection or quest logic is added.

Growth follows the existing GrowthMap, with a 0.6 threshold, 0.8-second growth animation and up to 1.2 seconds of stagger. Each cluster grows from its own surface anchor. The base remains unchanged. Preview Green toggles plants in the editor; runtime watering controls them in game.

Open sample.tscn to preview in Godot. barren.png and greened.png show both states. Existing well assets and level scenes are unchanged.
