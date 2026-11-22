# P4 补丁 B1 · 独立复验报告

- 复核人：software-qa-engineer-2（独立复核方）
- 工程：`C:\Users\60965\WorkBuddy\2026-10-08-18-34-17\dice-realm`（Flutter 3.47.9 / Dart 3.13.7）
- 补丁范围：`lib/domain/room_model_host_intent.dart` 的四个 INTENT 分支接线
  （`DICE{direct}` → `diceDirect`、`SAN_CHECK` → `playerSanCheck`、`OPPOSED` → `opposed`、`BOARD` → `boardSelf`），
  **未**把它们加进 `kRoomPolicy`。
- 边界：只改 `test/`，`lib/` 一行未碰。
- ✅ **最新状态（B1-F1 修复后复验，见 §10）**：全量 **985 全绿 / 0 红**、analyze 干净、gate 13 条全 OK。
  §0~§9 是 B1-F1 修复前的复验记录，原样保留供审计追溯。

---

## 0. 结论

**IS_PASS: YES** —— B1 的四个入口权威性成立，`diceDirect` 里**没有**留下吃客户端自报的口子。

| 判据 | 要求 | 实测 |
|---|---|---|
| 全量测试 | ≥942、0 红 | **969 全绿、0 红**（942 基线 + 27 新探针） |
| `dart analyze` | 干净 | `No issues found!` |
| `node tool/qa/qa_p4_gate.js` | 13 条全 OK | **13/13 OK**，`POLICY=61，分支=67` |
| 白名单 | 仍 2 条（9+1） | 2 条，`S:q1` 9 + `S:trim` 1 |
| fixture | 仍 1349 例 | 455 / 517 / 121 / 256，**0 error** |
| P4 既有探针 | 全绿 | 105 例全绿；P2/P3 回归网 85 例全绿 |

路由：**无源码阻断缺陷**；发现 **1 个 P2 级已知问题（B1-F1，旧版同源、被 B1 变为可达）**，需你裁决（§7）。
测试侧 0 缺陷（本轮 27 例全部一次通过语义校验；中途 3 处红都是我探针自己的读法错误，已修）。

---

## 1. 四个接线点（静态确认）

```
$ grep -n "diceDirect(seat, mem, role, p)\|playerSanCheck(seat, mem, p)\|opposed(seat, mem, role, p)\|boardSelf(seat, p)" lib/domain/room_model_host_intent.dart
        if (jsTruthy(p['direct'])) { out.addAll(diceDirect(seat, mem, role, p)); ... }
        case RoomIntent.sanCheck:  out.addAll(playerSanCheck(seat, mem, p)); break;
        case RoomIntent.opposed:   out.addAll(opposed(seat, mem, role, p)); break;
        case RoomIntent.board:     out.addAll(boardSelf(seat, p)); break;
```

- 非 direct 的 `INTENT.DICE` 仍是原来那条「请求掷 X」日志，**一字未动**（探针断言两种文案分流）。
- `intent()` 里没有直写 `state[...] =`（正则扫 0 处），四个入口都经 `emit → apply → reduce` 单一写口。

---

## 2. `INTENT.DICE{direct}`：骰面不可伪造（重点项）

新增 `test/qa_p4_b1_authority_test.dart`（17 例）。核心判据：**骰面必须等于用 `CocRules` + 同种子独立复算的值**。

| 探针 | 实测 |
|---|---|
| 客户端 `result{value:1, levelText:'大成功', rolls:[1], detail:'1'}` → 权威 `total` / `levelText` / `rolls` | 与独立 `CocRules.check(base=50, rng=Lcg(7))` **逐字段相等**；`total != 1`；`rolls != [1]` |
| 5 个种子（1..5）各塞同一个伪造 `result{value:1}` | 5 个 `total` **不全相同**（随种子变），且**都不等于 1** |
| 同 5 个种子重跑 | 结果序列**完全一致**（可复现 → 结果来自确定性随机源，不是客户端） |
| 同一房内连续 4 次同 expr | `total` 出现多个不同值（随机流在推进，不是常量回显） |
| `expr:'3D6'` + `result{value:999}` | 与独立 `CocRules.rollExpr('3D6')` 的 `total`/`rolls` 相等，落在 3..18，`!= 999` |
| 未入座的 `ghost` 调 direct | 只回 1 条定向提示（+2 条 skip），不产生 `state.dice`，日志只多 1 条 |
| **KP** 调 direct + 伪造 result | 同样**复算**（`diceDirect` 从不读 `result`），`total != 1` |
| 对照：KP 走 **ACT `combat.roll`** | 仍采用自报 result（`total == 1`）——F4 裁决「KP 是权威端」的语义**没有被 B1 改变** |
| 夹带 `target/hp/slotId/damage` | 只有 1 条 PUBLIC 计划、`to:'*'` 不变；战斗槽 JSON 前后一致；角色卡 HP 未变；没有发给 `target` |
| 夹带 `secret:true` | 切成暗骰（详见 §7 B1-F1）：本人 1 条 + KP 1 条 SEAT evt，公共流只留一句提示 |

**关于「客户端能选目标值 `base`」**：`diceDirect` 在「角色卡里查不到该技能」时回落到 `p['base']`。
这是**旧版明确记录的既有语义**，不是 B1 的洞：

```
room-model.js:3025
  /* v2.0.0：目标值优先从**角色卡权威取值**…查不到才回落到客户端上报的 base
     —— 客户端上报的 base 可伪造、换机就失效。 */
room-model.js:3011-3013
  /* 玩家端无法伪造骰面（伪造的只是目标值，而目标值和骰面都记录在案，
     KP 看得到 —— 朋友间跑团够用了）。 */
```

Dart 侧与它逐行同构（`test/qa_p4_b1_authority_test.dart` 的第一个用例就是把 base 钉死来单独验骰面）。
**结论：骰面 100% 权威；目标值在「技能不在卡上」时可由客户端给，与旧版一致，且 KP 侧看得到。**
若产品要求「目标值也必须权威」，那是**另一条新规则**（要改 `diceDirect` 的 base 回落），需要你和 PM 裁决，不属于 B1 缺陷。

---

## 3. `INTENT.SAN_CHECK`：检定 / 扣减 / 疯狂都走规则服务

| 探针 | 实测 |
|---|---|
| 检定值、等级、SAN 扣减、分支文本 | 与独立 `CocRules.resolveSanCheck(currentSan:50, maxSan:60, lossExpr:'0/1D6', rng:Lcg(6))` **逐字段一致**（掷 82 / 失败 / 损失 6 / 50→44） |
| 客户端自报 `success/passed/lossValue/sanLoss/roll/value/levelText` | 全部无效：骰面与扣减仍等于规则服务复算值 |
| 单次损失 **≥5** | 进入**临时疯狂**：`mental` 含「临时疯狂」、`madness` 有症状，且发作的 **INT 检定**也是权威端掷的（`state.dice` 里能查到该条） |
| SAN 归零（SAN=1 掷失败 -4） | 走 `afterSanLoss` 的 `san<=0` 分支 → `mental=['永久疯狂']`、SAN 停在 0；再点一次不会把 SAN 抬回去 |
| 未绑卡 / 旁观者 / 非法损失式 | 各只回 1 条定向提示；不掷骰、不动角色卡；定向提示进收件人自己的 `privateBySeat`，**不进** KP 的 `state.privates`（reduce 的 PRIVATE 守卫） |

---

## 4. `INTENT.OPPOSED`：两阶段都只「报选什么」，数值全来自权威态

先说清结构（免得误判）：玩家的 `INTENT.OPPOSED` **不直接算对抗**，它有两阶段：
`opposedPlayerRequest`（建申请 → `await_kp`）与 `opposedPlayerTarget`（选目标 → 结算武器伤害）。
真正的 `CocRules().opposedFull` 在 KP 侧 `checkOpposed/opposedAttackResolve` 里跑（S4.3 既有，已由 `room_rules` 455 例等价性覆盖）。

| 探针 | 实测 |
|---|---|
| 申请阶段：客户端伪造 `weapon.damage='99D99'`、`weapon.skill='神圣打击'`、`db='99D99'`、`shots=9`、`a/b/winner` | 权威态 `st.weapon.damage='1D10'`、`skill='射击'`、`db='0'`、`shots=1`（来自角色卡与 `perRound`）；`st` 里**没有** `win` 键 |
| 目标阶段：客户端伪造 `winner:'b'`、`a/b` 值、`damage:999` | 发出的 CHECK 载荷 `winner='a'`、`a.value/b.value/a.levelText/b.levelText` **等于我用 `CocRules.check ×2 + opposedFull` 独立算出的值**；伤害来自权威 `rollExpr`（`applied ≤ raw < 999`）；结算后 `state.opposed=null` |
| 秘密对抗（`st.secret=true`） | 公共 `state.logs` 末条 = `{text:'KP 秘密进行了一次对抗检定', kind:'check'}` 且**没有 `opp` 键**；明文只进 `privateBySeat['host']`（定向 `to:'host'`），发起人 `privateBySeat['p1']` 为 null；`syncFor(p1/p2/ghost)` 都搜不到明文 |

---

## 5. `INTENT.BOARD`：落笔进权威态，只回本人

| 探针 | 实测 |
|---|---|
| 落笔 | `boardBySeat['p1']={strokes,at}`、`state.board.strokes` 各 1 条、`state.scene.boards['p1']={at,count:1,thumb:''}` |
| 广播面 | 恰好 1 条 evt（`to:'p1'`）；`p2` 收 `skip`；**没有任何 `to:'*'`** 计划 |
| 全量同步 | `syncFor('p1').state.board.strokes` 有 1 条；`syncFor('p2').state.board == null`；别人只在 `scene.boards` 看到摘要 `{count,thumb}`（**不含 strokes**） |
| 笔迹上限 | 传 5000 条 → 权威态与 scene 摘要都只留 **4000**（`boardSelf` 的 `take(4000)` 生效） |

---

## 6. 可见性三闸 + POLICY 面（B1 没破坏）

```
VIS.KP  : plan(rec) 为空（不出门），state 仍归约 ................ OK
VIS.SEAT: 只有 to 收 evt，其余在线者收 skip（各 1 条） .......... OK
PUBLIC+secret: kpOnly 被 scrub，warnings 恰好 +1 ................ OK
intent() 层直写 state[...] = ................................... 0 处（正则扫）
kRoomPolicy.length ............................................. 61
'dice'/'sancheck'/'opposed'/'board' 在表里 ..................... 否（needs 全拒）
既有 ACT 别名 board.self / dice.request / check.opposed / sheet.sancheck ... 仍在表里（未被误删）
```

**一处需要说明的不对称（旧版既有，不是后门）**：四个 op **不在** `kRoomPolicy`，但 `INTENT.*` 仍然结算。
旧版 `Host.intent` 只有 `INTENT.ACT` 走 `needs()` 权限链，其余 INTENT 直接进结算函数 —— B1 照搬。
探针 `不对称是旧版既有语义` 用运行期断言把这件事钉住了：`needs('player','board').allowed == false` 的同时
`intent('p1', BOARD)` 仍结算；而 `ACT(op:'board')` 只回一条越权提示。

---

## 7. 发现：B1-F1（P2）暗骰结果落进**公共** `state.dice`，并随存档/重连扩散

**现象**（`qa_p4_b1_authority_test.dart` 的「夹带 secret 会切成暗骰」用例，★现状断言）：

```
state.dice.length == 2            # 本人 + KP 两条 SEAT 事件都被 reduce 进了同一个公共 dice 数组
syncFor('p2').state.dice.length == 2   # 其他玩家的全量同步里能读到这条「暗骰」的 total/levelText/label
save()['dice'].length == 2             # 存档外带
playerViewFromSave(save,'p2').state.dice.length == 2   # 重连/旁观者裁剪视图里也有
state.logs 末条文案 = '甲 暗骰了一次（结果只有他/她与 KP 可见）'   # ← 与上面的事实矛盾
```

**根因**：`reduceRoomState` 的 `EVT.DICE` 分支**不看 `evt.vis`**，任何 `emit(DICE, …, VIS.SEAT, …)` 都会 push 进
`state.dice`；而 `makeSync` 的 `dice` 字段是 `roomState.dice` 全量下发。旧版**一字不差**：

```
room-model.js:612-618   case EVT.DICE: state.dice.push({...})   // 无 vis 判断
room-model.js:1290      dice: clone(st.dice),                    // sync 全量
```

**定性**：
- **旧版同源**（不是 B1 改坏的），但 Dart 侧此前 `INTENT.DICE{direct}` 是 no-op、`ACT dice.direct` 被 `needs()` 拒，
  所以这条路径**第一次变成玩家可达** —— 属于「B1 让一个潜伏缺陷上线」。
- 影响面：泄漏的是**玩家自己**选择隐藏的那颗骰（不含 KP 秘密），无越权、无状态损坏；
  但暗骰文案明确承诺「只有他/她与 KP 可见」，属于**功能承诺被打脸**，且会写进存档长期留存。
- 归因：P2。**不阻断 B1 的权威性判定**（`result` 依然完全不被采用）。

**两种收口（都不影响任何 fixture —— 现有 1349 例没有一例覆盖暗骰/direct）**：

1. **reduce 侧过滤**：`case RoomEvt.dice:` 增加 `if (evt.vis != null && evt.vis != RoomVis.public) break;`
   → 暗骰不进公共 dice。副作用：**KP 自己**的暗骰也不再进 `state.dice`（旧版会进），
   若 KP 界面依赖它显示自己的暗骰，需要同时把 KP 那一路改成 `EVT.PRIVATE`/`emitLocal` 回显。
2. **diceDirect 侧分流**：暗骰不再发 `EVT.DICE`，改发 `EVT.PRIVATE`（to: 本人 + to: KP）+
   公共脱敏日志；`state.dice` 只承载公开骰。改动更集中（一个函数），但要同步 P5 的骰子列表渲染口径。

**我的建议**：选 **2**（改动集中、语义清楚、不动 reduce 的通用分支）。
若你决定本期不修，请在 **P5 UI 上线前**别把「玩家暗骰开关」暴露出去 —— 否则用户会立刻踩到「我开了暗骰，队友全看见了」。
若修：修完请让我同步改 `qa_p4_b1_authority_test.dart` 里那 4 条 ★现状断言（我改，不动源码）。

---

## 8. 回归与交付

```
flutter test test/qa_p4_secret_egress_test.dart test/qa_p4_whitelist_strength_test.dart \
             test/qa_p4_whitelist_proof_test.dart test/qa_p4_seq_rollback_edges_test.dart \
             test/qa_p4_alias_actions_test.dart test/qa_p4_c5_writeback_test.dart \
             test/qa_p4_fresh_oracle_test.dart test/qa_p4_final_gate_test.dart
00:01 +105: All tests passed!          # 上轮 105 例 P4 探针零回归

flutter test test/qa_probe_test.dart test/qa_p3_h1_h4_test.dart test/qa_p3_h2_h3_test.dart test/qa_p3_h5_test.dart
00:03 +85: All tests passed!           # P2/P3 回归网 85 例
```

新增（全部在 `test/`）：

```
test/qa_p4_b1_authority_test.dart   17 例  # diceDirect / SAN_CHECK / OPPOSED 的权威性
test/qa_p4_b1_visibility_test.dart  10 例  # BOARD 广播面 + 可见性三闸 + POLICY 61 条
```

复现：

```bash
source /d/dev/env.sh
cd /c/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm
export NO_PROXY=127.0.0.1,localhost
flutter test                                   # 969 全绿
dart analyze                                   # No issues found!
node tool/qa/qa_p4_gate.js                     # 13 条全 OK
flutter test test/qa_p4_b1_authority_test.dart test/qa_p4_b1_visibility_test.dart
```

---

## 9. 一句话总结

四个入口里**最危险的那个是安全的**：`diceDirect` 从不读客户端 `result`，骰面与 `CocRules` 独立复算逐字段相等，
换种子会变、同种子可复现、夹带字段零副作用；SAN/对抗/手绘板同样只把「选什么」交给客户端，
`POLICY` 仍 61 条、三闸未破、105 例 P4 探针零回归。
唯一需要你拍板的是 **B1-F1**：暗骰结果因 reduce 不看 `vis` 而落进公共 `state.dice` 并随存档扩散（旧版同源、B1 使其可达，P2，两条小改可收）。


---

## 10. B1-F1 修复后复验（暗骰隐私收敛）

### 10.1 结论

**IS_PASS: YES** —— B1-F1 已按方案 ② 收口，暗骰隐私成立，公开骰与其它面零回归。

```
flutter test                     00:31 +985: All tests passed!      （978 通过+1 待同步 → 985 全绿）
dart analyze                     No issues found!
node tool/qa/qa_p4_gate.js       13 条全 OK，P4_GATE IS_PASS: YES
                                  （POLICY=61 / reduceRoomState( 2 调用 + 1 声明 / 白名单 2 条 9+1 / 四 fixture 1349）
B1 四文件                        authority 17 + visibility 10 + dark_privacy 6 + 工程师 privacy 10 = 43 全绿
P4 既有探针                       105 全绿
P2/P3 回归网                     85 全绿
```

### 10.2 断言同步（6 条，全部**先实测再改**，不采信工程师的数字）

我先把修复后的真实输出打出来，再改断言。实测（`seed=4`、`1D100`、`label='偷袭'`、`base=50`）：

```
PLANS        : [ {to:p1, evt t:'private', p:{kind:'dice-dark', total:62, levelText:'失败', label:'偷袭', ...}}
                 {to:p2, skip 3}
                 {to:host, evt t:'private', p:{… total:62 …}}
                 {to:p1, skip 4} {to:p2, skip 4}
                 {to:'*', evt t:'log', p:{kind:'dice-dark', text:'甲 暗骰了一次（结果只有他/她与 KP 可见）'}} ]
STATE.DICE   : []
PRIV_1       : [{seq:3, title:'暗骰结果', text:'暗骰 1D100（偷袭） = 62（失败）　明细：个位骰 2；十位骰 6 → 62', kind:'dice-dark'}]
PRIV_HOST    : [{seq:4, … 同文本 …}]
STATE.PRIVATES: [{seq:4, … 同文本 …}]        # KP 侧私密栏（不进 makeSync、不进 save）
SYNC_P2      : dice=[] privates=[] logs=[{kind:'dice-dark', text:'甲 暗骰了一次…'}]   # 无「明细」
SAVE_DICE    : []     VIEW_P2_DICE : []
```

| # | 原断言 | 实测 | 已改为 | 备注 |
|---|---|---|---|---|
| 1 | `state.dice.length == 2` | 0 | `isEmpty` | 隐私核心 |
| 2 | `syncFor('p2').state.dice.length == 2` | 0 | `isEmpty` | 别人读不到 |
| 3 | `save()['dice'].length == 2` | 0 | `isEmpty` | 存档不带 |
| 4 | `playerViewFromSave(...).state.dice.length == 2` | 0 | `isEmpty` | 重连读不到 |
| 5 | toSelf evt `t == RoomEvt.dice` | `'private'` | `RoomEvt.private_` | 全量首个红点 |
| 6 | `otherDice.last['label'] == '偷袭'` | `otherDice` 已空（`.last` 会抛 StateError） | 删除，改为断言 `privateBySeat['p1'/'host']` 的 text 含 label + 骰面 | — |

同时**补强**（不是弱化）：把「暗骰的骰面也必须权威」加进这条用例 ——
`selfP['total'] == CocRules.check(base=50, rng=Lcg(4))['value']`，避免「为了隐私把结果也弄丢/弄假」。

### 10.3 独立复验矩阵（新增 `test/qa_p4_b1_dark_privacy_test.dart`，6 例）

| 要求 | 实测 |
|---|---|
| ① 暗骰不进公共面 | `state.dice` / `syncFor('p2')` / `syncFor('ghost')` / `save()['dice']` / `playerViewFromSave(save,'p2')` 全为空；**字节级**再确认别人载荷里没有「明细」「偷袭」 |
| ① 本人与 KP 都拿得到 | live evt（`t:'private'`）自带结构化 `total/levelText/label`，KP 那份与本人一致；`privateBySeat['p1']` 与 `['host']` 各 1 条，text 含骰面、label、等级文本；公共日志 `kind:'dice-dark'` 且**不含**骰面 |
| ② 公开骰没被带崩 | 仍 `EVT.DICE` + `to:'*'` + 进 `state.dice`；`syncFor('p2').dice` 有 1 条且 total 与权威一致 |
| ③ 混合场景 | 先公开后暗骰 → `state.dice` 只剩公开那条（label='明骰'）、别人同步里也只有它；暗骰只在 `privateBySeat` |
| ④ 多次 / KP 自己 | 连续 3 次暗骰 → `privateBySeat['p1']` 3 条、`state.dice` 恒空；KP 自己暗骰只收 **1** 条 evt（不发生「自己发给自己两次」） |
| ⑤ 闸门/warning | 暗骰是 SEAT 事件 → **不触发** scrub、warnings 不变；三闸（KP 空计划 / SEAT 单发 + 其余 skip / PUBLIC+secret 被 scrub 且 +1）复核全过 |
| ⑥ 静态不变式 | `kRoomPolicy` 61 条、`reduceRoomState(` 2 调用 + 1 声明、`lib/domain` 纯度零命中、白名单 2 条（9+1）、四 fixture 455/517/121/256 零 error |

**一处需要交接给 P5 的精度问题（不是缺陷）**：`_accumulatePrivate` 只保留
`{seq,title,text,at,kind}` 五个键，所以**重连后拿回来的是文本**（`'暗骰 1D100（偷袭） = 62（失败）　明细：…'`），
而不是结构化的 `total/levelText/label`。实时 evt 里有结构化字段，重连没有。
若 P5 的骰子列表要在断线重连后仍渲染结构化暗骰，需要把这几字段带进 `privateBySeat`
（或让 P5 直接渲染 text）—— 这属于 P5 的渲染口径选择，不影响本期隐私成立。

### 10.4 对 §12「第 3 处有意偏离旧版行为（无 fixture 覆盖）」的评估：**定性成立，且「不走白名单」是唯一自洽的做法**

我独立核对了工程师的三个事实主张（自己 grep 的，不是采信）：

```
room_rules     455 例 | "direct"=0 | dice.direct=0 | 暗骰=0  | dice.dark=0
room_model     517 例 | "direct"=0 | dice.direct=0 | 暗骰=0  | dice.dark=16（全是 POLICY / needs 元数据）
room_sequences 121 例 | "direct"=0 | dice.direct=0 | 暗骰=1  | dice.dark=0
   └ 唯一含「暗骰」的是 S:q1#1015 里一句手写 emit 的 text='暗骰：07'，与 diceDirect 无关
   └ room_sequences 中 **INTENT.DICE 用例 = 0 条**
room_actions   256 例 | "direct"=0 | dice.direct=0 | 暗骰=7  | dice.dark=20
   └ A:apply:dice.dark#30 的 p.op='dice.dark' → dispatch 到 KP 工具 darkRoll（本轮零改动）
```

结论三条：

1. **定性成立**：这确实是第 3 处「Dart 有意偏离旧版」的行为（前两处是 F4 的 result 丢弃、F3 的快照基线）。
2. **「不走白名单」不只是可接受，而是必须**：白名单的语义是「在某条 **被覆盖的 case** 里，允许某条 JSON 路径两侧不同」。
   当前 1349 例没有任何一例走 `diceDirect(secret:true)`，所以登记一条白名单**不会抑制任何差异**，
   反而会被我上轮落盘的 `qa_p4_whitelist_proof_test.dart` 判为「零消费的冗余登记 → 必须删除」而直接变红。
   换句话说：**加白名单才是错的**。
3. 但「不进白名单」≠「不用记录」。建议补两件事（都在本期无成本）：
   - 在设计/PRD 的「有意偏离清单」里加第 3 条（现在只存在于 `_p4_patch_b1.txt`，
     而那是补丁交付文档，不是长期规格）；
   - 若将来 `tool/oracle/dump_p4_room.js` 扩出 `INTENT.DICE{direct}` 用例，**必须预期这条差异**
     （暗骰走 PRIVATE、不落 state.dice），否则新 fixture 会立刻红且后人不知道原因。
     最省事的做法：在 dump 脚本的用例旁留一行注释指向本报告 §10。

### 10.5 本轮交付

```
[改] test/qa_p4_b1_authority_test.dart        同步 6 条断言 + 补「暗骰骰面也须权威」
[新] test/qa_p4_b1_dark_privacy_test.dart     6 例（隐私矩阵 / 公开骰 / 混合 / 多次 / KP / 静态不变式）
[改] qa_p4_b1_report.md                       本节
```

`lib/` 一行未碰；既有测试未删、未弱化；白名单未加条目。
