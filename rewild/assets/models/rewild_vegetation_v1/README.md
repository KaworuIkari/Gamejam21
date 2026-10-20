# Recoverable vegetation clusters

Five cluster types × three watering states = fifteen placeable models:

- Shrub_Cluster — low woody shrubs, fresh leaves and meadow flowers.
- Skeletal_Tree — approximately 4m branching tree; bare branches → buds → leafy crown.
- Reed_Bed — dry reeds → short green shoots → mature reeds and seed heads.
- Fern_Cluster — collapsed dry fronds → young fronds → full spreading fern group.
- Cracked_Planter — permanent broken concrete planter with recoverable shrubs.

Every type has Withered, Sprouting, Flourishing scenes. These are LOCAL watering states, not automatic global WorldStages changes. A patch should recover when the player waters it (or when your intended bloom event reaches it), rather than all patches switching merely because the world stage advances.

Open sample.tscn for the set at meter scale. Drag individual .tscn files into the world. Each scene has category=Recoverable and method=WATER metadata; this is descriptive only. Attach the existing interaction/detection, growth timing and saved state in your gameplay code. No water consumption, timers, automatic stage swapping or saves are implemented here.

Match the game's wetness-driven growth: water gives wet-ground feedback first, then switch to Sprouting, then Flourishing as growth completes. If flowers must appear only after drying, separate the flower geometry in Blender or reveal the flourishing state after that delay. Current flowers are part of the final Growth mesh and not independently timed.

Suggested placement: lake tutorial shrubs and reeds; eastern oasis shrubs, trees and planters; summit trees and ferns. Origins remain fixed across each type. Plant geometry is deliberately non-colliding, including trees, so bushes do not obstruct navigation. Only the concrete planter Support has static collision, unchanged across states. Add a trunk collider if the tree must block the player.

Embedded materials, no external textures, Godot Y up. Keep sparse instances first and test density/performance in your real map. The rendered contact sheet normalizes each model to compare shapes, so the tree and small shrubs appear similar in preview size; exported models retain meter scale. The models are discrete state variants, not morphing animations.
