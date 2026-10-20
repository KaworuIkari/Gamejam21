shader_type canvas_item;
// 模糊底：由 light_ui.gd 作为控件的子节点（show_behind_parent）垫在面板 / 按钮背后。
// 子节点画一个白色圆角形状作遮罩，这里把形状内填成“强模糊 + 压暗 + 染色”的背景；
// 控件自己的半透明玻璃贴图和文字盖在它上面，所以文字不受影响。
// 采样用螺旋圆盘（48 点），不依赖屏幕纹理 mip，Forward+ / 兼容渲染器都可用。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur_px : hint_range(0.0, 64.0) = 24.0;     // 模糊半径（以 1080p 屏幕高度为准）
uniform float lod : hint_range(0.0, 5.0) = 2.0;
uniform float saturation : hint_range(0.0, 1.5) = 0.8;    // <1 偏灰
uniform float dim : hint_range(0.3, 1.2) = 0.8;           // <1 压暗背后画面
uniform vec3 tint : source_color = vec3(0.12, 0.13, 0.16); // 染色（深灰）
uniform float tint_alpha : hint_range(0.0, 1.0) = 0.5;    // 染色层不透明度，面板约 50%，按钮 0（按钮贴图自带色）

void fragment() {
	float ry = blur_px / 1080.0;
	vec2 rad = vec2(ry * SCREEN_PIXEL_SIZE.x / SCREEN_PIXEL_SIZE.y, ry);
	vec3 acc = vec3(0.0);
	for (int i = 0; i < 48; i++) {
		float r = sqrt((float(i) + 0.5) / 48.0);
		float a = float(i) * 2.39996323;
		acc += textureLod(screen_tex, SCREEN_UV + vec2(cos(a), sin(a)) * r * rad, lod).rgb;
	}
	vec3 bg = acc / 48.0;
	float l = dot(bg, vec3(0.299, 0.587, 0.114));
	bg = mix(vec3(l), bg, saturation) * dim;
	bg = mix(bg, tint, tint_alpha);
	COLOR = vec4(bg, COLOR.a);
}
