extends TextureRect
## Localized title artwork; presentation only.
const CHINESE = preload("res://ui/main_menu/title/title_zh.png")
const ENGLISH = preload("res://ui/main_menu/title/title_en.png")
var _art: Dictionary = {}

func _ready() -> void:
	for source in [CHINESE, ENGLISH]:
		var cropped := AtlasTexture.new()
		cropped.atlas = source
		cropped.region = Rect2(source.get_image().get_used_rect())
		_art[source] = cropped
	resized.connect(_fit_art)
	_update_language()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_language()

func _update_language() -> void:
	var source = CHINESE if TranslationServer.get_locale().begins_with("zh") else ENGLISH
	texture = _art[source]
	_fit_art()

func _fit_art() -> void:
	if texture == null:
		return
	var width := minf(640.0, get_parent().size.x)
	custom_minimum_size = Vector2(width, width * texture.get_height() / texture.get_width())
