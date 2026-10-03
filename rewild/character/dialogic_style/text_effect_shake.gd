@tool
extends RichTextEffect
class_name ShakeTextEffect

@export var strength: float = 20.0
@export var speed: float = 12.0
# different from the default shake
var bbcode = "shake2"

func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var t = char_fx.elapsed_time * speed
	var seed = float(char_fx.range.x)
	var offset_x = sin(t + seed * 12.0) * strength
	var offset_y = cos(t + seed * 7.0) * strength
	char_fx.offset = Vector2(offset_x, offset_y)
	return true
