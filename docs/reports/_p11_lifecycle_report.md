# P11 · 跑团房间规则层 2 处缺陷修复报告（fix-lifecycle）

- 工程：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
- 主战场：`lib/domain/room_model_rollback.dart`（唯一被改的 lib 文件）
- 新增测试：`test/p11_lifecycle_test.dart`（12 组）
- 老 APP 基准：`coc7th-card-app/.../core/room-model.js`
- 门禁：`flutter analyze` **No issues found**；全量 `flutter test` **1980 组全绿**
- 结论：**IS_PASS**

---

## 0. 一句话结论

| # | 缺陷 | 改法 | 结论 |
|---|------|------|------|
| 1 | 结团 / 关房后不清战斗态与逐座位待办 | `closeRoom()` / `endSession()` 统一走 `_clearTransientOnLifecycleEnd()`：`state['combat'] = null` + `requestsBySeat.clear()` + `pending.clear()`（幂等） | 两版共同遗留（老 APP `room-model.js:3507-3513` 也只 `pending=[]`），**修到正确**而非照抄 |
| 2 | 回退后不重算 `sanLostThisRound` / `fireUsed` / `fadedArm` | `rollback()` 末尾调用 `_realignRoundScopedState(target)`：按幸存日志从 seq0 重扫到 target，复刻三条生命周期规则 | 两版共同缺陷；**这三个字段不进快照**，只能按日志重算 |

---

## 1. 缺陷 1：结团 / 解散后不清战斗态与逐座位待办

### 1.1 改前

```dart
List<SendPlan> closeRoom() {
  final out = plan(emit(RoomEvt.closed, {'at': now()}, vis: RoomVis.public));
  pending.clear();            // ← 只清这一处
  return out;
}
List<SendPlan> endSession() {
  final out = plan(emit(RoomEvt.ended, {'at': now()}, vis: RoomVis.public));
  pending.clear();            // ← 只清这一处
  return out;
}
```

`pending`（KP 侧待确认队列）清了，但：

- `state['combat']` 仍是战斗态 —— `reduce` 的 `CLOSED` / `ENDED` 分支只写 `meta`（`room_model_reduce.dart:352-361`），不碰 combat；
- `requestsBySeat`（逐座位的待办请求表，`host_core:105`）一条没少 —— 它是 `/sync` 里 `_requestsView(seat)`（`host_core:563-575`）的唯一数据源，重连时原样推回去 → 玩家侧那张「待你确认」的幽灵卡片。

### 1.2 改后

```dart
List<SendPlan> closeRoom() {
  final out = plan(emit(RoomEvt.closed, ...));
  _clearTransientOnLifecycleEnd();
  return out;
}
List<SendPlan> endSession() {
  final out = plan(emit(RoomEvt.ended, ...));
  _clearTransientOnLifecycleEnd();
  return out;
}

void _clearTransientOnLifecycleEnd() {
  state['combat'] = null;   // emptyRoomState() 的初值，与「未开战」同形
  pending.clear();
  requestsBySeat.clear();
}
```

### 1.3 为什么这么改（而不是别的写法）

1. **只清「本轮进行态」，不动历史**：`closed` / `ended` 是终态但**房间对象还在**（续玩、导出历史都靠它）。花名册、日志、存档、场景、素材一个都没动 —— L1-1 断言 `roster.dump().length` 不变、`log.items` 只增不减、`save()` 仍能完整导出。
2. **不 emit `COMBAT{combat:null}`**：那会多一条日志 + 一个 seq + 一条发送计划，而 `closeRoom()` / `endSession()` 的出站形状是 fixture 逐条比对的（`room_sequences.json` 的 `S:status#1016` / `#1018`）。现状是直接把权威态收敛回「没有进行中的战斗」，不是一条新的房间事件。
3. **幂等**：全是 `clear()` / 置 `null`，连调两次不抛错（L1-3 连调 `closeRoom` ×2 + `endSession` ×2）。
4. **为什么不顺手清 `state['requests']`**：它是 `REQUEST` 事件的归约镜像（每个客户端各存一份），玩家侧卡片的真正数据源是 `/sync` 的 `_requestsView(seat)` ← `requestsBySeat`（已清）。而镜像本身被逐字段 fixture 锁定（`qa_p4_fresh_oracle.json` 的 `F:1#2024` 明确期望 `$.state.requests` 长度为 1）—— 动它等于改「与旧版逐字段等价」，超出本缺陷范围。实测：清它会直接把 `qa_p4_fresh_oracle_test` 打红（见 §5）。
5. **老 APP 也不是全对**：`room-model.js:3507-3513` 的 `closeRoom` 同样只有 `this.pending = []`（v2.1.6 注释），不清 `combat` 与 `_requestsBySeat`。所以这不是「新工程没跟上老 APP」，是**两版共同遗留**，本次修到正确。

---

## 2. 缺陷 2：回退不重算三个「回合内累计型」字段

### 2.1 先确认「快照到底带不带这三个字段」

`RoomSnapshot` 的定义（`room_types.dart:399-404`）：

```dart
class RoomSnapshot {
  const RoomSnapshot(this.seq, this.state);
  final int seq;
  final Map<String, Object?> state;
}
```

- 快照只有 `seq + state` 两个字段；
- `state` 的键集是 `emptyRoomState()` 锁定的 18 键（`room_model_state.dart:45-94`），`snapshots` 里拍的也是这份 `state` 的深拷贝；
- `sanLostThisRound` / `roundStartSan` / `fadedArm` / `fireUsed` 全部是 `RoomHost` 的**内存字段**（`host_core:120-132`），**不进快照、不进 `state`、不进存档**（`save()` 白名单见 `room_model_save.dart:65-100`，只有 `adoptSave` 会把这四张表 `clear()`，见 `:164-167`）。

**结论：快照里没有这三个字段的任何副本，回退无法「恢复」，只能按日志重算。** 这也是为什么没有走「让快照带上它们」这条路：那要改 `RoomSnapshot`（在 `room_types.dart`，本次不在改动白名单内）并破坏 18 键形状的逐字段 fixture。

### 2.2 三个字段的生命周期推导（先读代码，不拍脑袋）

#### ① `sanLostThisRound[seat]`：本回合该座位累计的 SAN 损失

| 事件 | 代码位置 | 行为 |
|------|----------|------|
| 累加 | `room_model_actions_sheet.dart:1235-1236`（`afterSanLoss`） | `sanLostThisRound[seat] += loss` |
| 置 `roundStartSan` | `:1237-1240` | 本回合第一次损失时记 `currentSAN + lossTotal`（= 损失前的 SAN），只记一次 |
| 回合边界清零 | `host_core:211`（`_onRoundBoundary`，由 `RoomEvt.round` 驱动） | `sanLostThisRound.clear()` + `roundStartSan.clear()` |
| 治愈归零 | `actions_sheet:1846-1847`（精神分析成功）/ `:2000-2001`（治愈不定/潜在疯狂） | `= 0` + `roundStartSan.remove` |
| 归零早退 | `actions_sheet:1212-1223` | `san <= 0` → 永久疯狂分支**先 return**，不累计（对齐老 APP） |

**语义 = 「本回合之内」的累计**，用途：`afterSanLoss` ④ 的不定疯狂阈值 `lossTotal >= ceil(maxSAN/5)`（`:1289-1296`）。

**推导出的重算规则**：取「本回合窗口内 `RoomEvt.state` 里 `status.currentSAN` 的净下降量」。
为什么等价：四个调用点（`sanCheck:1194`、精神分析失败 `:801`、改 SAN 后判疯狂 `:1491`、`stateRequest` 结算 `:1786`）都是**先 `stateApply` 写新 `currentSAN`，再 `afterSanLoss` 累加同一个 `loss`**，所以「净下降量 == 当时累加的量」；`roundStartSan` 就是这轮第一次损失前的 `prev`，与 `currentSAN + lossTotal` 同值。

#### ② `fireUsed['seat\u0000weapon']`：本回合「某玩家 + 某武器」已发射数

| 事件 | 代码位置 | 行为 |
|------|----------|------|
| 累加 | `actions_combat.dart:1929/1938`、`:2070` | `fireUsed[key] = priorShots + shots/firedCount` |
| 读 | `:1930-1937`、`:2276` | 连发惩罚骰 `+priorShots` |
| 回合边界清零 | `host_core:210` | `fireUsed.clear()` |

**语义 = 「本轮」的发射计数**，与 `sanLostThisRound` 同寿命。

**推导出的重算规则**：**一律按「本回合 0 发」重算**。
理由：发射次数只存在于内存（`CHECK` 事件的载荷里只有摘要文本 `本轮已发射 x/y`，没有结构化的「座位+武器→已发几发」），日志还原不出来。回退时宁可少算一次连发惩罚骰，也不能把**已被撤销的那一枪**继续算作「已发射」—— 那正是缺陷症状「回退后这一枪打不出去」。

#### ③ `fadedArm[seat]`：潜在疯狂「本回合任意损失即复发」的武装开关

| 事件 | 代码位置 | 行为 |
|------|----------|------|
| 缺键的含义 | `host_core:124-129` 注释 + `actions_sheet:1291`（`fadedArm[seat] != false`） | **缺键 = 武装**（true） |
| 武装（置 true） | `actions_sheet:1929`（`advanceMadness`：不定疯狂症状消退 → 潜在疯狂） | 转入潜在疯狂时武装 |
| 解除武装（置 false） | `host_core:215-228`（回合边界）：`clear()` 后对**仍处潜在疯狂**的座位显式置 `false` | 跨过一个回合边界就 disarm |
| 判定 | `actions_sheet:1295-1296` | `(isPotential && fadedArmed) \|\| (lossTotal >= ceil(maxSAN/5))` |

**语义 = 「该座位是不是本回合内才转入潜在疯狂」** → 决定「任意 SAN 损失是否立刻复发」，还是「要重新累计到 1/5 maxSAN」。

**推导出的重算规则**：
- 从日志算出每个座位「最近一次进入潜在疯狂」的水位（`RoomEvt.state` 的 `mental` 由非潜在 → 潜在），
- 再算「最近一条 `RoomEvt.round` 的水位」，
- 进入水位 **晚于** 最近边界 → `fadedArm[seat] = true`（本回合内武装）；
- 进入水位 **早于** 最近边界 → `fadedArm[seat] = false`（边界已 disarm）；
- 进入水位落在日志窗口之外（被 `logCap` 裁掉，无从判定）→ **保持缺键**（= 武装，与改前默认口径一致）；
- 目标态里已不是潜在疯狂的座位 → 键必须消失。

⚠️ 特意**没有**简化成 `fadedArm[seat] = isPotentialMadness(mental)`：那样「潜在疯狂」会永远「任意损失即复发」，与回合边界 disarm 的设计冲突（L2-7 专门钉住这一点：转入发生在边界之前时，回退后仍必须是 `false`）。

### 2.3 改前 / 改后

**改前**：`rollback()` 重建 state、重放 `(snap.seq, target]` 的事件、裁日志、重建 `roundStarts` —— **四张表一列都不碰**。于是回退到旧回合后，这些表仍描述**被撤销掉的那一轮**：

- `sanLostThisRound` 带着「未来那一回合」的累计 → ④ 的阈值判高/判低；
- `fireUsed` 还标着「已发射」→ 回退后这一枪打不出去；
- `fadedArm` 方向错 → 该复发的没复发 / 不该复发的立刻复发。

**改后**（`room_model_rollback.dart:112-117`）：

```dart
state['seq'] = target < 0 ? 0 : target;

// ★ P11 修 2：回合内累计型字段必须跟着回退点重算
_realignRoundScopedState(target);
```

`_realignRoundScopedState(target)`（`:191-265`）：清空四张表 → 单遍扫 `log.items`（`seq <= target`）复刻 §2.2 的三条规则 → 按目标态的花名册精神状态收口 `fadedArm`。

**为什么不「跨回合才清、同回合不动」**：同回合回退同样会撤销掉一次 SAN 损失（对应 `state` 事件已从日志里消失），留着就是把「被撤销的伤害」继续算进阈值；L2-2 就是这个场景（改前 10、改后 7）。

### 2.4 不影响正常推进

`_realignRoundScopedState` **只在 `rollback()` 里被调用**，事件产生路径（`emit` → `apply(persist:true)` → `_onRoundBoundary`）一字未改。L2-8 是反向护栏：不回退时 `advanceRound` 照旧清零 + disarm。

---

## 3. 反向自证伪（两处各注入一次错误 → 必须变红 → 逐字节恢复）

### 3.1 注入 A：去掉战斗态清理

```dart
void _clearTransientOnLifecycleEnd() {
  // ⛔ 反向自证伪注入点 A：注释掉战斗态清理
  // state['combat'] = null;
  pending.clear();
  requestsBySeat.clear();
}
```

`flutter test test/p11_lifecycle_test.dart`：

```
00:00 +0 -4: Some tests failed.
Failing tests:
  ... L1-1 endSession：战斗态归 null、待办请求清空，成员/日志/ended 不受影响
  ... L1-2 closeRoom：同样清战斗态与待办，但 meta.ended 仍不置真
  ... L1-3 幂等：closeRoom / endSession 连调两次不抛错、状态不变
  ... L1-4 续玩：结团后同一房间再连进来，sync 里没有战斗态也没有幽灵卡片
```

→ L1 四组全红（`+0 -4`），L2 八组仍绿。

恢复：

```
370aa689bc9b5e6fded09919fa84474c3dcf671a9c641e7b492ff5b3e8e01e26 *lib/domain/room_model_rollback.dart
370aa689bc9b5e6fded09919fa84474c3dcf671a9c641e7b492ff5b3e8e01e26 *_fix_rollback.dart.p11
CMP_OK_A
```

### 3.2 注入 B：去掉回退重算

```dart
// ⛔ 反向自证伪注入点 B：注释掉重算
// _realignRoundScopedState(target);
```

`flutter test test/p11_lifecycle_test.dart`：

```
00:00 +6 -6: Some tests failed.
Failing tests:
  ... L2-1 跨回合回退：sanLostThisRound 回到「回退到的那个回合」的值
  ... L2-2 同回合回退：被撤销的那次 SAN 损失不再算进累计
  ... L2-3 回退到建团基线：累计表全部为空（不残留任何「未来」值）
  ... L2-4 fireUsed：回退到没射过的回合 → 连发计数从 0 起算（能再开枪）
  ... L2-5 fireUsed：同回合回退也一律按「本回合 0 发」重算（不堵死再射击）
  ... L2-6 fadedArm：潜在疯狂在回合内武装、跨边界被 disarm，回退后重新武装
```

→ L2 六组变红（L2-7「不许被误武装」、L2-8「正常推进不变」本来就该在两种实现下都绿，它们是**反向护栏**，不是缺陷靶子）。

恢复：

```
370aa689bc9b5e6fded09919fa84474c3dcf671a9c641e7b492ff5b3e8e01e26 *lib/domain/room_model_rollback.dart
370aa689bc9b5e6fded09919fa84474c3dcf671a9c641e7b492ff5b3e8e01e26 *_fix_rollback.dart.p11
CMP_OK_B
```

恢复后复跑：`+12: All tests passed!`（12/12）。

### 3.3 注入口径说明

- 两次注入都**只动 `room_model_rollback.dart`**，测试文件一字未改 —— 红是"删掉修复"造成的，不是改断言造成的。
- 恢复方式是 `cp` + `sha256sum` + `cmp -s` 三件套（两次都 `CMP_OK_A` / `CMP_OK_B`）。
- 全文最终 sha256：`3dbf72d60381be104c1d337178fead0b08687bf8c3c0af15f3e2fb0fca626181`（§3.1/§3.2 的 `370aa…` 是注释微调前的同内容版本，之后只改了一段注释文字，再未动逻辑）。

---

## 4. 测试账目

`test/p11_lifecycle_test.dart` —— 12 组，全绿：

| 组 | 用例 | 钉住什么 |
|----|------|----------|
| L1-1 | endSession：清 combat / requestsBySeat / pending，成员 / 日志 / `meta.ended` / **存档**不受影响 | 缺陷 1 主靶 |
| L1-2 | closeRoom：同样清，但 `meta.ended` 仍不置真 | 生命周期三兄弟口径不变 |
| L1-3 | closeRoom ×2 + endSession ×2 幂等 | 终态但对象还在 |
| L1-4 | 结团后重连 → `sync` 里 combat=null、requests=[] | 用户可见症状（幽灵卡片） |
| L2-1 | 第 1 回合损失 7 → 推进第 2 回合损失 3 → 回退到第 2 回合 ROUND 之前 → `sanLostThisRound == 7`、`roundStartSan == 50`（改前 3 / 46） | 跨回合 |
| L2-2 | 同回合两次损失 7 + 3 → 撤销第二次 → 7（改前 10） | 同回合 |
| L2-3 | 回退到建团基线（seq 0）→ 四张表全空 | 深回退 |
| L2-4 | `fireUsed` 跨回合回退 → 空（改前留着 2，枪打不出去） | fireUsed |
| L2-5 | `fireUsed` 同回合回退 → 也按 0 起算 | fireUsed 口径 |
| L2-6 | 潜在疯狂在第 1 回合武装 → 边界 disarm → 回退到第 1 回合 → 重新 `true`（改前 false） | fadedArm 方向（该复发的要复发） |
| L2-7 | 转入潜在疯狂发生在边界**之前** → 回退后仍 `false` | fadedArm 反向护栏（不许误武装） |
| L2-8 | 不回退时 `advanceRound` 照旧清零 | 正常路径零影响 |

### 全量口径

| 项 | 数字 |
|----|------|
| 基线 | 1959 组全绿 |
| 本次新增 | +12 组（`p11_lifecycle_test.dart`） |
| **实测全量** | **1980 组 `All tests passed!`** |
| 差额来源 | 同一工程内另一位工程师同期新增了 `test/p11_status_bar_test.dart` 等用例、并删掉了 `test/zz_probe_status_test.dart`（探针文件）；净额 +9 |

`flutter analyze`：`No issues found! (ran in 6.1s)`。

---

## 5. 过程中撞到的一处「假红」（记录备查）

中途一次全量跑出 `room_ui_pl_test.dart` 的「旁观者属性显示 STR —」失败。排查结论：**与本次修复无关** —— 同一工程里另一位工程师当时正在改 `lib/ui/room/widgets/gp_pl_char_card.dart`（文件 mtime 13:09，失败用例正是该卡片的渲染断言），他保存完成后同一用例立刻恢复绿；本次改动没有触碰 `lib/ui/**` 下任何文件。

另：曾尝试把 `state['requests']` 一并清空（见 §1.3-4），`qa_p4_fresh_oracle_test` 立即报 `F:1#2024 / $.state.requests：数组长度 0 ≠ 期望 1` —— 这条正是"与旧版逐字段等价"的闸门，据此把清理范围收回到 `combat + requestsBySeat + pending`。

---

## 6. 改动清单（严格限定）

| 文件 | 改动 |
|------|------|
| `lib/domain/room_model_rollback.dart` | ① 头部注释 + `import 'madness_state.dart'`；② `rollback()` 增加 `_realignRoundScopedState(target)` 调用；③ 新增 `_realignRoundScopedState`；④ `closeRoom` / `endSession` 改走 `_clearTransientOnLifecycleEnd`（新增） |
| `test/p11_lifecycle_test.dart` | 新建，12 组 |
| `_p11_lifecycle_report.md` | 本报告 |

**未动**：`lib/ui/**`（一个字都没改）、`room_model_host_intent.dart`、`room_model_actions_sheet.dart`、`room_model_reduce.dart`、`room_types.dart`、`room_model_host_core.dart`、`pubspec.yaml`、任何 fixture。

### 已知边界（不在本缺陷范围，仅记录）

1. **回退不回滚花名册里的 sheet**：`rollback` 重建的是 `state`，成员角色卡（`roster`）是命令式写入的、不从事件流重放（`state['members'] = members()` 用的是当前花名册）。所以「角色卡上的精神状态 / 血量」这类看 `roster` 的字段回退后不会变 —— 这是既有架构口径，本次没扩大范围（`fadedArm` 的重算因此以「目标态花名册里的 `mental`」为收口依据）。
2. **玩家设备上的 `state['requests']`**：靠 `/sync` 的 `_requestsView` 重建（数据源已清），在线玩家的本地镜像要到下一次全量同步才消失；`closed` / `ended` 后 UI 已在终态门内，不构成幽灵卡片。
