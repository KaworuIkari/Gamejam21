class_name UIType
extends RefCounted
## UI 字号与字体覆盖辅助。当前主题默认使用 Sarasa UI。
## 12 的步长沿用现有排版；不是当前矢量字体的固有像素网格。
## 字体由明亮主题和项目全局主题分别配置，控件可继承或显式覆盖。
## 修改字号步长时同时检查控件布局、行距和对话导出字号。

const GRID_PX := 12

## 常用字号档位（网格的 2× / 3× / 4×）
const SMALL := 24
const MEDIUM := 36
const LARGE := 48


## 把任意字号吸附到最近的网格整数倍（至少 1 倍）
static func snap(size: int) -> int:
	return maxi(GRID_PX, roundi(float(size) / GRID_PX) * GRID_PX)


## 该字号下“一个字体像素”在设计坐标中的边长。行距、内边距等用它的整数倍，排版就落在像素网格上
@warning_ignore("integer_division")
static func pixel(size: int) -> int:
	return snap(size) / GRID_PX


## 读取可选的字体覆盖：路径为空或无效时返回 null，表示“继承项目主题字体”
static func font_or_null(path: String) -> Font:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Font


## 给控件设置 / 清除字体覆盖。font 为 null 时移除覆盖，回到主题字体
static func apply_font(control: Control, theme_key: StringName, font: Font) -> void:
	if font:
		control.add_theme_font_override(theme_key, font)
	else:
		control.remove_theme_font_override(theme_key)


## 项目主题字体的路径（给只认“字体路径”的 Dialogic 自带图层使用，如词汇表）
static func theme_font_path() -> String:
	var t := ThemeDB.get_project_theme()
	if t and t.default_font:
		return t.default_font.resource_path
	return ""
