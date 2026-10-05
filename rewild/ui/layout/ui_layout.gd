class_name UILayout
extends RefCounted
## UI 的共享尺寸与断点规则。
## 各页面只查询这里的规则，不各自硬编码“手机端”判断。

const COMPACT_WIDTH := 1_050.0
const MOBILE_CONTENT_SCALE := 1.35


static func is_compact(viewport_size: Vector2) -> bool:
	# 竖屏始终使用紧凑布局；横屏仅在窄窗口时收紧。
	return viewport_size.x < viewport_size.y or viewport_size.x < COMPACT_WIDTH


static func content_scale(user_scale_percent: float) -> float:
	# 手机屏幕的物理尺寸远小于桌面显示器。基础放大与无障碍选项相乘，
	# 让 100% 在两类设备上都具有可读性。
	var platform_scale := MOBILE_CONTENT_SCALE if OS.has_feature("mobile") else 1.0
	return platform_scale * user_scale_percent / 100.0


static func settings_metrics(viewport_size: Vector2) -> Dictionary:
	if is_compact(viewport_size):
		return {
			"margin_x": 24,
			"margin_y": 20,
			"panel_gap": 14,
			"row_gap": 12,
			"title_size": 40,
			"tab_size": 20,
			"body_size": 22,
			"control_size": 20,
			"section_size": 28,
			"row_height": 54,
		}
	return {
		"margin_x": 220,
		"margin_y": 56,
		"panel_gap": 24,
		"row_gap": 18,
		"title_size": 56,
		"tab_size": 28,
		"body_size": 24,
		"control_size": 22,
		"section_size": 34,
		"row_height": 64,
	}
