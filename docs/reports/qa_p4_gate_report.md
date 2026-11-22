# P4 房间规则层 · 独立复核报告（终验 / 第二轮）

- 复核人：software-qa-engineer-2（独立复核方）
- 工程：`C:\Users\60965\WorkBuddy\2026-10-08-18-34-17\dice-realm`（Flutter 3.47.9 / Dart 3.13.7）
- 规格权威：`coc7th-card-app/web/js/core/room-model.js`(7712 行) / `room-rules.js`(1591 行)
- 本轮性质：**F3 / F4 / F5 修完后的重新独立验收**（不沿用上轮结论）。只改 `test/` 与 `tool/qa/`，`lib/` 一行未碰。

---

## 0. 结论

**IS_PASS: YES** —— P4 房间规则层可出包。

| 判据 | 要求 | 实测 |
|---|---|---|
| 全量测试 | ≥894 且 0 红 | **927 全绿、0 红**（894 + 33 新探针） |
| `dart analyze` | 干净 | `No issues found!` |
| `node tool/qa/qa_p4_gate.js` | 13 条全 OK | **13/13 OK**，`P4_GATE IS_PASS: YES` |
| 白名单条数 | 2 条（收窄后 9+1） | **S:q1 = 9 条 / S:trim = 1 条**，无通配 |
| 白名单自证 | 常驻且通过 | `qa_p4_whitelist_proof_test.dart`（12 例）全绿 |
| fixture 形状 | 1349 例不变 | 455 / 517 / 121 / 256，零 error |

路由：**源码无阻断缺陷**（F3/F4 修复经独立复验成立）；**测试侧 3 项缺陷由我修复**（见 §3 G1/G2/G3，
均在 `test/`／`tool/qa/` 内，且全部是**收紧**）；**新增 1 条契约外边界记录**（§5 K1，旧版同源，不阻断）。

---

## 1. 基线（我自己复跑，非引用）

```
$ flutter test
00:37 +927: All tests passed!

$ dart analyze
No issues found!

$ node tool/qa/qa_p4_gate.js
[OK]   lib/domain 纯 Dart（零 Flutter/IO/UI）            扫描 38 个 .dart，零命中
[OK]   reduceRoomState( == 2 调用 + 1 声明               调用 2（client:123, host_core:157），声明 1
[OK]   白名单恰好 2 条（S:q1 9 + S:trim 1），无通配       entries=2，S:q1:9 / S:trim:1，kTrimAllowedPath=$.snapshotSeqs[0]
[OK]   四 fixture 精确 455/517/121/256（三基线 1093），零 error
[OK]   room_sequences.json 121 例全实跑（hostScript 94 / clientScript 27）
[OK]   房间写回路径恰好 1 处 await repo.save(；Host.save() 恰好 20 个顶层键
[OK]   61 个 POLICY action 全部分支零缺口（POLICY=61，分支=67，缺失=无）
[OK]   Q6 休眠项三件保留 / receive 无 gapFrom / 禁改文件未反向依赖 / T05 门禁 8 个
==== 合计 13 条，失败 0 条 ====
P4_GATE IS_PASS: YES
```

---

## 2. 三项修复的独立复验（新增 `qa_p4_final_gate_test.dart`，20 例）

### 2.1 F3（深回退：状态不退 + 二次崩溃）—— 修复成立

`_maybeSnapshot` 现为「保留 index0 基线 + 最近 snapshotLimit-1 条」；`rollback` 只在
`seq<=target` 里挑快照，一条都没有就从建团空状态重放 `(0,target]`，并显式对齐
`state.seq = target`。我的实测（全部独立于工程师单测）：

| 场景 | 断言 | 结果 |
|---|---|---|
| `every=1, limit=3`，10 条事件后 | 快照表 = `[0, 11, 12]`（基线永存） | OK |
| `rollback(3)` | `from=0`、`state.seq == log.seq == 2`、被撤销的 10 条聊天**不残留**、成员表仍由花名册覆盖、快照表非空且首条为 0 | OK（旧版此处是 state.seq=8 / log.seq=2 + 表被清空） |
| 连续四次深回退 `[3,2,1,1]` | 每次 `returnsNormally`，每次 `state.seq == log.seq`，快照表始终含基线 | OK（旧版第二次抛 `StateError`） |
| `limit=2`（最小窗口）/ `limit=1`（极端） | 快照表 `[0,last]` / `[0]`，深回退后 `state.seq==log.seq`、内容正确 | OK |
| `adoptSave` 后 `rollback(1)` | 不崩溃、`state.seq==log.seq==0`、基线快照被重建；再来一次仍不崩 | OK |
| `logCap=3` 截断 + `rollback(2)` | 不崩溃、水位仍相等（内容不可重建属预期） | OK |
| `roundStarts` | 回退掉 round2 后表里只剩 round1 且 seq 正确 | OK |
| **Q1 在窗口打满后** | `limit=2` 打满 → 秘密 CHECK 的中间快照被裁 → 从基线重放 `(0,3]`：权威态只有 1 条**脱敏行**、`syncFor(p1/p2/ghost)` 与 `save()` 均无明文 | OK（F3 改动没带崩 Q1） |

### 2.2 F4（玩家伪造 `combat.roll`）—— 收口成立

修法：`seat != host` 走 `diceDirect`（只透传 `expr/label/skill`，丢弃 `result` 与
`secret/reqId/base/bonus/penalty/damage`），KP 保持 `diceRoll` 原样，POLICY 仍含 player。

| 断言 | 结果 |
|---|---|
| 玩家传 `result{value:1, levelText:'大成功'}` → `state.dice` 末条 `total != 1`、`levelText != '大成功'`、`total ∈ 1..100` | OK |
| `expr` / `label` 仍照常透传；广播对象仍是 `to:'*'`；一次 act 只产生 **1 条**计划 | OK |
| 夹带 `secret:true` **不**触发暗骰分支（仍单条 PUBLIC、载荷无 `secret` 键） | OK |
| 夹带 `slotId/damage` 不改战斗槽；夹带 `hp` 不改角色卡；夹带 `reqId` 不结掉待办；`target` 不生效 | OK（四项逐一对比前后 JSON） |
| KP 的 `combat.roll` 行为不变（`total==1`、`levelText=='大成功'`，权威端自报结果仍被采用） | OK |
| `needs('player','combat.roll')` = `allowed:true, confirm:null`；spectator = 拒绝 | OK |

### 2.3 F5（白名单死登记）—— 修复成立，但我又补了两刀

工程师的修法（比较根 `r'$'` + `label`、fixture 改成真正触发差异、键集合放行）经我独立验证成立：

```
S:q1#1013  snapshotEvery=2 → rollback(6)：快照[0,2,4] 命中@4，重放 (4,5] = seq5 秘密 CHECK
S:q1#1014  snapshotEvery=3 → rollback(6)：快照[0,3]   命中@3，重放 (3,5] = seq4 LOG + seq5 秘密 CHECK
S:q1#1015  snapshotEvery=1 → rollback(3)：重放区间为空 → 零差异（按名排除，见 G1）
```

**白名单非摆设**常驻自证（`qa_p4_whitelist_proof_test.dart`，12 例）：

```
S:q1：覆盖的每一例都必须真的有差异 ................ OK（绕开白名单必然抛 TestFailure）
S:trim：覆盖的每一例都必须真的有差异 .............. OK（F:4#900001）
S:q1：差异路径集合恰好等于登记集合 ................ OK（= 9 条，一条不多一条不少）
S:q1：逐条摘除都必须报错（每条都真的被消费）...... OK（9 次摘除 9 次报错）
S:trim：差异路径集合恰好等于登记集合 .............. OK（= {$.snapshotSeqs[0]}，仅 1 条）
S:trim：逐条摘除都必须报错 ........................ OK
S:q1#1015 在严格比较下确实相等 .................... OK（排除的理由是零差异，不是图省事）
```

---

## 3. 本轮我修掉的测试侧缺陷（全部是**收紧**）

### G1（白名单覆盖面）：`S:q1#1015` 零差异却被 tag 连带白名单

- 现象：`S:q1` 家族 3 例共用一个 tag；`#1015` 的重放区间为空、Dart 与旧版**逐字段相等**，
  却被 `coversCase(tag)` 连带覆盖 → 将来这 9 条路径上真出现回归会被静默放行。
- 处理：给 `KnownDivergence` 加 `excludeCaseNames`（**逐个点名排除**，不放宽任何前缀），
  把 `#1015` 送回严格比较；并加永久用例证明「它严格比较确实相等」。
- 为什么不是「删掉这条登记」：删了 `#1013`/`#1014` 的 9 条差异就没有登记了（Q1 修正必然偏离 oracle）。

### G2（比较器语义）：登记一条路径 = 放过整棵子树（F5 第 5 步的漏洞）

- 现象：`_expectJsonMatch` 开头 `if (_isAllowed(path, allowed)) return;` —— 登记
  `$.a.b` 会把 `$.a.b.c` / `$.a.b.d` 的差异**整棵子树**静默放过（一张空白支票）。
  我构造 `$.a.b.d` 不同的场景，修复前**不报错**。
- 处理：改成「只放行**这个值**本身」——`expected` 是标量才放行，容器（Map/List）继续递归；
  要放行整棵子树必须显式写 `.*`（让审计一眼看得出）。这是收紧，不放宽任何东西。
- 影响面核对：注册的容器路径只有 `$.state.privates` / `$.steps[8].state.privates`（两侧同为 `[]`），
  在 G3 收窄后已删除；收紧后全量 927 仍全绿。

### G3（登记冗余）：S:q1 的 14 条 → 9 条（独立核算，不采信工程师数字）

我先写了「一条不多」核算（用**正式 runner** 产出的 actual + 独立递归 diff），跑出来的冗余集合：

```
S:q1：登记的 {
  $.state.logs[1].opp,
  $.state.privates,
  $.steps[8].state.logs[1].opp,
  $.steps[8].state.privates,
  $.steps[9].state.logs[1].opp
} 在当前 fixture 下零差异 → 冗余登记，必须删除
```

与工程师给的 5 条**完全一致**（独立得出，不是抄）。原因：旧版 `:685` 的明文行**同样带 `opp:null`**
（两侧同值）；`state.privates` 与 `steps[8].state.privates` 两侧同为 `[]`。
收窄后 9 条 = `logs[1]` 的 `text/seat/redacted` × 三个视图（权威态 + `steps[8]` + `steps[9]`），
且这 9 条**每条都被消费**（逐条摘除 9 次全部报错）。

### G4（gate 第 ③ 条判据）

从「1 条 / 14 条路径」改为「**恰好 2 条：S:q1 9 条 + S:trim 1 条，无通配**」，并把
`kTrimAllowedPath` 的**字面量**（必须是 `$.snapshotSeqs[0]`）纳入静态检查 ——
防止有人把它改成 `.*` 或整段子树。其余 12 条判据一字未动。

### G5（两处既有断言 14 → 9）

`test/room_equivalence_test.dart`、`test/room_purity_test.dart` 各有一处 `allowedPaths.length == 14`，
按 lead 授权同步为 9 并补注释（说明收窄依据）。这两处断言的性质不变（仍在钉条数与唯一性），只改期望值。

---

## 4. 白名单强度结论（终态）

- 条数：**恰好 2 条**（`S:q1` 9 条精确路径 + `S:trim` 1 条），无第 3 条、无 `.*` 通配。
- 覆盖面：`S:q1` 只覆盖真有差异的 2 例（`#1013/#1014`），零差异的 `#1015` 精确排除；
  `S:trim` 只靠 `exactCaseNames` 点名 `F:4#900001`，不波及既有 121 例。
- 消费量：**一条不多、一条不少**（差异路径集合 == 登记集合，逐条摘除必须报错）——
  这条现在是**常驻测试**，将来有人破坏 Q1/F3 修复或偷偷加路径，先在这里红。
- 比较语义：登记只放行该值本身；容器仍递归（G2）。`coversCase` 不再被 `S:q10`/`S:q1-other` 蹭到。
- 结论：**白名单强度合格**，且它现在是「有自证能力的闸门」，不再是「跑完就删的手工探针」。

---

## 5. 已知问题 / 观察项（均不阻断出包）

| 编号 | 内容 | 定性 | 建议 |
|---|---|---|---|
| K1 | `rollback(0)`（**契约外**输入，`beforeSeq` 应 ≥1）：不崩溃，但 `log.seq=-1` 而 `state.seq=0`，二者不相等；下一次 `emit` 复用 seq 0 | 旧版同源（`rollbackBefore(0)` 同样得 -1）；`state.seq==log.seq` 的不变式只在契约内保证 | P5 的 UI 入口必须保证 `beforeSeq>=1`；可在 `rollback` 里对 `beforeSeq<1` 直接 no-op 更稳 |
| K2 | `gapFrom=0` 既是「无缺口」又是「缺口起点 0」的哨兵冲突 → `resyncDiag().holes` 在「首个事件就是 seq3」时看不出洞（补拉起点仍正确） | 旧版同源、P3 级观测性 | 记入已知问题 |
| K3 | `LogRecord.toWireJson()` 把 `{t,vis,to,p}` 原样带出（p 可能含明文），目前只被测试使用 | 交接红线 | **P6 中继禁止直接序列化日志记录**，否则 Q1 修正在补拉路径被绕开 |
| K4 | 旧版 buggy rollback 写出的存档，`logs` 里可能已有明文；`playerViewFromSave` 会原样透传 | 「数据早已泄漏」，非新增泄漏 | 导入旧存档时对 `kind==='check'` 的明文行做一次脱敏迁移 |
| K5 | `_cropMember` 的 self 分支保留完整 sheet；槽顶层 `hp/hpMax` 不剥 | 当前生成路径不可达（sheet 走 `sanitizeSheet` 白名单、槽一律写 `public.hp`） | P5 若允许非规范形状上报，需补剥 |

---

## 6. 上轮已过项的抽样复跑（确认没被 F3/F4/F5 带崩）

```
flutter test test/qa_p4_secret_egress_test.dart test/qa_p4_seq_rollback_edges_test.dart \
             test/qa_p4_alias_actions_test.dart test/qa_p4_c5_writeback_test.dart \
             test/qa_probe_test.dart test/qa_p3_h1_h4_test.dart \
             test/qa_p3_h2_h3_test.dart test/qa_p3_h5_test.dart
00:04 +143: All tests passed!      # P4 探针 58 + P2/P3 回归网 85
```

- Q1 七变体（改文案/改 seat/改 p3/加隐藏字段/`snapshotEvery=3`/两次回退/`logCap` 截断）→ 全绿；
- KP 三闸、seq 边界、存档 20 键、C5 濒死卡写回、61 action 权限、5 个别名 → 全绿；
- **5 个别名裁决不变**：`room.close`/`room.end`/`check.push` 保留（KP-only + twice，玩家被 needs 拒且权威态零变化）；
  `state.edit.self` 保留（pending + 去重）；`combat.roll` 按 F4 收口（POLICY 仍开给玩家，结果改由权威端算）。
- 旧存档回放不受影响（静态：replay/save 四文件无 `applyAction(`；实证：save→restoreHost 逐字节一致）。

---

## 7. 交付物

新增（全部在 `test/` 与 `tool/qa/`）：

```
test/support/room_host_script.dart       # 与正式用例同一条 hostScript 执行路径 + 独立 diff 收集器
test/qa_p4_whitelist_proof_test.dart     # 12 例：白名单非摆设（绕开必红 / 一条不多不少 / 只跳单键）
test/qa_p4_final_gate_test.dart          # 20 例：F3(8) + F4(4) + F5(8) 独立复验
```

改动（均为收紧）：

```
test/support/room_oracle.dart            # G2：容器路径不再放过整棵子树（标量才放行）
test/support/room_oracle_whitelist.dart  # G3：S:q1 14→9；G1：excludeCaseNames 排除 #1015
test/qa_p4_whitelist_strength_test.dart  # 同步 9 条 + 新增「privates 差异必须报错」
test/room_equivalence_test.dart          # G5：14→9
test/room_purity_test.dart               # G5：14→9
tool/qa/qa_p4_gate.js                    # G4：③ 改为「2 条 / 9+1 / 无通配 + kTrimAllowedPath 字面量」
```

复现：

```bash
source /d/dev/env.sh
cd /c/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm
export NO_PROXY=127.0.0.1,localhost
flutter test                                     # 927 全绿
dart analyze                                     # No issues found!
node tool/qa/qa_p4_gate.js                       # 13 条全 OK
flutter test test/qa_p4_whitelist_proof_test.dart test/qa_p4_final_gate_test.dart
```

---

## 8. 一句话总结

F3/F4/F5 的修复我都用**独立探针**复验成立（含 `limit=1/2/3`、连续四次深回退、`adoptSave`、
日志截断、窗口打满后的 Q1 脱敏、六种夹带字段的零副作用）。
同时我又在自己这层挖掉三个「会让闸门变松」的东西：**零差异用例蹭白名单**（G1）、
**登记容器路径 = 放过整棵子树**（G2）、**5 条零消费的冗余登记**（G3）。
最终 927 全绿 / analyze 干净 / gate 13 条 OK / 白名单 2 条（9+1）且自证常驻 —— **IS_PASS: YES**。
