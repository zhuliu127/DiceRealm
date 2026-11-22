# P4 增量 PRD：房间规则层（room-rules / room-model 移植）

> 本文档是**增量 PRD**，只描述 P4 相对 P0–P3 基线的新增与变更，不重写全量 PRD。
> 定位：给架构师做增量设计与任务分解的输入。所有 API、行号、边界值均**实读并在 Node VM 中加载旧版 JS 验证**，非摘要推测。

---

## 1. 项目信息

| 项 | 内容 |
|---|---|
| Language | 简体中文 |
| Programming Language | Flutter / Dart（原生重写，禁用 WebView 与 HTML 渲染）；本项目**不采用** Vite + React 默认栈 |
| Project Name | `dice_realm_p4_room_rules` |
| 文档类型 | 增量 PRD（简单档，无竞品/市场分析） |
| 工程根 | `C:\Users\60965\WorkBuddy\2026-10-08-18-34-17\dice-realm` |
| 旧版只读规格权威 | `C:\Users\60965\WorkBuddy\2026-10-08-18-34-17\coc7th-card-app\web\js` |
| 基线版本 | `2.15.0+81`；`flutter test` 572 组 0 红、`dart analyze` 干净、QA `IS_PASS: YES` |
| 落盘位置 | `dice-realm/_p4_prd.md`（本文件） |

### 1.1 原始需求复述

把旧版房间规则层的两个纯逻辑模块移植为 Dart，作为后续 P5 房间 UI、P6 局域网中继的**唯一规则出口与唯一权威状态机**：

1. `core/room-rules.js`（1591 行，全局 `window.CocRules`）→ Dart 规则服务；
2. `core/room-model.js`（7712 行，全局 `window.RoomModel`）→ Dart 权威状态机。

### 1.2 已完成基线（不重复规划）

P0 规则层（oracle 等价 1621 例）、P1 App 外壳/首页/新建角色、P2 车卡器、P3 AI 车卡 + 云分享 + 设置页。
P4 只做规则层与状态机，**不产出任何 UI、不建网络通道、不落地持久化**。

---

## 2. 范围与边界

### 2.1 P4 范围内

| 模块 | 旧版文件 | 行数 | 目标 |
|---|---|---|---|
| 规则服务 | `core/room-rules.js` | 1591 | `lib/domain/` 下的纯 Dart 规则服务；检定/状态/行动顺序唯一出口 |
| 权威状态机 | `core/room-model.js` | 7712 | `lib/domain/` 下的纯 Dart 状态机；事件协议、权限矩阵、可见性裁剪、seq 幂等、回退重放 |

### 2.2 明确不在 P4 范围（边界，架构师据此拆任务）

| 留给 | 内容 | 说明 |
|---|---|---|
| P5 | `ui/room-ui.js`(5652) / `ui/room-panels.js`(6173)、12 块布局、手绘、缩放 | P4 不产出任何 Widget、页面、画布 |
| P6 | `core/room-net.js`(1659) / `room-lan.js`(171)、Dart 原生 socket 替代 `LanServer.java` | P4 不建连接、不发包；`plan()` 只返回发送计划 |
| 本期不做 | `core/room-store.js`(529) 的持久化落地 | **但必须预留接口边界**，见 §5.10 |
| 本期不做 | 房间事件类型的**新增**、协议字段变更 | 中继层原样透传，加事件类型不用改服务端；P4 只做等价移植 |
| 本期不做 | `dice.js` 的 `d100Bonus` / `successLevel` 移植或复用 | 车卡阶段零调用预留，且有既有缺陷，见 §3 约束 C7 |

---

## 3. 约束（工程硬约束，必须写入设计与验收）

| ID | 约束 |
|---|---|
| **C1 纯 Dart** | `lib/domain` 保持零 `package:flutter` / `dart:io` / `dart:ui` 依赖。P3 已实跑验证零命中，P4 不得破坏。规则服务与状态机**不碰 DOM/网络/localStorage/文件系统**，时间、随机、持久化全部由外部注入。 |
| **C2 JS 当预言机** | Node VM 原样加载旧 JS，monkey-patch `Math.random` 为 LCG、`Date.now` 为固定时钟 `1700000000000` dump fixture；Dart 用同款 LCG（`seed * 1664525 + 1013904223 >>> 0`，`test/support/oracle.dart` 已有 `Lcg` 类）复现，逐字段深比较（键集合必须完全一致，多一个 null 键也算不一致），并断言 **`randUsed` 消耗次数一致**。 |
| **C3 注入源复用** | 随机源与时间必须可注入且**复用 `lib/domain/js_compat.dart` 已有的 `setRng()` / `setClock()`**（已实读确认存在），不得另造第二套全局注入点。Dart 侧所有掷骰入口同样接受 `opts.rng` / `opts.now`。 |
| **C4 角色卡契约冻结** | 无 `schemaVersion`，靠 `normalize()` 幂等迁移；**禁止新增/改名顶层或嵌套键**，旧版 JSON 必须无损导入。房间内 `sheet` 摘要字段集合与 `sanitizeSheet()` 白名单保持一致。 |
| **C5 写回必过 Repo** | 房间状态写回角色卡**必须经 `CharacterRepo.save(Character)`**（已确认 `lib/repo/character_repo.dart:224-225` 入口调 `applyExplicitStatusMarks()` → `normalize()` → `recalc()`）。禁止直接改 `card.status[k]` 后落盘，否则 HP=0 的濒死卡被 `recalc` 补满、P2 的 D1 缺陷原样复活。 |
| **C6 双后端** | 已有 `CharacterRepo` / `SettingsRepo` / `ShareStore` 都是「文件后端 + 内存后端」双实现，widget 测试用内存后端。P4 新增的持久化适配（若有）必须同样提供内存后端，且不得让 `lib/domain` 依赖任一后端。 |
| **C7 绕开 dice.js** | `dice.js:36-44` 的 `d100Bonus` 先对十位骰取 min/max 再组合，`ones=0`、`tens={0,1}` 时 `bonus>0` 会返回 100（应为 10），结果取反；`dice.js:47-54` 的 `successLevel` 用 `skill` 而非**本次要求阈值**判大失败。**P4 必须另建实现，不得复用、不得包装、不得委托**，且 Dart 侧不得改动 `lib/domain/dice.dart` 的既有行为。 |
| **C8 两层协议不混** | 中继层 `hub.*` / `peer.*`（`room_server.py`）↔ 应用层 `{k:'sync'\|'evt'\|'skip'\|'intent'}`。中继**不认识应用层任何字段**，原样透传；P4 只在应用层内部生效，不要求服务端改动。⚠️ 实读发现应用层是 **4 种**消息（`parse()` 在 `room-model.js:821` 接受 `sync/evt/skip/intent`），`skip` 是全局序号水位标记，不可省略。 |
| **C9 无隐式副作用** | 所有状态变更走 `apply(evt)` 单口（旧版是 `emit()` + `reduce()`，Dart 收敛为单口）。任何方法不得在 `apply` 之外直接写 `state`；回退 = 重放日志到某个 seq。 |
| **C10 兼容旧存档** | `CLOSED` 语义不得改（旧客户端当终止用）；`rollback.turn` 的 POLICY 入口虽已移除，但 `rollbackPropose/rollbackVote/rollbackCommit`、`EVT.REWIND`、`INTENT.VOTE`、`REWIND` 枚举、`case EVT.REWIND`、`state.rewind` 必须**休眠保留**，否则旧存档 reduce 走空分支、历史回退态丢失。 |

---

## 4. 产品定义

### 4.1 Product Goals（3 个正交目标）

| # | 目标 | 可度量口径 |
|---|---|---|
| G1 | **规则判定唯一且可复现** | 跑团房间内所有检定、奖惩骰、伤害/SAN 状态、行动顺序、战斗结算只由 Dart 规则服务产出；同一 `(输入, LCG seed, 固定时钟)` 与旧版 JS 逐字段一致且 `randUsed` 一致 |
| G2 | **权威状态可重放且不泄漏** | KP 端按序广播、玩家端确定性回放；未授权客户端**在字节层面收不到** KP 隐藏信息；重连/乱序/重复/回退后各端 `state` 与旧版一致 |
| G3 | **规则层可独立验证** | 两个模块可在无 Flutter、无网络、无存储的环境下被 Node-VM fixture 驱动跑完，`lib/domain` 零 Flutter/IO 命中，P5/P6 可直接消费而无需改规则代码 |

### 4.2 User Stories

| # | 场景 |
|---|---|
| US1 | As a **KP**，我想要在房间里发起一次困难/极难检定并得到与旧版完全一致的成功等级与大失败范围，so that 同一颗骰子在网页版与 Flutter 版不会判出不同结果 |
| US2 | As a **KP**，我想要把只给某位玩家的线索/暗骰结果单独下发，so that 其他玩家即使抓包也拿不到隐藏信息 |
| US3 | As a **玩家**，我想要断线重连后补齐缺失事件而不重复扣血、不重复刷聊天，so that 状态与房间历史保持正确 |
| US4 | As a **KP**，我想要回退到某个回合并同时恢复 HP/状态/地图/回合号与关联事件，so that 不是只把界面文字删掉 |
| US5 | As a **架构师/QA**，我想要用固定 LCG 与固定时钟复现任一历史掷骰与任一房间事件序列，so that 边界用例（01、100、00+0、十位骰取哪个、seq 跳号）能被确定性断言 |

---

## 5. 旧版 API 面清单（架构师拆分依据）

> 行号均指旧版 JS 源文件。`CocRules` 共 **53** 个导出成员、`RoomModel` 共 **41** 个导出成员（Node VM `Object.keys()` 实测）；`EVT` 27 项、`INTENT` 13 项、`POLICY` 61 个唯一 action（源码 62 行，`board.self` 定义两次且值相同）、`reduce` 26 个 case、`SECRET_KEYS` 7 项。

### 5.1 `window.CocRules` 导出面（`room-rules.js:1546-1590`）

| 分组 | 导出成员 | 定义行 | 导出行 |
|---|---|---|---|
| 常量/枚举 | `version`(1) | — | 1547 |
| | `LEVEL` `{CRITICAL:5, EXTREME:4, HARD:3, REGULAR:2, FAIL:0, FUMBLE:-1}` | 34-41 | 1548 |
| | `LEVEL_TEXT` / `LEVEL_KEY`（ASCII 稳定键，协议用 `LEVEL_KEY`） | 43-52 | 1548 |
| | `DIFFICULTY` `{regular:div1, hard:div2, extreme:div5}` | 54-58 | 1548 |
| | `OUTCOME` `{hit,miss,attacker_wins,defender_wins}` | 904-909 | 1579 |
| | `JAM_TYPES` `{jam,feed,dud,burst}` | 1469 | 1586 |
| | `limits` `{MAX_DICE:100, MAX_SIDES:1000}` | 543-544 | 1589 |
| 阈值/成功等级 | `thresholds` / `targetOf` / `normDifficulty` | 120/125/124 | 1550 |
| | `fumbleRange` / `isFumble` / `levelOf` | 158/163/181 | 1551 |
| | `critThresholdOf` / `fumbleThresholdOf`（v2.3.0 自定义阈值） | 146/152 | 1553 |
| 掷骰 | `rollD100` / `combine` | 220/100 | 1555 |
| 检定 | `check` / `describeCheck` | 282/332 | 1556 |
| 推动 | `canPush` | 353 | 1558 |
| 幸运 | `luckAllowed` / `spendLuck` | 373/387 | 1559 |
| 对抗 | `opposed` / `opposedReroll` | 435/462 | 1561 |
| | `opposedAttack`（模式敏感，自带 ≤10 轮重掷） / `opposedFull` | 489/534 | 1563 |
| 骰式/伤害 | `parseExpr` / `rollExpr` / `rollDamageBonus` | 554/587/611 | 1565 |
| SAN | `parseSanLoss` / `resolveSanCheck` / `insanityFlags` | 626/651/693 | 1567 |
| HP/状态 | `damageFlags` / `dyingRoundCheck` | 728/772 | 1569 |
| | `temporaryInsanityCheck` / `boutRounds` | 800/813 | 1571 |
| 行动顺序 | `initiativeOrder` / `advanceTurn` | 834/889 | 1573 |
| 战斗结算 | `resolveAttack` | 1001 | 1576 |
| 角色卡读数 | `skillValue` / `attrValue` | 1265/1306 | 1577 |
| 场景检定 | `sceneStepPlan` / `sceneStepResolve` | 1350/1384 | 1578 |
| 伤害式最大值 | `maxOfExpr` | 925 | 1579 |
| 贯穿/连发 | `maxOfDamageBonus` / `impaleDamage` | 941/962 | 1582 |
| | `burstMaxOf` / `isBurstWeapon` | 1422/1439 | 1583 |
| 武器故障 | `malfunctionThresholdOf` / `malfunctionOf` | 1442/1459 | 1584 |
| | `defaultMalfunctionType` / `malfunctionEffect` | 1483/1503 | 1585 |

**内部但必须等价移植的私有函数**（影响 `randUsed` 与输出字段）：`num`(85)、`defRng`(86)、`pickRng`(87)、`die10`(90)、`clampDie10`(94)、`combine`(100)、`clampValue`(104)、`describeDice`(256)、`canPush`(353)、`rollD100Value`(971)、`buildAttackSummary`(1129)、`SKILL_ALIAS`(1180)/`normSkillName`(1210)/`skillBase`(1223)/`skillSpecs`(1233)/`totalOfSkill`(1246)、`normBranch`(1331)、`toLevelNumber`(1366)、`isRevolver`(1472)、`burstSelfDamage`(1490)。

### 5.2 `window.RoomModel` 导出面（`room-model.js:7660-7711`）

| 分组 | 导出成员 | 定义行 | 导出行 |
|---|---|---|---|
| 常量 | `ROLE` `{KP:'kp',PLAYER:'player',SPECTATOR:'spectator'}` | 32 | 7661 |
| | `HOST_SEAT='host'` | 38 | 7662 |
| | `STATUS` `{RECRUITING,IN_GAME,CLOSED,SUSPENDED}` / `STATUS_TEXT` | 42/44 | 7663-7664 |
| | `MODE` `{EXPLORATION,COMBAT}` | 129 | 7665 |
| | `REWIND` `{IDLE,VOTING,DONE,FAILED}` / `CONFIRM` | 132/278 | 7666-7667 |
| | `EVT`(27) / `INTENT`(13) / `VIS` / `POLICY`(61) / `SECRET_KEYS`(7) | 52/106/140/164/152 | 7668-7672 |
| 权限 | `allowed(role,action)` / `needs(role,action)` | 281/288 | 7674-7675 |
| 可见性 | `hasSecret(p)`（递归） / `scrub(p)`（递归剥私有键） | 327/342 | 7676-7677 |
| 核心类 | `Log` / `Roster` / `Host` / `Client` | 362/417/829/6981 | 7679-7682 |
| 状态归约 | `emptyState(meta)` / `reduce(state,evt)` | 511/582 | 7683-7684 |
| 信封 | `syncMsg` / `evtMsg` / `skipMsg` / `intentMsg` / `parse` | 789/794/807/812/817 | 7686-7690 |
| 工具 | `validCode` / `cleanText` / `inviteLink` / `readInvite` / `clone` | 7565/7151/7570/7612/318 | 7692-7696 |
| 存档/写回 | `parseSave` / `restoreHost` / `playerViewFromSave` / `applyStateToCard` | 7479/7486/7500/7519 | 7699-7702 |
| | `sanitizeSheet` / `sanitizeSceneSteps` | 7297/7449 | 7703-7704 |
| 身体状态 | `bodyView` / `bodyForHp` / `migrateBodyStatus` | 4196/4216/4233 | 7708-7710 |

### 5.3 `EVT` 应用层事件类型（27 项，`room-model.js:52-103`）

| 事件 | 值 | 行号 | 可见性/去向 | `reduce` case |
|---|---|---|---|---|
| `HELLO` | hello | 53 | 全员：房间元信息 | 585 |
| `MEMBERS` | members | 54 | 全员：成员表全量（增删改同用它），逐人裁剪 | 592 |
| `CHAT` | chat | 55 | 全员 | 601 |
| `DICE` | dice | 56 | 全员：权威掷骰结果 | 612 |
| `LOG` | log | 57 | 全员：公共事件流（上限 2000 条） | 606 |
| `SCENE` | scene | 58 | 全员：探索场景 | 620 |
| `COMBAT` | combat | 59 | 全员：战斗态，逐人裁剪 HP | 623 |
| `TURN` | turn | 60 | 全员 | 626 |
| `STATUS` | status | 61 | 全员：状态机切换（同时带 `mode`） | 595 |
| `KICK` | kick | 62 | 针对某 seat | 774（置 `CLOSED`） |
| `CLOSED` | closed | 63 | 全员：关房 | 767（置 `CLOSED`，**不置 `ended`**） |
| `PRIVATE` | private | 64 | 针对某 seat / 或 `to=HOST_SEAT` 给 KP | 754（SEAT 且 to≠host 时不进 `state.privates`） |
| `BOARD` | board | 66 | 针对某 seat：个人手绘板（他人只见缩略） | 642 |
| `ASSET` | asset | 67 | 全员：已公开素材 | 651 |
| `ACTOR` | actor | 69 | 全员：一个参与者公开状态 | 656 |
| `TURNSTATE` | turnstate | 70 | 全员：当前行动者/剩余次数/回合号 | 670 |
| `CHECK` | check | 71 | 全员或 SEAT；**非 PUBLIC 只落脱敏行** | 677-705 |
| `REQUEST` | request | 73 | 针对某 seat：KP 请求改状态 | 738 |
| `REWIND` | rewind | 74 | 全员：回退投票态（休眠保留） | 751 |
| `ROUND` | round | 81 | 全员：显式回合边界，写 `meta.round`、维护 `roundStarts` | 637 |
| `TEMP_COMMIT` | tempcommit | 88 | 全员；**reduce 无分支、不进存档** | —（刻意无 case） |
| `ENDED` | ended | 89 | 全员：结团归档 | 770（`CLOSED` + `meta.ended=true`） |
| `ARCHIVE` | archive | 91 | 仅 KP（SEAT→host） | 727 |
| `SCENE_CHECK` | scenecheck | 92 | 全员：场景检定步骤引擎 | 715 |
| `STATE` | state | 95 | 针对某 seat：角色卡状态写回，带 `seq` 幂等 | 720 |
| `TURN_ALERT` | turnalert | 98 | 全员：轮次强提醒（与 `CHECK` 分开） | 731 |
| `OPPOSED` | opposed | 102 | KP/玩家：对抗申请态 | 709 |

> **关键**：`emit()`(955) 把 `vis`/`to` 一起传给 `reduce`（965 行），`CHECK` 与 `PRIVATE` 分支依赖它做脱敏；Dart `apply(evt)` 的事件对象必须携带这两个字段。见 §8 Q1。

### 5.4 `INTENT` 玩家意图（13 项，`room-model.js:106-126`）

| 意图 | 值 | 行号 | 处理入口 |
|---|---|---|---|
| `SYNC` | sync | 107 | `Host.intent` case 1373（`canFill` 增量补拉，否则全量 sync） |
| `READY` | ready | 108 | 1395（须先绑角色卡） |
| `CHAT` | chat | 109 | 1411 |
| `DICE` | dice | 110 | 1495（`p.direct` → `diceDirect`，否则只记请求） |
| `CHAR` | char | 111 | 1419（`sanitizeSheet` 白名单，权威端不信任客户端数字） |
| `ACT` | act | 112 | 1510 → `_act`(1662) → `needs()` → `applyAction`(1702) |
| `BOARD` | board | 113 | 1514 |
| `VOTE` | vote | 114 | 1518（休眠保留） |
| `CONSENT` | consent | 115 | 1522 → `consent`(1546) |
| `CONFIRM` | confirm | 116 | 1526 → `confirmPending`(1628) |
| `STATE_SYNC` | statesync | 118 | 1532 → `stateSyncAck`(3967)，幂等落点在客户端 |
| `SAN_CHECK` | sancheck | 122 | 1483 → `playerSanCheck`(5597) |
| `OPPOSED` | opposed | 125 | 1489 → `opposed`(6498) |

### 5.5 `POLICY` 权限矩阵（61 个唯一 action，`room-model.js:164-275`）

`confirm` 语义（`164-163` 注释 / `CONFIRM` 278 行）：`null`=直接执行；`'twice'`=二次确认（不可逆）；`'kp'`=玩家发起需 KP 确认；`'owner'`=KP 发起需被改玩家同意；`'all'`=全员投票。`needs()`(288) 对**未登记 action 默认拒绝**。

| action | roles | confirm | 行号 | action | roles | confirm | 行号 |
|---|---|---|---|---|---|---|---|
| `chat` | kp,player | null | 165 | `combat.set` | kp | null | 206 |
| `dice.request` | kp,player | null | 166 | `combat.start` | kp | null | 207 |
| `ready.set` | player | null | 167 | `combat.next` | kp | null | 208 |
| `char.share` | player | null | 168 | `combat.actor` | kp | null | 209 |
| `board.self` | kp,player | null | 169（204 重复） | `combat.enqueue` | kp | null | 211 |
| `state.edit.self` | player | kp | 170 | `combat.pool.set` | kp | null | 213 |
| `state.edit.other` | kp | owner | 171 | `combat.attack` | kp,player | null | 214 |
| `room.start` | kp | null | 172 | `combat.damage` | kp | null | 215 |
| `room.kick` | kp | null | 173 | `combat.end` | kp | null | 216 |
| `room.close` | kp | twice | 174 | `combat.roll` | kp,player | null | 217 |
| `room.end` | kp | twice | 175 | `dice.roll` | kp | null | 219 |
| `scene.set` | kp | null | 176 | `check.request` | kp | null | 221 |
| `scene.reveal` | kp | null | 177 | `check.push` | kp | null | 222 |
| `scene.clue` | kp | null | 178 | `dice.dark` | kp | null | 226 |
| `scene.mode` | kp | null | 179 | `sheet.damage` | kp | null | 227 |
| `state.request` | kp | null | 181 | `sheet.sancheck` | kp | null | 228 |
| `asset.add` | kp | null | 183 | `sheet.tempstatus` | kp | null | 229 |
| `asset.reveal` | kp | null | 184 | `sheet.item` | kp | null | 230 |
| `asset.cover` | kp | null | 186 | `rollback.commit` | kp | null | 240（休眠保留） |
| `asset.del` | kp | null | 188 | `round.next` | kp | null | 246 |
| `item.del` | kp,player | null | 190 | `rollback.round` | kp | null | 247 |
| `state.self` | player,kp | null | 194 | `session.end` | kp | twice | 248 |
| `madness.advance` | player,kp | null | 196 | `combat.prepare` | kp | null | 252 |
| `madness.cure` | player,kp | kp | 198 | `scene.check.push` | kp | null | 254 |
| `map.mark` | kp | null | 200 | `scene.check.step` | kp | null | 255 |
| `map.stroke` | kp | null | 201 | `check.opposed` | kp | null | 257 |
| `map.clear` | kp | null | 202 | `room.suspend` | kp | null | 261 |
| `map.strokes.set` | kp | null | 203 | `room.resume` | kp | null | 262 |
| `room.rules` | kp | null | 264 | `sheet.sanloss` | kp | null | 266 |
| `sheet.healwound` | player,kp | kp | 269 | `aid.apply` | player,kp | kp | 271 |
| `aid.psycho` | player,kp | kp | 274 | | | | |

**权限执行链**：`Host.intent`(1326) → `INTENT.ACT` → `_act`(1662) → `needs(role,op)`(288) → 未登记即 `allowed:false` 并回「你没有权限执行该操作」(1668)；有 `confirm` 且发起者不是 KP 时入 `pending`(1691) 并去重(1681-1689)；KP 发起且 `confirm='kp'` 直接执行(1674)。另有**全局操作锁** `locked`(1344-1369)：撕卡/疯狂发作/昏迷/濒死的玩家只剩白名单（CHAT/SYNC/READY/STATE_SYNC/CHAR + madness.advance/madness.cure/sheet.healwound）。
**角色推断**：`isHost = (seat === HOST_SEAT)`(1334) → `ROLE.KP`；`roster.get('host')` 恒为 null（花名册无房主），**不得据此判为旁观者**。

### 5.6 可见性与安全边界（`room-model.js`）

| 项 | 位置 | 语义 |
|---|---|---|
| `VIS` `public/kp/seat` | 140 | `KP`=只有 KP 端持有，**根本不出门**；`SEAT`=逐人单发，绝不广播 |
| `SECRET_KEYS` | 152 | `['secret','hidden','kpOnly','truth','clue','spoiler','answer']`（7 项） |
| `hasSecret` / `scrub` | 327/342 | 递归检测/剥离；`emit()`(957) 对 `vis!==SEAT` 自动剥私有字段并记 `warnings` |
| `Host.plan` | 1151-1209 | `VIS.KP` → 返回 `[]`；`VIS.SEAT` → 只给 `to` 发 `evt`，其余在线者发 `skip` 水位标记；PUBLIC 的 `MEMBER_EVTS`/`COMBAT_EVTS` 逐人裁剪后单发 |
| `combatFor` / `_cropMember` / `_cropSlot` / `_cropCombat` | 911/1062/1126/1134 | 玩家侧删 `hp`/`hpMax`（除 `hpPublic`）、`secret`/`kpOnly`/`attrs`/症状明细；`HOST_SEAT` 拿全量 |
| `_makeSync` / `syncFor` | 1281/1268 | 全量同步与增量裁剪**必须用同一套规则**（1269-1272 注释），否则重连前后忽隐忽现 |
| `EVT.CHECK` 脱敏 | 677-705 | 非 PUBLIC 检定只往 `state.logs` 落 `'KP 秘密进行了一次检定'` + `redacted:true` |
| `EVT.PRIVATE` 守卫 | 754-762 | `vis===SEAT && to && to!==HOST_SEAT` 时不归约进 KP 的 `state.privates` |
| `emitLocal` | 1029 | KP 私密备忘**不占共享序号**、永不外发 |

### 5.7 状态模型 `emptyState`（`room-model.js:511-575`）

顶层键：`meta`（code/name/rules/kpName/maxPlayers/allowSpectate/status/mode/round/critThreshold/fumbleThreshold/hpWeek/psychoRound）、`members`、`chats`、`logs`、`dice`、`scene`、`combat`、`privates`、`rewind`、`requests`、`board`、`sceneCheck`、`archive`、`lastState`、`alert`、`opposed`、`seq`、`version:1`。
⚠️ 未公开素材/标记/KP 备注**不进 `scene`**，只在 KP 端 `localAssets` 等本地容器（551 行注释）。

### 5.8 `Log` / `Roster` / `Host` / `Client` 主要方法（含行号）

| 类 | 方法 | 行号 | 职责 |
|---|---|---|---|
| `Log` | `push` / `since` / `canFill` / `rollbackBefore` | 370/382/391/402 | 全局序号、补拉窗口（cap 默认 400）、回退裁剪（`seq=beforeSeq-1`） |
| `Roster` | `open`/`markOffline`/`remove`/`get`/`list`/`players`/`spectators`/`onlinePlayers`/`allReady`/`dump` | 430/460/467/477/479/484/488/492/496/503 | 花名册**无房主**；`kicked` 防止被踢者立刻回来 |
| `Host` | `emit` / `emitLocal` / `_maybeSnapshot` / `_rebuildRoundStarts` | 955/1029/1022/1009 | 唯一出口；`snapshotEvery` 默认 20、快照上限 20 |
| | `plan` / `planAll` / `_push` | 1151/1212/940 | 返回 `[{to,msg}]` 发送计划，**不直接发网络** |
| | `attachPeer` / `detachPeer` / `syncFor` / `_makeSync` | 1227/1258/1268/1281 | 重连/全量同步 |
| | `intent` / `_act` / `applyAction` | 1326/1662/1702 | 意图→权限→动作分发（op 分支 1705-1858） |
| | `consent` / `confirmPending` / `stateSyncAck` | 1546/1628/3967 | 确认队列、幂等回执 |
| | `stateApply` / `settleWounds` / `applyHpChange` | 3983/4539/4623 | 角色卡状态写回、`_stateSeq` 单调自增 |
| | `diceRoll` / `diceDirect` / `darkRoll` | 2980/3016/4492 | 权威掷骰（玩家只声明，KP 端算） |
| | `combatStart` / `combatActor` / `combatEnqueue` / `combatDamage` / `combatAttack` / `combatEnd` | 2461/2563/2591/2716/2767/2965 | 战斗 |
| | `checkRequest` / `checkOpposed` / `sceneCheckPush` / `sceneCheckStep` | 3190/5830/6663/6734 | 检定/场景步骤 |
| | `rollbackPropose` / `rollbackVote` / `rollbackCommit` / `rollback` / `rollbackPlan` | 3258/3320/3347/3431/3483 | 回退（休眠保留 + 快照重放） |
| | `nextTurn` / `_onRoundBoundary` / `_advanceRound` / `setStatus` / `kick` / `closeRoom` | 3534/3623/3674/3418/3495/3507 | 回合与生命周期 |
| | `save` / `savePayload` / `adoptSave` | 6885/6907/6910 | 存档数据对象（**不落盘**） |
| | `suspendRoom` / `resumeRoom` / `setRoomRules` | 6855/6867/5566 | 挂起/续玩/自定义阈值 |
| `Client` | `receive` / `_gate` / `_filledMark` / `resyncIntent` / `resyncDiag` | 7008/7054/7072/7078/7090 | 序号闸门：重复丢、跳跃报缺口、连续放行 |
| | `applySheetState` | 7123 | `lastStateSeq` 幂等，返回 `{applied,seq,dup?}` |
| | `intent` / `member` / `isReady` | 7101/7103/7110 | 客户端只读 + 生成意图 |

### 5.9 两层协议与信封（`room-model.js:20-24, 788-823`）

```
中继层（room_server.py / 局域网外壳）      hub.* / peer.*
        ↕ 原样透传，不认识应用层字段
应用层（KP ↔ 玩家）  parse() 仅接受 4 种：
  {k:'sync',   seq, state}                 全量同步（首连/重连/超出补拉窗口）
  {k:'evt',    seq, t, p}                  增量事件
  {k:'skip',   seq}                        全局序号水位标记（SEAT 事件给其他人）
  {k:'intent', op, p}                     玩家 → KP 意图
```
`Host` 所有对外方法返回 `[{to:'*'|seat, msg}]` 发送计划（936-939 注释），由 P6 传输层照单发送。

### 5.10 与 `core/room-store.js` 的接口边界（本期不做落地，但必须预留）

| 方向 | 旧版接口 | 位置 | P4 边界 |
|---|---|---|---|
| model → store | `Host.save()` → `{v:2, code, rules, savedAt, seq, stateSeq, meta, members, chats, logs, dice, scene, combat, sceneCheck, roundStarts, privateBySeat, requestsBySeat, boardBySeat, localAssets, localActors}` | 6885-6905 | Dart 提供等价的**纯数据对象/序列化方法**，不含任何 `dart:io`；由 P5/P6 或后续期决定写文件/云端 |
| store → model | `Host.adoptSave(save)`（重建 roster、log.seq、snapshots、_stateSeq、roundStarts） | 6910-6953 | 同上：纯内存恢复 |
| store | `RoomStore.saveRoom(code,{role,seat,seq,state})` / `listRoomSaves` / `MAX_SAVES=8` | room-store.js:254/… | **不在 P4 实现**；P4 不得引用 `RoomStore` |
| 角色卡写回 | `applyStateToCard(store, charId, patch)` → `{ok,reason,cardId,source}`（charId 找不到即拒绝，绝不写到 current 别的卡） | 7519-7562 | Dart 侧等价物必须走 **C5 `CharacterRepo.save()`**；返回值结构化，禁止静默失败 |
| 玩家裁剪视图 | `playerViewFromSave(save, seat)` 复用 `syncFor` 同一套裁剪 | 7500-7504 | 供 P6 云端存档下发；P4 提供纯函数 |

### 5.11 已实测的关键边界值（Node VM 加载旧版 JS 直接跑出，作为 fixture 基准）

| 输入 | 旧版输出 |
|---|---|
| `LEVEL` | `{CRITICAL:5, EXTREME:4, HARD:3, REGULAR:2, FAIL:0, FUMBLE:-1}` |
| `thresholds(55)` | `{base:55, regular:55, hard:27, extreme:11}`（向下取整） |
| `fumbleRange(55,{})` / `fumbleRange(27,{})` | `{100..100}` / `{96..100}`（看**本次要求阈值**，非技能原值） |
| `levelOf(1,55,55,{})` … `(11)` `(27)` `(55)` `(56)` `(96,55,27)` `(100,55,55)` | `5 / 4 / 3 / 2 / 0 / -1 / -1` |
| `combine(0,0)` / `(0,1)` / `(9,9)` | `100 / 1 / 99` |
| `rollD100({bonus:1, ones:0, forcedTens:[0,1]})` | `combos=[100,10]`，`pickedIndex=1`，`value=10`（**先组合再比大小**） |
| `rollD100({penalty:1, ones:0, forcedTens:[0,1]})` | `pickedIndex=0`，`value=100` |
| `rollD100({bonus:1, penalty:1, ones:0, forcedTens:[0,1]})` | `cancelled=1, net=0, tens=[0], value=100`（先抵消再决定额外掷几个） |
| `check({base:50,value:100})` | `level=-1, canPush=false, canSpendLuck=false` |
| `spendLuck({result:check(base:50,value:3),amount:10,luckAvailable:99})` | `{ok:true, spent:2, refund:8, before:3, after:1, afterLevel:5, growthEligible:false}` |
| **`check({base:50, value:42, rng})` 的 RNG 消耗** | **2 次**（即使传入 `value`，`rollD100` 仍照掷）；`bonus:2` → 4 次；`ones+forcedTens` 全给 → **0 次** |
| `VIS.KP` 事件 `plan()` | `[]`（零条出站） |
| `VIS.SEAT` 事件 `plan()`（roster p1/p2） | `[{to:'p1',msg:{k:'evt',...}}, {to:'p2',msg:{k:'skip',seq}}]` |
| `emit(PUBLIC, {text, secret:'leak'})` | 载荷被 `scrub` 成 `{text}` + 一条 `warnings` |
| `Client._gate` seq 1→1→3→2 | `changed` / `dup:true` / `gap:true, gapFrom=1` / `changed, filled:true, gapFrom=0` |
| `CLOSED` reduce | `meta.status='CLOSED'`，`meta.ended` 保持 undefined（`ENDED` 才置 true） |
| `rollback(beforeSeq)` | `{dropped, seq:beforeSeq-1, from:snapSeq}`，状态 + 关联事件 + `roundStarts` + `snapshots` 一并回滚 |

---

## 6. 需求池（每条含「输入 → 期望输出或不变式」）

> P0 = Must have（本期必须全绿，等价性门禁）；P1 = Should have；P2 = Nice to have。
> 所有 P0 的通用验收前置：Node VM fixture 与 Dart 实现逐字段深比较一致且 `randUsed` 一致；`dart analyze` 干净；`lib/domain` 零 Flutter/IO 命中。

### P0 — 规则服务 `CocRules`（`room-rules.js` 等价移植）

| ID | 需求 | 验收（输入 → 期望输出 / 不变式） |
|---|---|---|
| **P0-R01** | 常量与阈值 | 输入 `LEVEL/LEVEL_KEY/LEVEL_TEXT/DIFFICULTY/OUTCOME/JAM_TYPES/limits` → 与 §5.11 逐键一致；`thresholds(b)` 对 `b=0,1,55,99,100,负数,非数字串` → `hard=floor(b/2)`、`extreme=floor(b/5)`、`base=max(0,parseInt)`；`normDifficulty` 未知值退回 `regular` |
| **P0-R02** | 成功等级边界 | 输入 `levelOf(v, base=55, target, opts)` 覆盖 `v∈{1,11,27,55,56,96,99,100}` 与 `target∈{55,27,11}` → 输出 `5/4/3/2/0/-1/-1` 组合与 §5.11 一致；`v=1` 恒 `CRITICAL`（先于大失败判定）；`v=100` 恒 `FUMBLE`；`v` 越界被 `clampValue` 夹到 `[1,100]` |
| **P0-R03** | 大失败动态/自定义阈值 | 输入 `fumbleRange(target=55,{})` → `{100,100}`；`target=49` → `{96,100}`；`opts.fumbleMin=90` → `{90,100}`；不传/`0`/空/非法 → 与改动前逐字节一致（回归保护）。`critThresholdOf` 默认 1、`fumbleThresholdOf` 默认 0（0=未设置走动态）；`critMax`/`fumbleMin` 从 `check` 透传到 `levelOf`/`fumbleRange`/`spendLuck` |
| **P0-R04** | 奖励骰/惩罚骰 | 输入 `rollD100({bonus:1,ones:0,forcedTens:[0,1]})` → `combos=[100,10], pickedIndex=1, value=10`；`penalty:1` → `pickedIndex=0, value=100`；`bonus:1,penalty:1` → `cancelled=1,net=0,tens.length=1,value=100`。**不变式：先 `combine(t,ones)` 成百分数再比大小**，禁止对十位骰先取 min/max（C7）；`tens/ones/combos/pickedTens/pickedIndex/value/bonus/penalty/cancelled/net/detail` 全部字段与旧版一致 |
| **P0-R05** | 掷骰注入与 RNG 消耗 | 输入 `check({base:50,value:42,rng})` → `value=42` 但 **RNG 消耗 2 次**；`check({base:50,bonus:2,value:42,rng})` → 4 次；`check({base:50,value:42,ones:3,forcedTens:[2],rng})` → **0 次**。`opts.ones`/`opts.forcedTens`/`opts.value` 三条注入通道缺一不可（重放历史、校验他人骰子）；`forcedTens` 不足时按末位补足到 `1+extra` |
| **P0-R06** | `check()` 全字段等价 | 输入 `check(opts)` 覆盖 `kind/difficulty/bonus/penalty/secret/label/critMax/fumbleMin` 组合 → `v:1, kind, label, secret, base, difficulty, difficultyText, bonus, penalty, target, required, thresholds, value, dice, level, levelKey, levelText, passed, failed, critical, fumble, fumbleRange, critMax, fumbleMin, canPush, pushBlockReason, canSpendLuck, luckBlockReason, summary` 逐字段一致（键集合完全一致）；`canPush` 必须在 `result` 成形后计算 |
| **P0-R07** | 推动与幸运 | 输入 `canPush(成功检定, 'skill')` → `ok:false, reason:'检定已经成功，不需要推动'`；`大失败` → `ok:false`；`combat/san/opposed/luck/damage/sanloss` → 对应 `PUSH_REASON`。`luckAllowed` 对 `luck/san/sanity/sanloss/damage` 拒绝。`spendLuck` 对 `fumble`/`critical` 拒绝；`after=max(1,before-amount)`；`refund=amount-spent`；`growthEligible:false`；沿用原检定 `critMax/fumbleMin` 重算等级 |
| **P0-R08** | 对抗检定 | `opposed`：等级高者胜 → 同级 `base` 高者胜 → 全同 `needsReroll:true`；`opposedReroll` 低者胜、相同继续；`opposedAttack` 模式敏感：同级 + `fightback` → `winner:'a'`（不重掷）、`dodge` → `winner:'b'`、`mode:'none'` 比 `base` 后逐轮重掷 ≤ `rerollMax`(默认 10) 轮，达上限 `fallback:true, winner:'a'`；`rounds[]` 逐轮明细一致。`opposedFull` = `opposedAttack(mode:'none')` |
| **P0-R09** | 骰式与伤害骰 | `parseExpr` 支持 `NdM`、纯数字、加减组合（不支持乘除括号，明确报错）；`MAX_DICE=100`/`MAX_SIDES=1000`/常数 ≤10000 越界拒绝；`rollExpr`/`rollDamageBonus` 的 `rolls[]`/`total`/`detail` 与旧版一致且 RNG 消耗一致 |
| **P0-R10** | SAN 与疯狂 | `parseSanLoss('0/1D6')`、`resolveSanCheck`、`insanityFlags`（`temporary: loss>=5`；`indefinite: dayStart>0 && dayTotal*5>=dayStart`，**乘法不做除法取整**）、`temporaryInsanityCheck`、`boutRounds(1D10)` → 逐字段一致 |
| **P0-R11** | HP/伤势/濒死 | `damageFlags`：`majorWound = dmg*2>=maxHP`；`lethal = dmg>maxHP`（**严格大于**，等于上限归濒死）；`after===0` 时 `hasMajorWound ? 'dying' : 'unconscious'`；`needsConCheck`/`requireFirstAid`/`summary` 一致。`dyingRoundCheck` 成功稳定、失败死亡 |
| **P0-R12** | 行动顺序 | `initiativeOrder`：按 `effDex` 降序（`readyFirearm` → DEX+50）、`manualOrder` 优先、`actionsPerRound` 展开成多槽且不删条目、`slot/totalSlots/lastSlot` 一致；`advanceTurn(index,round,len)` 走完回队首且 `round+1, roundWrapped:true` |
| **P0-R13** | 战斗结算 | `resolveAttack`：`kind:'combat'` 不可推动/不可花幸运；远程 `fightback` 降级 `dodge`（`coercedFromFightback`）；结局 `HIT/MISS/ATTACKER_WINS/DEFENDER_WINS`；贯穿（EXTREME/CRITICAL）走 `impaleDamage` 统一公式；护甲 `applied=max(0,raw-armor)`；`flags` 复用 `damageFlags`；`mode/ranged/compare/rerolls/damageBy/summary` 逐字段一致 |
| **P0-R14** | 角色卡读数/场景步骤/连发/故障 | `skillValue`/`attrValue`（`SKILL_ALIAS`）、`sceneStepPlan`/`sceneStepResolve`、`maxOfExpr`/`maxOfDamageBonus`/`impaleDamage`、`burstMaxOf`/`isBurstWeapon`、`malfunctionThresholdOf`/`malfunctionOf`/`defaultMalfunctionType`/`malfunctionEffect`/`isRevolver`/`burstSelfDamage` → 与旧版逐字段一致 |
| **P0-R15** | 纯函数与分工 | 规则服务不碰 DOM/请求/全局状态；**不得引用或复用 `dice.dart` 的 `d100Bonus`/`successLevel` 等价物**；`Math.random` 只在 `pickRng()` 默认分支出现，所有掷骰入口可注入 `rng`；Dart 侧通过 `js_compat.setRng()` 复现 |

### P0 — 权威状态机 `RoomModel`（`room-model.js` 等价移植）

| ID | 需求 | 验收（输入 → 期望输出 / 不变式） |
|---|---|---|
| **P0-M01** | `apply(evt)` 单口 + 无隐式副作用 | 所有状态变更只能经 `apply(evt)`；输入同一 `(state0, evt序列)` 两次 → `state` 完全一致；静态检查不存在 `apply` 之外对 `state` 的写入；`emit` 等价物同时完成「入日志 + 归约 + 快照 + 回合边界维护」，且把 `vis`/`to` 一并交给归约 |
| **P0-M02** | 常量与 `HOST_SEAT` 身份推断 | `HOST_SEAT='host'`；输入 `Host.intent('host', {op:CHAT,...})` → 产生 1 条广播（`roster.get('host')` 为 null 时**不得**判成 spectator 而拒绝）；`combatFor('host')` 返回**全量**（含 `hp/hpMax/secret/attrs`）；`_cropMember(self=HOST_SEAT)` 全量；`_sysTo(HOST_SEAT)`/`darkRoll`/秘密对抗的 `to=HOST_SEAT` 进 KP 私有栏。`ROLE/STATUS/MODE/REWIND/VIS/SECRET_KEYS/EVT/INTENT/POLICY` 键集合与值与 §5.3–5.6 一致 |
| **P0-M03** | `CLOSED` 兼容性 | 输入 `EVT.CLOSED` → `meta.status='CLOSED'` 且 `meta.ended` 保持未设；`EVT.ENDED` → `CLOSED` + `meta.ended=true`；`EVT.KICK` → `CLOSED`；`STATUS.SUSPENDED` 可续玩、**不得**复用 `CLOSED` 表示挂起；旧存档 `adoptSave` 读入 `CLOSED` 后语义不变 |
| **P0-M04** | KP 隐藏信息**不下发**（字节级） | ① `vis=KP` 的 `plan()` → `[]`；② `vis=SEAT` 且 `to='p1'` → 计划里只有 `{to:'p1',msg:{k:'evt'}}` 与其余在线者 `{k:'skip'}`，**任何其他人消息体中不含 `p` 内容**；③ `emit(PUBLIC,{text,secret:'leak'})` → 载荷被 `scrub` 成 `{text}` + 一条 `warnings`；④ 玩家/旁观者的 `combat`/`actor`/`turn`/`turnstate`/`members` 载荷中**不存在** `hp/hpMax/secret/kpOnly/attrs` 与症状明细字段（不是「前端少画」）；⑤ `syncFor(seat)` 与增量裁剪产出同一套视图；⑥ 非 PUBLIC 的 `EVT.CHECK` 只往 `state.logs` 落 `redacted:true` 脱敏行；⑦ `EVT.PRIVATE` 的 `vis=SEAT && to!==HOST_SEAT` 不进 `state.privates` |
| **P0-M05** | seq 幂等与乱序 | `Client.receive`：seq `1` → `changed:true`；重复 `1` → `dup:true, changed:false, rejected+1`；跳到 `3` → `gap:true, gapFrom=1, changed:false`（**状态不变**）；补 `2` → `changed:true, filled:true, gapFrom=0`；`skip` 与 `evt` 走同一 `_gate`；`sync` 重置 `lastSeq/gapFrom`。`resyncIntent` 带 `lastSeq`。`Host.intent(SYNC)`：`canFill(from)=true` 走 `log.since(from)` 增量重发（**不再叠全量 sync**），否则发全量 `syncFor(seat)`；`planAll` 顺序与 seq 一致 |
| **P0-M06** | 角色卡状态写回幂等 | `stateApply` 每次 `_stateSeq+1` 且 `EVT.STATE` 以 `VIS.SEAT` 只发本人；`Client.applySheetState(seq,patch)` 对 `seq<=lastStateSeq` → `{applied:false,dup:true}`，`seq<=0` → `applied:false`；同一 seq 应用两次只扣一次血。`applyStateToCard` 等价物：`charId` 命中才写、找不到返回 `{ok:false,reason:'card_not_found'}`（**绝不退到 current 别的卡**）、无 `charId` 才退 `current` 并标 `source:'current'`；返回结构化 `{ok,reason,cardId,source}` |
| **P0-M07** | 房间状态写回必过 `CharacterRepo.save()`（C5） | 输入一张 `currentHP=0, dying=true` 的濒死卡 + 一次 `EVT.STATE` 写回 → 落盘后 `currentHP` 仍为 0、`dying` 仍为 true（不被 `recalc` 补满）；静态检查：写回路径调用 `CharacterRepo.save(Character)`，不存在直接 `card.status[k]=v` + 落盘的旁路 |
| **P0-M08** | 回退重放（状态快照 + 关联事件） | 输入：连续 emit `E1(CHAT)`、`E2(LOG)`、`E3(LOG)` 后 `rollback(E3.seq)` → `state` = seq `snap` 的快照 + 重放 `snap<seq<=E3.seq-1` 的事件；`chats/logs` 内容与条数正确、`log.seq=beforeSeq-1`、`state.seq` 同步、`snapshots` 裁掉 `>target`、`roundStarts` 由 `_rebuildRoundStarts` 重建；`members` 用当前花名册覆盖（不把在线玩家变没）；`prevStatus===IN_GAME && 恢复出 RECRUITING` → 保持 `IN_GAME`；`rollbackPlan` 给所有在线者重发**全量 sync**（不发反向事件）。**只删界面文字不算回退** |
| **P0-M09** | `reduce` 26 分支全覆盖 | `EVT` 27 项中 26 项有 reduce 分支（`TEMP_COMMIT` 刻意无分支、不进存档）；逐分支构造事件 → `state` 与旧版一致；`state.seq=evt.seq` 无条件在末尾写入；`CHAT≤500`、`LOG≤2000`、`DICE≤200`、`PRIVATE≤100` 的裁剪一致 |
| **P0-M10** | 权限矩阵与确认策略 | `needs()` 对 §5.5 的 61 个 action 返回与旧版一致的 `{allowed,confirm}`；**未登记 action 一律 `allowed:false`**（伪造 ACT 被拒并回系统提示）；`_act` 的 `confirm` 入 `pending`、同 `(by,op,payload)` 去重、KP 发起且 `confirm='kp'` 直接执行；全局操作锁 `locked` 白名单与 1344-1369 一致；`stateSelf`/`healWound`/`cureIndefinite` 等跨玩家改状态必须被 `bySeat!==HOST_SEAT && target!==bySeat` 拒绝 |
| **P0-M11** | 协议与信封 | `parse()` 只接受 `sync/evt/skip/intent` 四类中合法 JSON（其余返回 null，中继自己的 `host.gone` 不进应用层）；`syncMsg/evtMsg/skipMsg/intentMsg` 字段与 `clone` 语义一致；`Host` 对外方法一律返回 `[{to,msg}]`，**不返回事件记录**；`planAll` 顺序与 seq 一致 |
| **P0-M12** | 存档数据对象与裁剪视图 | `Host.save()` 的 19 个键与 `adoptSave()` 的恢复结果逐字段一致（`v:2`、`stateSeq`、`roundStarts`、`privateBySeat`、`requestsBySeat`、`boardBySeat`、`localAssets`、`localActors` 全带）；`adoptSave` 对老存档跑一次 `migrateBodyStatus` 且幂等、成员 `online=false`；`playerViewFromSave(save,seat)` 产出可直接喂 `Client.receive` 的 `{k:'sync',seq,state}` 且已裁剪 |
| **P0-M13** | 规则/模型接缝 | `Host` 注入 `rules`（`opts.rules`，默认取全局 `CocRules`）与 `madness`（`opts.madness`）；`ruleOptsOf(meta)` 只在 `critThreshold/fumbleThreshold ∈ [1,99]` 时下发 `critMax/fumbleMin`（默认 1/100 = 未自定义，与改动前逐字节一致）；`diceRoll/diceDirect/darkRoll/checkRequest/combatAttack` 全部经规则服务计算，模型不得自行算成功等级；`opts.now` / `opts.rng` 注入生效，`at` 用固定时钟 |
| **P0-M14** | 纯 Dart / 等价性门禁 | `lib/domain` 零 `package:flutter`/`dart:io`/`dart:ui` 命中；Node VM 加载 `room-rules.js` + `room-model.js`（同 VM 上下文，模型可注入规则服务）、LCG + 固定时钟 dump fixture；Dart 用 `test/support/oracle.dart` 的 `Lcg` 复现，逐字段深比较 + `randUsed` 断言；覆盖 §5.11 全部边界与 P0-M04/M05/M08 场景；`flutter test` 全绿（在 572 组基线上只增不减）、`dart analyze` 干净 |

### P1 — Should have

| ID | 需求 | 验收 |
|---|---|---|
| **P1-01** | 可见性审查/可观测性 | `warnings` 对「非 SEAT 携带私有字段」「SEAT 缺收件人」各记一条；测试可断言正常路径 `warnings` 为空；`emitLocal` 的 KP 备忘不占共享序号 |
| **P1-02** | 补拉诊断 | `resyncDiag()` 返回 `{from,last,filled,holes,count}`，`resyncCount` 递增；缺口补齐后 `filled` 标记能传到上层（横幅可消失） |
| **P1-03** | 快照参数化 | `snapshotEvery`（默认 20）与 `logCap`（默认 400）、`snapshots` 上限 20 可注入；`canFill(fromSeq)` 在 `items[0].seq > fromSeq+1` 时返回 false 并触发全量 sync |
| **P1-04** | 自定义阈值联动 | `setRoomRules` 把 1–100 整数写入 `meta.critThreshold/fumbleThreshold` 并广播；非法值拒绝并回 KP 提示；`ruleOptsOf` 与规则服务阈值口径一致 |
| **P1-05** | 存档接口预留（不落地） | `save()/savePayload()/adoptSave()/parseSave()/restoreHost()/playerViewFromSave()` 提供纯内存实现与稳定 JSON 形状，供后续期接文件/云端；**不引入** `dart:io` 或 `RoomStore` 依赖 |

### P2 — Nice to have

| ID | 需求 | 验收 |
|---|---|---|
| **P2-01** | 休眠兼容项保留 | `rollbackPropose/rollbackVote/rollbackCommit`、`EVT.REWIND`、`INTENT.VOTE`、`REWIND` 枚举、`case EVT.REWIND`、`state.rewind` 存在且可被旧存档 reduce 消费；但 `POLICY['rollback.turn']` 不存在（入口已摘除），伪造 ACT 被 `needs()` 默认拒绝 |
| **P2-02** | 房间号/邀请链接工具 | `validCode('^[a-z0-9]{4,12}$')`、`inviteLink`、`readInvite`、`normalizeServerBase`、`cleanText` 与旧版一致（P6 会用到，P4 可先给纯函数） |
| **P2-03** | 文件拆分建议（给架构师，非强制） | 建议 6 个文件：`room_rules.dart`（CocRules 全量）、`room_rules_dice.dart`（骰式/伤害/故障）、`room_model_types.dart`（常量/EVT/INTENT/POLICY/state）、`room_model_reduce.dart`（`emptyState`/`apply`）、`room_model_host.dart`（Host/Log/Roster/plan/裁剪）、`room_model_client.dart`（Client/信封/存档视图）；全部位于 `lib/domain`，彼此只依赖 Dart 核心库 |

---

## 7. UI Design Draft

**N/A（规则层，UI 属 P5）**。P4 不产出 Widget、页面、布局、画布或交互稿；`plan()` 返回的发送计划由 P6 传输层消费，`state` 由 P5 渲染。

---

## 8. 待确认问题（需 team-lead / 架构师决策）

| ID | 问题 | 背景（实读证据） | 建议 |
|---|---|---|---|
| **Q1（高）** | **回退重放时 `vis`/`to` 丢失导致秘密检定明文进公共日志**，是否修正？ | `emit()` 在 `room-model.js:965` 把 `vis/to` 传给 `reduce`；但 `rollback()` 在 **3450** 行重放时只传 `{t, seq, p}`，未带 `vis/to`。实测：`VIS.SEAT` 的秘密 `CHECK` 初始只落 `redacted:true` 脱敏行，回退重放后 `state.logs` 变成明文「秘密检定：骰出 07，极难成功」→ 再经 `syncFor` 会广播给所有玩家，**直接违反 §0 硬要求**。同理 `EVT.PRIVATE` 的 SEAT 守卫(762)在重放时失效 | **建议 Dart 修正**：日志记录保存 `vis/to`，`apply(evt)` 重放时一并传入；等价性测试对该场景标注为「已知旧版缺陷，Dart 有意不一致」并单列白名单，其余场景仍严格等价。请 team-lead 确认是否接受这处**有意分歧** |
| **Q2** | `dice.js` 侧是否完全冻结？ | `dice.js:36-54` 缺陷已确认；`room-rules.js:19-24` 明说零调用预留 | 建议 P4 只新增实现，`lib/domain/dice.dart` 不动；请确认不做「修好旧 dice」的额外范围 |
| **Q3** | 应用层协议按 3 种还是 4 种？ | 任务摘要写 `{k:'sync'\|'evt'\|'intent'}`；实读 `parse()`(821) 与 `skipMsg`(807) 表明还有第 4 类 `skip`，且注释(801-805)说明缺了它会导致其他玩家 `lastSeq` 永久落后、卡死补拉循环 | 建议按 **4 种**移植，`skip` 列为 P0-M05 的一部分 |
| **Q4** | `check(opts.value)` 仍消耗 RNG，等价性口径如何定？ | 实测传入 `value=42` 时 `rollD100` 照掷，消耗 2 次；`ones+forcedTens` 全给时 0 次 | 建议**严格保持**（`randUsed` 断言会抓住任何「优化」）；fixture 需覆盖这三种组合 |
| **Q5** | `room-store.js` 边界：P4 是否要实现 `save()/adoptSave()` 的 Dart 版？ | 摘要说「本期不做持久化落地，但说明接口边界」 | 建议 P4 实现**纯内存序列化/恢复**（P1-05），不写文件、不引 `dart:io`；`saveRoom/saveNow` 等落地留后续期。请确认 |
| **Q6** | `TEMP_COMMIT` 与休眠回退项的兼容范围 | `EVT.TEMP_COMMIT`(88) 刻意无 reduce 分支、不进 `save()`；`rollback.turn` 的 POLICY 入口已移除(231-239)但 `applyAction`(1845) 仍保留分支 | 建议 P4 **原样保留**（不删方法/枚举/reduce 分支），仅 `POLICY` 不登记 `rollback.turn`；请确认旧存档回放是否纳入本期 oracle 用例 |
| **Q7** | 等价性 fixture 的规模与覆盖范围 | P0 已建 1621 例；P4 两模块 9303 行、53+41 导出成员 | 建议至少覆盖：§5.11 全部边界 + P0 表中每条的 3–5 组输入 + 一条「KP 秘密检定 + 回退」的可见性回归 + 一条「seq 乱序/重复/补拉」序列；请确认目标用例数与是否需要新增 `tool/oracle/dump_p4_room.js` |
| **Q8** | 版本号与文件命名 | 基线 `2.15.0+81`；`lib/domain/rules_coc7.dart` 已存在（P0 车卡规则层） | 建议 P4 文件统一 `room_*` 前缀，**不改 `rules_coc7.dart`**；版本递增留到 P4 收尾由 team-lead 定 |

---

## 9. 全局验收口径（Definition of Done）

1. §6 全部 **P0** 项通过；P1 至少 P1-01/P1-03/P1-05 通过；P2 不阻塞交付。
2. 「JS 当预言机」等价性：Node VM 原样加载旧 JS + monkey-patch `Math.random`=LCG / `Date.now`=固定时钟 dump fixture；Dart 用同款 LCG 复现，**逐字段深比较 + `randUsed` 断言**（`test/support/oracle.dart` 口径）。
3. `lib/domain` 零 `package:flutter` / `dart:io` / `dart:ui` 命中；`dart analyze` 干净；`flutter test` 在 572 组基线上**只增不减且 0 红**。
4. 角色卡契约冻结：旧版房间 JSON 无损导入/导出，无新增或改名键；所有写回路径经 `CharacterRepo.save()`（C5）。
5. 安全不变式：`VIS.KP` 零出站、`VIS.SEAT` 单发 + skip、PUBLIC 自动 scrub、玩家载荷无 HP/秘密字段、非 PUBLIC 检定脱敏。
6. 未改动任何 `lib/` 或 `test/` 代码、未跑构建（本 PRD 阶段仅文档产出）。
