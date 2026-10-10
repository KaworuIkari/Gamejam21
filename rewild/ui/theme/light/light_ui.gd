extends RefCounted
## Shared bright menu theme, scoped to menu roots rather than the whole game.

const LIGHT_THEME = preload("res://ui/theme/light/light_theme.tres")
const BLUR_SHADER = preload("res://ui/theme/light/light_backdrop.gdshader")
const INK := Color(0.22, 0.29, 0.28, 1)
const MUTED := Color(0.35, 0.41, 0.39, 1)
const GOLD_INK := Color(0.43, 0.32, 0.14, 1)



static func apply(root: Node) -> void:
	root.set(&"theme", bright_theme())


static func bright_theme() -> Theme:
	return LIGHT_THEME


static func frost(control: Control, follow_opacity: bool = false) -> void:
	if control.has_node("LightBackdrop"):
		return
	control.set_meta(&"no_glass", true)
	control.material = null
	# A non-Control wrapper keeps PanelContainer from fitting the backdrop
	# inside its content margins, which would create a second inset panel.
	var wrapper := Node2D.new()
	wrapper.name = "LightBackdrop"
	wrapper.show_behind_parent = true
	var backdrop := Panel.new()
	backdrop.name = "Surface"
	backdrop.set_meta(&"no_glass", true)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var radius := 18 if control is Button else 30
	if control is PanelContainer:
		var panel_style := control.get_theme_stylebox(&"panel")
		if panel_style is StyleBoxFlat:
			radius = panel_style.corner_radius_top_left
	backdrop.add_theme_stylebox_override(&"panel", surface(Color.WHITE, Color.TRANSPARENT, radius))
	var material := ShaderMaterial.new()
	material.shader = BLUR_SHADER
	material.set_shader_parameter(&"blur_px", 14.0)
	material.set_shader_parameter(&"lod", 2.0)
	material.set_shader_parameter(&"saturation", 0.85)
	material.set_shader_parameter(&"dim", 1.0)
	material.set_shader_parameter(&"tint", Vector3(0.95, 0.97, 0.93))
	material.set_shader_parameter(&"tint_alpha", 0.48)
	backdrop.material = material
	wrapper.add_child(backdrop)
	control.add_child(wrapper, false, Node.INTERNAL_MODE_FRONT)
	backdrop.size = control.size
	control.resized.connect(func(): backdrop.size = control.size)
	if follow_opacity:
		backdrop.self_modulate.a = control.self_modulate.a
		control.draw.connect(func():
			if not is_equal_approx(backdrop.self_modulate.a, control.self_modulate.a):
				backdrop.self_modulate.a = control.self_modulate.a)


static func soften_dim(dim: ColorRect) -> void:
	dim.color = Color(0.12, 0.19, 0.20, 0.08)


static func surface(fill: Color, edge: Color, radius: int, pad_x: int = 0, pad_y: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = pad_x
	style.content_margin_right = pad_x
	style.content_margin_top = pad_y
	style.content_margin_bottom = pad_y
	return style
