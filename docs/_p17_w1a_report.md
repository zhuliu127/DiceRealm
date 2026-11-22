# P17 波1-A 报告 · 申请推送链路修复（KP-1）

- 施工：`p17-w1a`「寇豆码」（Flutter 工程师）
- 工程根：`$P = C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`（改前 v2.29.0+99）
- 依据：`_p17_construction_spec.md §0/§1/§2·KP-1/§4`、`_p17_bug_roots.md §2 全部`、`_p17_kp_landing.md §KP-1`
- 独占文件（只改了这三个）：`lib/ui/room/room_request_watcher.dart`、`lib/domain/room_model_host_intent.dart`、`lib/ui/room/sheets/sheet_treat.dart`

## 0. 一句话结论

同一玩家连续两次同 op 的高危申请，第二条以前**永不弹窗**（去重键不含待办自身区分信息）；本批把去重键改成唯一键、同步把 `confirmPending` 改成「首条匹配即停」（否则会从「漏弹第二条」变成「第一条永久残留」）、并给治疗弹层补一条本机「已提交」反馈。`_seen` 去重机制一字未动。

## 1. 环境与自检

```bash
source /d/dev/env.sh
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy
export NO_PROXY=127.0.0.1,localhost
```

```text
$ dart analyze lib/ui/room/room_request_watcher.dart lib/domain/room_model_host_intent.dart lib/ui/room/sheets/sheet_treat.dart
Analyzing room_request_watcher.dart, room_model_host_intent.dart, sheet_treat.dart...
No issues found!
```

- **未跑 `flutter test`**（并发写码期纪律）。
- 未改 `pubspec.yaml` / `pubspec.lock` / `lib/app_version.dart`；未 `flutter clean`；未碰 `build/`。
- 未改任何既有测试文件，未新建测试文件。
- 红线自检：两个 `lib/ui/room/**` 文件代理对 emoji 计数均为 **0**（`[\uD83C-\uDBFF][\uDC00-\uDFFF]` = 0；注释里的 `⚠️` 是 BMP + VS16，不在门禁范围）；未新增 `jsStr(`（`sheet_treat.dart` 仍只用 `roomText`，`p16_wave1_sheets_test.dart:651` 的源码扫描继续绿）。
- 未新增固定尺寸控件（`sheet_treat.dart` 的 kind 按钮 / `RoomTap` 尺寸一个没动）→ textScaler 1.3/1.5/2.0 口径不受影响。

## 2. 逐文件改动（含 sha256 与代码片段）

### 2.1 `lib/ui/room/room_request_watcher.dart`

- 改动前 sha256：`b7b94b8c8bb7295b3a006fb0ffb8f153020f2a84c1450458f7b9ad19df637e30`
- **改动后 sha256：`2803786b1a65560fbc14ad0c5e1eb33af87d43d021f4310ec5cb6eea226cd68a`**（425 行）

**① 新增私有函数 `_payloadSig`（:129-138）** —— 载荷签名，`jsonEncode` 失败回空串，与 `_fmt` 同口径，保证弹窗链路不会因一条脏载荷整段抛：

```dart
String _payloadSig(Object? v) {
  try {
    return jsonEncode(v);
  } catch (_) {
    return '';
  }
}
```

**② 去重键改唯一（:169-199，主修）**

```dart
      /* ★ P17 KP-1①（本批主修）：去重键必须带 pending 项**自身的区分信息**。
         改前只用 `op + by`：同一玩家连续两次同名高危动作（例如两次
         `aid.apply`、只是 targetSeat / skill 不同）…… 两条 id 撞成一个
         → `_seen.add`（`_onSession`，本文件 :299）第二次返回 false → **第二条申请永不弹窗**。
         可用键只有 `act()` 入队处写入的那五个
         （`room_model_host_intent.dart:324-330`）：`by` / `op` / `p` / `need` /
         `at`（入队毫秒）。pending 项**没有** `id` 字段 —— 只有 `state.request`
         那条有 `r$localSeq`（`room_model_actions_sheet.dart:665-666`），而它没有
         `op`、已被上面 `op.isEmpty` 跳过，所以不能照抄 `q['id']`。
         ⚠️ `payload` 仍必须是 `{op, by}`：domain 的 `confirmPending` 按 op+by
         定位待办，加字段会让确认链路对不上。 */
      final sig = _payloadSig(asMap(q['p']));
      out.add(RoomPushRequest(
        id: 'pending:$op:$by:${roomText(q['at'])}:$sig',
        title: '待确认：$op',
        ...
        reply: RoomPushReply.confirm,
        payload: <String, Object?>{'op': op, 'by': by},   // ← 一字未动
      ));
```

**为什么用「`at` + 载荷签名」而不是「`q['id']`」**（`_p17_construction_spec.md §2·KP-1` 要求「用真实存在的键，不要臆造」）：

- `act()` 入 pending 的那条只有 `by / op / p / need / at` 五个键（`room_model_host_intent.dart:324-330`，**没有 `id`**）；`q['id']` 在这条上是 `null`，照抄会退化成 `pending:null:aid.apply:p1`，仍然撞键。
- 唯一性论证：`act()` 的防重复按 `by + op + jsonEncode(p)` 判重（`:307-323`），**同签名不可能同时存在两条**；因此 `(by, op, at, sig)` 四元组在同一时刻的 `pending` 里必然唯一（`at` 区分先后，`sig` 兜住同一毫秒入队）。
- 稳定性：同一条 pending 项在多次 `collectRoomPushRequests` 调用里字段不变 → 生成的 id 不变 → `_seen` 语义不变（**同 id 仍只弹一次**）。
- **`_seen` 零改动**（`final Set<String> _seen` :261，`_seen.add` :299，首次挂载 `_seen..clear()..addAll(...)` :282-284）——没有 remove、没有定期清理。P10 刻意设计原样保留，`p10_t6_room_fixes_test.dart:562`（5D）继续咬得住。

**③ `RoomPushRequest.id` 文档（:86）** 从 `pending:<op>:<by>` 改成 `pending:<op>:<by>:<入队时刻>:<参数签名>`。

### 2.2 `lib/domain/room_model_host_intent.dart`（domain 冻结文件）

- 改动前 sha256：`202ccc528fcfcd01c64636d2093508bb6e60f04f71a3e01635a9259e41567462`
- **改动后 sha256：`202ccc528fcfcd01c64636d2093508bb6e60f04f71a3e01635a9259e41567462`** → 见下方 §3.0「哈希说明」

**唯一改动：`confirmPending` 的 `for` 循环加 `break`（:482-504）**

```dart
    final op = jsStr(p['op']);
    var idx = -1;
    for (var i = 0; i < pending.length; i++) {
      if (pending[i]['op'] == op && pending[i]['by'] == p['by']) {
        idx = i;
        /* ★ P17 KP-1②：摘到**第一条**匹配就必须停（原来这里没有 break，
           `idx` 会被循环覆写成最后一条匹配项）。…… */
        break;
      }
    }
```

其余（`removeAt` / 120 秒 TTL / `agree` 判定 / `applyAction(entry['by'], entry['p'])`）**逐行未动**。

### 2.3 `lib/ui/room/sheets/sheet_treat.dart`

- 改动前 sha256：`3a454bcb10a87c4071142b792a3bf662d7708a5bb3fa9695e9060f3d3601706f`
- **改动后 sha256：`3a454bcb10a87c4071142b792a3bf662d7708a5bb3fa9695e9060f3d3601706f`** → 见 §3.0

**`_submit` 提交后补一条本机提示（:122-134）**

```dart
    widget.ctl.hostAction(kind.op, payload);
    /* ★ P17 KP-1⑤：…… domain 侧的「已提交，等待确认」是 `sysTo` 定向系统提示
       （`room_model_host_intent.dart:331-339`），只发**发起玩家**……
       这里只补一条本地 banner …… 把「等 KP 同意、不会立刻结算」说清楚。 */
    widget.ctl.notice('已提交${kind.label}申请，等待 KP 同意');
    Navigator.of(context).pop();
```

- 载荷（`seat` / `targetSeat` / `skill`）、`pop()` 位置、三个 kind 按钮的纯 `setState` 逻辑、`TreatSheetKeys` 全部常量：**一字未动**。
- `ctl.notice` 只写 `local.notice`（`room_controller.dart:155-159`），不弹模态、不发 intent，不叠 domain 提示。
- 顺序说明（写在代码注释里）：`RoomController.hostAction` 失败提示是 `notice('操作失败：…')`（`room_controller.dart:74-80`），三个 session 实现的 `hostAction` 都是 `async`（`room_session_local.dart:258` / `_cloud.dart:147` / `_remote.dart:102`），异常走微任务落地、**晚于**本行 → 真失败时「操作失败」会覆盖「已提交」，不会把错误盖住。

## 3. `confirmPending` 改动的影响分析（单独一节）

### 3.0 先解释哈希（重要，别误判成没改）

上面两个文件的「改动前/后 sha256 相同」是**我的记录疏忽**：我在第一次 `sha256sum` 之前就完成了对这两个文件的编辑，所以所谓「改动前」抓到的是「已改后」的哈希。**两个文件确实都改了**（`grep` 可直接验证）：

```bash
grep -n "P17 KP-1②" lib/domain/room_model_host_intent.dart        # :487
grep -n "已提交\${kind.label}申请" lib/ui/room/sheets/sheet_treat.dart  # :133
```

波4 / 波5 请以**当前磁盘内容的 `sha256sum`** 为准（=`202ccc52…` / `3a454bcb…`），不要拿本表做「改动前」基线。真实改动前基线请从 git / 备份取。

### 3.1 改了什么

`lib/domain/room_model_host_intent.dart:484-504`：`for` 循环里命中第一条 `(op, by)` 就 `break`，`idx` 固定为**最早入队**的那条；其余逻辑不变。

### 3.2 为什么必须改（不修会造出更糟的 bug）

改前 `idx` 被覆写成**最后一条**匹配。以前用户看不到问题，是因为 UI 去重键不唯一、同 op 同 by 的第二条**根本不弹**（只有一条能点）。本批把去重键改唯一后两条都会弹，此时：

- 点第 1 条「同意」→ domain 摘掉**最后**一条（应用的是第 2 条载荷）；
- 点第 2 条「同意」→ 摘掉剩下那条（应用第 1 条载荷）；
- 若第 1 条被「拒绝 / 点屏障关闭」，则第一条**永久残留**在 `pending`，`GpStatus` 会一直挂一张「待确认」卡，且 120 秒后点它只回「已过期」。

即：**不修 `confirmPending`，KP-1 会从「漏弹第二条」变成「弹两条、同意一条、另一条再也消不掉」**（`_p17_bug_roots.md §2.5 建议 1「连锁残留风险」`）。

### 3.3 为什么按 `op+by` 首条匹配，而不改成「按唯一 id 精确匹配」

读了代码后的结论是：**本批不能改成唯一 id 匹配**，依据：

1. CONFIRM 载荷契约就是 `{op, by, agree}`，三个调用点都是这么发的：`RoomController.dangerAction`（`room_controller.dart:95-104`）、`GpStatus` 的待确认卡（`gp_status.dart:142` → `_confirm(controller, op, by, agree)`）、`GpCombatList` 的待确认卡（`gp_combat_list.dart:100-109`）。改载荷要同时改这三处 + watcher 的 `payload`，而施工单明确「`payload` 仍必须是 `{op, by}`，不许改」。
2. 待办项**自身没有 id 字段**（`act()` 入队处只写 `by/op/p/need/at`，:324-330）。要按 id 精确匹配，得先在 domain 给 pending 加 `id`，那会改变 `hostRead.pending` 的形状（`GpStatus`/`GpCombatList`/watcher 三处消费者都要跟着改），且 `pending` 属于老存档快照字段（`room_model_save.dart` 序列化，`_p17_bug_roots.md` 未做安全评审）→ 超出本批范围，风险大于收益。
3. **首条匹配与用户看到的顺序天然对齐**：`collectRoomPushRequests` 按 `read.pending` 数组顺序产出、watcher `_queue` 按入队顺序消费、`_drain` 一次只弹一条 → 「先弹的那条 = 先摘的那条」，FIFO 语义正确。
4. 唯一残留的理论缺口（**已登记，不修**）：第 1 条弹窗用「点屏障」关掉（不发 intent）、第 2 条弹窗点「同意」→ 应用的是第 1 条载荷（最早入队那条）。这与改前「只摘最后一条」相比是**严格更正确**的方向（改前是「应用最新一条、把最早那条永久卡住」），且用户点屏障关闭本身就等于跳过、后续仍可在 `GpStatus` 里按卡片逐条处理。

### 3.4 为什么不会改变既有 oracle 契约

- **未碰** `oracle_*` 测试、`test/fixtures/room_actions.json`、`test/fixtures/room_model.json`（`_p17_construction_spec.md §0.4` 红线）。这三处都**不含** `confirmPending` 的场景：`room_actions.json` 里 `"confirm"` 只出现在 POLICY 字段（`:7020` 起的 `"confirm": null / "kp" / "owner"`），没有「两条同 op 待办再确认」的用例。
- `confirmPending` 的**输出形状**、TTL 语义、`sysTo` 文案、「非 KP → 无权限」守卫全部逐行未动；单条待办场景下（所有既有用例都是单条）`break` 与原来**完全等价**——第一次命中即最后一条，`idx` 相同。
- `act()` / `consent()` / `settleRequest()` / `stateRequest()` 零改动；`pending` 的字段集合零改动。
- 因此 domain 的对外可观察契约只有一处变化：**「同 op + 同 by 存在多条待办时，确认哪一条」** —— 从「最后一条」变为「最早一条」。这是修 bug 的必然结果，不是契约放水。

### 3.5 可能因 `confirmPending` 转红的既有测试（逐条判定）

| 用例 | 是否红 | 依据 / 建议口径 |
|---|---|---|
| `p11_fix_intent_test.dart:211` T2-1 / `:229` T2-2 / `:245` T2-3 / `:269` T2-4 | **绿** | `h.pending` 恒单条（`queueEnd` 后 `hasLength(1)`），首条即最后一条 |
| `p10_t1_cloud_room_test.dart:487` | **绿** | 单条 `room.end` 确认 |
| `qa_p4_alias_actions_test.dart:117/129` | **绿** | 单条 |
| `room_ui_blocks_test.dart:396/439/494` | **绿** | 断言的是 CONFIRM 载荷字段，不涉及多条匹配 |
| `room_ui_confirm_flow_test.dart:98/154/181` | **绿（预计）** | 每条用例只 `hostAction` 一次 → `pending` 长度 1（`:118`/`:165` 显式断言 `pending.length == 1`），`break` 不改变结果 |
| `room_ui_kp_test.dart:406` | **绿（预计）** | `:435` 只发一次 `state.edit.self`，且断言的是 `{op, by, agree}` 载荷（未变） |
| `room_ui_player_test.dart:169` | **绿（预计）** | 单条 `state.request` → 玩家 CONSENT 路径，不经 `confirmPending` |

> 若波4 全量跑出以上任何一条红，**先查是否有人加了「两条同 op 待办」的前置**；本文件集内没有这种新增。真红的话建议口径：断言改为「首条确认后剩余待办 = 第二条 + 两条都能被消费」，不要放宽为 `isNotEmpty`。

## 4. 交给波3 的接手说明：`c$localSeq` 全体推送 id 冲突（**我没有这个文件，一行未动**）

### 4.1 位置与现象

- 文件行号：`lib/domain/room_model_actions_combat.dart:1326-1327`（`localSeq += 1; final id = 'c$localSeq';`），复用点 `:1347`（写入 `requestsBySeat[t]` 的 `rec['id']`）与 `:1360-1362`（定向 `RoomEvt.request` 的 `id`）。
- 现象：`checkRequest` 在 `for (final t in targets)`（`:1338`）**循环外**只生成一次 id，N 个 target 共用同一个 `cN`。KP 读 `hostRead.requestsBySeat` **全量**（`room_request_watcher.dart:196-208`），一次「全体检定」会产出 N 条 id 相同的 `RoomPushRequest` → `_seen.add` 只认第一条 → **KP 只弹 1 次**（第 2 个玩家那条永不弹）。

### 4.2 建议改法与两个必须同步的点

**方案 A（推荐，最小）**：domain 侧把 id 改成逐 target 唯一 —— `final tid = 'c${localSeq}_$t';`，写入 `rec['id']`（`:1347`）与 `emit(RoomEvt.request ... 'id': tid)`（`:1362`）**两处必须同改**。

- 理由：玩家点「同意」时 `consent(seat, {'id': ...})` 按 `requestsBySeat[seat]` 里的 `r['id'] == p['id']` 定位（`room_model_host_intent.dart:346-361`）；只改一处会让玩家点同意时找不到卡片（回「这条请求已经处理过了」）。
- `settleRequest(seat, id, ...)` 也是按 id 摘（`room_model_actions_combat.dart:1301-1305`），同一 id 必须贯通。

**方案 B（若不想动 domain）**：在 UI 侧给去重键拼 seat —— 落点在**我的文件** `lib/ui/room/room_request_watcher.dart:197-208`（② 段）：

```dart
id: '${entry.key}:$id',      // 只改去重键
payload: <String, Object?>{'id': id},   // ★ 必须保留裸 id（domain CONSENT 按它定位）
```

- 我**没有**采用方案 B，原因：① 施工单把 `c$localSeq` 明确划给波3；② 若波3 采用方案 A，UI 再拼一次 seat 会产生双重前缀（无害但要重复协调）。**请波3 二选一并回写结论。**

### 4.3 相邻发现（同样是「id 撞车」，但不在我的文件集，登记不清）

1. `lib/ui/room/widgets/gp_status.dart:136` / `:148`：待确认卡 key 用 `'pending:$op:$by'`、请求卡 key 用裸 `r['id']`。同 op 同 by 的两条待办、或全体检定的 N 条同 id 请求，会在同一个 `Column` 里产生**重复 `ValueKey`** → debug 下 `Duplicate keys found` 断言。这在本批之前就存在（`pending` 里真能同时有两条同 op 同 by），但 P17 让两条都能弹之后用户更容易撞上 → 建议顺手把 key 与去重无关地加 `at`/seat 后缀（**只改 key，不改 `id` 入参**，`GpStatusKeys.request(id)` 的既有断言需同步）。
2. `lib/ui/room/widgets/gp_combat_list.dart:99`：`'combat-pending:$op:$by'`，同上。
3. KP 侧 `requestsBySeat` 的推送是 `reply: RoomPushReply.consent`，但 KP 点「同意」发的是 `INTENT.CONSENT{id}`，domain 的 `consent(seat,...)` 读的是 `requestsBySeat[kHostSeat]` → 恒空 → 回「这条请求已经处理过了」。**这是既有的语义怪点**（KP 能看到别的 seat 的待办卡却点不动），不是本批引入，登记给后续批次。

## 5. 验收用例口径（给波4 写测试用）

> 硬要求：**不许复用** `p10_t6` 的纯 watcher 夹具、`p16_wave1_sheets_test.dart` 的 `_OpenButton` 夹具。必须把 `RoomRequestWatcher` 与业务弹层放进**同一棵树**，并构造**连续时序**（`_p17_bug_roots.md §2.7`）。
> 可复用：`test/support/room_ui_harness.dart` 的 `RoomUiFixture / mountRoom / useRoomScreen / _settle`、`f.host.pending`、`f.plSessions['p1']!.hostAction(...)`、`f.sessionOf(kHostSeat)`、`RoomPushKeys`、`TreatSheetKeys`、`openTreatSheet`。

### 甲 · 连续时序：先弹一次推送并关闭 → 再开治疗弹层仍可点（复现「点了没反应」）

```dart
final f = RoomUiFixture();
await f.boot(inGame: true);
useRoomScreen(tester, 900, 1600);
// 夹具：写一个宿主按钮（RoomTap），onTap: () => openTreatSheet(ctx, ctl: f.controllerOf('p1'))
// 树形：MaterialApp.builder 里 f.scoped('p1', child: RoomRequestWatcher(child: 宿主))
await tester.pumpWidget(_watcherHost(f, 'p1'));

// ① KP 给 p1 推一条状态变更请求 → p1 弹窗
await pushRequest(f, 'p1', '甲变体说明');       // p10_t6 现成 helper
await _settle(tester);
expect(find.byKey(RoomPushKeys.root), findsOneWidget);

// ② 关掉推送
await tester.tap(find.byKey(RoomPushKeys.agree));
await _settle(tester);
expect(find.byKey(RoomPushKeys.root), findsNothing);

// ③ 再开治疗弹层点第一个 kind
await tester.tap(find.byKey(_openTreatKey));
await _settle(tester);
expect(find.byKey(TreatSheetKeys.root), findsOneWidget);
await tester.tap(find.byKey(TreatSheetKeys.kind('急救')));
await tester.pump();

// ④ 必须进第二步（bug 存在时这两条红）
expect(find.textContaining('当前：急救'), findsOneWidget);
expect(find.byKey(TreatSheetKeys.target('p2')), findsOneWidget);
expect(tester.takeException(), isNull);
```

补充（KP 视角同一时序）：`mountRoom(tester, f, kHostSeat)` + `f.plSessions['p1']!.hostAction('aid.apply', {...})` → 弹窗 → 点「同意」→ `f.host.pending` 清空 → 再推第二条 → 仍须弹窗。

### 乙 · 同玩家连续两次同 op 申请 → 必须弹两次（本次主修的唯一判据）

```dart
final f = RoomUiFixture();
await f.boot(inGame: true);
useRoomScreen(tester, 900, 1600);
await mountRoom(tester, f, kHostSeat);        // KP 视角，watcher 已挂

// ① 同 by 同 op、**参数不同**（否则 act() 的防重复会拒第二条）
await f.plSessions['p1']!.hostAction('aid.apply',
    <String, Object?>{'seat': 'p1', 'targetSeat': 'p1', 'skill': '急救'});
await f.plSessions['p1']!.hostAction('aid.apply',
    <String, Object?>{'seat': 'p1', 'targetSeat': 'p2', 'skill': '医学'});

// ② 纯函数层：两条都在、id 不同（改前这里长度是 1）
expect(f.host.pending, hasLength(2));
final reqs = collectRoomPushRequests(f.sessionOf(kHostSeat))
    .where((r) => r.reply == RoomPushReply.confirm).toList();
expect(reqs, hasLength(2), reason: 'B1-1：同玩家第二次同 op 申请必须也能弹');
expect(reqs[0].id, isNot(reqs[1].id), reason: '去重键必须唯一');
expect(reqs[0].payload.keys.toSet(), <String>{'op', 'by'},
    reason: 'payload 必须仍是 {op, by}');

// ③ 组件层：连续弹两条（先弹先关）
await _settle(tester);
expect(find.byKey(RoomPushKeys.root), findsOneWidget);
expect(find.descendant(of: find.byKey(RoomPushKeys.details),
    matching: find.textContaining('急救')), findsOneWidget);
await tester.tap(find.byKey(RoomPushKeys.agree));
await _settle(tester);

expect(find.byKey(RoomPushKeys.root), findsOneWidget,
    reason: '第一条处理完，第二条必须紧跟着弹（改前 HERE 是 findsNothing）');
expect(find.descendant(of: find.byKey(RoomPushKeys.details),
    matching: find.textContaining('医学')), findsOneWidget);
await tester.tap(find.byKey(RoomPushKeys.agree));
await _settle(tester);
expect(find.byKey(RoomPushKeys.root), findsNothing);
expect(f.host.pending, isEmpty, reason: '两条都要被消费，不能残留');
```

### 丙 · `confirmPending` 首条匹配（钉住 domain 改动）

```dart
// 前置同乙 ①（pending 两条、顺序 = 急救 → 医学）
await f.kpSession.sendIntent(RoomIntent.confirm,
    <String, Object?>{'op': 'aid.apply', 'by': 'p1', 'agree': true});
expect(f.host.pending, hasLength(1));
// ★ 判据：剩下的是**第二条**（医学 / targetSeat p2），不是第一条
expect(asMap(asMap(f.host.pending.single)['p'])['skill'], '医学',
    reason: '改前会摘掉最后一条 → 这里剩的就是「急救」，本断言红');
// 再确认一次 → 清空，且第一条真的被执行过（两条都消费，不残留）
await f.kpSession.sendIntent(RoomIntent.confirm,
    <String, Object?>{'op': 'aid.apply', 'by': 'p1', 'agree': true});
expect(f.host.pending, isEmpty);
```

### 丁 · `_seen` 语义不变：同一 id 仍只弹一次

```dart
// 单条 pending → 弹一次 → 点同意 → 反复 refresh()
await _settle(tester);
expect(find.byKey(RoomPushKeys.root), findsOneWidget);
await tester.tap(find.byKey(RoomPushKeys.agree));
await _settle(tester);
for (var i = 0; i < 3; i++) {
  f.sessionOf(kHostSeat).refresh();     // 只发通知、不改数据
  await _settle(tester);
  expect(find.byKey(RoomPushKeys.root), findsNothing,
      reason: '同一 id 只弹一次（第 $i 次额外通知）');
}
```

### 戊（可选）· `sheet_treat` 提交反馈

```dart
await tester.tap(find.byKey(TreatSheetKeys.submit));
await tester.pump();
expect(f.localOf('p1').notice, contains('等待 KP 同意'),
    reason: '提交后必须有本机反馈（KP-1⑤）');
expect(find.byKey(TreatSheetKeys.root), findsNothing, reason: '提交后弹层照旧关闭');
```

### 反向证伪清单（波5 用，必须逐条咬得住）

| 改坏点 | 必须变红的用例 |
|---|---|
| 把 id 改回 `'pending:$op:$by'` | 乙（② 纯函数层 `hasLength(2)` 先红，③ 组件层第二条 `findsOneWidget` 红） |
| 删掉 `confirmPending` 的 `break` | 丙（断言「剩下的是医学」红） |
| 删掉 `ctl.notice(...)` | 戊 |
| 给 `_seen` 加 `remove`/`clear` 每次 `_onSession` | 丁（历史待办被重弹）与 `p10_t6` 5D 一起红 |

## 6. 预计会因本批行为变更转红的既有测试（逐条建议口径）

| 用例 | 预计 | 建议口径 |
|---|---|---|
| `test/p10_t6_room_fixes_test.dart:562` 5D「首屏已有 id 不弹；同一 id 只弹一次」 | **绿**（不必改） | 走 `state['requests']`（`r$localSeq`），id 构造未变；若波4 想加固，可加一条「KP 侧同 op 两条只各弹一次」的正向用例（见丁） |
| `test/p10_t6_room_fixes_test.dart:677` 5F「两条数据源分别验」 | **绿** | 未断言 id 字符串（`:695-699` 只查 `reply` 与 details 含「侦查」）；别顺手改 title/details 文案 |
| `test/room_ui_confirm_flow_test.dart:98`「同意 → 权威态真变 7」 | **绿** | `pending.length == 1` 单条，`break` 等价；如转红先查是否有人前置了两条 |
| `test/room_ui_confirm_flow_test.dart:154`「拒绝 → 数值不变、待办被消费」 | **绿** | 同上 |
| `test/room_ui_confirm_flow_test.dart:181`「旁观者打开同一弹层」 | **绿** | 不经 `confirmPending` |
| `test/room_ui_kp_test.dart:406`「确认仍走同一 confirm 载荷」 | **绿** | 载荷 `{op, by, agree}` 未变（`:448` 起逐字段断言） |
| `test/room_ui_player_test.dart:169`「完整链路…KP 同意 → 数值生效」 | **绿** | 单条 CONSENT |
| `test/p16_wave1_sheets_test.dart:610/615/620`（急救/医学/精神分析三分支） | **绿（需确认 harness 口径）** | `_submit` 新增 `ctl.notice` → `local.showNotice` 会 `notifyListeners()` 并挂 2s `Timer`；`room_ui_harness.dart:324` 的 `boot()` 把 `scheduleDismiss` 换成 `(_, _) => null`，**不产生 pending timer**，`:605` 的 `takeException() isNull` 应保持绿。若波4 改了 harness 的 `scheduleDismiss`，这组会因「A Timer is still pending」转红 → **不要改 harness**，改为在用例末尾 `f.localOf('p1').clearNotice()` |
| `test/p16_wave1_sheets_test.dart:645`「零 emoji / 零 jsStr( / 零权威快照赋值」 | **绿** | `sheet_treat.dart` 仍无 `jsStr(`、无代理对 emoji、无 `state[...] =` |
| `test/p11_fix_intent_test.dart:202` 组（TTL 四条） | **绿** | 单条 pending |
| `test/room_ui_blocks_test.dart:389/430/492` | **绿** | 这两个 id 是 `GpStatus`/`GpCombatList` 自己的 key（`'pending:room.close:p1'`），我没改；它们**不经过 watcher 的去重键** |

> 若某条真的转红，**首选口径**是「补更强断言」而不是放宽：加「同 op 同 by 两条各自可弹、各自可消费」的正向断言，保留原不变量逐字断言（`findsOneWidget` 不许降 `findsWidgets`）。

## 7. 声明

- **未跑 `flutter test`**（`_p17_construction_spec.md §4.1`）；只用 `dart analyze` 自检我这三个文件（零 error / warning / info）。
- **未修改任何既有测试文件**，**未新建测试文件**；验收用例以 §5 的「口径 + 骨架」形式交给波4 落地。
- **未碰别人的文件集**：`room_game_page.dart`、`gp_feeds.dart`、`gp_privates.dart`、`sheet_chat_composer.dart`、`gp_pl_char_card.dart`、`gp_map_stage.dart`、`stroke_painter.dart`、`lib/ui/home_page.dart`、`room_model_actions_combat.dart`、`gp_status.dart`、`gp_combat_list.dart` 一行未改（只在报告里登记后三个的接手点）。
- 未改 `pubspec.yaml` / `pubspec.lock` / `lib/app_version.dart`；未 `flutter clean`；未删/改 `build`。
- 版本号保持 v2.29.0+99，等波4 升 `2.30.0+100`。

## 8. 当前磁盘 sha256（最终交付基线）

```text
2803786b1a65560fbc14ad0c5e1eb33af87d43d021f4310ec5cb6eea226cd68a  lib/ui/room/room_request_watcher.dart   ← v1（仅去重键）
202ccc528fcfcd01c64636d2093508bb6e60f04f71a3e01635a9259e41567462  lib/domain/room_model_host_intent.dart
3a454bcb10a87c4071142b792a3bf662d7708a5bb3fa9695e9060f3d3601706f  lib/ui/room/sheets/sheet_treat.dart
```

（三个文件的行数：`room_request_watcher.dart` 425 行；`room_model_host_intent.dart` 改动点 :482-504；`sheet_treat.dart` 改动点 :122-134。）

### 8.1 ★ v2 修订（P17 KP-1-b：玩家申请到达 KP）后的**唯一基线**

```text
46b730a07d214e21e82105279c2dd8168aedeb5aceca1a88af6c56d98a17707e  lib/ui/room/room_request_watcher.dart   ← v2（500 行，含 KP-1-b）
202ccc528fcfcd01c64636d2093508bb6e60f04f71a3e01635a9259e41567462  lib/domain/room_model_host_intent.dart   （v1 之后未再改）
3a454bcb10a87c4071142b792a3bf662d7708a5bb3fa9695e9060f3d3601706f  lib/ui/room/sheets/sheet_treat.dart      （v1 之后未再改）
```

下文的 §9 / §10 是 v2 追加；§1~§7 仍然有效（去重键修复、`confirmPending` 首条匹配、治疗反馈都没被 v2 覆盖掉）。

---

# 9.（v2 追加）KP-1-b：玩家申请到达 KP 的链路核查

> 用户追加口径（原文）：「我是指玩家点治疗按钮了之后，KP 视角没有收到推送，无法同意。」
> 即**第一条**就该到、但没到。下面按四段逐段给结论 + 证据行号；结论是**前三段无断点，断点全在 watcher 的记账时机与弹窗兜底上**（v1 只修了「去重键」这一处），最终改法仍落在 `lib/ui/room/room_request_watcher.dart`。

## 9.1 段①玩家侧发起 —— 无断点

- 入口：`room_game_page.dart:1056-1066`（`if (!isKp)` 的「治疗」`RoomTap`）→ `openTreatSheet(context, ctl: RoomScope.read(context).controller)`（`sheet_treat.dart:72-84`）。
- 提交：`sheet_treat.dart:110-134` `_submit` → 载荷 `<String, Object?>{'seat', 'targetSeat', 'skill'}`（psycho 无 skill）→ `widget.ctl.hostAction(kind.op, payload)`。
- 控制器：`RoomController.hostAction`（`room_controller.dart:74-80`）= 仅 `try/catch` → `session.hostAction`，**无全局 busy / 无 throttle**（`throttle` 只被 `gp_pl_char_card.dart:256/:358` 两处调用，`_submit` 完全没用）。
- 三种会话的信封形状一致：`LocalLoopbackSession.hostAction`（`room_session_local.dart:258-267`）、`RemoteSession.hostAction`（`room_session_remote.dart:102-107`）、`CloudRemoteSession.hostAction`（`room_session_cloud.dart:147-154`）都是「外层 `op:'act'`、内层 `p['op']=action`」，远端经 `LanClient.sendAct` / `CloudRoomClient.sendAct` 打出**同一形状**（`lan_client.dart:271-278` / `cloud_room.dart:730-736`）。
- **结论**：发起段不会丢包；这条路径与 `state.edit.self`（P10 已端到端验过的 `RoomConfirm.kp` 动作）逐字同构。

## 9.2 段②是否进 pending —— 无断点（player 发起必然入队）

- `INTENT.ACT` 分发：`room_model_host_intent.dart:240-242` → `act()`（`:288-343`）。
- 权限：`needs('player','aid.apply')` = `allowed:true, confirm:RoomConfirm.kp`（`room_types.dart:311-314`；`needs` 实现 `room_model_state.dart:152-158`）。
- 入队判定：`confirm != null`（`:301-302`）；**只有「KP 自己发起 + 确认方也是 KP」才走 `applyAction`**（`:304-306`）→ player（`seat != kHostSeat`）一定走到 `:324-330` 的

  ```dart
  pending.add(<String, Object?>{'by': seat, 'op': op, 'p': asMap(roomClone(p)), 'need': confirm, 'at': now()});
  ```

  并向发起玩家回 `sysTo`「已提交，等待确认」（`:331-339`）。
- 同类四件完全同构：`madness.cure`（`room_types.dart:269-272`）、`sheet.healwound`（`:307-310`）、`aid.apply`（`:311-314`）、`aid.psycho`（`:315-318`），都是 `[player, kp] + RoomConfirm.kp`。
- 唯一会「静默不入队」的分支是**全局操作锁**（`_memberLocked` + `_passSelf`，`:128-133`）：昏迷/濒死/疯狂发作时 `madness.cure` / `sheet.healwound` / `madness.advance` 放行，其余（含 `aid.apply`）只回一条定向提示。这是 P16/施工单要在 UI 侧同步的既有口径，**不是本 bug**（此时玩家侧会看到「无法进行该操作」的提示）。
- **结论**：`host.pending` 里一定有这一条；不需要改 domain（我也没改）。

## 9.3 段③KP 侧收集 —— 无断点（`op` 非空，一定被产出）

- `RoomHostRead.pending` 就是 `host.pending` 的只读副本（`room_session.dart:71-73`）。
- KP **恒有** `hostRead`：本机/LAN = `LocalLoopbackSession.hostRead`（`room_session_local.dart:143-144`）；公网开房 = `CloudHostingSession extends LocalLoopbackSession`（`room_session_cloud.dart:34`）；只有玩家/旁观会话返回 `null`（`room_session_remote.dart:76` / `room_session_cloud.dart:128`）。→ 研究者假设 B1-3「KP 拿不到 hostRead」**证伪**。
- `op` 字段由 `:326` 写入，非空 → `room_request_watcher.dart:168` 的 `if (op.isEmpty) continue` **不会**跳掉它；被跳掉的只是 `state.request` 那条无 `op` 的记账（`room_model_actions_sheet.dart:681-688`）。
- **结论**：`collectRoomPushRequests(kpSession)` 一定产出这条 `reply: confirm` 的请求。

## 9.4 段④弹窗 —— 有两条真断点（都在 watcher 自己身上）

- 通知链是通的：`pumpPlans` 末尾 `_hub.notifyAll()`（`room_session_local.dart:184`）；网络路径 `LanServer._dispatchHostPlans` → `onHostPlans = pumpPlans`（`lan_server.dart:98-105`；注入点 `room_session_hosting.dart:37`）→ KP 的 `_onSession` 一定会跑。
- **断点 B（v2 新修①）：挂载即记账。** v1 的 `didChangeDependencies` 首次挂载把当时**所有** id 记成已读（v1 代码 `:280-285`）。真机最典型的时序恰恰是「KP 先在大厅看成员 / 刚切过视角 / 断线重连重建页面 → 玩家提交治疗申请 → KP 才进/回到房间页」：watcher 在挂载瞬间把这条 pending 记成已读 → **这条永远不弹**，而 `GpStatus` 的「待办」卡也未必被 KP 注意到 = 用户说的「KP 没收到推送、无法同意」。
  - 为什么「挂载不弹历史」这条防护对 pending 不适用：那个防护服务的是**玩家侧「需我同意」历史请求**（一进房弹一堆旧卡很烦）；KP 的 `pending` 是**必须 KP 处理**的队列，挂载即弹才是正确口径（且正常情况下 pending 为空，不会有噪声）。
- **断点 C（v2 新修②）：`_seen.add` 早于真正弹出 + `_drain` 无单条兜底。** v1 在 `_onSession` 里 `_seen.add` 之后才入队（v1 `:298-299`）；一旦这条最终没弹成（弹窗期异常 / 页面卸载 / 路由状态异常），id 已被永久记账；同时 `_drain` 里 `showGeneralDialog` 一抛就整轮跳出，**当条已被 `removeAt` 吃掉、后面排队的全丢**，`finally` 复位 `_draining` 后也没有任何人再触发 `_drain`。

## 9.5 最终改法（v2 全部在 `lib/ui/room/room_request_watcher.dart`）

| # | 改动 | 行号 | 作用 |
|---|---|---|---|
| ① | 新增 `_queued`（已入队未弹）；`_seen` 语义改为「已**真弹过**」 | `:272-279` | 记账点后移，弹不成不永久记账 |
| ② | 挂载首填：`consent` 类仍记为已读，`confirm` 类（KP pending）改为**入队弹一次** | `:296-320` | 修断点 B：KP 进页面就能看到未处理的申请 |
| ③ | 抽出 `_schedule()`（帧后开弹的唯一调度口，含 unmount 复位） | `:344-361` | 挂载路径与新请求路径共用 |
| ④ | `_drain`：出队后 `_seen.add`；单条 `try/catch` + `FlutterError.reportError`；`finally` 队列非空则补排 | `:364-412` | 修断点 C：一条弹失败不再拖垮整条流水线 |
| ⑤ | `_onSession`：`_seen`/`_queued` 双判重 + 统一 `_schedule()` | `:329-339` | 保持「同一 id 只弹一次」 |

- `_seen` **仍然没有 remove / 定期清理**（红线满足）；「同一 id 只弹一次」不变量逐字保留（v1 的 §5·丁 用例继续有效）。
- domain 零新增改动：`confirmPending` 的 `break` 仍按 §3 单独挂 QA 回归。
- 文件头注释（`:13-18`）已同步改口径，避免下一个人再按「挂载全量记账」理解。

## 9.6 诚实的边界（请 QA 注意）

- 段③/段④的**通知链**我只做了静态核验（本批禁跑 `flutter test`，也无法在真机打点）。若波4 的验收用例（§10）全绿、真机仍复现，剩下的可能只剩「KP 端 `RoomScope` 的 session 与页面 `_session` 不是同一个 hub」（需在 `_onSession` 打点确认），那属于 W2-A 总装范畴（`room_game_page.dart` 不在我的文件集）。
- 断点 B 的修复会让 **KP 挂载时对已有 pending 弹窗**：`room_ui_player_test.dart:284-293` 里那段「先清空上一轮待确认，让弹窗的已读基线干净」的前置注释口径需要同步（行为仍绿，因为他们**确实清空了**）。

---

# 10.（v2 追加）验收用例口径 —— 玩家申请到达 KP

> 给波4 写测试用。前置：`import 'package:dice_realm/domain/room_types.dart' show kHostSeat, RoomIntent;`、`import 'package:dice_realm/ui/room/room_request_watcher.dart' show RoomPushKeys, RoomPushReply, collectRoomPushRequests;`、`import 'package:dice_realm/ui/room/sheets/sheet_treat.dart' show TreatSheetKeys, openTreatSheet;`

## 10.1 最简链路（本批核心，必须绿）

```dart
testWidgets('玩家点治疗提交 → KP 弹窗可见 → 点同意后 pending 被摘掉', (tester) async {
  final f = RoomUiFixture();
  await f.boot(inGame: true);
  useRoomScreen(tester, 900, 1600);

  // ① 玩家侧：完整 RoomGamePage（role=player），治疗入口走真实工具栏
  await mountRoom(tester, f, 'p1');
  await tester.tap(find.byKey(RoomGamePage.treatKey));
  await _settle(tester);
  expect(find.byKey(TreatSheetKeys.root), findsOneWidget);
  await tester.tap(find.byKey(TreatSheetKeys.kind('急救')));
  await tester.pump();
  await tester.tap(find.byKey(TreatSheetKeys.target('p2')));   // 夹具里 p2 必须在房间
  await tester.pump();
  await tester.tap(find.byKey(TreatSheetKeys.submit));
  await _settle(tester);

  // ② 权威端：真的进 pending（不是直接 apply）
  final pend = f.sessionOf(kHostSeat).hostRead!.pending;
  expect(pend.where((q) => q['op'] == 'aid.apply'), hasLength(1),
      reason: 'player 发起 confirm=kp 的动作必须入待确认队列');
  expect(asMap(pend.single)['need'], RoomConfirm.kp);

  // ③ 纯函数层：KP 侧能收集到这条（reply=confirm、id 非空）
  final reqs = collectRoomPushRequests(f.sessionOf(kHostSeat))
      .where((r) => r.reply == RoomPushReply.confirm).toList();
  expect(reqs, hasLength(1));
  expect(reqs.single.payload['op'], 'aid.apply');
  expect(reqs.single.payload['by'], 'p1');

  // ④ 组件层：KP 视角抬起来 → 弹窗可见（含技能详情）→ 点同意
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await mountRoom(tester, f, kHostSeat);
  await _settle(tester);
  expect(find.byKey(RoomPushKeys.root), findsOneWidget,
      reason: '★ 用户口径：玩家提交后 KP 必须收到居中推送，否则无法同意');
  expect(find.descendant(
      of: find.byKey(RoomPushKeys.details),
      matching: find.textContaining('急救')), findsOneWidget);
  await tester.tap(find.byKey(RoomPushKeys.agree));
  await _settle(tester);
  expect(f.sessionOf(kHostSeat).hostRead!.pending, isEmpty,
      reason: '同意后待办必须被摘掉（不残留）');
  expect(tester.takeException(), isNull);
});
```

> ★ 这条用例同时咬住**断点 B**：第 ④ 步是「pending 已经存在之后才抬 KP 页面」，v1 代码在这里会 `findsNothing`（挂载即记账），v2 转绿。

## 10.2 同类申请回归（四个都到 KP）

```dart
for (final c in <(String, Map<String, Object?>)>[
  ('aid.apply',   {'seat': 'p1', 'targetSeat': 'p2', 'skill': '急救'}),
  ('aid.psycho',  {'seat': 'p1', 'targetSeat': 'p2'}),
  ('sheet.healwound', {'seat': 'p1'}),
  ('madness.cure',    {'seat': 'p1'}),
]) {
  test('$c.1 → host.pending 有 1 条 + KP 可收集', () { ... });
}
// 断言：f.sessionOf(kHostSeat).hostRead!.pending.where((q)=>q['op']==op) 长度 1；
//      collectRoomPushRequests(...).where((r)=>r.reply==confirm).single.payload['op']==op
```

四件 POLICY 都是 `[player, kp] + RoomConfirm.kp`（`room_types.dart:269-272 / 307-318`），口径一致；`sheet.healwound` / `madness.cure` 的载荷只需 `seat`。

## 10.3 两条不同 id 都弹 + 同 id 只弹一次（v1 §5 乙/丁 的 v2 版）

- 两条：`p1` 连发两次 `aid.apply`（skill 必须不同，否则被 `act()` 防重复拒）→ `pending` 2 条、`collectRoomPushRequests` 里 confirm 2 条且 id 不同 → 弹第一条 → 同意 → **第二条必须紧跟着弹** → 两条都清。
- 同 id 只弹一次：单条 → 弹一次 → 点同意 → 连 `f.sessionOf(kHostSeat).refresh()` 3 次 → 不再弹。

## 10.4 反向证伪（波5）

| 改坏点 | 必须红 |
|---|---|
| 把挂载首填改回「全部记成已读」（`_seen..addAll(all.map(id))`） | 10.1 第 ④ 步（`findsNothing`） |
| 把 `_seen.add` 挪回 `_onSession` 入队处 | 10.1 / 10.3 仍绿（属兜底），**用「人为让 `showGeneralDialog` 抛一次」的探针用例才咬得住**；若不做探针，至少保证 10.3 双弹窗绿 |
| 删 `confirmPending` 的 `break` | §5·丙 |
| id 改回 `pending:$op:$by` | §5·乙 / 10.3 |

## 11.（v2）预计转红 / 需同步口径的既有测试

| 用例 | 预计 | 说明 / 建议口径 |
|---|---|---|
| `test/room_ui_player_test.dart:284-293` | **绿** | 他们**先** `sendIntent(confirm, agree:false)` 清空 pending 才挂 watcher，所以挂载即弹的新行为不触发；但注释「弹窗只弹挂载之后新到的请求」需改成「待确认（pending）挂载即弹，consent 类只弹新到的」 |
| `test/p10_t6_room_fixes_test.dart:562(5D)` | **绿** | 玩家侧 consent，挂载首填仍全记账；`room.details` 不变 |
| `test/p10_t6_room_fixes_test.dart:677(5F)` | **绿** | ① 先挂 KP（pending 空）再提交 → 1 条弹窗；③ 屏障关闭后 pending 仍在，但**用例随后 unmount**，不会二次弹 |
| `test/room_ui_confirm_flow_test.dart:98/154/181` | **绿** | 均为「先挂 watcher、后提交」；181 是旁观（无 hostRead） |
| `test/room_ui_kp_test.dart:406` | **绿** | `_boot` 后 pending 空；:435 才提交 |
| `test/p16_wave1_sheets_test.dart:610/615/620` | **绿** | 仅 `_submit` 新增 `ctl.notice`，见 §6 备注（harness 的 `scheduleDismiss` 已置空） |

> 若波4 发现**别的**用例因「KP 挂载即弹 pending」转红，正确口径不是回退修复，而是把该用例的前置改成「挂载前先清空 pending」（与 `room_ui_player_test.dart:284-293` 同一手法），并在注释里写明这是 P17 新口径。
