# 对话 UI（Dialogic 自定义布局）

所有对话界面都在 `CustomUi/` 下，由默认样式 `UI .tres` 引用 `custom_ui_.tscn`。

## 结构
- `custom_ui_.tscn` 根节点，脚本 `dialogue_layout_base.gd`
  - `StagePortraitLayer`：Dialogic 自带的站位立绘层，**默认隐藏**（join/leave/update 指令照常工作）。想在屏幕上显示大立绘：选中根节点，勾选 `show_stage_portraits`
  - `FullAdvanceInputLayer`：点击屏幕任意位置推进对话
  - `DialogueBoxLayer`（`layers/dialogue_box_layer.tscn`）：底部对话框、头像、名牌、继续箭头、角落按钮（自动 / 跳过 / 历史）
  - `ChoiceLayer`（`layers/choice_layer.tscn`）：选项按钮（最多 6 个，复用全局像素主题）
  - `TextInputLayer`（`layers/text_input_layer.tscn`）：文字输入
  - `Glossary`：Dialogic 自带词汇表弹窗
  - `HistoryLayer`（`layers/history_layer.tscn`）：对话记录
- `dialogue_trigger.gd`：可复用的触发区域组件 `DialogueTrigger`
- `dialogue_utils.gd`：安全暂停 Dialogic 的小工具（规避 Dialogic Alpha 的一个报错）

## 常改的地方
- 字体 / 字号：各图层 Inspector 的 `dialogue_font` / `font_sizes`（ChillBitmap 7px 的像素网格是 8px，字号用 8 的倍数）
- 头像：像素画头像把 `DialogueBoxLayer` 的 `portrait_smooth_filter` 关掉
- 外观：框体、按钮沿用 `ui/theme/pixel/*.png`；继续箭头是 `assets/next_arrow.png`
- 快捷键：项目设置 > 输入映射 中的 `dialogue_auto`(Q / 手柄 Y)、`dialogue_skip`(Tab / 手柄 View)、`dialogue_history`(H / 手柄 LB)、`interact`(F / 手柄 X)

## 触发对话
1. 在场景里新建节点，类型搜 `DialogueTrigger`（Area3D）
2. Inspector 填 `timeline`（如 `XBot_timeline`）；可选 `auto_start`（进入即触发）、`one_shot`（只触发一次）、`radius`
3. 玩家需在 `player` 分组（`xbot.gd` 已自动加入）。玩家靠近会出现“按 F 交谈”
4. 代码里也可以直接 `Dialogic.start("时间线名")`

## 中英台词
- 已开启 Dialogic 翻译（项目设置 `dialogic/translation/enabled`）
- 时间线每行末尾的 `#id:xx` 是翻译编号，**不要删**
- 译文在 `i18n/dialogue_xbot.csv`（keys, zh_CN, en），改完 Godot 会自动重新导入
- 新时间线：可以用 Dialogic 编辑器设置里的翻译功能自动生成编号和表格（注意它会按自己的格式另建 CSV），或参照现有格式手写：行尾加 `#id:新编号`，再在 CSV 里加对应的 `Text/编号/text` 等行
- 台词语言跟随 设置 > 语言

## 设置联动
设置 > 语言与辅助 > 对话：文字速度、对话字号、对话框不透明度（保存在 `user://settings.cfg` 的 accessibility 段）
