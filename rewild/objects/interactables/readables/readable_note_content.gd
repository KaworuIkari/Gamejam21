class_name ReadableNoteContent
extends Resource
## One resource per story note. Translation keys use the project's existing CSV.
@export var translation_key := ""
## Paginated tablets use these keys in order; paper notes keep their existing fields.
@export var page_keys: Array[String] = []
@export_multiline var text_zh := ""
@export_multiline var text_en := ""

func get_text(locale: String = TranslationServer.get_locale()) -> String:
	if not translation_key.is_empty():
		var translated := String(TranslationServer.translate(translation_key))
		if translated != translation_key:
			return translated
	if locale.begins_with("en") and not text_en.is_empty():
		return text_en
	return text_zh
