# P11 · 差异盘点 —— intent / action 层

范围：intent 分发、POLICY 登记、applyAction 分发、request/consent/check 请求系统、`_settleRequest`、越权处置。
老 APP 基准：`coc7th-card-app/android/app/src/main/assets/js/core/room-model.js`（7712 行，2.13.13/WebView）。
新工程：`dice-realm/lib/domain/`。

> 本文只做盘点，未改动任何代码。

---

## 一、集合差结果（先给结论）

| 维度 | 老 APP | 新工程 | 差集 |
|---|---|---|---|
| `INTENT` 枚举 | 13（`sync/ready/chat/dice/char/act/board/vote/consent/confirm/statesync/sancheck/opposed`，:106-124） | 13（`room_types.dart:190-221`） | **无差** |
| `POLICY` 登记键 | 61 个唯一 action（:164-262） | 61 个（`room_types.dart:242-311`） | **无差**（逐键比对，包括 `board.self` 重复定义、`rollback.turn` 已摘除） |
| `applyAction` 分发 op | 52 个分支（:1705-1861） | 67 个 `case`（room/combat/sheet 三个 dispatch） | **老有新无 0 个** |
| 反向（新有老无） | — | 15 个 | 见下 |

新有老无的 15 个，分两类，**都已在代码注释里说明来由，但需确认是否有副作用**：

1. **老「只登记、无处理器」的历史占位（7）**：`check.push` / `combat.roll` / `room.close` / `room.end` / `scene.reveal` / `state.edit.self` / `state.edit.other`
   → 老 POLICY 有键、`applyAction` 的 if/else 链里**没有任何分支**（实测这 11 个 op 在 ACTION 通道上是静默空操作，另 4 个由 `intent()` 的 INTENT 分支承接：`chat`/`ready.set`/`char.share`/`dice.request`）。新工程对这 7 个**都补了真实分支**，等于在这些点上是「新有老无」的行为增强；逐个定性见 A07–A11。
2. **非 POLICY 的内部别名（8）**：`chat` / `dice.request` / `ready.set` / `char.share` / `sancheck` / `opposed` / `dice.direct` / `state.apply`
   → 其中 **前 4 个 op 本身就在 POLICY 里**，因此可以经 `INTENT.ACT` 触达 —— 这里出现了两处**老 APP 没有的越权面**（A04 / A05）。

> 结论：**没有「老 APP 有、新工程整条缺失的 intent」**。真正的风险全部集中在「同名但语义/权限不等价」和「新加别名引入越权」这两类。

---

## 二、差异清单

| 编号 | 差异点 | 老 APP（room-model.js:行号 + 关键代码） | 新工程（文件:行号 + 现状） | 判定 | 影响 | 建议 |
|---|---|---|---|---|---|---|
| A01 | **consent 同意状态变更后不落账**（只摘卡、不写状态、不判死） | `:1569` `out = out.concat(this._settleRequest(seat, req.id, !!p.agree, null));` 之后 `:1589-1607` 组 `change={status:{currentHP/currentSAN/currentMP}}` → `stateApply(seat, change, {})` → `applyStatusJudgment(m, change, seat, {sanBefore, hpBefore, bodyBefore, flagsBefore})`；`:1612-1616` 日志带 `（理由）` | `room_model_host_intent.dart:376-400`：`settleRequest` → `syncMembers()` → 只发一条「KP 调整了…的状态」，**全文没有 stateApply / applyStatusJudgment**。等价实现 `room_model_actions_sheet.dart:365-392 sheetActionConsentApply` 有完整逻辑，但**全库零调用点**（只有 `:332` 的 `case 'state.apply'` 指向它，而 `state.apply` 从不是任何 intent 的 op）；且它读 `p['change']`，与请求里的 `payload={hp,san,mp}` 形状也不匹配 | ❌ 缺失 | **KP 请求给玩家扣 HP/SAN → 玩家点「同意」→ 血量和 SAN 一点没变**，也没有 `EVT.STATE` 回写角色卡；HP 打到 0 不会判濒死/死亡。玩家侧只看到一张消失的卡 + 一条「KP 调整了…的状态」日志（谎报） | 改 `room_model_host_intent.dart` 的 `consent()`：按老口径把 `req['payload']` 读成 `{hp,san,mp}`，依次调 `stateApply` + `applyStatusJudgment`（补 `sanBefore/hpBefore/bodyBefore/flagsBefore` 四参），日志补 `（reason）`。`sheetActionConsentApply` 的入参改为直接吃 payload，并在 consent 里调用 |
| A02 | **confirmPending 缺 TTL 过期闸门** | `:1626` `var CONFIRM_TTL_MS = 120000;` `:1643-1651` `var age = this.now() - num(task.at,0); if (age > CONFIRM_TTL_MS) { … '这条确认已放太久…已作废；请重新点一次操作' ; return out; }` | `room_model_host_intent.dart:404-425`：`pending.removeAt(idx)` 后**直接**判 `agree` 并 `applyAction`，全库无 TTL 常量（grep `TTL` 无命中） | ❌ 缺失 | 老 APP v2.13.6 修的就是这个坑：**KP 锁屏/页面重载后，几小时前排队的一条「结团 / 关房」被点一下就真执行了**，全桌被莫名结团 | 改 `confirmPending()`：`pending` 条目已存 `at`，补 `age > 120000` 即丢弃 + 回提示（与老文案一致） |
| A03 | confirmPending 的**匹配键与待办过滤**不同 | `:1636-1638` `if (!q.need) continue;` `if (id ? q.id === id : (q.op === (p && p.op)))`（优先 id；**跳过无 `need` 的待办**，如 `state.request` 的 owner/all 记账） | `:412-414` `if (pending[i]['op'] == op && pending[i]['by'] == p['by']) idx = i;`（只按 op+by，无 `need` 过滤，不支持 `id`） | ⚠️ 部分 | 同一 op 被不同玩家各排一条时，老按 id 精确命中，新按 op+by 区分（UI 恰好都传 `by`，暂不炸）；但 `state.request` 那条无 `p` 的记账待办可被 confirm 命中 → 删掉 pending 记账却 `applyAction(by, {})` 空跑，「待确认」永久消失而请求卡还在 | 同文件补 `need` 过滤（`if (q['need'] == null) continue;`）并支持 `id` 优先匹配 |
| A04 | **ACT 通道 `char.share` 别名可用 `p.seat` 改别人的角色名/卡 id（越权，新引入）** | `:1419` `case INTENT.CHAR:` 全程只用 `roster.get(seat)` 与 `mem.charName/charId`，**从不读 `p.seat`**；ACTION 通道**无 `char.share` 分支**（`:1705-1861` 无此 op）→ 伪造的 ACT `char.share` 是老 APP 的静默空操作 | `room_model_actions_room.dart:617-632`：`final target = cleanText(p['seat'],64).isNotEmpty ? p['seat'] : seat;` → 直接写 `mem['charName'] / mem['charId']`。`POLICY['char.share'].roles = ['player']`，所以**任意玩家**可发 `ACT{op:'char.share', seat:'别人', name:'X'}` | ❌ 不等价（老无此面） | 玩家 A 能把玩家 B 花名册上的**角色名改成任意内容**、把 B 的 `charId` 顶替（B 的「已准备」判定与绑卡对账随之错乱）。`syncMembers()` 全员广播，改完所有人可见 | 改 `room_model_actions_room.dart:617`：删掉 `p['seat']` 分支，强制 `target = seat`；或干脆让该 case 返回空（保持老行为，INTENT.CHAR 才是唯一入口） |
| A05 | ACT 通道 `ready.set` 别名可**替别人点准备**（越权，新引入） | `:1395` `case INTENT.READY:` 只改 `mem.ready`（`mem` 由 `seat` 查得）；ACTION 通道无 `ready.set` 分支 | `room_model_actions_room.dart:595-611`：`target = p['seat'] ?? seat` → 直接改 `mem['ready']`。`POLICY['ready.set'].roles = ['player']` | ⚠️ 部分（老无此面） | 玩家可把其他玩家置为「已准备 / 取消准备」，开团前的准备统计被篡改 | 同 A04：忽略 `p['seat']`，只用 `seat` |
| A06 | **`stateSyncAck` 记账错位**：老写成员字段，新却推全局状态序号 | `:3967-3972` `Host.prototype.stateSyncAck = function(seat,p){ var m=this.roster.get(seat); if(m) m.stateAckSeq = num(p&&p.seq,0); return []; }`（只记账、不占序号） | `room_model_host_intent.dart:428-431`：`stateSeq += 1; return const <SendPlan>[];` —— **没有写 `mem['stateAckSeq']`，反而推进了 `stateSeq`** | ❌ 不等价 | ① 成员表里永久缺 `stateAckSeq` 字段（重连/回执对账、成员键集合比对都会差一个键）；② `stateSeq` 是 `EVT.STATE` 幂等序号（`room_model_actions_sheet.dart:481-483`），被玩家每次回执无故顶高 | 改 `stateSyncAck`：`final m = roster.get(seat); if (m != null) m['stateAckSeq'] = jsNum(p['seq']);` 并删掉 `stateSeq += 1` |
| A07 | `check.push` 三层差异：POLICY 一致、分发层新增行为 | **POLICY** `:222` `'check.push': { roles:['kp'], confirm:null }`；**分发** `applyAction` 无该分支（`:1806 check.request` → `:1808 check.opposed` → `:1810 scene.check.push`，中间整条 if/else 落空）→ 静默空操作 | **POLICY** `room_types.dart:289` 只登记 `roles:['kp']` + `confirm:null`（一致）；**分发** `room_model_actions_combat.dart:92-93` `case 'check.push': return checkRequest(seat, p);` → 会真发 `EVT.REQUEST` 定向卡 + 公共 `check-req` 日志 | ✅ 等价（POLICY）+ 行为增强（分发） | 无线上症状（UI 零调用点）。仅当客户端伪造 `ACT{op:'check.push'}` 时，新会真发一次检定请求，老 APP 什么也不做 | 保持现状即可（比空操作有用、不改权限面）；若要绝对对齐老行为，改为 `return const <SendPlan>[];` |
| A08 | `combat.roll` 老无分支、新接权威复算 | `:217` 只登记；`applyAction` 无 `combat.roll` 分支 | `room_model_actions_combat.dart:53-74`：非 host 走 `diceDirect` 复算（丢弃客户端自报 `result`），host 走 `diceRoll` | ✅ 等价（且比老更安全） | 无。老此处是死分支，新补齐时已做防伪造加固 | 保持 |
| A09 | `room.close` / `room.end` 老只登记、由传输层直调；新让 ACT 直接生效 | `:174-175` 只登记；`applyAction` 无分支；真实入口是传输层调 `Host.prototype.closeRoom`（`:3507`）/ `endSession`（`:3407`） | `room_model_actions_room.dart:463` `case 'room.close': return closeRoom();`、`:465-466` `case 'room.end': case 'session.end': return endSession();`（实现见 `room_model_rollback.dart:171-186`，内部 `pending.clear()`） | ⚠️ 部分 | 功能上是增强（老 ACT 关房无效）。但**若 Flutter 侧传输/控制器仍保留「自己的关房入口」**，会出现 `EVT.CLOSED` / `EVT.ENDED` 双发、`meta.status` 被写两次（客户端看到两条系统播报） | 落实单一入口：确认 `RoomController.dangerAction('room.close')` 之外没有第二条调用 `closeRoom()` 的路径 |
| A10 | `scene.reveal` 语义偏移 | `:177` 只登记、无处理器 | `room_model_actions_room.dart:480-481` `case 'scene.reveal': return revealAsset(p['id'], p['revealed'] != false);` | ⚠️ 部分 | 若 KP 端发的是「揭示场景图」而非「揭示某个素材 id」，`p['id']` 缺失 → `revealAsset` 空转，KP 点「揭示」没反应；若误传 id，会连带把某个素材一起公开（信息泄露风险低但语义错） | 与 UI 对齐：要么改为只改 `scene.image` 的揭示位，要么删掉该 case 让 UI 统一走 `asset.reveal` |
| A11 | `state.edit.self` / `state.edit.other` 老只登记、新接真实处理器 | `:170-171` 只登记；`applyAction` 无分支（真实入口是 `state.self`（免确认）/ `state.request`） | `room_model_actions_sheet.dart:324-329` → `stateSelf(seat,p)` / `stateRequest(seat,p)` | ✅ 等价（只登记） | 无：两者 `confirm` 都非空（`kp` / `owner`），经 `act()` 会被压进 `pending` 等确认，不会绕过权限 | 保持；`state.edit.other` 的 `'owner'` 通道在老/新都无人消费（历史死路），可后续清理 |
| A12 | 全局操作锁 + 白名单三句分流 | `:1344-1369`：`locked = !isHost && mem && (memberRipped ‖ memberInBout ‖ _isUnconscious ‖ _isDying)`；`passSelf` 白名单 = chat/sync/ready/statesync/char + `madness.advance`/`madness.cure`/`sheet.healwound`；三句分流（撕卡 / 昏迷濒死 / 疯狂发作） | `room_model_host_intent.dart:46-103`：`_memberLocked` 判据、`_passSelf` 白名单、`_lockedHint` 三句分流，逐条一致 | ✅ 等价 | — | — |
| A13 | `_act` 权限闸门 / 越权回执 / KP 自确认直通 / pending 去重 | `:1662-1699`：`needs()` 不通过 → `_sysTo('你没有权限执行该操作')`；`confirm==='kp' && seat===HOST_SEAT` → 直接 `applyAction`；`JSON.stringify(p)` 去重 | `room_model_host_intent.dart:267-322`：同结构，`jsonEncode(p)` 去重 | ✅ 等价 | — | — |
| A14 | 请求系统全生命周期（建卡/摘卡/记账/`EVT.REQUEST done`） | `stateRequest` :3161-3178（`rec.op='state.apply'`、`pending.push({id,kind})`、SEAT 定向 REQUEST）；`checkRequest` :3186-3240（同 id 多目标、跳过撕卡目标）；`_settleRequest` :3138-3151（摘 `requestsBySeat` + `pending.filter(id)` + `EVT.REQUEST{self,done:true}` SEAT + 可选 verb）；reduce `:738-750`；`syncFor` 映射 `:1303-1312`（`payload`→`p`） | `room_model_actions_sheet.dart:658-700`；`room_model_actions_combat.dart:1027-1092`；`settleRequest` :1002-1025；`room_model_reduce.dart:309-328`；`room_model_host_core.dart:559-570 _requestsView` | ✅ 等价 | — | — |
| A15 | `rollback.turn` 已摘 POLICY、分支休眠保留 | `:231-239` 注释 + 无 POLICY 键 | `room_types.dart:240` 注释；`room_model_actions_room.dart:539-541` `case 'rollback.turn'` 保留但 `needs()` 默认拒绝 | ✅ 等价 | — | — |
| A16 | confirmPending 的**三条回执文案**与老不同 | `:1653` `'没有需要确认的操作'`；`:1659` `'已取消该操作'`；`:1631` `'只有房主能确认高危操作'` | `:416` `'这条待办已经处理过了'`；`:421` `sys('KP 拒绝了待确认操作：$op')`（公共流，非定向）；`:407` `'你没有权限执行该操作'` | ⚠️ 部分 | 文案不一致，且 `:421` 用 `sys()`（**PUBLIC**）而非 `sysTo()`，一条「KP 拒绝了…」会全员可见（老只回 KP 一人） | 改 `:421` 为 `sysTo(seat, '已取消该操作')`；其余两条文案对齐老 |

---

## 三、已验证「不需重复盘」的部分

- `consent → check.request` 同意路径（`_rollCheckRequest` 权威代掷）：`host_intent.dart:351-362` ↔ `room-model.js:1552-1566`，含 `sk` 兜底与 verb 文案，一致。
- 非 `check.request` 的请求改走 `settleRequest`：`host_intent.dart:376-378` ↔ `room-model.js:1569`，一致（但落账缺失，见 A01）。
- `check.push` 三层表述（与 `_p11_diff_rules.md` §3.1 一致）：**POLICY 层**老 `:222` ↔ 新 `room_types.dart:289`，都只登记 `roles:['kp']` + `confirm:null`；**分发层**老 `applyAction` 无该分支（`:1806 check.request` → `:1808 check.opposed` → `:1810 scene.check.push`，中间跳过）、静默空操作，新 `combat.dart:92-93` 接到 `checkRequest` → 行为增强（UI 零调用点）；**判定** ✅ 等价 + 行为增强，不算缺失。
- POLICY 表 61 键逐键一致（含 `board.self` 重复定义、`rollback.turn` 摘除）。

---

## 四、优先级汇总

### P0（影响对局正确性）

1. **A01** `consent` 同意后不落账 —— KP 批准的 HP/SAN/MP 变更完全不生效、不判死。这是本层唯一「功能级断路」。
2. **A02** `confirmPending` 无 TTL —— 迟到确认会执行不可逆操作（结团/关房），老 APP 专门修过。

### P1（影响体验 / 权限面）

3. **A04** ACT `char.share` 别名可改他人角色名 / 卡 id（老 APP 无此面）。
4. **A05** ACT `ready.set` 别名可替他人点准备（老 APP 无此面）。
5. **A03** `confirmPending` 不按 `id` 匹配、不过滤无 `need` 的待办 → 可能确认错条 / 令 `state.request` 记账永久丢失。
6. **A06** `stateSyncAck` 把回执写到了 `stateSeq`，成员表丢 `stateAckSeq`。

### P2（技术债 / 文案 / 语义）

7. **A16** confirm 三条回执文案不一致，且拒绝提示误用 PUBLIC。
8. **A09** `room.close` / `room.end` 双入口需确认。
9. **A10** `scene.reveal` 语义偏移。
10. **A07 / A08 / A11 / A15** 历史占位与休眠项，保持现状即可（需保留注释说明「老 APP 也无行为」）。

---

## 五、最该先改的 3 条

1. `room_model_host_intent.dart:376-400 consent()` —— 接回 `stateApply` + `applyStatusJudgment`（A01）。**不改这一条，KP 的「请求改状态」功能等于没做。**
2. `room_model_host_intent.dart:404-425 confirmPending()` —— 补 120s TTL 闸门（A02）。**不改这一条，锁屏回来会误结团。**
3. `room_model_actions_room.dart:595-632` 的 `roomActionReady` / `roomActionCharShare` —— 强制 `target = seat`，堵掉两条新引入的越权（A04/A05）。**改动量最小、风险收益比最高。**
