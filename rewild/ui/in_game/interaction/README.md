# 游戏内交互提示

`interaction_prompt.tscn` 与同名脚本负责提示布局、按键标识、语言及输入设备切换。使用 `configure(action, message_key)` 指定动作与翻译键，使用 `set_available(bool)` 指定可用状态。

翻译文本使用 `%s` 标记按键位置，例如“按 %s 交谈”。提示从 SettingsManager 读取当前绑定并显示，不固定为 F；暂停和对话期间隐藏。提示不接收点击，也不消费交互输入。

范围检测、最近目标选择、交互输入及对话生命周期由 `ui/CustomUi/dialogue_trigger.gd` 负责。触发器销毁时提示一起销毁；候选分组为 `dialogue_interaction_candidates`。

提示绘制到主视口，避免随游戏像素化 SubViewport 变粗，通过 UIScaler 跟随界面缩放。主题、字体与局部背景效果来自 `ui/theme/light/`；具体布局和视觉参数在提示场景与样式调用中调整。

交互反馈：共用提示观察当前绑定的按下事件，只做缩放、高亮与回弹，不消费输入。所有者接受玩家交互时调用 play_activation()，显示约 0.15 秒完成闪亮及淡出；交谈开始后仍短暂保留于对话上方，暂停或 SceneRouter 切场景立即隐藏。长按清理由 Clearable 通过 set_hold_progress() 提供真实进度，set_interactable(false) 禁止锁定对象的按下与进度反馈。进度描边位于 interaction_progress.gd，不参与容器最小尺寸计算。

长按清除专用场景：clear_hold_prompt.tscn 继承共用提示，启用 hold_to_clear 布局。仅 Clearable 引用；交谈、拾取/投掷、机关仍引用 interaction_prompt.tscn。清除提示保留 26px 字体，通过缩小外边距、键帽和间距收紧面板，使用柔和金色横向进度条；锁定目标隐藏进度条，完成时填满并沿用 0.15 秒淡出。

剧情权限：Clearable 的玩家清理与提示统一要求 Quests.terminal_unlocked()。首次接触湖心终端并完成现有首次接触流程后解锁；新游戏隐藏清理提示并禁止长按计时，读取进度时沿用已有终端能力状态。额外 required_ability 限制继续生效；水泵、交谈、拾取等其他交互不受该限制。脚本恢复场景用 clear(instant) 继续可用。
