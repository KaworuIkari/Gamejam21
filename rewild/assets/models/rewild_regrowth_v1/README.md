# Rewild — 20 props with watering-driven greenery

Every prop has one permanent barren base and a separate greenery overlay. There are no duplicate greened structures. Foliage uses meshes and textures from the project's stylized_nature pack; ivy is new lightweight geometry. All dimensions are metres.

## Place a prop

Restorable props live in `res://objects/restorable/overgrown/<category>/restorable_<name>.tscn`, each an instance of `*_Barren.tscn` with its `*_Greenery.tscn` overlay as a child. The base owns collision; plants never add collision.

| Category | Props |
|---|---|
| wooden | timber_bench, split_rail_fence, trail_sign, wayside_shelter, abandoned_handcart |
| stone | dry_stone_wall, broken_stone_arch, old_stone_steps, cracked_planter |
| water | abandoned_well, rusted_water_tank, water_trough, broken_pipe |
| industrial | power_cabinet, relay_mast, cable_spool, collapsed_solar_panel, broken_cargo_crate |
| deadwood | hollow_stump, fallen_log |

## Watering and growth

`growing_greenery.gd` (class `GrowingGreenery`) works like the forest tree leaves: it swaps each patch's glb materials for the shared overgrowth materials in `materials/` (shader `res://systems/growth_map/overgrowth.gdshader`) and binds them to `/root/GrowthMap`. Each patch reads the ground growth under its own origin and dissolves in clump by clump: ivy/moss from 0.35-0.45 growth, grass from 0.4, leaves from 0.5, flowers last from 0.7 (tune `grow_start`/`grow_full` in the .tres files). It's all on the GPU, with no polling or tweens. Clearing the growth map makes the plants disappear again. In the editor (or without GrowthMap) the plants show fully grown. Optional `sample_anchor` makes a whole overlay follow one ground point (e.g. a roof over the sea).

## Existing landmarks

- `Harbour_Greenery.tscn` → attached in meadow_hand as `IslandHarbor/Overgrowth`.
- `Factory_Greenery.tscn` → attached in meadow_hand as `DesertRoboticsLaboratory/Overgrowth`.
- `Plane_Greenery.tscn` → attached in meadow_hand as `Water/CrashsiteOutpostV2/Overgrowth`.

Use identity transforms. These were fitted to the meshes and local overrides in meadow_hand, not to generic substitute landmarks. Main floors and entrance ramps were excluded from planting. The plane overlay includes its current fuselage offset; if you move individual parts later, adjust the corresponding patches.

The 20 smaller props are provided for placement, not scattered automatically through the map.

## Preview

- `sample.tscn`: all 20 props.
- `watering_demo.tscn`: isolated four-prop demonstration using the real game GrowthMap; water is applied automatically after 1.5 seconds. Space resets this demo's growth map and repeats. Run separately, not as an in-game child.
- `props_1.png`, `props_2.png`: asset sheets.
- `harbour_preview.png`, `plane_preview.png`, `factory_preview.png`: fitted greenery.

## Catalog

1. Timber bench
2. Split rail fence
3. Trail sign
4. Wayside shelter
5. Dry stone wall
6. Broken stone arch
7. Abandoned well
8. Cracked planter
9. Power cabinet
10. Rusted water tank
11. Broken pipe
12. Relay mast
13. Abandoned handcart
14. Cable spool
15. Broken cargo crate
16. Collapsed solar panel
17. Hollow stump
18. Fallen log
19. Water trough
20. Old stone steps

The base collision uses static triangle meshes suitable for environmental props; these are not dynamic physics objects. Existing landmark collision is reused unchanged. All new materials and meshes live within this pack.
