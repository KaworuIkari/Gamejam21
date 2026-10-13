# Rewild flow asset pack v1

Nine placeable Godot 4.7 scenes, backed by editable GLB meshes. Designed against `docs/story/game_flow.md` and the supplied map/reference art: warm limestone, cream enamel, oxidized iron and cyan equipment lights. These are stylized low-poly additions; they do not reproduce the existing packs' texture detail.

## Use

Drag a `.tscn` into your level. Open `sample.tscn` and run the current scene to inspect the set. All paths live under `res://assets/models/rewild_flow_v1/`. The pack has no plugin or autoload dependencies. Units are meters; Godot Y is up. Static environment scenes include concave collision on layer 1. Pickups deliberately have no collision, triggers or pickup code, so they can also be used as character attachments.

| Scene | Map placement | Notes |
|---|---|---|
| Lake_Island_Dock | Center lake | Origin at dry lakebed, dock at Y=4m. Use waterline around Y=3.7m. Empty mounting pad for your existing terminal. Ladder stops above dry bed. This uses the document's proposed raised-island option, independently of task implementation. |
| Sluice_Gate_Closed / Open | East and west lake outlets | 2.7m wide channel. Swap the entire scene at the same transform, including collision, when the terminal opens it. These are static state variants, not animations. |
| Spring_Intake | North spring | Permanent intake grille and service indicator. Place existing removable rubble/pipes in front of it for the clearing task. |
| Rescue_Enclosure_Closed / Open | Spring, east oasis, mountain summit | Empty 1.8m enclosure. Add an animal separately. Swap the complete scene on rescue or remove it as a clearable object. |
| Jetpack_Pickup | Eastern oasis | Approx. 0.8m high. Origin below the tanks, not at a character bone; adjust attachment offset. Add your existing pickup/flight behavior. |
| Water_Tool_Pickup | Lake terminal | Points along local -Z. Add pickup, water stream and watering behavior separately. |
| Peak_Landing_Platform | Western ascent | 3.6m landing slab. Set vertical spacing from your jetpack's tested range. |

The `zone`, `category`, and `description` root metadata are descriptive only. They do not implement WorldObject, Clearable, Recoverable, saves, tasks or growth effects. Gate/door changes, animal rescue, swimming and ability unlocking remain responsibilities of the game's systems.

## Placement guidance

Preserve the supplied map: spring north → lake center → east oasis; peak to the west; starting basin southwest. The new gate can be rotated to follow each channel. The raised island must sit inside water deep enough that a player cannot simply walk onto the dock. Confirm this with the actual player's jump height and swim controller. Existing terrain scale was not changed, and nothing was automatically placed in `meadow_hand.tscn`.

`manifest.json` records each model's dimensions in X/Y/Z order. Preview renders enlarge the small pickups for visibility; they are exported at their actual meter scale.

## Validation

Models exported with Blender 5.2.2 and imported with Godot 4.7.2. The standalone sample loads and runs headlessly. Rendered GLB preview checked visually. Placement, player collision behavior and task integration still require an in-game pass.
