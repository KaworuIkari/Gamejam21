# Wooden bridge with optional greenery

One barren wooden base plus a separate vegetation-only overlay. No duplicate greened bridge model.

1. Place `Wooden_Bridge_Barren.tscn` at the bank's walking height.
2. Add `Wooden_Bridge_Greenery.tscn` as a child of that bridge, with position and rotation zero and scale one.
3. Toggle the Greenery node's visibility to change the appearance. All collision stays on the base.

The overlay contains moss, vines, leaves and flowers with their own materials. It is additional geometry, not a material override, and has no collision. Both exports use the exact same coordinate space.

Span 6 m along X; deck width 2.2 m; origin at centre of walking surface; supports extend 1.1 m below deck. Railings about 1.1 m tall. One unit = one metre. Seven box collision shapes on the base provide a smooth deck, rail barriers and pier collision.

Open `sample.tscn` to compare the barren base and the same base with greenery attached. Automatic world-stage wiring and map placement are not included.
