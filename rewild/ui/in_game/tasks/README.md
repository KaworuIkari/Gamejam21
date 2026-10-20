# 行动终端

- `terminal_ui.tscn/.gd`：右下角入口与 `task_terminal`（Tab）输入路由；由暂停菜单创建，对话、暂停和切场景期间隐藏入口。左上角 HUD 显示混沌能量模块充能与各区域清理度，顶部只保留能力解锁提示（任务开始/完成提示已移除，见 `dialogue/backup/README_备份.md`）。
- `task_page.tscn/.gd`：终端页面，两栏：
  - **混沌能量模块**：充能 = 湖泊、森林、山地、工厂四个区域清理度的平均值（`levels/meadow_hand/battery_charge.gd`），未满时提示“混沌能量模块充能中”，满 100% 后取得混沌能量模块。
  - **装备升级**：已清理垃圾即材料（减去已花费），可升级水枪射速与水箱容量，各 3 级、每级 5 份材料（`systems/upgrades/water_gun_upgrades.gd`）。
  布局在场景里改；行由脚本填充，文本在 `i18n/strings.csv` 的 `TERMINAL_*`、`UPGRADE_*`。
- `ui/theme/terminal/terminal_theme.tres`：独立终端主题，复用 `ui/fonts/fusion-pixel-12px.ttf`；24 / 36 / 48 像素字号，不改全局主题。
- `pause_menu.gd`：暂停与鼠标显示的唯一负责人；终端通过 `open_terminal/close_terminal` 接入。Esc 优先关闭终端，Tab 使用独立输入动作，忽略键盘连发，对话期间不拦截原有 Tab 跳过。
- 设置中可重绑定行动终端按键，入口同步显示实际绑定。页面采用现有 UIScaler，不叠加第二次缩放；窄屏时两栏改为上下排列。

## 终端窗口与数字雨
外框使用 TerminalWindow 局部主题（6px 直角边框、8px 内沿），标题栏独立固定，内容区滚动条保留槽位。数字雨在 `ui/theme/terminal/digital_rain.gd`：纯绘制层、不接收输入，30fps 重绘上限，页面隐藏时停止处理，暂停期间仍可运行。可通过节点的 intensity / fall_speed 调整强度与速度；fall_speed=0 可静止显示。

取出混沌能量模块后，`task_page.gd` 复用场景内的 BatteryStatus 标签显示“当前目标”，随 `radar_coordinates`、`boat_coordinates_loaded`、`boat_battery_installed` 更新为前往雷达站／前往港口／安装混沌能量模块／确认出发。提前取得坐标时直接提示港口；无需返回雷达重复操作。文字使用 `i18n/strings.csv` 的 `TERMINAL_NEXT_*`，布局仍在 task_page.tscn 中维护。

左上充能 HUD、区域标签和解锁提示的布局在 terminal_ui.tscn 中维护；Restoration 的上边距 48 为全局 FPS 留出空间。内部 battery 及相关事件名保持不变。
