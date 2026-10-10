# UI 与对话系统维护说明

团队项目的目录层级为准。界面放在 `ui/`，全局 UI 管理脚本放在 `autoload/ui/`，对话内容与样式注册放在 `dialogue/`，翻译放在 `i18n/`。

## 模块职责

| 模块 | 项目内路径 | 职责 |
|---|---|---|
| SettingsManager | `autoload/ui/settings_manager.gd` | 设置预览、应用、撤回与按键重绑定，读写 `user://settings.cfg` |
| DisplayResolutions | `autoload/ui/display_resolutions.gd` | 分辨率候选、显示器尺寸及自动档 |
| SaveManager | `autoload/ui/save_manager.gd` | 存档槽位与元数据；尚未保存完整游戏状态 |
| SceneRouter | `autoload/ui/scene_router.gd` | 淡入淡出和场景切换；当前游戏入口为 `levels/meadow_hand/meadow_hand.tscn` |
| PlayerSettingsBridge | `ui/common/player_settings_bridge.gd` | 向符合接口的角色应用灵敏度和视野 |
| UIScaler / UILayout | `ui/layout/ui_scaler.gd`、`ui/layout/ui_layout.gd` | 界面缩放与响应式布局 |
| UIType | `ui/theme/ui_type.gd` | 字号档位、字号吸附及字体覆盖辅助 |
| 主菜单 / 设置 / 存档列表 | `ui/main_menu/`、`ui/settings/`、`ui/save_slots/` | 各自页面与交互 |
| 暂停菜单 | `ui/in_game/pause_menu.gd` | 由关卡创建，管理游戏暂停和游戏内存档页面 |
| ConfirmPopup | `ui/common/confirm_popup.gd` | 覆盖、删除等确认；默认聚焦取消 |
| 对话布局 | `ui/CustomUi/` | 文本、头像、选项、输入、历史与对话期间的玩家冻结 |
| 对话样式 | `dialogue/styles/UI.tres` | 注册 `ui/CustomUi/custom_ui_.tscn` |
| DialogueTrigger / DialogueUtils | `ui/CustomUi/dialogue_trigger.gd`、`ui/CustomUi/dialogue_utils.gd` | 交互触发与按原因管理对话暂停 |
| 交互提示 | `ui/in_game/interaction/` | 显示实际绑定键，适配语言与输入设备 |

## 主题与字体

主菜单、设置、存档、确认弹窗和自定义对话图层使用 `ui/theme/light/light_theme.tres`。项目全局回退主题仍是 `ui/theme/glass/glass_theme.tres`；对话还引用玻璃目录的部分素材和材质。两者并存有明确用途，不要只因菜单使用明亮主题就删除玻璃资源。

两个主题的默认字体均为 `ui/fonts/SarasaUiCL-Regular.ttf`，按钮和部分标题、名牌使用 `SarasaUiCL-SemiBold.ttf`。主菜单标题另使用 `ui/main_menu/title/` 中的图片。字体覆盖留空时继承所在控件的主题；Dialogic 的部分内置图层通过 `UIType.theme_font_path()` 读取项目全局主题。

`UIType` 当前保留 12 的字号步长，常用档位为 24 / 36 / 48。这是现有排版规则，不表示当前默认字体是 Fusion Pixel。换字体应检查明亮主题与全局主题各自的字体设置，再评估字号步长。

## 状态与输入约定

- 暂停菜单管理场景树暂停；SceneRouter 切场景前解除暂停。设置、存档子页与确认框处理各自的返回操作。
- 暂停及存档页面为 CanvasLayer 100，确认框为 120，场景切换遮罩为 128。新增模态界面须检查层级，避免遮挡或穿透。
- 对话暂停使用 `DialogueUtils.push_pause()` / `pop_pause()` 登记原因，不直接覆盖其他模块的暂停状态。
- 对话布局管理带 `frozen` 接口的玩家冻结与恢复；鼠标恢复规则见 `pause_menu.gd` 的 `restore_gameplay_mouse()`。
- 交互提示读取 `interact` 当前绑定；不要写死 F。以项目输入映射与用户重绑定为准。
- 普通设置通过 `set_value()` 预览，`commit()` 应用写盘，离开未应用时 `revert()`；按键重绑定按管理器自身规则即时保存。
- 分辨率候选由 `DisplayResolutions.CANDIDATES` 管理；新增 UI 使用 UIScaler 和 UILayout 的布局规则。选项步进控件使用 `ui/settings/option_stepper.gd`。

## 当前边界

反转 Y 轴、镜头晃动、手柄震动、字幕等设置尚未完整接入游戏功能。存档界面可管理槽位，但角色位置、任务和绿化进度需要游戏系统接入，不能据此认为完整进度已保存。


## 行动终端（2026-10-10）

入口及页面：`ui/in_game/tasks/`；独立像素主题：`ui/theme/terminal/terminal_theme.tres`。
任务页展示可点击的“演示参考”案例，不创建实际流程任务或存档数据。以后任务定义与状态放在 `systems/tasks/`。
暂停菜单实例化终端，并统一负责两种菜单的场景树暂停与鼠标恢复；Esc 优先关闭已打开的终端。
`task_terminal` 默认 Tab，可在设置中重绑定。对话期间终端不打开，Tab 继续保留对话跳过用途。
终端字体只通过局部主题覆盖为已有 Fusion Pixel 12px，字号使用 12 的整数倍；其他明亮菜单继续使用各自主题。

任务显示案例集中在 `ui/in_game/tasks/task_demo.gd`，仅供页面排版参考。`task_page.gd` 的 `show_demo` 导出开关设为 false 可恢复“待编辑”空页。演示追踪每次关闭/打开页面重置；案例的 1/3 进度是固定展示值，无真实完成行为。
