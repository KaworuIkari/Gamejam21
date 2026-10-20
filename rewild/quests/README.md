# Quests

Every `.tres` file in this folder is a quest. Files run in name order, so prefix them
`01_`, `02_`, ... Quests are now internal bookkeeping (events, rewards, saves): the
terminal no longer lists them and there is no quest tracker or quest toast. The
terminal shows the battery charge and the equipment upgrades instead (see below).

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

## Main flow after the terminal

The terminal (Tab, or E at the lake station) has two columns
(`ui/in_game/tasks/task_page.*`):

- **Core battery**: charges with the average recovery of the four measured regions
  (lake, forest, mountain, factory; `levels/meadow_hand/restoration_regions.tscn`).
  `levels/meadow_hand/battery_charge.gd` computes it. At 100% the HUD says so once and
  the terminal says to return; interacting with the lake station then hands over the
  battery (`battery_collected`, ability `battery`) for the boat ending. Opening the
  terminal with Tab does not.
  The HUD in the top-left shows the same charge and each region.
- **Equipment upgrades**: every cleared Clearable tagged `garbage` is one material.
  Spending is recorded as `garbage_spent`, so material = garbage − spent. Two tracks,
  fire rate (`water_gun_rate`) and tank capacity (`water_tank`), 3 upgrades each at
  5 material (`systems/upgrades/water_gun_upgrades.gd`: COST, MAX_LEVEL). Their
  values are LIRA → Abilities → Water Gun Cooldown / Water Tank Capacity (first
  entry = no upgrade). Splash radius still follows `water_gun` level.

First contact with the physical lake terminal grants `water_gun: 1` and
`jetpack_equipped: 1` (backpack visible, no flight). Flight (`jetpack: 1`) comes from
repairing the factory bot (quest 04). Robot and radar have no prerequisites.

Removed dialogues and notices (station hand-ins, quest toasts, the bot's wake-up
dialogue, radar key lines) are listed with their text keys in
`dialogue/backup/README_备份.md`.

## Quest 04 — gears and the sleeping bot

No prerequisites. Steps: collect 6 `factory_gear`, then `core_activated`; reward
`jetpack: 1`.

The companion bot stands idle in the factory from the start (where
`CubeBotCompanion` is placed in meadow_hand.tscn): not moving, eye dark with no
glow or light (`CubeBot.eye_on = false`).

Gears (`objects/pickups/gear/gear_pickup.tscn`) are in the world from the start
and are picked up with the interact key. Each reports `factory_gear` plus its own
saved event, so collected gears stay with LIRA across saves and are not respawned.

Placing gears by hand: drag `gear_pickup.tscn` into meadow_hand.tscn (e.g. under
`Enviroment/East_Robot_factory`) and move it with the gizmo; the origin is the
gear's centre. Every GearPickup in the level is used and saved by its node path
(`factory_gear_<snake_case path>`), so don't rename or re-parent them once
players have saves. With none placed, FactoryStory falls back to its
`GEAR_SPOTS` list. 6 are needed (`count` of the gear step in
04_energy_core.tres and `GEARS_NEEDED` in factory_story.gd): change both together.
Gear highlight: the SoftSparkles node.

Near the sleeping bot a greyed prompt shows the gear count (`ROBOT_REPAIR_GEARS`).
With every gear the bot glimmers and can be repaired: it shakes, its eye lights
yellow and fades to blue, `core_activated` is reported (04 completes, jetpack
enabled) and the bot follows LIRA. Timings are in `FactoryStory._repair`.

## Quest 05 — radar coordinates

No prerequisites (no key, no mountain recovery). Steps: `radar_started`, then
`radar_coordinates` (read the readout at the radar's auxiliary cabinet to the
end); reward `chaos_energy_module: 1`, which the current finale still uses. The
readout text is `RADAR_READOUT_COORDINATES`. Six litter piles around the radar are
ordinary garbage (they also record radar_litter_00..05 so they don't respawn).

## Quest 06 — final choice

06 opens once 05 is done (the station's briefing dialogue was removed). Its two parallel steps are
alternatives (`complete_any = true`), not two mandatory goals. Only the selected
route is checked in the archive; the other is labelled unselected. The boat route
loads the radar coordinates and installs the battery (`boat_battery_installed`,
the step's progress event) before `ending_boat`.

FinaleStory is created by meadow_level.gd and uses the placed RadioObservatory
and IslandHarbor. The disruptor is only soft particles and an interaction sphere
parented to Model/Service_Platform (the second-floor deck). The boat point is
parented to Workboat_Hull_014/Visual/Workboat_Hull beside the existing hull.
Moving those models carries their lights and interaction spheres with them.

Startup always uses ConfirmPopup with cancel selected by default. The boat
departs in one confirmed action once the coordinates and battery are loaded.
Before confirmation, both choices remain open. Quests.complete_choice
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

## Quest 00 — startup checks and cabin investigation

New saves have `startup_checks: {step: -1, confirmed: false}`. `levels/meadow_hand/startup_checks.gd` waits for the opening fade to finish, then runs perception, walking, jumping and sprinting checks in order. It samples actual camera/player feedback; pauses, dialogue and transitions suspend checks and the 2.5-second feedback hold. Sprinting accumulates 0.8 seconds of actual movement while sprint is held; a brief floor-contact loss or collision pauses progress rather than clearing it. Holding sprint while stationary cannot complete it. Only completed checks are persisted; partial motion is sampled afresh after loading.

Presentation lives in `ui/in_game/startup/startup_hint.tscn` and its script: one non-modal upper-right card for both self-checks and the pre-terminal objective. Each new prompt slides down from above the screen while fading in, and slides up while fading out after at most 10 seconds. Expiry only hides the card; checks continue. Completed checks still advance after their 2.5-second feedback hold. The pause overview reviews the current card without consuming its timeout; settings/save submenus hide it. Obtaining the terminal retires the pre-terminal objective. The same card is reused for water-gun and jetpack checks; their progress is stored in equipment_checks (1 = confirmed, 2 = complete). See ui/CustomUi/README_对话UI.md for the equipment checks and bindings. Wording is in `i18n/strings.csv` (`STARTUP_*`, `QUEST_CABIN_*`); key labels follow SettingsManager bindings and language changes.

`00_investigate_cabin.tres` has one required step, `pump_started`. The two cabin tablets are optional reading (`optional_steps`: `cabin_delivery_read`, `cabin_crew_read`, counted only at the final confirmation); the pump works without them. The shared upper-right card shows the pump objective. Saves from the required-reading version are rebuilt by CabinStory.migrate_save (version 3). Existing 10-second, pause-review and terminal-retirement rules apply.

WaterFlowSwitch reports completion after the existing flow/rise animation, ending 00 and starting 01 at the lake station activation step. (The “第一幕 / Act I” card was removed.)

The level runs CabinStory.migrate_save before loading quests: old 01 indices shift past the removed pump step, prior progress/equipment are retained, and older saves without startup checks retain access to the pump. Completed pumps restore flowing water before child nodes become ready. `cabin_story_version` prevents repeat migration; `act_one_entered` prevents replaying the chapter card. These flags and reading event counters use normal SaveManager persistence; no extra save files are created. F6 without a fresh-save marker follows the legacy compatibility path. New games retain the opening and self-check sequence.

## 开局装备与水池检测维护

主关卡 LIRA 不覆盖 `start_water_gun_level`，沿用角色默认 0。水枪和水箱在首次湖心终端交谈后由 `receive_starter_equipment()` 解锁；01 的奖励是兼容性兜底。未获取时不能持枪、瞄准或发射，已保存的装备等级照常恢复。喷气背包按 main 的工厂任务流程解锁：收集齿轮、修复机器人，由机器人取回并交付背包。

`objects/player/LIRA/lira.gd` 在场景初始化结束后延迟调用 `_refresh_water_list()`，收集全部 `water_surfaces`（包括水泵后续显示的水面）；实际查询时忽略隐藏水面和已移除节点。重叠水面每帧选择最高的有效局部水面，避免北部水池被低处海面抢先匹配。保留现有 `in_water`、游泳动画、浮力和空格出水跳跃，不需要喷气背包或新增动画。调整水面位置时同步核对水池边缘的出水路径。

工厂与水泵房之间的小坑使用主关卡 SubViewportContainer/PixelateSubViewport/Water/Pond，保持 Visible 开启，沿用场景内水位与 Fit To Basin。它是常驻积水，不加入 WaterFlowSwitch 的 Water 或 Rise 列表；水泵启动前后都可游泳，并沿用无喷气背包时的空格出水跳跃。位置、尺寸和水位仍在场景中调整，无运行时代码补水。

## Cabin and harbor flow maintenance

`CabinStory.migrate_save()` now uses version 2: it rebuilds only quest 00 from its counters. Existing pump/terminal progress credits prior cabin reading so later saves are not relocked; partially read early saves keep each read flag. The old 01 step shift runs only for version 0, never again for version 1/2 saves.

The placed keyed radar (`rada_interaction.gd`) and story radar (`radar_story.gd`) both call `RadarStory.record_coordinates()` to record `radar_started` and `radar_coordinates` once. Both display `FinaleStory.COORDINATES` through `coordinates_text()`; world XYZ coordinates are not the harbor entry code. The placed console restores its completed display from quest events after loading. Saves from before this fix that only displayed coordinates have no stored completion flag: use that radar once again, without starting a new save.

After collecting the lake battery, the existing terminal status label shows the next objective: radar -> harbor coordinates -> battery installation -> departure. The boat still validates the recorded radar event and the correct navigation code; cancel/wrong-code paths do not advance progress. A powered legacy boat without recorded code entry still opens the coordinate pad before departure. Scene placements, interaction points and UI layouts stay in their existing scene files.

## 岛屿边界

`levels/meadow_hand/island_boundary.tscn` 直接实例化在主关卡根节点下，与地形和玩家共用物理世界。23 个简单 BoxShape3D 首尾重叠，围住主岛外海，不创建可见网格；高度覆盖游泳深度和喷气背包活动范围。打开该场景调整 Wall01..Wall23 的位置、Y 旋转与 Shape Size；不要运行时生成或修改碰撞体。北侧远海的小块地形位于作业范围之外，主岛与港口保留在圈内。

`island_boundary.gd` 仅读取这些碰撞箱判断距离：Warning Distance 默认 12 米，Release Distance 默认 18 米，避免边缘反复闪烁。StartupChecks 将警告交给原 `ui/in_game/startup/startup_hint.tscn` 右上卡片，复用顶部滑动淡入淡出，文字在 `i18n/strings.csv` 的 `BOUNDARY_WARNING_*`。边界提示优先于教学，停留期间持续显示、不计入 10 秒；远离后恢复原提示及其剩余显示时间。暂停总览可见，设置、对话与转场期间遵循原卡片显隐规则；取得终端后边界提示仍有效。碰撞与警告无额外存档状态。

## 主场景散布缓存与编辑器加载

`levels/meadow_hand/meadow_hand.tscn` 的 19 个 ProtonScatter 节点（包括三个花草实例的关卡覆盖）均关闭 Performance → Force Rebuild On Load，避免打开、切换场景时同时重建并等待物理查询。保留原种子、修改器、散布范围、复制模式和碰撞设置，不修改插件默认值，也不禁用插件。

根节点下的 ScatterCache 使用插件原生 `ProtonScatterCache`，读取同目录唯一缓存 `meadow_scatter_cache.res`（初始 19 组、573 个变换）。请把场景与缓存一起提交给队友，否则关闭自动重建后会缺少散布物。该缓存是场景资源，不是 `.godot` 导入缓存；清理导入缓存不会替代它。

编辑散布范围或修改器后，等待对应节点生成完成再保存主场景，ScatterCache 默认会在保存时更新缓存；也可选中 ScatterCache，在检查器使用 Update Cache，再保存。仅改普通场景物件无需重建散布。继续保持上述加载重建开关关闭；不要勾选 Enabled=false 来解决卡顿，那会移除散布物。旧的 meadow_hand_debug.tscn 是独立调试场景，本次不改变其散布设置。
