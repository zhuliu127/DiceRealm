# 骰境 TRPG v2.38.0+108 增量系统设计与施工单（P13 / 第 10 期）

> 架构师：高见远（software-architect） · 精简施工设计（目标 300–500 行） · 全程中文
> 源码根 ROOT：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`（全部绝对路径）
> 上游：`docs/p13_incremental_prd.md`（9 条需求）、`docs/p12_incremental_design.md`（v1.1 契约风格）、`.workbuddy/memory/2026-11-16.md`（P22 三真因 + 实机铁证）
> 版本 `2.37.0+107` → **`2.38.0+108`**（本次实测 `pubspec.yaml:19` / `app_version.dart:15,18` 仍为 2.37.0+107，尚未升）。
> **纪律**：本阶段只读调研 + 写本文档；未改任何 `.dart` / 测试 / `pubspec.lock` / 版本号，未运行 `flutter` / `dart`。

---

## 0. ★ SAVE-1 根因结论（一票否决项 · 唯一主修法）

### 0.1 实机铁证（主理人 diceA 亲测，2026-11-16）
- 包 `com.teaegg.dice_realm` v2.37.0，userdebug 模拟器 `adb root` 后读 `//data//data//com.teaegg.dice_realm//app_flutter//room_saves//`。
- `room_saves/` 存在且可写（`drwx------ u0_a210`），但**只有 1 个文件 `P7NUR5.json`（513 B，mtime 11-11 06:16）**，目录 mtime 也停在 11-11。
- **判定：用户测一局后零新文件落盘，连 `saveOnOpen` 开局档都没有 → 不是「写进去 list 看不到」，而是 `store.put()` 从未作用到文件后端。**

### 0.2 读码复核（逐条核实主理人线索）

| 线索 | 裁定 | 精确落点 |
|---|---|---|
| `main.dart:58-66` 装 `FileRoomSaveStore` + `loadSync` | **对，但 `:89` 有静默 catch** | `main.dart:50 await _installRoomSaves()`；`:60 getApplicationDocumentsDirectory()`；`:64-66 new FileRoomSaveStore(dir).loadSync() → installRoomSaveStore(store)`；**`:89 catch(_){}` 吞掉一切异常 → 保持 `InMemoryRoomSaveStore`（`room_boot.dart:91`）** |
| `file_room_save_store` 编码/解码往返 | **对，无 bug** | `isSafeKey:96` 仅 `[A-Za-z0-9_-]`；`isStructuredSlotKey:120` 放行 `auto/share/<code>/<tail>` 三段；`_fileNameKeyOf:132`（`~sk~<hex(utf8)>`）、`_decodeFileNameKey:144`、`_fileFor:162`；`put:213` 校验后 `_enqueueWrite`；`get:225`/`list:232` 用逻辑键。房号 `P7NUR5` 过 `isSafeKey`，历史能落盘已证。 |
| 入口页 `_store` 6 处注入 | **对** | `room_entry_page.dart:172 _store => widget.saveStore ?? roomSaveSlots`；`:259/317/453/510/634/664` 全传 `saveStore: _store`；`app.dart:140/147` 构造入口页不传 saveStore → 用全局 `roomSaveSlots`。 |
| `saveOnOpen` / `autoSave` 门禁 | **对，但非根因** | `room_save_syncer.dart:126 saveOnOpen`：`!isKp‖_busy‖code空‖store空‖房号键已存在` 全 return false；`autoSave:201` 同门禁 + `:209 if(data==null) return false`。 |
| `host.save()` / `exportSave()` 返回 null | **部分对，已证伪** | `room_model_save.dart:71 host.save()` **恒返回非空 Map**；`room_session_local.dart:326 exportSave => role==kp ? host.save() : null`；**`CloudHostingSession extends LocalLoopbackSession`（`room_session_cloud.dart:34`）继承真实现** → 云端 KP 也能存。恒 null 的是 `room_session_remote.dart:145` / `room_session_cloud.dart:181`（**玩家非权威视角**，设计如此），P22 证伪成立，不能当根因。 |
| ticker 启动 | **对** | `room_save_syncer.dart:108 startTicker`（仅 KP）；`room_entry_page.dart:1123` 在 initState 调；`:1129-1133` post-frame 调 `onStateChanged()` + `saveOnOpen()`；`:1173 dispose stopTicker`。 |
| `put` 需 flush | **非本次根因** | `put:212` `_enqueueWrite` 异步写盘（`_writeNow:276` 原子 tmp→copy），`flush():256` 存在但无人调用；一局 10 分钟足以来得及，不足以解释「零文件」。 |

### 0.3 ★ 唯一主修法（给出决断，不列选择题）

**根因判断（最可能一条）**：**生产文件后端在真机未被安装，全局 `roomSaveSlots` 仍是 `InMemoryRoomSaveStore`。** `main.dart:89` 的 `catch(_){}` 把 `_installRoomSaves()` 中任一异常（`getApplicationDocumentsDirectory()` 插件异常 / `loadSync()` 抛 / 目录不可写 / 后续 `installCloudBackupRuntime` 等）一律吞掉；只要异常发生在 **`:66 installRoomSaveStore(store)` 之前或之内**，全局 store 就保持内存实现 → 所有 `put` 只写内存、磁盘一个文件都不产生 → **完美解释「目录在、老档在、测试全绿、真机零新文件、UI 列表（同内存实例）当时能看到但重进就空」**。P12/P22 两期都没动这个 catch，所以连续两期「测试绿、真机丢」。

**为什么这是唯一能同时解释全部现象的因果链**：
- 编码链（`~sk~`/`isStructuredSlotKey`）若有 bug → 老档也不会在，且单元测试会红（实际 2538 绿）；排除。
- `exportSave()==null` → 只有 KP 存不下，但老档是 KP 写的；且 `host.save()` 恒非空；排除。
- `startTicker` 未启动 / `saveOnOpen` 门禁 → 只能解释自动档缺失，解释不了**用户手动点「存档槽保存」也没落盘**（`saveNow:148` 直接 `store.put`，不经过这些门禁）；排除。
- **store 是内存实例** → 手动、自动、开局、终态**全部** put 都进内存不落盘，**且 UI 列表与保存共用同一内存实例所以当下看着"有"、杀进程/重进即空** —— 与用户全部描述一致。

**最小修法（三步，叠加在 P22 成果之上，不回退任何已修机制）**：
1. **让安装失败可见 + 兜底重试**（`main.dart:58-93`）：`catch(e)` 不再空吞，`lastError` 落到可诊断处（repo 已有 `lastError` 口径）；把 `installRoomSaveStore(store)` **前移到 try 的最前面**（紧跟 `dir` 构造、`loadSync` 之前——即使 `loadSync` 抛错，文件后端也已生效）；`loadSync` 自身已有内部 try（`:199`），不会再向外抛。
2. **消除静默失败**（`room_save_syncer.dart:201-242` / `room_controller.dart:132-156`）：`store.put()` 后检查 `store is FileRoomSaveStore && store.lastError != null` → 写 `syncer.lastError` 并经 `controller.notice` 给出可见提示；`autoSave`/`saveNow` 返回 false 时均带 `lastError` 原因（当前 `:236 catch` 已有，但 store 静默拒写路径没有）。
3. **诊断日志（施工前置，写进施工单 T0）**：在 `autoSave`/`saveOnOpen`/`saveNow` 各加一行 `debugPrint('[SAVE] ...')` 输出 `runtimeType(store)` / `code` / `data!=null` / `resumeKey` / `store.lastError`；**工程师先在 diceA 跑一局抓这行**。若日志显示 `runtimeType=InMemoryRoomSaveStore` → 主修法 1 命中；若已是 `FileRoomSaveStore` 但仍零文件 → 转查 `lastError`（此时按数据分支：编码/写盘异常），**不得跳过日志直接改码**。

> **验收铁律**：以上修法完成后，仍必须由 QA 按 PRD §6.1 十项在 diceA/diceB **双端真机逐项打勾**；判据是 `room_saves/` 出现本次房号/时间戳新文件（`~sk~<hex>.json` 或房号键 `.json`）、mtime 正确、`cat` 出 `meta.code` 正确，而非 UI 列表或 widget test。任一未过 → SAVE-1 不通过、本期不宣称修复。

### 0.4 新风险裁决

| # | 风险 | 裁决 |
|---|---|---|
| **R1** | 生产/测试后端行为分叉（P22 新坑 #2） | 至少 1 条测试走真实 `FileRoomSaveStore`（`dart:io` 临时目录），与内存后端行为比对；本条为 T5 验收项，不是可选项 |
| **R2** | `main.dart:89` 静默 catch 掩盖安装失败 | 见 §0.3 主修法 1；`installRoomSaveStore` 前移 + `lastError` 可见；禁止继续空吞 |
| **R3** | `put` 异步写盘无 flush，进程骤停丢档 | 本期加 `autoSave`/`saveNow` 出口 `flush()`（文件后端）兜底；不改 P22 写盘机制本身 |
| **R4** | 玩家侧 `exportSave()==null` 是设计 | 不得为「让玩家本地也能存全量」去改 `RoomSession.exportSave` 契约（会破坏权限分族）；玩家端继续走 `onSharedSave` 落盘 |
| **R5** | 存档键大小写 | 沿用 `resumeKeyOf(code)=toUpperCase()` 单一真源；云端小写房号与 LAN 大写归一，凭据仍走 `loadRecentCredentialFlexible`，零改动 |

---

## 1. 实现方案与框架选型

沿用 Flutter / Dart 现有栈，**零新增依赖**。权威端 `host.save()` 产快照 → `saveStore.put`（文件后端编码落盘）→ `save.share` 广播 → 各端 `onSharedSave` 落盘。存档修法只在 `main.dart` / `room_save_syncer.dart` / `room_controller.dart` 三个文件的既有函数体内叠加诊断与兜底；其余 4 项按 PRD 白名单局部改动。不新增 action / 事件 / 意图；契约 `kRoomPolicy 62` / `RoomEvt 28` / `RoomIntent 13` 逐字不变。

---

## 2. 文件清单（性质 / 需求号 / 热点独占）

| 相对路径（`lib/` 下） | 需求 | 性质 | 热点 | 摘要 |
|---|---|---|---|---|
| `main.dart` | SAVE | 改 | ★ | `:58-93` catch 可见化 + `installRoomSaveStore` 前移 |
| `ui/room/room_save_syncer.dart` | SAVE | 改 | ★ | `autoSave`/`saveOnOpen`/`onStateChanged` 加诊断与 store 失败提示；不动 P22 机制 |
| `ui/room/room_controller.dart` | SAVE | 改 | ★ | `saveNow:148` put 后失败可见 + flush 兜底 |
| `repo/file_room_save_store.dart` | SAVE | 核/改 | ★ | 编码链只读核对；如需加 `flush` 调用点不在此文件 |
| `ui/room/room_entry_page.dart` | SAVE | 核 | — | 6 处注入与 `_reloadSaves` 只读核对，不回退 |
| `ui/room/widgets/gp_pl_sketch.dart` | SKETCH-1/2/3 | 改 | ★ | 扁平点集 → 分段笔迹、上限可见、按段擦除 |
| `ui/room/painter/stroke_painter.dart` | SKETCH/KPBOARD | 改 | — | `BoardPainter:188` 支持分段绘制（兼容旧扁平点） |
| `ui/room/room_ui_local.dart` | SKETCH | 改 | — | 手绘板草稿/上限提示本机态 |
| `ui/room/widgets/gp_kp_players.dart` | KPBOARD-1 | 改 | — | `:298-302` 补 `child: CustomPaint(BoardPainter(...))` |
| `ui/room/widgets/gp_kp_left.dart` | MAP-1 | 改 | ★ | 删地图 tab + `_mapPanel`，tabs 3→2，索引重映射 |
| `ui/room/widgets/gp_combat_list.dart` | COMBAT-2/3 | 改 | ★ | 滚动/手势、玩家攻击入口、参战者显示 |
| `ui/room/widgets/gp_combat_strip.dart` | COMBAT-1/2 | 改 | — | `isMyTurn` 门控、顺序条可拖 |
| `ui/room/view/combat_view.dart` | COMBAT-1 | 改 | — | `combatRows(isKp:false)` 玩家裁剪态怪物仅名字 |
| `ui/room/sheets/sheet_combat.dart` | COMBAT-3 | 改 | — | 玩家攻击弹窗（武器含肉搏、防守方选怪） |
| `domain/room_model_actions_combat.dart` | COMBAT-3 | 改 | ★ | `check.opposed`/`combat.attack` 上层编排（不改规则函数） |
| `domain/room_rules_combat.dart` | COMBAT-3 | **禁改** | — | `:148 _resolveAttack` 规则与 rng 顺序逐字不动 |
| `domain/data/skills.dart` / `occupations.dart` / `test/oracle_*` | — | **禁改** | — | GENERATED / 规则契约 |
| `ui/room/sheets/sheet_save_slots.dart` / `sheet_kp_panel.dart` / `room_exit.dart` / `room_lobby_page.dart` | SAVE | 核 | — | 各手动入口只读核对，不改 P22 机制 |

波次：Wave0 = SAVE 取证+修复（独占最前）；Wave1 = SKETCH / KPBOARD / MAP / COMBAT 按文件集并行；Wave2 = 测试 + 真机验收。

---

## 3. 数据结构与接口（要点）

- **SAVE**：`store.runtimeType` / `FileRoomSaveStore.lastError` 纳入诊断；`resumeKeyOf(code)` 既有单一真源不改；不新增存档字段。
- **SKETCH**：`BoardStroke = {pts:[{x,y},...], id}` 分段结构；`INTENT.BOARD{strokes:<segments>}` 载荷兼容旧扁平点集（旧点按单段读入）；上限 `kBoardMaxPoints=4000` 按**整段丢弃最早段**并发可见提示。
- **KPBOARD**：`showFullscreenReader(child: CustomPaint(painter: BoardPainter(hostRead.boardBySeat[seat]['strokes'])))`，不读 `state.board`。
- **COMBAT**：复用 `combat.attack` / `combat.damage` / `check.opposed` + `RoomConfirm.kp`；门控 `isMyTurn(state, seat)`（`combat_view.dart:109`）只改 `enabled`、按钮始终渲染；攻击载荷含 `defender.value`（KP 补值，1–100）；`_resolveAttack`（`room_rules_combat.dart:148`）不改；不新增 action/事件/意图。
- 类图/时序图要点已内联在 §0.3 与施工单；不另附长图（按精简要求）。

---

## 4. 其余 4 项：精确锚点 + 改法 + 禁改（每项三行）

**SKETCH-1/2/3**（`widgets/gp_pl_sketch.dart`）
- 行号：`_pending:88` / `_commit:108-114`（`take(4000)` 静默截断）/ `_onPanStart:144-154` / `_onPanUpdate:162` / `_onPanEnd:168` / `eraseBoardPoints:48`（逐点 tol 0.03）/ `BoardPainter:188`。
- 改法：画笔 panStart 新建段、panEnd 整段提交一次 intent（对齐 `gp_map_stage.dart` 的 `map.strokes.set` 整笔口径）；超 4000 丢最早**整段** + 面板显示「已达上限，最早笔迹已移除」；橡皮改按段擦（复用 `eraseStrokeSegments` 思路，容差 0.03），抬手提交后不回弹。
- 禁改：不动 `stageNormOf` 归一化；不动 `RoomIntent.board` 枚举；旧扁平点集必须可读入。

**KPBOARD-1**（`widgets/gp_kp_players.dart`）
- 行号：`:293-302`「手绘板」`RoomTap.onTap → showFullscreenReader` 只传 `title`/`text`，漏 `child`；`room_sheet.dart:121-142` 的 `FullscreenReader` 支持 child。
- 改法：补 `child: CustomPaint(painter: BoardPainter(hostRead.boardBySeat[seat]['strokes']))`（`boardBySeat` 取数口径同本文件 `:63/:109`）；保留标题与笔数文字。
- 禁改：绝不读 KP 视角恒空的 `state.board`；不改 `GpKpPlayersKeys.board(seat)`。

**MAP-1**（`widgets/gp_kp_left.dart`）
- 行号：`:102 tabs:['地图','NPC·怪物','素材']`、`:109 index:leftTab`、`:115 equalWidth:true`、`:118-120` 三分支、`:125 标题`、`:136-175 _mapTab`。
- 改法：tabs 改 2 项、删 `_mapTab` 分支与函数、leftTab `0=NPC·怪物/1=素材`（旧 2→0）、标题改「NPC / 素材」、`equalWidth:true` 保留（两等宽）。
- 禁改：静态锚点表守恒（`table.length`/`noAnchor` 按 P22 口径同步核算，删符号=编译期假红）；`RoomKeys.action` 字面量不动；玩家视角零变化；不补回「情况标记层」（Q8）。

**COMBAT-1/2/3**（`gp_combat_list.dart` / `gp_combat_strip.dart` / `view/combat_view.dart` / `domain/room_model_actions_combat.dart`）
- 行号：`combat_view.dart:43 combatRows(isKp:)`、`:109 isMyTurn`；`gp_combat_list.dart:109` 取 rows、`:162 GpCombatStrip`、`:289 Expanded/SingleChildScrollView`（COMBAT-2 手势冲突点）；`room_rules_combat.dart:148 _resolveAttack`；`room_model_actions_combat.dart:44 combat.damage` / `:46 combat.attack`。
- 改法：① `combatRows(isKp:false)` 对怪物只留名字（沿用 `hpPublic`/`syncFor` 裁剪 + P12 `visibleToPlayers` 过滤，Q9）；② 展开态下方栏位用可滚动父 + 去掉抢占手势的 `NeverScrollableScrollPhysics`/内部 `InkWell` opaque 命中，保 `GpCombatKeys.strip` 命中；③ 玩家攻击按钮仅 `isMyTurn` 时 `enabled=true`（始终渲染）、甲方固定本人、武器含肉搏斗殴（斗殴技能、`1D3+DB`）、防守方只列怪物、复用 `RoomConfirm.kp` pending→KP 选反击/闪避/不防御→补值→`_resolveAttack`→`combat.damage` 扣 hp/down→PUBLIC。
- 禁改：`_resolveAttack` 与 rng 消耗顺序（§6.3 九条边界）、`oracle_*`、契约 62/28/13；不新增 action/事件/意图；门控只改 `enabled` 不撞 T-30 探针。

---

## 5. 有序任务列表（施工单）

| 任务号 | 需求 | 文件集 | 依赖 | 实施顺序 | 独占要求 |
|---|---|---|---|---|---|
| **T0** | SAVE 取证 + 诊断 | `main.dart`、`room_save_syncer.dart`、`room_controller.dart`（各加 1 行诊断日志） | 无 | **Wave0 最先** | 存档三文件单 worker 独占。**取证未出结论前不许改存档修复逻辑**；先用 debugPrint 在 diceA 抓 `runtimeType(store)` / `code` / `lastError` |
| **T1** | SAVE 主修法 | 同上三文件 + `repo/file_room_save_store.dart`(核) | T0 日志结论 | Wave0 | 同 worker 续做；按 §0.3 三步叠加；P22 机制零回退 |
| **T2** | SAVE 后端同款测试 | `test/p13_save_file_backend_test.dart`(增)、`test/p20_offline_no_regression_test.dart`(核) | T1 | Wave0 | 至少 1 条走真实 `FileRoomSaveStore`；契约计数零漂移 |
| **T3** | SKETCH-1/2/3 | `gp_pl_sketch.dart`、`stroke_painter.dart`、`room_ui_local.dart` | 无 | Wave1 | 手绘板三文件单 worker 独占 |
| **T4** | KPBOARD-1 | `gp_kp_players.dart` | T3（BoardPainter 分段签名） | Wave1 | 与 T3 对齐 BoardPainter 构造 |
| **T5** | MAP-1 | `gp_kp_left.dart`、`room_ui_local.dart`(leftTab) | 无 | Wave1 | 锚点表守恒核算；与 T4 不同文件可并行 |
| **T6** | COMBAT-1/2 | `gp_combat_list.dart`、`gp_combat_strip.dart`、`view/combat_view.dart` | 无 | Wave1 | 战斗 UI 三文件单 worker 独占 |
| **T7** | COMBAT-3 | `sheet_combat.dart`、`room_model_actions_combat.dart`、`domain/room_rules_combat.dart`(禁改核) | T6 | Wave1 | 与 T6 串行（同战斗域）；规则函数零 diff |
| **T8** | 全量回归 + 双端真机验收 | `test/*`、`docs/` 验证报告 | T0–T7 全绿 | Wave2 | QA 主导；SAVE §6.1 十项双端打勾为硬关卡 |
| **T9** | 版本 + 出包 | `pubspec.yaml`、`app_version.dart`、出包脚本 | T8（存档十项全过） | Wave3 | Q12：存档未全打勾前不出包 |

> 存档任务 T0→T1→T2 严格串行且排最前；工程师已并行开工其余项不冲突（文件集与存档零重叠）。

---

## 6. 共享知识 / 跨文件约定

- **Key 命名**：新增键沿用组件前缀 `ValueKey<String>`，不挂 `RoomKeys.action(...)` 锚点；既有 Key 常量/枚举成员一个不删（删符号=编译期假红）。
- **本机态**：手绘板草稿/上限提示放 `RoomUiLocal`；拖动 offset / 全屏态不进 state/存档/出站计划。
- **裁剪态**：玩家 `combatRows(isKp:false)` 怪物仅 `{id,name}`，无 `hp/hpMax/armor/value`；遵守 `hpPublic` 与 P12 `visibleToPlayers`。
- **契约**：62/28/13、静态锚点表、`oracle_*`、GENERATED、`FROZEN=4` 全部零改动；COMBAT 门控只改 `enabled`。
- **textScaler**：新增「攻击对抗」按钮、两 tab、战斗栏位在 1.3/1.5/2.0 三档无溢出；固定尺寸控件用 `MediaQuery.withClampedTextScaling(maxScaleFactor:1.0)` 只包子树，禁 `ClipRect` 硬裁。
- **测试口径**：零 diff = `app_version_test` / `oracle_*` / 契约计数 / `room_rules_combat._resolveAttack`；「更强或等价」= MAP tab 数断言、SKETCH 分段断言、存档新增 `auto/<code>/open-` 槽（P22 旧用例按更强改写）。禁 skip / 放宽 / `findsOneWidget→findsWidgets`。
- **版本链路**：三处同步 `2.38.0`/`108`；`app_version_test.dart` 零 diff；存档十项打勾前不出包。
- **存档真机责任**：QA 留存房号 / 槽键 / 落盘文件名 / mtime / 续玩前后状态摘要；判据以真机目录文件为准，非 UI 列表、非 widget test。

---

## 7. 待明确事项

- PRD Q1–Q13 均按推荐默认值推进，无需用户裁决；Q3/Q4 手绘板改分段结构（用户已明确），Q7 tab 索引重映射、Q12 存档未过不出包按默认。
- **新风险**：若 T0 日志显示 store 已是 `FileRoomSaveStore` 仍零文件 → 主修法 1 不成立，转向 `lastError` 分支定位编码/写盘异常（不得跳过日志直接改码）；此分支需主理人携 diceA 实测数据再裁决。
- 静态锚点表 `table.length`/`noAnchor` 精确数字由 T5 施工时读 `room_ui_permission_test.dart` 现值与 P22 守恒式核算后确定，本文不臆造具体数值。

---

> **交付边界**：本文档为精简施工设计。本阶段未改源码/测试/lock/版本号，未运行 `flutter`/`dart`。SAVE-1 的完成判定以 diceA/diceB 真机 §6.1 十项打勾为唯一依据；任一未过，本期不得宣称存档已修复。
