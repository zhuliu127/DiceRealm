# P5 增量 PRD：房间 UI（room-ui / room-panels 移植）

> 编写人：software-product-manager-2（许清楚 · 产品经理）
> 基线版本：`2.15.0+81`（P4 未出包，P5 一起出包 → 建议 `2.16.0+82`，待 team-lead 最终定）
> 上游输入：team-lead 任务说明（P5 范围 / 布局决策 / K1·K4 待办）
> 交付性质：**只做需求分析与文档**。本阶段未改任何 `lib/`、`test/` 代码，未跑构建。

---

## 0. 一句话结论（给 team-lead 的摘要）

P5 的信息架构是 **两个页面**（招募中的「房间页」+ 开局后的「游戏页」），游戏页是 **同构多块布局 × 3 种视角（KP / 玩家 / 旁观）** —— KP 侧 12 个容器（源码行内编号 1–11 + `.gp-status`），玩家侧实读为 **13** 个容器（v2.1.6 加「笔记栏」、v2.1.8 把「我的手绘板」拆成独立块，旧注释的「12 块」已过期）。旧版 `room-panels.js` 里有 **4 个导出面板在游戏页根本没有挂载**（`kpChat` / `kpGameLog` / `plFeeds` / `plBottomBar` —— 聊天与记录改由 `room-ui.js#paintGameFeeds` 直绘，玩家工具栏改由 `diceBar` 承担），照 exports 面 1:1 实现会写出一批「永远不显示」的死代码 —— PRD 已在 C7 与 §6 逐条标出「只实现被挂载的那一份」。

**本 PRD 发现 1 个 P5 阻塞项（B1）和 2 个必须先裁决的口径（K1 / K4）**，见 §9：

- **B1（阻塞）**：`INTENT.DICE {direct:true}`、`INTENT.SAN_CHECK`、`INTENT.OPPOSED`、`INTENT.BOARD` 四个 intent 分支在 P4 被降级为 no-op（证据：`room_model_host_intent.dart:192-208` 与 `:214-243`）。**这四条正好是玩家端所有掷骰/检定/手绘板动作的唯一通道**。四个结算函数（`diceDirect` / `playerSanCheck` / `opposed` / `boardSelf`）P4 **都已实现**，只是没有接线 —— 修法是补 4 个 `case` 分支（约 10 行），**不是**加 POLICY 条目。若不修，P5 的「D100 / 技能检定 / SAN Check / 手绘板」按钮全部点了没反应。
- **K1**：旧版自 **v2.9.0** 起**已整体移除回退 UI**（证据：`room-ui.js:4935`、`room-ui.js:5143`，且全仓 `ui/` 无任何 `rollback*` 调用）。1:1 复刻 ⇒ **P5 不提供回退按钮**，因此 K1 在 P5 无触点。仍建议在 P5 的 Host 适配层对 `beforeSeq < 1` 做**闭区间守卫**（不改进规则层语义），以防将来接入。
- **K4**：建议「导入旧存档时一次性脱敏迁移 + UI 提示」，并给出**可机械判定的命中条件**（§9.2），默认在 P5 新增的纯函数里做，不动 `lib/domain` 已冻结语义。

---

## 1. 项目信息

### 1.1 原始需求复述

把 `coc7th-card-app/web/js/ui/room-ui.js`（5652 行，房间主界面）与 `ui/room-panels.js`（6173 行，功能面板）以**原生 Flutter widget** 移植到 `dice-realm`，复用 P4 已交付的房间规则层（`RoomHost` / `RoomClient` / `room_types` / `room_save`），实现「房间页 + 游戏页 + 全部功能面板」的完整交互。**禁止 WebView / HTML 渲染**。

### 1.2 已完成基线（不重复规划）

| 期 | 内容 | 状态 |
|---|---|---|
| P0 | COC7 规则层（`rules_coc7.dart` / `dice.dart` / `engine.dart`） | ✅ |
| P1 | 外壳 / 首页 / 新建角色 | ✅ |
| P2 | 车卡器（多步向导 + 属性 + 技能 + 背景） | ✅ |
| P3 | AI 车卡 + 云分享 + 设置页 | ✅ |
| P4 | **房间规则层**（`room_*` 16 文件：EVT 27 / INTENT 13 / POLICY 61 / Host / Client / save / rollback） | ✅ 927 组 0 红 |

P4 已交付、**P5 直接消费**的 Dart API：

```dart
// 全部从单行入口拿
import 'package:dice_realm/domain/room_model.dart';
```

| 用途 | API | 位置 |
|---|---|---|
| KP 端权威写口 | `LogRecord RoomHost.apply(RoomEvent evt, {bool persist = true})` | `room_model_host_core.dart:146` |
| 出站计划 | `List<SendPlan> plan(LogRecord)` / `planAll(List<LogRecord>)` | `:298` / `:361` |
| 按 seat 裁剪 | `SyncEnvelope syncFor(String seat)` / `Map? combatFor(String seat)` / `Map cropFor(String, Map, String to)` | `:507` / `:478` / `:376` |
| 玩家意图入口 | `List<SendPlan> intent(String seat, Map? msg)` | `room_model_host_intent.dart:109` |
| 动作分发 | `applyAction` / `act` / `consent` / `confirmPending` / `stateSyncAck` | `:383` / `:247` / `:305` / `:346` / `:370` |
| 回退 | `RollbackResult rollback(int beforeSeq)` / `List<SendPlan> rollbackPlan(int)` | `room_model_rollback.dart:56` / `:121` |
| 回合推进 | `nextTurn()` / `advanceRound(int)` | `:287` / `:377` |
| 本地候选池 | `bool addLocalActor(Map?)`（**唯一允许直写的 KP 本地字段**，返回 bool 不发包） | `room_model_actions_room.dart:1008` |
| 存档 | `Map save()` / `RoomHost adoptSave(Map)` / `String savePayload()` | `room_model_save.dart:71` / `:106` / `:104` |
| 断言/脱敏 | `sanitizeSheet` / `playerViewFromSave` / `parseSave` / `restoreHost` | `:366` / `:278` / 同文件 |
| 写回角色卡 | `CharacterRepoRoomCardSink.write(RoomCardPatch)`（内部唯一 `await repo.save(card)`） | `lib/repo/room_state_writer.dart` |
| 存档后端 | `InMemoryRoomSaveStore implements RoomSaveStore` | `lib/repo/room_save_store.dart` |
| 玩家端回放 | `ReceiveResult RoomClient.receive(Object? raw)` / `IntentEnvelope intent(op, p)` | `room_model_client.dart:80` / `:179` |

### 1.3 本期范围 / 非范围

**范围内**

- 房间页（招募中，`meta.status != IN_GAME`）：`paintHead` / `paintMembers` / `paintPanels` / `paintStatus` / `diceBar`
- 游戏页（`meta.status == IN_GAME`）：KP 12 / 玩家 13 个容器 + 三视角 + 全部被挂载的面板
- 全部**被实际挂载**的弹层（§5.9）
- 首页「骰境」入口 + `/room`、`/room/<code>` 路由
- 局部重绘 / 滚动保持 / 输入不丢 / 防连点
- 响应式（网格 / 单列）+ 触控适配 + 手势

**明确不在范围（写给架构师，防止越界）**

| 不做 | 归属 | 说明 |
|---|---|---|
| WebSocket / 中继 / 房间号发现 / 局域网广播 | **P6** | P5 只定义抽象 `RoomSession` 端口，附一个同进程 `LocalLoopback` 实现（§9.4） |
| 出站事件的序列化与发送 | **P6** | P5 只调 `RoomHost`/`RoomClient` 拿到 `List<SendPlan>` / 消费 `receive()`，**不自己拼 JSON** |
| `LogRecord.toWireJson()` 参与中继 | **P6（K3）** | P5 的日志展示**禁止**渲染 `toWireJson` 原始结构（§2 约束 C6） |
| 任何规则结算（掷骰 / 检定 / 伤害 / 疯狂 / 战斗顺序） | **P4** | UI 只发 intent、只画 state |
| 文件存档后端（`dart:io`） | 后续期 | P5 只用 `InMemoryRoomSaveStore`，`FileRoomSaveStore` 留构造位 |
| 角色卡字段增删改名 | **冻结** | 见约束 C3 |

---

## 2. 约束（工程硬约束，必须写入设计与验收）

> 来源：team-lead 布局决策 + 旧版 `core/room-rules.js` 文件头明文要求 + P4 架构约束。**每条都有验收含义，不是背景介绍。**

### C1 · 状态机是唯一权威：UI 只做两件事

> 旧版 `core/room-rules.js` 文件头原文要求：界面拿到结果只负责显示，**不得再算一遍**，否则一定出现「掷骰页说成功、记录里写失败」。

- UI **只**把 `state` 画出来、把用户操作变成 intent（`RoomIntent.*` 或 `INTENT.ACT` 的 action）。
- UI **禁止**：改 `state` / `RoomHost.state` 任一键；本地算成功等级、HP 变化、SAN 损失、先攻顺序。
- 例外（**唯一**）：KP 本地候选池 `RoomHost.addLocalActor(...)`（不进事件流、随 `save()` 落存档）、纯 UI 本地态（当前 tab、折叠态、画笔颜色、草稿输入框、zoom）。
- 验收：`lib/ui/room*` 内零命中 `state['` 的**赋值**、零 `rules?.check(` / `rollExpr(` / `opposedFull(` 调用。

### C2 · 可见性按 seat，UI 不能假设自己拿得到全部数据

`VIS.KP` 的 `plan()` 为空 —— **未授权客户端根本收不到数据**，不是收到后靠 UI 隐藏（`room_types.dart:104-112`、`room_model_host_core.dart:404-475`）。

| 数据 | KP（`seat == 'host'`） | 玩家本人 | 其他玩家 | 旁观者 |
|---|---|---|---|---|
| `member.sheet` | 全量 | 全量 | `{name, avatar, status{currentHP,maxHP,currentSAN,currentMP,maxMP,body,dying,unconscious}, mental(≤6), madnessCount, sanLoss:null, maxSAN:null}` | 同「其他玩家」 |
| `combat.order[].public` | 全量 | 未 `hpPublic` → **`hp`/`hpMax` 键被删** | 同左 | 同左 |
| 槽位 `secret` / `kpOnly` / `attrs` | 有 | **恒删** | 恒删 | 恒删 |
| `state.privates` | 只含 `to == host` 或非 SEAT 定向 | 只含发给自己的 | 只含发给自己的 | 只含发给自己的 |
| 秘密检定（`VIS.KP` / `VIS.SEAT`） | KP 收 `EVT.PRIVATE` 全文 | 只有发起人收全文，公共栏只见脱敏行「KP 秘密进行了一次检定」 | 只见脱敏行 | 只见脱敏行 |

- **UI 必须**：① 表格里 `pub['hp'] == null` 显示「隐藏」而不是 `0/null`；② 队友 SAN **只有当前值**（`maxSAN` 被置 null）→ 不得渲染「SAN 40 / 60」这种上限格式，只显示「SAN 40」；③ 队友疯狂明细只剩 `madnessCount`（整数），**不得**渲染症状名。
- 验收：widget 测试注入两份不同 seat 的 view，断言同一控件文案不同（§8 T-04）。

### C3 · 角色卡数据契约冻结

- 禁止新增 / 改名任何键（`character.dart` 既有键集合 + `_hpTouched` 等旧标记）。
- 任何「写回角色卡」必须经 `CharacterRepoRoomCardSink`（`lib/repo/room_state_writer.dart`），它内部唯一 `await repo.save(card)`（C5 兜底 `recalc` 与濒死卡守护）。
- 验收：`grep -c "await repo.save(" lib/repo/ lib/ui/` 命中数不增加。

### C4 · 布局：优先 1:1 复刻信息架构与功能完整性，允许移动端适配

**允许**：响应式断点、触控热区 ≥ 48dp、手势替代 hover、横竖屏、字号/间距微调、面板折叠。
**禁止**：删功能、改数据语义、改字段名、合并容器（旧版注释明写「每块是独立 DOM 容器，绝不把 5/6/7/8/9/10 合并成一个节点」，`room-ui.js:2890`）。

旧版网格判定是**唯一真相源**（`room-ui.js:2734-2748`，CSS 不再二次判定）：

```
grid = ((landscape && w >= 520) || w >= 820)
       && !(w >= 520 && w <= 599)      // 520–599 太窄塞不下 → 单列
       && h >= 290                     // 极矮横屏 → 单列
compact = grid && h <= 360            // 手机横屏档：行高下限收紧
```

Flutter 侧等价实现用 `LayoutBuilder` + `MediaQuery`，保留同一组阈值常量（含 `520/599/820/290/360`），**不要**换成 `breakpoints` 语义不同的一套。

其他旧版已定稿的适配行为（1:1 保留）：

- **不强制横屏**：跟随系统旋转（`applyOrientation` 恒发 `'auto'`，`room-ui.js:3201`）。
- **UI 缩放**：`60%–100%` 预设档 + 双指捏合 + 「⤢ 重置缩放」+ 点百分比进设置（`setZoom` / `bindPinchZoom` / `openZoomSheet`，`room-ui.js:3271/3327/3300`）。Flutter 用 `Transform.scale` + `InteractiveViewer` 或自算 scale，**注意**：缩放容器**不得**包住工具栏（旧版为此把 toolbar 移到 `.gp-zoom` 之外，`room-ui.js:2683-2686`）。

### C5 · 禁止 WebView / HTML 渲染

全部原生 widget。图片（素材 / 头像 / 完整人物卡信息图）用 `Image.memory` / `Image.file`，不用 `webview_flutter`。

### C6 · 日志展示不得绕开脱敏

- 游戏记录只读 `state.logs` / `state.dice` / `state.chats`（**reduce 已裁剪过的形状**）。
- **禁止**调 `LogRecord.toWireJson()` 拼 feed（K3：`toWireJson` 含 `{t,vis,to,p}` 原文，`p` 可能带明文；中继红线在 P6，但 UI 若拿它渲染会绕过 Q1 修正）。
- 渲染「检定」条目时只认 `{seat, text, at, kind, opp, redacted}`；`redacted == true` 的行**只能**显示 `text`（已是「KP 秘密进行了一次检定」），**不得**尝试还原。

### C7 · 弹层职责：只实现「被挂载的那一份」

旧版 `RoomPanels` 导出 33 项，但游戏页只 `mountPanel` 了 10 个名字（`paintKpRegions` / `paintPlRegions`，`room-ui.js:3105-3199`）。以下导出**游戏页零挂载**（旧版注释自己承认是「遗留死代码 / 兼容保留」）：

| 未挂载导出 | 证据 | P5 处置 |
|---|---|---|
| `plBottomBar` | `room-panels.js:3234` 注释「本 plBottomBar 为遗留死代码（0 调用方，真实玩家工具栏见 diceBar）」 | **不实现** |
| `plFeeds` | 骨架未挂载；聊天/记录由 `room-ui.js#paintGameFeeds` 直绘（`:3995`） | **不实现** |
| `kpChat` / `kpGameLog` | 同上（`paintGameFeeds` 直绘） | **不实现** |
| `plChat` / `plBottomBar` 同族 | 同上 | **不实现** |
| `modeSwitch` | 游戏页未挂载（探索/战斗切换在 KP 工具栏「⚔️ 战斗模式」与 `combat.end`） | 仅房间页 `render()` 用 |
| `renderExplore` / `render` / `renderCombat` | 房间页 `paintPanels` 用 `render`；`renderCombat` 作 `paintCombatRegion` 的 fallback | 房间页 + fallback |
| `mapCard` / `assetCard` / `playerBoardCard` / `explorationPanel` | 仅弹层「素材与地图」「我的手绘板」与房间页 | 按弹层实现 |

> ⚠️ 这是本期最容易做错的一处：**照 exports 面 1:1 会多写 ~2000 行永不显示的死 widget**。架构师拆任务时应以 §5.3/§5.5 的「被挂载面板」为准。

---

## 3. 产品目标（3 个清晰、正交的目标）

**G1 · 完整可跑的对局闭环（不带网络）**
一个人也能在自己手机上开团、开团前绑卡准备、开局后掷骰/检定/战斗/发线索/存档/结团 —— 全部经 P4 状态机结算，UI 不参与任何规则计算。衡量：单机闭环走查脚本 0 处「按钮点了没反应」、0 处「界面显示与游戏记录不一致」。

**G2 · 三种视角的可见性口径零泄漏、零误伤**
同一份 `state`，KP 看得到全量、玩家只看得到自己的秘密、旁观者只看得到公开信息；且**不是靠 UI 隐藏**（客户端本来就没收到）。衡量：跨视角探针（玩家 A 的 view 里搜不到玩家 B 的技能值 / 秘密检定明文 / 怪物隐藏 HP）。

**G3 · 手机上真的能用**
全部功能块在 360×640 竖屏（单列）与 780×320 横屏（compact 网格）都不溢出；所有可点元素热区 ≥48dp；长列表懒构建 + 输入不丢 + 防连点。衡量：两个目标尺寸的 golden 走查 + 滚动/输入/连点专项用例。

---

## 4. 用户故事

| # | 角色 | 故事 |
|---|---|---|
| US-1 | **KP（房主）** | 作为 KP，我想在开局前看到谁准备好了、谁绑了卡，这样我知道能不能开团。 |
| US-2 | **KP** | 作为 KP，我想在一屏里同时看到公开素材、玩家血量、战斗顺序、聊天与游戏记录，这样我不用来回切页就能推进剧情。 |
| US-3 | **玩家** | 作为玩家，我想随时看到自己的 HP/MP/SAN、队友状态和私密线索，并且**只能**看到该我看到的东西。 |
| US-4 | **玩家** | 作为玩家，我想掷 D100 / 技能检定 / SAN Check 并立刻在记录里看到权威端算出的结果，而不是「请求掷骰」四个字。 |
| US-5 | **旁观者** | 作为旁观者，我想围观聊天与公开记录，但不能操作任何东西、也看不到任何私密信息。 |
| US-6 | **KP（续玩）** | 作为 KP，我想把整局存进存档槽、下次恢复，且恢复后玩家血量/线索/战斗轮次都在。 |

---

## 5. UI 设计稿（本节为重头）

### 5.1 页面清单与导航

```
首页 (/)
  └─[房间入口 FAB/按钮]→ /room               房间入口页（无会话）
                          ├─ 创建房间（房间名/最大人数/允许旁观）→ /room/<code>  角色=KP
                          ├─ 加入房间（6 位房间号 + 昵称）      → /room/<code>  角色=玩家/旁观
                          └─ 续玩（本机未完结房间 / 存档槽）    → /room/<code>
/room/<code>
  ├─ 无会话        → 房间入口页
  ├─ 有会话 && meta.status != IN_GAME → 房间页（招募中）
  └─ 有会话 && meta.status ==  IN_GAME → 游戏页（KP 12 / 玩家 13 容器）
                                         └─ 离开/结团 → 回首页或房间页
```

- 状态翻转（`IN_GAME` ⇄ 非 `IN_GAME`）时**整页重建**（骨架不同），旧版 `paint()` 显式判 `pageRefs.isGame !== inGame → rerenderRoom()`（`room-ui.js:3454-3456`）。Flutter 用路由级 `key` 或直接 `pushReplacement` 保证不残留旧骨架。
- 身份切换（KP 转让 / 旁观变玩家）同样整页重建（`skel` 变了，`room-ui.js:3458-3460`）。

### 5.2 房间页（招募中）线框

```
┌─ 房间头卡 ─────────────────────────────────────────────┐
│ 房间名  [招募中]  [🟢已连接]                            │  ← meta.name / status / 连接态
│ 房间号  K3M9QZ                    ← 大字、可复制        │
│ 规则：COC 7th · 你是 KP                                 │
│ [服务地址块 → 复制地址 / 复制加入信息]   ← 仅 KP         │
│ [复制邀请链接]  [离开]                                  │
├─ 成员卡 ───────────────────────────────────────────────┤
│ 成员                          3/4 已准备               │
│  👤 老王 · 记者  HP 12/14 SAN 40   [已准备]  [手绘板]   │
│  👤 小美 · 侦探  HP 9/11  SAN 33   [未准备]            │
│  👁 旁观者 ×1                                          │
│ ——— KP 操作区 ———                                      │
│ [开始游戏(需全员准备)]  [结束房间]                     │
│ ——— 玩家操作区 ———                                     │
│ [我准备好了 / 取消准备]   [绑定角色卡 / 更换角色卡]     │
├─ 面板区（KP 才有）──────────────────────────────────────┤
│ [🧭探索 | ⚔️战斗]  ← modeSwitch（仅 KP）                │
│ explorationPanel: 场景名输入(仅KP) / 素材卡 / 地图卡 / 我的手绘板 |
│ kpPanel: 待你确认 / 待裁定对抗 / 待改状态请求 / 工具分组 |
├─ 状态条 ───────────────────────────────────────────────┤
│ [需我同意的改状态请求卡] [只给你看的信息卡] [我的角色卡] │
├─ 掷骰条（diceBar）──────────────────────────────────────┤
│ D100 | 奖励/惩罚骰 0-5 | 🕶暗骰 | D4 D6 D8 D10 | 扩展组   │
└─────────────────────────────────────────────────────────┘
```

**房间页区块表**

| # | 区块 | 渲染函数（行号） | 数据来源 | 交互 → intent/action | 可见性 |
|---|---|---|---|---|---|
| R1 | 房间头卡 | `paintHead` `room-ui.js:4318` | `meta.{name,status}`、`sess.code`、连接态 | `copyInvite`（本机剪贴板）、离开（本机断连） | 全部 |
| R2 | 服务地址块 | `hostAddrBlock` `:5502` | 读者设置里的 `roomBase`（P3 设置） | 复制地址 / 复制加入信息 | 仅 KP |
| R3 | 成员列表 | `paintMembers` `:4342` + `memberRow` `:4729` | `state.members`（`role/nickname/charName/sheet.status/ready/online/boundCharId`） | 点成员 → `memberDetailSheet`；KP 踢人 → `room.kick` | 全部 |
| R4 | 准备按钮 | `:4409` | `me.ready` / `me.charId` | `INTENT.READY {ready, charId}` | 仅玩家（旁观/已开局置灰） |
| R5 | 绑定角色卡 | `bindSheetSheet` `:4645` | `me.charId` / 本机 `repo` | `INTENT.CHAR {id,name,sheet:sheetSummary(c)}` | 仅玩家 |
| R6 | 开始游戏 | `:4380` | 全员 `ready` | `room.start` | 仅 KP |
| R7 | 结束房间 | `closeRoomConfirm` `:5514` | — | `room.close`（POLICY `twice` → 二次确认） | 仅 KP |
| R8 | 模式切换 | `modeSwitch` `panels:277` | `meta.mode` | 探索→`scene.mode`；战斗→先开 `combatPrepareSheet`；退回探索→`combat.end` | 仅 KP |
| R9 | 探索面板 | `explorationPanel` `panels:5535` | `state.scene` | `scene.set` / `asset.add,reveal,cover,del` | 场景名仅 KP；素材按 `revealed` |
| R10 | KP 工具 | `kpPanel` `panels:5673` | `host.pending`、`state.opposed`、`requestsBySeat` | 确认/取消 → `INTENT.CONFIRM`；9 项定向指令；`round.next`；`room.rules`；`saveSlotsSheet`；`endSession` | 仅 KP（旁观者见 `spectatorHint`） |
| R11 | 状态条 | `paintStatus` `:4918` | `state.requests`、`state.privates`、`me.sheet` | 同意/拒绝 → `INTENT.CONSENT {id, agree}` | 按 seat |
| R12 | 掷骰条 | `diceBar` `panels:5322` | 本机草稿 `{bonus,penalty,darkRoll}` | `INTENT.DICE` / `INTENT.ACT{op:dice.*}` | 非旁观；受操作锁 |

### 5.3 游戏页 · KP 视角 · 12 块

> 块号沿用旧版源码注释（`room-ui.js:2879-2890` 明确写「12 块」，块 1–11 有行内编号，块 12 = `.gp-status`）。

```
┌ 块1 .gp-topbar ─────────────────────────────────────────────────────────────┐
│ 克苏鲁的呼唤 7th                                                            │
│ 房间号 K3M9QZ · 👑 老李 · KP 主持 · 洋馆惊魂                                 │
│ [服务地址块（仅KP）]                                                        │
│              [当前场景：洋馆一层] [🟢已连接] [KP] [🔍探索] [👁3] [离开]      │
└─────────────────────────────────────────────────────────────────────────────┘
┌ .gp-main-kp （4 列 × 2 行；grid 时）────────────────────────────────────────┐
│ 行1 ┌块2 left≈55┐┌块3 tools≈80┐┌块4 中央公开素材 16:9 ┐┌─ 右列（跨两行）─┐│
│     │🗺地图      ││标记图标网格││  [战斗时叠加：行动顺序条] ││ 块5 场景检定   ││
│     │👹NPC·怪物  ││✏️画笔      ││  [素材舞台 + 缩放控件]    ││ ─────────────  ││
│     │🖼素材      ││🧽橡皮擦    ││                          ││ 块6 战斗列表 ▾ ││
│     │            ││👹放置单位  ││                          ││ 块7 玩家信息 ▾ ││
│     │            ││👤放置玩家  ││                          ││ （6/7 并排）   ││
│     │            ││🎨5 色      ││                          ││ 空档 foot      ││
│     │            ││🗑清除地图  ││                          ││ 块10 只给你看  ││
│ 行2 └────────────┘└────────────┘└──────────────────────────┘└────────────────┘│
│     ┌块8 💬聊天 ───────────────┐┌块9 📜游戏记录 ──────────┐                  │
│     │ [列表，最新在下]          ││ [logs+dice 时间序]      │                  │
│     │ [输入框][✨AI RP][发送]   ││                         │                  │
│     └──────────────────────────┘└─────────────────────────┘                  │
└─────────────────────────────────────────────────────────────────────────────┘
┌ 块12 .gp-status ────────────────────────────────────────────────────────────┐
│ （游戏页近乎空：KP 逻辑跳过 privates / 我的卡；玩家保留「需我同意」请求卡）  │
└─────────────────────────────────────────────────────────────────────────────┘
┌ 块11 .gp-toolbar（挂在 .game-page 上，**在缩放容器之外**）────────────────────┐
│ [⚔️战斗模式] [🧰KP工具(角标)] [🗺素材与地图] [💾保存本局] [⤢重置缩放] [100%]│
│ D100 | 奖励骰/惩罚骰 0-5 | 🕶暗骰 | D4 D6 D8 D10 | 🎯技能检定 🎲自定义骰子    │
│ 🧠SAN Check 🩹临时状态 📖规则参考                                            │
└─────────────────────────────────────────────────────────────────────────────┘
```

**KP 12 块详表**

| 块 | 容器（保留旧类名以便断言） | 用途 | 渲染函数（行号） | 数据来源 | 交互 → intent/action | 可见性 |
|---|---|---|---|---|---|---|
| **1** | `.gp-topbar.gp-kpbar` | 身份/房间号/场景/连接/模式/观众/离开 | `paintGameHead` `room-ui.js:3488`；`paintLinkChip` `:3546`；`roleChip` `:3563`；`hostAddrBlock` `:5502` | `meta.{name,kpName,status,mode}`、`state.scene.title`、`members[role==spectator]`、连接态（P6 端口） | 观众 chip → 只读弹层；离开 → 本机断连（**非** intent） | 全部；服务地址块仅 KP |
| **2** | `.gp-region-kp-left` + `.gp-left-icons`（≈55px） | KP 左窄栏三 tab：🗺地图 / 👹NPC·怪物 / 🖼素材 | `kpLeftColumn` `panels:1402`；子：`leftAssetsList` `:1256`、`leftActorsList` `:1377` | 地图：`scene.assets`(kind=map) + `host.localAssets`；NPC：`host.localActors` + `UI_STATE.pendingActors` + `combat.order` 复用；素材：全部 | 点素材 → `asset.reveal {id,revealed}`（secret 切换）；上传 → `asset.add`（**KP 本地池**）；删 → `asset.del`；加怪 → `addLocalActor`（本地，不发包）+ 开团时随 `combat.start.actors` 送 | 仅 KP |
| **3** | `.gp-region-kp-tools`（≈80px） | 标记 / 画笔 / 橡皮 / 5 色 / 放置单位 / 放置玩家 / 清除地图 | `kpToolColumn` `panels:1422`；`placeActorSheet` `:1504`；`placePlayerSheet` `:1478` | **纯 UI 本地态**（`UI_STATE.tool = {mode,icon,color,actorName,playerName}`），不读 state | 画笔落笔 → `map.stroke {color,width,pts}`；标点 → `map.mark {x,y,kind,label,revealed}`；橡皮 → `map.strokes.set {strokes}`（全量替换）；清除 → `map.clear` | 仅 KP |
| **4** | `.gp-center` / `.gp-region-kp-map` | 公开素材舞台（16:9）+ 战斗时叠加行动顺序条 + 缩放/全屏 | `kpMapArea` `panels:1540`；`mapStage` `:479`；`initiativeBar` `:372`；`zoomCtrl` `:899`；`openFullscreen` `:919`；平移 `mapPan`/`bindMapPan` `:582/:645` | `scene.{image,assets,marks,strokes}`；战斗时 `combat.order`（KP 全量，含隐藏 HP） | 拖动（放大后平移）；缩放 ±；全屏只读；落点由块 3 的工具态决定 | 全部（玩家 `editable=false`） |
| **5** | `.gp-region-kp-scene` | 场景检定：步骤进度 + 当前步裁定 + 自定义快速检定 + 打开编辑器 | `kpSceneCheckPanel` `panels:1818`；`sceneCheckSheet` `:4414`；`pushSceneCheck` `:4547` | `sceneCheck.{title,desc,steps,cursor,results}`；目标候选 = `playersOf()` 过滤 `targetBlocked` | 裁定档位 → `scene.check.step {stepId,seat,level}`（level ∈ `5 大成功 / 4 极难 / 3 困难 / 2 成功 / 0 失败 / -1 大失败`）；推送 → `check.request {seat,skill,difficulty,desc}`；编辑器 → `scene.check.push {title,desc,steps}` | 仅 KP |
| **6** | `.gp-region-kp-combat`（可折叠） | 战斗列表（顺序/名称/类型/HP/状态/行动）+ 怪物信息 tab + 未参战玩家加入 | `kpCombatPanel` `panels:1695`；`damageSheet` `:5299`；`addActorSheet` `:5258` | `combat.{order,turn,round}`；`slot.public.{hp,hpMax,hpPublic,dex,state}`；`slot.{kind,name,seat,actorId,slot,totalSlots}` | ▶ → `combat.next`；💥 → `combat.damage {slotId,damage,summary}`；＋加入 → `combat.enqueue {seat}`；＋加单位 → `combat.actor {actor}`；结束 → `combat.end`（二次确认） | 仅 KP（玩家同容器放裁剪视图） |
| **7** | `.gp-region-kp-players`（可折叠） | 玩家信息：头像/名字/HP/MP/SAN/手绘板入口 | `kpPlayerList` `panels:1925`；`viewBoardSheet` `:1981`；`memberDetailSheet` `room-ui.js:3603` | `members[role==player]`（`sheet.status` 或 `runtime` 现值）；手绘板缩略 = `scene.boards[seat].thumb`（**恒空**，见 §6.4 陷阱）→ 用 `host.boardBySeat[seat].strokes` 笔数/内容 | 点手绘板 → 全屏只读（读 KP 本机 `boardBySeat`）；点头像 → 成员详情 | 仅 KP |
| **8** | `.gp-region-kp-chat` + `.gp-chat-list` | 聊天列表（最新在下，保留最近 60 条）+ 输入行（**建页挂一次，重绘不重建**） | `paintGameFeeds` `room-ui.js:3995`；`appendFeed` `:4115`；`feedHead` `:3900`；`chatBar` `:5216`；`openChatEditor` `:5263`；`fullscreenFeed` `:3940` | `state.chats`（`{seat,nickname,text,at}`） | 发送 → `INTENT.CHAT {text}`；✨AI RP → `aiRpSheet`（结果**只填输入框不发**） | 全部；输入框旁观禁用 |
| **9** | `.gp-region-kp-log` + `.gp-glog` | 游戏记录：`logs` + `dice` 合并按 `at` 升序，最近 120 条；含检定/对抗结果卡/伤害/系统 | `paintGameFeeds` 同；`appendFeed`；`opposedResultCard` `:4043`；`diceBubble` `:5199`；`feedAvatarForSeat` `:4107` | `state.logs[]`（`{seq,seat,text,at,kind,opp,redacted}`）+ `state.dice[]`（`{seat,nickname,expr,value,rolls,level,secret,...}`） | 点标题 → 全屏只读 | 全部（`redacted` 行只显示脱敏文案） |
| **10** | `.gp-priv`（右列底、绝对定位、z-index 最低） | 「只给你看的信息」：线索/私密检定结果/暗骰结果，最近 12 条，正序（最新在下），新条到达高亮 | `paintPrivates` `room-ui.js:4779`；`fillPrivCard` `:4828`；`privHeadBar` `:4862`；`fullscreenPriv` `:4880` | `state.privates[]`（`{seq,title,text,at,kind}`） | 点某条 → 全文弹层；⛶ → 全屏 | 全部（内容按 seat 裁剪，**不是** UI 隐藏） |
| **11** | `.gp-toolbar`（挂 root，缩放容器外） | KP 快捷行 + 骰子条 + 扩展按钮组 | `paintGameToolbar` `room-ui.js:4189`；`diceBar` `panels:5322`；`d100ModPanel` `:3275`；`doRoll`/`doRollExpr` `:5510/:5485` | 本机草稿 `UI_STATE.{d100Mod,darkRoll}`；`combat.meta.mode` 决定战斗对抗可用性 | D100/D4-D10/自定义 → `INTENT.DICE {expr,direct:true,bonus,penalty}`（暗骰开 → `dice.dark`）；扩展组 → 各弹层 | 非旁观；受「整体操作锁」影响 |
| **12** | `.gp-status` | 「需要我处理」条：KP 改我状态的请求（玩家）/ 对抗待办 | `paintStatus` `room-ui.js:4918`；`consentCard` `:5026`；`checkReqCard` `:5060`；`checkOpposedPrompt` `:3882` | `state.requests[]`、`state.opposed` | 同意/拒绝 → `INTENT.CONSENT {id,agree}`；选怪 → `INTENT.OPPOSED {phase:'target',targetId}` | 玩家可见；KP 此块为空 |

**KP 折叠区域**（`attachFoldHeaders` `room-ui.js:2849`，竖屏才显示标题栏，横屏由 CSS 隐藏）：
`foldCombat`（⚔️ 战斗列表）· `foldPlayers`（👥 玩家信息）。玩家侧另有 `foldCard/foldMap/foldMates/foldScene/foldChat/foldLog/foldNotes/foldSketch`（`:2855-2869`）。

### 5.4 游戏页 · 玩家视角 · 13 个容器

> **实读修正**：旧版注释称「用户玩家线框 12 块」（`room-ui.js:3011/3129`），但按 `buildPlSkeleton` 实际建的容器数是 **13** —— 因为 v2.1.8 把「我的手绘板」从 `plTeammates` 里拆成**独立块**（`:3138 splitSketchIntoOwnBlock`），v2.1.6 又新增了「笔记栏」。源码注释是**过期**的，以容器数为准。KP 侧仍是 12（源码行内编号 1–11 + `.gp-status`）。
>
> 玩家骨架与 KP **同构但不同内容**（`buildPlSkeleton` 注释：「与 KP 同构（同 4 栏 + 3 栏结构），差异只在栏内放什么」，`room-ui.js:2972`）。

```
┌ 块1 顶栏（同 KP，但 whoLine = 🎭 当前玩家：老王；无服务地址块）────────────┐
└─────────────────────────────────────────────────────────────────────────────┘
┌ .gp-main-pl（3 列）─────────────────────────────────────────────────────────┐
│ 左列                中列                                右列              │
│ ┌块2 我的角色卡──┐  ┌块3 公开素材 16:9──────┐  ┌块7 场景检定─────────┐  │
│ │头像 名字 职业   │  │ [只读舞台]            │  │ KP 推来的检定 /      │  │
│ │HP ▓▓▓▓ 12/14   │  │ [缩放][⛶全屏]         │  │ 用自己技能主动检定    │  │
│ │MP ▓▓ 8/10      │  │ [公开素材九宫格]       │  ├块8 队友信息 ────────┤  │
│ │SAN ▓▓▓ 40      │  ├块3' 战斗轮次条────────┤  │ 👥队友（N）▾        │  │
│ │[📝状态管理]     │  │ （探索态战斗信息在此） │  │ 名字 体/精 HP SAN   │  │
│ │[⏩推进1轮]      │  ├块4 💬聊天 ────────────┤  ├块9 只给你看的信息──┤  │
│ │—角色状态—      │  │ [列表][输入][✨][发送]│  │ 📩 线索（⛶全屏）    │  │
│ │身体：正常       │  ├块5 📜游戏记录 ────────┤  ├块10 ✏️我的手绘板──┤  │
│ │精神：正常       │  │ [logs+dice 时间序]    │  │ [画布][‹1/1›][笔/擦]│  │
│ │疯狂：—          │  │                       │  ├块11 📝笔记栏 ──────┤  │
│ └────────────────┘  └───────────────────────┘  └─────────────────────┘  │
│   （块6 战斗列表：探索态 `gp-explore` 下隐藏/收起；战斗态出现在右列）      │
│   （竖屏单列时「块9 只给你看的信息」order:-1 提前到顶部常驻）              │
└─────────────────────────────────────────────────────────────────────────────┘
┌ 块13 状态条：[KP 请求改我状态 → 同意/拒绝] [对抗待办 → 选怪/确认] ──────────┐
┌ 块12 工具栏（root 级，缩放外）─────────────────────────────────────────────┐
│ [📋人物卡查看] [✏️我的手绘板] [⤢重置缩放] [100%]                            │
│ D100 | 奖励/惩罚骰 | 🕶暗骰 | D4 D6 D8 D10 | 🎯技能检定 🎲自定义骰子          │
│ ⚔战斗对抗(仅本人行动轮+战斗模式) 🧠SAN Check 🩹临时状态 🩺急救/医疗/精神分析   │
│ 🎒物品道具 📖规则参考                                                       │
└─────────────────────────────────────────────────────────────────────────────┘
```

**玩家 13 个容器详表**

| 块 | 容器 | 用途 | 渲染函数（行号） | 数据来源 | 交互 → intent/action | 可见性 |
|---|---|---|---|---|---|---|
| **1** | `.gp-topbar` | 同 KP（无服务地址块） | `paintGameHead` `:3488` | 同上，`whoLine` = `🎭 当前玩家：<昵称>` | 离开 → 本机断连 | 全部 |
| **2** | `.gp-region-pl-card` | 我的角色卡：头像/名/职业/HP·MP·SAN 条/状态管理/推进1轮/角色状态摘要/撕卡提示/临时卡条 | `plCharacterCard` `panels:2779`；`charVitals` `:2930`；`tempCardBar` `:2723`；`selfStateSheet` `:3492` | `me.sheet`（本人 = 全量）+ `me.runtime` | 📝状态管理 → `state.self {status,reason,mental?}`（免 KP 同意）/ HP·MP·SAN 数字 → `state.edit.self`（POLICY `confirm:kp` → 进 pending）；⏩推进1轮 → `INTENT.ACT{op:'madness.advance'}`（**不受操作锁限制**，400ms 防连点） | 仅本人 |
| **3** | `.gp-region-pl-map` + `.gp-combat-strip` | 公开素材只读舞台 + 缩放/全屏 + 已公开素材九宫格；探索态战斗信息收进 `combat-strip` | `plMapArea` `panels:3054`；`publicAssets` `:949`；`mapStage(ctx,false)` `:479` | `scene.image/assets/marks/strokes`（KP 已公开部分）；`combat.order`（裁剪后） | 只读；点素材 → 全屏只读；⛶ → 全屏 | 全部（不可编辑） |
| **4** | `.gp-region-pl-chat` | 聊天（最近 60 条）+ 输入行 + AI RP | `paintGameFeeds` `:3995`；`chatBar` `room-ui.js:5216` | `state.chats` | `INTENT.CHAT {text}` | 全部；输入框旁观禁用 |
| **5** | `.gp-region-pl-log`（在 `.gp-region-pl-feeds` 内） | 游戏记录（120 条，含对抗结果卡） | `paintGameFeeds`；`appendFeed`；`opposedResultCard` | `state.logs` + `state.dice` | 全屏查看 | 全部 |
| **6** | `.gp-region-pl-combat`（右列） | 战斗列表（玩家视角：怪物隐藏 HP 显示「隐藏」）；探索态由 `gp-explore` 类收起 | `paintCombatRegion` `room-ui.js:3087` → `kpCombatPanel`（复用，含裁剪） | `combat.order`（裁剪） | 玩家不推进；仅看 | 全部 |
| **7** | `.gp-region-pl-scene` | 场景检定（玩家侧）：**只读**展示 KP 推来的检定 + 用自己角色卡技能主动检定 | `plSceneCheckPanel` `panels:4214`；`localSkills` `:4383`；`skillCheckSheet` `:3329` | `sceneCheck.*`（只读）+ 本机 `repo` 角色卡技能 | 主动检定 → `INTENT.DICE {expr:'1D100',direct:true,base,label}` | 仅玩家 |
| **8** | `.gp-region-pl-mates` | 队友列表（可收起）+ 每人 HP/SAN + 身体/精神标签 + 手绘板缩略 | `plTeammates` `panels:3093`；`bodyViewOf` `:2232` | `members[role==player]` 中排除自己；**他人视图**：`name/avatar/status{currentHP,currentSAN,currentMP,maxHP,maxMP,body,dying,unconscious}/mental(≤6)/madnessCount` | 收起/展开（本地态）；查看队友手绘板缩略 | 全部（旁观见全部玩家，无本人行） |
| **9** | `.gp-priv`（右列，队友栏正下方） | 只给你看的信息 + 标题栏 + ⛶ 全屏 | `paintPrivates` `:4779`；`privHeadBar` `:4862`；`fullscreenPriv` `:4880` | `state.privates` | 点条 / ⛶ | 按 seat |
| **10** | `.gp-pl-sketch` | 我的手绘板（独立块）：画布 + `‹ 1/1 ›` 分页 + 画笔/橡皮切换 + 清空 | `miniBoard` `panels:3164`；`splitSketchIntoOwnBlock` `room-ui.js:3138`；`bindDraw` `panels:1014`；`bindEraseStage` `:1190`；`eraseStrokeSegments` `:801` | `state.board.strokes` | 落笔 → `INTENT.BOARD {strokes}`（全量替换，最多 4000 笔）；擦除 → 手势末尾一次 `INTENT.BOARD`；清空 → `INTENT.BOARD {strokes:[]}` | 仅本人（他人 / KP 只能看缩略、只读） |
| **11** | `.gp-pl-notes` | 笔记栏：玩家个人笔记，**本机保存、不上传** | `notesPanel` `panels:3894` | 本机存储（不进 `state`） | 新增/编辑/删除（纯本地） | 仅本机使用者 |
| **12** | `.gp-toolbar`（root 级） | 快捷行（人物卡查看 / 我的手绘板 / 缩放）+ 骰子条 + 扩展组 | `paintGameToolbar` `:4189`；`diceBar` `panels:5322`；`openCharSheet` `:3313`；`cardImageSheet` `room-ui.js:3641` | 本机草稿 | 同 KP；扩展组含玩家独有 3 项（⚔战斗对抗 / 🩺急救医疗 / 🎒物品道具，`p[2]==='pl'` 门控） | 非旁观；受操作锁 |
| **13** | `.gp-status` | 「需要我处理」：改状态请求卡 + 对抗待办提示 | `paintStatus` `:4918`；`consentCard`/`checkReqCard`/`checkOpposedPrompt` | `state.requests`、`state.opposed` | `INTENT.CONSENT {id,agree}` / `INTENT.OPPOSED` | 仅玩家（旁观通常为空） |

### 5.5 旁观者视角差异

| 维度 | KP | 玩家 | 旁观者 |
|---|---|---|---|
| 骨架 | `.gp-kp` + `gp-main-kp`（4 列 2 行，**12 容器**） | `.gp-pl` + `gp-main-pl`（3 列，**13 容器**） | **复用玩家骨架 `.gp-pl`**（`renderGamePage` 只判 `isKp`，`room-ui.js:2649-2662`） |
| 左列（KP 块2 / PL 块2） | KP 左窄栏（素材/NPC/地图三 tab） | 我的角色卡 | `plCharacterCard` 走 `findMe(ctx)==null` 分支 → 文案「你是旁观者，没有角色卡。」 |
| 玩家/队友区（KP 块7 / PL 块8） | 玩家信息（含手绘板入口、成员详情） | 队友列表（排除自己） | 全员列表（无本人行） |
| 聊天（KP 块8 / PL 块4） | 可用 | 可用 | **输入禁用**（`isSpec` → `disabled`） |
| 掷骰条（KP 块11 / PL 块12） | 全部可用 | 全部可用 | **全部禁用**（`isSpec`） |
| 准备 / 绑定卡 | — | 可用 | 禁用（文案「旁观中（不能准备）」） |
| 房间页 KP 工具 | `kpPanel` | — | `spectatorHint`「你是旁观者，不能操作房间。」 |
| 私密线索（KP 块10 / PL 块9） | 只有收件人为 `host` 的 | 只有发给自己的 | 只有发给自己的（通常为空） |
| 权威端拒绝 | — | — | `intent()` 里 `role == spectator` → `ready` 被拒、`diceDirect` 返回「旁观者不能掷骰」 |

**UI 要求**：旁观者**不得**出现任何「做了会静默失败」的可用按钮。旧版教训（`room-ui.js:3178-3183` 注释）：玩家侧误挂了 KP 的 `kpSceneCheckPanel`（含「推送给玩家」按钮），点下去权威端静默拒绝、界面却弹「推送成功」。**P5 硬要求**：按钮的可见性与 `POLICY` 的 `roles` 必须同源（§5.9 表），不可用时要么不渲染、要么 `disabled` + 明确原因。

### 5.6 三角色 × 功能块 可见性矩阵

> 以**功能块**为行（避免块号在两侧不一致造成误读），并列给出两侧块号。

| 功能块 | KP 块号 | PL 块号 | KP | 玩家 | 旁观 | 备注 |
|---|---|---|---|---|---|---|
| 顶栏 | 1 | 1 | ✅ +服务地址 | ✅ | ✅ | 连接态始终可见 |
| KP 左窄栏 | 2 | — | ✅ | ❌ | ❌ | 玩家同位置是「我的角色卡」 |
| KP 工具窄栏 | 3 | — | ✅ | ❌ | ❌ | |
| 我的角色卡 | — | 2 | ❌ | ✅ 本人 | 占位文案 | 旁观者走「没有角色卡」分支 |
| 公开素材 | 4 | 3 | ✅ 可编辑 | ✅ 只读 | ✅ 只读 | 笔迹/标记归一化坐标 |
| 战斗列表 | 6 | 6 | ✅ 可推进 | ✅ 只读 | ✅ 只读 | 怪物 HP 按 `hpPublic`；未公开显示「隐藏」 |
| 场景检定 | 5 | 7 | ✅ 裁定/推送 | ✅ 只读 + 自查 | ✅ 只读 | **面板必须分流**：`kpSceneCheckPanel` vs `plSceneCheckPanel` |
| 玩家 / 队友信息 | 7 | 8 | ✅ 全量 + 手绘板全屏 | ✅ 他人裁剪视图 | ✅ 全体裁剪 | 他人 SAN 只显当前值、无疯狂明细 |
| 聊天 | 8 | 4 | ✅ | ✅ | ✅ 只读 | 输入行不随重绘重建 |
| 游戏记录 | 9 | 5 | ✅ | ✅ | ✅ | `redacted` 只显脱敏文案 |
| 只给你看的信息 | 10 | 9 | ✅ 仅 `to==host` | ✅ 仅自己 | ✅ 仅自己 | 数据本就裁剪，UI 不二次过滤 |
| 我的手绘板 | — | 10 | 只读全屏查看他人 | ✅ 本人可画 | ❌ | `VIS.SEAT` 单发，他人收不到 |
| 笔记栏 | — | 11 | ❌ | ✅ 本机 | ✅ 本机 | 不进 `state`、不上传 |
| 工具栏 | 11 | 12 | ✅ | ✅ | 禁用 | 必须在缩放容器外 |
| 状态条 | 12 | 13 | 空 | ✅ 请求/对抗 | 空 | |

### 5.7 弹层（Sheet）清单

旧版弹层是 `UI.sheet({title, body, key})`，`body` 可为**函数**（→ 底层状态变化后弹层自动重画，`room-ui.js:4312 refreshSheet`）。Flutter 侧建议统一一个 `showRoomSheet(...)` helper（`showModalBottomSheet` + 可刷新 body），并在每次 `paint` 后调 `refreshTopSheet()` 等价物。

**P0 必做（12 个）**

| 弹层 | 行号 | 触发点 | 主要控件 → intent/action |
|---|---|---|---|
| 绑定角色卡 | `room-ui.js:4645` | 房间页「绑定/更换角色卡」 | 选卡 → `INTENT.CHAR {id,name,sheet}`；清空 → `INTENT.CHAR {id:'',name:'',sheet:{name:'',madness:[],mental:['正常']}}` |
| 状态管理 | `panels:3492` | 玩家卡「📝状态管理」 | 身体 chips → `state.self {status:{body,dying,unconscious},reason}`；精神状态 → `state.self {mental}`；HP/MP/SAN 数字 → `state.edit.self` |
| 人物卡 | `panels:3313`（+ 信息图 `room-ui.js:3641`） | 工具栏「📋人物卡查看」 | 只读 |
| 技能检定 | `panels:3329` | 工具栏「🎯技能检定」 | 选技能 → `INTENT.DICE {expr:'1D100',direct:true,base,label}` |
| SAN Check | `panels:3394` | 工具栏「🧠SAN Check」 | 成功/失败损失 → `INTENT.SAN_CHECK {okLoss,loss}` |
| 自定义骰子 | `panels:3454` | 工具栏「🎲自定义骰子」 | `INTENT.DICE {expr,direct:true,secret}` |
| 暗骰 | `panels:2372` | 骰子行「🕶暗骰：开」+ 投掷 | `dice.dark {sides,count,bonus,reason}` |
| 结算伤害 | `panels:5299` | 战斗列表「💥」 | `combat.damage {slotId,damage,summary}` |
| 存档 | `panels:5997` | 工具栏/ KP 工具「💾保存本局」 | 新建 → `host.save()` + `saveStore.put`；载入 → `adoptSave`；删除 |
| 续玩 | `panels:5120` | 房间入口 | `room.resume {code}` 或 `adoptSave` |
| KP 工具 | `panels:5673`（`renderKp`） | 工具栏「🧰KP工具」 | 见 §5.8 |
| 递线索 | `panels:5902` | KP 工具「📩递线索」 | `scene.clue {seat,title,text}` |

**P1 必做（有功能完整性要求，但可第二批）**

`战斗模式 · 选择参战单位`（`panels:4080` → `combat.start {actorIds,actors,pcSeats}`）· `⚔对抗` 二级菜单（`panels:4655`）· `通用对抗`（`panels:4691` → `check.opposed`）· `攻击对抗`（`panels:4752`）· `⚔武器对抗`（`panels:4910` → `INTENT.OPPOSED`）· `裁定对抗申请`（`panels:4997` → `check.opposed {reqId,...}`）· `⚔选择伤害目标`（`panels:5076` → `INTENT.OPPOSED {phase:'target'}`）· `场景检定编辑器`（`panels:4414` → `scene.check.push`）· `要求检定`（`panels:5870` → `check.request`）· `请求修改状态`（`panels:5839` → `state.request`）· `⚖检定成败阈值`（`panels:2614` → `room.rules`）· `修改玩家状态/造成伤害/临时状态/给物品/SAN Check/治愈/急救医学/急救医疗精神分析/暗骰`（KP 定向 9 项，`panels:2021-2587`）· `放置单位/放置玩家`（`panels:1478/1504`）· `物品道具`（`panels:3955` → `item.del`）· `新增怪物/NPC`（`panels:5258`）· `AI RP`（`room-ui.js:5364`）· `UI 缩放设置`（`room-ui.js:3300`）· `角色状态`（`room-ui.js:3603`）

**P2（可延后，不阻塞出包）**

`规则参考`（`panels:3997`）· `音乐控制台`（`panels:4029`，本机 BGM）· `临时状态`（`panels:3467`，旧版实现为聊天提示）· `观众名单`（`room-ui.js:3506` 内联）· `网络自检 / 局域网自检 / 附近的房间 / 还没连上 WiFi / 房间服务地址`（`room-ui.js:918/1080/1604/1541/1705`，**依赖 P6 传输**）· 游戏历史记录归档（`room-ui.js:565`）

### 5.8 KP 工具弹层（`kpPanel`）结构与权限

```
[kpPanel]
├── 待你确认（pending: need ∈ {twice, kp}）        → INTENT.CONFIRM（side.confirmAct(q.op,true/false)）
├── 待处理的对抗申请（state.opposed.phase=='await_kp'） → check.opposed / 取消
├── 待处理的改状态请求（stateRequestCard）          → 同意/拒绝
├── 工具 · 回合与时间
│     └── ⏭ 进入下一回合                          → round.next            [kp]
├── 工具 · 检定与骰子
│     ├── 🎲 要求检定                              → check.request         [kp]
│     └── ⚖ 检定成败阈值                          → room.rules            [kp]
├── 工具 · 战斗
│     └── ⚔ 对抗                                   → check.opposed / 二级菜单  [kp]
├── 定向指令卡（9 项 · 直接生效 · 无需玩家同意）
│     ├── 造成伤害   → sheet.damage     [kp]
│     ├── 临时状态   → sheet.tempstatus [kp]
│     ├── 给物品     → sheet.item       [kp]
│     ├── SAN Check  → sheet.sancheck   [kp]
│     ├── 暗骰       → dice.dark        [kp]
│     ├── 治愈不定疯狂 → madness.cure   [kp]（confirm 由 POLICY 定义，KP 自发起即视为确认）
│     ├── 治愈重伤/濒死/昏迷 → sheet.healwound [kp, player] confirm:kp
│     ├── 🚑 急救/医学 → aid.apply      [kp, player] confirm:kp
│     └── SAN 大失败追加理智损失 → sheet.sanloss [kp]
├── 工具 · 场景与素材
│     └── 📩 递线索                                → scene.clue           [kp]
└── 工具 · 房间管理
      ├── ✉️ 邀请加入（本机剪贴板）                 → 无 intent
      ├── 💾 保存本局                              → saveStore.put
      └── 🏁 结团                                  → session.end          [kp] confirm:twice
```

### 5.9 控件 → intent → 最小权限全表

> **口径**：`INTENT.*`（13 项）走 `RoomHost.intent(seat, msg)`，**不经 POLICY**（与旧版 `Host.intent` 一致）；`INTENT.ACT {op}`（61 个 action）走 `needs(role, op)` 闸门。下表「权限」列 = `kRoomPolicy[op].roles` / `confirm`。

| 控件 | 位置 | 载荷 | intent / action | 权限（POLICY） |
|---|---|---|---|---|
| 发送聊天 | 块 8/4 输入行 | `{text}` | `INTENT.CHAT` | `chat` [kp,player] |
| 我准备好了 | 房间页成员卡 | `{ready,charId}` | `INTENT.READY` | `ready.set` [player] |
| 绑定/更换角色卡 | 房间页 | `{id,name,sheet}` | `INTENT.CHAR` | `char.share` [player] |
| 开始游戏 | 房间页 KP 区 | — | `room.start` | [kp] |
| 踢人 | 成员行 | `{seat}` | `room.kick` | [kp] |
| 结束房间 | 房间页 | — | `room.close` | [kp] `twice` |
| 结团 | KP 工具 | — | `session.end` | [kp] `twice` |
| 模式切换→探索 | 房间页 | `{mode:'EXPLORATION'}` | `scene.mode` | [kp] |
| 结束战斗 | 战斗面板 | — | `combat.end` | [kp] |
| 战斗模式（进战斗） | 工具栏 | `{actorIds,actors,pcSeats}` | `combat.start` | [kp] |
| 场景名 | 房间页 | `{scene:{title}}` | `scene.set` | [kp] |
| 素材公开/隐藏 | 素材格 | `{id,revealed}` | `asset.reveal` | [kp] |
| 素材封面 | 素材卡 | `{id}` | `asset.cover` | [kp] |
| 删素材 | 素材卡 | `{id}` | `asset.del` | [kp] |
| 上传素材 | 素材卡 | `{asset:{kind,name,data}}` | `asset.add` | [kp] |
| 画一笔 | 地图 | `{color,width,pts}` | `map.stroke` | [kp] |
| 标点 | 地图 | `{x,y,kind,label,revealed}` | `map.mark` | [kp] |
| 橡皮一划 | 地图 | `{strokes}` | `map.strokes.set` | [kp] |
| 清除地图 | 工具窄栏 | `{strokesOnly?}` | `map.clear` | [kp] |
| 我的手绘板落笔/擦/清空 | 块 10(PL) | `{strokes}` | `INTENT.BOARD`（→ `boardSelf`） | intent 通道（**见 B1**） |
| D100 / D4-D10 / 自定义骰式 | 骰子条 | `{expr,direct:true,bonus,penalty}` | `INTENT.DICE` | intent 通道（**见 B1**） |
| 🕶暗骰投掷 | 骰子条 | `{sides,count,bonus,reason}` | `dice.dark` | [kp] |
| 🎯技能检定 | 工具栏 | `{expr:'1D100',direct:true,base,label}` | `INTENT.DICE` | intent 通道（B1） |
| 🧠SAN Check（玩家） | 工具栏 | `{okLoss,loss}` | `INTENT.SAN_CHECK` | intent 通道（B1） |
| SAN Check（KP 定向） | KP 工具 | `{seat,okLoss,loss,reason}` | `sheet.sancheck` | [kp] |
| ⚔战斗对抗（玩家） | 工具栏 | `{phase:'apply',weaponId,targetId,...}` | `INTENT.OPPOSED` | intent 通道（B1） |
| ⚔通用对抗（KP） | KP 工具 | `{...}` | `check.opposed` | [kp] |
| 裁定对抗申请 | 块 12 | `{reqId,attack,damage,...}` | `check.opposed` | [kp] |
| 🎲要求检定（KP） | KP 工具 | `{seat,skill,difficulty,desc}` | `check.request` | [kp] |
| 场景检定裁定 | 块 5 | `{stepId,seat,level}` | `scene.check.step` | [kp] |
| 场景检定编辑器推送 | 弹层 | `{title,desc,steps}` | `scene.check.push` | [kp] |
| 递线索 | KP 工具 | `{seat,title,text}` | `scene.clue` | [kp] |
| 状态管理（身体/精神） | 块 2(PL) | `{status,reason,mental?}` | `state.self` | [player,kp] |
| 状态管理（HP/MP/SAN 数字） | 块 2(PL) | `{status}` | `state.edit.self` | [player] **confirm:kp** |
| ⏩推进 1 轮 | 块 2(PL) | — | `madness.advance` | [player,kp] |
| 同意/拒绝改状态 | 块 12 | `{id,agree}` | `INTENT.CONSENT` | 本人 |
| 选伤害目标 | 块 12 | `{phase:'target',targetId}` | `INTENT.OPPOSED` | intent 通道（B1） |
| 战斗列表 ▶ | 块 5 | — | `combat.next` | [kp] |
| 💥结算伤害 | 块 5 | `{slotId,damage,summary}` | `combat.damage` | [kp] |
| ＋加入战斗 | 块 5 | `{seat}` | `combat.enqueue` | [kp] |
| ＋加单位 | 块 5 | `{actor}` | `combat.actor` | [kp] |
| ⏭进入下一回合 | KP 工具 | — | `round.next` | [kp] |
| ⚖检定成败阈值 | KP 工具 | `{critThreshold,fumbleThreshold}` | `room.rules` | [kp] |
| 治愈不定疯狂 | KP 工具/PL | `{seat?}` | `madness.cure` | [player,kp] `kp` |
| 治愈重伤 | KP 工具/PL | `{seat}` | `sheet.healwound` | [player,kp] `kp` |
| 急救/医学 | KP 工具 | `{seat,targetSeat,skill}` | `aid.apply` | [player,kp] `kp` |
| 急救/医疗/精神分析（玩家） | 工具栏 | `{op:'aid.apply'\|'aid.psycho',seat,targetSeat,skill}` | `INTENT.ACT` | [player,kp] `kp` |
| 给物品 | KP 工具 | `{seat,name,qty,note}` | `sheet.item` | [kp] |
| 删物品 | 物品弹层 | `{id}` | `item.del` | [kp,player] |
| 请求改状态（KP） | KP 工具 | `{seat,reason,change}` | `state.request` | [kp] |
| SAN 大失败追加 | KP 工具 | `{seat}` | `sheet.sanloss` | [kp] |
| 房间挂起/复活 | — | — | `room.suspend` / `room.resume` | [kp] |

**验证方法**：`kRoomPolicy` 是唯一权限源。建议 P5 写一条 widget 探针，遍历本表每一行，用 `needs(currentRole, op)` 断言「控件可点 ⟺ allowed」，防止界面与权限表漂移。

### 5.10 响应式与手势

| 场景 | 旧版行为 | Flutter 落地 |
|---|---|---|
| 宽屏网格 | `grid` 条件见 C4 | `LayoutBuilder` 计算同一条件，切 `Row/Column` 组合 |
| 520–599 宽 | 强制单列 | 同 |
| 高 < 290 | 单列 | 同 |
| 高 ≤ 360 | `gp-compact` 收紧行高 | 收缩 `minimumSize` / padding |
| 竖屏单列 | `.gp-priv` `order:-1` 提前到顶部常驻 | `Column` 里把它放第一位 |
| 旋转 | 跟随系统，不锁横屏 | 不调 `SystemChrome.setPreferredOrientations` |
| 缩放 | 捏合 + 60–100% 预设 + 重置 | `GestureDetector.onScaleUpdate` + 工具栏在缩放容器**外** |
| hover | 桌面端 title 提示 | 长按 `Tooltip` 替代 |
| 触控热区 | 旧版 `btn.sm` 偏小 | 全部 ≥ 48dp（`minimumSize: Size(48,48)` 或 `MaterialTapTargetSize.padded`） |
| 画布手势 | `pointerdown/move/up`，`bindTap` 防误触 | `Listener`/`GestureDetector`，笔迹归一化坐标 `[0,1]`（跨设备一致，`panels:801`） |
| 输入框 | 点一下全屏编辑（`openChatEditor`） | 弹全屏 `TextField`，确认只回填不发送 |

### 5.11 UI 层结构建议（给架构师，非强制）

```
lib/ui/room/
  room_routes.dart            路由与入口（/room, /room/<code>）
  room_entry_page.dart        房间入口页（创建/加入/续玩）
  room_lobby_page.dart        房间页（招募中）
  room_game_page.dart         游戏页壳体 + 12/13 个容器 + 视角路由
  room_session.dart           RoomSession 抽象 + LocalLoopback 实现（§9.4）
  view/                       state → 只读视图模型（纯函数，可单测）
    room_view.dart            meta/members/feeds 的派生（不调规则）
    member_view.dart          HP/MP/SAN 提取（兼容 sheet.status 与 runtime）
    feed_view.dart            logs+dice 合并排序、redacted 处理
  widgets/                    可复用块（逐块一个 widget）
    gp_topbar.dart  gp_kp_left.dart  gp_kp_tools.dart  gp_map_stage.dart
    gp_scene_check.dart  gp_combat_list.dart  gp_players.dart
    gp_chat.dart  gp_log.dart  gp_privates.dart  gp_toolbar.dart  gp_status.dart
    gp_pl_char_card.dart  gp_pl_mates.dart  gp_pl_sketch.dart  gp_pl_notes.dart
  sheets/                     弹层（每个一个文件或按组）
  painter/stroke_painter.dart 笔迹/标记 CustomPainter（归一化坐标）
```

**关键**：`view/` 是纯函数层，**不 import `package:flutter`**（可纯 Dart 单测），也不调 `RoomRulesPort`。这样「UI 不算规则」这条约束在结构上就成立，而不是只靠 review。

---

## 6. 旧版 UI 组件清单（块 → 面板 → 控件，含行号）

> 目的：给架构师拆 widget 的依据。**不要求逐行翻**，但**被挂载**的面板必须逐个过一遍。

### 6.1 `room-ui.js`（5652 行）三层归纳

| 层 | 名称 | 行号 | 说明 |
|---|---|---|---|
| **壳/基建** | | | |
| T | 常量表 `T()`（ROLE/STATUS/INTENT/STATUS_TEXT） | 127 | 桥接 `RoomModel` 常量 |
| el / timeText / roleText / chip / banner / setBanner | 136-225 | 极小的 DOM helper；P5 用 widget 替代 |
| selectCtl | 280 | 下拉包装（等价 `DropdownButton`） |
| **入口页** | | | |
| renderEntry | 376 | 房间入口页（创建/加入/续玩/自检/局域网） |
| resumeMineCard / recentCard / unfinishedCard / identityCard / inviteCard / ruleCard / serviceCard / lanCard / manualJoinCard | 599-1705 | 入口页内的卡片 |
| createSheet / joinSheet / manualJoinSheet / roomBaseSheet / lanCheckSheet / selfCheckSheet / noWifiSheet / lanCreate / lanFind | 918-1870 | 入口弹层（**局域网部分属 P6**） |
| **会话/连接** | | | |
| startHost / startPlayer / resumeMine / reopenJoined / resumeRoomImpl / onLinkState / dissolveFromLink / maybeDissolved / maybeKicked | 2018-2478 | P6 边界；P5 用 `RoomSession` 端口替换 |
| **房间页** | | | |
| renderRoom | 2478 | 房间页壳（含房间号不一致的四级回退） |
| paintHead | 4318 | R1 |
| paintMembers / memberRow / readyText / findMe | 4342/4729/4713/4719 | R3-R5 |
| paintPanels | 4283 | 面板区（调 `RoomPanels.render`） |
| paintStatus / mySheetCard / consentCard / checkReqCard | 4918/4967/5026/5060 | R11 |
| paintLog | 5145 | 房间页日志 |
| **游戏页骨架** | | | |
| renderGamePage | 2648 | 12 块容器装配 |
| buildKpSkeleton | 2893 | **KP 12 块**（块 1–11 有行内编号） |
| buildPlSkeleton | 2972 | **玩家 12 块**（注释；实读 13 容器，见 §5.4） |
| applyGridClass / attachGridListeners / detachGridListeners | 2734/2749/2756 | 网格阈值**唯一真相源** |
| foldState / isFolded / toggleFold / foldHeader / syncFoldRegion / ensureInlineFold / ensureFoldHeader / attachFoldHeaders | 2795-2888 | 折叠态（本地） |
| mountPanel | 3065 | **区域 → 面板函数**，带 fallback |
| paintCombatRegion / paintKpRegions / paintPlRegions | 3087/3105/3158 | 块→面板映射（§5.3/§5.5 的依据） |
| splitSketchIntoOwnBlock | 3138 | 把「我的手绘板」从 `plTeammates` 输出里**移动**到独立块 |
| **缩放/方向** | | | |
| applyOrientation / restoreOrientation / maybeAutoZoom / setZoom / resetZoom / openZoomSheet / pinchDist / bindPinchZoom | 3201-3356 | C4 缩放 |
| **中心舞台** | | | |
| paintCenterInto / paintGameCenter / fullscreenScene | 3683/3702/3705 | 块 4 |
| openCombatPrepare | 3364 | 战斗准备弹层 |
| **信息流** | | | |
| paintGameFeeds | 3995 | **块 8/9 的唯一渲染点**（聊天与记录都在这里） |
| feedHead / scrollFeedToBottom / fullscreenFeed | 3900/3927/3940 | 标题栏 + 全屏 |
| appendFeed | 4115 | 单条 feed 渲染器（sys/chat/dice/check/opposed 分派） |
| diceBubble | 5199 | 骰子气泡 |
| opposedResultCard | 4043 | 对抗结果卡（攻守双方/反击闪避/逐轮/伤害） |
| feedAvatarForSeat | 4107 | feed 头像 |
| triggerFeedFlash / feedFlashCheck / optoast* | 3730-3882 | 新消息闪烁 / 操作居中播报（P2 动效） |
| **玩家块** | | | |
| paintPlayersInto / paintPlayersStrip / memberDetailSheet / cardImageSheet | 3572/3599/3603/3641 | 块 7 |
| paintPrivates / fillPrivCard / privHeadBar / fullscreenPriv / restorePrivFs | 4779-4918 | 块 10 |
| **工具栏** | | | |
| paintGameToolbar / syncToolbarReserve | 4189/4275 | 块 11 |
| **聊天** | | | |
| chatBar / openChatEditor / cleanRpText / buildRpMessages / aiRpSheet | 5216-5429 | 块 8 输入行 + AI RP |
| **动作/出口** | | | |
| sendIntent / hostAction / buildConfirmText | 5429/5435/5462 | **两个唯一出口**：`INTENT` vs `ACT` |
| copyInvite / copyServerAddr / copyJoinInfo / hostAddrBlock | 5470-5514 | 剪贴板 |
| closeRoomConfirm / leaveConfirm / stopLanIfHost | 5514/5544/5582 | 危险操作二次确认 |
| **存档归档** | | | |
| resumeArchiveCard / archiveDetailSheet / exportArchiveText | 479/565/535 | P2 |
| **面板上下文** | | | |
| panelCtx | 4299 | `{st, role, host, client, side, act, intent, paint, refreshSheet}` ← **P5 的 ViewModel/Controller 就对应这个** |

### 6.2 `room-panels.js`（6173 行）三层归纳

**基座（1-275）**

| 项 | 行号 | P5 对应 |
|---|---|---|
| `boot()` / `T()` | 37/41 | 无（Dart 直接 import） |
| `el` / `esc` | 43/44 | widget |
| `DRAW_COLORS`（5 色）/ `ATTR_LABELS` | 46/47 | 常量 |
| `UI_STATE`（面板本地态） | 58 | **一个 `ChangeNotifier` 或 `State` 对象**：`leftTab/logTab/combatTab/feedTab/matesOpen/tool{mode,icon,color}/boardMode/boardPage/d100Mod/darkRoll/pendingActors` |
| `rerender(ctx)` | 51 | `ctx.paint()` → notify |
| `selectCtl` / `toolBtn` / `panelTabs` / `scrollBox` / `svgEl` / `strokesSvg` | 91/102/110/122/128/146 | 通用 widget（`PanelTabs` / `ScrollBox` / `StrokesPainter`） |
| `findMember/mySeatOf/findMe/playersOf/isCombat` | 162-186 | `view/` 纯函数 |
| `memberStats` | 188 | **关键**：HP/MP/SAN 兼容 `sheet.status` 与 `runtime` 两套来源 |
| `memberDex` | 207 | 战斗敏捷**唯一权威 = `sheet.attrs.dex`** |
| `statBar` / `avatarEl` / `timeText` / `beep` | 218-249 | widget（beep = 轮次提示音，P2） |

**战斗基础（303-450）**：`combatOf/curSlot/unitDown/isDown/isMyTurn/hpBar/chipFor/initiativeBar/notifyTurn`

**地图与画布（450-1250）**：`mapBackground/mapStage/mapPan*/clampMapPan/bindMapPan/distSegSq/hitStrokeIndex/eraseStrokeSegments/commitMapStrokes/eraseAt/eraseBoardAt/zoomCtrl/openFullscreen/openFullscreenSrc/publicAssets/bindTap/bindDraw/bindErase/bindEraseStage`

**素材（1223-1330）**：`collectAssets/assetUpload/leftAssetsList`

**KP 三块（1335-1550）**：`actorPool/addPendingActor/leftActorsList/kpLeftColumn/kpToolColumn/placePlayerSheet/placeActorSheet/kpMapArea`

**信息流（1553-1690）**：`seatRole/memberOfSeat/feedAvatar/feedNode/collectFeeds/renderLogItems/renderChatItems/kpGameLog/kpChat/chatInput`

**KP 面板（1693-1960）**：`kpCombatPanel/kpSceneCheckPanel/boardInfo/kpPlayerList/viewBoardSheet`

**KP 定向（2021-2660）**：`pickPlayerToEdit/targetName/validLossSide/pickTargetPlayer/memberSanText/memberHpText/dmgForPlayer/tempForPlayer/itemForPlayer/isMemberMadActive/isMemberRippedU/bodyViewOf/WOUND_BODY/isMemberWounded/isMemberUnconscious/sanBlocked/targetBlocked/playerOperationLocked/saneTargets/sanForPlayer/darkRollSheet/kpDirectivesCard/cureForPlayer/cureWoundForPlayer/aidForPlayer/aidPlayerSheet/sanLossForPlayer/roomRulesSheet/inviteForRoom`

**角色卡（2657-3050）**：`charSheetOf/tempCardCommitButton/commitRoomTempCards/tempCardBar/tempCardsSection/plCharacterCard/attrListOf/charStatus/charVitals/charSkills/charItems/localOwnItems/charProfile`

**玩家块（3052-3270）**：`plMapArea/plFeeds/plTeammates/miniBoard/plBottomBar(死代码)`

**玩家工具（3274-4055）**：`d100ModPanel/rollPlayerD100/openCharSheet/skillCheckSheet/rollSkill/sanCheckSheet/customDiceSheet/tempStateSheet/selfStateSheet/notesPanel/itemsSheet/rulesSheet/musicSheet`

**战斗准备/场景检定（4057-4575）**：`pcActors/combatPrepareSheet/newSceneStep/sceneCheckDraft/plSceneCheckPanel/localSkills/findLocalSkill/sceneCheckSheet/stepEditor/pushSceneCheck`

**对抗全链路（4579-5120）**：`intIn/monsterList/aliveUnits/opposedSheet/genericOpposedSheet/kpAttackSheet/playerOpposedSheet/opposedResolveSheet/playerTargetSheet/kpOpposedPendingCard/resumeSheet`

**其它（5258-6106）**：`addActorSheet/damageSheet/diceBar/parseDiceExpr/doRollExpr/doRoll/explorationPanel/assetCard/mapCard/playerBoardCard/kpPanel/spectatorHint/opLabel/seatLabel/pendingDetail/stateRequestCard/stateRequestSheet/pushCheckSheet/clueSheet/endSession/render/defaultSaveName/saveSlotsSheet`

### 6.3 关键既有语义（必须 1:1 保留，别「顺手优化」）

| # | 语义 | 证据 | 为什么不能改 |
|---|---|---|---|
| S1 | `memberStats` 兼容 **两套来源**（`sheet.status` 与 `runtime`），missing 时回退 | `panels:188` | 旧客户端存档里两套都有；只读一套会「血量显示 0」 |
| S2 | 战斗敏捷**只认 `sheet.attrs.dex`** | `panels:207` | 曾用 `derivedStats` 导致与 KP 视角不一致 |
| S3 | 奖惩骰**互斥**（切边清空另一侧，0–5） | `panels:5350-5400` | 用户实测报过「N 奖励 + M 惩罚」并存导致误判 |
| S4 | 统计骰子按 `bonus`/`penalty` **分开**传，不传 net | `panels:5525` | 规则层先抵消，传 net 会丢信息 |
| S5 | `isDown`/`unitDown` 判活必须带 `hpMax > 0` 守卫 | `panels:314-345`、`room_model:4619` 注释 | 否则 HP 未公开的怪物被判「已死」 |
| S6 | 「推进 1 轮」400ms 防连点 + 模块级持久 | `panels:2776-2790` | 连点会触发 intent 风暴、真机卡死 |
| S7 | 整体操作锁（昏迷/濒死/撕卡/疯狂发作）**只放行** `madness.advance` 等自助动作 | `panels:2298` | 与模型 `_memberLocked`/`_passSelf` 必须同判据 |
| S8 | 撕卡（死亡/永久疯狂）后只能聊天 | `panels:2827` | |
| S9 | 素材上传 2MB 上限 | `panels:1244` | |
| S10 | 手绘板最多 4000 笔（模型侧 `take(4000)`） | `actions_room:940` | |
| S11 | 危险操作二次确认（清空地图/清空手绘板/结束战斗/结团/结束房间） | `panels:890/3205`、`room-ui:5514` | |
| S12 | 聊天输入行**建页挂一次**，重绘不重建（不丢正在输入） | `room-ui:4025-4027` | 每次重绘重建 = 输入内容丢失 |
| S13 | 私密/记录「最新在下」+ 用户上滚时不强制拉底 | `room-ui:4815-4830` | |
| S14 | 点输入框 → 全屏编辑，确认**只回填不发送** | `room-ui:5237/5281` | |

### 6.4 旧版已修的陷阱（P5 不要重犯）

| 陷阱 | 旧版结论 | P5 要求 |
|---|---|---|
| `boards[seat].thumb` **恒为空** | `panels:1962-1980` 长注释：`Host.boardSelf` emit 的载荷根本没 `thumb`，reduce 存 `thumb: p.thumb||''` → KP 永远只见占位 | 玩家手绘板缩略用**笔数**（`scene.boards[seat].count`）；KP 全屏查看读 `host.boardBySeat[seat]['strokes']`（本机权威副本，**协议零改动**） |
| 玩家侧误挂 KP 面板 | `room-ui:3178-3183`：玩家点「推送给玩家」→ 权威端静默拒绝，界面弹「推送成功」 | 面板**按角色分流**（`plSceneCheckPanel` vs `kpSceneCheckPanel`），且**不得**在本地乐观提示成功（以权威端系统消息为准） |
| 工具栏放进缩放容器 | `room-ui:2683-2686`：`transform:scale()` 生成 containing block，`position:sticky` 失效 | 工具栏必须在缩放 `Transform` **之外** |
| 折叠后标题栏漂移 | 旧版为此把 grid 判定收敛到 `.gp-grid` 单一类 | 折叠态与布局态**分离**，不要在布局 widget 里改折叠 |
| 大量 intent 重绘风暴 | `panels:2786-2796` | 批量操作节流；`paint` 只重绘受影响块（Flutter 用 `ValueListenable` 局部重建） |
| `state.seq > log.seq` 分叉 | P4 F3 已修 | UI 不读 `state.seq` 做逻辑，只用于诊断 |

---

## 7. 需求池

> 格式：**输入 → 期望表现 / 不变式**。P0 = 必须有，P1 = 应该有，P2 = 可延后。

### P0

| ID | 需求 | 输入 → 期望 / 不变式 |
|---|---|---|
| **P0-01** | 路由与首页入口 | 首页点「房间」→ `/room`；`/room/<code>` 直达；无会话时落入口页；有会话且 `status==IN_GAME` 落游戏页 → **不变式**：`IN_GAME` ⇄ 非 `IN_GAME` 切换必整页重建，旧骨架不残留 |
| **P0-02** | 房间入口页 | 创建（房间名/最大人数/允许旁观）→ 生成本机 `RoomHost`（`InMemoryRoomSaveStore`），`meta` 8 键齐全；加入（6 位房间号 + 昵称）→ **P5 阶段**：本机假会话（§9.4）；续玩 → 列本机未完结房间，选中 → `adoptSave` |
| **P0-03** | 游戏页骨架 | `status==IN_GAME` → 按视角建容器（KP 12 / 玩家 13） → **不变式**：每个功能块是独立 widget 子树，**不合并**（否则滚动/折叠/局部重绘互相牵连）；容器 key 稳定，折叠/重绘后滚动位置不丢 |
| **P0-04** | 块 1 顶栏 | 渲染房间名/身份/房间号/场景/连接态/角色/模式/观众数；点观众 → 只读名单 → **不变式**：连接态三档（已连接/连接中/已离线）在游戏页**始终可见**（旧版 `.game-page` 全屏会遮住房间横幅，`room-ui:3510`） |
| **P0-05** | 块 4 公开素材舞台（KP 可编辑） | KP：拖动平移 + 缩放 ± + 全屏 + 落点；玩家：只读 → **不变式**：笔迹/标记坐标为 `[0,1]` 归一化；`map.stroke` 单笔 ≤ 合理点数；`map.strokes.set` 为**全量替换** |
| **P0-06** | 块 8/9 聊天与游戏记录 | 聊天最近 60、记录最近 120，按 `at` 升序、最新在下 → **不变式**：① 输入行不被重绘重建；② `redacted` 行只显示脱敏文案；③ 记录**不得**渲染 `toWireJson`；④ 新消息到达时若用户已上滚，不强制拉底 |
| **P0-07** | 块 11 掷骰条 | D100 / D4-D10 / 自定义骰式 / 奖惩骰 0–5 互斥 / 暗骰开关 → **不变式**：结果**只能**来自权威端（UI 绝不本地掷）；`bonus`/`penalty` 分开传；旁观禁用；（**依赖 B1**） |
| **P0-08** | 块 2 我的角色卡 | 头像/名/职业/HP·MP·SAN 条/角色状态（身体·精神·疯狂）→ **不变式**：数据取 `me.sheet` + `me.runtime` 两套兼容（S1）；撕卡后显示「只能聊天」 |
| **P0-09** | 块 7 玩家/队友信息 | KP：全量 HP/MP/SAN + 手绘板入口；玩家：队友 HP/SAN + 体/精标签 → **不变式**：他人视图**无** `maxSAN` → SAN 只显示当前值；无 `madness` 明细 → 只显示 `madnessCount`；怪物未公开 HP 显示「隐藏」 |
| **P0-10** | 块 10 只给你看的信息 | 最近 12 条、正序、新条高亮、点开全文、⛶全屏 → **不变式**：内容来自 `state.privates`（已按 seat 裁剪），UI **不做**任何二次过滤 |
| **P0-11** | 场景检定（KP 块 5 / 玩家块 7） | KP：步骤进度 + 6 档裁定（大成功/极难/困难/成功/失败/大失败）+ 自定义快速推送 + 编辑器入口；玩家：**只读** KP 推来的 + 用自己技能主动检定 → **不变式**：玩家侧**绝不**渲染 KP 裁定按钮与「推送给玩家」 |
| **P0-12** | 块 6 战斗列表 | 表格（顺序/名称/类型/HP/状态/行动）+ 怪物信息 tab + 未参战加入 + 下一行动 + 伤害 + 结束 → **不变式**：判活带 `hpMax>0` 守卫；`combat.next` 只由 KP 发 |
| **P0-13** | 玩家状态管理 | 身体 chips（正常/轻伤互斥；重伤/濒死/昏迷可叠加；死亡独立+撕卡确认）+ 精神状态多选 + HP/MP/SAN 数字 → **不变式**：身体/精神**立即生效**（`state.self`）；数字走 `state.edit.self`（**POLICY confirm:kp**）→ UI 文案必须写「提交后等 KP 同意」，**不得**沿用旧版「不需要 KP 同意」的误导文案 |
| **P0-14** | KP 工具弹层 | 待确认队列（逐条确认/取消）+ 待裁定对抗 + 四组工具 → **不变式**：`room.close`/`session.end` 必须二次确认；未读角标计数 = `pending(need∈{twice,kp}) + requests + (opposed.phase=='await_kp'?1:0)` |
| **P0-15** | 存档与续玩 | KP「💾保存本局」→ `host.save()` → `saveStore.put(code, data)`；载入 → `adoptSave(data)`；续玩 → 本机未完结房间列表 → **不变式**：存档后刷新仍能恢复 20 个顶层键（成员/线索/战斗轮次/私密栏） |
| **P0-16** | 权限与可见性同源 | 每个控件可点性 ⟺ `needs(role, action).allowed` → **不变式**：旁观者零可用写操作；不可用时 `disabled` + 原因，不静默失败 |
| **P0-17** | 局部重绘与状态保持 | 任意状态变化 → 只重绘受影响块 → **不变式**：折叠态、tab、滚动位置、正在输入的文本、画笔颜色在重绘后不变 |
| **P0-18** | 响应式两档 | 竖屏单列 / 横屏网格（C4 阈值）→ **不变式**：360×640 与 780×320 下无 overflow 警告、无控件不可达 |

### P1

| ID | 需求 | 输入 → 期望 / 不变式 |
|---|---|---|
| P1-01 | KP 左窄栏三 tab（块 2） | 素材/地图/NPC 三个 tab 切换不丢滚动位置；素材 secret 可切换公开 |
| P1-02 | KP 工具窄栏（块 3） | 5 色 / 画笔 / 橡皮 / 放置单位 / 放置玩家 / 清除（二次确认）；橡皮为**段级删除**，手势末尾一次提交 |
| P1-03 | NPC·怪物候选池 | 添加 → `addLocalActor`（同 id 去重、只收 `monster`/`npc`）；**随 `save()` 落存档**；开团时随 `combat.start.actors` 送 |
| P1-04 | 我的手绘板（独立块） | 实时绘制 + 橡皮（段级）+ `1/1` 分页 + 清空（确认）；每次落笔/擦除 = 一次 `INTENT.BOARD` 全量替换 |
| P1-05 | 笔记栏 | 本机保存（不上传）；增/删/改；不参与 `state` |
| P1-06 | 对抗全链路 | 通用对抗 / 攻击对抗 / 武器对抗（玩家）/ 裁定 / 选伤害目标；反击·闪避·逐轮重掷·伤害段可读 |
| P1-07 | 战斗准备弹层 | 勾选怪物/NPC + 玩家 → `combat.start`；部署位置可选 |
| P1-08 | 场景检定编辑器 | 多步骤/分支；`scene.check.push` 后 KP/玩家视图同步 |
| P1-09 | KP 定向 9 项 | 造成伤害/临时状态/给物品/SAN Check/暗骰/治愈×2/急救/SAN 大失败；目标过滤「已撕卡」，并按 R2a 口径过滤「疯狂发作中」 |
| P1-10 | 玩家自助急救/医疗/精神分析 | `aid.apply`/`aid.psycho` 走 KP 审批，UI 显示「等待 KP 同意」 |
| P1-11 | 完整人物卡信息图 | 从角色卡数据渲染只读信息图（复用 P2 的 `summary_card.dart`，**不新增卡片键**） |
| P1-12 | AI RP | 调 P3 的 AI 通道；结果**只填入输入框**，不自动发送、不改状态 |
| P1-13 | 全屏查看 | 聊天/记录/素材/线索/手绘板各自全屏只读；Esc/返回退出 |
| P1-14 | UI 缩放 | 60–100% 预设 + 捏合 + 重置 + 百分比可点 |

### P2

| ID | 需求 | 输入 → 期望 / 不变式 |
|---|---|---|
| P2-01 | 规则参考 | 静态文案，只读 |
| P2-02 | 物品道具 | 查看/使用 KP 发放物品；`item.del` |
| P2-03 | 音乐控制台 | 本机 BGM，不联网、不打包音频 |
| P2-04 | 临时状态 | 旧版实现为聊天提示（模型无 self 状态编辑动作）→ 保持同语义，**不造假入口** |
| P2-05 | 动效 | feed 新增闪烁、操作播报（居中 2s）、角标脉冲、轮次提示音 |
| P2-06 | 游戏历史归档 | 只读历史记录 + 导出文本 |
| P2-07 | 网络自检 / 局域网 | **依赖 P6**，P5 只留入口占位 |

---

## 8. 测试口径（P5 widget 测试怎么写）

### 8.1 铁律（写进每个用例的注释里）

| # | 规则 | 原因（工程既有坑） |
|---|---|---|
| **T1** | widget 测试一律用**内存后端**：`newMemoryRepo()` / `newMemorySettings()` / `newMemoryShareStore()` / `InMemoryRoomSaveStore` | `flutter_test` 跑在 fake-async 区域，**真实文件 I/O 的 `Future` 永远不完成** → 测试永久挂起（`app_harness.dart` 顶部注释明写） |
| **T2** | 自造裸 `MaterialApp` 宿主时必须 `await wrapWithScopes(child)` | 否则 `ShareScope.of(...)` 命中 `repo_scope.dart` 的断言；`wrapWithScopes` 层级与 `DiceRealmApp` 完全一致（Repo→Settings→Share） |
| **T3** | `SectionCard` 内**禁止** `ListTile` / `SwitchListTile` | `SectionCard` 外层是 `DecoratedBox`，不是 `Material`；`ListTile` 要在最近 `Material` 上画底色/水波纹，Flutter 会直接断言（`settings_page.dart:568-572` 已有先例，改成 `Row` + `Switch`） |
| **T4** | 懒构建列表（`ListView`/`CustomScrollView`）取控件前必须 `await scrollTo(tester, '<key>')` | 屏幕外的 widget 不在树里，`find.byKey` 直接失败 |
| **T5** | 起 App 用 `pumpApp(tester, home: ...)`；`useTallScreen` 默认 1200×2600 | 800×600 装不下向导与 12 块布局 |
| **T6** | 断言「点了没反应」必须断言**权威侧**（`host.state` / `SendPlan` 列表），不断言 UI 文案 | 旧版最大缺陷就是「UI 说成功、权威端拒绝了」 |

### 8.2 建议用例清单（约 38 例，按块分组）

**A. 壳与视角（8 例）**

| ID | 用例 | 断言要点 |
|---|---|---|
| T-01 | `IN_GAME` 前渲染房间页、后渲染游戏页 | 两套骨架 key 互斥；切回时旧骨架不在树里 |
| T-02 | `role=kp` → 12 个容器全部存在 | 12 个稳定 key 各 `findsOneWidget`（玩家侧 13 个，另测一例） |
| T-03 | `role=player` → KP 专属块不存在 | `find.byKey(kpLeftColumn)` = `findsNothing` |
| T-04 | **可见性跨视角**：同一 `state`，玩家 A 视图无 B 的技能值；KP 视图有 | 用 `syncFor('seatA')` vs `host.state` 各建一次页面 |
| T-05 | 旁观者：聊天输入禁用、掷骰条全禁用 | `tester.widget<TextField>(...).enabled == false` |
| T-06 | 旁观者点准备 → 不发 intent | 记录 adapter 调用次数 == 0 |
| T-07 | 身份切换（旁观→玩家）整页重建 | 骨架 key 变化 |
| T-08 | 折叠态在重绘后保持 | 折叠 → 触发一次 `paint` → 仍折叠 |

**B. 块级（14 例）**

| ID | 用例 | 断言要点 |
|---|---|---|
| T-10 | 块 8 输入框在重绘后内容不丢（S12） | 输入「abc」→ 触发 state 变化重绘 → 仍为「abc」 |
| T-11 | 块 9 `redacted` 行只显示脱敏文案 | 造一条 `{kind:'check',redacted:true,text:'KP 秘密进行了一次检定'}` + 一条带明文的伪造行 → 页面不含明文 |
| T-12 | 块 9 记录不含 `toWireJson` 键 | 断言渲染文本中无 `{"t":` / `"vis":` |
| T-13 | 块 7 怪物未公开 HP 显示「隐藏」而非 0 | `hpPublic:false` → 文案含「隐藏」，不含「0」 |
| T-14 | 块 7 队友 SAN 无双上限格式 | 断言不含 `'/'` 分隔的 SAN |
| T-15 | 块 10 线索按 `at` 正序、最新在最后 | 用三条不同 `at` 验证渲染顺序 |
| T-16 | 块 10 点条 → 全文弹层 | |
| T-17 | 块 11 奖惩骰互斥（S3） | 选「惩罚骰」+3 → 奖励骰变 0；发出去的 intent `bonus==0, penalty==3` |
| T-18 | 块 11 上限 5（点第 6 次不增长、有提示） | |
| T-19 | 块 11 暗骰开 → 投掷走 `dice.dark` 而非 `INTENT.DICE` | |
| T-20 | 块 2 撕卡后显示「只能聊天」且状态管理禁用 | |
| T-21 | 块 2「推进 1 轮」400ms 内连点只发 1 条（S6） | 用 `tester.pump(Duration(milliseconds: 100))` 连点 5 次 → adapter 调用 == 1 |
| T-22 | 块 5 玩家视角无「下一个行动 ▶」 | |
| T-23 | 块 6/4 场景：玩家侧无「推送给玩家」按钮 | 复用旧版缺陷回归 |

**C. 权限与安全（6 例）**

| ID | 用例 | 断言要点 |
|---|---|---|
| T-30 | **控件可点 ⟺ `needs()` allowed**（表驱动，遍历 §5.9） | 对每个 op 造一次页面，断言 disabled 状态与 `needs` 一致 |
| T-31 | 旁观者/玩家点 KP-only action → 权威侧零状态变化 | `host.state` 深比较前后一致 |
| T-32 | 越权操作给出**定向**系统提示（`sysTo`），不静默 | `SendPlan` 里有该 seat 的消息 |
| T-33 | KP 改玩家状态 → 玩家侧出现「需我同意」卡 → 同意后生效 | `requests` → `CONSENT` → `state` 变化 |
| T-34 | 秘密检定：公共栏只见脱敏行，发起人私密栏见全文 | 两个 seat 各建页面 |
| T-35 | 玩家手绘板内容其他玩家**看不到**（`VIS.SEAT`） | 他人视图 `state.board` 为空 |

**D. 布局与手势（4 例）**

| ID | 用例 | 断言要点 |
|---|---|---|
| T-40 | 360×640 单列：`overflow` 零警告 | `tester.takeException()` == null |
| T-41 | 780×320 网格 + compact：全部功能块都在可视/可滚范围 | `scrollTo` 全部可达 |
| T-42 | 480 宽（520–599 区间）→ 单列 | |
| T-43 | 所有可点元素 ≥48dp | 遍历 `find.byType(InkWell/GestureDetector)` 量尺寸 |

**E. 存档（3 例）**

| ID | 用例 | 断言要点 |
|---|---|---|
| T-50 | `save()` → `adoptSave()` 往返，成员的 HP/SAN/线索/战斗轮次一致 | 20 顶层键深比较 |
| T-51 | 存档面板新建/载入/删除三路径 | `InMemoryRoomSaveStore.length` 变化 |
| T-52 | 旧存档导入触发 K4 脱敏迁移 + 提示（若采纳 §9.2） | 导入后 `logs` 无明文；页面有提示 |

**F. 阻塞项回归（4 例，**依赖 B1 修复**）**

| ID | 用例 | 断言要点 |
|---|---|---|
| T-60 | 玩家 D100 → 权威端结算 → 记录里出现带 `value`/`level` 的 dice 项 | 不是「请求掷 1D100」 |
| T-61 | 玩家技能检定 → 结果含 `base` 与成功等级 | |
| T-62 | 玩家 SAN Check → SAN 实际下降 + `EVT.STATE` 写回 | |
| T-63 | 玩家手绘板落笔 → 自己视图 `state.board.strokes` 增长，他人视图不变 | |

### 8.3 测试夹具建议

新增 `test/support/room_ui_harness.dart`：

```dart
// 造一个「KP 端 + N 个玩家视图」的完整场景，全部内存后端
class RoomUiFixture {
  late RoomHost host;
  final Map<String, RoomClient> clients = {};
  final InMemoryRoomSaveStore saves = InMemoryRoomSaveStore();
  /// 记录所有 UI 发出的 intent / action，用于「点了没反应」断言
  final List<Map<String, Object?>> sent = [];

  Future<void> boot({int players = 2, RoomMode mode}) async { /* ... */ }
  Widget kpPage();
  Widget playerPage(String seat);
  Widget spectatorPage(String seat);
}
```

要点：`RoomHostOptions(rules: CocRulesAdapter(), madness: …, now: fixedClock, rng: lcg)` —— **复用 `test/support/room_fakes.dart` 既有的规则/疯狂/时钟/随机源假实现**，不要新造（P4 已有）。

---

## 9. 待确认问题（需 team-lead / 架构师决策）

> 按优先级排序。**B1 不裁决则 P5 无法开工**（掷骰类按钮必然无效）。

### 9.1 【B1 · 阻塞】四个 INTENT 分支在 P4 是 no-op

**证据**

- `room_model_host_intent.dart:192-208`：`case RoomIntent.dice:` 只 emit 一条 `kind:'dice-request'` 日志（注释自承「direct 掷骰的规则结算属 S4.3；本批统一记『请求掷 X』」）。
- `room_model_host_intent.dart:241-243`：`case RoomIntent.sanCheck: case RoomIntent.opposed: case RoomIntent.board: default: break;`（**完全 no-op**）。
- 四个结算函数**都已实现**：`diceDirect`（`actions_combat:790`）、`playerSanCheck`（`:2560`）、`opposed`（`:2080`）、`boardSelf`（`actions_room:939`）。

**影响面**（P5 直接受害）

| 旧版调用 | 预期 | 现状 |
|---|---|---|
| `INTENT.DICE {direct:true}`（D100/D4-D10/技能检定/自定义骰/场景检定） | 权威端掷骰 + 结果广播 | 只写「请求掷 X」，**无结果** |
| `INTENT.SAN_CHECK` | 权威端结算 + 扣 SAN + `EVT.STATE` 写回 | 什么都不发生 |
| `INTENT.OPPOSED`（武器对抗 / 选伤害目标） | 进对抗流程 | 什么都不发生 |
| `INTENT.BOARD {strokes}` | 全量替换该 seat 手绘板 | 什么都不发生 |

**建议（推荐 A）**

- **A（推荐）**：在 `intent()` 的这四个 `case` 里**直接调已实现的结算函数**，约 10 行：
  ```dart
  case RoomIntent.dice:
    if (jsTruthy(p['direct'])) { out.addAll(diceDirect(seat, mem, role, p)); break; }
    /* 否则保持现有「请求掷 X」语义 */
  case RoomIntent.sanCheck: out.addAll(playerSanCheck(seat, mem, p)); break;
  case RoomIntent.opposed:  out.addAll(opposed(seat, mem, role, p)); break;
  case RoomIntent.board:    out.addAll(boardSelf(seat, p)); break;
  ```
  **不要**把这些 op 加进 `kRoomPolicy` —— 旧版 `Host.intent` 本来就**不经过 POLICY**，只有 `INTENT.ACT` 才走 `needs()`。加 POLICY 会把权限面从 61 扩到 65，还要连带改 P4 的「POLICY 恰好 61 条」门禁与 QA 白名单。
- **B**：P5 侧改用 `INTENT.ACT` 别名绕过（`board.self` 可用；`dice.direct`/`sancheck`/`opposed` 不在 POLICY 内 → 被 `act()` 拒）。
- **C**：P5 只做展示，掷骰留 P6 —— **违反「不许删功能」**，不接受。

**风险**：A 会改动 P4 已冻结文件 → 需要重跑 `flutter test`（927 组）+ `node tool/qa/qa_p4_gate.js`（13 条）。因为**只加分支、不动既有分支**，风险低；但 `diceDirect` 会消耗 RNG，若有「randUsed」类断言需同步。

**请裁决**：走 A 吗？如果走 A，由谁执行（P4 补丁 or P5 第一批）？

### 9.2 【K4】旧存档明文迁移口径

**背景**：旧版 buggy rollback 重放时丢 `vis/to`（P4 Q1 已修），旧存档 `logs` 里可能存在**明文秘密检定行**；`playerViewFromSave` 会原样透传（`qa_p4_gate_report.md` §5 K4）。

**产品口径（建议采纳）**

1. **导入时一次性脱敏迁移**（不是每次加载都跑），迁移完成后再 `adoptSave`/`restoreHost`。
2. **可机械判定的命中条件**（保守，只打真缺陷产物）：
   ```
   log.kind == 'check'
   && log.opp == null
   && log.seat != ''
   && log.text 含「秘密检定」
   ```
   理由：合规的脱敏行恒为 `{seat:'', text:'KP 秘密进行了一次检定', redacted:true}`（`room_model_reduce.dart:227-235`）；明文行只可能来自 Q1 缺陷重放，而秘密检定的 `summary` 文案以「秘密检定」开头。公开检定不会命中。
3. **迁移动作**：就地改为脱敏行 —— `seat: ''`、`text: 'KP 秘密进行了一次检定'`、`redacted: true`，**保留** `seq` 与 `at`（不打乱时间轴，不影响 `log.seq` 水位）。
4. **幂等**：已脱敏行不满足 `seat != ''` → 重复导入零变化。
5. **UI 提示**：迁移发生 >0 条时，在载入完成的页面上给一条**一次性**提示：
   > 「旧存档含历史明文记录，已自动脱敏 N 条。」
   不弹模态、不阻断流程。
6. **落点**：建议放在 P5 新增的纯函数（`lib/ui/room/view/legacy_migrate.dart` 或 `lib/repo/`），**不改 `lib/domain`**。若架构师认为该亲和 `playerViewFromSave` 一致，则放 `room_model_save.dart` 更内聚，但会动 P4 文件。

**请裁决**：① 采纳该口径吗？② 落点放 `lib/ui`（不动 P4）还是 `lib/domain`（更内聚但需重跑 P4 门禁）？

### 9.3 【K1】回退入口：旧版已整体移除

**证据（推翻任务说明的前提）**

- `room-ui.js:4935`：「v2.9.0（用户第 3 项）：删除回退投票入口 —— 回退功能整体移除，玩家侧不再出现投票卡。」
- `room-ui.js:5143`：同上，日志区也删了。
- 全仓 `ui/*.js` 内**零** `rollback*` 调用（`grep -rn "rollback" ui/` 只命中注释）；`rollback.commit` 的 POLICY 条目是「休眠保留」（`room-model.js:239`）。

**结论**：1:1 复刻 ⇒ **P5 不提供任何 KP 回退按钮** → K1（`beforeSeq < 1`）在 P5 **无触点**。

**仍建议做的一件小事**：P5 的 Host 适配层（`room_session.dart`）若将来暴露 `rollback(beforeSeq)`，加**闭区间守卫** `assert/夹取 beforeSeq >= 1`，并在 UI 侧永不传 0。这样即使 K1 不复存在，也不会有人从 UI 侧再把它引出来。

**请裁决**：确认「P5 不提供回退入口」这一口径，并确认守卫加在 P5 适配层而不是改 P4 的 `rollback`。

### 9.4 【Q-P5-1 · 高】P5 如何在没有 P6 的情况下跑通「玩家视角」

旧版玩家端的一切都通过 WebSocket 到 KP。P5 不做传输，但**必须**能验证玩家视角（否则 US-3/US-4/US-5 无法验收）。

**建议**：P5 定义一个极薄的会话抽象，附一个同进程实现。

```dart
// lib/ui/room/room_session.dart（UI 层，不是 domain）
abstract class RoomSession {
  String get code;
  String get seat;
  String get role;
  Map<String, Object?> get state;        // 只读：KP=host.state，玩家=client.state
  Listenable get changes;                // 状态变化通知（驱动局部重绘）
  Future<void> sendIntent(String op, Map<String, Object?> p);   // 玩家 → KP
  Future<void> sendAction(Map<String, Object?> p);              // KP → 自己
  void dispose();
}

/// 同进程环回：KP 的 SendPlan 直接喂给本机所有 client / host 刷新
class LocalLoopbackSession implements RoomSession { /* ... */ }
```

- `LocalLoopbackSession` 内部：`host.intent(...) → List<SendPlan>` → 逐条 `client.receive(plan.msg.toJson())`（`to == '*'` 或 `to == seat` 才投递）→ `notifyListeners()`。
- **它能顺带验证**：`plan()` 的裁剪是否真的生效、`skip` 信封是否被正确消费、`receive()` 的拒绝分支。这对 P6 是白送的回归网。
- **P6 只做一件事**：实现 `RemoteSession implements RoomSession`，把 `SendPlan` 交给中继、把收到的消息喂 `receive()`。UI 一行不改。

**请裁决**：同意在 P5 定 `RoomSession` 抽象 + `LocalLoopbackSession` 吗？（替代方案：P5 只测 KP 视角，玩家视角留 P6 —— 那 US-3/4/5 本期无法验收，**不推荐**。）

### 9.5 【Q-P5-2 · 中】素材/头像的图片来源

旧版用 `<input type="file">` + `FileReader` 读成 dataURL。Flutter 需要图片选择器。

**建议**：抽一个端口，P5 不直接依赖插件：

```dart
abstract class ImagePickerPort {
  /// 返回 dataURL（与旧版 `rd.result` 同形状）或 null（用户取消）
  Future<String?> pickImage({int maxBytes = 2 * 1024 * 1024});
}
```

- 生产实现用 `image_picker` 或 `file_picker`（**不违反「禁 WebView」**）；
- 测试实现返回固定小 PNG 的 dataURL；
- 2MB 上限校验在 UI 侧保留（S9 语义不变）。
- 若 team-lead 不想新增依赖，退路：P5 只支持「从本机角色卡头像复用」+ 预设素材，上传留 P7 —— 但那会删功能，需明确接受。

**请裁决**：引入 `image_picker` 还是先做端口 + 测试假实现（生产后补）？

### 9.6 【Q-P5-3 · 中】`state.edit.self` 的文案与旧版不一致

**事实**：`kRoomPolicy['state.edit.self'] = ([player], confirm: kp)` —— HP/MP/SAN 数字修改**需要 KP 同意**。但旧版 UI 文案写着「状态管理（自行修改）」「不需要 KP 同意」（`panels:2805`）。

**建议**：以**权威行为**为准改文案 —— 身体/精神状态（`state.self`，confirm null）写「立即生效」；HP/MP/SAN 数字（`state.edit.self`）写「提交后等 KP 同意」。**不**沿用旧版误导文案（这正是「掷骰页说成功、记录里写失败」那类问题的变体）。

**请裁决**：确认按权威行为改文案（我倾向必须改，否则又是一次「UI 骗人」）。

### 9.7 【Q-P5-4 · 低】版本号与命名

建议 `2.16.0+82`（P4 未出包，P5 一起出）；新目录 `lib/ui/room/`；测试夹具 `test/support/room_ui_harness.dart`；PRD 文件 `_p5_prd.md`。请 team-lead 定。

---

## 10. 验收口径（Definition of Done）

1. **§7 全部 P0 通过**；P1 至少 P1-01～P1-10 通过；P2 不阻塞出包。
2. **B1 已裁决并落地**（否则 P0-07 / P0-11 / P1-04 无法验收）。
3. **基线不退化**：`flutter test` 在 **927 组**基线上只增不减且 **0 红**；`dart analyze` **零 issue**；`lib/domain` 仍零 `package:flutter` / `dart:io` / `dart:ui`。
4. **契约冻结**：角色卡键集合无新增/改名；房间写回仍只经 `CharacterRepoRoomCardSink`；`await repo.save(` 命中数不增加。
5. **可见性零泄漏**：跨视角探针全绿（玩家视图不含他人技能值 / 秘密检定明文 / 怪物隐藏 HP / 他人手绘板内容）。
6. **UI 不算规则**：`lib/ui/room/**` 零 `rules?.check(` / `rollExpr(` / `opposedFull(` 调用；零 `state['...'] =` 赋值。
7. **死代码零产出**：`plBottomBar` / `plFeeds` / `kpChat` / `kpGameLog` 在 `lib/ui/room/` 内零命中（C7）。
8. **两档布局无 overflow**：360×640 与 780×320 走查 + 用例 T-40/T-41。
9. **本阶段产物**：仅 `_p5_prd.md`；未改 `lib/`、`test/`；未跑 `flutter build`。

---

## 附录 A · 12/13 块 ↔ 容器 key ↔ 渲染函数（速查）

> ⚠️ **重要**：KP 与 PL 的块号**各自独立编号**，同一块号在两侧内容完全不同（例：块 2 在 KP 是「左窄栏」、在玩家是「我的角色卡」）。给架构师的建议：**以容器 key 为唯一标识**，块号只用于对照旧版源码注释与线框图。下面拆成两张表，不做跨视角的块号对齐。

### A.1 KP 视角（`buildKpSkeleton`，`room-ui.js:2893`；块号来自源码行内注释 `:2894-2949`）

| 块 | 容器 key（建议） | 旧类名 | 渲染函数 |
|---|---|---|---|
| 1 | `gpTopbar` | `.gp-topbar.gp-kpbar` | `paintGameHead` |
| 2 | `gpKpLeft` | `.gp-region-kp-left` | `kpLeftColumn` |
| 3 | `gpKpTools` | `.gp-region-kp-tools` | `kpToolColumn` |
| 4 | `gpMap` | `.gp-center` / `.gp-region-kp-map` | `kpMapArea` |
| 5 | `gpScene` | `.gp-region-kp-scene` | `kpSceneCheckPanel` |
| 6 | `gpCombat` | `.gp-region-kp-combat` | `paintCombatRegion` |
| 7 | `gpPlayers` | `.gp-region-kp-players` | `kpPlayerList` |
| 8 | `gpChat` | `.gp-region-kp-chat` | `paintGameFeeds` |
| 9 | `gpLog` | `.gp-region-kp-log` | `paintGameFeeds` |
| 10 | `gpPriv` | `.gp-priv` | `paintPrivates` |
| 11 | `gpToolbar` | `.gp-toolbar` | `paintGameToolbar` |
| 12 | `gpStatus` | `.gp-status` | `paintStatus` |

### A.2 玩家/旁观视角（`buildPlSkeleton`，`room-ui.js:2972`；**实读 13 容器**）

| 块 | 容器 key（建议） | 旧类名 | 渲染函数 |
|---|---|---|---|
| 1 | `gpTopbar` | `.gp-topbar` | `paintGameHead` |
| 2 | `gpPlCharCard` | `.gp-region-pl-card` | `plCharacterCard` |
| 3 | `gpPlMap` + `gpCombatStrip` | `.gp-region-pl-map`（在 `.gp-pl-mapwrap` 内）/ `.gp-combat-strip` | `plMapArea` + `paintCombatRegion` |
| 4 | `gpPlChat` | `.gp-region-pl-chat` | `paintGameFeeds` |
| 5 | `gpPlLog` | `.gp-region-pl-log`（在 `.gp-region-pl-feeds` 内） | `paintGameFeeds` |
| 6 | `gpPlCombat` | `.gp-region-pl-combat` | `paintCombatRegion` |
| 7 | `gpPlScene` | `.gp-region-pl-scene`（在 `.gp-pl-row1` 内） | `plSceneCheckPanel` |
| 8 | `gpPlMates` | `.gp-region-pl-mates` | `plTeammates` |
| 9 | `gpPriv` | `.gp-priv`（`privWithFs = true`） | `paintPrivates` |
| 10 | `gpPlSketch` | `.gp-pl-sketch` | `miniBoard`（经 `splitSketchIntoOwnBlock` 移入） |
| 11 | `gpPlNotes` | `.gp-pl-notes` | `notesPanel` |
| 12 | `gpToolbar` | `.gp-region-pl-bottom.gp-toolbar` | `paintGameToolbar` |
| 13 | `gpStatus` | `.gp-status` | `paintStatus` |

**跨视角同构关系**（便于复用 widget）：`gpTopbar`(1/1)、`gpMap`↔`gpPlMap`(4/3)、`gpChat`↔`gpPlChat`(8/4)、`gpLog`↔`gpPlLog`(9/5)、`gpCombat`↔`gpPlCombat`(6/6)、`gpScene`↔`gpPlScene`(5/7)、`gpPlayers`↔`gpPlMates`(7/8)、`gpPriv`(10/9)、`gpToolbar`(11/12)、`gpStatus`(12/13)。KP 专属：`gpKpLeft`(2)、`gpKpTools`(3)；玩家专属：`gpPlCharCard`(2)、`gpPlSketch`(10)、`gpPlNotes`(11)。

## 附录 B · 本 PRD 引用的行号索引

| 文件 | 行号 | 内容 |
|---|---|---|
| `room-ui.js` | 2648 | `renderGamePage`（骨架装配） |
| `room-ui.js` | 2734 | `applyGridClass`（网格阈值唯一真相源） |
| `room-ui.js` | 2879-2890 | **KP 12 块线框 ASCII 注释** |
| `room-ui.js` | 2893 | `buildKpSkeleton` |
| `room-ui.js` | 2972 | `buildPlSkeleton` |
| `room-ui.js` | 3065 | `mountPanel`（区域→面板） |
| `room-ui.js` | 3105 / 3158 | `paintKpRegions` / `paintPlRegions` |
| `room-ui.js` | 3995 | `paintGameFeeds`（块 8/9 唯一渲染点） |
| `room-ui.js` | 4189 | `paintGameToolbar`（块 11） |
| `room-ui.js` | 4299 | `panelCtx`（面板上下文契约） |
| `room-ui.js` | 4318 / 4342 | `paintHead` / `paintMembers`（房间页） |
| `room-ui.js` | 4779 | `paintPrivates`（块 10） |
| `room-ui.js` | 4918 | `paintStatus`（块 12） |
| `room-ui.js` | 4935 / 5143 | **回退 UI 已移除**的证据 |
| `room-ui.js` | 5216 | `chatBar`（AI RP 入口） |
| `room-ui.js` | 5429 / 5435 | `sendIntent` / `hostAction`（两个唯一出口） |
| `room-panels.js` | 58 | `UI_STATE`（面板本地态全集） |
| `room-panels.js` | 188 / 207 | `memberStats` / `memberDex`（两处关键语义） |
| `room-panels.js` | 1402 / 1422 / 1540 | `kpLeftColumn` / `kpToolColumn` / `kpMapArea` |
| `room-panels.js` | 1695 / 1818 / 1925 | `kpCombatPanel` / `kpSceneCheckPanel` / `kpPlayerList` |
| `room-panels.js` | 1962-1980 | **`thumb` 恒空**的长注释 |
| `room-panels.js` | 2779 | `plCharacterCard` |
| `room-panels.js` | 3093 / 3164 | `plTeammates` / `miniBoard` |
| `room-panels.js` | 3234 | `plBottomBar` 死代码自述 |
| `room-panels.js` | 3492 | `selfStateSheet`（状态管理） |
| `room-panels.js` | 5322 | `diceBar`（工具栏骰子条） |
| `room-panels.js` | 5673 | `kpPanel`（KP 工具） |
| `room-panels.js` | 6113-6172 | `window.RoomPanels` 导出面（33 项） |
| `room_model_host_core.dart` | 146 / 298 / 376 / 478 / 507 | `apply` / `plan` / `cropFor` / `combatFor` / `syncFor` |
| `room_model_host_core.dart` | 404-475 | `_cropMember` / `_cropSlot`（可见性口径） |
| `room_model_host_intent.dart` | 109 / 192 / 241 / 247 / 383 | `intent` / **B1 证据** / `act` 闸门 / `applyAction` |
| `room_model_rollback.dart` | 56 / 121 | `rollback` / `rollbackPlan`（K1） |
| `room_model_save.dart` | 71 / 106 / 278 | `save()` 20 键 / `adoptSave` / `playerViewFromSave`（K4） |
| `room_model_actions_room.dart` | 939 / 1008 | `boardSelf` / `addLocalActor` |
| `room_model_actions_combat.dart` | 790 / 2080 / 2560 | `diceDirect` / `opposed` / `playerSanCheck`（B1 可用件） |
| `room_model_reduce.dart` | 195-236 / 314-328 | CHECK 两种落库形状 / PRIVATE 归约 |
| `lib/ui/settings_page.dart` | 568-572 | **SectionCard 禁 ListTile** 的既有注释 |
| `test/support/app_harness.dart` | 全文 | `wrapWithScopes` / `scrollTo` / 内存后端 |

---

*— 完 —*
