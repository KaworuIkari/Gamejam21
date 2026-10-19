# 对话 UI

默认 Dialogic 样式为 `dialogue/styles/UI.tres`，注册并加载 `ui/CustomUi/custom_ui_.tscn`。剧情在 `dialogue/timelines/`，角色定义在 `dialogue/characters/`，显示布局与剧情内容分别维护。

## 组成

- `dialogue_layout_base.gd`：主题设置、对话期间玩家冻结与鼠标状态管理。
- `layers/dialogue_box_layer.tscn`：统一的底部文本框、姓名、继续提示及自动／跳过／历史操作。
- `layers/choice_layer.tscn`、`text_input_layer.tscn`、`history_layer.tscn`：选项、文字输入及历史。
- `StagePortraitLayer`：保持隐藏，仅兼容现有剧情中的角色入场／离场指令；全局不显示头像或立绘。
- `dialogue_trigger.gd`：进入范围后选取最近的可交互目标，按 `interact` 启动时间线。
- `dialogue_utils.gd`：按原因管理对话暂停，避免历史、确认框与游戏暂停互相覆盖。

## 外观与字体

自定义图层显式使用 `ui/theme/light/light_theme.tres`。默认正文为 Sarasa UI Regular，按钮和名牌等使用主题中的 SemiBold；覆盖字段留空则继承主题。字号辅助规则见 `ui/theme/ui_type.gd`，当前步长为 12，常用 24 / 36 / 48。

对话框仍引用 `ui/theme/glass/next_circle.png`、`nameplate.png` 和 `glass_panel_material.tres` 等资源，不能删除整个玻璃目录。头像容器及其过滤／定位逻辑已移除。平板、终端及其他对话均使用默认 UI 样式，不另设加高阅读样式。

## 触发与快捷键

在场景添加 `DialogueTrigger` 并设置 `timeline`，或用 `DialogueTrigger.attach_to(area, "时间线名")` 包装已有区域。可配置自动启动、一次性触发与范围。触发器识别 `player` 分组，或带 `frozen` 属性的 CharacterBody3D。

靠近提示由 `ui/in_game/interaction/interaction_prompt.tscn` 显示，按键文字来自 SettingsManager 的实际绑定；重绑定后自动更新。不要把交互键写成固定 F，也不要在文档中把某个默认键当成永久规则。自动、跳过和历史分别使用 `dialogue_auto`、`dialogue_skip`、`dialogue_history` 动作，以项目输入映射和当前用户设置为准。

## 翻译

UI 文案在 `i18n/strings.csv`，现有 XBot 台词译文在 `i18n/dialogue_xbot.csv`。时间线行尾的 `#id:xx` 用于匹配译文，不随意删除。项目的 Dialogic 翻译开关与资源注册需在新增时间线时一并核对；CSV 修改后由 Godot 重新导入。界面语言由 SettingsManager 管理。

## 新存档开场

- 流程位于 `levels/meadow_hand/opening_sequence.gd`，由 `meadow_level.gd` 创建；`PAGE_KEYS` 决定分页顺序，文字及中英译文维护在 `i18n/strings.csv` 的 `OPENING_*` 行，`\n` 表示换行。
- `opening_ui.tscn` 继承现有对话布局，`dialogue/styles/Opening.tres` 只负责选择该布局；正文居中，右下角复用自动／跳过／历史。字号、语言及暂停沿用现有系统；开场文字间隔通过 `text_delay_multiplier` 设为当前对话速度的 3 倍，其他对话保持原速。文字显示中点击仅补全当前页，再次点击才翻页。
- `SaveManager.start_new_game()` 初始化 `opening_page = 0`；页码随确认推进，暂停菜单保存后可继续当前页，完成后自动保存。没有该字段的旧存档与直接运行关卡不补播。
- 镜头与动画可连接 OpeningSequence 的 `started`、`page_started(index)`、`reveal_started`、`finished` 信号，分别对应黑屏开始、切页、淡出开始、交还操作；`fade_duration` 控制淡出时长。淡出期间仍冻结玩家，Esc 暂停也暂停淡出。

## 统一布局与分页

普通对话统一使用 `layers/dialogue_box_layer.tscn`：宽度为设计画面的 80%，高度 272，距底部 36（1920×1080 设计坐标，随 UI 统一缩放）。当前说话者姓名在对话框右上角；自动／跳过／历史和继续提示在右下方。修改尺寸只改这一处。黑屏开局仅保留居中呈现，复用同一正文和操作控件。

长文通过剧情分页，不拉高面板。平板分页顺序在 `dialogue/readables/*.tres` 的 Page Keys，中英文在 `i18n/strings.csv` 的 `TABLET_*`；新增正文需核对最大字号 48 的中英文可见范围。普通时间线每行是一条确认内容，也可用 Dialogic 的 `[n]` 拆页。头像及加高平板样式不再有独立开关或文件。

## 说话者 / 记录来源

复用现有 `NamePlate / DialogicNode_NameLabel`，锚定对话框右上角并向左扩展，不创建第二套姓名 UI。多角色切换由每条 DialogicTextEvent 的 Character 决定；未指定角色的纯旁白不沿用上一句姓名。黑屏开场保留原有居中无名牌呈现。

角色在 `dialogue/characters/`。`named_speaker.gd` 让 Display Name 支持 `i18n/strings.csv` 的 `SPEAKER_*` 名称键，姓名及本次平板历史随语言切换。湖心终端、机器人和雷达对白已配置对应 Character。新角色可沿用该资源脚本与标准 Dialogic 角色字段，无需改 UI。文件时间线用 `LakeTerminal: 台词` 等角色标识，动态时间线给事件的 Character 指定同一资源。

平板与纸条的名称从正文资源 `dialogue/readables/*.tres` 的 Speaker 指定；设备投送记录与机组离线记录各用独立来源，所有分页共用，不把离线记录误标成 LIRA 自言自语。原 XBot 角色继续走同一右上名牌。
