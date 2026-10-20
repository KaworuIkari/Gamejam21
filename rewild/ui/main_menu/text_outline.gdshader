shader_type canvas_item;
// 给主菜单的图片文字加描边 + 投影 + 暖色微调。
// 描边/投影宽度按“屏幕像素”计算（用 fwidth(UV) 换算），所以缩放后粗细不变。

uniform vec4 fill_tint : source_color = vec4(1.0, 0.97, 0.86, 1.0);
uniform vec4 outline_color : source_color = vec4(0.30, 0.17, 0.08, 1.0);
uniform float outline_px : hint_range(0.0, 8.0) = 2.5;
uniform vec4 shadow_color : source_color = vec4(0.12, 0.07, 0.03, 0.6);
uniform vec2 shadow_offset_px = vec2(2.0, 3.5);

float body(vec2 uv) {
	// 只取字体实体，忽略图里自带的柔和阴影光晕
	return smoothstep(0.45, 0.85, texture(TEXTURE, uv).a);
}

float grow(vec2 uv, vec2 px, float r) {
	float m = body(uv);
	for (int i = 0; i < 16; i++) {
		float a = 6.2831853 * float(i) / 16.0;
		vec2 d = vec2(cos(a), sin(a)) * px;
		m = max(m, body(uv + d * r));
		m = max(m, body(uv + d * r * 0.5));
	}
	return m;
}

void fragment() {
	vec4 tint_in = COLOR;
	vec2 px = fwidth(UV);
	vec4 tex = texture(TEXTURE, UV);

	float o = grow(UV, px, outline_px);
	float s = grow(UV - shadow_offset_px * px, px, outline_px);

	vec4 col = vec4(shadow_color.rgb, shadow_color.a * s);
	col = vec4(mix(col.rgb, outline_color.rgb, o), col.a + (1.0 - col.a) * o);
	vec4 fill = vec4(tex.rgb * fill_tint.rgb, tex.a);
	// 标准 over 合成：fill 盖在 outline/shadow 之上
	float a_out = fill.a + col.a * (1.0 - fill.a);
	vec3 premult = fill.rgb * fill.a + col.rgb * col.a * (1.0 - fill.a);
	vec3 rgb = a_out > 0.0001 ? premult / a_out : vec3(0.0);
	COLOR = vec4(rgb * tint_in.rgb, a_out * tint_in.a);
}
