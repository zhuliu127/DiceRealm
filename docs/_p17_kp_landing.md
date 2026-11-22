# P17 · KP 视角（平板横屏 dock）8 项需求落点研究报告（只读）

- 工程：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`，当前 **v2.29.0+99**（P16 已交付）。
- 性质：**纯只读研究**。未改任何 `lib/**`、`test/**`、`pubspec.*`，唯一写入是本 md。
- 方法：逐个 `Read` 当前源码 + `Grep` 交叉验证；**行号一律以本次实际读到的 v2.29.0 源码为准**。上一批报告 `_p16_kp_landing.md` / `_p16_construction_spec.md` 仅作结构索引（其行号是 P16 改前的，已失效，本文不复用其行号）。
- 口径：严格区分「**现状事实**」与「**建议落点**」；查不到的写「未找到 + 搜过的关键词」。
- **修订记录（与 `researcher-bugs-p17` 交叉复核后）**：① KP-1 假设 C 补三点修正（`:309-311` 严格同参去重是设计、`:304-305` KP 发起不进 pending、`:484-486` 循环不 break 的连锁修法）；② **`_seen` 红线**：不去重是 P10 刻意设计、被 `:562` 钉死，**不许加 remove/清理，只改去重键构造**；③ §2.3 强调「KP 收不到新申请弹窗是 bug 不是设计」；④ **KP-5 主因由「与 KP-1 barrier 共因」改为 B2-1（`onSend` 闭包持有已 dispose 的 `ChatInputRowState`）**，新增甲乙两变体完整夹具裁定用例。**初稿发给 team-lead 的「KP-1/KP-5 大概率同根因、合并排查、优先修 watcher」结论已作废，以本修订为准。** ⑤ **老 APP 口径复核（`researcher-oldapp-p17` 提供 `room-panels.js`/`room-rules.js`/`room-model.js` 行号，未经我本人二次读源码）**：KP-2「检定方式四档」**老 APP 也没有**（0 命中）→ 纯新需求、需主理人拍板，且老 APP 有**大小写退化坑**必须统一；KP-3「武器对抗」**不是独立功能**（= 老 APP `playerOpposedSheet`），**删按钮但必须保留 `INTENT.OPPOSED` / `opposed()` 整条链路**，且**新 APP 权威端已内置 4 档技能别名归一**（`room_rules_sheet.dart:369-421`）——初稿「需新增反向解析 / 复用 `skill_synonyms.dart`」判断作废，KP-3 只需补 UI 输入框。 ⑥ **KP-5 H1 复核（`researcher-bugs-p17`）**：H1 降级为 B2-1 的一句注解（不删、不单列独立假设）；补 **debug/release 限定**（真机 assert 被裁须另验）、**`try/finally` 为不依赖抛点的无条件兜底必须做**、甲乙裁定在 debug 夹具做且真机再跑一轮；**KP-1 与 KP-5 文件不重叠可并行**，`room_model_host_intent.dart:484-486` 改动须挂 QA 全量回归。 ⑦ **老 APP B6 补查（`researcher-oldapp-p17`）**：`pc:` 只是 `kpAttackSheet` UI 下拉的 value、提交前被 `optOf` 剥掉**从不进模型载荷**（`core/` 0 命中），模型按 `spec.side` 分派、`_resolveOpposedSide` 完全不看前缀 → **别给新 APP domain 写 `pc:` 解析**；`secret` 秘密对抗的**新 APP domain 已 1:1 落地**（`emitOpposedCheck :1390-1416` + `:2682` 暂存态继承），P17 无需施工，仅登记「伤害副作用 HP 是否泄漏公共流」的验收边界。
- 术语：`dock` = KP 平板横屏固定网格（`roomDockPlanOf(isKp: true)`，`widgets/room_layout.dart:103`）；「弹窗后的 3 个按钮」按任务口径 = `sheet_treat.dart` 选治疗方式的 3 个 `RoomTap`（急救/医学/精神分析）。

---

## 0. 硬约束（施工单会重申，本文全程遵守）

1. KP 改动**只落平板横屏 dock**；玩家视角 / folded 档不动。
2. `lib/domain/data/skills.dart`、`occupations.dart` 是 GENERATED FILE，**禁改**。
3. `test/oracle_*`、`test/room_rules_oracle_test.dart`、`test/fixtures/room_actions.json`、`test/fixtures/room_model.json` 是**逐字节契约**，禁改。
4. `lib/domain/room_rules_combat.dart` 计算式禁改（KP-7 直接相关：`_initiativeOrder` 在此文件）。
5. `lib/ui/room/**` 零 emoji（`⚔️` 这类 BMP 允许）；**禁止新写 `jsStr(`**（预算冻结，复用 `roomText`）。
6. 测试不许为变绿放宽断言；固定尺寸控件须测 `textScaler` 1.3/1.5/2.0（范本 `test/p16_button_unify_test.dart`）。
7. P16 已改的事实（**别当原始状态**）：`room_layout.dart` KP dock 已删 `gpStatus`/`gpCombat`，中排 flex **41→46**（`:148`），右列 `gpScene 56`/`gpPlayers 44`（`:140-141`）；`gpMap` 战斗态默认渲染 `GpCombatList`；`GpKpLeft` 吃满高度；素材「公开」互斥；左栏加怪改弹窗；工具窄栏删加怪/上传；`sheet_opposed.dart`/`sheet_scene.dart` 手填 id 已改 `unit_picker.dart` 下拉。

---

## 1. 文件 → 需求 映射（供切批，重叠文件必须串行）

| 文件 | KP-1 | KP-2 | KP-3 | KP-4 | KP-5 | KP-6 | KP-7 | KP-8 |
|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| `room_request_watcher.dart` | ● | | | | ○ | | | |
| `sheets/sheet_treat.dart` | ● | | | | | | | |
| `room_game_page.dart` | ○ | | ○ | | | | | ○ |
| `room_controller.dart` | ○ | | | | | | | |
| `domain/room_model_host_intent.dart` | ○ | | | | | | | |
| `domain/room_model_actions_sheet.dart` | ○ | | | | | ○ | | |
| `widgets/gp_scene_check_kp.dart` | | ● | | | | | | |
| `sheets/sheet_scene.dart` | | ● | | | | | | |
| `sheets/sheet_opposed.dart` | | | ● | | | | | |
| `widgets/gp_dice_bar.dart` | | | ○ | | | | | |
| `sheets/sheet_kp_panel.dart` | | | ○ | | | | | ● |
| `domain/room_model_actions_combat.dart` | | ○ | ○ | | | | ○ | |
| `domain/room_rules_combat.dart`（只读） | | | | | | | ○ | |
| `domain/room_model_rollback.dart` | | | | | | | ○ | |
| `domain/room_types.dart`（只读） | | | ○ | | | ○ | ○ | |
| `widgets/gp_feeds.dart` | | | | ● | ● | | | |
| `widgets/gp_privates.dart` | | | | ● | | | | |
| `widgets/room_layout.dart` | | | | ○ | | | | |
| `widgets/room_panel_kit.dart` | | | | ○ | | | | |
| `sheets/sheet_chat_composer.dart` | | | | | ● | | | |
| `sheets/sheet_kp_directives.dart` | | | | | | ● | | |
| `sheets/sheet_misc.dart` | | | | | | | | ● |
| `widgets/gp_combat_list.dart` / `gp_combat_strip.dart` | | | | | | | ● | |

**最热的 3 个重叠文件（必须单 worker 串行）**：
1. `domain/room_model_actions_combat.dart` —— KP-2（难度）/ KP-3（`checkOpposed`/`opposed`）/ KP-7（order）三项同时要碰。
2. `widgets/gp_feeds.dart` —— KP-4（块内高度）+ KP-5（全屏发送回调）同文件。
3. `sheets/sheet_kp_panel.dart` —— KP-3（对抗入口核对）+ KP-8（新增音乐按钮）同文件。

---

## 2. 逐项落点

### KP-1「申请推送后治疗按钮失灵」（用户报的真 bug，优先级最高）

**一行结论**：治疗弹层自身是好的（纯弹层测试 `test/p16_wave1_sheets_test.dart:567-608` 三分支全过）；「推送过一次之后失灵」的根因在**页面级 `RoomRequestWatcher` 的 `showGeneralDialog` 弹层状态 / `_seen` 去重**，与 domain 的 pending 去重共同构成；治疗按钮只在 `!isKp`（玩家侧）渲染，KP dock 本身没有治疗按钮——施工前需向用户确认复现视角。

#### 2.1 完整链路（逐段文件:行号）

| 段 | 文件:行号 | 现状行为 |
|---|---|---|
| 入口 | `room_game_page.dart:1050-1066` | `if (!isKp)`（`:1056`）才渲染「治疗」`RoomTap`（`treatKey` `:249`）；`onTap: openTreatSheet(context, ctl: RoomScope.read(context).controller)`（`:1064-1065`）。**KP 视角（含 dock）没有这个按钮**。 |
| 弹层 | `sheets/sheet_treat.dart:72-84` | `openTreatSheet` → `showRoomSheet`（`:76`），body = `TreatSheet(key: ValueKey('treatSheet/body'))`。 |
| 3 个按钮 | `sheets/sheet_treat.dart:151-161` | 急救/医学/精神分析 3 个 `RoomTap`（`_kTreatKinds` `:65-69`），`onTap` 只 `setState(() { _kind = k; _targetSeat = ''; })`（`:157-160`）——**纯本地态，不发 intent、不碰 domain**；选中后出现第二步「选择队友」+「提交申请」（`:165-219`）。`TreatSheetKeys.kind` `:40-41`。 |
| 提交 | `sheets/sheet_treat.dart:110-124` | `_submit`：payload `{seat: session.seat, targetSeat, [skill]}`（`:116-121`）→ `ctl.hostAction(kind.op, payload)`（`:122`）→ `Navigator.of(context).pop()`（`:123`）；`kind.op` = `aid.apply`/`aid.psycho`。 |
| 出口 | `room_controller.dart:74-80` | `hostAction` **只** `await session.hostAction(action, p)`，catch 转 notice；**无 `_busy`、无全局闸门**。`throttle`（`:108-115`）按 key 分桶、400ms，治疗路径**没有调用**。`gate.can`（`:33`）也不参与此弹层。`dangerAction`（`:95-104`）注释里记录了同款「同一 pending 去重吞掉第二次点击」的历史 bug。 |
| POLICY | `room_types.dart:311-318` | `aid.apply`/`aid.psycho` = `[player, kp]` + **`RoomConfirm.kp`** → 玩家发起必入 `pending` 队列，KP 确认才执行。 |
| 入队 | `room_model_host_intent.dart:288-343` | `act()`：`confirm != null` 且 `seat != kHostSeat` → 按 `by + op + jsonEncode(p)` 去重（`:307-323`），命中回 sysTo「该操作已在等待确认，请勿重复提交」（`:316-319`）并 return；否则 `pending.add({by, op, p, need, at})`（`:324-330`）。**注意 pending 条目没有 `id` 字段**。 |
| 消费 | `room_model_host_intent.dart:476-510` | `confirmPending`：按 `op + p['by']` 定位（`:484-486`），`pending.removeAt(idx)`（`:491`），同意 → `applyAction(jsStr(entry['by']), asMap(entry['p']))`（`:509`）。 |
| 结算 | `room_model_actions_sheet.dart:320-355` | `dispatchSheetAction` case `aid.apply`（`:349`）/ `aid.psycho`（`:351`）；handler 用 `skillBaseOf` 从角色卡自动取检定值（`:1600`、`:1732`），**不接受 UI 传 base**（`sheet_treat.dart:15-18` 已登记口径差）。 |
| 推送弹窗 | `room_request_watcher.dart:157-210` | `collectRoomPushRequests`：KP 读 `hostRead.pending`（`:162-179`）+ `read.requestsBySeat`（`:181-193`）；玩家读 `state['requests']`（`:194-207`）。**KP pending 去重键 `id: 'pending:$op:$by'`（`:170`）**；状态请求用 `id = roomText(r['id'])`（`:183-190`）。 |
| watcher 状态 | `room_request_watcher.dart:225-310` | `_seen`（`:232`）、`_queue`（`:233`）、`_draining`（`:234`）；`didChangeDependencies` 首挂载把当时已有 id **全部** `_seen.addAll`（`:253-255`）；`_onSession` `if (_seen.add(r.id)) _queue.add(r)`（`:270`）——**全库无 `remove`**；`_drain` `await showGeneralDialog`（`:287-305`），`finally` 复位 `_draining`（`:307-309`）；`_reply` 发 intent 后 `Navigator.of(ctx).pop()`（`:391`）。 |
| 挂载 | `room_game_page.dart:313-336` | `RoomRequestWatcher`（`:319`）包在 `PopScope`/`KeyedSubtree`（`:335-336`）**之外**，注释明说放里面会连 `_seen` 一起丢。 |

#### 2.2 至少 2 个可证伪假设（含证据行号）

**假设 A（解释「其他玩家推送的申请没反应」；置信度最高）——`_seen` 永不清理 + 请求 id 复用**
- 证据：`room_request_watcher.dart:232` `final Set<String> _seen`；`:253-255` 首挂载 `addAll`；`:270` `if (_seen.add(r.id)) _queue.add(r)`；**全文件无 `_seen.remove` / `_seen.clear`（除首挂载）**。一旦某 id 被弹过（哪怕点屏障关闭、或点同意/拒绝后被 settle），该 id 永久留在 `_seen`。
- id 复用来源：① `collectRoomPushRequests` KP pending 用 `'pending:$op:$by'`（`:170`）——**同一玩家连续两次发同一 op（如两次 `aid.apply`），或不同玩家发同 op 但 `by` 解析成空串时，id 完全相同**；② 状态请求用权威端 `r['id']`（`:183`），而 `checkRequest` 的 `final id = 'c$localSeq'`（**`room_model_actions_combat.dart:1327` 在 `for (final t in targets)` `:1338` 之外只生成一次**）被 `:1359` 写进**每一个** `requestsBySeat[t]`（`:1338-1368`）——一次「全体检定」产生 N 条**同 id** 记录；KP 读 `hostRead.requestsBySeat` 全量（`room_request_watcher.dart:181-193`）→ watcher 只认第一条、只弹 1 次。这是**第二处独立 id 撞车**（与 `researcher-bugs-p17` 报告 §2.5 交叉核验一致）。
- **⚠️ 红线**：`_seen` 不去重是 P10 刻意设计、被 `test/p10_t6_room_fixes_test.dart:562`「5D 同一 id 只弹一次」钉死。**不要给 `_seen` 加 `remove`/清理**（会打红该断言），要改的是**去重键构造**（见 §2.4 建议①）。
- **可证伪**：注入两条 `id` 相同（如 `pending:aid.apply:p1` 两次）的请求，断言弹窗出现次数；若第二次仍弹则假设不成立。现有 `test/p10_t6_room_fixes_test.dart:677-719` 只测「一条 pending 弹一次」，**没有重复 id 用例**（测试缺口）。

**假设 B（解释「推送过一次之后 3 个按钮都没反应」）——`showGeneralDialog` 的 modal barrier 残留 / `_draining` 卡死**
- 证据：`room_request_watcher.dart:287-305` 弹窗是 `showGeneralDialog` 的 modal route，`barrierDismissible: true`（`:289`）；`_drain` 靠 `await` 等 route pop（`:287`），`_reply` 用 `Navigator.of(ctx).pop()`（`:391`）关闭。若弹窗 route 未被 pop（例如 `_reply` 的 ctx 与 route 失配、或页面在弹窗打开时被 `room_game_page.dart:335-336` 的 `KeyedSubtree` 换 key 重建），**modal barrier 会一直拦截下层所有点击** → 治疗弹层 3 个 `RoomTap`（`sheet_treat.dart:151-161`）点了没反应。
- 旁证：`test/p10_t6_room_fixes_test.dart:700-703` 测试里必须显式 `await tester.tapAt(const Offset(4, 4))`（点屏障）关闭弹窗，才能继续后续操作——证明 barrier 确实吃点击。`:646-657` 也靠整树重建来复位 watcher。
- 变体 B'：`_onSession` 先 `_draining = true`（`:273`）再排 postFrameCallback（`:274-276`，`if (mounted) unawaited(_drain())`）；若回调因 `mounted == false` 未执行，**`_draining` 不在 finally 里、永久卡 true**（复位只在 `_drain` 的 `finally` `:307-309`），之后再无弹窗。
- **可证伪**：真机/测试里点「同意」后查 `Navigator` 栈顶是否还有 modal route；或连续触发两次 `_onSession` 观察 `_draining` 是否复位。
- **⚠️ 修订（与 `researcher-bugs-p17` 交叉复核后降级）**：本文初稿曾把假设 B 外推为 KP-5「全屏编辑发送无反应」的共因，并建议「两症状合并排查、优先修 watcher」。**该外推不成立**，三条反证：① 用户描述是「点输入框 → 成功进全屏 → 编辑文字 → 点发送」，barrier 若仍在栈顶会吃全页点击，第一步就做不到；② 编辑期间若新推送弹出，`showGeneralDialog` 会盖在 `ChatComposerPage` 之上，用户看到的是居中对话框而非「点发送没反应、文字还在」；③ `test/p10_t6_room_fixes_test.dart:700-703` 必须显式 `tapAt(4,4)` 点掉 barrier 才能继续，恰好反证「barrier 在时连测试都得显式点掉」，而 `p10_t7_c_feeds_test.dart:462-497` 能一路点到发送正说明其夹具里 barrier 不在。**结论：假设 B 只用于解释 KP-1（治疗按钮没反应 + 新申请不弹）；KP-5 主因另见 §KP-5「B2-1」。** 唯一能让 B 对 KP-5 成立的边界是「透明但命中仍在的残留 route」，真机层低置信。裁定方式见 §KP-5 末的甲乙两变体验收用例——**施工单不得凭任一报告直接改布局/domain**。

**假设 C（domain 侧，解释「提交申请点了没反应」，非 3 个方式按钮）——`confirmPending` 用 `op+by` 定位失败导致 pending 残留，后续同签名申请被 `act()` 去重吞掉**
- 证据：`room_model_host_intent.dart:307-323`（去重命中即 return，不执行）；`:484-486`（`confirmPending` 按 `pending[i]['op'] == op && pending[i]['by'] == p['by']` 定位）；watcher 弹窗回的 `by` 取自 `roomText(q['by'])`（`room_request_watcher.dart:164`，即 `pending` 项的 `by`），而 `act()` 写 pending 时 `by = seat`（`:325`）——正常情况下一致；但若 `by` 为空/被裁剪（例如跨设备成员裁剪后 `by` 丢失），`confirmPending` 找不到 idx（`:487-490`「这条待办已经处理过了」）→ pending 不摘 → 之后同 `by+op+jsonEncode(p)` 的申请全被吞。
- **⚠️ 三点修正（与 `researcher-bugs-p17` 对齐，避免施工单误改 domain）**：① `act()` 去重判据 `:309-311` 含 `jsonEncode(q['p']) == sig`，**只吞同 op + 同 by + 同参数**的重复提交，`:316-319` 明确回「该操作已在等待确认，请勿重复提交」——这是**设计上的防重复提交，不是把不同申请误吞**；② `:304-305` `confirm == RoomConfirm.kp && seat == kHostSeat` 时 **KP 自己发起直接 `applyAction`、根本不进 pending**，所以 C 只对「玩家提交」成立、对「KP 提交」不成立（这也反证治疗按钮只在 `!isKp` 渲染）；③ **连锁点**：`:484-486` 的 for 循环**不 break**，`idx` 被覆写成**最后一个**匹配项——若按假设 A 改去重键让两条 pending 都能弹出来，KP 点同意只会摘掉最后一条、第一条永久残留 → **必须同步修 `:484-486`**，否则「弹两条、同意一条、另一条再也消不掉」。
- 补充缺口：`settleRequest` 里 `pending.removeWhere((x) => x['id'] == id)`（`room_model_actions_combat.dart:1305`）**清不掉 `act()` 入队的 pending**（那些条目无 `id` 键，`room_model_host_intent.dart:324-330`），只有 `list.removeWhere`（`:1303`）与 `confirmPending` 的 `removeAt` 能清。
- **别叠第二条提示**：domain 已有 `sysTo`「已提交，等待确认」（`room_model_host_intent.dart:331-339`），只是**只发给发起玩家、KP 看不到**——不是「零反馈」，施工单不要再叠第二条成功提示。
- **可证伪**：玩家连续两次 `hostAction('aid.apply', 同载荷)`，检查 `session.sent` 条数与第二条是否收到 sysTo「请勿重复提交」。

> **施工单须注明**：用户口述的「弹窗后的 3 个按钮」是 `sheet_treat.dart:151-161` 的**纯 setState 按钮**，与 domain 无关；因此「3 个按钮没反应」只可能由 UI 层（假设 B）造成，假设 A/C 解释的是「申请不弹 / 提交被吞」。请在真机复现时区分「选方式后没进入第二步」与「选完点提交没反应」。

#### 2.3 「其他玩家推送的申请没反应」是否同一根因

- **KP 侧**：`collectRoomPushRequests` 走 `session.hostRead.requestsBySeat`（`room_request_watcher.dart:159-160,181`），`RoomHostRead.requestsBySeat`（`room_session.dart:88-90`）取的是**权威端全量** `host.requestsBySeat`（`room_model_host_core.dart:105`），**不受成员裁剪**；`syncMembers()`（`room_model_host_core.dart:584-585`）只广播 members，注释（`room_model_host_intent.dart:390-391`）明说「碰不到 `state.requests`」。→ 与假设 A **同一根因（id 复用/`_seen` 不清理）**，不是 `RoomVis`/`syncMembers` 问题。
- **玩家侧「看不到别人的申请」是设计、非 bug**：请求用 `vis: RoomVis.seat, to: seat` 定向（`room_model_actions_combat.dart:1311`、`:1360-1368`），客户端 `state['requests']` 只由 `RoomEvt.request(self && ...)` 裁剪（`room_model_reduce.dart:344-362`），全量同步 `_requestsView(seat)` 也只取本 seat（`room_model_host_core.dart:564-575`）。`test/p10_t6_room_fixes_test.dart:646-657`（含 `:646-660`）明确断言「别的玩家不该收到别人的推送」并 `findsNothing` 钉死。
- **⚠️ 但务必区分视角**：上面这条**只约束玩家**；KP 走 `hostRead.requestsBySeat` 全量（见上一条），**本就该看到所有 seat 的待办**。所以「KP 收不到新申请弹窗」**不是设计、是 bug**（假设 A），施工单别把 KP 侧一起放过。

#### 2.4 建议落点 / 会撞到的既有测试
- 建议：① **只改去重键构造**，把 `collectRoomPushRequests` 的 `id:'pending:$op:$by'`（`:170`）与状态请求 id（`:183`）改成含 `at`/seq/目标 seat 的**稳定唯一值**，让两条不同 pending 都能弹、全体推送的每个 target 各有独立 id。**严禁给 `_seen` 加 `remove`/清理**（`:562` 红线，会打红 P10「同一 id 只弹一次」断言）。`_draining` 复位改到 `_onSession` 的 postFrameCallback 外层兜底（`:273-276`）；`_reply` 的 pop 改为持有 route Future 或 `rootNavigator` 口径。② **必须同步**修 `confirmPending`（`room_model_host_intent.dart:484-486`）的「循环不 break / idx 覆写成最后一条」——否则弹两条、同意只摘一条、另一条永久残留（假设 C 修正③）。③ 若采用假设 C，`confirmPending` 增加 `by` 为空的兜底定位；**不要**额外叠「已提交」提示（`:331-339` 已有 sysTo，只是 KP 侧看不到）。④ **不要改** `sheet_treat.dart` 的 3 个按钮（它们没问题）。⑤ **KP-1 与 KP-5 分开裁定，不要合并修**：按 §KP-5 末的甲乙两变体完整夹具用例先复现再动刀。
- 撞测试：`test/p10_t6_room_fixes_test.dart:485-715`（watcher 全套，尤其 `:693-703` 屏障关闭、`:646-657` 跨视角裁剪、`:677-719` 两条数据源 CONFIRM/CONSENT）；`test/p16_wave1_sheets_test.dart:567-608`（`openTreatSheet` 三分支路由，断言 `seat='p1'`/`targetSeat='p2'`/`skill`/不含 `base`，`:592-604`）；`test/p10_t4_synonym_request_done_test.dart:105-114,241-249`（`state.request` pending 不残留）；`test/fixtures/room_actions.json:258` `A:pending:aid.apply`（逐字节契约）；`test/room_ui_feeds_test.dart`。

---

### KP-2 场景检定「检定方式」改老 APP 模式 + 四个等级

**一行结论（经 `researcher-oldapp-p17` 老 APP 源码复核）**：**老 APP 2.13.13 也没有「检定方式」四档**（全库 Grep `检定方式|检定等级` **0 命中**）——**这是纯新需求，不是照抄老 APP，必须请主理人定义四档语义**。新 APP 现状只有 6 档裁定结果 level + 3 档难度且 UI 全硬编码 `'REGULAR'`；老 APP 与新 APP 在「无检定方式选择器」上是一致的。⚠️ 老 APP 有个**大小写退化坑**（UI/载荷大写、domain 键小写），施工时务必统一，见下。

**现状事实**
- `widgets/gp_scene_check_kp.dart`：`kSceneCheckLevels = [5,4,3,2,0,-1]`（`:27`）、`kKpSceneLevels` 6 档文案（大成功/极难成功/困难成功/成功/失败/大失败，`:38-45`）——这是 **`scene.check.step` 的 `level`（裁定结果）**，不是「检定方式」。`sceneCheckStepPayload({stepId, seat, level})`（`:48-58`）恰好 3 键，6 档按钮 `gate.can('scene.check.step') && hasStep`（`:143-159`）。
- 推送载荷：`kpQuickSceneStep()`（`:75-81`）硬编码 `'difficulty': 'regular'`（`:80`，小写）；「快速推送」按钮发 `scene.check.push {title, desc, steps:[kpQuickSceneStep()]}`（`:160-175`）；「检定编辑器」入口（`:176-195`）打开 `showSceneSheet`。
- `sheets/sheet_scene.dart`：头注释（`:6-7`）明写「难度用 REGULAR / HARD / EXTREME **三档**」；`_StepDraft.toPayload`（`:80-92`）`'difficulty': 'REGULAR'`（`:87`）；「要求检定」`check.request` 载荷（`:348-362`）`'difficulty': 'REGULAR'`（`:358`）；`scene.check.push` 推送（`:236-253`）；`scene.clue`（`:294-307`）、`state.request`（`:363-376`）。P16 已把 4 处座位输入改成 `UnitPickerField`（`:196-206`、`:265-275`、`:321-331`、`:380-390`），**载荷字段名 `targetSeat`/`seat` 未变**。
- domain 消费端（**不在 sheet 文件，在 combat 文件**）：`room_model_actions_combat.dart:25-112` `dispatchCombatAction` case `check.request`（`:86-98` → `checkRequest`）、`scene.check.push`（`:101-102` → `sceneCheckPush`）、`scene.check.step`（`:103-104`）；`checkRequest`（`:1319-1380`）读 `p['difficulty'] ?? 'REGULAR'`（`:1324`），`diffText` 三档中文标注（`:1370-1374`）；`sceneCheckPush` 用 `raSanitizeSceneSteps(p['steps'])`（`:2700`），step difficulty 在 `:2821-2827`；`raSanitizeSceneSteps` 在 `room_model_actions_room.dart:410-426`，**`:426` 把 difficulty 收敛成 `(HARD|EXTREME) ? diff : 'REGULAR'`**；等级映射 `room_rules.dart:51-53`（`EXTREME:4 / HARD:3 / REGULAR:2`）。
- **⚠️ 老 APP 复核结论（行号由 `researcher-oldapp-p17` 提供，来自 `room-panels.js` / `room-rules.js` / `room-model.js`，**未经我本人二次读源码**；其报告 `_p17_oldapp_research.md` B2(1-补)/B5 节）**：老 APP 有三套东西，**都不是「检定方式四档」**，别混：
  - **① 难度 3 档（不是 4 档、不是检定类型）**：`room-panels.js:1885-1889`（快速推送）/ `:4512-4516`（场景检定编辑器 stepEditor）；value 字面量**大写** `REGULAR`/`HARD`/`EXTREME`，label `常规`/`困难（÷2）`/`极难（÷5）`，默认 `REGULAR`；载荷字段名 **`difficulty`**（`check.request {op,seat,skill,difficulty,desc}` `:1901-1902`；`scene.check.push` step 同名字段 `:4564`）。domain：`room-rules.js:54-58` `DIFFICULTY` **键小写** `regular/hard/extreme` = `{required: LEVEL.REGULAR(2)|HARD(3)|EXTREME(4), div: 1|2|5}`；`thresholds(base)` `:120-123`；`check()` `:285-297` `passed = level >= DIFFICULTY[difficulty].required`；`sceneStepResolve` `:1384-1405` `success = lvl >= required`。
  - **② 大小写退化坑（务必别复现）**：UI/载荷发大写 `HARD`/`EXTREME`，而 `DIFFICULTY` 键是小写，`normDifficulty(d)`（`:124`）`hasOwnProperty ? d : 'regular'` → **大写值在权威端退化成常规**（全库 Grep `difficulty.*toLowerCase` 0 命中；链路 `checkRequest` → REQUEST 卡 → `diceDirect :3044` → `rules.check() :285` 已逐段核）。新 APP 现状恰好也有大小写混用：`sheet_scene.dart:87/:358` 大写 `'REGULAR'`、`gp_scene_check_kp.dart:80` 小写 `'regular'`、`room_model_actions_room.dart:426` 白名单认 `HARD|EXTREME`（大写）、`room_rules.dart:51-53` `LEVEL` 大写键。→ **施工时必须统一一套大小写并全链路验证**，否则新 APP 同样会静默退化成常规。
  - **③ 6 档裁定结果 level = 新 APP 已有的 `gp_scene_check_kp.dart:38-45`，逐字一致**：`room-panels.js:1856` `[['大成功',5],['大失败',-1],['失败',0],['成功',2],['困难成功',3],['极难成功',4]]` → `scene.check.step {stepId, seat, level}`（`:1859`）；`room-rules.js:34-41` `LEVEL={CRITICAL:5,EXTREME:4,HARD:3,REGULAR:2,FAIL:0,FUMBLE:-1}`。这是**结果等级**，不是「检定方式」输入。
  - **④ 「检定类型」下拉已被老 APP 删除**：`:1881-1884` 注释逐字「删掉『检定类型』下拉（技能检定 / 属性检定）—— 协议里没有 type 字段」→ 明确**不是检定类型**。
- **🔴 需主理人拍板的歧义（施工单阻塞项）**：用户说的「检定方式 4 档：大成功/成功/困难成功/极难成功」在老 APP 里对应的是**结果 LEVEL 的子集 5/2/3/4**，老 APP 从没把它做成「成功所需等级」的输入；且「大成功」档**无对应难度**（`DIFFICULTY` 只有 3 档、无 critical 档，掷 01 才过）。请主理人定义：四档是「把结果 LEVEL 当 `required`」，还是「新造第 4 个难度档」；据此再定 `difficulty` 白名单与阈值计算。**不要凭空按老 APP 抄，老 APP 没有可抄的**。
- **老 APP 无通用「系统自动检定」**：`check.request`（`room-model.js:3190-3238`）推 REQUEST 卡给**玩家自己掷**，`_skillBaseOf` 权威取 base；只有 `scene.check.push` 里**疯狂发作中**目标由权威端替掷（`sceneCheckStep :6768-6783`，`autoBase = _skillBaseOf(m, step.skill, null)` 查不到回落 **50**），已撕卡则跳过不掷。若新 APP 要加「自动检定」，这是口径来源。

**建议落点（⛔ 先等主理人拍板四档语义，再动刀）**
- **阻塞前置**：四档是「结果 LEVEL 当 required」还是「新造难度档」未定前，不要写 UI 下拉、不要改 `difficulty` 白名单。施工单把此歧义列为第一批拍板项。
- UI：`gp_scene_check_kp.dart`（快速推送块加四档选择 + 把 `kpQuickSceneStep()` `:75-81` 的 difficulty 参数化）、`sheet_scene.dart`（`_StepDraft.toPayload` `:87` 与 `check.request` `:358` 改成读下拉值；步骤编辑器每行加一个选择）。
- domain（**慎动，与 KP-3/KP-7 同文件**）：若新增第 4 档，`room_model_actions_room.dart:426` 白名单、`room_model_actions_combat.dart:1370-1374` diffText、`room_rules.dart:51-53` 等级表 + `DIFFICULTY`/阈值计算需同步；**`room_rules_combat.dart` 计算式禁改**、**`room_rules_sheet.dart` 的 `_skillValue` 等 oracle 侧禁改**。
- **大小写统一（独立必做项）**：把 `sheet_scene.dart:87/:358`、`gp_scene_check_kp.dart:80`、`room_model_actions_room.dart:426`、`room_rules.dart:51-53` 统一成同一套字面量（建议按 domain `DIFFICULTY` 键小写 `regular/hard/extreme`，或全程大写并让白名单/阈值两侧都认），并补一条端到端用例验证 `HARD` 真的按 ÷2、`EXTREME` 按 ÷5 生效，**别复现老 APP 静默退化成常规**。
- 保持 `scene.check.push` / `check.request` 的 op 与字段名不变（fixture 锁定）。

**会撞到的既有测试**：`test/room_ui_kp_test.dart:1003-1006`（`SceneSheet.addStep`）、`:1116-1148`（T04 源码门禁）；`test/room_ui_permission_test.dart:304-353`（T-30 锚点表）、`:358-487`（`enabled == gate.can`）；`test/p16_wave1_sheets_test.dart:320-352`（4 处 `UnitPickerField` 断言 + 静态扫 `unitValueToSeat(`）、`:376-410`（选单位交互）；`test/p10_t6_room_fixes_test.dart`；`test/fixtures/room_model.json:105,268-270,1962-1976`、`room_actions.json:207-209,9611-9658`（`scene.check.push` POLICY 逐字节契约）；`test/room_ui_shell_test.dart`。

---

### KP-3 对抗大改（删除「武器对抗」+ 输入技能套用近义词自动取角色卡数值）

**一行结论（经 `researcher-oldapp-p17` 老 APP 源码复核）**：「武器对抗」按钮在 `sheets/sheet_opposed.dart:144-153`（发 `RoomIntent.opposed {phase:'apply'}`）；老 APP 里它**不是独立功能**——「⚔ 战斗对抗」按钮 = `playerOpposedSheet` = 弹层标题「⚔ 武器对抗」= **同一个玩家功能**，走 `INTENT.OPPOSED {phase:'request', ...}`。→ **删的是那个「独立按钮/弹层」，`INTENT.OPPOSED` / domain `opposed()` 整条链路必须保留**，否则把玩家战斗对抗本身删没了。另 UI 现有载荷（`kind:'general'` / 裸 `base` / 直发链路里的 `reqId`）与老 APP 及 domain `checkOpposed` 期望的 `aSeat/aSkill/bSeat/bSkill/...` **字段对不上**，正是「对抗大改」要补的；`kind:'general'` 与裸 `base` 是新 APP 自造、老 APP 全库 0 命中。

**现状事实**
- `sheets/sheet_opposed.dart`：五入口注释（`:4-7`）；`OpposedSheetKeys.weapon`（`:40`）、`reqBase`/`targetBase`（`:47-48`）；`kpOpposedCanApply`（`:52-60` = 非旁观 + `isCombat` + `isMyTurn`）；两处 `UnitPickerField`（`:163-170` 申请单位、`:206-213` 伤害目标）、无卡单位 `TextField`（`:172-181`、`:215-224`）；通用对抗 `check.opposed {kind:'general'}`（`:121-133`）；攻击对抗 `combat.attack {phase:'apply'}`（`:134-143`）；**武器对抗 `:144-153`**（`sendIntent(RoomIntent.opposed, {phase:'apply'})` `:149-152`）；裁定 `check.opposed {reqId, attack:true, [base]}`（`:182-196`）；选目标 `RoomIntent.opposed {phase:'target', targetId, [base]}`（`:225-239`）。
- 入口分布：`widgets/gp_toolbar.dart` **没有对抗按钮**（主组 `:113-174` 只有缩放/下一轮/转战斗，扩展 `:178-184`）；真正入口是 `widgets/gp_dice_bar.dart:356-362`（「对抗」→ `showOpposedSheet`，其 `:318-330` 注释记载历史 bug「空参 `check.opposed` → domain 回『甲方无效：未指定对抗方类型』」）、`sheets/sheet_kp_panel.dart:317-323`（「对抗」→ `opener('opposed')` → `openKpSheet` case `'opposed'` `:154-156`）、`room_game_page.dart:1021-1028`（「KP」按钮 → `showKpPanel(onOpen: openKpSheet)`）。
- domain 消费：`room_model_actions_combat.dart:25-112`（case `check.opposed` `:99-100` → `checkOpposed`；case `'opposed'` `:107-108` → `opposed(seat, roster.get(seat), RoomRole.player, p)`，**硬编码 player**）；`checkOpposed`（`:1538-1630`）期望 `aSeat/aSkill/aBase/aBonus/aPenalty`、`bSeat/bSkill/bBase/bBonus/bPenalty`、`difficulty`、`rng`（`:1547-1550,1559-1578`），`attack`/`cancel` 走 `opposedAttackResolve`（`:1544-1546`）；`resolveActorSkill`（`:1634-1705`）已支持 `p:`/`a:`/`mo:` 前缀（`:1651-1660`）并用 `skillBaseOf(m, name, fallback)`（`:1671`）从角色卡取值；`skillBaseOf`（`:1744-1755`）调 `rules!.skillValue(sheet, nm)` / `attrValue`（`:1748-1750`），而 `rules.skillValue`（`room_rules.dart:284`）**内部已走 4 档别名归一**（本次复核修正，详见下条）；`opposed`（`:2440-2461`）`if (role != RoomRole.player) return sysTo('只有玩家能发起武器对抗')`（`:2447-2450`）；`opposedPlayerRequest`（`:2464-2560`）需 `p['weapon']['name']`（`:2479-2480`）、`targetId`（`:2520`）、`shots`（`:2503`）、`db`（`:2496-2498`）。`room_types.dart:302` `check.opposed` `[kp]`，`:283` `combat.attack` `[kp,player]`。
- **✅ 重大修正（本次复核）：新 APP 权威端已完整具备「输入技能别名 → 自动取角色卡数值」，无需新增任何反查、无需碰 `skill_synonyms.dart`**：
  - `room_rules_sheet.dart:369-421` `_skillValue(Object? sheet, Object? skillName)` **已实现老 APP `room-rules.js:1265-1300` 的 4 档归一**（注释 `:371-372` 逐字「① 精确名 ② 别名 ③ 基名相等 ④ 子类名相等」，命中多个即判歧义返回 null）：`_normSkillName`（`:329-339`，全/半角括号→`()`、去空白、去首尾标点、小写）、`_skillAlias`（`:297-314`，**16 条**，与老 APP `SKILL_ALIAS :1180-1197` 逐条对应：斗殴→格斗(斗殴)、踢→格斗(踢)、射击/手枪→射击(手枪)、弓/弩、侦察→侦查、图书馆→图书馆使用、计算机→计算机使用、开锁→锁匠…）、`_skillBase`（`:342-346`）、`_skillSpecs`（`:349-359`）；`_attrValue`（`:424+`）支持中文名或 key。
  - 链路已通：`checkOpposed :1549-1550` → `resolveActorSkill :1634-1705` → `skillBaseOf :1671/:1744` → `rules!.skillValue :1748` → `room_rules.dart:284` → `_skillValue`。**唯一缺的是 UI**：`sheet_opposed.dart` 没有 `aSkill`/`bSkill` 输入框、也没把它们放进 `check.opposed` 载荷。→ 施工单只需「补两个技能文本输入 + 载荷补 `aSkill`/`bSkill`」，**domain 一行不用改，且天然避开 `oracle_*` / `room_rules_sheet.dart` 红线**。
  - **我初稿判断作废**：原写「现有 API 没有『输入别名 → 规范技能名』反向解析、需新增或复用 `skill_synonyms.dart` 反查」是错的——那张表是**车卡搜索**用的（`skillSynonyms` 方向是「技能 id → 近义词列表」），与权威端取值不是一回事。
  - **三张别名表别混**（老 APP 口径）：① `room-rules.js SKILL_ALIAS` / 新 APP `room_rules_sheet.dart:297-314 _skillAlias`（**权威端取值，本项要用**）；② `steps-c.js:30-34 WEAPON_SKILL_ALIAS` / 新 APP `combat_skill_map.dart:33`（车卡阶段武器→专攻名）；③ 新 APP P15 `skill_synonyms.dart`（`skillSynonyms :44-102`、`skillSynonymIdOf :113-129`、`synonymsOf :132-136`、`synonymContains :142-149`、`synonymOwnersOf :152-155`）+ `skill_subskill_synonyms.dart`（`skillSubskillSynonyms :34`、`subskillSynonymsOf :164-169`）（车卡搜索近义词，消费方 `lib/ui/create/skill_groups.dart:21-22,219-236`）——**②③ 不要接进对抗取值**。
  - 老 APP UI `aSkill`/`bSkill`（`room-panels.js:4706-4707`）是**纯文本框**（`maxlength:20`），**无下拉、无标签、无近义词搜索**；怪物/NPC 无卡 → 必须手输 1–100（`:4708-4712`、`:4730-4737`，`_resolveActorSkill :3849-3861` 校验 1–100 整数）。新 APP `sheet_opposed.dart` 的 `reqBase`/`targetBase`（`:47-48`、`:172-181`、`:215-224`）已是这个手输兜底，方向一致。
  - ⚠️ `skills.dart`/`occupations.dart` 是 GENERATED 禁改；`room_rules_sheet.dart` / `oracle_*` 是逐字节契约也禁改。
- 单位枚举契约：`widgets/unit_picker.dart` `collectUnitOptions`（`:100-149`）、`showUnitPicker`（`:160-194`）、`UnitPickerField`（`:200-246`）、`unitValueToSeat`（`:253-259`）、value 前缀 `p:<seat>`/`a:<id>`/`*`（`:13`）——**对抗弹层保留前缀**（`:250-252` 注释），与场景检定「剥裸 seat」是两套契约。

**老 APP 精确字段对照（行号由 `researcher-oldapp-p17` 提供，来自 `room-panels.js` / `room-model.js`，未经我本人二次读源码；其报告 B5 节全量 Grep 4+2 个提交点核过）**

| 场景 | 老 APP 载荷 |
|---|---|
| 通用对抗 KP 直发 `:4738` | `check.opposed {aSeat, aSkill, aBase, bSeat, bSkill, bBase, secret}` |
| 攻击对抗 KP 直发 `:4876` | `check.opposed {attack:true, attacker:{...}, defender:{...}, weapon:{...}, shots, armor:{...}, secret}` |
| KP 裁定玩家申请 `:5060` | `check.opposed {reqId, attack:true, noDefense, defender:{...}, armor:{...}, malfType, secret}` |
| 拒绝申请 `:5107` | `check.opposed {reqId, cancel:true}` |
| 玩家申请 `:4979` | `INTENT.OPPOSED {phase:'request', weapon, db, targetId, targetName, shots, note}` |
| 胜后选目标 `:5087` | `INTENT.OPPOSED {phase:'target', targetId}` |

- 老 APP **没有** `kind:'general'`（全库 0 命中）——通用/攻击靠 `attack:true` 有无分（`room-model.js:5841 if(p.attack||p.cancel)`），不是 `kind`。新 APP `sheet_opposed.dart:131` 的 `kind:'general'` 是自造字段。
- 老 APP **没有裸 `base` 协议字段**：通用用 `aBase`/`bBase`，攻击用 `attacker.value`/`defender.value`，申请用 `weapon`+`db`；`base` 只是 `rules.check()` 内部参数名（`room-rules.js:286`）。新 APP `sheet_opposed.dart:193`/`:236` 的 `'base'` 属自造。
- `reqId` **只在**「玩家申请 → KP 裁定」链路出现，直发链路没有。
- 难度/奖惩：老 APP 通用对抗 UI 载荷 `:4738-4741` **没有** `difficulty` / `aBonus`/`aPenalty`/`bBonus`/`bPenalty`，但模型 `checkOpposed :5863-5868` **接收**（`diff = p.difficulty || 'REGULAR'`、`bonus:num(p.aBonus,0)`…）→ **协议预留、UI 不发**；新 APP domain（`:1559-1578`）把模型侧预留做全，方向没问题，但**照老 APP UI 抄不到，得按模型口径补**。奖惩骰在老 APP 只在 `stepEditor :4518-4528` 与 `diceBar :5345-5397` 出现。
- **前缀（经 `researcher-oldapp-p17` B6 节复核，以下老 APP 行号由其提供、未经我本人二次读源码）**：
  - 全库 `grep -rnE 'pc:|mo:'`：`pc:` 在 **`core/` 0 命中**，只在 `ui/room-panels.js` 3 处（`:4688` 注释、`:4761`、`:4769`）——全是 `kpAttackSheet` 的 `attPool`/`defPool` 里 `selectCtl` 的 option `value: 'pc:'+m.seat`；`mo:` UI 3 处 + `core/room-model.js:3820-3822` 一处宽松解析。
  - **关键：`pc:`/`mo:` 是 UI 下拉的 value，提交前就被剥掉、从不进模型载荷**：`kpAttackSheet :4875-4890` 用 `optOf(attPool, aSel.value)` 按 value 找回选项对象，再构造 `attacker.seat = 裸 seat`、`attacker.actorId = 裸 id`、`side:'pc'|'monster'`；模型 `_resolveOpposedSide :5956-5975` **按 `spec.side` 分派**（`'pc'` → `roster.get(seat)` + `_skillBaseOf` 读人物卡；`'monster'/'npc'` → 手输 1–100 整数），**完全不看前缀**。
  - `p:`/`a:` 才是通用对抗（`check.opposed` 非 attack 路径）真正在 `aSeat`/`bSeat` 里传的复合值，由 `_resolveActorSkill :3816-3822` 剥：`p:`→`hint='pc'` roster 查座位、`a:`→`hint='actor'` 战斗单位 id、`mo:`→`hint='actor'`（v2.5.0 放宽，注释 `:3820` 逐字「UI 里怪物复合值还可能是 'mo:'（monster）或干脆不带前缀」），**无前缀两者都试**。已撕卡玩家拒绝通用对抗（`:3830-3833`）。
  - ⚠️ **`_resolveActorSkill` 不认 `pc:`**：误把 `pc:s1` 当 `aSeat` 传会落到「无前缀两者都试」→ `roster.get('pc:s1')` 失败 + `_findActorSlot('pc:s1')` 失败 → `ok:false`「找不到对抗单位」。这是**两套前缀体系**（攻击对抗下拉 value vs 通用对抗 `aSeat`/`bSeat` 复合值）不能混用的根因。
  - → **施工单：别为新 APP domain 写 `pc:` 解析**（老 APP 根本没这处理）；`resolveActorSkill :1651-1660` 已支持 `p:`/`a:`/`mo:`，口径一致，不要动。

**`secret`（秘密对抗）口径 —— 新 APP domain 已 1:1 落地，不需补 domain**（老 APP 行号由 `researcher-oldapp-p17` B6 提供，未经我本人二次读源码）：
- 老 APP UI 三处复选框「秘密对抗（仅 KP 可见结果）」：`room-panels.js:4724`（通用）/ `:4863`（攻击）/ `:5050`（KP 裁定），载荷 `secret: !!secretChk.checked` 在 `:4741`/`:4896`/`:5065`。
- 模型 `room-model.js:5801-5824` `_emitOpposedCheck(out, payload, secret)`：**非秘密** → `EVT.CHECK PUBLIC`（全体现行 + 进公共日志，行为不变）；**秘密** → 完整结果经 `EVT.PRIVATE` 单发 KP（`VIS.SEAT, HOST_SEAT`）+ 公共只落一条脱敏 `EVT.LOG`「KP 秘密进行了一次对抗检定」。4 类调用点：`checkOpposed :5884-5896`、`_opposedAttackResolve :6205-6207`、`canDefer :6229-6232`、**暂存 `state.opposed` `:6242-6244`**（`secret` 一并暂存，跨 `await_target` 不泄漏）、`_opposedPlayerTarget :6636-6651`（`!!st.secret` 从暂存态继承）。`resolveAttack` 另把 `secret: !!o.secret` 透传进 `rules.check()`（`room-rules.js:1015`，结果带 `secret` 字段 `:305`），但**真正的可见性裁剪只在 `_emitOpposedCheck`**，规则层不负责。
- **✅ 新 APP 已等价实现（我本次复核）**：`room_model_actions_combat.dart:1390-1416` `emitOpposedCheck(out, payload, secret)`（注释 `:1390` 明写「旧版 :5811-5824」）——秘密走 `RoomEvt.private_ vis: RoomVis.seat, to: kHostSeat`（`:1404-1409`）+ 公共脱敏 `RoomEvt.log`「KP 秘密进行了一次对抗检定」（`:1410-1414`）；调用点 `:1628`（`checkOpposed` 收尾 `emitOpposedCheck(out, payload, jsTruthy(p['secret']))`）、`:2337`/`:2369`/`:2388`（攻击 / 暂存 `'secret': jsTruthy(p['secret'])`）、**`:2682` `st['secret'] == true`（从 `state.opposed` 暂存态继承，等价老 APP `:6636-6651`）**。→ 施工单**不需要改 domain**；`sheet_opposed.dart` 目前没有 `secret` 复选框/载荷，若后续要「秘密对抗」只需补 UI 一个复选框 + 载荷 `secret`。**注意：用户 P17 8 项里没有明确要求秘密对抗，此项仅作口径登记，不必施工**。
- ⚠️ **验收边界（老 APP 如实标注；新 APP 因 1:1 照搬同样存在）**：`secret` 只包裹**结果卡**（`EVT.CHECK`/`EVT.PRIVATE`/脱敏 `EVT.LOG`）；`_opposedDamagePlayer`/`_opposedDamageMonster` 的 `EVT.ACTOR`/`EVT.TURNSTATE` HP 同步、以及 `applyHpChange → stateApply` 的伤害副作用走**另一条 emit 链，不在 `_emitOpposedCheck` 范围内**，老 APP 侧未逐条核实。若将来实现秘密对抗，**必须单独验证「秘密对抗造成伤害时 HP 变化是否也会泄漏到公共流」**，别默认已处理。

**建议落点（修正版）**
- **删**：`sheet_opposed.dart:144-153` 那个独立「武器对抗」按钮 + `OpposedSheetKeys.weapon`（`:40`）；**但 `INTENT.OPPOSED` / domain `opposed()`（`:2440-2461`）整条链路必须保留**，把 `sheet_opposed.dart` 收成**一个玩家入口**（对齐老 APP `playerOpposedSheet`）。老 APP 死代码 `plBottomBar`（0 调用方）里曾并列两个入口、`:3253-3254` 注释明确已摘除，**别据此认为老 APP 有两个并列入口**。
- **补**：「发起对抗」改成甲/乙两方 `UnitPickerField`（`p:<seat>`/`a:<id>`）+ **两个技能纯文本框**（老 APP 口径，无下拉无标签），载荷产出 `aSeat/aSkill/aBase/bSeat/bSkill/bBase`（对齐 `checkOpposed :1547-1550` 与老 APP `:4738`）；**删掉自造的 `kind:'general'` 与裸 `base`**；`reqId` 只留在裁定链路。
- **技能取值不用改 domain**：`aSkill`/`bSkill` 原样传给 `checkOpposed` → `resolveActorSkill` → `skillBaseOf` → `rules.skillValue` 的 4 档归一（含 16 条别名）自动取卡值；怪物/NPC 走 `aBase`/`bBase` 手输 1–100 兜底（`reqBase`/`targetBase` 已是这个用途）。**不要**把 `skill_synonyms.dart` 接进来、**不要**改 `room_rules_sheet.dart`/`oracle_*`。
- `gp_dice_bar.dart:356-362` / `sheet_kp_panel.dart:317-323` 入口保留但复核文案（老 APP 该弹层标题是「⚔ 武器对抗」）。
- domain 侧若要改 `checkOpposed` 入参需同步 `test/p16_wave1_sheets_test.dart:442-445`（当前断言 `{reqId:'p:p1', attack:true}`，改载荷必红）。

**会撞到的既有测试**：`test/p16_wave1_sheets_test.dart:290-318`（两处必须 `UnitPickerField`、`:306-310` 反向断言 TextField、`resolve`/`target` key）、`:420-471`（`check.opposed` 载荷逐字段 `:442-445`、`kpOpposedCanApply=false` 闸门 `:459-468`）、`:202-206`（`unitValueToSeat`）、`:345-352`（静态源码扫 `UnitPickerField(`/`unitValueToSeat(`）；`test/room_ui_kp_test.dart:963-979`（对抗弹层 `enabled == gate.can`）、`:1116-1148`（T04 门禁）；`test/room_ui_permission_test.dart:304-353`（T-30 锚点表，`check.opposed` 在 `gp_dice_bar.dart:356`+`sheet_opposed.dart:122` 两处挂载）、`:358-487`、`:535-591`（结构式 `findsNothing`）；`test/room_ui_wiring_test.dart`；`test/p10_t4_synonym_request_done_test.dart`（近义词表逐 id 非空）；`test/room_rules_oracle_test.dart` / `test/fixtures/room_model.json`（`check.opposed` 契约，禁改）。

---

### KP-4 游戏记录 / 只给你看比聊天栏短

**一行结论**：**根因不是 flex、也不是 `GpPrivates` 的 220（P16 已把它从 160 改到 220 并与 `GpFeeds` 对齐）**；真正差值是 `GpFeeds` 的 **chat pane 在 `SizedBox(height:220)` 下方多渲染一个 `ChatInputRow`**（`gp_feeds.dart:356`），record/priv 没有；三块 `SectionBox` 又都是 `Column(mainAxisSize: min)`（`room_panel_kit.dart:77`），Card 高度由内容决定，`CrossAxisAlignment.stretch` 只保证**格子**等高、不保证 **Card** 等高。

**精确尺寸计算（文件:行号）**
| 项 | 文件:行号 | 值 |
|---|---|---|
| 中排 flex | `room_layout.dart:146-154` | `flex: 46`（`:148`），`gpChat`/`gpLog`/`gpPriv` 各 `flex:1`（`:150-152`）→ **格子等高** |
| stretch | `room_layout.dart:325-328` | `Flex(crossAxisAlignment: CrossAxisAlignment.stretch)`（`:327`） |
| SectionBox | `room_panel_kit.dart:68-103` | `Card > Padding(10) > Column(crossAxisAlignment: stretch, mainAxisSize: MainAxisSize.min)`（`:75-77`）+ 标题行（`:79-97`）+ `SizedBox(height: 8)`（`:98`）+ `child`（`:99`）→ **Card 高 = 20(padding) + 标题行 + 8 + child 高**，不被格子拉伸 |
| 聊天栏 child | `gp_feeds.dart:343-358` | `Column`: `SizedBox(height: widget.height)`（`:347-348`，`height=220` `:121`）+ `if (pane == FeedPane.chat) const ChatInputRow()`（`:356`） |
| 记录栏 child | 同上 | 只有 `SizedBox(height: 220)`（无 `:356` 分支） |
| 只给你看 child | `gp_privates.dart:155-206` | `SizedBox(height: widget.height)`（`:179-180`，`height=220` `:59`） |
| ChatInputRow 高 | `gp_feeds.dart:764-821` | `Row`：单行 `TextField(isDense: true)` + 3 个 `RoomTap(minSize: RoomBtnSize.chatIcon)`（`:790`、`:809`、`:817`）→ 约 44–48dp |
| **差值** | — | 聊天 Card ≈ `20 + 标题(约20) + 8 + 220 + ChatInputRow(约48)` ≈ **316**；记录/私密 Card ≈ `20 + 20 + 8 + 220` ≈ **268**；**差 ≈ 一个 ChatInputRow（约 48dp）** |

**建议落点（最小、不动 dock 树）**
- ① 给 record/priv 补等高占位（在 `gp_feeds.dart:343-358` 的 `if (pane == FeedPane.chat)` 之外补一个 `SizedBox` 占位，或让 `GpPrivates`/`GpFeeds(record)` 的 `height` 默认改成 `220 + ChatInputRow 高`）——**但会打红 `test/p16_wave1_theme_test.dart:100-103`**（见下）。
- ② 更稳：三块统一在 `SectionBox.child` 用 `LayoutBuilder`/`Expanded` 吃满格高（参考 `gp_combat_list.dart:171-230` 的 `c.hasBoundedHeight ? Expanded(...) : column` 现成范式），不改任何 widget 的默认 `height`、不动 `room_panel_kit.dart` 共用件（P16 报告 §KP-5 明确不建议动）。
- ③ **不要改** `room_layout.dart:146-154` 的 flex（会被 `test/p10_t6_layout_test.dart:437` `gpChat=[83,46,1]` 钉死）。

**会撞到的既有测试**：`test/p16_wave1_theme_test.dart:100-103`（**`expect(const GpPrivates().height, 220)` 把 220 钉死**，改默认高度必红）、`:108+`（固定高度 textScaler 1.3/1.5/2.0）；`test/p10_t6_layout_test.dart:437`（`gpChat=[83,46,1]`）、`:480-486`、`:531-533`（`gpChat`/`gpPriv` Rect 落位）；`test/p10_t7_layout_test.dart:98-102`（底部三块等高）；`test/p10_t3_layout_test.dart:220-221`（`openSquare(gpChat/gpPriv)`）；`test/p16_button_unify_test.dart:244,761`（`GpPrivatesKeys.fullscreen` 热区）；`test/room_ui_feeds_test.dart`、`test/room_ui_gap_fill_test.dart`、`test/room_ui_wiring_test.dart`。

---

### KP-5 聊天栏全屏编辑发送无反应

**一行结论（经与 `researcher-bugs-p17` 交叉复核后修订）**：主因在 **`onSend` 闭包层** —— 全屏打开期间底层 `ChatInputRowState` 若因 `KeyedSubtree` key 含 `inGame` 换 key（`room_game_page.dart:335-336`）被销毁，闭包里 `_text.text = text`（`gp_feeds.dart:745`）对已 dispose 的 controller 赋值抛 used-after-dispose → `sheet_chat_composer.dart:127` 的 `onSend` 抛异常 → `:128` `Navigator.pop` 被跳过 → 全屏页不关、文字还在、chat intent 没发。本文初稿的「与 KP-1 barrier 共因」外推**不成立**（三条反证见 §KP-1 假设 B 修订）；**KP-1 与 KP-5 须分别裁定，不要合并修**。

**现状事实 / 可疑点（文件:行号）**
- `gp_feeds.dart` `ChatInputRow._send()`（`:717-724`）：`final scope = RoomScope.read(context)`（`:718`，`RoomScope.read` = `getInheritedWidgetOfExactType`，`room_scope.dart:44-48`）、`_text.text.trim()`（`:719`）、`scope.local.setChatDraft('')`（`:721`）、`_text.clear()`（`:722`）、`sendIntent(RoomIntent.chat, {'text': text})`（`:723`）。
- `_openComposer`（`:736-758`）：`onSend: (text) { _text.text = text; _text.selection = ...; _send(); }`（`:744-748`）；`await showChatComposer(...)` 返回后 `final String draft = result ?? local.chatDraft;`（`:754`）→ `_text.text = draft`（`:755`）→ `local.setChatDraft(draft)`（`:757`）。
- `sheet_chat_composer.dart`：`showChatComposer` 推 `MaterialPageRoute(fullscreenDialog: true)`（`:59-68`）；`bool _closed = false`（`:100`）；`_finish`（`:117-121`）与 `_send`（`:124-129`）**都先 `if (_closed) return; _closed = true;`**；`_send` 顺序 = `_closed=true`（`:126`）→ `widget.onSend(_draft.text)`（`:127`）→ `Navigator.of(context).pop<String>()`（`:128`）；「发送」按钮 `onTap: _send`（`:188`）。
- `room_ui_local.dart:194-196` `setChatDraft(String v) { chatDraft = v; }` —— **不调用 `notifyListeners()`**（其它 setter 如 `setMatesOpen` `:189-192` 都调）；`chatDraft` 字段 `:77`。

**可证伪假设（按当前置信度排序；与 `researcher-bugs-p17` §3.7 对齐）**
- **B2-1（首选主因，采纳自 `researcher-bugs-p17`）**：全屏 `MaterialPageRoute`（`sheet_chat_composer.dart:59-68`）打开期间，底层 `RoomGamePage` 因 session 通知重跑 build，`KeyedSubtree` 的 key = `RoomGamePage.pageKeyOf(role, inGame)`（`room_game_page.dart:336`，`inGame = isInGame(state)` `:303`）在 `meta.status` 翻转时换值 → 整棵子树重建 → `_ChatInputRowState` 被销毁、`_text`（`gp_feeds.dart:698`）已 dispose；而 `onSend: (text) { _text.text = text; ...; _send(); }`（`:744-748`）闭包仍持有旧 State → 赋值抛 used-after-dispose → `widget.onSend`（`sheet_chat_composer.dart:127`）抛 → `:128` `Navigator.pop` 跳过 → 弹窗不关、文字还在、**没发包**。`_closed`（`:100`、`:126`）已置 true → 再点发送/完成/关闭全被吞（`:118`、`:125`）。**同时解释「文字还在」与「没反应」**。
- **B2-2（次选）**：`ChatComposerPage` 的 `autofocus: true` + `expands: true`（`sheet_chat_composer.dart:156-158`）使底部「发送」Row（`:170-191`）在键盘弹起时落进键盘命中区或被推离可视区，点击落空。
- **H1 → 降级为 B2-1 的一句注解（保留但不单列独立假设；与 `researcher-bugs-p17` 静态复核一致）**：`onSend` 执行顺序语言级确定（`gp_feeds.dart:744-748`：`_text.text = text` ① → `_text.selection` ② → `_send()` ③），而 `RoomScope.read(context)` 在 `_send()` **内部**（`:718`）。若底层 `_ChatInputRowState` 已 dispose，其 controller 已在 `:711-715` `dispose()`，① 赋值先触发 disposed 断言 → ③ 根本轮不到，**H1 在 B2-1 场景下没有独立触发路径**；若 State 未 dispose，`ChatInputRow.build` 的 `RoomScope.of(context)`（`:762`）在 build 期已成功订阅，要让 `read` 失败只剩「祖先 RoomScope 被摘除、但 State 靠 key 存活」，与 B2-1 同类触发条件。且 `RoomScope.read` 是 `assert`（`room_scope.dart:45-47`），**release 包 assert 被裁**、`scope!` 退化成空解引用。→ **一句话：异常可能来自两个抛点、先后确定 —— 先 `_text.text`（disposed controller）、后 `RoomScope.read`（仅当 Scope 被摘除且 State 存活；release 下 assert 被裁变空解引用）；二者共用同一修复，不单列独立假设，施工单不为它多写一条动作**。
- **H2（保留）**：`_openComposer` 回填 `draft = result ?? local.chatDraft`（`gp_feeds.dart:754`）——`result` 为 null（发送/系统返回）时取 `chatDraft`；`setChatDraft` 不 notify（`:194-196`），若 `ChatComposerPage` 的 `onChanged`（`sheet_chat_composer.dart:166`）在 pop 之后还有一次写入把旧文本写回 `chatDraft`，`draft` 就会是旧文本 → `_text.text = draft`（`:755`）→ 「文字还在」（**此时 chat intent 其实已发出**）。**可证伪**：断言发送后 `session.sent` 有且仅有 1 条 `chat` 且 `gpChatInput.controller.text == ''`。
- **❌ barrier 共因（已排除，详见 §KP-1 假设 B 修订）**：`RoomRequestWatcher` 的 `showGeneralDialog` barrier 残留**不能**解释 KP-5 —— 用户能「点输入框 → 成功进全屏 → 编辑文字」，说明当时栈上没有 barrier；若编辑期间才弹新推送，dialog 会盖在 `ChatComposerPage` 之上，用户看到的是居中对话框而非「点发送没反应」。`_closed`（`:100,:125`）只在 `_finish/_send` 置位、首次点发送为 false，`researcher-bugs-p17` 已核过不是主因。

**交叉 / 裁定方式（务必写进施工单的验收用例）**：`test/p10_t7_c_feeds_test.dart:462-497` 是 **KP 视角**（`:464` `_host(f, kHostSeat, GpFeeds(pane: chat))`）的「⑥a 全屏发送」成功用例，断言 1 条 chat（`:483`）、trim 后文本（`:484-485`）、`chatDraft == ''`（`:486`）、全屏页关闭（`:487-488`）、原输入框清空（`:489-496`）；但 `_host` 是**最小 shell**，既无 `RoomRequestWatcher`、也不会重建 `KeyedSubtree`，**覆盖不到 B2-1**。
用**完整夹具**（完整 `RoomGamePage` + `RoomRequestWatcher` + dock，不是 `_host`）跑两变体：
  - **甲**：先弹一次推送并正常关闭，再走「点输入框 → 全屏 → 编辑 → 发送」；
  - **乙**：全屏打开后插入一次底层子树重建（触发 `KeyedSubtree` 换 key），再点发送；
  - **甲红乙绿 → KP-1 假设 B 共因成立；甲绿乙红 → B2-1 成立**（`researcher-bugs-p17` 判定后者）。
  **不得凭任一报告直接改布局/domain**，先跑这两条再动刀。
  - **⚠️ debug / release 限定（务必写进施工单）**：B2-1 在 widget test（**debug、assert 开启**）里会以 `A TextEditingController was used after being disposed` 稳定复现；但**真机 release 包 assert 被裁**，对已 dispose 的 controller 赋值是否仍抛、或改在别处抛，**必须真机另验**。→ ① **别把「debug 夹具复现」直接等同于「真机同因」**；② 正因抛点不确定，`try/finally` 保证 pop 是**不依赖具体抛点的无条件兜底，必须做**；③ 甲乙变体裁定在 debug 夹具里做，**真机再跑一轮**。

**建议落点（先跑甲乙裁定用例再动刀）**：① **`try/finally` 保证 `pop` 是无条件兜底、必须做**（不依赖具体抛点，见上 debug/release 限定）：`sheet_chat_composer.dart:124-129` 把 pop 放进 finally、`_closed` 只在真正 pop 前置位；`widget.onSend`（`:127`）用 try/catch 包住，异常时仍 pop 并回传错误（对应 `researcher-bugs-p17` §3.6 建议 2）。② `gp_feeds.dart:736-758` 的 `onSend` 闭包**不要持有 `_ChatInputRowState` 的 `_text`/`context`**：改为把「当前有效 controller」或 `RoomScope`/`RoomUiLocal` 在打开前捕获，`onSend` 只走 `controller.sendIntent(RoomIntent.chat, {'text': text})` + `setChatDraft('')`，不直接写已可能 dispose 的 `_text`；`await` 返回后（`:750-757`）用 `if (!mounted) return;` 守卫再回填。③ `gp_feeds.dart:750-757` 发送成功分支显式把 `_text`/`chatDraft` 清成空串而非依赖 `result ?? chatDraft`。④ **不要改** `TextField.onTap`（`:778`，`:728-731` 注释警告会弄崩既有输入用例），也不要为 KP-5 动 `room_request_watcher.dart` / dock 布局（除非甲变体复现为红）。

**会撞到的既有测试**：`test/p10_t7_c_feeds_test.dart:418-442`（「完成」保留草稿）、`:462-497`（全屏发送，见上）、`:500-520`（旁观者不渲染）、`:522-541`（`enterText` 不弹全屏）；`test/room_ui_feeds_test.dart:266-315`（既有输入用例）；`test/p10_t7_c_feeds_test.dart` 的 `chatComposer*` key 断言（`:423-427`、`:470-476`、`:487`、`:517`、`:535`）。

---

### KP-6 KP 定向指令（只能选目标、没有输入效果；删「暗骰」「请求修改状态」）

**一行结论**：弹层所有指令的载荷由 `kpDirectivePayload(op, seat)`（`sheet_kp_directives.dart:113-162`）**硬编码成常量**，UI 只有「选指令 → 选目标 → 执行」两步、**没有任何数值/文本/骰式输入框**；「暗骰」在 `kKpDirectives:44`（`dice.dark`）、「请求修改状态」在 `kKpExtraDirectives:76`（`state.request`）。

**所有按钮及当前载荷（文件:行号）**
| # | 按钮 / label | op | 定义行 | `kpDirectivePayload` 行 / 载荷 |
|---|---|---|---|---|
| 1 | 造成伤害 | `sheet.damage` | `:40` | `:115-116` `{seat, amount:1, kind:''}` |
| 2 | 临时状态 | `sheet.tempstatus` | `:41` | `:117-118` `{seat, text:'临时状态'}` |
| 3 | 给物品 | `sheet.item` | `:42` | `:119-125` `{seat, name:'物品', qty:1, note:''}` |
| 4 | SAN Check | `sheet.sancheck` | `:43` | `:126-132` `{seat, okLoss:'1D6', loss:'1D10', reason:''}` |
| 5 | **暗骰（删）** | `dice.dark` | **`:44`** | `:133-140` `{seat, sides:100, count:1, bonus:0, reason:''}` |
| 6 | 治愈疯狂状态 | `madness.cure` | `:47` | `:157-160` `{seat}` |
| 7 | 治愈重伤 | `sheet.healwound` | `:48` | `:157-160` `{seat}` |
| 8 | 急救/医学 | `aid.apply` | `:49` | `:143-148` `{seat, targetSeat:seat, skill:'医学'}` |
| 9 | SAN 大失败追加 | `sheet.sanloss` | `:50` | `:141-142` `{seat, dice:'1D10'}` |
| 10 | 精神分析 | `aid.psycho` | `:75` | `:149-150` `{seat, targetSeat:seat}` |
| 11 | **请求修改状态（删）** | `state.request` | **`:76`** | `:151-156` `{seat, change:{}, reason:'KP 请求修改状态'}` |

- 执行链：`_targetList`（`:224-265`）每行 `RoomTap(label:'执行', onTap: hostAction(_selectedOp, kpDirectivePayload(_selectedOp, seat)))`（`:250-259`）；`all = [...kKpDirectives, ...kKpExtraDirectives]`（`:186`）；标题「定向指令（9 项）」（`:193`）。
- 「需其同意」5 项 `kKpConsentOps`（`:59-65`）、`kpDirectiveNeedsConsent`（`:80`）、`kpDirectiveTargets`（`:101-110`）过滤撕卡/疯狂发作目标。

**domain 侧每个 action 的必填字段（施工单必须对齐）**
- 分派：`room_model_actions_sheet.dart:320-355`（case `state.request` `:328`、`sheet.damage` `:335`、`sheet.tempstatus` `:339`、`sheet.item` `:341`、`sheet.sanloss` `:343`、`aid.apply` `:349`、`aid.psycho` `:351`）；`dice.dark` 在 `room_model_actions_combat.dart:80-81`（→ `darkRoll`）。
- POLICY：`room_types.dart:258`（`state.request` `[kp]`）、`:290`（`dice.dark` `[kp]`）、`:291-294`（`sheet.damage`/`sancheck`/`tempstatus`/`item` `[kp]`）、`:306`（`sheet.sanloss` `[kp]`）、`:307-318`（`sheet.healwound`/`aid.apply`/`aid.psycho` `[player,kp]` + `RoomConfirm.kp`）。
- ⚠️ `dice.dark` 的 `RoomKeys.action` 锚点另在 `sheets/sheet_dice_tools.dart:226`，`state.request` 另在 `sheets/sheet_scene.dart:364` —— 删 directives 里这两个按钮**不会**让 T-30 锚点表少 op，但 `room_ui_permission_test.dart:358-487` 的 `enabled == gate.can(op)` 表驱动与 `:535-591` 结构式 `findsNothing` 需复核。

**「只能选目标没有输入效果」的具体缺口**：`kpDirectivePayload` 每个 case 都是编译期常量（`amount:1`、`text:'临时状态'`、`name:'物品'`、`sides:100`…），`_targetList` 无 `TextField`/`UnitPickerField`，用户无法输入伤害数值/物品名/骰式/状态文本。建议：在选指令后、目标列表前增加按 `op` 分支的动态表单（草稿存 `State`），把值合并进 `kpDirectivePayload` 的结果；`dice.dark`/`state.request` 两 case 随按钮删除一并从 `kKpDirectives`/`kKpExtraDirectives` 移除（`kpDirectivePayload` 里对应 case 可留可删，但 `kKpConsentOps` `:64` 含 `state.request` 需一并核对）。

**会撞到的既有测试**：`test/fixtures/room_actions.json:21,41,43,144-146,252-254,4125-4131,5073-5079,9101-9148,10669-10706`、`test/fixtures/room_model.json:69,95,160-162,238-240,1308-1322,1782-1796,2865-2909,4113-4133`（`dice.dark`/`state.request` 的 POLICY/apply/needs **逐字节契约，禁改**）；`test/room_ui_permission_test.dart:304-353`（T-30 锚点表 `table.length == 30`）、`:358-487`、`:535-591`；`test/room_ui_kp_test.dart`（定向指令弹层）；`test/p10_t4_synonym_request_done_test.dart:105-114,241-249`（`state.request` pending）；`test/room_ui_confirm_flow_test.dart`。

---

### KP-7 战斗信息栏行动顺序可自定义调整

**一行结论**：`combat.order` 由 `combatStart` 一次性按 `initiativeOrder`（敏捷/先攻）生成，运行时 `nextTurn()` 只推进 `turn` 游标并在整轮折返时自动 `_reorderTail`；**全库没有 KP 手动 reorder/插队 action 与 UI**，需新增。

**现状事实（文件:行号）**
- UI：`gp_combat_list.dart:67-235`；`rows = combatRows(state, isKp: isKp)`（`:89`）决定行顺序，`_CombatRowTile` 序号是 `${index+1}`（`:269`，index 来自 `:158` `itemBuilder`）；`GpCombatStrip`（`:135`）是纯展示条；「下一个行动 ▶」`hostAction('combat.next')`（`:192-201`）；「＋加入」`combat.enqueue {seat}`（`:205-217`）；`openCombatEnqueueSheet` 读 `state['combat']['order']`（`:325-327`）。
- `gp_combat_strip.dart`：文件头 `:17`「只画、不发意图」；`_slots`（`:98-119`）按 `rows` 顺序画固定宽 104 的槽（`:149`）；`GpCombatStripKeys.slot(id)`（`:37-38`）；**无任何拖拽/上下移/长按入口**。
- domain 生成：`room_model_actions_combat.dart:170-300` `combatStart` → `rules!.initiativeOrder(brief, {useReadyFirearm})`（`:230`），brief 含 `manualOrder`（`:227`），slot 带 `manual`/`manualOrder`/`movedToTail`（`:274-279`），最终 `'order': slots`（`:295`）。排序实现在 **`room_rules_combat.dart:24-94`（红线只读）**：有 `manualOrder` 的优先（`:58-63`），否则 `effDex`→`dex`→`name`（`:64-70`）。
- domain 运行时：`room_model_rollback.dart:432-492` `nextTurn()` 读 `c['turn']`（`:445`），线性 `next = i+1`（`:472`），整轮折返调 `_reorderTail(order)`（`:478`）并清 done/movedToTail（`:479-483`）——**唯一改 order 顺序的地方，且是自动的**。
- 可复用落点：`room_model_actions_combat.dart:29-32` 已有 `case 'combat.set'` → `emit(RoomEvt.combat, {'combat': p['combat']}, vis: public)`（直接整体写 combat 对象）；`room_types.dart:277` `'combat.set': [kp], null`（POLICY 已登记）；`:279` `combat.next`、`:281` `combat.enqueue` 同为 `[kp]`。
- 注意 `reduce` 侧 `RoomEvt.combat` 是**整体替换** `state['combat']`（`room_model_reduce.dart:153-155` `state['combat'] = jsTruthy(p['combat']) ? roomClone(p['combat']) : null`；`RoomEvt.turn` `:157-162` 才单独改 round/turn），改 order 后 `turn` 游标、`done`/`movedToTail` 需一并处理，否则 `nextTurn` 会跳错。

**建议落点**：① `gp_combat_list.dart`「顺序」tab 的行/条（`:154-166` / `gp_combat_strip.dart:98-119`）加 KP 专属「上移/下移」或拖拽（只在 `isKp` 渲染，符合 T-22 结构式权限）；② 发 `combat.set`（复用 `:29-32`）或新增 `combat.reorder {order/ids}` action（若新增需同步 `room_types.dart` POLICY —— 但 `kRoomPolicy.length == 61` 被 `test/room_ui_permission_test.dart:342` 钉死，**新增 action 会打红，优先复用 `combat.set`**）；③ 服务端需保证重排后 `turn` 指向正确槽；④ **绝不改 `room_rules_combat.dart` 的计算式**。

**会撞到的既有测试**：`test/p10_t7_c_combat_test.dart:249-297`（`combat.start` 载荷逐字段、`⚔️ 战斗部署完毕`）、`:280-286`（PC hp>0）；`test/p10_t2_tempcommit_test.dart:203,226`（`combat.next` 折返触发 TEMP_COMMIT）；`test/p10_t6_layout_test.dart`、`test/p10_t7_layout_test.dart`（dock/舞台几何）；`test/room_ui_blocks_test.dart`、`test/room_ui_wiring_test.dart`（槽位/接线 `findsOneWidget`）；`test/room_ui_permission_test.dart:342`（`kRoomPolicy.length == 61`）；`test/fixtures/room_actions.json:15,126-128,3760-3867,8540-8587`、`room_model.json:84,205-207,1582-1596,3585-3605`（`combat.next` 逐字节契约）；`test/combat_logic_test.dart`、`test/room_rules_oracle_test.dart`、`test/room_coverage_test.dart`（红线）。

---

### KP-8 音乐控制台按钮上移一级（从「更多工具」→「KP 工具」）

**一行结论**：音乐控制台现在在 **第二级**「更多工具」弹层（`MiscSheet`，`sheet_misc.dart:259-266`）；「上一级」= `KpPanel`（`sheet_kp_panel.dart:263`，由 `room_game_page.dart:1021-1028` 的「KP」按钮直接打开）。**只需改两处**。

**现状事实（文件:行号）**
- `sheets/sheet_misc.dart`：`import 'sheet_music.dart' show openMusicSheet`（`:34`）；`MiscSheetKeys.musicEntry = ValueKey('misc/music')`（`:56`）、`musicSection`（`:59`）；「本机工具」节（`:250-253`）；**音乐入口 `RoomTap`（`:259-266`）**：`key: MiscSheetKeys.musicEntry`（`:260`）、`label:'音乐控制台'`（`:262`）、`minSize: Size(120,40)`（`:264`）、`onTap: () => openMusicSheet(ctx)`（`:265`）；同 Wrap 里还有「导出游戏历史」（`:269-281`）。`openMiscSheet`（`:83-87`）标题「更多工具」。
- `sheets/sheet_kp_panel.dart`：`KpPanel`（`:263-399`）三组 + 房间管理，`showKpPanel`（`:421-430`）标题「KP 工具」；「工具 · 房间管理」组（`:348-396`）现有「存档槽」（`:354-360`）、「更多工具」（`:361-367`，`onTap: opener(context, 'misc')`）、「保存本局」（`:368-375`）、结束房间/结团（`:376-393`）；`kKpSheetIds`（`:132-141`）**只有 8 个 id，没有 `'music'`**；`openKpSheet`（`:149-194`）无 music case。
- 入口层级：`room_game_page.dart:1021-1028` 「KP」`RoomTap`（`kpPanelKey` `:235`）→ `showKpPanel<void>(context, onOpen: openKpSheet)`（`:1028`）→ `KpPanel`「更多工具」→ `openMiscSheet` → `MiscSheet`「音乐控制台」。

**建议落点（两处）**
1. `sheet_misc.dart`：删 `:259-266` 的 `RoomTap`（按 P16 惯例 `MiscSheetKeys.musicEntry`（`:56`）常量**保留**以兼容测试引用，参考 `aiEntry` `:64-70` 的做法）；`import`（`:34`）可留（无其他引用则删）。
2. `sheet_kp_panel.dart`：在 `KpPanel` 某组（建议「工具 · 房间管理」`:348-396`，或新建一组）加一个 `RoomTap(key: MiscSheetKeys.musicEntry, ...)` 并 `import 'sheet_music.dart' show openMusicSheet`，`onTap: () => openMusicSheet(context)`；若走 `opener` 则需把 `'music'` 加进 `kKpSheetIds`（`:132-141`）并补 `openKpSheet` case（`:149-194`）。

**会撞到的既有测试**：`test/room_ui_entry_test.dart:751-761`（**`find.byKey(MiscSheetKeys.musicEntry)` `findsOneWidget` + `enabled` + `onTap != null` + `hint` 含「本机」——删了必红**，需在 KpPanel 侧补同名 key 或同步改测试）；`test/p10_t5_music_synonym_layout_test.dart:390-396`（静态读 `sheet_misc.dart` 全文扫 `zoomRow`/`spacing: 3`/`Size(54, 34)`/缩放文案，删音乐块不影响这几条）；`test/sheet_music_test.dart`（音乐弹层本体）；`test/p16_wave1_sheets_test.dart`（MiscSheet 结构）；`test/room_ui_confirm_flow_test.dart:20,126-128,198`（`KpPanelKeys.pendingList`/`unread` 的 `findsNothing` 反向断言，新增按钮不影响但要复核）；`test/p16_button_unify_test.dart`（新增 `RoomTap` 热区/textScaler）。

---

## 3. 跨项重叠文件清单（施工单切批用，同文件必须串行，禁止多 worker 并发改）

| 文件 | 涉及项 | 冲突说明 |
|---|---|---|
| **`domain/room_model_actions_combat.dart`** | **KP-2 / KP-3 / KP-7** | 三项都要改：难度/Steps（`:1324`、`:1370-1374`、`:2700`、`:2821`）、`checkOpposed`/`opposed`（`:1538`、`:2440`）、`combatStart`/`combat.set`（`:29-32`、`:170-300`）。**domain 最热，建议单 worker 一次改完**。 |
| **`widgets/gp_feeds.dart`** | **KP-4 / KP-5** | 同文件：`:343-358`（高度/输入行）与 `:717-758`（全屏发送回调）。 |
| **`sheets/sheet_kp_panel.dart`** | **KP-3 / KP-8** | `:317-323`（对抗入口核对）与 `:348-396`（新增音乐按钮）、`:132-141`/`:149-194`（若加 music id）。 |
| `room_game_page.dart` | KP-1 / KP-3 / KP-8 | `:1050-1066`（治疗入口）、`:1021-1028`（KP 工具入口）、`:313-336`（watcher 挂载）三处同在 `build`/`_buildToolbar`。 |
| `room_request_watcher.dart` | KP-1（+ KP-5 疑似共因） | 若 KP-5 根因确认为 barrier 残留，两批须合并成一个「watcher 生命周期」修复。 |
| `domain/room_types.dart`（只读） | KP-3 / KP-6 / KP-7 | POLICY 表 `kRoomPolicy`（`kRoomPolicy.length == 61` 被 `test/room_ui_permission_test.dart:342` 钉死）：**三项都不要新增 action**，优先复用 `combat.set` / 现有 op。 |
| `sheets/sheet_scene.dart` + `widgets/gp_scene_check_kp.dart` | KP-2 | 同一弹层链路（编辑器 + 场景检定栏），一起改。 |
| `widgets/gp_combat_list.dart` + `gp_combat_strip.dart` | KP-7 | 顺序条与列表同源 `combatRows`，加交互要同批。 |
| `widgets/unit_picker.dart` | KP-3（只读依赖） | 现有契约（`:13` 前缀、`:253-259` `unitValueToSeat`）**不要为 KP-3 改动**，否则连带打红 `sheet_scene` 的 P16 用例。 |

**建议串行顺序**：① `room_request_watcher.dart` + `room_model_host_intent.dart:484-486`（**只做 KP-1**：去重键构造 / `_draining` 复位 / `confirmPending` 循环不 break；**不要顺手改 KP-5**）→ ② `sheets/sheet_scene.dart` + `gp_scene_check_kp.dart`（KP-2，弹层）→ ③ `sheets/sheet_opposed.dart` + `gp_dice_bar.dart`（KP-3 UI）→ ④ `sheets/sheet_kp_directives.dart`（KP-6）→ ⑤ `sheets/sheet_misc.dart` + `sheet_kp_panel.dart`（KP-8，且 KP-3 入口核对在同文件，合并）→ ⑥ **`gp_feeds.dart` + `sheet_chat_composer.dart`（KP-5，独立批次；先跑甲乙两变体完整夹具用例裁定主因，不与 ① 合并）** → ⑦ `gp_feeds.dart` + `gp_privates.dart`（KP-4，注意与 ⑥ 同文件需串行）→ ⑧ `gp_combat_list.dart` + `gp_combat_strip.dart`（KP-7 UI）→ ⑨ **domain 单批**：`room_model_actions_combat.dart`（KP-2/3/7）+ `room_model_actions_room.dart` + `room_rules.dart` → ⑩ 全量回归。

**并行与门禁补充（与 `researcher-bugs-p17` 排期复核一致）**：KP-1 落 `room_request_watcher.dart` + `room_model_host_intent.dart`，KP-5 落 `gp_feeds.dart` + `sheet_chat_composer.dart`，**两组文件不重叠、可并行**（分别裁定、各自内部串行即可）；`gp_feeds.dart` 仍被 KP-4/KP-5 先后占用须串行。唯一需单独门禁的是 **`room_model_host_intent.dart:484-486`（domain 冻结文件，P10/P16 反复对拍过）**——`confirmPending` 循环不 break 的改动**必须显式排一轮 QA 全量回归**（连锁残留风险见 §KP-1 假设 C 修正③），施工排期别漏这一轮。

---

## 4. 预计转红的既有测试清单（按风险排序）

| 测试文件 | 涉及项 | 高风险断言（精确行） |
|---|---|---|
| `test/p16_wave1_sheets_test.dart` | KP-1/2/3/4/5/6/8 | `:202-206`（`unitValueToSeat`）、`:290-318`（对抗两处 `UnitPickerField`）、`:320-352`（场景 4 处 + 静态源码扫）、`:420-471`（`check.opposed` 载荷 `reqId`/`attack`、闸门）、`:567-608`（`openTreatSheet` 三分支 `seat`/`targetSeat`/`skill`/无 `base`）。**KP-3 改载荷必红 `:442-445`**。 |
| `test/p10_t6_room_fixes_test.dart` | KP-1 | `:485-715`（`RoomPushKeys` 全套）、`:562`（**「5D 同一 id 只弹一次」= `_seen` 不去重红线，不许给它加 remove/清理**）、`:646-657`（跨视角裁剪 `findsNothing`）、`:677-719`（CONFIRM/CONSENT 两条数据源）、`:700-703`（屏障关闭）。 |
| `test/room_ui_permission_test.dart` | KP-2/3/6/7 | `:304-353`（T-30 锚点表 `table.length == 30`、`kRoomPolicy.length == 61` `:342`、`noAnchor == kFrozenNoAnchor` `:350`）、`:358-487`（`enabled == gate.can(op)`）、`:535-591`（结构式 `findsNothing`，删按钮会红）。 |
| `test/room_ui_entry_test.dart` | KP-8 | **`:751-761`**（`MiscSheetKeys.musicEntry` `findsOneWidget` + `onTap` 非空 + `hint` 含「本机」）——删音乐入口必红。 |
| `test/p16_wave1_theme_test.dart` | KP-4 | **`:100-103`**（`expect(const GpPrivates().height, 220)`）、`:108+`（textScaler 1.3/1.5/2.0）——改 `height` 默认值必红。 |
| `test/p10_t7_c_feeds_test.dart` | KP-5 | `:418-442`（「完成」保留草稿）、`:462-497`（KP 视角全屏发送：1 条 chat / 清草稿 / 关页 / 输入框清空）、`:500-520`（旁观者）、`:522-541`（`enterText` 不弹全屏）。 |
| `test/p10_t6_layout_test.dart` | KP-4/7 | `:437`（`gpChat == [83,46,1]`）、`:480-486`、`:531-533`（Rect 落位）、`:402-428`（DFS 顺序）、`:519-551`（`takeException`）。 |
| `test/p10_t7_layout_test.dart` | KP-4 | `:98-102`（底部三块等高）、`:390-433`（热区）。 |
| `test/p10_t7_c_combat_test.dart` | KP-7 | `:249-297`（`combat.start` 载荷逐字段）、`:280-286`（PC hp>0）。 |
| `test/p10_t2_tempcommit_test.dart` | KP-7 | `:203`、`:226`（`combat.next` 折返才触发 TEMP_COMMIT）。 |
| `test/room_ui_kp_test.dart` | KP-2/3/6 | `:963-979`（对抗弹层 `enabled == gate.can`）、`:1003-1006`（`SceneSheet.addStep`）、`:1116-1148`（11 个 T04 文件零命中源码门禁）。 |
| `test/room_ui_confirm_flow_test.dart` | KP-1/8 | `:126-128`、`:198`（`KpPanelKeys.pendingList`/`unread` `findsNothing`）。 |
| `test/room_ui_feeds_test.dart` / `room_ui_gap_fill_test.dart` / `room_ui_wiring_test.dart` / `room_ui_blocks_test.dart` | KP-4/5 | 各种 `findsOneWidget` / 输入行接线。 |
| `test/p10_t5_music_synonym_layout_test.dart` | KP-8 | `:390-396`（静态读 `sheet_misc.dart` 扫缩放区字面量）。 |
| `test/p16_button_unify_test.dart` | KP-3/4/6/8 | 按钮尺寸 / 热区 / textScaler（新增或删除 `RoomTap` 都要复核）；`:244`、`:761`（`GpPrivatesKeys.fullscreen`）。 |
| `test/p12_game_e2e_test.dart` | 全部 | `:68-172`（6 档屏幕点击 + `takeException() == null` 溢出总闸门）。 |
| **`test/fixtures/room_actions.json` / `room_model.json`** | 全部 | **逐字节契约，禁改**：`dice.dark`(`room_actions.json:21,43,144-146,4125,9101`)、`state.request`(`:41,252-254,5073,7775`)、`scene.check.push`(`room_model.json:105,268-270`)、`combat.next`(`:84`)、`aid.apply`(`room_actions.json:75-80,258`)、`check.opposed` 等。**任何 POLICY/载荷改动都不得碰这两份 fixture**。 |
| `test/oracle_*.dart` / `room_rules_oracle_test.dart` / `combat_logic_test.dart` | KP-3/7 | 规则逐字节契约，**红线只读**。 |

---

## 5. 未找到 / 需外部输入

| 项 | 结论 | 搜过的关键词 |
|---|---|---|
| 「检定方式」四个等级（KP-2） | **新 APP 未找到实现；老 APP 也没有**（`researcher-oldapp-p17` 全库 Grep `检定方式\|检定等级` 0 命中）→ **纯新需求，不是照抄老 APP，需主理人拍板定义四档语义**（结果 LEVEL 当 required，还是新造难度档；「大成功」档无对应难度）。现有 `kKpSceneLevels` 6 档是裁定结果 level（`gp_scene_check_kp.dart:38-45`），难度只有 `REGULAR/HARD/EXTREME` 三档（`room_model_actions_room.dart:426`）且 UI 全硬编码 `'REGULAR'`。**另必做：统一难度大小写**（老 APP 大写载荷 / 小写 domain 键会静默退化成常规）。 | `检定方式`、`difficulty`、`REGULAR`、`HARD`、`EXTREME`、`level`、`kSceneCheckLevels`、`四档`、`等级`、`raSanitizeSceneSteps`、`scene.check.push`、`check.request` |
| 「技能近义词反向解析」API（KP-3） | **✅ 初稿判断作废：新 APP 权威端已具备，无需新增**。`room_rules_sheet.dart:369-421` `_skillValue` 已实现老 APP 4 档归一（精确名 / `_skillAlias :297-314` 16 条别名 / 基名 / 子类名），链路 `checkOpposed :1549` → `resolveActorSkill :1634` → `skillBaseOf :1744` → `rules.skillValue`（`room_rules.dart:284`）已通。**只缺 UI 的 `aSkill`/`bSkill` 输入框与载荷字段**。老 APP `aSkill`/`bSkill` 也是纯文本框（`room-panels.js:4706-4707`），靠权威端归一取值，不是搜索/下拉。`skill_synonyms.dart` 是车卡搜索表（`id → 近义词`），**不要接进对抗取值**。 | `resolveActorSkill`、`skillBaseOf`、`skillValue`、`_skillValue`、`_skillAlias`、`normSkillName`、`SKILL_ALIAS`、`synonymsOf`、`subskillSynonymsOf` |
| KP 手动 reorder action（KP-7） | **未找到**。全库只有 `combat.start`（生成 order）、`combat.next`（推 turn）、`combat.enqueue`（追加）、`combat.set`（整体覆盖，`:29-32`）；无 `combat.reorder`/`order.move`/`insert`。 | `reorder`、`combat.order`、`manualOrder`、`initiativeOrder`、`movedToTail`、`combat.set`、`nextTurn` |
| `gp_toolbar.dart` 的对抗按钮（KP-3） | **未找到**（`gp_toolbar.dart:113-184` 只有缩放/下一轮/转战斗/扩展插槽）。对抗入口实际在 `gp_dice_bar.dart:356-362` 与 `sheet_kp_panel.dart:317-323`。 | `showOpposedSheet`、`opposed`、`对抗`、`check.opposed` |

---

## 6. 全局门禁复述（施工单带入）

- `lib/ui/room/**` 零 emoji（`⚔️` 等 BMP 允许）；**禁止新写 `jsStr(`**，展示文本统一 `roomText`（`lib/ui/room/room_text.dart`）。
- `skills.dart` / `occupations.dart` GENERATED 禁改；`oracle_*` / `fixtures/**` 逐字节契约禁改；`room_rules_combat.dart` 计算式禁改；**`room_rules_sheet.dart`（`_skillValue` 4 档归一 `:369-421`、`_skillAlias :297-314`、`_normSkillName :329-339`）与 `room_rules.dart:284` `skillValue` 适配器同属规则契约，KP-3 一律不许改**——技能别名取值靠现有链路，只补 UI。
- **KP-2 难度大小写统一是独立必做项**：统一 `sheet_scene.dart:87/:358`、`gp_scene_check_kp.dart:80`、`room_model_actions_room.dart:426`、`room_rules.dart:51-53` 的字面量，并补端到端用例验证 `HARD` ÷2 / `EXTREME` ÷5 真的生效（老 APP 因大小写不一致静默退化成常规）；不许靠改 `room_rules_combat.dart` 计算式绕过。
- KP 改动只落平板横屏 dock；`RoomGridSpec.of`（`view/room_view.dart:158`，class `:130`）档位判定、`RoomSlot`/`RoomKeys` 命名、`buildRoomLayout` 同一 `gap`（`room_layout.dart:293-331`）、DFS 槽位顺序（`roomLayoutSlotsOf` `room_layout.dart:205` / `roomLayoutFlexPathsOf` `:219`）均不许推翻。
- 测试不许放宽断言；新增/删除固定尺寸 `RoomTap` 须补 `textScaler` 1.3/1.5/2.0（`test/p16_button_unify_test.dart` 范本）。

---

*报告完 · 仅本文被写入，生产代码零改动。*
