class_name Quest extends Resource
## A mission. Save it as a .tres in res://quests/ and it appears in the game; files are
## ordered by name, so prefix them 01_, 02_... Steps are done one after another.
## Texts can be plain text or translation keys from i18n/strings.csv.

@export var title := ""
@export_multiline var description := ""
## Where it takes place, shown under the title.
@export var location := ""
## Starts once all of these are complete (empty = available from the start).
@export var requires: Array[Quest] = []
@export var steps: Array[QuestStep] = []
## Abilities granted on completion: name -> level, e.g. water_gun: 1, jetpack: 2.
## A level only ever goes up, so granting water_gun: 1 after water_gun: 2 changes nothing.
@export var rewards: Dictionary[StringName, int] = {}


## Stable id for saves: the file name without its extension.
func get_id() -> StringName:
	return StringName(resource_path.get_file().get_basename())
