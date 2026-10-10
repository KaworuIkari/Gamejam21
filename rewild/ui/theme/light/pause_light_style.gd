extends PanelContainer
## Local visual treatment for the bright pause-menu variant.
## Flat styles deliberately bypass the shared GlassFx texture decorator.

const BACKDROP_SHADER = preload("res://ui/theme/light/light_backdrop.gdshader")
const INK := Color(0.22, 0.29, 0.28, 1.0)
const GOLD_INK := Color(0.43, 0.32, 0.14, 1)


func _ready() -> void:
	set_meta(&"no_glass", true)
	material = null
	var surface := _surface(Color(1.0, 0.99, 0.95, 0.12), Color(1.0, 1.0, 0.97, 0.65), 30)
	surface.shadow_color = Color(0.12, 0.19, 0.18, 0.12)
	surface.shadow_size = 18
	surface.shadow_offset = Vector2(0, 8)
	add_theme_stylebox_override(&"panel", surface)
	_add_backdrop()

	var margin: MarginContainer = $Margin
	margin.add_theme_constant_override(&"margin_left", 44)
	margin.add_theme_constant_override(&"margin_right", 44)
	margin.add_theme_constant_override(&"margin_top", 34)
	margin.add_theme_constant_override(&"margin_bottom", 40)
	var column: VBoxContainer = $Margin/VBox
	column.add_theme_constant_override(&"separation", 16)
	var title: Label = $Margin/VBox/Title
	title.custom_minimum_size.y = 64
	title.add_theme_font_size_override(&"font_size", 30)
	title.add_theme_color_override(&"font_color", INK)
	title.add_theme_color_override(&"font_shadow_color", Color.TRANSPARENT)
	for child in column.get_children():
		if child is Button:
			_style_button(child)
	var feedback: Label = $Margin/VBox/SaveFeedback
	feedback.add_theme_color_override(&"font_color", INK)
	feedback.add_theme_color_override(&"font_shadow_color", Color.TRANSPARENT)
	var dim: ColorRect = get_node("../../Dim")
	dim.color = Color(0.12, 0.19, 0.20, 0.08)


func _add_backdrop() -> void:
	var backdrop := Panel.new()
	backdrop.name = "PauseLightBackdrop"
	backdrop.set_meta(&"no_glass", true)
	backdrop.show_behind_parent = true
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.add_theme_stylebox_override(&"panel", _surface(Color.WHITE, Color.TRANSPARENT, 30))
	var frost := ShaderMaterial.new()
	frost.shader = BACKDROP_SHADER
	frost.set_shader_parameter(&"blur_px", 14.0)
	frost.set_shader_parameter(&"lod", 2.0)
	frost.set_shader_parameter(&"saturation", 0.85)
	frost.set_shader_parameter(&"dim", 1.0)
	frost.set_shader_parameter(&"tint", Vector3(0.95, 0.97, 0.93))
	frost.set_shader_parameter(&"tint_alpha", 0.48)
	backdrop.material = frost
	add_child(backdrop, false, Node.INTERNAL_MODE_FRONT)


func _style_button(button: Button) -> void:
	button.set_meta(&"no_glass", true)
	button.custom_minimum_size.y = 64
	button.add_theme_font_size_override(&"font_size", 30)
	for state in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]:
		button.add_theme_color_override(state, INK)
	button.add_theme_color_override(&"font_disabled_color", Color(0.35, 0.41, 0.39, 0.55))
	button.add_theme_color_override(&"font_shadow_color", Color.TRANSPARENT)
	var normal := _surface(Color(1.0, 1.0, 0.97, 0.16), Color(1.0, 1.0, 0.98, 0.34), 18)
	if button.name == &"ResumeButton":
		normal = _surface(Color(1.0, 0.88, 0.59, 0.34), Color(0.94, 0.77, 0.39, 0.65), 18)
		button.add_theme_color_override(&"font_color", GOLD_INK)
		button.add_theme_color_override(&"font_focus_color", GOLD_INK)
	button.add_theme_stylebox_override(&"normal", normal)
	button.add_theme_stylebox_override(&"hover", _surface(Color(1.0, 0.94, 0.76, 0.46), Color(0.94, 0.77, 0.39, 0.75), 18))
	button.add_theme_stylebox_override(&"pressed", _surface(Color(0.94, 0.81, 0.53, 0.44), Color(0.80, 0.64, 0.30, 0.8), 18))
	button.add_theme_stylebox_override(&"hover_pressed", button.get_theme_stylebox(&"pressed"))
	button.add_theme_stylebox_override(&"disabled", _surface(Color(1.0, 1.0, 1.0, 0.08), Color(1.0, 1.0, 1.0, 0.18), 18))
	var focus := _surface(Color.TRANSPARENT, Color(0.90, 0.70, 0.30, 0.95), 18)
	focus.set_border_width_all(2)
	focus.shadow_color = Color(1.0, 0.85, 0.47, 0.16)
	focus.shadow_size = 5
	button.add_theme_stylebox_override(&"focus", focus)


func _surface(fill: Color, edge: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	return style
