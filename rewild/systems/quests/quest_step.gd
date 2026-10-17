class_name QuestStep extends Resource
## One line of a quest: done once the world has reported `event` at least `count` times.
## Events are plain names that world objects report, e.g. a Clearable reports each of its
## tags ("garbage"), a WaterFlowSwitch its quest_event ("pump_started"). See quests/README.md.

## Shown in the terminal and the HUD. Plain text or a translation key.
@export var text := ""
## The event this step waits for.
@export var event: StringName = &""
## How many times it must happen.
@export_range(1, 999) var count := 1
## On: everything reported since the game started counts (safe for one-off events such as
## the pump, which can't happen again). Off: only what happens after this step starts
## counts, e.g. "clear 10 more garbage" after an earlier quest already asked for some.
@export var count_earlier := true
## On: opens together with the step before it. Such steps can be done in any order and the
## quest moves on once all of them are done (e.g. "clear 8 litter" and "restore the area").
@export var with_previous := false

## Optional intermediate collection display; does not complete the route.
@export var progress_event: StringName = &""
@export var progress_target := 0
