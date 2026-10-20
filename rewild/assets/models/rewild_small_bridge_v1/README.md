# Small bridge — barren / greened

Two placeable 3D Godot scenes, each with an embedded-material GLB.

- Span: 6 metres along local X; deck width: 2.2 metres; clear rail width about 2 metres.
- Origin: centre of deck surface. Match origin Y to bank walking height. Abutments extend 1.1 metres below the deck; handrails reach about 1.15 metres above it.
- Same structure and five identical box colliders in both stages: smooth deck, two rail barriers, two abutments. Vegetation has no collision.
- Barren: worn concrete, chipped ivory rails, rusted girders and sagging conduit.
- Greened: same weathered bridge with moss, trailing vines and small flowers. The centre stays walkable.

Drag either `.tscn` into the game. `sample.tscn` shows both versions. The map has not been changed. For stage changes, replace the instance, or keep one collision body and swap only the Visual child; hiding a complete scene does not disable its collision. Stage wiring is not included.

`preview.png` is the rendered comparison. One Godot unit equals one metre.
