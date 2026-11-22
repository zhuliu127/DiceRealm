# P11 修复批 · 意图层 3 处缺陷（fix2-intent）

改动文件（**只有这两个**）：

- `lib/domain/room_model_host_intent.dart`（生产代码，唯一改动文件）
- `test/p11_fix_intent_test.dart`（新建，12 组）

未触碰 `lib/ui/**`、`room_model_actions_sheet.dart`、`room_model_host_core.dart`、
`room_model_actions_room.dart`、`room_rules_sheet.dart`、`pubspec.yaml`。

文件哈希（改前 → 改后）：

```
改前 6b88c696b08c31ff7fa3f13439afbe1a7fc7017785ac843b54ae865303f0bb63
改后 090a9231ad707c9c919a16f08e532ba5cb9dbb0a3d9035687b116c7146da012b
```

---

## 一、任务 1（P0）· `consent` 同意后状态不落地

### 改前

`consent()` 同意分支只有三步：`settleRequest` → `syncMembers` → 一条
「KP 调整了 X 的状态」公共日志。**没有任何字段被写入**。

后果：KP 请求扣该玩家 HP → 玩家点同意 → 待办卡消失、日志照发 → HP 一点没变，
HP 归零也不判濒死/昏迷（`applyStatusJudgment` 从未被调用）。

### 改后

`settleRequest` 之后、`syncMembers` 之前插入落地链（`room_model_host_intent.dart:394-441`）：

```
req['payload']（{hp,san,mp}）
  → 译成 {status:{currentHP,currentSAN,currentMP}}（raFinite 逐个转换）
  → stateApply(seat, change, {})
  → applyStatusJudgment(m, change, seat, {sanBefore,hpBefore,bodyBefore,flagsBefore})
  → 最后照旧 syncMembers + 一条公共日志（未重复发）
```

### 为什么这么改

1. 老 APP `room-model.js:1572-1610`（v2.6.0 / v2.8.0 / v2.10.0 R5）就是这么做的，
   `stateSelf` 与 `consent` 共用同一条落地路径；本工程 `stateApply` + 上限夹取
   + runtime 记账也都在 `stateApply` 里，绕过去写字段会丢夹取与 runtime。
2. **`change` 在 `req['payload']`，不在 `p['change']`**。玩家点「同意」发的是
   `{id, agree}`（`p` 里根本没有 change），只有权威端 `requestsBySeat[seat]`
   里那条记录才存着 `{hp,san,mp}`（创建处 `room_model_actions_sheet.dart:660-695`
   `rec['payload'] = change`）。
3. 不调用 `sheetActionConsentApply`（它在别人负责的文件里），逻辑内联在本文件。

### `applyStatusJudgment` 的「第 4 参数传 null」语义结论（关键）

**结论：传 null 时内部读的是「改后」的值，所以 before 必须在 `stateApply` 之前取好。**
逐项证据（`room_model_actions_sheet.dart:704-813`）：

| 内部变量 | 传 null 时的实际取值 | 后果 |
|---|---|---|
| `prevBody` | `oBody == null` → `bodyView(status)`，即**改后**状态 | 归零分流拿「已变成重伤」的 body 做 prevBody，判据错位 |
| `dyingBefore` / `unconsciousBefore` | 无 `flagsBefore` → 直接读 `status[...]`，即**改后** | `dyingChanged` 永远为 false → 「刚进入濒死」不落盘 |
| `hpBefore` | `null` → `hpChanged = true` 但 `amountNow` 恒 0 | 伤害量丢失，`raDeriveBodyFromHp` 的 `amount > maxHP`（秒杀）与 `isMajorHit`（重伤）两条分支永远走不到 |
| `oSan` | `null` → `if (oSan != null && sanNow > 0)` 整段跳过（:798） | **净减 SAN 判定完全不执行** |

因此本修复先取 4 个 before 值（`sanBefore = raMemberStatusValue(currentSAN)`、
`hpBefore = currentHP`、`bodyBefore = bodyView(status)`（**视图**，不是裸
`status.body`）、`flagsBefore = {dying, unconscious}`），再 `stateApply`，
再带 opts 调 `applyStatusJudgment` —— 与老 APP 的
`sanBeforeConsent / hpBeforeConsent / bodyBeforeConsent / flagsBeforeConsent`
一一对应（`room-model.js:1585-1592`）。

### 验收（`test/p11_fix_intent_test.dart` T1-1 ~ T1-6）

- `{hp:5}` 同意 → `sheet.status.currentHP == 5` **且** `runtime.hp == 5`，未濒死；
- `{hp:0}` 同意（5→0，`5*2 < maxHP12`）→ `currentHP == 0`、`unconscious == true`、
  `bodyView == '昏迷'`（归零分流确实跑了）；
- 拒绝 → HP 仍 10、`runtime.hp` 仍为 null、待办清空；
- `{san:45, mp:3}` → `currentSAN 45` / `currentMP 3`（runtime 同步）；
- `{hp:999}` → 夹回 `maxHP 12`（证明走的是 `stateApply` 而不是直写）；
- 同意后公共日志「KP 调整了…的状态」**恰好 1 条**（不重复）。

---

## 二、任务 2（P0）· `confirmPending` 缺 120 秒 TTL

### 改前

`confirmPending` 只做「按 op+by 找到待办 → `removeAt` → 拒绝/执行」，全库**没有任何
过期闸门**。KP 昨天点过「解散房间」但没确认，待确认项一直挂在 `pending` 里，
今天点一下就真结团。

### 改后

1. 新增文件级常量（`:34-40`）：

```dart
/// 二次确认（confirmPending）的有效期：120 秒。
/// 来源：老 APP `room-model.js:1626` `CONFIRM_TTL_MS = 120000`（v2.13.6，…）
const int kConfirmTtlMs = 120000;
```

2. `confirmPending` 在 `removeAt` 之后、`agree` 判定之前加闸门（`:479-490`）：

```dart
final age = now() - jsNum(entry['at']);
if (age > kConfirmTtlMs) {
  pushInto(out, sysTo(seat, '这条确认已过期（超过 2 分钟），请重新操作'));
  return out;
}
```

### 为什么这么改

- 语义与老 APP `:1643-1651` 对齐：过期项先**摘掉**（否则每次点击重复提示）、
  只给 KP 一条**私信**（`sysTo` → `RoomEvt.private_` / `vis=seat` / `to=KP`，
  不污染公共流）、**不执行**动作；「拒绝过期项」同样作废（闸门在 agree 之前）。
- 时间基准用工程注入的 `now()`（`JsClock`），**没有**引入裸 `DateTime.now()`。
- `at` 缺失按 `jsNum(null) == 0` 处理 → `age` 巨大 → 同样过期，与老 APP
  「at 缺失的老数据按 0 处理」一致（老存档升级后不会突然「复活」一条待办）。

### 验收（T2-1 ~ T2-4）

- `at = now-180000` + `room.end` → 无 ENDED 事件、`meta.ended` 未置真、`pending` 清空、
  KP 收到 `private` 且文案含「已过期」；
- `at = now-10000` → ENDED 事件发出、`meta.ended == true`、无过期提示；
- 边界 119 秒执行 / 121 秒作废；
- `at` 键缺失 → 视为过期。

---

## 三、任务 3（P1）· `stateSyncAck` 写错字段

### 改前

```dart
List<SendPlan> stateSyncAck(String seat, Map<String, Object?> p) {
  stateSeq += 1;      // ← 错
  return const <SendPlan>[];
}
```

`stateSeq` 是**权威端状态版本号**（`stateApply` 每写一次卡才 +1，客户端按它做
幂等）；玩家回执把它 +1，等于骗所有客户端「又有一版新状态」。

### 改后（`:499-508`）

```dart
final m = roster.get(seat);
if (m != null) m['stateAckSeq'] = jsNum(p['seq']);
return const <SendPlan>[];
```

对齐老 APP `room-model.js:3967-3970`：
`var m = this.roster.get(seat); if (m) m.stateAckSeq = num(p && p.seq, 0);`
`stateSeq` 完全不动。

### `stateAckSeq` 现状与「是否进快照」

- 改前 `grep -rn "stateAckSeq" lib/` **零命中**（字段不存在，回执的记账根本没记）。
- 写法：成员是自由形状 `Map<String,Object?>`（`room_model_log.dart:76-77`），
  与 `lastTempCommitRound` 那类内存字段不同，**不需要新增类字段**，直接写在
  member map 上即可；不需要白名单注册。
- **进存档**：`save()` 的 `'members': roster.dump()`（`room_model_save.dart:81`），
  而 `RoomRoster.dump()` 是**整表 clone**（`room_model_log.dart:159-161`）→
  `stateAckSeq` 自动进存档，无需改序列化。与老 APP `room-model.js:6895`
  `members: this.roster.dump()` 同形。
- **不进回退快照**：`snapshots` 里存的是 `state`（事件归约产物），只有
  `MEMBERS` 事件才会刷新 `state['members']`；`stateSyncAck` 按老 APP 是**静默
  记账、不发事件**（T3-1 断言 `plans` 为空），所以快照里没有它 —— 与老 APP
  完全一致（老 APP 也只在 roster 上记账）。回退后 `stateAckSeq` 归 0 是既有
  语义，不是本次回归。

### 验收（T3-1 / T3-2）

- `stateSyncAck('p1', {seq:7})` → `roster.get('p1')['stateAckSeq'] == 7`、
  `stateSeq` 不变、返回空计划；
- 连发 7 → 9 → 记为 9（后到覆盖先到），`stateSeq` 恒定；
- `save()` 的 `members` 行里 `stateAckSeq == 9`（存档确证），`save().stateSeq == 0`。

---

## 四、反向自证伪（三处各注入一次错误，实测输出）

备份：`cp lib/domain/room_model_host_intent.dart /tmp/host_intent.fixed.dart`
（`sha256 090a9231…012b`）；每次恢复后 `cmp -s` + `sha256sum` 双校验。

### 注入 A · 注释掉 consent 的 `stateApply`

```
injected A
00:00 +8 -4: Some tests failed.
```

真红 4 组：**T1-1**（currentHP 仍 10）、**T1-2**（不判昏迷）、**T1-4**（SAN/MP 不动）、
**T1-5**（999 不夹取）。T1-3（拒绝）与 T1-6（日志条数）按预期仍绿 —— 它们钉的是
「不该发生的事」，不依赖落地。

恢复：`090a9231ad707c9c919a16f08e532ba5cb9dbb0a3d9035687b116c7146da012b` / `RESTORE_A_OK`

### 注入 B · `kConfirmTtlMs = 0`

```
injected B
00:00 +10 -2: Some tests failed.
```

真红 2 组：**T2-2**（10 秒前的确认被当过期，不结团）、**T2-3**（119 秒边界被作废）。
T2-1 / T2-4 仍绿（它们本来就断言「过期」）。

恢复：`090a9231…012b` / `RESTORE_B_OK`

### 注入 C · `stateAckSeq` 退回 `stateSeq += 1`

```
injected C
00:00 +10 -2: Some tests failed.
```

真红 2 组：**T3-1**（`stateAckSeq` 不存在 + `stateSeq` 被推进）、**T3-2**（存档里
`stateAckSeq != 9` 且 `stateSeq != 0`）。

恢复：`090a9231…012b` / `RESTORE_C_OK`

三次恢复后复跑：`flutter analyze` → `No issues found!`，
`flutter test test/p11_fix_intent_test.dart` → `+12: All tests passed!`。

---

## 五、测试账目

| 项 | 结果 |
|---|---|
| `flutter analyze` | **No issues found!**（4.9s） |
| `flutter test test/p11_fix_intent_test.dart` | **+12 全绿**（T1×6 / T2×4 / T3×2） |
| `flutter test`（全量） | **+1952 全绿**（基线 1934；本文件新增 12 组；其余 +6 组来自同期他人用例 `p11_authz_ready_test.dart` / `p11_fix2_sheet_test.dart`，非本文件） |
| `flutter clean` | 未执行 |
| 断言放宽 | 无 |

新增用例数：**12 组**（超出要求的 8-10 组，因为 consent 单独拆了 6 条覆盖
sheet/runtime/夹取/日志/拒绝/归零）。

## 六、范围声明

只改了 `consent` 同意分支、`confirmPending` 的过期闸门、`stateSyncAck` 的记账字段。
`afterSanLoss` / `detachPeer` / 越权与文案修复**未触碰**（越权与文案由他人在
`room_model_host_intent.dart` 之外的批次已完成；本次改动未与其产生重写）。
