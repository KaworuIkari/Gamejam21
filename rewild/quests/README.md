# Quests

Every `.tres` file in this folder is a quest. Files run in name order, so prefix them
`01_`, `02_`, ... The terminal (Tab, or E at the lake station) and the tracker in the
top-left corner show them automatically.

## Add a quest

1. FileSystem → right-click this folder → **Create New → Resource… → Quest**, name it e.g. `04_save_animals.tres`.
   (Or duplicate an existing quest file and edit it.)
2. Double-click it and fill in the Inspector:
   - **Title / Description / Location**: plain text, or a key from `i18n/strings.csv`.
   - **Requires**: drag in the quest files that must be finished first (empty = starts right away).
   - **Steps**: Add Element → New QuestStep. Each step has
     - **Text**: what the player sees,
     - **Event**: the event name it waits for (table below),
     - **Count**: how many times,
     - **Count Earlier**: on = everything since the game started counts (use this for one-off
       events like the pump); off = only what happens after the step starts ("clear 10 *more*").
   - **Rewards**: ability → level, e.g. `water_gun: 2`, `jetpack: 1`.

Steps are done one after another. A quest is done when its last step is. A step with
**With Previous** ticked opens together with the step before it (do both in any order).
Tick **Parallel** on the quest to open all steps at once, in any order; it is done when every step is.

## Events

World objects report events by name. A step's **Event** must match exactly.

| Who reports it | Event name | Where to set it |
|---|---|---|
| Clearable (garbage, rubble, cages…) | each of its **Tags**, e.g. `garbage`, `animal_rescue` | Clearable → Tags |
| Ready-made garbage (`objects/clearable/`) | `garbage` | already set |
| Restorable reaching its last look | its **Quest Event** | Restorable → Quest Event |
| Ready-made trees (`objects/restorable/restorable_tree_*`) | `tree_restored` | already set |
| WaterFlowSwitch (pump) when the water has arrived | its **Quest Event**, e.g. `pump_started` | WaterFlowSwitch → Quest Event |
| Lake power station activated | `station_activated` | Station → Quest Events |
| Lake station terminal closed | `station_terminal` | Station → Quest Events |
| InteractTrigger used | its **Quest Event** | InteractTrigger → Quest Event |
| GrowthZone fully revived | its **Quest Event** | GrowthZone → Quest Event |
| QuestArea (player walks in) | its **Event** | Add Node → QuestArea |

Anything else can report with one line of code:
`get_node("/root/Quests").report(&"my_event")`.
In debug builds the Output panel prints every event as `[Quests] garbage (3)`, so you can
check the names.

## Abilities

Rewards raise abilities: `water_gun` and `jetpack`. Their effect per level is set on
**LIRA → Abilities** (splash radius, fire cooldown, jetpack energy). **Start Water Gun
Level / Start Jetpack Level** there are the levels LIRA has before any quest (0 = locked).

A Clearable with **Required Ability** set (e.g. `jetpack`) can only be cleared once that
ability is unlocked.

## Testing

Debug builds: **F9** completes the current step of the tracked quest.
