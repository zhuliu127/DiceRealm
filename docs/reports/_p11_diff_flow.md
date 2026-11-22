# P11 · 流程与状态机差异盘点（diff-flow）

- 基准：老 APP `coc7th-card-app/android/app/src/main/assets/js/core/room-model.js`（2.13.13，7712 行）
- 对照：新工程 `dice-realm/lib/domain/`（`room_model_rollback.dart` / `room_model_reduce.dart` / `room_model_host_core.dart` / `room_model_state.dart` / `room_model_save.dart` / `madness_state.dart` / `room_model_log.dart` / `room_model_host_intent.dart` / `room_model_actions_room.dart` / `room_model_actions_combat.dart` / `room_model_actions_sheet.dart`）
- 范围：回合推进 / 时间系统 / 疯狂状态机 / 战斗生命周期 / 单位与座位 / 存档回滚 / 结团重置
- 已对齐、**本轮不重复盘**：D05 天/周恢复、D06 `madness.advance` 不触发天/周、D09 潜在疯狂复发武装（回合边界 disarm 已改 `isPotentialMadness()`）、`room.close`/`room.end` 需 `INTENT.CONFIRM`。
- 本文件**只做盘点，未改任何代码**。

---

## 差异清单

| 编号 | 差异点 | 老 APP（room-model.js:行号 + 关键代码） | 新工程（文件:行号 + 现状） | 判定 | 影响 | 建议 |
|---|---|---|---|---|---|---|
| F01 | 精神分析**失败**时，目标处于临时/不定疯狂是否还掉 SAN | `:5036-5041`<br>`var sanLoss = ...; out = stateApply(targetSeat, { status: { currentSAN: sanAfter } }, ...)`（无条件扣；`alreadyMad` 只挡「新增疯狂症」） | `room_model_actions_sheet.dart:1751-1763`<br>`final appliedLoss = targetMadActive ? 0 : sanLoss; if (appliedLoss > 0) { stateApply(...) }` | ❌ 不等价（**P1-口径待确认**，非缺陷） | 队友对我做精神分析失败，老版本扣 1D6 SAN；新版本一分不扣，只在日志写「本次不受 SAN 减损」。玩家会觉得「精神分析失败没有代价」，KP 也无法用它给疯狂中的角色施压。<br>⚠️ 但老 APP 2.13.13 **已有同向口径**，只是没覆盖精神分析：`:5499`（`sheetSanCheck`）与 `:5528`（`sheetSanLoss`）都拦 `memberMadActive(m)`（后者注释标 v2.5.0 需求）；新端 `:1102` / `:1439` 一一对应。故 P8 的「精神分析失败免减」是**既有方向的延伸**，不是新发明 | 倾向**保留**，只需产品签字 + 验收表写明「与 2.13.13 有意不同」；若产品否决，再回改 `psychoAnalyze`（`room_model_actions_sheet.dart:1750-1763`）恢复无条件 `stateApply`。<br>归属：diff-rules 已认领为 D-01，本表只登记不重复计票 |
| F02 | `_afterSanLoss` 在「临时/不定疯狂」期间是否整体早退 | `:5171-5172`、`:5160-5271`<br>无 madActive 早退；`:5198 if (loss >= 5 && !isFaded)` 仍会再走临时疯狂，`:5226+` 仍累计 `lossTotal` | `room_model_actions_sheet.dart:1210-1232`<br>`final madActive = blockedByMadness(mentalNow); if (madActive) { log('本次不获得新的疯狂症'); return; }`（连 ②累计 也跳过） | ❌ 不等价 | ① 老版本「临时疯狂中再遭 ≥5 点 SAN 损失 → 再抽一条症状」（`:5214 _addSymptom(m, symptom, '临时疯狂', ...)`）的叠加链消失，新版本疯狂期症状数会偏少；② 疯狂期损失不计入 `sanLostThisRound`，症状消退（→潜在）后本回合累计从 0 起算，复发门槛漂移。<br>⚠️ **「1/5 阈值公式本身两版一致」**：新 `:1281-1285` `ceil(maxSAN/5)` + `lossTotal >= oneFifth` ↔ 老 `:5242-5244` `Math.ceil(maxSanForIndef/5)` + `lossTotal >= oneFifth`。**差异只在「是否早退」，不是 D08「不定疯狂公式已对齐」被推翻** | 「不掉 SAN」这一 P8 口径建议只作用在**扣值层**（`settleSanCheck` / `stateApply` 入口），不要顺手在 `afterSanLoss` 早退；至少把 ② 累计与 ③ 判定恢复为老逻辑 |
| F03 | 跑团中发作的症状是否派生「疯狂症状」标签 | `:5143`<br>`if (mental.indexOf(MENTAL_SYMPTOM) < 0) mental.push(MENTAL_SYMPTOM);` | `room_model_actions_sheet.dart:1357-1362`<br>注释「P8（需求 7）：「疯狂症状」只标记**背景**疯狂表选中的症状」→ 不再 push | ❌ 不等价 | 老版本玩家疯一次，状态面板多一个「疯狂症状」chip；新版本只有背景症状才有该 chip。玩家/KP 少一个「这人有疯狂症」的可视抓手，且 `advanceMadness` 里 `md.isEmpty → 摘「疯狂症状」` 那行（`:1920-1922`）对新数据成了死代码 | 若确认为新产品口径，请在规格文档钉死并在 UI 侧给出替代标记；否则回改 `addSymptom`（`room_model_actions_sheet.dart:1326-1363`） |
| F04 | 「治愈不定疯狂」是否连带清掉「临时疯狂」 | `:5412-5415`<br>`mental = mental.filter(x => x !== MENTAL_INDEF && x !== MENTAL_INDEF_FADED);`（只摘不定，保留临时） | `room_model_actions_sheet.dart:1984-1988`<br>`nextMentalState(mental, MentalEvent.cured)` → 只保留 `永久疯狂`/`疯狂症状`，临时疯狂一并清 | ❌ 不等价 | 同时处于「临时疯狂 + 不定疯狂」的角色，新版本一次治愈申请直接回到「正常」；老版本只摘不定疯狂、临时疯狂仍要靠「推进 1 轮」倒计时。玩家会觉得治愈按钮变强了 | 口径问题，二选一即可；若要一致，改 `madness_state.dart:178-191` 的 `cured` 分支保留 `kMentalTemporary` |
| F05 | `stateSyncAck`（玩家回执「已写入本机卡」）记什么 | `:3967-3970`<br>`if (m) m.stateAckSeq = num(p && p.seq, 0); return [];` | `room_model_host_intent.dart:428-431`<br>`stateSeq += 1; return const <SendPlan>[];` | ❌ 不等价 | 老版本把回执水位写进成员的 `stateAckSeq`（KP 面板显示「该玩家已同步」）；新版本反而把**写回序号**加一 —— 成员级水位丢失，且 `save().stateSeq` 每次回执都前跳（审计值失真）。玩家端无感，KP 端「已同步」确认消失 | 改回 `m['stateAckSeq'] = p['seq']`，不要动 `stateSeq`（`room_model_host_intent.dart:428`） |
| F06 | 有人断线时是否作废进行中的回退表决 | `:1258-1265`<br>`out = out.concat(this.rollbackAbortIfVoting(seat));` | `room_model_host_core.dart:618-622`<br>只有 `markOffline` + `syncMembers()`；注释自认「T04 落 D15 后必须补」，但 D15 已落（`room_model_rollback.dart:245-262` 实现齐全）仍未接回 | ❌ 缺失 | 回退投票期间玩家掉线，表决不会作废 → 投票卡在 `VOTING` 永不出结果。（Q6 已把 `rollback.turn` 入口摘除，实际触发概率低） | `detachPeer` 里 `out.addAll(rollbackAbortIfVoting(seat))`（`room_model_host_core.dart:618`） |
| F07 | `room.close` / `room.end` 是否由 applyAction 真正执行 | `:174-175` POLICY 登记了 confirm:twice，但 `applyAction`（`:1702-1861`）**无对应分支**；实际关房靠 `room-net.js:1263 HostSide.closeRoom()` 直调 `host.closeRoom()` | `room_model_actions_room.dart:462-466`<br>`case 'room.close': return closeRoom(); case 'room.end'/'session.end': return endSession();` | ⚠️ 部分（新补齐老的空转） | 老 APP：KP 点两次确认的 `room.close` ACT 是空转（靠 UI 另一条路径才真关）；新工程同一条 ACT 会直接发 `CLOSED`/`ENDED` 并清 `pending`。若新 UI 仍保留传输层直调，会出现「关两次」/重复归档 | 保留新行为即可，但要确认 UI 只走一条路（`room_model_actions_room.dart:462-466` 或传输层，二选一） |
| F08 | 重伤「每周 CON 检定」是否注入自定义大成功/大失败阈值 | `:3727-3729`<br>`rules.check({ base: con\|\|50, difficulty:'regular', kind:'attribute', label:'重伤每周 CON 检定', rng })`（**不传** `ruleOptsOf`） | `room_model_rollback.dart:469-476`<br>`rules?.check({ ...ruleOptsOf(meta), base:..., label:'重伤每周 CON 检定', rng })` | ⚠️ 部分 | 默认 `critThreshold=1 / fumbleThreshold=100` 时 `ruleOptsOf` 只带出 `critMax=1`，与老等价；一旦 KP 把大成功阈值调到 >1，新版本「极难成功 → 2D3 + 清重伤」的触发概率变高，老版本不变。同一个团两版回血速度不同 | 与 `dyingRoundCheck` 口径统一：要么都传、要么都不传（`room_model_rollback.dart:469`） |
| F09 | 回退快照表的淘汰策略（深回退是否可用） | `:1024-1025`<br>`this.snapshots.push(...); if (this.snapshots.length > 20) this.snapshots.shift();`（会把 seq=0 建团基线一起裁掉） | `room_model_host_core.dart:235-241`<br>`while (snapshots.length > snapshotLimit && snapshots.length > 1) snapshots.removeAt(1);`（基线永留） | ⚠️ 部分（新修正老 bug） | 老 APP 快照打满 20 份后，`snapshots[0]` 已是「未来状态」→ `rollback()` 拿到 `seq > target` 的基准，权威态不退、`state.seq` 与 `log.seq` 分叉，二次回退直接 `StateError`。新工程已不会复现。**建议保留新实现** | 无需改；`room_model_rollback.dart:53-115` 的 `snap?.seq ?? 0` 兜底同样保留 |
| F10 | `adoptSave`（续玩）是否清空「本回合 SAN 累计」等 Host 侧临时容器 | `:6910-6953`<br>未触碰 `_sanLostThisRound` / `_roundStartSan` / `_fadedArm` / `_fireUsed` | `room_model_save.dart:164-167`<br>`sanLostThisRound.clear(); roundStartSan.clear(); fadedArm.clear(); fireUsed.clear();` | ⚠️ 部分（新修正老 bug） | 老 APP 在**同一个 Host 实例**上续玩时，上一局残留的「本回合累计损失」会让续玩后一次小额损失立刻触发不定疯狂；新工程不会。**建议保留新实现** | 无需改 |
| F11 | 回退后是否重算 `fadedArm` / `sanLostThisRound` / `fireUsed` / `entry roundStartSan` | `:3467-3471`<br>只 `this._rebuildRoundStarts();`，上述容器不动 | `room_model_rollback.dart:107-113`<br>`rebuildRoundStarts();`，上述容器同样不动（`_onRoundBoundary` 只在 `persist:true` 跑） | ✅ 等价（只登记·两版共同缺陷） | 回退掉一个 `ROUND` 事件后，被撤销那回合的 `fadedArm=false`（disarm）仍留在内存 → 玩家处在「潜在疯狂」却拿不到「任意 SAN 损失即复发」特权；重放期间清空的 `fireUsed` 也不会复原（连发惩罚骰计数错位） | P2 备忘：`rollback()` 末尾按重放后的 `roundStarts.last` 重算一次这三个容器即可 |
| F12 | `advanceRound` 四步顺序（硬契约） | `:3674-3688`<br>`emit(ROUND)` → `_onRoundBoundary()` → `_onDayWeekTick()` → `emit(TEMP_COMMIT)`（注释 `:3678-3680` 明确「TEMP_COMMIT 必须在 day/week 之后」） | `room_model_rollback.dart:384-393`<br>`emit(round)` → `onRoundBoundaryJudgments()` → `onDayWeekTick()` → `emit(tempCommit)` | ✅ 等价（只登记） | 顺序一致，不会出现「自动保存写了旧 HP（重伤每周回血前）」这类只在顺序错位时才出现的怪 bug。**这条是本轮最该盯死的契约，已对齐** | 无需改；建议加一条断言/单测把该顺序钉住（`room_model_rollback.dart:384`） |
| F13 | `ROUND` 事件的簿记（`roundStarts` / `fireUsed` / SAN 累计 / fadedArm disarm）放在哪 | `:979-1002`<br>`emit()` 的 `if (evt.t === EVT.ROUND)` 分支内；disarm 判据 `ment.indexOf(MENTAL_INDEF_FADED)`（上批已改 `isPotentialMadness`） | `room_model_host_core.dart:199-224`<br>`apply()` → `_onRoundBoundary(rec)`；`isPotentialMadness(mental)` 判据 | ✅ 等价（只登记） | 机制等价（唯一写口，`nextTurn`/`round.next` 两条路径都覆盖）；`persist:false`（回退重放）不重复计数，比老版本更干净 | 无需改 |
| F14 | 时间系统：1 回合 = 1 天、3 回合 = 1 周、回退后重新计时 | `:3705-3770`<br>`if (base == null \|\| base > round) { week[seat] = round; return; }`、`if (round - base < 3) return;` | `room_model_rollback.dart:436-530`<br>同判据同顺序（`:462-467`） | ✅ 等价（只登记） | 「基准晚于当前回合 → 重新计时」这一条在回退场景下两版都成立；`hpWeek` 随 `meta` 进快照/存档，回退后基准不会指向未来 | 无需改（注意 F08 的 `ruleOptsOf` 差异） |
| F15 | `nextTurn`：跳过已死槽 / `movedToTail` / 仅整轮折返才 `advanceRound` | `:3537-3609`<br>`else if (!s.done && !slotDown(s)) othersPending = true;`、`:3593 if (round !== prevRound)` | `room_model_rollback.dart:287-373`<br>`else if (!jsTruthy(s['done']) && !raSlotDown(s))`、`:349 if (round != prevRound)` | ✅ 等价（只登记） | 全员倒地时两版都发「没有可行动的单位了」并**不**推进回合（不会卡在尸体上死循环）；`roundChanged` 字段也一致 | 无需改 |
| F16 | 战斗生命周期：开战 → 先攻 → 结束 | `:2461-2560`（`combatStart`，`:2553 _stampAllPcSlots()` 在 emit COMBAT 之前）、`:2965-2972`（`combatEnd` 置 `mode=EXPLORATION` + `combat:null`）；**无 abort 分支** | `room_model_actions_combat.dart:165-288`（`:277 stampAllPcSlots()` 同样先于 emit）、`:757-770`；同样无 abort | ✅ 等价（只登记） | 入队即按 body 打 `down/state/hp`，战前已昏迷/濒死的 PC 不占行动轮；结束只清 `combat`、不复位 `meta.round`（两版一致） | 无需改 |
| F17 | 单位死亡后战斗槽如何处理（座位 / 占位） | `:3556-3558`、`:3586-3589`<br>槽位**不移除**，只靠 `slotDown(s)` 跳过；全员不可行动时提示「请结束战斗或添加新单位」 | `room_model_rollback.dart:315`、`:345-348`<br>同：槽位保留 + `raSlotDown` 跳过 | ✅ 等价（只登记） | 两版都有「死人不占轮、也不能被推进到」的行为；`combat.end` 后槽位整体丢弃。没有「尸体一直轮到他」的死锁 | 无需改 |
| F18 | 结团 / 关房时对成员表、战斗、座位的清理 | `:3407-3416`（`endSession`：只 `pending=[]`）、`:3507-3513`（`closeRoom`：只 `pending=[]`） | `room_model_rollback.dart:171-186`<br>`pending.clear()`，其余不动 | ✅ 等价（只登记·共同遗留） | 两版结团后 `roster` / `state.combat` / 各 seat 的 `requestsBySeat` 都保留 → 续玩同一房间号时会带着上一局的战斗槽与待办卡进来。**玩家侧可见症状：结团后重开仍是战斗模式、还挂着「待你确认」** | P2 建议（两版一起改）：`endSession` 追加 `combat=null` / `mode=EXPLORATION` / 逐 seat 清 `requestsBySeat` |
| F19 | 全局操作锁（撕卡 / 疯狂发作 / 昏迷 / 濒死）与白名单 | `:1344-1370`<br>`locked = memberRipped \|\| memberInBout \|\| _isUnconscious \|\| _isDying`；白名单含 `madness.advance` / `madness.cure` / `sheet.healwound` | `room_model_host_intent.dart:46-60`（`_memberLocked`）、`:88-103`（`_passSelf`） | ✅ 等价（只登记） | 锁定范围与三句分流提示逐字对齐；疯狂发作中的玩家仍能「推进 1 轮 / 申请治愈 / 申请治愈伤势」 | 无需改 |
| F20 | 非 KP 发 `combat.roll` 的处理 | POLICY `:217` 允许 `kp+player`，但 `applyAction`（`:1702-1861`）**无分支** → 静默无效果 | `room_model_actions_combat.dart:53-74`<br>非 host 走 `diceDirect` 用权威 rng 复算（丢掉客户端 `result`） | ⚠️ 部分（新增强） | 老 APP 玩家点「战斗掷骰」什么都不发生（也不报错）；新工程会真的掷一次并广播。可视为修 bug，但属于行为扩展 | 保留；若要严格对齐老口径，需产品确认（`room_model_actions_combat.dart:53`） |

---

## 优先级汇总

### P0（先改，会造成难查的状态不一致 / 规则错误）
> 本轮盘点结论：**没有发现新的 P0**。`advanceRound` 的四步顺序（F12）、ROUND 簿记（F13）、`1 回合=1 天 / 3 回合=1 周`（F14）这三条「顺序即契约」的关键链路两版一致，`room.start` 首回合故意不走 `advanceRound` 也一致。真正的 P0 风险集中在下一节 F09/F10 的两个老 bug —— **新工程已经修好，不要回退**。

### P1（规则口径分叉，玩家能直接看到）
1. **F01** 精神分析失败不再扣 SAN —— **P1-口径待确认，不是缺陷**：老 APP 已有 `:5499` / `:5528` 两处同向拦截，新端是延伸而非新发明；只需产品签字。归属 diff-rules（D-01）。
2. **F02** 疯狂期 `afterSanLoss` 整体早退 —— 连带改变了「多症叠加」与「本回合累计」的语义，属规则级分叉。
3. **F09 / F10** 是老 APP 的真 bug（深回退失效、续玩残留 SAN 累计），新工程已修 —— 列为 P1 是提醒**回移植时不要照抄老实现**。

### P2（语义细节 / 显示层 / 休眠功能）
- **F03**「疯狂症状」标签不再派生（口径变更，需产品确认）
- **F04** 治愈会连带清「临时疯狂」（口径变更，需产品确认）
- **F05** `stateSyncAck` 写错字段（成员水位丢 + `stateSeq` 虚增）
- **F06** `detachPeer` 漏 `rollbackAbortIfVoting`（Q6 休眠，触发概率低）
- **F07** `room.close` / `room.end` 由 ACT 真执行（需确认 UI 只走一条路）
- **F08** 重伤每周 CON 注入了自定义阈值（默认配置下等价）
- **F11** 回退不重算 `fadedArm` / SAN 累计 / `fireUsed`（**两版共同缺陷**，不是回退引入的）
- **F18** 结团不清 `combat` / 逐 seat 待办（**两版共同遗留**）
- **F20** 非 KP `combat.roll` 由空转变为真掷骰（增强）

---

## 最该先改的 3 条

1. **F02（`afterSanLoss` 早退）** —— 理由：它把一个「扣值口径」错误地实现在「症状判定」函数里，导致 `sanLostThisRound` 在疯狂期完全停止累计。表面看只是「不获得新症状」，实际会让「症状消退 → 潜在疯狂 → 复发」的整套链路在跨回合场景下阈值漂移，是典型「一回合后才显形」的难查 bug。**注意：1/5 公式本身没被动过（见 F02 行内说明），别误读成 D08 被推翻。**
2. **F05（`stateSyncAck` 写 `stateSeq += 1`）** —— 理由：这是**纯写错的实现**（老版本写 `m.stateAckSeq`），不是口径选择。它污染存档里的 `stateSeq` 审计值，同时让「KP 能看到该玩家已同步」这条反馈彻底消失；修起来是一行，越早改越不会有人基于错误的 `stateSeq` 语义写新逻辑。
3. **F06（`detachPeer` 漏 `rollbackAbortIfVoting`）** —— 理由：1 行可补（`rollbackAbortIfVoting` 在 D15 已实现齐全，只是没接回），不补的话「回退表决期间掉线」这条需求 §9 的规则在两版里只有老版本成立。

> **F01 已从「最该先改」移出**：归属 diff-rules（D-01），老 APP 已有同向拦截（`:5499` / `:5528`），判定降为 **P1-口径待确认（非缺陷）** —— 只需产品签字，不需改代码。
> F07 建议顺手确认（`room.close` / `room.end` 的 ACT 通路与传输层直调只留一条），避免以后排查关房问题时再回头翻。
