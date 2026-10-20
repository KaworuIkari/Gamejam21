# 游戏流程 · 任务系统 · 场景资产分类

> 来源：手绘地图草图 + 设计修订（v2）+ `docs/story/ideas.md` + LIRA 档案（ENV-734-91）。
> 用途：交给实现方（GPT）制作 `systems/tasks/` 任务系统与场景资产。
> 标 **[建议]** 的是对设计的补充提议，标 **[待确认]** 的是还没定的点，实现前请和设计确认。

---

## 1. 核心概念

- 玩家是 **LIRA**（地貌与生态界面再生助理），在一片被垃圾封住的沙质洼地里醒来。
- 整个世界只有北方一处还有水。LIRA 的工作是把水一路引回来：**清堵 → 救动物 → 水流向下一个区域 → 浇灌变绿**。
- 能力随进度解锁，每个能力打开下一片区域：

| 顺序 | 能力 | 获得位置 | 作用 |
|---|---|---|---|
| 初始 | **清除**（拆除子程序） | 自带 | 清理堵塞物、垃圾、残骸（Clearable） |
| 第 3 步 | **游泳** | 湖水注满后自然可用 | 游到湖心岛 |
| 第 3 步 | **水枪** | 湖心终端 | 浇灌枯地、枯树，让它们复苏（Recoverable 中的植被） |
| 第 4 步 | **喷气背包** | 东部绿洲 | 上升到西部高山 |
| 第 5 步 | **拆除授权** [建议] | 高山顶净化完成后 | 允许清除洼地外的大型垃圾墙 |

- 每完成一个主线节点 → `WorldStages.advance()` → 绿化从焦点扩散（已有 `GrowthMap` / `GrowthProp`）。

---

## 2. 地图区域

| 区域 ID | 名称 | 方位 | 初始状态 | 最终状态 |
|---|---|---|---|---|
| `basin` | 沙质洼地 | 西（偏南） | 干沙地，被垃圾墙围住，看不到外面 | **海滩**，垃圾墙拆除后面向大海 |
| `lake` | 中心湖 / 湖心终端 | 中 | 干涸湖床，湖心岛上的终端发着微光，但走不上去 | 湖水注满，中心绿洲 |
| `spring` | 北方水源 / 绿洲 | 北 | 世界上唯一的水源和一小片绿洲，水口被堵住 | 水源畅通，河道流向湖心 |
| `east` | 东部绿洲 | 东 | 干涸，有一只受困的小动物，喷气背包在这里 | 湖水流入后复苏 |
| `peak` | 西部高山 | 西 | 走不上去（峭壁），山顶有受困的小动物 | 山顶净化，可以俯瞰大海 |

水流路线：`spring → lake → east` 和 `lake → peak/西侧`；最终 `basin → 大海`。

```
            [spring 北方水源]
                   │ 河道
[peak 西部高山] ←─ [lake 湖心终端] ─→ [east 东部绿洲]
       │
[basin 沙质洼地] ═垃圾墙═ 大海
```

---

## 3. 主线流程

世界阶段：`stage_1_wasteland` → `stage_2_revival`（终端启动）→ `stage_3_golden`（高山净化完成）→ **`stage_4_coast`**（海滩，[建议] 新增）。

### 第一步 · 洼地苏醒 — `basin → lake`
- LIRA 在西部沙质洼地醒来。四周是垃圾堆成的墙，看不到外面（**先展示，但现在拆不动**，为结局埋伏笔）。
- 教学：移动、交互、用“清除”清掉几块小垃圾，打开往北的路。
- 往北爬上岸，远远看到中心湖里发着微光的终端，被吸引过去。
- 湖已干涸，无法到达湖心岛。终端只能远程读到一句提示，把玩家引向北方的水源。
- **为什么没水就上不了岛** [建议，选一种]：
  - A：湖心岛是一根高石柱，唯一的上岛点是高处的码头/梯子，只有水位升起后游过去才够得到。（推荐，和“游泳”能力衔接最自然）
  - B：湖床是有毒淤泥/流沙，踩上去会被弹回岸边。
- **任务 `main_01_awaken`**
  1. 苏醒（对话）
  2. 清除洼地出口的小垃圾（清除 ×3）
  3. 走到湖边（进入 `lake`）
  4. 观察湖心终端（交互：远程扫描）→ 指向北方

### 第二步 · 北方水源 — `spring`
- 北方是全图唯一有水的地方，有一小片绿洲。水口被垃圾和落石堵住。
- 清掉堵塞 → 救出困在里面的小动物 → 水流顺着河道流向中心湖。
- 河道放水的过场：镜头跟着水流一路到湖心，湖水开始上涨。
- **任务 `main_02_spring`**
  1. 抵达北方绿洲
  2. 清除水源堵塞物（清除 ×N）
  3. 解救小动物（清除笼子/压住它的残骸）
  4. 观看水流向湖心（自动）

### 第三步 · 启动湖心终端 — `lake`
- 湖水注满后，LIRA 可以游到湖心岛，启动终端。
- 终端上线 → 中心绿洲复苏（`stage_2_revival` + `BLOOM`），湖里出现鱼（已有 `aquatic_animal_spawner`）。
- 获得 **水枪**：可以浇灌枯地和枯树让它们复苏。
- 终端打开两个闸口，水流向东、西两个区域，同时在地图上标出东部绿洲和西部高山。
- **任务 `main_03_terminal`**
  1. 游到湖心岛
  2. 启动终端（交互 + 过场）
  3. 获得水枪
  4. 浇灌湖岸的第一片枯地（水枪教学，浇灌 ×3）

### 第四步 · 东部绿洲 — `east`
- 先去西部高山，发现是峭壁上不去（或者终端直接提示“需要升空装置”）。
- 前往东部：水已经流进来，但绿洲还是枯的，需要清理加浇灌。
- 解救小动物，拾取 **喷气背包**。
- **任务 `main_04_east`**
  1. 尝试登上西部高山（进入山脚触发区 → 对话“无法攀登”）[可选步骤]
  2. 抵达东部绿洲
  3. 清除垃圾 / 浇灌枯地（清除 ×N，浇灌 ×N）
  4. 解救小动物
  5. 拾取喷气背包

### 第五步 · 西部高山 — `peak`
- 用喷气背包一段一段往上飞（中途有平台可以落脚）。
- 山顶：清除污染、浇灌、解救最后一只小动物。全部净化完成（`stage_3_golden`，`REVEAL_ALL`）。
- 站在山顶看到初始洼地外面就是**大海**。终端提示：洼地那一侧的垃圾墙可以拆开，让它变成海滩。
- **任务 `main_05_peak`**
  1. 用喷气背包登上山顶
  2. 净化山顶（清除 ×N，浇灌 ×N）
  3. 解救小动物
  4. 眺望大海（过场）→ 获得“拆除授权” [建议]

### 第六步 · 打开海滩（最终任务） — `basin`
- 回到洼地，把堵在海边的废弃垃圾全部清除。
- 最后一块拆掉后海水涌入、沙地变成海滩（`stage_4_coast`），动物们聚过来，结局。
- **任务 `main_06_beach`**
  1. 返回沙质洼地
  2. 清除全部海边垃圾（清除 ×全部，带进度条）
  3. 拆除最后的大型垃圾墙（交互 + 结局过场）

---

## 4. 对设计的建议

1. **说清楚“没水为什么上不了岛”**：干湖床照理可以走过去，玩家会觉得被骗。推荐把湖心岛做成高石柱，水位升起后才能游到码头（见第一步方案 A）。
2. **垃圾墙为什么一开始拆不了**：玩家开局就有清除能力，看到墙会想拆。建议用 LIRA 的档案设定来解释：拆除子程序只有在确认“建筑已完全废弃、无人使用”后才会解锁。玩家在山顶看到外面只有大海、确认墙后面没有人之后，终端才发出“拆除授权”。这样剧情和机制是同一个理由，结局也有分量。
3. **每个区域用同一套节奏**：清堵 → 救动物 → 水流到下一区 → 浇灌变绿。玩家很快就能懂，任务系统也可以复用同样的步骤类型。
4. **水枪的限制** [待确认]：建议加一个水箱容量，在任意水体旁自动补水。让“有水的地方越来越多”变成能感受到的进度。不想做资源管理的话，就做成无限水。
5. **喷气背包要设上限**：燃料或高度有限，只能一段段跳平台，免得玩家飞出地图边界或跳过高山的关卡设计。落地后燃料自动恢复。
6. **加一个全局净化进度**：终端里显示“净化度 xx%”，三只小动物和各区域的清除/浇灌都算进去。第五步“全部净化完毕”就是进度到 100%，不用一个一个检查。
7. **动物分区**：北方水源（小型陆地动物）、湖心（鱼，已有）、东部（小型动物）、山顶（鸟类更合适）、结局海滩（海鱼/鲨鱼，`animals/shark` 已有）。救出的动物可以跟着 LIRA，或者在已复苏的区域里游荡，作为成就感反馈。
8. **新增第四个世界阶段** `stage_4_coast`：现有三个阶段只到 Golden，海滩结局需要单独一套天空/光照（比如更开阔的海天色、海平面雾）。
9. **方位**：洼地和高山都在西边，建议把洼地放在西南、高山放在西北，这样从山顶往下看能完整看到洼地和后面的大海。

---

## 5. 任务系统规格（给实现方）

按 `ui/in_game/tasks/README.md` 的约定：逻辑放在 `systems/tasks/`，UI 只通过 `set_task_record(record)` 读取快照，存档交给 SaveManager。

### 5.1 数据结构
```
TaskDef (Resource)
  id: StringName              # main_02_spring
  title_key / desc_key: String # i18n 键，写进 i18n/strings.csv
  zone: StringName            # basin / lake / spring / east / peak
  kind: MAIN | SIDE
  steps: Array[TaskStep]
  prerequisites: Array[StringName]
  on_complete: Array[TaskEffect]

TaskStep (Resource)
  text_key: String
  type: REACH_ZONE | INTERACT | PICKUP | CLEAR | WATER | RESCUE | DIALOGUE | WAIT_EVENT
  target: StringName          # 区域 id / 物体 id / 物体 tag
  count: int = 1              # 0 表示该 tag 的全部物体（第六步“清除全部”）
  optional: bool = false
```
状态：`LOCKED → ACTIVE → COMPLETED`，同一时间只追踪一个主线任务。

### 5.2 事件（信号总线）
世界物体只发事件，不直接引用任务：
- `zone_entered(zone_id)`
- `object_interacted(object_id)`
- `item_picked(item_id)`
- `object_cleared(object_id, tags)`
- `object_watered(object_id, tags)` / `object_recovered(object_id, tags)`
- `animal_rescued(animal_id)`
- `dialogue_finished(timeline_id)`

### 5.3 完成效果 TaskEffect
- `UNLOCK_TASK(id)`
- `ADVANCE_WORLD_STAGE`（`WorldStages.advance()`）
- `GRANT_ABILITY(swim | water_gun | jetpack | demolition_auth)`
- `START_WATER_FLOW(channel_id)`（spring→lake、lake→east、lake→west）
- `SET_WATER_LEVEL(body_id, level)`（湖心注水、海水涌入洼地）
- `BLOOM_AT(node, radius)`
- `PLAY_DIALOGUE(timeline)` / `PLAY_CUTSCENE(id)`

### 5.4 主线依赖
```
main_01_awaken → main_02_spring → main_03_terminal → main_04_east → main_05_peak → main_06_beach
```

---

## 6. 场景资产三分类

### 6.1 分类定义

| 分类 | 含义 | 交互方式 | 是否存档 | 对绿化的影响 |
|---|---|---|---|---|
| **Permanent 永久** | 地形、地标、结构骨架 | 不可交互（最多扫描/对话） | 否 | 不影响；可挂 `GrowthProp(moss=true)` 只长苔藓 |
| **Recoverable 可修复** | 枯萎/损坏 → 复苏/修好 | **水枪浇灌**（植被、土地）或 **交互**（机械：终端、闸口） | 是（状态） | 复苏时原地小范围 `BLOOM` |
| **Clearable 可清除** | 堵塞物、垃圾、残骸、污染 | **清除**（按住）；可以设置需要 `demolition_auth` | 是（是否已清除） | 清除时原地小范围 `BLOOM` |

公共基类：`WorldObject (Node3D)`，字段有 `object_id`、`category`、`tags`、`zone`。
- `Clearable`：`hold_time`、`required_ability`（例如垃圾墙需要 `demolition_auth`）、清除后露出的物体
- `Recoverable`：`method = WATER | INTERACT`、`broken_scene` / `restored_scene`、`water_needed`

### 6.2 现有模型分类（`assets/models/`）

**crashsite_outpost** → 主要用在 `basin`（洼地垃圾）和 `east`
| 模型 | 分类 | 用在哪 / 备注 |
|---|---|---|
| Fuselage_Continuous, Impact_Earth_Bed, Hull_Surface_Details | Permanent | 洼地里 LIRA 苏醒处的坠毁残骸（场景背景） |
| Rock_Original | Permanent | 通用岩石、高山落脚平台 |
| Wing_Detached, Tail_Fin_Detached, Engine_Nacelle_Broken, Engine_Turbine | Clearable（需拆除授权） | **洼地垃圾墙**的大块部件，最终任务 |
| Debris_Cluster_1/2/3, Torn_Skin_Lip, Rib_Open | Clearable | 洼地出口教学、海边小垃圾 |
| Fence_Bent, Concrete_Barrier, Cargo_Box, Fence_3m | Clearable | 垃圾墙的填充物、东部障碍 |
| Dry_Grass | Recoverable（浇灌） | 枯草 → 新草 |
| DeadTree_Original | Recoverable（浇灌） | 枯树 → 活树，用于东部和高山 |
| Bulkhead_Open | Clearable | 困住动物的舱段/笼子 |
| Cargo_Case_Small | 拾取点 | 喷气背包的箱子（东部） |
| Workbench, Bench_Tools, Portable_Lamp, Lamp_Stand, Salvaged_Access_Ramp | Permanent | 洼地苏醒点的装饰，也可以作为高山中途的营地 |
| Cargo_Floor_3m, Rib_Intact, Engine_Mount, Wing_Attached_Broken, Tail_Spars, Cockpit_Fittings | Permanent | 结构和装饰 |

**industrial_relay** → 主要用在 `lake`（终端）和 `spring`（水源设施）
| 模型 | 分类 | 用在哪 / 备注 |
|---|---|---|
| Core_Pedestal + Console_Broken + Energy_Core | Recoverable（交互） | **湖心终端**（发微光 → 上线） |
| Core_Armor_Shield, Core_Broken_Cage | Permanent | 终端外围装饰 |
| Pipe_Broken_3m, Pipe_Elbow, Tank_Ruptured | Clearable / Permanent | 北方水源的堵塞（断管、破罐卡在水口）；清掉的部分用 Clearable，其余作为背景 |
| Rubble_Cluster_1/2/3 | Clearable | 北方水口的落石堵塞 |
| Machine_Wreck, Truss_Broken, Roof_Fragment, Column_Broken, Rail_Broken_3m | Clearable | 东部和高山顶的污染废墟 |
| Relay_Antenna_Bent | Permanent / 可选 Recoverable | 山顶地标（修好后可以显示全图） |
| Wall_Broken_Low/Tall, Column_5m, Floor_Tile_3m, Floor_Fractured, Catwalk_3m, Stairs_2m | Permanent | 湖心岛码头、东西闸口结构 |
| Cargo_Crate | Clearable | 通用垃圾 |
| Fern_Original, Moss_Patch | Permanent（`GrowthProp grow_in`） | 复苏后长出来，不是交互物 |

### 6.3 需要新做的资产
| 资产 | 分类 | 区域 | 说明 |
|---|---|---|---|
| 湖心岛（高石柱 + 码头/梯子） | Permanent | lake | 配合“没水上不了岛” |
| 湖面水位（干 → 满） | Recoverable（由事件驱动） | lake | 用 `water_offset` 或单独水体 |
| 河道水流 ×3（spring→lake、lake→east、lake→west） | Recoverable（由事件驱动） | — | 干河床 → 有水流，可以用 stylized_water 加流动 shader |
| 东、西闸口 | Recoverable（交互） | lake | 终端启动后自动打开 |
| 污染地面贴片（灰黑枯地） | Recoverable（浇灌） | 各区域 | 浇灌后消失，同时触发 `BLOOM` |
| 受困小动物 ×3 + 跟随/游荡行为 | — | spring、east、peak | 可以复用 `animals/chicken`，山顶建议用鸟 |
| 喷气背包（拾取物 + 角色挂件） | 拾取物 | east | |
| 水枪（拾取物 + 角色挂件 + 喷水特效） | 拾取物 | lake | |
| 海面 + 海浪 + 海滩沙材质 | Permanent | basin 外 | 垃圾墙后面一直存在，但开局被挡住看不到 |
| 垃圾墙整体（多个 Clearable 组合） | Clearable 组 | basin | 一个父节点带 tag `beach_wall`，`count = 0` 表示全部清完 |

---

## 7. 每个区域的资产配比（参考）

| 区域 | Permanent | Recoverable | Clearable |
|---|---|---|---|
| basin | 坠毁残骸、岩石、大海 | 枯草（结局后自动变绿） | 出口小垃圾 ×3、**垃圾墙**（需拆除授权） |
| lake | 湖床、湖心石柱、码头 | 终端、湖面水位、东/西闸口、湖岸枯地 | 湖底垃圾（可选） |
| spring | 绿洲原有的树、水源岩壁 | 河道水流 | 落石 + 断管堵塞、动物笼 |
| east | 地形、岩石 | 枯树、枯地（浇灌） | 废墟、动物笼、背包箱旁的障碍 |
| peak | 山体（`mountain_ring`）、落脚平台、天线 | 山顶枯树/草场 | 污染废墟、动物笼 |

---

## 8. 已确认的决定（2026-10-12）
1. 湖心岛上不去的原因：**淤泥**（方案 B）。干湖床是有毒淤泥，踩上去会被推回岸边；湖水注满后才能游过去。
2. **采用“拆除授权”**：垃圾墙在山顶确认外面只有大海后才能拆。
3. **水枪有水箱容量**，需要到水边补水。
4. 三只小动物的物种：未定，最后再改（先用占位动物）。
5. **结局后可以继续自由探索。**

## 9. 浇水视觉方案（已实现）
问题：原来浇水是直接把地面从沙地贴图切到草地贴图，一块一块的，像 Splatoon。
做法：
- **浇水不直接变绿**：`GrowthMap.water()` 只写入一张“湿度图”。地面马上变暗（湿沙），这是即时反馈。
- **生长跟着湿度慢慢来**：每个湿的像素按各自随机的速度长绿，挨着已有草地的地方长得更快（从边缘往里蔓延）。水分大约 20 秒蒸发完，所以浇得透的中心会长满，边缘只长一半，自然过渡。
- **四段颜色**：沙地 → 湿沙 → 橄榄色新芽 → 草地，每段有自己的噪声边界（`ground_blend()`，在 `meadow_palette.gdshaderinc`）。
- **区域收尾**：`GrowthZone` 节点统计一个区域的绿化率，到阈值（默认 45%）后从中心 bloom，把没浇到的空隙一次补满。玩家浇水只是在“播种”，最后区域会连成一整片。这个覆盖率也直接给任务步骤“浇灌区域”使用。
- **自动补空隙（70%）**：不需要摆放 `GrowthZone`，全图都会生效。某块地周围 8 米内有 70% 以上已经是草地时，这块地会自己变湿、发芽、长满。它只会往缺口和凹进去的地方补，不会越过平直或往外凸的边缘继续扩张，所以快浇完的区域会自然补齐，剩下的小斑点不会留着。参数在 `GrowthMap` 的 Hole filling 分组里。
- **花朵**：草地长满后还要等地面干了才开花（`meadow_flower.gdshader` 里乘以 `1 - wet_at`），所以花会在浇水后 10～20 秒陆续开出来，算是一个延迟的奖励。
- **终端启动后的散落绿地**：`WorldStage` 新增了 Scattered patches 分组。`stage_2_revival` 会在 600×600 米范围内撒 30 团不规则绿地（每团由 2～4 个大小不一的圆叠成）。每团绿地都会经历和浇水一样的湿 → 芽 → 草过程，之后也会成为玩家浇水时连接的种子。想手工摆位置的话，给 `WorldStages.scatter_points` 指定一个节点，在它下面放 Marker3D 子节点，用 scale.x 控制大小。
