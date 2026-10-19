@tool
extends DialogicCharacter
## Display Name may be a key in i18n/strings.csv; standard Dialogic names still work.
func get_display_name_translated() -> String:
	return tr(super.get_display_name_translated())
