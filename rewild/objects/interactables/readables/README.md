# 可复用阅读纸条

将 readable_note.tscn 拖入关卡，放在箱子、桌面等物体的表面上。纸面在局部 XZ 平面，朝向局部 +Y；抬高几毫米避免与承载表面重叠。

在 Inspector 的 Content 指定一份 ReadableNoteContent 资源。正文放 dialogue/readables/，每张不同纸条使用独立资源；同一正文的重复实例可共享资源。坠机点第一张使用 crashsite_cargo_note.tres，正文有意留空。

- Text Zh / Text En：中英文正文，可换行；英文留空时回退中文。
- Translation Key：可选，填写 i18n/strings.csv 中的键以使用现有翻译体系，优先于直接正文。
- Timeline：可选，填写正式 Dialogic 时间线路径时替代直接正文，支持更复杂剧情。
- Radius：交互提示筛选距离；场景自带 ReadRange 球形范围，调整范围时同步修改球形半径。
- One Shot：默认关闭，可反复阅读。

沿用现有对话 UI、玩家冻结/恢复、最近对话目标筛选、交互按键重绑定和按下反馈。阅读不依赖清理权限，不修改任务进度，也不授予终端或装备。空正文使用不可见占位字符，仍能打开对话框并正常推进关闭。

首张纸条位于 meadow_hand 场景 Water/CrashsiteOutpostV2/Cargo_Box_034/CrashsiteCargoNote。原始模型资源不作修改。SoftSparkles 仅使用六个低速小光点，不使用大范围光源。