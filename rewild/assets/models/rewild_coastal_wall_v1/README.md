# Coastal garbage wall

Six placeable removable modules, each approximately 5m wide and 5–7m tall: stacked containers, vehicle carcass, compacted scrap, rebar seawall, engine pile, and final locked section. Built as an opaque industrial barrier for the opening basin and the final sea reveal.

Start with `Coastal_Wall_Intact.tscn` (about 29m across). Modules are separate child scenes. `Coastal_Wall_Partially_Cleared.tscn` illustrates two removed modules. `Coastal_Wall_Open.tscn` is an empty passage marker with no geometry or collision, representing all sections removed. These are example compositions, not animated destruction or automatically saved gameplay states.

Each section carries `category=Clearable`, `tags=[beach_wall]`, and `required_ability=demolition_auth` as metadata. Your interaction code must enforce the authorization and remove/count modules. Metadata alone does not lock them or connect the task system.

Use `sample.tscn` for the individual pieces. Arrange more sections to fit the basin; test sightlines from the actual spawn camera and terrain elevations. Meter scale, Y up, static collision layer 1. The lock is visual only. No changes were made to the playable level.
