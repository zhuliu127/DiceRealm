# P11 · CoC 7e「花幸运」与「推动检定」接线报告

- 工程：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
- 结论：**IS_PASS**
- `flutter analyze`：**No issues found**
- `flutter test`：**1987 → 2006 全绿**（+19，本批新增 `test/p11_luck_push_test.dart`，既有 1987 组一个未改）

---

## 0. 一句话结论

规则层（`spendLuck` / `canPush` / `luckAllowed`）本来就写对了，问题是**没有调用方**。
本批把它们接上了「权威端处理器 + 玩家端按钮」，并把「算出来却没送出去」的
`canPush` / `canSpendLuck` 一并落进协议。**没有新增 RoomEvt、没有新增 POLICY action、
没有改任何 fixture、没有改任何既有断言、没有改 `lib/ui/room` 的布局结构。**

---

## 1. 15 个函数的审计分类（grep 证据）

审计口径：`lib/` 里除「门面定义行」与「`_私有实现` 自身定义行」以外的引用才算调用方。
`test/` 侧只有 oracle / 覆盖矩阵在打 tag，不算业务调用。

| # | 函数（公开门面） | 私有实现 | 分类 | 证据（`grep -rn` 结果，已剔除门面自身与私有定义） |
|---|---|---|---|---|
| 1 | `spendLuck` | `_spendLuck` | **真死代码 → 本批接线** | 改动前：`lib/domain/room_rules.dart:161` 是唯一命中。改动后：`room_model_actions_combat.dart:1131 rulesRef.spendLuck(...)`、`room_ports.dart:91`（端口） |
| 2 | `canPush` | `_canPush` | **半接线 → 本批接线** | `room_rules_core.dart:305/307`：`_check` 算了 `result['canPush']`，但 `diceRoll` 只落 total/level/levelText/label，**这个布尔从未离开权威端**（玩家端拿不到）。改动后 `room_model_actions_combat.dart:1223` 直接调用 |
| 3 | `luckAllowed` | `_luckAllowed` | **内部已用** | `room_rules_core.dart:306`（`_check` 算 `canSpendLuck`）、`:383`（`_spendLuck` 内部校验）。门面 `room_rules.dart:160` 零外部调用 → 已接线，不重复暴露 |
| 4 | `insanityFlags` | `_insanityFlags` | **真死代码（不接）** | 只有 `room_rules.dart:243`。宿主侧疯狂流程走 `madness` 端口 + `temporaryInsanityCheck`（`room_model_actions_sheet.dart:1259`），症状持续轮数取自 `symptom['rounds']`（`:1276`）→ 已有等价实现，玩家无感知，**画蛇添足不加按钮** |
| 5 | `boutRounds` | `_boutRounds` | **真死代码（不接）** | 只有 `room_rules.dart:259`。同上：发作轮数由疯狂表端口给出，宿主不调用它 |
| 6 | `advanceTurn` | `_advanceTurn` | **真死代码（不接）** | 只有 `room_rules.dart:269`。战斗轮转由 `RoomHost.nextTurn()`（`room_model_actions_combat.dart`）自己算，规则层这份从未被调用 |
| 7 | `sceneStepPlan` | `_sceneStepPlan` | **内部已用** | `room_rules_sheet.dart:508`（`sceneStepResolve` 内部） |
| 8 | `maxOfExpr` | `_maxOfExpr` | **内部已用** | `room_rules_expr.dart:203`（`parseExpr`）、`:215`（`burstMaxOf`） |
| 9 | `thresholds` | `_thresholds` | **内部已用** | `room_rules_core.dart:68`（`_targetOf`）、`:123`（`_levelOf`）、`:251`（`_check`） |
| 10 | `levelOf` | `_levelOf` | **内部已用** | `room_rules_core.dart:262`（`_check`）、`:407`（`_spendLuck`） |
| 11 | `fumbleRange` | `_fumbleRange` | **内部已用** | `room_rules_core.dart:107`（`_isFumble`）、`:298`（`_check` 写进结果） |
| 12 | `isFumble` | `_isFumble` | **内部已用** | `room_rules_core.dart:126`（`_levelOf`） |
| 13 | `combine` | `_combine` | **内部已用** | `room_rules_core.dart:173`（`_rollD100` 的十位/个位合成） |
| 14 | `describeCheck` | `_describeCheck` | **内部已用** | `room_rules_core.dart:312`（`_check` 写 `result['summary']`） |
| 15 | `damageFlags` | `_damageFlags` | **内部已用** | `room_rules_combat.dart:281`（攻击结算）、`room_rules_sheet.dart:153`（`damageFlags` 门面实现转发） |

**汇总：真死代码 4 个**（`spendLuck` / `insanityFlags` / `boutRounds` / `advanceTurn`）、
**半接线 1 个**（`canPush`：算出来但送不出去）、**内部已用 10 个**。

其中只有 `spendLuck` 与 `canPush` 属于「玩家应该有感知」：
所以**只给这两个做 UI**，其余 3 个真死代码在报告里登记「已有等价实现 / 玩家无感知」，不加按钮。

---

## 2. 三层改动清单

### 2.1 协议层

> ⚠️ **与派单有一处刻意偏离，请看 §4。** 没有往 `kRoomPolicy` 加 `check.luck` / `check.repush`。

| 位置 | 改动 |
|---|---|
| `lib/domain/room_ports.dart:85-94` | 端口新增 `spendLuck(Map?)` 与 `canPush(Map?, [Object?])`（签名逐字照抄 53 导出的可空口径）。原端口只暴露宿主用得到的 22 个成员，这两个此前不在里面，所以宿主**根本调不到规则** |
| `lib/domain/room_rules.dart:155-164` | 给 `canPush` / `spendLuck` 补 `@override`（唯一改动，实现一字未动） |
| `lib/domain/room_model_reduce.dart:113-146`（新增键在 127-141） | `EVT.DICE` 归约分支新增 11 个**可选键**：`kind/base/target/difficulty/required/critMax/fumbleMin/pushed/luckSpent/luckFrom/pushFrom`。全部 `if (p.containsKey(...))` 才落 —— 不带这些键的骰记录（快捷骰、暗骰、旧回放）**键集与形状逐字节不变** |
| `lib/domain/room_model_actions_combat.dart` `diceRoll` | 检定结果（`rules.check()` 产物）把上面这些键一起广播出去；`checkMeta: false` 的调用方保持旧形状（见 §4.2） |
| `lib/domain/room_model_host_intent.dart` `case RoomIntent.dice` | 分流 `{luck:true, amount:N}` → `checkLuck`，`{push:true}` → `checkRepush`。**两个都是既有 DICE 通道的载荷变体，不新增 intent、不新增 action** |

### 2.2 规则/处理器层（`lib/domain/room_model_actions_combat.dart`）

新增 4 个成员（放在 `rollCheckRequest` 之后，与检定族同处）：

| 成员 | 职责 |
|---|---|
| `lastDiceOf(seat)` | 取该座位**最近一条**公共骰记录。刻意不「往前找更早的检定」：最近一次掷的是 3D6 伤害骰，说明前面那条检定已经翻篇，不能再回头改 |
| `checkArgsOf(rec)` | 把 `state.dice` 记录还原成规则层吃的 `result`。**关键**：`_spendLuck`/`_canPush` 判的是 `bool`，而 state 里存的是 `levelKey` 字符串；`jsTruthy('fail')` 为真，直接喂字符串会把「失败」当成「大失败」——所以这里显式翻译 |
| `levelKeyOfLevel(int)` | 走注入端口的 `levelMap` 反查协议 key，不在宿主里硬编码第二份常量表 |
| `checkLuck(seat, p)` | ① 只认自己（KP / 旁观者拒绝）② 调 `spendLuck`（含余额校验，`luckAvailable` 直接传 `status.currentLuck`）③ `ok=false` → `sysTo` 私有提示，**零状态变更** ④ `ok=true` → `stateApply` 扣 `currentLuck`（不低于 0）+ 新增一条 `EVT.DICE`（新骰值/新等级/`luckSpent`/`luckFrom`）+ 公共播报「X 花 N 点幸运（侦查）：32 → 20（常规成功，剩 8 点）」 |
| `checkRepush(seat, p)` | ① 只认自己 ② `canPush` 判死（战斗/理智/对抗/大失败/已成功）③ `pushed` 标记防二次推动 ④ 同 base 同 difficulty 重掷 ⑤ 新记录带 `pushed:true` / `pushFrom` ⑥ 广播「X 推动了「侦查」检定：1D100 → 75，失败（推动失败，后果加重）」——**只提示，不施加任何后果** |

设计要点：
- **不改写历史记录，而是追加一条修正记录。** `state` 只能经 `reduceRoomState` 改，就地改会让「回退重放」还原不出修正；
  追加一条 `EVT.DICE` 则回退/重放/全量同步三条路都自然正确，且记录栏能看到「原 32 → 现 20」的完整轨迹。
- 「未结算」的判据 = **该座位最近一条骰记录且带 `target`**。这是已有数据（`state.dice`，`_rCap(200)`）上能给出的
  唯一可跨设备一致的解释，没有新造状态存储。

### 2.3 UI 层

| 位置 | 改动 |
|---|---|
| `lib/ui/room/view/feed_view.dart` | 新增 `FeedCheckAction`（值对象）+ `checkActionOf(...)`（纯函数，与权威端同口径）+ `selfLuckOf(state, seat)`；`diceLine` 追加两个后缀：`（花 N 点幸运）` / `（推动重掷，原 75）` |
| `lib/ui/room/widgets/gp_feeds.dart` | `GpFeeds` 计算 `seq → 动作区` 的 map；`FeedList` / `FeedRow` 各加一个**可选**参数 `actions` / `trailing`（默认空 = 行为与改前完全一致）；新增 key `GpFeedsKeys.luck(seq)` / `GpFeedsKeys.push(seq)` |

---

## 3. 按钮放在哪里，有没有挤压现有布局

**位置：记录栏里「我自己最近一条失败检定」的骰行下面，另起一行。**

```
[骰] 甲：侦查：1D100 → 32 · 失败
     [花 12 点幸运改为成功]  [推动检定（重掷一次）]
```

- **为什么选这里**：玩家看检定结果的唯一入口就是记录栏骰行（`state.dice` → `collectFeeds` → `FeedRow`）。
  角色卡没有「技能列表可点掷」的入口，也没有独立的检定结果面板，所以这是唯一「玩家能看到自己检定结果」的地方。
- **怎么做到不挤压**：`FeedRow` 原来是一行 `Padding(Row(头像, 图标, Expanded(RichText)))`。
  有动作时，我只把这一行**整体**塞进 `Column` 的**第一个 child**，动作区作为第二个 child 另起一行，
  左缩进 22/26px 与正文左缘对齐。**原 Row 的槽位、flex、尺寸、顺序、`Expanded` 一分未动**，
  文字宽度完全不受影响（记录栏那一行「谁·什么技能·掷了多少·什么等级」是最该读全的）。
- **代价**：被操作的那**一行**会高约 34px（`minSize: 132×30` + 4px 间距）。除此之外零影响：
  不可操作时 `trailing == null`，`FeedRow` 直接 `return row`，**渲染树与改前逐节点相同**。
- **只渲染一条**：只有「该座位最近一条骰」才可能带按钮（与权威端 `lastDiceOf` 同一判据），
  历史行永远不会长出按钮，不会出现「一屏十几个按钮」。
- 全屏记录弹层（`showRoomSheet` 里的 `FeedList`）不传 `actions` → 那边一个按钮都没有（只读视图，行为不变）。
- 旁观者 / KP 视角：`role != player` 直接返回 null，不渲染。

---

## 4. 两处必须交代的偏离

### 4.1 没有新增 POLICY action（派单要求加 `check.luck` / `check.repush`）

`kRoomPolicy` 的 61 条被**fixture 覆盖矩阵**逐项锁死：
`test/fixtures/room_model.json` 里有 `P:<action>` / `N:<action>:<role>` 的 tag 计数，
同时 5 个用例断言 `kRoomPolicy.length == 61`
（`qa_p4_b1_visibility_test.dart:190`、`room_actions_test.dart:194/211/229`、`room_coverage_test.dart:112/120`、
`room_intent_dark_dice_privacy_test.dart:364`、`room_intent_dice_wiring_test.dart:445`）。

加一条 action 就必须改 `room_model.json`（fixture）+ 改这 5 条断言 —— 这与
「**不动任何 fixture**、**不放宽任何断言**」直接冲突，且派单明确要求「打穿既有用例就停下来报告」。

**采用的替代方案**：走 `RoomIntent.dice` 通道的两个载荷变体 `{luck:true}` / `{push:true}`。
理由不是绕过检查，而是它本来就在同一语义域：
- 13 个意图通道（含 `dice`）**本来就不经 `needs()`**（`room_model_host_intent.dart` 的既有注释：「旧版 Host.intent 只有 INTENT.ACT 走权限链」）；
- 两个动作只作用于**自己**最近一条记录，处理器里按 seat 自校验（KP/旁观者一律拒绝），越权面为零；
- 权限面仍恰好 61 条、事件面仍恰好 27 项 —— 协议**没有扩张**。
- 这是**唯一**能让「加按钮」与「不动 fixture」同时成立的路。若要严格按派单加 POLICY 键，
  代价是改 1 个 fixture + 5 条断言，需要 team-lead 裁决。

### 4.2 `combat.roll` 不落检定附加信息（`checkMeta: false`）

`room_combat_roll_authority_test.dart` 的 F4 回归用例 ①里有一句

```dart
// 记录键集合完全不变（reduce 的 dice 分支未被改动）。
expect(rec.keys.toSet(), <String>{'seq','seat','nickname','expr','rolls','total','level','levelText','label','at'});
```

这是**既有断言**，本批不许改。所以 `dispatchCombatAction` 的 `combat.roll → diceDirect` 这一条路
显式传 `checkMeta: false`：记录的键集与改前完全一致，也就不提供花幸运/推动。
这在规则上也站得住：**战斗检定按规则书不可推动**（`_pushable['combat'] = false`），
本批把「花幸运」限定在技能/属性/特征检定通道，战斗结果仍由 KP 裁定。
（`diceDirect` / `rollCheckRequest` / SAN 检定等其余路径都正常带附加信息。）

---

## 5. 为什么没有新增 RoomEvt

`RoomEvt.values` 恰好 27 项，被 `test/fixtures/room_model.json` 的 `EVT:*` tag 与
`room_coverage_test.dart:112/133` 双向锁死（加一项就要动 fixture + 27 条 reduce 分支覆盖）。

而这两件事本来就能用既有三件套**无损**表达：

| 要做的事 | 用哪个既有事件 |
|---|---|
| 「骰值/等级被改过」或「这是推动重掷」 | `EVT.DICE`（追加一条带 `luckSpent` / `pushed` 的记录）—— 语义上它**本来就是一条骰子记录** |
| 「扣了 N 点幸运」 | `EVT.STATE`（`stateApply` 的既有唯一写口，SEAT 单发 + `syncMembers`） |
| 「公共告知」 | `EVT.LOG` |
| 「越权/不可花的私有提示」 | `emit(EVT.PRIVATE, VIS.SEAT)`（`sysTo`） |

好处不只是省一条枚举：**回退重放能把这三件事一起还原**（新枚举若不带归约分支，回退后会丢状态）。

---

## 6. 反向自证伪（先红后绿，逐字节恢复）

基线哈希：`lib/domain/room_model_actions_combat.dart`
`64c81d0d2e5b4a672f0ebd2e9506330ad8f5bf87f321e039e105959e0e268fe2`

### ① 把 `spendLuck` 调用注释掉

```dart
// final r = rulesRef.spendLuck(<String, Object?>{
//   'result': args, 'amount': amount, 'luckAvailable': avail,
// });
final Map<String, Object?> r = {'ok': false, 'reason': '（自证伪：spendLuck 未接线）'};
```

`flutter test test/p11_luck_push_test.dart` → **`00:00 +13 -6: Some tests failed.`**
红的正是花幸运 ①~⑥（失败改成功 / 自动 need / 点数不足 / 大失败 / 大成功 / 理智检定）；
⑦⑧ 仍绿 —— 它们在进 `spendLuck` 之前就被「找不到可结算的检定结果」挡住了，符合预期。

恢复：`cp /tmp/combat.bak …` → `sha256sum` 回到 `64c81d0d…68fe2`，`cmp -s` → **RESTORED-IDENTICAL**。

### ② 把 `canPush` 校验去掉

```dart
// final verdict = rulesRef.canPush(args, args['kind']);
final Map<String, Object?> verdict = {'ok': true, 'reason': ''};
```

`flutter test test/p11_luck_push_test.dart` → **`00:00 +17 -2: Some tests failed.`**
红的是推动 ④（已成功的检定仍在推动）、⑤（大失败仍被推动）。
（③「战斗检定」没红是因为它在更外层就被「这不是一条可推动的检定记录」拦下了 ——
规则层那条 `canPush({'kind':'combat'})` 断言本身仍在用例里直接钉着。）

恢复：同样回到 `64c81d0d…68fe2`，`cmp -s` → **RESTORED-IDENTICAL**。

---

## 7. 测试账目

| 项 | 数 |
|---|---|
| 改动前基线 | 1987 |
| 新增 `test/p11_luck_push_test.dart` | +19 |
| 改动后 | **2006 全绿** |
| 既有用例改动 | **0**（一条断言都没改） |
| fixture 改动 | **0** |
| 新增/修改 RoomEvt | **0** |
| 新增 POLICY action | **0** |
| `lib/ui/room` 布局结构改动 | **0**（只加可选参数与按钮） |

新增用例清单（19 条）：

- **花幸运 8 条**：失败→成功（扣点/改写/播报三件事）、自动算 need、点数不足（状态零变更）、
  大失败（「不能被幸运抹掉」）、大成功、理智检定（kind 不可花）、别人的检定（拒绝且对方记录不变）、KP/旁观者拒绝。
- **推动 5 条**：失败→重掷（`pushed`/`pushFrom`/新值 75/「推动失败，后果加重」）、二次推动拒绝、
  战斗检定（规则层 `canPush` 原话 + 宿主层不给入口）、已成功拒绝、大失败拒绝。
- **UI 6 条**：`checkActionOf` 正例（need = 骰值 - 目标 = 12）、8 种不可操作返回 null、
  点数不够时「只降级不整体消失」、真渲染（按钮出现 + 点击发出的载荷 `{luck:true, amount:12}`）、
  成功的检定 `findsNothing`、KP 视角 `findsNothing`。

---

## 8. 已知边界（都不影响已交付行为）

1. **暗骰（secret）结果不在 `state.dice`**（走 `EVT.PRIVATE`），因此暗骰不能花幸运/推动 ——
   会得到一句私有提示「找不到可结算的检定结果」。要支持得给 SEAT 私密记录另开一路结构化存储，本批不做。
2. **推动重掷不带原奖励/惩罚骰**：`state.dice` 从未存过 `bonus/penalty`，重掷按 0/0 处理（同技能值、同难度）。
3. **`combat.roll` 不提供花幸运**（见 §4.2，F4 断言锁键集）。
