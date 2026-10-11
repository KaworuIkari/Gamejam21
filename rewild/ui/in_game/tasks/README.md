# 行动终端

- `terminal_ui.tscn/.gd`：游戏内右下角紧凑入口与 `task_terminal` 输入路由；由暂停菜单创建，对话、暂停和切场景期间隐藏入口。
- `task_page.tscn/.gd`：仅负责页面布局、空状态与关闭请求。当前展示一条明确标记为“演示参考”的 UI 案例，支持选择、归档空状态与演示追踪，不关联游戏流程或存档。
- `ui/theme/terminal/terminal_theme.tres`：独立终端主题，复用 `ui/fonts/fusion-pixel-12px.ttf`；24 / 36 / 48 像素字号，不改全局主题。
- `pause_menu.gd`：暂停与鼠标显示的唯一负责人；终端通过 `open_terminal/close_terminal` 接入。Esc 优先关闭终端，Tab 使用独立输入动作，忽略键盘连发，对话期间不拦截原有 Tab 跳过。
- 设置中可重绑定行动终端按键，入口同步显示实际绑定。页面采用现有 UIScaler，不叠加第二次缩放。

后续真实任务模块放在 `systems/tasks/`：任务状态通过接口与信号供页面读取，存档由 SaveManager 接入。当前不建立空管理器、不新增 Autoload、不把任务数据写进 UI。

任务显示案例集中在 `ui/in_game/tasks/task_demo.gd`，仅供页面排版参考。`task_page.gd` 的 `show_demo` 导出开关设为 false 可恢复“待编辑”空页。演示追踪每次关闭/打开页面重置；案例的 1/3 进度是固定展示值，无真实完成行为。

页面显示层提供 set_task_record(record) 接口，接收 title / description / location / steps / completed_steps 的显示快照。步骤数量可变；当前仅展示一条任务记录，批量任务列表、真实进度事件及存档接入仍由未来 systems/tasks 模块负责。主题补齐 hover_pressed/disabled，避免全局圆角玻璃样式回落。面板外框保持固定，内容在内部滚动；展开箭头与详情同步；退出提示合并在右上角关闭按钮。

## 终端窗口与数字雨
外框使用 TerminalWindow 局部主题（6px 直角边框、8px 内沿），标题栏独立固定，内容区滚动条保留槽位。数字雨在 `ui/theme/terminal/digital_rain.gd`：纯绘制层、不接收输入，30fps 重绘上限，页面隐藏时停止处理，暂停期间仍可运行。可通过节点的 intensity / fall_speed 调整强度与速度；fall_speed=0 可静止显示。无新增 Autoload 或游戏数据。
