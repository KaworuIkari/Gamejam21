# 可复用阅读物

纸条继续使用 `readable_note.tscn`；平板使用继承它的 `readable_tablet.tscn`，共享交互、最近目标筛选、按键重绑定及现有对话 UI。平板外形由简单网格组成，不新增贴图。纸条原有场景和其他关卡引用保留。

正文资源放 `dialogue/readables/`。`ReadableNoteContent` 的 Translation Key / Text Zh / Text En 仍供纸条使用；平板按 Page Keys 的顺序读取 `i18n/strings.csv`，每个键是一页。`TABLET_POWER` 为独立开机页，其余 `TABLET_DELIVERY_*`、`TABLET_CREW_*` 保存中英文正文。语言切换同步当前页和本次阅读历史，保留逐字显示进度。

主场景 `levels/meadow_hand/meadow_hand.tscn` 中，两块平板分别挂在 `Enviroment_permanent/CrashSite/CrashsiteOutpostV2/Cargo_Box_034/CrashsiteDeliveryTablet` 和 `Cargo_Box_038/CrashsiteCrewTablet`，随箱子一起移动。第一块沿用 `crashsite_cargo_note.tres`，第二块用 `crashsite_crew_tablet.tres`；原始机舱模型不改动。

每块平板的 Read Event 独立配置：`cabin_delivery_read` / `cabin_crew_read`。最后一页确认结束时才首次上报；中途退出不计数，重读不重复计数。已读后停止小光点，提示改成重读。记录随现有任务数据保存。Radius 和 ReadRange 球半径保持一致；One Shot 保持关闭以允许重读。

任务顺序与旧存档迁移入口见 `quests/README.md`，流程在 `levels/meadow_hand/cabin_story.gd`，不在阅读物内硬编码任务顺序。

平板、终端与其他对话统一使用 `dialogue/styles/UI.tres` → `ui/CustomUi/custom_ui_.tscn`，不显示人物头像。底部对话框保持原高度，较长内容通过 Page Keys 分页，最大字号下也不拉高面板；统一的尺寸和按钮入口见 `ui/CustomUi/README_对话UI.md`。

正文资源的 Speaker 可指定 `dialogue/characters/` 下的角色或记录来源，所有页面与阅读历史共用该名称；显示位置统一为对话框右上角。设备投送记录用 DeliveryRecord，机组离线记录用 CrewLog。新记录无需修改阅读 UI。
