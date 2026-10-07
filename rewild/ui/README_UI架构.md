# UI / 对话系统 架构说明

给队友看的“谁负责什么”。改动这些行为时，请改对应的唯一负责模块，不要在别处另写一份。

## 模块一览

| 模块 | 位置 | 职责 |
|---|---|---|
| SettingsManager（Autoload） | `autoload/settings_manager.gd` | 读写 `user://settings.cfg`，应用设置，管理按键重绑定；`set_value` 预览 → `commit` 应用并写盘 / `revert` 撤回 |
| └ UIScaler（子节点） | `ui/layout/ui_scaler.gd` | 把 `res://ui/`、`res://CustomUi/` 下的界面按 1920×1080 排版后缩放到项目基准分辨率；不改全局缩放 |
| DisplayResolutions（静态类） | `autoload/display_resolutions.gd` | 窗口分辨率规则：按当前显示器生成可选尺寸、标注宽高比、计算“自动”档；设置里保存尺寸本身，`(0,0)` = 自动 |
| UIType（静态类） | `ui/theme/ui_type.gd` | 像素字体排版规则：字体网格、字号档位、字号吸附、字体覆盖。全部界面的字体 / 字号从这里取 |
| └ PlayerSettingsBridge（子节点） | `autoload/player_settings_bridge.gd` | 把鼠标/手柄灵敏度、视野写到 real-controller 角色上（不改队友的控制器代码） |
| SaveManager（Autoload） | `autoload/save_manager.gd` | 存档位读写、游戏时长 |
| SceneRouter（Autoload） | `autoload/scene_router.gd` | 带淡入淡出的场景切换；切换前解除暂停 |
| 暂停菜单 | `ui/in_game/pause_menu.gd` | 由 `main.gd` 创建 |
| 对话布局 | `CustomUi/`（Dialogic 样式 `UI .tres`） | 对话框、选项、输入框、历史；对话期间冻结玩家 |
| 对话触发器 | `CustomUi/dialogue_trigger.gd` | 靠近显示“按 F 交谈”，按交互键开始时间线 |

## 唯一负责人（避免互相打架）

| 状态 | 负责模块 | 说明 |
|---|---|---|
| 暂停键 Esc | 暂停菜单 | 只有它处理 `pause` 动作；历史面板、确认框、设置页会先消费 Esc |
| 场景树暂停 `get_tree().paused` | 暂停菜单（开/关）、SceneRouter（切场景前解除） | |
| 对话暂停 `Dialogic.paused` | `DialogueUtils.push_pause / pop_pause` | 不要直接写 `Dialogic.paused`；按“原因”登记，全部撤销才继续 |
| 鼠标显示/锁定 | 对话布局（对话中显示）、暂停菜单（打开显示、关闭按规则恢复）、主菜单（显示） | 回到游戏的规则在 `pause_menu.gd` 的 `restore_gameplay_mouse()` |
| 玩家冻结 `frozen` | 对话布局 | 对话开始冻结、结束/切场景解冻 |

## 约定

- 分辨率：可选尺寸只在 `DisplayResolutions.CANDIDATES` 里增减；放不下当前显示器的尺寸不会出现在列表里，旧设置放不下时自动回落到“自动”档（保持宽高比，不截断）。编辑器“游戏”标签页内嵌运行时窗口由编辑器控制，分辨率按钮会显示为不可用。
- 设置的“应用”：改设置只调用 `SettingsManager.set_value()`（立即预览）；只有设置页的“应用”按钮调用 `commit()` 写盘；离开设置页未应用则 `revert()`。不要在别处直接调用 `save()` 保存普通设置（按键重绑定除外，它自己即时写盘）。
- 字体：所有界面默认使用项目主题 `ui/theme/greybox_theme.tres` 的字体，不要在场景或脚本里写死字体路径。字号用 12 的整数倍（`UIType.SMALL / MEDIUM / LARGE` = 24 / 36 / 48），代码里设置字号时经过 `UIType.snap()`。换字体时改主题的 `default_font` 和 `UIType.GRID_PX` 两处。
- 2D 默认纹理过滤是“最近邻”（像素风）。渐变背景、照片、3D 渲染的立绘等非像素图，在节点上单独把 `texture_filter` 设为 Linear。

- 新界面放在 `res://ui/` 或 `res://CustomUi/` 下、根节点铺满全屏，就会自动按 1920×1080 设计尺寸缩放；排版时用自身 `size`，需要视口尺寸时用 `UIScaler.virtual_viewport_size()`。
- 我们的界面里不要用 `OptionButton` / `PopupMenu`：Godot 4.7 在缩放后的界面里弹不出来。用 `ui/settings/option_stepper.gd`（◀ 值 ▶）。
- 新增可重绑定按键：在 `SettingsManager.REBINDABLE_ACTIONS` 里加动作名（必须和输入映射一致），并在 `i18n/strings.csv` 加 `ACTION_<动作名大写>`。
- 新的对话 NPC：拖一个 `DialogueTrigger` 节点、填时间线名即可；已有 Area3D 可用 `DialogueTrigger.attach_to(area, "时间线名")`。

## 尚未接入

设置里的“反转 Y 轴、镜头晃动、手柄震动、字幕”目前只保存，不生效：角色控制器没有对应功能，需要和控制器作者商量后再接。
