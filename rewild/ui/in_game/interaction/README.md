# 游戏内交互提示

`interaction_prompt.tscn` 与同名脚本负责提示布局、按键标识、语言及输入设备切换。使用 `configure(action, message_key)` 指定动作与翻译键，使用 `set_available(bool)` 指定可用状态。

翻译文本使用 `%s` 标记按键位置，例如“按 %s 交谈”。提示从 SettingsManager 读取当前绑定并显示，不固定为 F；暂停和对话期间隐藏。提示不接收点击，也不消费交互输入。

范围检测、最近目标选择、交互输入及对话生命周期由 `ui/CustomUi/dialogue_trigger.gd` 负责。触发器销毁时提示一起销毁；候选分组为 `dialogue_interaction_candidates`。

提示绘制到主视口，避免随游戏像素化 SubViewport 变粗，通过 UIScaler 跟随界面缩放。主题、字体与局部背景效果来自 `ui/theme/light/`；具体布局和视觉参数在提示场景与样式调用中调整。
