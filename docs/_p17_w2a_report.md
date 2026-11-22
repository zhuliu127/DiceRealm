# P17 波2-A 施工报告 · 房间页总装（P-2 战斗信息栏置顶 + P-3 锁定态统一禁用）

> worker：p17-w2a（Flutter 工程师 寇豆码）　|　版本基线：`v2.29.0+99`（本波**未**升版本）
> 工程根 `$P = C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
> 依据：`_p17_construction_spec.md` §0/§1/§2-P2/P3/P4/§6-Q5/Q6、`_p17_player_common_landing.md` P-2 / P-3

---

## 0. 一句话结论

P-2 与 P-3 的**调用侧**全部落地：战斗信息栏在战斗态被提到玩家折叠档展开区**首位**且强制展开（非战斗态一字未变）；`locked` 由 `session.state → findMe → operationLocked` 单点派生（`_lockedOf`）后逐按钮叠加（治疗禁用、「更多工具」恒可点、骰子条与工具栏壳透传），并按 team-lead G-1 裁决把**聊天发送**也接入锁定判定（用比工具栏少禁一态的 `_chatLockedOf`，撕卡仍可聊天）；另按 W2-B 的布局事实把「更多工具 / 治疗」移入新的 `mainActions` 扁平插槽（P-4 重排，手机竖屏 412dp 档落到 4 行 = 4/3/3/3）。`dart analyze` 三个文件 **No issues found!**（开工中途先后有 2 条 / 1 条 `locked` 参数未定义，均属跨组并发瞬态，w2b / w1b 落盘后自动消解，过程见 §5.2）。

---

## 1. 声明（纪律自证）

| 项 | 状态 |
|---|---|
| 是否跑 `flutter test` | **没有**（并发期禁令） |
| 是否改既有测试 | **没有**（一个 test 文件都没碰） |
| 是否新建测试 | **没有**（本波未新建；波4 统一补口径） |
| 是否碰别人文件集 | **没有**。本波只写 `lib/ui/room/room_game_page.dart` |
| `room_ui_local.dart` | **零改动**（P-2 不需要新的 local 字段，见 §3.4） |
| `room_layout.dart` | **零改动**（P-2 明确「不动 `roomDockPlanOf`」；另注：该文件实际路径是 `lib/ui/room/widgets/room_layout.dart`，任务书写的 `lib/ui/room/room_layout.dart` 不存在） |
| 门禁：`lib/ui/room/**` 零 emoji（U+1F300–1FAFF） | 本文件 **0 个**（脚本自查） |
| 门禁：禁止新写 `jsStr(` | 本文件 `jsStr(` 出现 **0 次**（本次改动零新增） |
| 布局红线 | `RoomSlot` / `RoomKeys` 命名、`gap` 机制、DFS 槽位机制、dock/folded 档位判定 **一律未改**；KP dock 树零改动；玩家树除 `kPlExpandedSlots` 一处外零改动 |
| 固定尺寸控件 textScaler 1.3/1.5/2.0 | 本波**未新增固定尺寸控件**（只改 `enabled` / 传参与纯函数过滤），不需要新的 `MediaQuery.withClampedTextScaling` |

---

## 2. 逐文件落点与哈希

| 文件 | 是否改 | 改动后 sha256 |
|---|---|---|
| `lib/ui/room/room_game_page.dart` | **改**（唯一改动文件，1215 行） | `61f58635242eb33c3fc921b3de9b0764ad1403a50820763a5cec2469e70ff34f`（含 G-1 聊天锁定（窄判据）+ P-4 `mainActions` 重排；演进：`7e581a1e…`(P-2/P-3) → `6e1da366…`(G-1) → `29c16758…`(P-4) → 当前） |
| `lib/ui/room/widgets/room_layout.dart` | 未改 | `989b0cfe6128408e578f12869808e0a528cb2661878a1179cb458278b14d867c` |
| `lib/ui/room/room_ui_local.dart` | 未改 | `9ea5a53fc258d9f1a7e79cef92dea4ecaffd7328249dfba6b4f5ecf55da8cf6c` |
| `lib/ui/room/widgets/gp_toolbar.dart`（**别人的**，w2b 在改） | 未改 | `79d972303aa82391b2ec9ddf044001ef00de8a691606968a3aa7f054205cfbd7`（w2b 落 `locked` 后我复核时的值） |
| `lib/ui/room/widgets/gp_dice_bar.dart`（**别人的**，w2b 在改） | 未改 | `b8df92d95e28a038c8f5df2011d5b55e8cf5196310e34017f9630d21b8ddf235`（同上；改前为 `f3ca9f82…`） |
| `lib/ui/room/widgets/gp_feeds.dart`（**别人的**，w1b 在改） | 未改 | `50197c4f864ba6503df4d6bdbd57071140327204283fde9cd47b314addb5d993`（w1b 落 `locked` 后我复核时的值） |

### 2.1 落点总表（`room_game_page.dart`，行号为改动后）

| # | 行号 | 落点 | 项 |
|---|---|---|---|
| 1 | `:40` | `import 'view/member_view.dart' show bodyViewOf, operationLocked;` | P-3 |
| 2 | `:105-114` | `kPlExpandedSlots` 加 `gpPlCombat` 并排首位 | P-2 |
| 3 | `:116-139` | `roomExpandedSlots(..., {state})` 战斗态过滤 + 提到首位 | P-2 |
| 4 | `:141-155` | `roomFoldedSlots(..., {state})` 透传 state | P-2 |
| 5 | `:668-684` | `_foldedContent` 先取 state、算 `combat`、按 state 求 expanded/squares | P-2 |
| 6 | `:691-701` | 展开区渲染：战斗态 `gpPlCombat` 忽略 `isFolded` | P-2 |
| 7 | `:1041-1058` | `_lockedOf(context, role)` —— 锁定态**单一真源**（方法体 `:1057-1061`）；`:1063-1076` `_chatLockedOf` —— 聊天专用的**窄判据**（撕卡除外） | P-3 / G-1 |
| 8 | `:863-874` | `gpChat`/`gpPlChat` → `GpFeeds(pane: chat, locked: _chatLockedOf(...))`（去掉 `const`）；`gpLog`/`gpPlLog` 仍 `const` | G-1 |
| 9 | `:1073` | `final locked = _lockedOf(context, role);`（工具栏侧复用同一份） | P-3 |
| 10 | `:1100` | `GpToolbar(locked: locked, mainActions: …, extensions: …)` | P-3 / P-4 |
| 11 | `:1112-1147` | `mainActions` 插槽：「更多工具」(`:1115`，**不叠** `!locked`) + 「治疗」(`:1135`，`enabled: !locked` 在 `:1141`) | P-3 / P-4 |
| 12 | `:1148-1176` | `extensions` 插槽：`GpDiceBar(locked:)` `:1152` + KP 专属 `KP` / `BGM 场景` + 调用方注入 | P-3 / P-4 |

---

## 3. P-2 战斗信息栏自动展开并置顶

### 3.1 `kPlExpandedSlots` 改动前后（`:105-114`）

**改动前**（原 `:105-108`）
```dart
const List<RoomSlot> kPlExpandedSlots = <RoomSlot>[
  RoomSlot.gpPlCharCard,
  RoomSlot.gpPlScene,
];
```

**改动后**（`:110-114`）
```dart
const List<RoomSlot> kPlExpandedSlots = <RoomSlot>[
  RoomSlot.gpPlCombat,
  RoomSlot.gpPlCharCard,
  RoomSlot.gpPlScene,
];
```

### 3.2 战斗态强制展开 + 置顶的判定位置

关键设计：**这张常量表是「候选 + 优先级」表，真正的有效展开表由 `roomExpandedSlots` 按 `state` 解析**。理由见 §3.5。

```dart
// :123-139
List<RoomSlot> roomExpandedSlots(
  List<RoomSlot> slots,
  String role, {
  Map<String, Object?>? state,
}) {
  final want = role == RoomRole.kp ? kKpExpandedSlots : kPlExpandedSlots;
  final combat = role != RoomRole.kp && state != null && isCombat(state);
  final expanded = <RoomSlot>[
    for (final s in slots)
      if (want.contains(s) && (s != RoomSlot.gpPlCombat || combat)) s,
  ];
  // 战斗信息栏必须排首位（`plSlots` 里它在第 6 位，直接遍历排不出来）。
  if (expanded.remove(RoomSlot.gpPlCombat)) {
    expanded.insert(0, RoomSlot.gpPlCombat);
  }
  return expanded;
}
```

判定链三处：
1. `:674` `final bool combat = isCombat(state);` —— 战斗态判据（`view/room_view.dart:96`，与 KP 的 `gpMap` 换战斗列表同一判据）。
2. `:675` `roomExpandedSlots(slotList, role, state: state)` —— 战斗态才会把 `gpPlCombat` 计入并 `insert(0)` → 落在 `_foldedContent` 的 `Column` **第一项**，即「场景检定 / 角色卡之后、所有方块（私聊 / 聊天 / 记录 …）之前」的展开区第一位。`_foldedContent` 的展开区渲染在 `Wrap(方块区)` **之前**（`:691` vs `:702`），所以视觉上就是「所有信息流最上方」（`_AdventureSection` 之外的最上）。
3. `:697-701`
```dart
              child: local.isFolded(slot.name) &&
                      !(combat && slot == RoomSlot.gpPlCombat)
                  ? _squareOf(context, slot, local, role, flash, state, seat)
                  : _expandedPanel(context, slot, spec, local, role),
```
→ 战斗态下即便 `local.isFolded('gpPlCombat') == true`（用户此前收过 / 存量偏好），也走 `_expandedPanel`：**强制展开**。折叠头仍然可点，只是战斗期间只记偏好、不生效；战斗结束（回到探索态）后按该偏好呈现。

### 3.3 非战斗态行为不变的证据

| 主张 | 证据 |
|---|---|
| 非战斗态玩家有效展开表仍是「角色卡 + 场景」两块 | `state` 传入但 `isCombat == false` → `expanded` 里 `gpPlCombat` 被 `(s != RoomSlot.gpPlCombat || combat)` 过滤掉 → 结果 `<gpPlCharCard, gpPlScene>`，与 P16 逐字相同 |
| 非战斗态 `gpPlCombat` 仍收成方块、点击可全屏 | `roomFoldedSlots(..., state: state)` 里 `expanded` 不含它 → 它留在 `squares` → `Wrap` 里渲染 `_squareOf`（`RoomSlotSquare`，`onOpen` 打开全屏 `GpCombatList`），与 P16 相同 |
| 单测口径不变（`state` 省略时行为 = P16） | `roomExpandedSlots(RoomKeys.plSlots, RoomRole.player)` 不传 state → `combat == false` → 返回 `[gpPlCharCard, gpPlScene]`；`roomFoldedSlots(...)` 长度仍 9。`test/room_ui_layout_test.dart:158-176`、`test/p10_t3_layout_test.dart:176-188` 的断言**不需要改**（见 §6） |
| KP 完全不受影响 | `role == RoomRole.kp` → `want = kKpExpandedSlots`（没有 `gpPlCombat`），`combat` 也恒 false；`_foldedContent` 的强制展开条件含 `slot == RoomSlot.gpPlCombat`，KP 槽位表里没有该槽位 → 结构上不可能命中 |
| 玩家 dock（平板横屏）不受影响 | `_dockContent` → `roomDockPlanOf` 一字未改；P-2 只作用于 `_foldedContent`（手机竖/横、平板竖） |

### 3.4 为什么 `room_ui_local.dart` 零改动

任务书给了两条备选实现（「忽略 `isFolded`」或「进战斗态时 `setFold(name,false)`」）。选前者：
- `setFold` 方案需要「战斗态翻转的那一刻写本地态」，得在 build 里做副作用（`build` 期间 `notifyListeners` 会触发 `setState during build`），或加 `didUpdateWidget`/监听器整套机制；
- 忽略 `isFolded` 是**纯派生**：无状态写入、无时序依赖、无 Timer，符合工程「零动画/零时序驱动」的测试纪律；
- 副作用是「折叠头点击在战斗期间无效」——已在代码注释与 §3.2 明确写出。

### 3.5 一处需要 team-lead 知情的口径取舍（可一句话否决）

任务书 §3.1 同时要求：
- ① 把 `gpPlCombat` 加进 `kPlExpandedSlots`（并排最前）；
- ④ 非战斗态行为保持现状（**折叠成方块、点击展开**）。

若把该常量当作「无条件展开表」直接使用，非战斗态玩家竖屏会**常驻展开**一块战斗列表（吃屏），与 ④ 冲突。故实现为「常量登记（满足 ① 的字面要求）+ 解析函数按 `state` 过滤（满足 ④）」。若 team-lead 要的是「非战斗态也常驻展开」，只需把 `:132` 的过滤条件去掉、把 `:129` 的 `combat` 用不到即可 —— 但**会吃掉手机竖屏很大一块高度**，建议保持现状。

---

## 4. P-3 锁定态统一禁用（按 §2 白名单逐字执行）

### 4.1 `locked` 的计算链（从 state 到 `operationLocked`）

**工具栏侧（含撕卡）单一真源**（`:1057-1061`，注释 `:1041-1056`）：

```dart
  bool _lockedOf(BuildContext context, String role) {
    if (role != RoomRole.player) return false;
    final scope = RoomScope.read(context);
    return operationLocked(findMe(scope.session.state, scope.session.seat));
  }
```

**聊天侧窄判据**（`:1073-1078`，见 §9 与该方法注释）：

```dart
  bool _chatLockedOf(BuildContext context, String role) {
    if (role != RoomRole.player) return false;
    final scope = RoomScope.read(context);
    final me = findMe(scope.session.state, scope.session.seat);
    return operationLocked(me) && !isRipped(me);   // 撕卡（死亡 / 永久疯狂）除外
  }
```

调用方共 **两处**，各自调用对应的方法（判定实现各只有一份，不重复写）：
- `:1094` `final locked = _lockedOf(context, role);`（工具栏 / 骰子条 / 治疗，见 §4.2）；
- `:873` `locked: _chatLockedOf(context, role)`（聊天输入行，见 §9）。

逐步拆解：

| 步 | 表达式 | 来源 | 说明 |
|---|---|---|---|
| 1 | `role != RoomRole.player → false` | 形参 `role`（与页面 `build` 同源：`widget.role ?? scope.session.role`） | **只有玩家视角参与**：KP 恒 false；**旁观者不适用**（口径如此，且第 3 步本就返回 null） |
| 2 | `scope.session.state` | `RoomScope.read(context)`（`:1056`） | 当前会话的权威状态快照（UI 只读；`read` 不订阅） |
| 3 | `scope.session.seat` | 同上 | 当前视角座位（旁观者也有 seat，但不在 `members` 里） |
| 4 | `findMe(state, seat)` | `lib/ui/room/view/room_view.dart:90` → `memberOfSeat`（`:83-88`） | **复用现有 helper**，不自己造映射；查不到返回 `null`（= 旁观者 / 未入座） |
| 5 | `operationLocked(mem)` | `lib/ui/room/view/member_view.dart:167-175` | 判据：`status.body == '死亡'` ∨ `dying` ∨ `unconscious` ∨ `mental[]` 含 `永久疯狂 / 临时疯狂 / 不定疯狂`；`mem == null` → false |
| 6 | 返回 bool | — | 供工具栏 / 骰子条 / 治疗 / 聊天输入行四处使用 |

与权威端同源：`lib/domain/room_model_host_intent.dart:95-111` `_passSelf` + `:128-133` `locked && !_passSelf(op,p)`；与角色卡 `gp_pl_char_card.dart:442` 的 `selfLocked(state, seat) => operationLocked(findMe(state, seat))` **同一表达式**（此处直接展开写，避免为一个判据再 import 一个 widget 文件）。

⚠️ **口径差**（G-1 裁决已处理）：权威端 `_passSelf` 放行 `RoomIntent.chat / sync / ready / stateSync / char`，即「锁定态仍可聊天」是**老 APP 遗留**；本批按用户口径在 **UI 侧收口**（禁聊天发送），**不动 domain**。所以现状是「UI 比权威端更严」——用户点了不会发包，也不会被 `_lockedHint` 打回（输入框根本不可写）。

### 4.2 传给两个被注入组件的位置

```dart
// :1080-1131（节选）
    return GpToolbar(
      locked: locked,
      mainActions: <Widget>[ …更多工具 / 治疗… ],
      extensions: <Widget>[
        GpDiceBar(locked: locked),
```
- `GpToolbar({..., bool locked = false, List<Widget> mainActions = const []})` 由 `_buildToolbar` 构造 → `:1083`（`mainActions` 见 §10）。
- `GpDiceBar(locked: locked)` —— 原来这里是 `const GpDiceBar()`，**已去掉 `const`**（`:1131`）。理由：带非常量实参的 `const` 不合法，且 `const` 实例会被元素树按身份跳过重建。

### 4.3 白名单 / 黑名单逐项落点表（Q6 口径，逐项对号）

| 项 | 键 / 标识 | 归属文件 | 本波落点 | 锁定态 `enabled` 表达式 |
|---|---|---|---|---|
| **① 角色卡「推进 1 轮」** | `madness.advance`（`gp_pl_char_card.dart` 内 throttle 按钮） | `gp_pl_char_card.dart`（w1c 已改，**我不碰**） | — | 保持可点（白名单，天然可用） |
| **② 工具栏「更多工具」** | `RoomGamePage.miscToolsKey`（`:1091-1112`，在 `mainActions`） | **本文件** | 只加注释 + 保持无 `enabled` | **不叠** `!locked`（默认 `enabled: true` → 恒可点）。本 key 不是 POLICY action，不受 T-30 约束 |
| **③ 更多工具内两申请** | `madness.cure` / `sheet.healwound` | `sheets/sheet_misc.dart`（w2c，**我不碰**） | — | 白名单，不叠 `!locked`（w2c 已按 `sheet_misc.dart:312` 注释落实） |
| **④ 纯视图操作（缩放 / 全屏 / 折叠 / 滚动）** | `GpToolbarKeys.zoomPercent`、`RoomKeys.gpZoomReset`、`FoldHeader`、`RoomSlotSquare.onOpen` | `gp_toolbar.dart`（w2b）/ 本文件 `_foldedContent` | 本文件未给折叠头/方块加任何 `locked` 判断 → 结构上保持可用 | 恒可用 |
| 黑：骰子条整棵（D100/D4–D20/自定义/奖惩骰/暗骰/战技/对抗） | `GpDiceBarKeys.*`、`RoomKeys.action('combat.roll'/'check.opposed')` | `gp_dice_bar.dart`（w2b） | **透传** `locked`（`:1131`） | 组件内部逐按钮 `!locked && 原判据` |
| 黑：工具栏主组（`round.next` / `scene.mode`） | 同上 | `gp_toolbar.dart`（w2b） | **透传** `locked`（`:1083`） | 组件内部逐按钮叠加（注：P-4 会**删掉**这两个按钮，属 w2b/w2c 范围） |
| 黑：治疗 | `RoomGamePage.treatKey`（`:1113-1124`，在 `mainActions`） | **本文件** | `:1139` | `enabled: !locked`（`:1120`；渲染条件仍只有 `!isKp`，未变） |
| 黑：AI RP / BGM | `gp_feeds.dart` 全屏入口、`roomSceneQuick` | `gp_feeds.dart`（w1b）/ 本文件 `:1132-1144` | KP 专属按钮，玩家侧 `isKp == false` → 结构上不渲染，无需处理 | — |
| 黑：角色卡「保存到已保存」/ 其它短按钮 | `GpPlCharCardKeys.saveBtn` 等 | `gp_pl_char_card.dart`（w1c） | — | 不在我文件（w1c 已加锁） |
| 黑：**聊天发送**（G-1 裁决新增；**撕卡除外**） | `RoomKeys.gpChatInput` / `GpFeedsKeys.send` / `aiRp` / `chatFullscreen` | `gp_feeds.dart`（w1b 已落 `locked`）/ **本文件调用侧** | `:863-874` 传 `locked: _chatLockedOf(...)`（= `operationLocked && !isRipped`） | 组件内 `writable = editable && !locked`：输入框 `enabled:false`、AI RP 与全屏入口 `enabled:false`、点输入框不弹全屏编辑器；历史仍可滚动 |
| 黑：KP 定向指令 | `sheet_kp_directives.dart` | KP 专属，玩家侧不渲染 | — | — |

### 4.4 为什么不做全局 `IgnorePointer`

- 用户口径是「**只禁操作、不禁看**」；全局闸门会连折叠头、方块点开、列表滚动一起废掉（白名单 ④ 直接违反）。
- 白名单 ②③ 必须保持可点（「更多工具」→ 弹层 → 两个申请按钮），全局闸门会把这条唯一自救路径一起封死。
- T-30 契约（`gp_toolbar.dart:16-18` / `gp_dice_bar.dart:16-17`：`enabled` 必须**恰好**等于 `gate.can(op)`）：逐按钮叠加会撞它，但叠加点分散、语义清晰，波4 可把探针口径改成「`gate.can && !locked`」并保留白名单项的正向断言；全局闸门则会把「不可点」与「不渲染」混在一起，探针更难定位。

### 4.5 与 w2b（`gp_toolbar.dart` / `gp_dice_bar.dart`）的对接复核

w2b 落盘后我复核了组件内部实现，与本波调用侧的约定**完全一致**，无口径漂移：

| 组件 | 内部行为 | 与我的调用侧 |
|---|---|---|
| `GpToolbar` | `locked` 只叠加到**黑名单**按钮；缩放（−/%/+, `gpZoomReset`）**故意不叠**（白名单 ④）；注释明写「扩展插槽里的按钮，其 `enabled` 由注入方按白名单自行判定」 | 我在 `:1093` 给「更多工具」**不叠** `!locked`，在 `:1121` 给「治疗」叠 `!locked` —— 分工正确 |
| `GpDiceBar` | `canRoll = editable && !locked`；`combat.roll` / `check.opposed` 走 `gate.can(op) && !locked`；`locked` 时给统一 `blockedHint` | 我只负责把 `locked` 传进去（`:1070`），骰子条整棵属黑名单，无需在注入侧重复叠加 |

---

## 5. 静态检查结果（`dart analyze`，仅我的文件）

### 5.1 最终结果：**零问题**

```bash
dart analyze lib/ui/room/room_game_page.dart lib/ui/room/widgets/room_layout.dart lib/ui/room/room_ui_local.dart
```

```
Analyzing room_game_page.dart, room_layout.dart, room_ui_local.dart...
No issues found!
```

### 5.2 中途的并发瞬态（已自然消解，如实记录过程）

本波开工时 `GpToolbar`（旧签名 `const GpToolbar({super.key, this.extensions = …})`，`gp_toolbar.dart:46`）与 `GpDiceBar`（旧签名 `const GpDiceBar({super.key, this.extensions = …})`，`gp_dice_bar.dart:170`）**都还没有** `locked` 参数，`dart analyze` 曾报 2 条：

```
  error - lib\ui\room\room_game_page.dart:1065:7 - The named parameter 'locked' isn't defined. ...
  error - lib\ui\room\room_game_page.dart:1070:19 - The named parameter 'locked' isn't defined. ...
2 issues found.
```

按 §1 要求重跑一次（仍 2 条）→ 继续做别的事、未擅自改别人的文件。约 2 分钟后，负责 `gp_toolbar.dart` / `gp_dice_bar.dart` 的 worker 落盘了参数：

- `gp_toolbar.dart:69` `const GpToolbar({…})` / `:89` `final bool locked;`
- `gp_dice_bar.dart:215` `const GpDiceBar({…})` / `:233` `final bool locked;`（`:285` 内部已使用）

复跑后 **No issues found!** —— 契约按逐字签名对接成功（`GpToolbar(..., locked: locked)`、`GpDiceBar(locked: locked)`），我的调用侧无需任何调整。


---

## 6. 给波4 的验收用例口径（只写口径，不必由我实现）

### ① 战斗态 + 玩家 folded 档：`gpPlCombat` 必定可见且位于「所有信息流最上方」

```dart
// 夹具：RoomUiFixture().boot(inGame: true, mode: RoomMode.combat)；
// 档位：手机竖屏 360×640（或 820×1180 平板竖），seat: 'p1'
// 前置：先让 gpPlCombat 处于「用户已折叠」的存量偏好
f.localOf('p1').setFold('gpPlCombat', true);   // 走 local API，别直接改 Set
await tester.pumpWidget(f.playerPage('p1'));
expect(find.byType(RoomSlotSquare), findsNothing);            // 它不是方块
expect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlCombat)),
    findsOneWidget);
expect(
  tester.widget(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlCombat))),
  isNot(isA<RoomSlotSquare>()),                                // 强制展开
);
expect(find.descendant(
  of: find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlCombat)),
  matching: find.byType(GpCombatList)), findsOneWidget);       // 真块已渲染
// 位置：它必须是展开区的第一项 —— 用 RenderBox 的 dy 与 gpPlCharCard /
// gpPlScene / 私密方块（gpPriv）逐一比：combat.dy < priv.dy（方块区在其后），
// 且在同层展开面板中 y 最小（cp 上层用 `tester.getTopLeft(...).dy`）。
```

### ② 非战斗态（`mode: RoomMode.exploration`）仍折叠成方块

```dart
expect(tester.widget(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlCombat))),
    isA<RoomSlotSquare>());
// 且点开 → 全屏真块（沿用 P16 既有断言写法）
```

### ③ 昏迷 / 疯狂玩家（`sheet.status.unconscious == true` 或 `mental` 含「临时疯狂」）

```dart
// 治疗禁用
expect(tester.widget<RoomTap>(find.byKey(RoomGamePage.treatKey)).enabled, isFalse);
// 更多工具恒可点（白名单）
expect(tester.widget<RoomTap>(find.byKey(RoomGamePage.miscToolsKey)).enabled, isTrue);
// 骰子条整棵禁用（w2b 组件内部叠加）
expect(tester.widget<RoomTap>(find.byKey(GpDiceBarKeys.expr('1D100'))).enabled, isFalse);
// 角色卡「推进 1 轮」仍可点（跨文件：gp_pl_char_card.dart，本波只写口径）
// 角色卡「保存到已保存」禁用（w1c）
```

反向证伪要求：把 `operationLocked` 的 `unconscious` 分支临时改坏 → ③ 必须红。

### ④ 正常玩家：全部 enabled

```dart
expect(tester.widget<RoomTap>(find.byKey(RoomGamePage.treatKey)).enabled, isTrue);
expect(tester.widget<RoomTap>(find.byKey(RoomGamePage.miscToolsKey)).enabled, isTrue);
// 骰子条 / 工具栏主组沿用各自的 gate.can 口径
```

### ⑤ 纯函数口径（可放同一批）

```dart
// 非战斗态：与 P16 完全一致
expect(roomExpandedSlots(RoomKeys.plSlots, RoomRole.player),
    <RoomSlot>[RoomSlot.gpPlCharCard, RoomSlot.gpPlScene]);
// 战斗态：首位是战斗信息栏
final combatState = <String, Object?>{'meta': <String, Object?>{'mode': RoomMode.combat}};
expect(roomExpandedSlots(RoomKeys.plSlots, RoomRole.player, state: combatState).first,
    RoomSlot.gpPlCombat);
// 不丢不重：展开 ∪ 方块 ∪ {顶栏,工具栏} == 全部槽位（战斗/非战两种 state 各跑一次）
```

### ⑥ 聊天锁定（G-1 裁决）

```dart
// 甲（禁）：把 p1 打成昏迷（或 mental 加「临时疯狂」），pump 玩家页（手机竖屏，折叠档）
final tf = tester.widget<TextField>(find.byKey(RoomKeys.gpChatInput));
expect(tf.enabled, isFalse, reason: '昏迷 / 濒死 / 疯狂发作：聊天禁发');
expect(tester.widget<RoomTap>(find.byKey(GpFeedsKeys.aiRp)).enabled, isFalse);
expect(tester.widget<RoomTap>(find.byKey(GpFeedsKeys.chatFullscreen)).enabled, isFalse);
// 历史仍可看 / 可滚：列表与行照常渲染
expect(find.byKey(GpFeedsKeys.list), findsWidgets);

// 乙（放）：**撕卡**（body=死亡 或 mental 含「永久疯狂」）→ 聊天仍可用（P10 T-20）
//   同一份夹具把 p1 打成死亡后再 pump：
expect(tester.widget<TextField>(find.byKey(RoomKeys.gpChatInput)).enabled, isTrue,
    reason: '撕卡保留「只能聊天」的社交口子');
//   但工具栏 / 骰子 / 治疗仍是禁的（那条用全量 _lockedOf）：
expect(tester.widget<RoomTap>(find.byKey(RoomGamePage.treatKey)).enabled, isFalse);

// 丙（对照）：解锁玩家 → 全开；KP / 旁观者不受影响（KP 恒 false）
```

反向证伪两条：
1. 把 `_chatLockedOf` 的 `&& !isRipped(me)` 删掉 → **乙** 必红；
2. 把 `_chatLockedOf` 改成恒 `false` → **甲** 必红。

> ★ 可执行版本以 `_p17_w1b_report.md` §6.8 为准（W1-B 已把 ② 从注释升级成断言，并加了
> `expect(isRipped(findMe(f.stateOf('p1'),'p1')), isTrue)` 的**夹具真实性前置自检**）：
> ① 昏迷禁 → ② 撕卡放行（另起夹具）→ ③ 解锁全开 → ④ 撕卡夹具自检，四段互咬。
> 注意边界：`dying` / `unconscious` 属 **①（禁）**，只有 `body == '死亡'` 或 `mental` 含「永久疯狂」
> 才是 **②（放行）**；夹具若只打成「濒死」，② 会拿到 `enabled == false`（此时是 ① 的口径，不是 bug）。

---

## 7. 预计转红的既有测试 + 建议口径（逐条）

### 7.1 由**我的**改动直接引起的

**结论：0 条。** 理由逐条列（均已按源码核对）：

| 用例 | 现状断言 | 我的改动为何不红 |
|---|---|---|
| `test/room_ui_layout_test.dart:156-176`「折叠档：展开白名单按口述（KP 三块 / 玩家两块）」 | `roomExpandedSlots(plSlots, player) == [gpPlCharCard, gpPlScene]`；`plFolded.length == 9` | 该用例**不传 `state`** → `combat == false` → `gpPlCombat` 被过滤 → 结果与长度都逐字不变 |
| `test/room_ui_layout_test.dart:178-190`「一个不少」 | 展开 ∪ 方块 ∪ {顶栏, 工具栏} == 全部槽位 | 同上（`state` 省略时 `gpPlCombat` 进方块区，仍是「一个不少」） |
| `test/p10_t3_layout_test.dart:132-190`「三档 × 两角色」 | 用 `roomExpandedSlots/roomFoldedSlots`（不传 state）比对真实渲染 | 该夹具 `boot(inGame: true)` 默认 `mode: RoomMode.exploration` → 渲染路径与之同源，等价 |
| `test/room_ui_wiring_test.dart:131` | `gpPlCombat → GpCombatList`（1280×800 dock） | 我的改动只作用于 `_foldedContent`，dock 走 `_dockContent`；`_bodyOf` 零改动 |
| `test/room_history_export_test.dart:930-955` | `miscToolsKey` 在玩家侧有、KP / 旁观无 | 渲染条件 `!isKp && canOpenMisc` 未动；只加了 `locked` 注释（`enabled` 仍默认 true） |
| `test/p16_button_unify_test.dart:180-235`（分组表 + 大字体） | 逐 key 在大字号下不溢出 | 未改任何 `minSize` / `padding` / 文本 |
| `test/room_ui_permission_test.dart` T-30 探针 | `enabled == gate.can(op)` | `treat` / `miscTools` **不是** POLICY action key，探针不覆盖；`GpToolbar.locked` 默认 false 时组件内 `enabled` 不变 |
| `test/qa_p5_priv_probe_test.dart:463-484`「撕卡后仍能聊天」 | 撕卡（濒死/死亡）后 `RoomKeys.gpChatInput` `findsOneWidget` | **保持绿、不必改**：`_chatLockedOf` 对撕卡返回 `false`（`operationLocked && !isRipped`），撕卡仍可聊天，与 P10 T-20 契约一致。波4 只需**新增**一条「昏迷态 `TextField.enabled == false`」的正向守卫（见 §6-⑥ 甲） |

### 7.2 由**别人**改动引起、需要波4 处理的（登记，非我引起）

| 用例 | 触发项 | 建议口径 |
|---|---|---|
| `test/room_ui_permission_test.dart:625-640`「恒渲染的那批（`round.next` / `scene.mode`）三视角都存在」 | P-4 删这两个按钮（w2b） | 改成「工具栏**不含** `round.next` / `scene.mode`」（`findsNothing`），并把「KP 的下一轮在战斗信息栏 `combat.next`」单列一条正向断言；三视角各跑一次 |
| `test/room_ui_permission_test.dart` 其它 T-30 表驱动探针（骰子条 / 工具栏） | P-3 叠加 `!locked`（w2b 组件内） | 探针表达式从 `enabled == gate.can(op)` 改为 `enabled == (gate.can(op) && !locked)`；**同时**保留白名单项独立正向断言（`miscToolsKey` enabled、`madness.advance` enabled），否则等于放宽 |
| `test/p16_button_unify_test.dart:197` 分组表（`gpToolbar 主组` 含 `round.next`/`scene.mode`；扩展含 `miscToolsKey`） | P-4 删按钮 + 重排 | 从分组表移除已删除的 key；重排后按新分组表断言（组内数量 + 大字号不溢出）并**新增**「删除的 key 全文零命中」 |
| `test/p10_t3_layout_test.dart:111-130` 玩家 dock 落位表 | P-4 / P-3 若动 dock（本波未动） | 保持原表；若 w2b 改 dock，需逐槽位复核 |
| `test/room_ui_entry_test.dart:751-761`（音乐入口） | KP-8（w2c） | 见施工单 §2-KP-8 |
| `test/qa_p5_priv_probe_test.dart:475-479`、`test/room_ui_pl_test.dart:242-248` | 角色卡锁定（w1c） | 见 w1c 报告 |
| `test/qa_p5_priv_probe_test.dart:463-484`「撕卡后仍能聊天」 | **team-lead 收窄裁决（撕卡保留聊天）** | **该用例无需修改**：撕卡态 `_chatLockedOf == false`，输入行 `enabled == true`，原断言与 reason 都成立。要补的是另一条**新**用例（昏迷态禁言，§6-⑥ 甲），不是改这条 |

### 7.3 建议波4 新增（不是改既有）

1. `p17_w2a_test.dart`：§6 的 ①②③④⑤ + ⑥（聊天锁定）六组，外加**反向证伪**两条（改坏 `operationLocked` 的 `unconscious` 分支 → ③ 必红；把 `roomExpandedSlots` 的 `insert(0, …)` 删掉 → ① 的位置断言必红）。
2. 断言 `kPlExpandedSlots.first == RoomSlot.gpPlCombat`（钉住「登记 + 首位」这条常量语义，防后来人把它挪走）。

---

## 8. 遗留 / 风险（需 team-lead 决策或下一波承接）

| # | 事项 | 说明 |
|---|---|---|
| **G-0** | ~~`GpToolbar` / `GpDiceBar` 的 `locked` 参数未落盘~~ | **已消解**：w2b 已落 `locked`（`gp_toolbar.dart:69/:89`、`gp_dice_bar.dart:215/:233/:285`），复跑 `dart analyze` 三文件零问题 |
| **G-1** | ~~「聊天发送」锁定态禁用无人承接~~ | **已裁决并落地**（team-lead 2026-11-14：锁定态**要禁**聊天，UI 侧收口、不动 domain）。`_lockedOf` 上提为单一真源，聊天两处调用点已传 `locked`；详见 §9 |
| **G-2** | `lib/ui/room/room_layout.dart` 路径不存在 | 实际是 `lib/ui/room/widgets/room_layout.dart`；本波按「不动 `roomDockPlanOf`」处理，零改动 |
| **G-3** | 战斗态折叠头可点但无效 | 现值行为：点击只写偏好，战斗期间不生效（§3.4 说明）。若用户要求「战斗期间折叠头隐藏/置灰」，需再申请一处小改（`_expandedPanel` 的 `FoldHeader` 加 `enabled`），本波未做以免越界 |
| **G-4** | 旁观者战斗态也会置顶战斗栏 | 口径要求「仅玩家/旁观视角生效」，故旁观者同样置顶；旁观者无 seat 成员行 → `locked` 恒 false（不会被误禁） |

---

## 9. §G-1 聊天锁定（team-lead 2026-11-14 裁决的补丁）

### 9.1 裁决原文与我的落点

> "聊天发送在锁定态要禁。用户原话是「玩家昏迷或疯狂时应该什么都不能操作，只能点击推进1轮按钮和更多工具」——聊天属于操作；而且「申请治愈」已经走更多工具，不需要靠聊天求助。权威端 `_passSelf` 放行 chat 是老 APP 遗留，本批按用户口径在 UI 侧收口（不动 domain）。"

| 指令 | 落地 |
|---|---|
| ① `_bodyOf` 里 `gpChat` / `gpPlChat` 传 `locked: locked`（去掉 `const`） | **已改**（`:863-874`）：`GpFeeds(pane: FeedPane.chat, locked: _chatLockedOf(context, role))`（team-lead 后续收窄：撕卡保留聊天，见 §9.6）；`gpLog` / `gpPlLog` **保持 `const`**（只读记录没有输入行，按指令不传） |
| ② `locked` 上提，`_buildToolbar` 与 `_bodyOf` 共用同一份、不算两遍 | **已改**：新增 `bool _lockedOf(BuildContext, String role)`（`:1057-1061`）给工具栏侧；收窄裁决后又加 `bool _chatLockedOf(...)`（`:1073-1078`）= `operationLocked && !isRipped` 给聊天侧。两者共用同一套 `findMe/operationLocked` 底层函数，**没有**任何一份「手写状态判定」重复 |
| ③ `GpFeeds.locked` 由 W1-B 加，我写调用侧 | **已对接**：w1b 已落 `GpFeeds({..., this.locked = false})`（`gp_feeds.dart:125/:150`）→ `ChatInputRow(locked:)`（`:385-387`）→ `writable = editable && !widget.locked`（`:851`）。跨组瞬态（1 条 `undefined_named_parameter`）复跑后归零 |
| ④ KP 侧不受影响 | `_chatLockedOf` / `_lockedOf` 首行都是 `role != player → false`；KP 的 `gpChat` 也走 `locked: false`，行为与 P16 逐字相同。旁观者同样 false（且 `editable` 本就是 false，另有一层兜底） |

### 9.2 两个判据：`_lockedOf`（工具栏全量）与 `_chatLockedOf`（聊天窄一格）

```dart
// :1057-1061 —— 工具栏侧：含撕卡，权威动作全禁
  bool _lockedOf(BuildContext context, String role) {
    if (role != RoomRole.player) return false;
    final scope = RoomScope.read(context);
    return operationLocked(findMe(scope.session.state, scope.session.seat));
  }

// :1073-1078 —— 聊天侧：少禁「撕卡」一态（P10 T-20「撕卡后只能聊天」）
  bool _chatLockedOf(BuildContext context, String role) {
    if (role != RoomRole.player) return false;
    final scope = RoomScope.read(context);
    final me = findMe(scope.session.state, scope.session.seat);
    return operationLocked(me) && !isRipped(me);
  }
```

两处调用点（同源底层函数，无手写判定重复）：

| # | 位置 | 用途 | 生效方式 |
|---|---|---|---|
| 1 | `:1094` `final locked = _lockedOf(context, role);` | 工具栏外壳 / 骰子条 / 治疗 | `GpToolbar(locked:)` `:1100`、`GpDiceBar(locked:)` `:1152`、`治疗 enabled: !locked` `:1141`（「更多工具」不叠，白名单） |
| 2 | `:873` `locked: _chatLockedOf(context, role)` | 聊天输入行 | 组件内 `writable = editable && !locked`：`TextField.enabled=false`、hint 改「昏迷 / 疯狂发作期间不能发言」、不弹全屏编辑器、AI RP 与全屏入口 `enabled=false`；列表仍可滚 |

### 9.3 跨组契约（与 W1-B）

| 契约 | 提供方 | 消费方 | 现状 |
|---|---|---|---|
| `GpFeeds({..., bool locked = false})` | w1b（`gp_feeds.dart`） | 本文件 `:870` | **已落**（`:125` 构造 / `:150` 字段 / `:387` 下传 `ChatInputRow`） |
| `ChatInputRow({..., bool locked = false})` | w1b（同文件） | `GpFeeds` 内部 | **已落**（`:736/:745`），`writable` 同时决定 `enabled`、hint、`onTap` 与全屏入口 / AI RP 的 `enabled` |
| 「只禁操作、不禁看」 | 双方约定 | — | 输入行**照常渲染**（不隐藏、不改尺寸）→ P17 KP-4 的「三块等高」不会被锁定态打破；历史照常滚动 |
| 只对 `FeedPane.chat` 生效 | w1b | — | `gp_feeds.dart:385` 注释明确「`locked` 对其它 pane 无意义」；`record` 档我不传（双保险） |

### 9.4 与权威端的关系（口径说明，不改 domain）

- 权威端 `_passSelf`（`lib/domain/room_model_host_intent.dart:95-111`）放行 `RoomIntent.chat` → 锁定态下**发包不会被拒**。
- G-1 裁决明确这是老 APP 遗留、**本批不动 domain**，改为 UI 侧「结构上发不出」：输入框 `enabled:false` → 不可能产生 `RoomIntent.chat`；全屏编辑器入口也 `enabled:false`，堵掉「独立路由绕过输入行」这条侧门（w1b 在 `onTap: writable ? … : null` 处已堵）。
- 后果：UI 比权威端**更严**。这是用户口径（"什么都不能操作"）与老协议（chat 属通讯、不算 act）之间的差，如需与 domain 完全一致，后续可另开一项把 `chat` 从 `_passSelf` 移除（本批不做，避免动冻结文件）。

### 9.5 交付口径补充

- 波4 验收新增 §6-⑥（甲：昏迷禁言 / 乙：撕卡仍可聊 / 丙：解锁全开）。`test/qa_p5_priv_probe_test.dart:463-484`（撕卡后仍能聊天）**保持绿、不必改**（见 §7.1/§7.2）。
- `dart analyze` 三文件：**No issues found!**（w1b 落 `locked` 之后复跑）
- sha256 演进：`7e581a1e…`(P-2/P-3) → `6e1da366…`(G-1) → `29c16758…`(P-4) → **`61f58635…`(聊天收窄，1215 行)**

### 9.6 收窄裁决（team-lead 同日追加）：撕卡保留「只能聊天」

**裁决**：撕卡（已死亡 / 永久疯狂）**保留「只能聊天」**，不纳入聊天禁言；聊天锁定只覆盖「昏迷 / 濒死 / 疯狂发作」。

| 项 | 落地 |
|---|---|
| 不改 `_lockedOf` 语义（工具栏 / 骰子条 / 治疗仍含撕卡全禁） | ✅ `:1057-1061` 原样保留（P10 既有行为：撕卡后权威动作全禁） |
| 新增聊天专用窄判据 | ✅ `_chatLockedOf`（`:1073-1078`）：`operationLocked(me) && !isRipped(me)`；撕卡判据**复用** `member_view.dart:163` 的 `isRipped`（`bodyViewOf == '死亡'` 或 `mental` 含「永久疯狂」），未手写任何新判定 |
| `gpChat` / `gpPlChat` 换判据 | ✅ `:873` `locked: _chatLockedOf(context, role)` |
| `gpLog` / `gpPlLog` 仍不传 | ✅ 保持 `const GpFeeds(pane: FeedPane.record)` |
| 注释写清「为什么聊天比工具栏少禁一态」 | ✅ `_chatLockedOf` 文档注释：P10 T-20 社交口子 + `gp_pl_char_card.dart:186` 文案「已撕卡 / 无法行动：只能聊天」+ `qa_p5_priv_probe_test.dart:483-484` 钉着该行为 |
| `qa_p5_priv_probe_test.dart:463-484` | **保持绿、不需改**：撕卡态 `_chatLockedOf == false` → 输入行 `enabled == true`，原断言与 reason 都成立。真正要新增的守卫是「**昏迷态** `TextField.enabled == false`」（§6-⑥ 甲） |

与 W1-C 的文案矛盾已消解：`gp_pl_char_card.dart:186` 的「已撕卡 / 无法行动：只能聊天」**无需修改**（该文案属 W1-C 文件，本波也未碰）。

---

## 10. §P-4 重排：「更多工具 / 治疗」移入 `mainActions`（W2-B 请求，2026-11-14 追加）

### 10.1 为什么要动（W2-B 给的布局硬事实）

| 事实 | 出处 |
|---|---|
| 骰子条窄档是 `Container(width: double.infinity)` | `gp_dice_bar.dart:451`（narrow 分支） |
| `extensions` 是**嵌套** `Wrap`（key `GpToolbarKeys.extensions`），外层 `quickRow` 把它当**一个整体**换行 | `gp_toolbar.dart:219` / `:153`；`room_ui_shell_test.dart:408` 钉死该 key 必须存在 |
| ⇒ 只要「更多工具 / 治疗」留在 `extensions`，第 1 行永远只有 `zoomPercent + gpZoomReset` 2 个 → 全栏 **5 行（2/3/3/3/2）**，达不到用户要的 4 行 | 同上 |
| 放 `mainActions`（扁平进主 Wrap）后，412dp 档 `80+80+90+90+3×4 = 352 ≤ 400` ⇒ 第 1 行 4 个 → **4/3/3/3** | `gp_toolbar.dart:82-89` 的注释与实算 |

### 10.2 我的改动（`_buildToolbar`，`:1097-1176`）

```dart
    return GpToolbar(
      locked: locked,
      // ★ P17 P-4 重排：`mainActions` 是扁平进主 Wrap 的插槽（与两个缩放控件同一行）……
      mainActions: <Widget>[
        if (!isKp && canOpenMisc)
          RoomTap(key: RoomGamePage.miscToolsKey, …),   // 白名单：不写 enabled
        if (!isKp)
          RoomTap(key: RoomGamePage.treatKey, …, enabled: !locked),  // 黑名单
      ],
      extensions: <Widget>[
        GpDiceBar(locked: locked),
        if (isKp) RoomTap(key: kpPanelKey, …),
        if (isKp && canQuickBgm) RoomTap(key: MusicSheetKeys.roomSceneQuick, …),
        ...widget.toolbarExtensions,
      ],
    );
```

- 位置：`:1100` `GpToolbar(`、`:1112` `mainActions:`、`:1115` 更多工具、`:1135` 治疗（`:1141` `enabled: !locked`）、`:1148` `extensions:`、`:1152` 骰子条、`:1174` `...widget.toolbarExtensions`。
- **视觉顺序 = 列表顺序**：`GpToolbar` 内部主 Wrap 的拼法是 `zoomPercent → gpZoomReset → ...mainActions → Wrap(extensions)`（`gp_toolbar.dart:153-219`，`mainActions` 在 `:214` 展开），所以第 1 行从左到右是 `[缩放−][缩放%][缩放+][更多工具][治疗]` → 满足「更多工具 / 治疗 在最右」。
- **玩家侧 `extensions` 只剩 `GpDiceBar(locked: locked)`**（骰子条窄档 `width: double.infinity`，独占整行）；`extensions` 里另两个 `KP` / `BGM 场景` 只在 `isKp` 时渲染，玩家视角为空。
- **顺序即视觉顺序**：主 Wrap 里是 `zoomPercent → gpZoomReset → 更多工具 → 治疗`，正好是用户截图要的第 1 行 4 连。
- **权限语义零变化**：「更多工具」仍只判 `!isKp && canOpenMisc`（白名单，不叠 `!locked`）；「治疗」仍只判 `!isKp` 且 `enabled: !locked`（黑名单）。
- **KP 侧零变化**：`KP` / `BGM 场景` 留在 `extensions`（平板横屏是宽档单 Wrap，无换行问题），`mainActions` 在 KP 视角为空列表（两个 `if (!isKp …)` 都不成立）→ KP dock 的工具条与 P16 逐像素一致。
- `GpToolbarKeys.extensions` 这个 Wrap 仍存在（玩家侧装骰子条，KP 侧装骰子条 + 两个 KP 按钮）→ `room_ui_shell_test.dart:408` 的结构断言不受影响。

### 10.3 口径边界（已在报告登记，勿在波4 误判为 bug）

- **412dp**：4 行 = 4/3/3/3（目标达成）。
- **360dp**：`352 > 348` →「治疗」掉到第 2 行，变成 3/1/3/3/3。这是 `RoomBtnSize` 两个常量（80 / 90）的物理极限，本批**不许改常量**（P16 已冻结尺寸口径，`p16_button_unify_test` 钉着）。**建议波4 只在 412dp 断言「每行 3 或 4 个 + 总行数 == 4」，不要在 360dp 断言严格 4/3/3/3。**
- 「更多工具 / 治疗」不是 POLICY action key，不受 T-30「`enabled` 恰好等于 `gate.can`」约束，换插槽不改变探针口径。

### 10.4 转红风险核对（我改的这 3 行搬移）

| 用例 | 影响 |
|---|---|
| `test/room_ui_shell_test.dart:408`（`GpToolbarKeys.extensions` 必须存在） | **绿**：该 Wrap 仍在（装骰子条） |
| `test/room_history_export_test.dart:930-955`（`miscToolsKey` 玩家侧有 / KP·旁观无） | **绿**：渲染条件未改，只是换了所在 Wrap |
| `test/p16_button_unify_test.dart`（按 key 查大字号溢出，含 `miscToolsKey` / `treatKey`） | **绿**：按 key 找控件，不校验父子关系；尺寸未改 |
| 任何断言「miscTools/treat 在 `extensions` 子树内」的用例 | **不存在**（全库检索 `GpToolbarKeys.extensions` 只有 `room_ui_shell_test.dart:408` 一处，只断言存在） |
| `test/p10_t3b_rule_diff_test.dart:751`（源码里必须含 `final squares = roomOrderedContentSlots(`） | **绿**：该行未动 |

### 10.5 交付

- `dart analyze lib/ui/room/room_game_page.dart lib/ui/room/widgets/room_layout.dart lib/ui/room/room_ui_local.dart` → **No issues found!**
- `room_game_page.dart`：1215 行，sha256 `61f58635242eb33c3fc921b3de9b0764ad1403a50820763a5cec2469e70ff34f`
- ⚠️ 未改 `gp_toolbar.dart`（归 W2-B）：`mainActions` 的插入点（`:214`，位于 `zoomPercent`/`gpZoomReset` 之后、`extensions` Wrap 之前）**正好符合需求**，无需 W2-B 再调任何一行。
