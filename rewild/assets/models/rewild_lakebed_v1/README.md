# Toxic lakebed kit

Eight placeable models: three matching polluted/cleared pairs (cracked flat, buried drums, stranded machine chassis), plus a hazard sign and waterline gauge. Intended for the confirmed toxic-mud barrier in game_flow.md.

Open `sample.tscn` to compare the set. Ground patches are approximately 6m across with irregular edges. Place slightly above the existing terrain to avoid z-fighting; overlap or rotate them to break repetition. Match the gauge's high-water band to your actual lake level. The preview normalizes object sizes; props are exported at meter scale.

Polluted patches have dark clay plates, oil residue and embedded debris. Cleared variants preserve the ground-patch placement and replace contamination/debris with bare mineral-stained clay. Cleared states are optional art variants, not required by the story's lake-filling event. Flooding should normally submerge the polluted bed using the existing water system, not automatically remove all debris.

Ground scenes use a simple flat box collider instead of detailed debris collision so the tiny props do not form unintended stepping stones toward the island. The actual toxic-mud detection, player pushback, swim/water volumes and task gating are NOT implemented. `hazard_visual` is only descriptive metadata. Add the proper hazard Area3D/controller using the game's actual lake boundaries. Keep warning signs above high water.

When a terrain collider already exists, disable/remove FlatGroundCollision to avoid duplicate ground surfaces. The simplified collider does not follow the irregular outer edge of the mesh. This kit is a visual environment pack rather than a complete walkability or hazard system. No gameplay scenes were modified.

Models use embedded material colors without external textures. Godot Y up, meters, collision layer 1. Independent polluted/cleared scenes, no automatic stage switching or save integration.
