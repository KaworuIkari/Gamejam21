# Modular water channels

Four layouts × three versions = twelve assets: Straight, Bend, Junction, Spillway; each Dry, Flowing and Reclaimed. Concrete shell and collision remain identical across each set. Reclaimed adds growth; water and growth have no collision.

Each constituent floor tile is 2m square. Straight modules are 6m long. In Godot local X/Z coordinates, straight ports are (0,+3) and (0,-3); bend ports (0,+3) and (+3,0); junction ports (0,+3), (0,-3), (+3,0). Rotate modules in 90-degree steps and align these port centers. Floor top is Y=0.24, water top approximately Y=0.4475. Banks narrow the interior near edges.

Spillway runs from local Z=+3 (high) to Z=-3 (low), dropping 0.7m in two 0.35m steps. Offset connecting modules vertically to match its floor ends. The water animation defaults toward local -Z and can be adjusted with `flow_direction` and `flow_speed` on the scene root.

Use the `.tscn` files to get the time-animated ripple shader. The GLB alone contains static colored water geometry. Ripple motion is a visual cue, not hydraulic simulation; the bend/junction does not calculate a branching velocity field. These shallow channels do not add WaterVolume, swimming, refill triggers or water-release task logic. Connect those to your existing systems. Dry/Flowing states should follow each route's unlock event rather than only the global world stage.

Open `sample.tscn` to preview the twelve variants. No external texture dependencies. The shader/script references remain inside this folder. Scene geometry is meters, Y up; structural collision layer 1.
