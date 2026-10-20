# 已移除的对话与提示（备份）

主线改为“终端电池充能”后，以下对话与提示暂时停用，文本保留以便之后改写复用。

## 时间线文件（本目录）

- `core_activated.dtl`：修复小机器人后播放，原含发放雷达密钥（`Quests.grant("radar_key")`、`robot_key_received`）。原由 `levels/meadow_hand/factory_story.gd` 的 `activation_timeline` 启动。
- `core_delivery.dtl`：把激活的储能核心交给湖心终端时播放，随后上报 `core_delivered`。原由 `lake_power_station.gd` 的 `core_delivery_timeline` 启动。

两者仍登记在 `project.godot` 的 Dialogic `dtl_directory` 中（路径已指向本目录）。

## 代码拼接的对话（文本仍在 `i18n/strings.csv`）

| 原场景 | 键 | 原触发位置 |
|---|---|---|
| 草原清理提交（任务 02） | 已删除（文本见 git 历史） | 湖心终端 `_submit_meadow_cleanup`，结束后上报 `meadow_cleanup_delivered` |
| 雷达信息提交（任务 05） | `RADAR_DELIVERY_RECEIVED`、`RADAR_DELIVERY_REWARD`、`FINALE_BRIEFING_DEVICE`、`FINALE_BRIEFING_BOAT` | 湖心终端 `_submit_radar_information`，结束后上报 `radar_delivered` |
| 补领雷达密钥 | `INTERACT_ROBOT_KEY`、`ROBOT_KEY_RECOVERY` | `factory_story.gd` 的 `_check_key_recovery` |
| 雷达读取中的密钥/返回提示 | `RADAR_READOUT_KEY`、`RADAR_READOUT_RETURN` | `radar_story.gd` 的 `make_readout_timeline`（现只保留坐标一页） |

## 屏幕提示

- 任务开始/完成提示：`QUEST_TOAST_STARTED`、`QUEST_TOAST_DONE`，原在 `ui/in_game/tasks/terminal_ui.gd` 连接 `Quests.quest_started` / `quest_completed`。
- 左上角任务追踪与背包未启用提示（`JETPACK_LOCKED_*` 等“背包能量不足/供能”文本已删除，见 git 历史）。
- 湖心终端初次接触对话 `first_contact.dtl` 中关于背包交付与供能的台词已删除。

完整旧代码可在 git 历史中查看（此次改动之前的提交）。
