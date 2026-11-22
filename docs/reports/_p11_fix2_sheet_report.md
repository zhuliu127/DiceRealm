# P11 修 2 — 规则层两处缺陷 + 越权修复补测试 · 报告

**结论：IS_PASS**

工程根：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
交付日期：2026-11-11

---

## 0. 一键结论

| 项 | 结果 |
|---|---|
| `flutter analyze` | **No issues found!**（全量，零问题） |
| 新建用例 | `test/p11_fix2_sheet_test.dart` **6 组全绿**；`test/p11_authz_ready_test.dart` **7 组全绿** |
| 全量 `flutter test` | **1959 组全绿**（基线 1934 + 本人 13 + 同批另一位工程师 `p11_fix_intent_test.dart` 12） |
| 基线是否掉 | **未掉**（1934 → 1959 纯增量，无红、无 skip） |
| 反向自证伪 | 两处均**变红**，恢复后 `sha256sum` 与原值一致、`cmp -s` 通过 |
| 铁律遵守 | 生产代码只动 2 个函数（+1 条必需 import）；`lib/ui/**`、`room_model_host_intent.dart`、`room_model_actions_room.dart`、`room_rules_sheet.dart`、`pubspec.yaml` **零改动** |

---

## 1. 任务 1（P1）：`afterSanLoss` 早退把 SAN 累计吃掉了

### 1.1 缺陷

`lib/domain/room_model_actions_sheet.dart` 的 `afterSanLoss` 原顺序：

```
① san <= 0 → 永久疯狂 → return
   madActive（临时/不定疯狂）→ 提示「本次不获得新的疯狂症」→ return   ← ★ 早退
② sanLostThisRound / roundStartSan 累计                            ← ★ 被跳过
③ loss >= 5 && !isPotential → 临时疯狂 INT 检定
④ lossTotal >= ceil(maxSAN/5) → 不定性疯狂
```

P8 需求原文是「临时 / 不定疯狂期间**不获得新疯狂症**」——约束的是**发不发症状**，
不是「记不记 SAN 损失」。改前把整段累计放在早退之后，疯狂期受的损失一条都不进
`sanLostThisRound`，于是 ④ 的阈值 `ceil(maxSAN/5)` 基于错的累计，
「症状消退 → 潜在疯狂 → 复发」链上阈值**跨回合漂移**、隔一回合才显形。

### 1.2 改法（只动 `afterSanLoss`）

把 `sanLostThisRound` 与 `roundStartSan` 的累计整段**移到 `madActive` 早退之前**，
`madActive` 分支的 `return out` **原样保留**（仍然不发新症状）。
最终顺序对齐老 APP `room-model.js:5155-5271`：

```
① 归零 → ② 累计 → madActive 早退（P8 新增，老 APP 靠入口 raMemberMadActive 拦）→ ③ → ④
```

### 1.3 `san <= 0`（永久疯狂）分支为什么**不**累计 —— 选择与理由

**选择：不累计，保持原样（`①` 仍先于 `②` return）。**

理由（三条，正交）：

1. **老 APP 同序**：`room-model.js:5169-5176` 的 ① 归零分支就 `return out` 在
   `var lossTotal = ...`（:5190-5196）之前。本工程与老 APP 逐行对齐是 P10 第 3 期
   已确立的口径，此处改动会**新造**一处不等价。
2. **语义失效**：`san <= 0` 已判「永久疯狂 = 撕卡，只能聊天」。撕卡角色不再参与
   回合判定，④ 的判定分母 `maxSAN` 也失去意义 —— 记了也没人消费，只会留下
   「死人的回合计数」，与 `cureIndefinite`/`round.next` 的清零时机互相打脸。
3. **风险收益比**：若强行在归零分支也累计，`sanLostThisRound` 会成为「永久疯狂」
   状态下唯一被写的东西，而该状态的所有出口（治愈/推进回合）都会把它清掉 ——
   净效果为零，却多一条与老 APP 不同的路径。

已在 `p11_fix2_sheet_test.dart` 的 **F1-3** 把这条选择钉成断言
（`sanLostThisRound.containsKey('p1') == false`），防止未来「顺手补齐」。

### 1.4 未动的部分（明确声明）

- `blockedByMadness` / `isPotentialMadness` 的语义：**零改动**（`madness_state.dart` 未碰）。
- ④ 的 `ceil(maxSAN/5)` + `lossTotal >= oneFifth` 公式（:1281-1285 附近）：**零改动**（两版本来就一致）。
- `afterSanLoss` 之外的任何函数：**零改动**。

### 1.5 验收（F1-1 / F1-2 / F1-3）

- **F1-1**：`临时疯狂` + 连续两次损失（3 / 4）→ `sanLostThisRound == 7`（改前 `null`）、
  `roundStartSan == 43`（40 + 3，首值只记一次）、`madness` 仍为空、`mental` 仍是
  `['临时疯狂']`、第二次仍发「不获得新疯狂症」告警、且**没有** ② 的 INT 检定骰。
- **F1-2**（端到端差分）：`临时疯狂` 期先掉 9（只记账）→ 症状消退回 `正常` → 再掉 3。
  `9 + 3 = 12 == ceil(60/5)` → **不定性疯狂**成立。改前那 9 点没记，累计只有 3，
  阈值永不达标 —— 这一个用例直接复现了「阈值漂移」的现场。
- **F1-3**：`SAN = 0` + loss 60 → 永久疯狂成立，且**不写**累计（1.3 的选择）。

---

## 2. 任务 2（P1）：`detachPeer` 漏接 `rollbackAbortIfVoting`

### 2.1 缺陷

`lib/domain/room_model_host_core.dart` 的 `detachPeer` 只做 `markOffline` +
`syncMembers()`，**没调用** `rollbackAbortIfVoting`。而后者在
`lib/domain/room_model_rollback.dart:245-262` 早已实现齐全（非表决中、或掉线者
不在 `need` 名单里都返回空表）。所以是**没接线**，不是没实现。

后果：需求 §9「回退表决期间有人掉线 → 该次表决作废」不成立，表决会挂着等一个
已经不在的人。

### 2.2 改法（只动 `detachPeer`）

```dart
List<SendPlan> detachPeer(String seat) {
  final m = roster.markOffline(seat);
  if (m == null) return <SendPlan>[];
  final out = <SendPlan>[];
  out.addAll(rollbackAbortIfVoting(seat));
  out.addAll(syncMembers());
  return out;
}
```

- 返回类型 `List<SendPlan>` **不变**。
- 副作用顺序：`markOffline`（先）→ 中止表决（改 `state['rewind']`）→ 广播成员表。
  这样成员表广播带出去的是**已作废**的 rewind，客户端不会先看到 VOTING 再被覆盖。
- `rollbackAbortIfVoting` 签名是 `List<SendPlan> rollbackAbortIfVoting(String seat)`
  ——接受 `seat`，无需额外枚举参数。
- **`room_model_rollback.dart` 零改动**（只读）。
- 非表决中：`rewind == null` → 返回 `const <SendPlan>[]` → `out` 与改前**逐条相同**
  （`p11` 的 F2-2 + 既有 `qa_p4_seq_rollback_edges_test.dart:347` 的 `detachPeer` 用例
  同时守住这一点）。

### 2.3 一处必需的、函数外的改动（如实交代）

`host_core.dart` 原来没有 import `room_model_rollback.dart`，而
`rollbackAbortIfVoting` 是 `extension RoomHostRollback on RoomHost` ——
**扩展方法必须 import 定义库才可见**。因此加了一行 import（含 3 行说明注释）。
这构成 `host_core ↔ rollback` 的库环，Dart 允许（库环只影响顶层初始化顺序，
不影响扩展解析；两侧都没有依赖对方的顶层初始化）。`flutter analyze` 零问题已确认。

### 2.4 验收（F2-1 / F2-2 / F2-3）

- **F2-1**：表决进行中（`need = [p1, p2]`）+ 投票者 `p2` 掉线 →
  `rewind.state == FAILED`、`failReason == '有玩家在表决期间断线'`；
  广播一条 `rewind`（载荷内 `state == FAILED`，不是 VOTING）+ 一条公共
  「回退失败：有玩家在表决期间断线」+ 一条成员表；事件序列严格为
  `['rewind', 'log', 'members']`；`p2` 仅 `online == false`、**仍在花名册**（2 人）。
- **F2-2**：不在表决中 → `rewind` 保持 `null`，无 rewind / 无 log，成员表照发。
- **F2-3**：掉线者不在 `need` 名单里 → 表决保持 `VOTING`，无 rewind / 无 log。

---

## 3. 任务 3：越权修复的补测试（**未改生产代码**）

`lib/domain/room_model_actions_room.dart` **零改动**。新建
`test/p11_authz_ready_test.dart`，7 组（覆盖要求的 6 组 + 1 组闸门兜底）：

| 用例 | 断言要点 |
|---|---|
| R-1 玩家 A 指自己 `ready:true` | A 变已准备；无越权提示；成员表里 A `ready=true`、B 仍 `false` |
| R-2 玩家 A 指 B | **B `ready` 仍 `false`**（权威态零变更）+ A 收到 `'只能设置自己的准备状态'` + 不发成员表 |
| C-1 `char.share` A 指自己 | A 的 `charName` 变 `'甲·改'`；无越权提示；成员表已带新名 |
| C-2 `char.share` A 指 B | **B 的 `charName` / `charId` 均不变** + A 收到 `'只能上报自己的角色卡'` + 不发成员表 |
| S-1 旁观者指自己 | 走真实 `INTENT.ready` → `'旁观者不能设准备状态'`；再直呼 `roomActionReady` 覆盖 ACT 内的角色守卫；权威态不变 |
| S-2 空 `p['seat']` | 缺键 / 空串都回落本人并正常生效（`ready.set` 与 `char.share` 各测一遍），且**不误报**越权 |
| K-1 KP 伪造 ACT `ready.set` 指别人 | `needs(kp, 'ready.set').allowed == false` 前提成立 → 被闸门拒，提示 `'你没有权限执行该操作'`，p1 状态不变 |

**断言强度说明**：每组都要求「① 权威态没被改」+「② 越权者收到定向提示」两段同时成立
（只断言 ① 会把「静默吞掉」当成功，只断言 ② 会把「提示了但照样改了」当成功）。
未使用任何 `isNot` / 弱匹配放宽。

---

## 4. 反向自证伪（逐字节恢复）

### 4.1 任务 1：把累计移回早退之后

| 步骤 | 结果 |
|---|---|
| 备份 + 记 sha256 | `actions_sheet.dart` = `3761b510…cbc28` |
| 把累计段移回 `madActive` 之后 | `flutter test test/p11_fix2_sheet_test.dart` |
| 变红（预期） | **F1-1 红**（`Expected: <3> / Actual: <null>`）、**F1-2 红**（`Expected: <9> / Actual: <null>`）；F1-3 / F2-* 保持绿（互不影响，符合设计） |
| `cp` 恢复 | sha256 仍为 `3761b510…cbc28`；`cmp -s` → `CMP_OK actions_sheet` |

### 4.2 任务 2：注释掉 `rollbackAbortIfVoting`

| 步骤 | 结果 |
|---|---|
| 备份 + 记 sha256 | `host_core.dart` = `3b55be3f…ba0ed` |
| `// out.addAll(rollbackAbortIfVoting(seat));` | `flutter test test/p11_fix2_sheet_test.dart` |
| 变红（预期） | **F2-1 红**（`§9：表决期间有人掉线 → 该次表决作废`）；F1-* / F2-2 / F2-3 保持绿 |
| `cp` 恢复 | sha256 仍为 `3b55be3f…ba0ed`；`cmp -s` → `CMP_OK host_core` |

### 4.3 恢复后复测

- `flutter analyze` → **No issues found!**
- 两个新测试文件 → **13 组全绿**
- 全量 `flutter test` → **1959 组全绿**

> **哈希口径说明（避免误读）**：4.1 / 4.2 的 `sha256sum` 是「反向自证伪 → 恢复」
> 这一步的逐字节校验，两次都是 `3761b510…cbc28`（actions_sheet）与
> `3b55be3f…ba0ed`（host_core），`cmp -s` 均通过。
> 校验完成后只对 `actions_sheet.dart` 里那段**注释**做了一次措辞微调
> （把「① 归零 → ② 累计 → ③ ②分支」改写成完整四段顺序），
> 因此当前该文件哈希为 `604cfebd…91620`；`host_core.dart` 仍为 `3b55be3f…ba0ed`。
> 微调后已重新 `flutter analyze`（零问题）+ 重跑两个新测试文件（13 组全绿），
> 逻辑代码与反向自证伪时的版本逐字节相同。

---

## 5. 改动清单（全部文件）

```
M lib/domain/room_model_actions_sheet.dart   ← 只动 afterSanLoss 一处（累计前移 + 注释）
M lib/domain/room_model_host_core.dart       ← 只动 detachPeer 一处 + 1 条必需 import
A test/p11_fix2_sheet_test.dart              ← 6 组（F1 ×3、F2 ×3）
A test/p11_authz_ready_test.dart             ← 7 组（R ×2、C ×2、S ×2、K ×1）
A _p11_fix2_sheet_report.md                  ← 本文件
```

**零改动（逐项确认）**：`lib/ui/**`、`lib/domain/room_model_host_intent.dart`、
`lib/domain/room_model_actions_room.dart`、`lib/domain/room_rules_sheet.dart`、
`lib/domain/room_model_rollback.dart`、`lib/domain/madness_state.dart`、`pubspec.yaml`。

**未执行**：`flutter clean`（按要求）。

---

## 6. 测试组数变化

| 阶段 | 组数 |
|---|---|
| 基线 | 1934 |
| 同批另一位工程师（`p11_fix_intent_test.dart`，12 组） | +12 |
| 本人 `p11_fix2_sheet_test.dart`（6 组） | +6 |
| 本人 `p11_authz_ready_test.dart`（7 组） | +7 |
| **当前全量** | **1959（全绿）** |

本人对增量的贡献为 **+13**；1934 基线一条未掉。
