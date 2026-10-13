# Small clearable litter

14 assets: aluminum can, crushed can, three plastic bottles, takeaway cup, drink carton, food tray, crumpled bag, snack wrapper, wire offcut and three mixed piles.

Drag individual .tscn files into the map. sample.tscn shows actual meter scale; the rendered contact sheet enlarges the individual items to compare shapes. Cans are about 0.32m tall, bottles about 0.5m, and clusters about 1.2m across. Slightly oversized silhouettes suit the game's distant camera.

Each scene is tagged with category=Clearable, tags=[small_garbage], hold_time=0.8 as metadata. ClearTarget is an Area3D with a generous sphere for interaction detection. Its collision layer/mask are zero by default because the game's interaction layers were not changed: set them to your existing interaction layer before ray/overlap detection. There are no rigid or static bodies to snag the player on tiny rubbish.

Metadata and the target shape do not implement hold-to-clear, persistence, task counting or bloom. Connect these roots to your existing clearing system. Each mixed pile is a single target. To clear individual pieces, place the separate models instead. No scripts or playable level files were changed.

No textures or external resources required. GLBs contain embedded materials. Godot Y up. Origin is near the base of each asset; use small terrain offsets where required. Worn neutral colors, faded labels and simplified geometry match the previous environmental packs. Labels have no real brands.
