# Lake power station

Reference-inspired original 3D station: rounded ivory armor, cyan halo and beacon, recessed front display, botanical symbol, weathered seams and root-like power cables. About 3.1m tall, 2.25m body diameter, roughly 5m cable footprint. Meter scale, Godot Y up. Front/interface faces local +Z. Origin rests on the island surface.

## Place and try

Place **Lake_Power_Station.tscn** on top of the existing lake island. Do not replace the island itself. Keep 2m of approach space in front of the console. Cables are non-colliding; a shared cylinder blocks the central body. InteractionZone defaults to player collision layer 1 and the `player` group, matching the existing interaction convention; adjust its mask if needed.

Run **interaction_demo.tscn** with F6 to try the behavior. U completes the spring prerequisite; E (or the project's mapped interact action) activates; another interaction emits a terminal request; R resets. The demo player is invisible and remains in range. Demo key handling lives only in the demo scene.

**sample.tscn** compares the three static appearances. The separate Dormant, Ready, Active scenes are also available for purely visual placement. Only the unsuffixed Lake_Power_Station.tscn includes the controller.

## Task and interaction hooks

The controller uses your existing `interact` action and respects pause and active Dialogic dialogue. It has no autoload dependencies and does not change your input bindings.

- `required_task_ids` defaults to `[main_02_spring]`, matching the flow: restore the spring, swim to the island, activate the terminal. Change this array if several task completions must be required. It unlocks only after ALL listed ids are reported.
- Call `station.mark_task_completed(task_id)` from your task completion signal. Unrelated or duplicate ids do not activate it.
- Alternatively call `station.set_tasks_complete(true)` for manual unlocking. With an empty required_task_ids array, manual unlocking is required.
- Dormant rejects interaction. Ready can activate. Active stays active and can be used repeatedly to request the terminal.
- Connect `activated` to your world-stage advance, water release, ability reward and task completion. This signal fires once per activation state, not on later uses or save restoration.
- Connect `terminal_requested` to the terminal UI's public open request. It fires on subsequent active-state interactions. If you want the UI to open on the first activation too, connect `activated` to that handler as well.
- `state_changed(state)` reports 0/1/2. `initial_state` supports preview or manually unlocked placement. `locked_message` is editable.

No task-manager implementation was found in the inspected project, so the task-completion signal and terminal opening are intentionally not connected to a guessed manager or scene path. The model is installed for placement; existing level files are unchanged.

## Persistence

`get_save_data()` returns a serializable dictionary (version, state, completed task ids). Pass it to your save manager. `restore_save_data(data)` restores visuals and task history before or after the node enters the tree, without emitting activation rewards again. Disk saving itself belongs to the existing save system.

Activation state is gameplay progress, not the global Wasteland/Revival/Golden palette. The ruin does not automatically reset when the world stage changes. All three visual models share identical structural geometry and one body collider in the interactive scene. Bloom/halo intensity depends on the game's renderer/environment; the cyan ring material is emissive in all renderers but bloom is not forced.
