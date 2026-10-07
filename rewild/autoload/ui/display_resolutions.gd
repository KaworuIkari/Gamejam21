class_name DisplayResolutions
extends RefCounted
## 窗口分辨率规则（唯一出处）：可选列表、宽高比标注、“自动”档的计算。
## SettingsManager 用它决定窗口尺寸，设置页用它生成“分辨率”选项。
##
## 设置里保存的是尺寸本身（Vector2i），AUTO = Vector2i.ZERO 表示“自动适配显示器”。
## 列表只列出当前显示器放得下的尺寸；放不下的旧设置会自动回落到“自动”。

const AUTO := Vector2i.ZERO

## 常见窗口尺寸（16:9 / 16:10 / 21:9）。需要更多比例时只改这里
const CANDIDATES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1440, 900),
	Vector2i(1600, 900), Vector2i(1680, 1050), Vector2i(1920, 1080),
	Vector2i(1920, 1200), Vector2i(2560, 1080), Vector2i(2560, 1440),
	Vector2i(2560, 1600), Vector2i(3440, 1440), Vector2i(3840, 2160),
]

## 已知比例（用于标注；按实际宽高比就近匹配）
const ASPECTS := {
	"16:9": 16.0 / 9.0, "16:10": 16.0 / 10.0, "21:9": 64.0 / 27.0,
	"4:3": 4.0 / 3.0, "3:2": 3.0 / 2.0, "5:4": 5.0 / 4.0, "32:9": 32.0 / 9.0,
}

## 窗口标题栏、边框的预留高度（usable rect 已经扣掉了任务栏）
const DECORATION_MARGIN := Vector2i(0, 48)

## “自动”档占屏幕可用区域的最大比例（留出边框，避免窗口贴边）
const AUTO_FILL := 0.9


## 当前显示器可用区域（扣除任务栏）
static func usable_size(screen := -1) -> Vector2i:
	if screen < 0:
		screen = DisplayServer.window_get_current_screen()
	return DisplayServer.screen_get_usable_rect(screen).size


## 显示器的物理分辨率
static func screen_size(screen := -1) -> Vector2i:
	if screen < 0:
		screen = DisplayServer.window_get_current_screen()
	return DisplayServer.screen_get_size(screen)


static func fits(size: Vector2i, screen := -1) -> bool:
	var room := usable_size(screen) - DECORATION_MARGIN
	return size.x <= room.x and size.y <= room.y


## 当前显示器放得下的分辨率（按面积从小到大）
static func available(screen := -1) -> Array[Vector2i]:
	var list: Array[Vector2i] = []
	for s in CANDIDATES:
		if fits(s, screen):
			list.append(s)
	list.sort_custom(func(a: Vector2i, b: Vector2i): return a.x * a.y < b.x * b.y)
	return list


## “自动”档：与显示器同比例、不超过可用区域 AUTO_FILL 的最大尺寸；
## 找不到同比例时退而取任意比例中最大的；再不行就按显示器比例直接计算
static func auto_size(screen := -1) -> Vector2i:
	var room := Vector2(usable_size(screen) - DECORATION_MARGIN) * AUTO_FILL
	var target := aspect_name(screen_size(screen))
	var best := Vector2i.ZERO
	var best_any := Vector2i.ZERO
	for s in available(screen):
		if s.x > room.x or s.y > room.y:
			continue
		if s.x * s.y > best_any.x * best_any.y:
			best_any = s
		if aspect_name(s) == target and s.x * s.y > best.x * best.y:
			best = s
	if best != Vector2i.ZERO:
		return best
	if best_any != Vector2i.ZERO:
		return best_any
	var ratio := float(screen_size(screen).x) / maxf(1.0, screen_size(screen).y)
	var h := floori(room.y)
	return Vector2i(mini(floori(h * ratio), floori(room.x)), h)


## 把设置值解析成实际窗口尺寸（AUTO 或放不下 → 自动档）
static func resolve(value: Vector2i, screen := -1) -> Vector2i:
	if value == AUTO or not fits(value, screen):
		return auto_size(screen)
	return value


## 宽高比名称：就近匹配常见比例（如 2560×1080 → 21:9），都不接近时给出约分结果
@warning_ignore("integer_division")
static func aspect_name(size: Vector2i) -> String:
	if size.x <= 0 or size.y <= 0:
		return ""
	var r := float(size.x) / size.y
	for name in ASPECTS:
		if absf(r - ASPECTS[name]) / ASPECTS[name] < 0.02:
			return name
	var g := _gcd(size.x, size.y)
	return "%d:%d" % [size.x / g, size.y / g]


## 选项文字，例如 “1920 × 1080  16:9”
static func label(size: Vector2i) -> String:
	return "%d × %d  %s" % [size.x, size.y, aspect_name(size)]


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t := b
		b = a % b
		a = t
	return maxi(a, 1)
