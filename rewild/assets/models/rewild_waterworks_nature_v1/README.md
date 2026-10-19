# Woodland pump house and wooden bridge

Two new placeable props matching the approved nature style. Original bark/rock textures and fern/clover/flower meshes come from the existing stylized_nature pack.

Use Woodland_Pump_House_Restorable.tscn or Woodland_Wooden_Bridge_Restorable.tscn. Each combines a fixed barren structure with collision and a separate, collision-free Greenery overlay. Individual plant clusters grow using the existing GrowthMap: threshold 0.6, animation 0.8 seconds, stagger up to 1.2 seconds. The bases never grow or swap.

Open sample.tscn in the editor to compare. Toggle Preview Green on each Greenery child to see the bare structures. barren.png and greened.png show both states.

The bridge runs along local X, roughly 6.8 metres long and 2.5 metres wide including stone supports. The pump house has an open entrance, side inspection window, partial roof damage, and decorative pump, valve and outlet. Pump machinery is visual: existing water-flow quest logic is not added or replaced. These are new assets; existing levels and pump house/bridge scenes are unchanged.
