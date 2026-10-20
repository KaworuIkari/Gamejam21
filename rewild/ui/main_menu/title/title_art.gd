extends TextureRect
## Localized title artwork; presentation only.
## 控件尺寸严格等于图片比例，配合 size_flags_horizontal = SHRINK_END 才能真正贴右。
const CHINESE = preload("res://ui/main_menu/title/title_zh.png")
const ENGLISH = preload("res://ui/main_menu/title/title_en.png")
@export var art_bounds := Vector2(760, 260)
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
	var aspect := float(texture.get_width()) / float(texture.get_height())
	var max_width := minf(art_bounds.x, get_parent().size.x)
	var width := minf(max_width, art_bounds.y * aspect)
	custom_minimum_size = Vector2(width, width / aspect)
