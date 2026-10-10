# 对话 UI

默认 Dialogic 样式为 `dialogue/styles/UI.tres`，注册并加载 `ui/CustomUi/custom_ui_.tscn`。剧情在 `dialogue/timelines/`，角色定义在 `dialogue/characters/`，显示布局与剧情内容分别维护。

## 组成

- `dialogue_layout_base.gd`：主题设置、对话期间玩家冻结与鼠标状态管理。
- `layers/dialogue_box_layer.tscn`：底部文本框、说话者头像、姓名、继续提示及自动／跳过／历史操作。
- `layers/choice_layer.tscn`、`text_input_layer.tscn`、`history_layer.tscn`：选项、文字输入及历史。
- `StagePortraitLayer`：Dialogic 站位立绘层；`show_stage_portraits` 控制是否显示。
- `dialogue_trigger.gd`：进入范围后选取最近的可交互目标，按 `interact` 启动时间线。
- `dialogue_utils.gd`：按原因管理对话暂停，避免历史、确认框与游戏暂停互相覆盖。

## 外观与字体

自定义图层显式使用 `ui/theme/light/light_theme.tres`。默认正文为 Sarasa UI Regular，按钮和名牌等使用主题中的 SemiBold；覆盖字段留空则继承主题。字号辅助规则见 `ui/theme/ui_type.gd`，当前步长为 12，常用 24 / 36 / 48。

对话框仍引用 `ui/theme/glass/next_circle.png`、`nameplate.png` 和 `glass_panel_material.tres` 等资源，不能删除整个玻璃目录。头像过滤通过 `portrait_smooth_filter` 调整；布局和外观参数以对应场景及脚本导出字段为准。

## 触发与快捷键

在场景添加 `DialogueTrigger` 并设置 `timeline`，或用 `DialogueTrigger.attach_to(area, "时间线名")` 包装已有区域。可配置自动启动、一次性触发与范围。触发器识别 `player` 分组，或带 `frozen` 属性的 CharacterBody3D。

靠近提示由 `ui/in_game/interaction/interaction_prompt.tscn` 显示，按键文字来自 SettingsManager 的实际绑定；重绑定后自动更新。不要把交互键写成固定 F，也不要在文档中把某个默认键当成永久规则。自动、跳过和历史分别使用 `dialogue_auto`、`dialogue_skip`、`dialogue_history` 动作，以项目输入映射和当前用户设置为准。

## 翻译

UI 文案在 `i18n/strings.csv`，现有 XBot 台词译文在 `i18n/dialogue_xbot.csv`。时间线行尾的 `#id:xx` 用于匹配译文，不随意删除。项目的 Dialogic 翻译开关与资源注册需在新增时间线时一并核对；CSV 修改后由 Godot 重新导入。界面语言由 SettingsManager 管理。
