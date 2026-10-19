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

## Starter equipment and meadow cleanup hand-in

First contact with the physical lake terminal grants `water_gun: 1` and
`jetpack_equipped: 1` immediately after the briefing, before opening the task
page. `jetpack_equipped` shows the backpack model but grants no flight. Until
`jetpack` reaches level 1, energy stays at zero and cannot regenerate. The HUD
explains that cleanup and a return to the central island are required.

Clearables (garbage included) can be cleared at any time, before the terminal too.
02 now has two sequential steps: clear 10 more `garbage` (Count Earlier off: only
piles cleared after 02 starts count), then physically return to
the lake station and report `meadow_cleanup_delivered`. Clearing alone leaves
02 active, keeps 03 locked, and does not enable flight. The station plays the
submission/power-restoration briefing before reporting the delivery event;
the existing 02 reward enables `jetpack: 1`. Tab only views the task page.

Existing saves that already completed 02 and earned flight retain both flight
and their subsequent quest progress. Existing terminal owners gain the starter
equipment flag and water gun when loading, without prematurely enabling flight.
The first quest's water-gun reward remains an idempotent fallback.

## Quest 05 — radar information

04 grants `radar_key: 1` through the companion bot dialogue. Existing saves
with 04 already done receive the missing key when the level's RadarStory starts.
The key is checked automatically and remains available after startup.

05 runs in order: `mountain_restoration >= 30`, `radar_started`,
`radar_coordinates`, then `radar_delivered`. The reward is
`chaos_energy_module: 1`. Reaching 30% only unlocks startup; it does not finish
the mission. Six radar-side litter props have the additional `radar_garbage` tag,
but no specific litter count is required. Mountain now covers the radar hill with a 90 m radius. meadow_level.gd aligns
its centre with the placed RadioObservatory on each load; adjust the radius in
restoration_regions.tscn if the authored hill footprint changes.

RadarStory attaches a RadarConsolePoint marker and interaction to the existing
Model/Auxiliary_Cabinet, so moving that model also moves its light/use zone.
Terrain height places the surrounding litter. GrowthMap percentage increments
are compared against saved counters to avoid counting the same recovery twice.
Pre-restored ground counts when 05 becomes available.

Readout and hand-in use the existing Dialogic layout. Bilingual text is in
i18n/strings.csv: RADAR_READOUT_* and RADAR_DELIVERY_*. The exact coordinates
are deliberately a placeholder. Interrupted reading can be resumed at the radar.
Only E at the lake terminal submits information; opening tasks with Tab does not.
All flags/key/module use the existing quest save data. No inventory is added.
Quest 06 follows hand-in; see the final-choice section below.


Old one-step 05 saves resume at the appended startup/readout/delivery steps.
QuestLog reconciles completed sequential quests whose saved step count is smaller
than their current resource, preserving existing completed steps and counters.

## Quest 06 — final choice

05 hand-in now briefs both routes and opens 06. Its two parallel steps are
alternatives (`complete_any = true`), not two mandatory goals. Only the selected
route is checked in the archive; the other is labelled unselected. Both routes
appear on the HUD and in the task terminal. The boat's intermediate collection
uses QuestStep.progress_event/target, displayed as harbor_parts 0/6, while its
completion event remains ending_boat. Earlier quests keep their existing rules.

FinaleStory is created by meadow_level.gd and uses the placed RadioObservatory
and IslandHarbor. The disruptor is only soft particles and an interaction sphere
parented to Model/Service_Platform (the second-floor deck). The boat point is
parented to Workboat_Hull_014/Visual/Workboat_Hull beside the existing hull.
Moving those models carries their lights and interaction spheres with them.

Ten harbor piles each offer one scrap part. Collection unlocks after 05. Six
parts suffice; the displayed ledger caps at six. Per-pile events harbor_pile_00
through harbor_pile_09 prevent repeated collection after loading. No inventory
or harbor recovery percentage is required. Pile positions are relative to the
harbor yard/apron and use terrain height if it rises above that surface.

Startup always uses ConfirmPopup with cancel selected by default. The boat
installs the module and starts in one confirmed action after collecting six
parts. Before confirmation, both choices remain open. Quests.complete_choice
consumes chaos_energy_module and commits exactly one branch synchronously.
ending_disruptor/ending_boat lock the other route, persist in normal quest save
data, and reopen the corresponding ending placeholder on subsequent loading.
The ending screen uses the existing bright UI theme. It pauses gameplay and
offers manual Save Progress and Return to Main Menu; it never saves automatically.
F9 cannot bypass the final world interaction and confirmation.

### Camera and later cinematic hooks

Select the meadow level root in Godot: optional `finale_disruptor_camera` and
`finale_boat_camera` accept Camera3D nodes. Leave both empty for current gameplay.
Use a camera in the player's viewport when using the existing pixel presentation.
FinaleStory emits `ending_selected(route, focus)` when presenting the chosen
ending. `get_ending_focus(route)` returns its world interaction anchor. Cinematics
can use those hooks; no authored camera motion or boat movement is added yet.
The ending placeholder pauses gameplay, so a future sequence should run with
PROCESS_MODE_ALWAYS or take over presentation before opening that screen.

### Key acquisition and old-save compatibility

04 has an explicit bot-key dialogue step between core activation and delivery.
The key is granted by the call events after the bot's key line in
dialogue/timelines/Factory/core_activated.dtl, not by quest 04 equipment rewards.
The bot has a recovery conversation until robot_key_received is recorded, so
an interrupted dialogue can be resumed. Its trigger follows the bot from the
main viewport to keep its CanvasLayer independent of the pixel SubViewport.
Completed legacy saves keep their already-earned key and are reconciled with
the appended quest steps. No password entry is needed and radar startup retains
the key. Core hand-in requires that key to have been obtained.

New strings, prompts, briefings and ending placeholders are bilingual in
i18n/strings.csv (FINALE_*, ENDING_*, QUEST_FINALE_* and ROBOT_KEY_RECOVERY).
The exact radar coordinates and final story text remain placeholders.


The mountain_region_radar_hill_v2 counter migrates the changed measurement area
once. An unfinished recovery step is recalculated from the actual new region;
startup already earned and completed missions are preserved. No growth-map pixels
or player save files are erased by this change. The quest threshold stays 30%.

## Optional radar cleanup

05 now displays its existing six radar-side clearables as an optional 0/6 goal
on the task page and HUD. Quest.optional_steps is a separate display-only list
of lifetime event counters; it never changes required-step indices, completion
requirements, or old save states. Unfinished optional goals appear on the HUD
while the quest is active, and remain visible on its archived task page.
Each newly cleared pile also records radar_litter_00..05 so it is not respawned
after loading. Existing radar_garbage totals are retained; displayed progress
is capped at six. Startup and hand-in still require only the authored 30%
recovery / key / radar information stages. Cleanup is not an additional gate.

Jetpack per-level energy is now [100, 200, 240]; only level 2 changed.

## Quest 00 — startup checks and cabin investigation

New saves have `startup_checks: {step: -1, confirmed: false}`. `levels/meadow_hand/startup_checks.gd` waits for the opening fade to finish, then runs perception, walking, jumping and sprinting checks in order. It samples actual camera/player feedback; pauses, dialogue and transitions suspend checks and the 2.5-second feedback hold. Sprinting accumulates 0.8 seconds of actual movement while sprint is held; a brief floor-contact loss or collision pauses progress rather than clearing it. Holding sprint while stationary cannot complete it. Only completed checks are persisted; partial motion is sampled afresh after loading.

Presentation lives in `ui/in_game/startup/startup_hint.tscn` and its script: one non-modal upper-right card for both self-checks and the pre-terminal objective. Each new prompt slides down from above the screen while fading in, and slides up while fading out after at most 10 seconds. Expiry only hides the card; checks continue. Completed checks still advance after their 2.5-second feedback hold. The pause overview reviews the current card without consuming its timeout; settings/save submenus hide it. Obtaining the terminal retires this entire card. Wording is in `i18n/strings.csv` (`STARTUP_*`, `QUEST_CABIN_*`); key labels follow SettingsManager bindings and language changes.

`00_investigate_cabin.tres` contains two parallel reading steps (`cabin_delivery_read`, `cabin_crew_read`), followed by `pump_started`. Both tablets must be read to the last confirmation; cancelling, opening only, or repeating a completed tablet does not add credit. The shared upper-right card keeps the single cabin objective during reading and switches to `QUEST_CABIN_PUMP` once both are read. All existing 10-second, pause-review and terminal-retirement rules apply.

`levels/meadow_hand/cabin_story.gd` gates the pump interaction until both records are read. WaterFlowSwitch reports completion after the existing flow/rise animation, ending 00 and starting 01 at the lake station activation step. A non-blocking “第一幕 / Act I” card fades in and out once; edit its timing/presentation in `ui/in_game/story/act_title.*`. `act_one_started` is available for later camera/animation work.

The level runs CabinStory.migrate_save before loading quests: old 01 indices shift past the removed pump step, prior progress/equipment are retained, and older saves without startup checks retain access to the pump. Completed pumps restore flowing water before child nodes become ready. `cabin_story_version` prevents repeat migration; `act_one_entered` prevents replaying the chapter card. These flags and reading event counters use normal SaveManager persistence; no extra save files are created. F6 without a fresh-save marker follows the legacy compatibility path. New games retain the opening and self-check sequence.
