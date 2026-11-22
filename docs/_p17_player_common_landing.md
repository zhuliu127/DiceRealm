# P17 落点定位报告：玩家视角 4 项 + 所有模式 4 项 + APP 首页 1 项

> 研究员：researcher-player-p17　|　纯只读研究，未改 `lib/**`、`test/**`、`pubspec.*`
>
> 工程根 `$P = C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
> 版本：`v2.29.0+99`（`lib/app_version.dart:15` `kAppVersion='2.29.0'`、`:18` `kAppBuildNumber=99`）
> 所有行号基于当前工作副本（v2.29.0+99），行号与 key 名逐字核对过。
>
> **档位口径（本批）**：玩家视角 = 非平板横屏（手机竖屏 / 手机横屏 / 平板竖屏 `folded`）；KP 视角 = 平板横屏 `dock`；平板横屏玩家档本批不动。
> **硬约束提醒**：`skills.dart`/`occupations.dart` GENERATED 禁改；`oracle_*`/`test/fixtures/**` 逐字节契约禁改；`lib/domain/room_rules_combat.dart` 计算式禁改；`lib/ui/room/**` 零 emoji（只匹配代理对，`⚔️` 允许）、禁止新写 `jsStr(`（用 `roomText`）；固定尺寸控件须过 textScaler 1.3/1.5/2.0（`MediaQuery.withClampedTextScaling(maxScaleFactor: 1.0)` 只包该控件子树，工程已有封装 `clampBtnText`，见 `lib/ui/room/widgets/room_button_size.dart:150-153`）。

---

## 一、玩家视角 4 项（非平板横屏 / folded）

### P-1　状态栏缺 luck（幸运）

**一行结论**：「我的角色卡」属性区只画 8 项属性、缺 `LUK`；幸运值其实已在 `vitals.luck` 里取到但没用，**最小落点是在 `gp_pl_char_card.dart:194-201` 的 `Wrap` 里追加一行**，不要改共享纯函数 `attrRows`。

**证据与现状**
- `lib/ui/room/widgets/gp_pl_char_card.dart:104` `final attrs = attrRows(me);`；`:103` `final vitals = vitalsOf(me);`（**已有 luck，但未用于属性区**）。
- `lib/ui/room/widgets/gp_pl_char_card.dart:194-201` 属性显示区：
  ```dart
  Wrap(
    spacing: 8, runSpacing: 2,
    children: <Widget>[
      for (final row in attrs)
        Text('${row.k} ${row.v}', style: const TextStyle(fontSize: 11)),
    ],
  ),
  ```
  当前显示 8 项：`STR CON SIZ DEX APP INT POW EDU`（`lib/ui/room/view/sheet_view.dart:73-75` `_attrLabels`），**没有 `LUK`/幸运**。
- `lib/ui/room/view/sheet_view.dart:78-89` `attrRows(mem)` 按 `_attrLabels.length` 遍历、用 `kRaAttrKeys[i]` 取 `sheet.attrs`；`kRaAttrKeys` 含 `'luck'`（`lib/domain/room_model_actions_room.dart:72`），但 `_attrLabels` 只有 8 个标签 → luck 被截断。
- **字段名**：`luck` 属性本身在 `sheet.attrs['luck']`；**当前幸运点**在 `sheet.status['currentLuck']` → `Vitals.luck`（`lib/ui/room/view/sheet_view.dart:29-32` 声明、`:59-71` `vitalsOf`、`:69` `luck: roomNumber(st['currentLuck'], 0)`）。`lib/domain/character.dart:130` 模板里有 `'luck': ''`；`lib/ui/card_view.dart:51` `luckLabel(c) => jsNum(c.status['currentLuck'])`。
- 取值 helper **`bodyViewOf` 不在 `room_view.dart`**，在 `lib/ui/room/view/member_view.dart:124-132`（`room_view.dart:96` 是 `isCombat`）。`room_game_page.dart:1096` 的 `_showSpectators` 用 `bodyViewOf(m)` 显示观众名单。
- 对照：全屏只读详情 `lib/ui/room/sheets/sheet_char_view.dart:141` **已经**显示 `'SAN ${v.san}/${v.sanMax} · 幸运 ${v.luck}'`，`:153` 也用 `attrRows(mem)`。即「幸运」在弹层里有、主卡上没有。

**建议落点**：`gp_pl_char_card.dart:194-201` 的 `Wrap` 内、`for (final row in attrs)` 之后加一行（示例）：
```dart
Text('LUK ${_fmtLuck(vitals.luck)}', style: const TextStyle(fontSize: 11)),
```
`vitals` 已在 `:103` 取到、作用域内可用；若要显示「属性 luck」而非「当前幸运点」，取 `asMap(me['sheet'])['attrs']['luck']`。**不要改 `attrRows`**（`sheet_view.dart:78`，被 `sheet_char_view.dart:153` 与 `gp_pl_char_card.dart:104` 复用，改它会连坐 `room_view_test.dart:288/628` 的 8 项断言）。

**会撞到的既有测试**：改 `attrRows` → `test/room_view_test.dart:288`（`attrRows(mem).first.v == '—'`）、`:583-628`（`vitalsOf/attrRows/skillRows/charStatusText`）；只改 Wrap → 现有测试**没有**按文字断言主卡属性行，`test/p11_status_bar_test.dart`、`test/room_ui_pl_test.dart:181`（`GpPlCharCardKeys.status`）不受影响。

---

### P-2　战斗模式没自动展开战斗信息栏到置顶（所有信息流最上方）

**一行结论**：玩家侧战斗信息栏 `RoomSlot.gpPlCombat` 只是 `GpCombatList()`，在 `folded` 档默认**折叠成方块**、在 dock 档是右列第 3 格；工程里**没有任何「置顶 / pin」现成机制**，需要新建（改展开白名单 + 顺序 + 战斗态强制展开）。

**证据与现状**
- `lib/ui/room/room_game_page.dart:827-829`：
  ```dart
  case RoomSlot.gpCombat:
  case RoomSlot.gpPlCombat:
    return const GpCombatList();
  ```
  无展开/置顶逻辑。
- 玩家 dock 树 `lib/ui/room/widgets/room_layout.dart:162-202`（`roomDockPlanOf(isKp:false)`）：`gpPlCombat` 在 `:181`，位于右侧竖列 `gpPlScene / gpPlMates / gpPlCombat / gpPlSketch / gpPlNotes`（flex 20）**第 3 位**，不是最上方。本批玩家档是 folded，这棵树不动（`test/p10_t3_layout_test.dart:111-130` 钉死落位表）。
- `lib/ui/room/room_keys.dart:116-130` `plSlots` 顺序：`gpTopbar, gpPlCharCard, gpPlMap, gpPlChat, gpPlLog, gpPlCombat(第6), gpPlScene, gpPlMates, gpPriv, gpPlSketch, gpPlNotes, gpToolbar, gpStatus`。
- 折叠档展开白名单 `lib/ui/room/room_game_page.dart:99-108`：
  ```dart
  const List<RoomSlot> kPlExpandedSlots = <RoomSlot>[
    RoomSlot.gpPlCharCard,
    RoomSlot.gpPlScene,
  ];
  ```
  **`gpPlCombat` 不在白名单** → 默认进方块区（`roomFoldedSlots` `:120-129`），由 `roomOrderedContentSlots`（`:75-90`，单列把 `gpPriv` 提到第一位）排在聊天/记录方块附近。
- `_foldedContent`（`room_game_page.dart:634-680`）：先渲染 `expanded`（展开面板，`:661-668`），再用 `Wrap` 平铺 `squares`（`:669-676`）；`:665-667` 用 `local.isFolded(slot.name)` 决定展开还是方块。
- `lib/ui/room/room_ui_local.dart:31` `folded`（Set）、`:114-123` `toggleFold/isFolded/setFold`；`:39` `combatPanelCollapsed` 是 **KP** 战斗面板开关（`:126-130` `setCombatPanelCollapsed`），与玩家档无关。
- **「置顶」机制核查**：全 `lib/ui/room/**` 搜 `RoomFeedFlash|pinned|置顶|class .*Flash|pin\(` → 只命中 `lib/ui/room/room_feed_flash.dart:38` `FeedFlashTracker`、`lib/ui/room/widgets/room_layout.dart:513` `RoomFlashBoard`、`:478` `_PaneFlash`，**全部是「新消息角标」语义**（`room_game_page.dart:282-285` `flashBoard`、`RoomFlashBoard.refresh` `:534-567` 只返回 `{chat, record, priv} → bool`），没有 pin/置顶。`RoomUiLocal` 也没有任何 pin 字段。**结论：无现成置顶机制，须新建。**
- 战斗态判据：`lib/ui/room/view/room_view.dart:96` `isCombat(state)`（`room_game_page.dart:818` 已用于 KP 分支）。

**建议落点（三处，最小）**
1. `room_game_page.dart:105-108` `kPlExpandedSlots` 加入 `RoomSlot.gpPlCombat`，并**排到最前**（`roomExpandedSlots` `:111-117` 用 `for (final s in slots) if (want.contains(s))` 按 `plSlots` 顺序返回，需单独把 `gpPlCombat` 前置），使战斗信息栏落在 `_foldedContent` 展开区的第一行 —— 即 `_AdventureSection` 之外「所有信息流（聊天/记录/私密方块）最上方」。
2. 「自动展开」：战斗态 `isCombat(state)` 时忽略 `local.isFolded('gpPlCombat')`（`:665-667`），或进战斗态时 `scope.local.setFold('gpPlCombat', false)`（`room_ui_local.dart:121-123`）。
3. **不要动** `roomDockPlanOf` 玩家图（P16 明确「玩家图整段一字未改」，`room_layout.dart:100-102` 注释）与 `_bodyOf`（`:808-878`），否则 `p10_t3_layout_test.dart:111-130` 与 `room_ui_wiring_test.dart:131`（`_inSlot(RoomSlot.gpPlCombat, GpCombatList)`）转红。

**会撞到的既有测试**：`test/room_ui_wiring_test.dart:131`（gpPlCombat→GpCombatList，只要不改 `_bodyOf` 就绿）；`test/p10_t3_layout_test.dart:111-130`（dock 落位表，别动）；折叠档展开/折叠纯函数 `roomExpandedSlots/roomFoldedSlots/roomOrderedContentSlots` 的既有断言（`test/room_ui_gap_fill_test.dart`、`test/room_ui_harness_test.dart` 系列，按名搜 `roomExpandedSlots|roomFoldedSlots|roomOrderedContentSlots`）；`test/p10_t7_c_combat_test.dart:874-897`（`combatPanelCollapsed`，仅 KP，别误改）。

---

### P-3　玩家缺「申请治愈疯狂状态」「申请治愈重伤」按钮 + 昏迷/疯狂状态锁定审查

**一行结论**：domain 早有两个现成「申请」action（`madness.cure` / `sheet.healwound`，均 `[player,kp]+RoomConfirm.kp`），载荷 `{'seat': seat}` 即可，KP 侧 `RoomRequestWatcher` 已有接收弹窗；**建议把两个按钮放进 `sheet_misc.dart`「更多工具」弹层**（同时满足「锁定期间只能点推进1轮和更多工具」）。**锁定审查结论：现状不符合**——角色卡局部符合，工具栏与「保存到已保存」全部漏网。

#### （a）申请按钮的现成链路
- POLICY 表 `lib/domain/room_types.dart`：
  - `:269-272` `'madness.cure': RoomPolicyEntry([player, kp], RoomConfirm.kp)` ← **申请治愈疯狂状态**
  - `:307-310` `'sheet.healwound': RoomPolicyEntry([player, kp], RoomConfirm.kp)` ← **申请治愈重伤**
  - 旁证：`:265-268` `madness.advance`（`null`，无需确认）、`:311-314` `aid.apply`、`:315-318` `aid.psycho`、`:244` `dice.request`、`:258` `state.request`、`:288` `check.request`。
- 权威端锁定白名单 `lib/domain/room_model_host_intent.dart:95-111` `_passSelf`：`act` 仅放行 `madness.advance / madness.cure / sheet.healwound`（`:106-108`）；`:128-133` `locked && !_passSelf(op,p)` 直接回 `_lockedHint`。**即锁定期间这两个申请本来就被允许发**。
- domain 实现 `lib/domain/room_model_actions_sheet.dart:345-358`（dispatch）：
  - `sheet.healwound` → `healWound(bySeat,p)`（`:1497-1559`）：`p['seat']` 可选，空时 `bySeat != kHostSeat ? bySeat : ''`（`:1499-1501`）；**玩家只能治自己**（`:1502-1505`）；要求 `body=='重伤'` 或 `dying`/`unconscious`（`:1525-1531`）。
  - `madness.cure` → `cureIndefinite(bySeat,p)`（`:1955-1993`）：同样 `p['seat']` 可选、默认本人（`:1957-1962`）；**只治「不定疯狂 / 潜在疯狂」**（`:1981-1993`，临时疯狂提示「请点『推进 1 轮』」）。
- KP 侧现成入口（可抄载荷与文案）：`lib/ui/room/sheets/sheet_kp_directives.dart:47-48`
  ```dart
  KpDirective(op: 'madness.cure', label: '治愈疯狂状态', icon: Icons.healing),
  KpDirective(op: 'sheet.healwound', label: '治愈重伤', icon: Icons.medical_services),
  ```
  `:157-160` `kpDirectivePayload` 两 case 都 `return <String,Object?>{'seat': seat};`。
- KP 接收弹窗 `lib/ui/room/room_request_watcher.dart:160-179`：`hostRead.pending` → `RoomPushRequest(reply: RoomPushReply.confirm, payload: {'op':op,'by':by})`，点「同意」→ `INTENT.CONFIRM`（`:383-391`）。
- 玩家「治疗」弹层现状 `lib/ui/room/sheets/sheet_treat.dart:65-69` `_kTreatKinds` 只有 `急救/医学/精神分析`（`aid.apply`×2 / `aid.psycho`），`:21-22` 注释明说「domain 另有 `sheet.healwound`（治愈重伤，只能治自己），用户三选一未包含，本弹层不提供该分支」；`:110-124` `_submit` 组 `{seat, targetSeat, skill?}` 后 `hostAction(kind.op, payload)`。
- 玩家「更多工具」弹层 `lib/ui/room/sheets/sheet_misc.dart:255-286`「本机工具」Wrap（现有 `音乐控制台` `MiscSheetKeys.musicEntry`、`:269-281` `导出游戏历史`）；`:282-284` 注释说 P16 已删 AI RP 指引件。

**建议落点 + 载荷**
- 首选：`sheet_misc.dart:255-286` 新增一节（例如「申请 / 自助」，与「本机工具」分开，因为这两个是**权威动作**、不是纯本机），放两个 `RoomTap`：
  ```dart
  // 申请治愈疯狂状态
  key: RoomKeys.action('madness.cure'),
  onTap: () => scope.controller.hostAction('madness.cure', {'seat': scope.session.seat}),
  // 申请治愈重伤
  key: RoomKeys.action('sheet.healwound'),
  onTap: () => scope.controller.hostAction('sheet.healwound', {'seat': scope.session.seat}),
  ```
  载荷与 `kpDirectivePayload`（`sheet_kp_directives.dart:157-160`）及 domain 默认值（`bySeat` 兜底）同口径；空 `{}` 也能跑，但显式 `seat` 更稳。`enabled` 用 `gate.can(op)`（T-30，见 `gp_toolbar.dart:16-18`）。
  **选这里的理由**：用户要求「昏迷/疯狂时只能点『推进1轮』和『更多工具』」，两个申请放「更多工具」弹层正好是允许的入口，且 `_passSelf` 放行；若放角色卡 `if (!locked)`（`:221-299`）内，昏迷/疯狂时反而**看不到**按钮，与诉求相悖。
- 备选：`sheet_treat.dart:65-69` `_kTreatKinds` 追加两项（但弹层标题「治疗」/「选队友」流程要改，且 `sheet.healwound`/`madness.cure` 只能治自己，与现有「选队友」UI 冲突，改动更大）；或 `gp_pl_char_card.dart` 放在 `if (!locked)` **之外**、紧邻「推进 1 轮」（`:345-363`）另起一行（但会让角色卡更挤，且 `p16_button_unify_test.dart` 的卡片分组表要重写）。
- 提示施工方：`madness.cure` 语义只覆盖「不定/潜在疯狂」，`sheet.healwound` 只治自己；按钮 `hint` 要如实写，别承诺「治愈所有疯狂」。

#### （b）昏迷/疯狂状态锁定审查（**现状：不符合**）
- 判据函数：`lib/ui/room/view/member_view.dart:167-175`
  ```dart
  bool operationLocked(mem) {          // 死亡 / 濒死 / 昏迷 / 永久疯狂 / 临时疯狂 / 不定疯狂
    if (mem == null) return false;
    final st = _statusOf(mem);
    if (st['body'] == '死亡') return true;
    if (jsTruthy(st['dying']) || jsTruthy(st['unconscious'])) return true;
    return _hasMental(mem,'永久疯狂')||_hasMental(mem,'临时疯狂')||_hasMental(mem,'不定疯狂');
  }
  ```
  `:163-164` `isRipped` = 死亡 / 永久疯狂；字段名：`sheet.status` 的 `body` / `dying` / `unconscious` / `mental[]`（`:155-160` `_hasMental`）。权威端同源判据 `_memberLocked`（`room_model_host_intent.dart:129`）。
- 角色卡 `gp_pl_char_card.dart`：`:106-107` `locked = operationLocked(me)` / `ripped = isRipped(me)`；`:221-299` `if (!locked)` 包住 4 个短按钮（状态管理/急救/物品/AI RP）→ **这几项符合**；`:159-173` locked 文案 `'操作受限：只能「推进 1 轮」或申请治愈'`；`:345-363` `if (!ripped && gate.can('madness.advance'))`「⏩ 推进 1 轮」→ **符合**。
- **三处漏网（不符合的证据）**：
  1. `:317-344`「保存到已保存」只判 `gate.can('state.self')`，**不在 `if (!locked)` 内** → 昏迷/疯狂仍可点。
  2. `gp_toolbar.dart:129-174` 全部按钮 `enabled` 只依据 `gate.can(op)`（`:152` `round.next`、`:162` `scene.mode`）或缩放无关；`gp_dice_bar.dart:234-365` 全部按钮 `enabled` 只依据 `editable`（`:223` `role != spectator`）或 `gate.can(op)`（`:333/354` `combat.roll`/`check.opposed`）。**整棵工具栏子树零 `operationLocked` 判定** → 昏迷/疯狂时奖励/惩罚/D100/其他骰子/自定义/暗骰/战技/对抗/治疗/更多工具/缩放全部仍可点。
  3. `_buildToolbar`（`room_game_page.dart:1006-1070`）注入的 `更多工具`(`miscToolsKey`,`:1041-1049`)、`治疗`(`treatKey`,`:1056-1066`) 同样只按 `!isKp` / `canOpenMisc`，与 locked 无关。
- 权威端其实**已经拦**：`room_model_host_intent.dart:128-133` + `_passSelf`（`:95-111`）在玩家 locked 时只放行 `madness.advance/madness.cure/sheet.healwound` 与 `chat/sync/ready/stateSync/char`，其余 act 一律回 `_lockedHint`。所以现状是「**权威端已拦、UI 未同步禁用**」——用户看到的按钮能点、点了发 intent 被拒，属于口径不一致。
- **统一禁用的最小落点（不要逐个按钮硬编码）**：
  - 在 `RoomScope`/`RoomController.gate` 或一个共享纯函数里派生「本人是否 locked」（`operationLocked(findMe(state, seat))`，`gp_pl_char_card.dart:433-434` 已有 `selfLocked(state, seat)` 顶层函数可复用）。
  - 在 **`_buildToolbar`（`room_game_page.dart:1006`）一处**把 `extensions` 整组用一个「统一闸门」包起来（例如给 `GpToolbar`/`GpDiceBar` 传一个 `bool actionsEnabled`，内部所有 `enabled` 改为 `actionsEnabled && 原判据`），并把角色卡 `保存到已保存`（`:317`）补 `!locked`；白名单保留「推进 1 轮」与「更多工具」两个入口。
  - ⚠ **T-30 契约冲突**：`gp_toolbar.dart:16-18`、`gp_dice_bar.dart:16-17` 明写「挂了 `RoomKeys.action(op)` 的按钮，`enabled` 必须**恰好**等于 `gate.can(op)`，不许叠加业务前置条件」，`test/room_ui_permission_test.dart` 用表驱动探针逐点读 `RoomTap.enabled`。叠加 `!locked` 会被判成漂移 → 施工时须**同步改探针口径**或把锁做在「结构上不渲染 / 拦截层」而不是改 `enabled`。这是本项最大的隐藏成本。

**会撞到的既有测试**：`test/qa_p5_priv_probe_test.dart:475-479`（locked 时 `stateBtn`/`aid.apply` 应 `findsNothing`）、`test/room_ui_pl_test.dart:242-248`、`test/room_ui_gap_fill_test.dart:104-120`、`test/p16_button_unify_test.dart:230-237 / 650-653 / 984-987`（卡片按钮分组表）、`test/room_ui_permission_test.dart:587`（`aid.apply` 探针）、`test/room_view_test.dart:318-328`（`operationLocked` 与权威端同判据）、`test/room_actions_test.dart:294-296`（`madness.cure`/`sheet.healwound`/`aid.apply` 的 POLICY 契约）、`test/room_ui_kp_test.dart:892-899`（KP 侧 `RoomKeys.action('madness.cure')` 定向指令）、`test/p16_wave1_sheets_test.dart:610-617`（治疗弹层三分支）。

---

### P-4　工具栏删「下一轮」「转战斗」+ 重排

**一行结论**：删 `gp_toolbar.dart:147-174` 两个 `RoomTapTile`；主组剩 2 个，建议把「更多工具 / 治疗」上提到主组 Wrap 并统一到 `diceTile`(90×40)，得到手机竖屏 **4 / 3 / 3 / 3 共 4 行**；此项会连坐 5+ 个钉死按钮集合/几何的测试。

#### 工具栏现在全部按钮、Key、尺寸档、分组/行数逻辑

**主组** —— `lib/ui/room/widgets/gp_toolbar.dart:107-186`，外层 `Wrap(key: GpToolbarKeys.quickRow, spacing: 4, runSpacing: 2)`：

| # | 控件 | Key | 尺寸档 | enabled | 行号 |
|---|---|---|---|---|---|
| 1 | `100%` 缩放 | `GpToolbarKeys.zoomPercent` = `gpToolbar/zoomPercent` | 裸 `RoomTap` + `minSize: RoomBtnSize.toolbarTile`(80×40) + `clampBtnText`（**不定宽**，实测≈80×40） | 恒可点 | `:129-138` |
| 2 | 重置缩放（用户截图叫「全屏图标」，实际 `Icons.center_focus_strong`） | `RoomKeys.gpZoomReset` = `gpZoomReset` | `RoomTapTile(size: toolbarTile)` 80×40 | 恒可点 | `:139-145` |
| 3 | **下一轮** | `RoomKeys.action('round.next')` = `act/round.next` | `RoomTapTile(size: toolbarTile)` 80×40 | `gate.can('round.next')`（玩家侧 false） | `:147-155` **要删** |
| 4 | **转战斗 / 转探索** | `RoomKeys.action('scene.mode')` = `act/scene.mode` | `RoomTapTile(size: toolbarTile)` 80×40 | `gate.can('scene.mode')`（玩家侧 false） | `:156-174` **要删** |
| 5 | 扩展插槽 `Wrap(key: GpToolbarKeys.extensions)` | — | 内部自换行 | — | `:178-184` |

「下一轮 / 转战斗」确为 **KP 专属**：POLICY `lib/domain/room_types.dart:296` `round.next=[kp]`、`:257` `scene.mode=[kp]`；`gp_toolbar.dart:153/163` hint 写「只有 KP 能推进回合 / 切换模式」。但注意：它们在**三视角都恒渲染**（只是玩家侧 disabled），见 `test/room_ui_permission_test.dart:625-640`。

**扩展组** —— `lib/ui/room/room_game_page.dart:1006-1070` `_buildToolbar`，非 KP（玩家档）注入：
- `const GpDiceBar()`（`:1018`，容器 key `RoomKeys.gpDiceBar`）：
  - `rollGroup`（`gp_dice_bar.dart:233-274`，全部 `RoomTap` + `minSize: RoomBtnSize.diceTile`(90×40) + `.map(clampBtnText)`）：`奖励 N`(`GpDiceBarKeys.bonus`)、`惩罚 N`(`penalty`)、`D100`(`expr('1D100')`)、`其他骰子`(`otherDice`)。
  - `tailGroup`（`:280-365`）：`3D6+1` 输入框（`customExpr`，`SizedBox(width:68)`）、掷自定义（`rollCustom`）、`暗骰关/开`(`dark`)、`战技`(`RoomKeys.action('combat.roll')`, `gate.can`)、`对抗`(`act/check.opposed`, `gate.can`)、`...widget.extensions`。
- `更多工具` `:1041-1049`：`RoomGamePage.miscToolsKey` = `gpToolbar/miscTools`，`minSize: RoomBtnSize.toolbarWide`(90×40)，`if (!isKp && gate.can(kRoomHistoryExportPolicyOp))` → `openMiscSheet`。
- `治疗` `:1056-1066`：`RoomGamePage.treatKey` = `gpToolbar/treat`，`minSize: RoomBtnSize.toolbarWide`(90×40)，`if (!isKp)` → `openTreatSheet`。
- （KP 档另有 `KP` `kpPanelKey`(toolbarWide)、`BGM 场景`(diceLong 104×40)，本批玩家档不涉及。）
- `RoomBtnSize` 档位全表：`lib/ui/room/widgets/room_button_size.dart:41-122`（`toolbarTile 80×40`、`toolbarWide 90×40`、`diceTile 90×40`、`diceLong 104×40`、`charTile 104×40` …）。

**行数逻辑**
- `gp_toolbar.dart:104-107` `SingleChildScrollView > Padding > Wrap`，**高度由内容决定**（无横向滚动），页面 `ConstrainedBox(maxHeight: c.maxHeight * kToolbarMaxShare)`（`room_game_page.dart:421-430`，`kToolbarMaxShare=0.62` `:139`）。
- `GpDiceBar` 分档 `gp_dice_bar.dart:371-425`：窄档（`outer.maxWidth < _kGroupBelowWidth=600`，`:49`）用 `_balancedRows(<rollGroup+tailGroup>, diceMaxPerRow(w))` 显式切行（`:397-415`）；宽档单个 `Wrap`（`:417-422`）。`diceMaxPerRow = ((w-16)/(90+3)).floor().clamp(2,4)`（`:69-76`），`diceBalancedRowSizes(9, 3|4) = 3/3/3`（`:87-96`、`:155-157` 注释）。
- 用户截图的 5 行 = 主组 4 个（第1行）+ 骰子条 9 项按切行（第2-4 行）+ 扩展末尾「更多工具/治疗」（第5行）。

**建议（删哪两处 + 重排成几行几列）**
1. **删**：`gp_toolbar.dart:147-155`（`round.next` 的 `RoomTapTile`）与 `:156-174`（`scene.mode` 的 `RoomTapTile`），连同 `:113-127` 那段「主组 4 个按钮统一 80×40」的注释口径更新。删后主组只剩 `100%` + `重置缩放` 2 个。
2. **重排推荐**：把 `_buildToolbar`（`room_game_page.dart:1041-1066`）里的「更多工具」「治疗」从 `extensions` 末尾**上提到 `gp_toolbar.dart` 主组 Wrap**（与两个缩放按钮同组、同 `Wrap`），四个都统一 `RoomBtnSize.diceTile`(90×40) 定宽（`RoomTapTile`），并把 `100%` 也纳入定宽（它现在 `minSize` 不定宽，内容宽实测 87 > 80 才特殊，见 `:121-128`；改 90 后可直接用 `RoomTapTile`）。这样：
   - 第 1 行：`100% / 重置缩放 / 更多工具 / 治疗`（4 个 90×40）
   - 第 2~4 行：骰子条 9 项 → `3 / 3 / 3`
   - 合计 **4 行（4/3/3/3）**，比现状 5 行（4/3/3/2/2）少一行、每行数量稳定、全栏按钮同宽 90×40。
   - 若不想动 `_buildToolbar` 的注入结构，最小替代：只删两个按钮 → 主组 2 个 + 骰子条 3/3/3 + 末尾 2 个 = `2/3/3/2/2` 仍 5 行，整齐度改善有限，**不推荐**。
3. textScaler：主组新增/改动的定宽控件必须走 `RoomTapTile`（内部已 `clampBtnText`，`room_button_size.dart:220`）或显式包 `clampBtnText`（`:150-153`）；`100%` 若保留裸 `RoomTap` 必须保留 `clampBtnText`（`gp_toolbar.dart:129`）。
4. ⚠ 删掉的两个 `RoomKeys.action(...)` 按钮是 T-30 表驱动探针的锚点，删后 `test/room_ui_permission_test.dart:625-640` 与 `test/p10_t3_layout_test.dart:291-302/322-330` **必红**，需同步改测试（这是施工单要单列的成本）。

**会撞到的既有测试（P-4 重点）**
- `test/p10_t3_layout_test.dart:291-302`：`for (final Key key in [... round.next, scene.mode ...]) tester.getRect(find.byKey(key))` → **删按钮必红**；`:322-330` 横屏档也列了 `scene.mode`。
- `test/room_ui_permission_test.dart:625-640`：`alwaysRendered=['round.next','scene.mode']` 三视角 `findsOneWidget` + `enabled == gate.can(op)` → **必红**。
- `test/p16_button_unify_test.dart:188-198` `_p16ButtonGroups()['gpToolbar 主组']` 恰为 `[zoomPercent, gpZoomReset, round.next, scene.mode]`，`['gpToolbar 扩展'] = [kpPanelKey, miscToolsKey]` → **必红**（且 `:974` 注释钉死 `roomTapFixedGrid2` 2 列口径）。
- `test/p10_t6_layout_test.dart:303-311`（骰子条按钮 key 几何）、`test/p10_t3_layout_test.dart:276-289`（工具栏高度 >56、无横向滚动）、`test/p10_t5_music_synonym_layout_test.dart:381-387`（`zoomPercent` / `quickRow` 是 `Wrap`）。
- `test/p16_button_unify_test.dart:431-466`（`diceMaxPerRow` / `diceBalancedRowSizes` / `kDiceTileW == diceTile.width` / `charTile`），改按钮数会漂「9 项」假设。
- `test/fixtures/room_actions.json:34/36/204-206/216-218/5989…`（`A:apply:round.next` / `scene.mode` 的 POLICY oracle 契约）—— **UI 删按钮不需要改 fixtures，但别顺手改它**（逐字节契约）。

---

## 二、所有模式 4 项

### C-1　删玩家状态栏的 AI RP 和急救按钮（含「用户口径核实」）

**一行结论**：两个按钮都在 `gp_pl_char_card.dart`（`GpPlCharCardKeys.aiBtn` / `RoomKeys.action('aid.apply')`），可删；但用户「聊天栏和玩家工具栏有相同的按钮」**不属实**，须在报告里纠正（删后功能仍有去处，所以删除本身安全）。

**证据**
- `lib/ui/room/widgets/gp_pl_char_card.dart:45` `static const Key aiBtn = ValueKey<String>('gpPlCharCard/aiBtn');`，按钮本体 `:281-297`（`RoomTapTile`，`label:'AI RP'`，点开只弹「去聊天输入行点魔棒」指引，`:287-296`）。
- 急救按钮 `:245-268`：`roomKey: RoomKeys.action('aid.apply')`（= `act/aid.apply`，`lib/ui/room/room_keys.dart:90`），`label:'急救'`，`enabled: gate.can('aid.apply')`，`:262-266` 载荷 `{seat, targetSeat, skill:'急救'}`（P16 刚补齐）。
- 二者都在 `:221-299` `if (!locked)` 的 `roomTapFixedGrid2` 里（与「状态管理」`stateBtn`、`物品` `itemsBtn` 共 4 个短按钮，各 `RoomBtnSize.charTile` 104×40，固定 2 列）。

**核实「聊天栏和玩家工具栏有相同的按钮」——不属实，逐条**
- 聊天栏 **有** AI RP 真入口：`lib/ui/room/widgets/gp_feeds.dart:50` `GpFeedsKeys.aiRp = 'gpFeeds/aiRp'`，`:785-800` `ChatInputRow` 里的魔棒图标 `Icons.auto_awesome` → `openAiRpSheet`，结果只回填输入框。`gp_pl_char_card.dart:277-280` 注释也明说「AI RP 真入口是聊天输入行的魔棒图标，这里给的是指引」。
- 玩家工具栏 **没有** AI RP 入口：`room_game_page.dart:1016-1068` 的 `extensions` 只有 `GpDiceBar` + `更多工具` + `治疗`；「更多工具」弹层 `sheet_misc.dart:14-15/64-70/282-284` 的 AI RP 条目 P16 已删（`MiscSheetKeys.aiEntry/aiHint` 常量刻意保留但不再渲染）。
- 玩家工具栏 **没有** 急救 `aid.apply` 按钮：只有 `RoomGamePage.treatKey`（`gpToolbar/treat`，`room_game_page.dart:249/1056-1066`）打开 `openTreatSheet` 聚合弹层，弹层里才有 `急救/医学/精神分析` 分支（`sheet_treat.dart:65-69`），且**不发 `aid.apply` 到工具栏按钮本身**。急救按钮的 `RoomKeys.action('aid.apply')` 只钉在角色卡（`gp_pl_char_card.dart:247`），`room_game_page.dart:248` 注释明确「不挂 `RoomKeys.action('aid.apply')`（那个 key 已被角色卡急救按钮钉死）」。
- **结论**：用户把「角色卡里的 AI RP 指引 / 急救」与「聊天栏 AI RP 真入口 / 工具栏治疗弹层」混为「相同的按钮」。删状态栏两个按钮后：AI RP 走聊天输入行魔棒、急救走工具栏「治疗」弹层，**功能不丢**，删除可行；但施工单口径要写「删角色卡这两处」，不要写「删重复按钮」。

**会撞到的既有测试**
- `test/room_ui_entry_test.dart:785`：`expect(card.contains('GpPlCharCardKeys.aiBtn'), isTrue)` —— **源码字符串断言，删按钮后必红**。
- `test/p16_button_unify_test.dart:230-237`（`gpPlCharCard` 分组含 `aid.apply`/`aiBtn`）、`:650-653`（几何逐个 `getSize`）、`:984-987`（同分组）、`:688`（`'p1：aid.apply'` 文案）。
- `test/room_ui_pl_test.dart:245-248`、`test/room_ui_gap_fill_test.dart:118-120`（`aiBtn`/`aid.apply` 应存在/不存在）。
- `test/qa_p5_priv_probe_test.dart:479`（locked 时 `aid.apply` `findsNothing`）、`test/p16_wave1_theme_test.dart:131-142`（源码断言 `RoomKeys.action('aid.apply')` 与「不得发空参数」）、`test/p16_wave1_sheets_test.dart:610-617`。
- `test/room_ui_permission_test.dart:587`（`aid.apply` 在结构探针列表里）。

---

### C-2　舞台放置单位名字黑色看不清

**一行结论**：`MarksPainter` 把标点/单位名文字写死 `Color(0xff222222)`，与 C-4 的白板、暗色主题底色都不兼容；最小改法是给 `MarksPainter` 加 `labelColor` 构造参数，由 `gp_map_stage.dart` 按实际画布底色传对比色。

**证据**
- `lib/ui/room/painter/stroke_painter.dart:81-125` `MarksPainter`（`foregroundPainter`，画标点名字）；关键 `:109-119`：
  ```dart
  final label = roomText(m['label']);
  ...
  final tp = TextPainter(
    text: TextSpan(
      text: label,
      style: const TextStyle(color: Color(0xff222222), fontSize: 11),  // ← :114 写死近黑
    ),
    textDirection: TextDirection.ltr,
  );
  tp.layout(maxWidth: size.width);
  tp.paint(canvas, Offset(o.dx - tp.width / 2, o.dy + 10));
  ```
  `:86-95` `_markColor` 圆点色固定（蓝/黄/红）、`:107` 白色内芯 `0xffffffff`，**文字无背景板/无描边**，直接压在舞台底色上。
- 舞台底色：`lib/ui/room/widgets/gp_map_stage.dart:268-269` 外层 `ColoredBox(color: theme.colorScheme.surfaceContainerHighest)`、`:301-303` 内层 `Container` 同色（无底图时），暗色主题下是深色 → 黑字看不清。
- `lib/ui/room/room_theme.dart:11-17` `kDrawColors = ['#e74c3c','#f1c40f','#2ecc71','#3498db','#9b59b6']` 是 **KP 画笔 5 色**（`RoomUiLocal.toolColorIndex` 索引，`:47-53` `drawColor`、`:57-67` `colorArgb/drawColorArgb`），**不是标签文字色**；且本文件「纯 Dart、零 Flutter 依赖」（`:1-8`），**不能在这里放 `Theme` 取色**。
- ⚠ **两个 `0xff222222` 别搞混**：`stroke_painter.dart:135` `DoodlePainter({this.color = 0xff000000})` 的默认笔色 P16 已改成纯黑 `0xff000000`，`test/p16_wave1_theme_test.dart:64` 断言的是**这个**（`reason: '白板默认笔色必须是纯黑 0xff000000（原 0xff222222）'`）。C-2 要改的是 `MarksPainter` 的 `:114` 标签色，两者互不影响；别误改 `DoodlePainter`。

**建议落点**
- `stroke_painter.dart:81-84` 给 `MarksPainter` 加 `final Color labelColor`（或 `TextStyle`），`:114` 用它替换 `const TextStyle(color: Color(0xff222222))`。
- 构造处 `gp_map_stage.dart:310-313`（有 `theme`）：
  ```dart
  foregroundPainter: MarksPainter(marks, labelColor: <按画布底色算的对比色>),
  ```
  亮/暗都要能看清 → 按**实际画布底色**算，不要简单用 `theme.colorScheme.onSurface`：C-4 把「无公开素材」改成白板（亮暗都白）后，暗色主题 `onSurface` 是白 → 白底白字。（建议：白板时深色字，有底图时按 `Theme.of(context).brightness` 取 `onSurface`，或给文字加半透明对比底/描边。）
- 不要改 `room_theme.dart`（纯 Dart 约束）。

**会撞到的既有测试**：C-2 本身无直接按 `0xff222222` 断言（该字面量只在 `p16_wave1_theme_test.dart:64` 的 `reason` 文案里出现，针对 DoodlePainter）；`test/p10_t7_layout_test.dart:302`（`Container(color: surfaceContainerHighest)` 不透明铺盖断言，与 C-4 相关，改底色时留意）；`MarksPainter` 构造签名变化要同步所有调用点（Grep `MarksPainter(` 全库仅 `gp_map_stage.dart:312`）。

---

### C-3　奖励骰/惩罚骰只能加不能减/重置

**一行结论**：`setBonus/setPenalty` 的「归零」逻辑现成（传 0），UI 只缺减号与归零入口；落点 `gp_dice_bar.dart:234-251`，新增控件须过 `clampBtnText`，且会改变 `diceBalancedRowSizes(9,…)` 的「9 项」切行假设。

**证据**
- 控件 `lib/ui/room/widgets/gp_dice_bar.dart:234-251`：
  ```dart
  RoomTap(
    key: GpDiceBarKeys.bonus,
    label: '奖励 ${local.bonus}',
    icon: Icons.add_circle_outline,
    enabled: editable,
    minSize: RoomBtnSize.diceTile,
    onTap: () => local.setBonus(local.bonus + 1),   // :241 只能 +1
  ),
  RoomTap(
    key: GpDiceBarKeys.penalty,
    label: '惩罚 ${local.penalty}',
    icon: Icons.remove_circle_outline,
    enabled: editable,
    minSize: RoomBtnSize.diceTile,
    onTap: () => local.setPenalty(local.penalty + 1), // :250 只能 +1
  ),
  ```
  稳定 key：`GpDiceBarKeys.bonus = 'gpDice/bonus'`、`.penalty = 'gpDice/penalty'`（`:102-103`）——注意是**私有 key 类，不是 `RoomKeys`**。
- 状态与逻辑 `lib/ui/room/room_ui_local.dart:59-60` `int bonus=0; int penalty=0;`；`:159-172`：
  ```dart
  void setBonus(int v) { final n = v<0?0:(v>5?5:v); bonus=n; if(n>0) penalty=0; notifyListeners(); }
  void setPenalty(int v){ final n = v<0?0:(v>5?5:v); penalty=n; if(n>0) bonus=0; notifyListeners(); }
  ```
  → 夹取 0–5、互斥、**传 0 即归零**（`n>0` 才清另一侧，传 0 不会误清对面）。**归零不需要改状态层**，只缺 UI 入口。
- `.map(clampBtnText)`：`gp_dice_bar.dart:274`（rollGroup）、`:365`（tailGroup）；`clampBtnText` = `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.0)` 只包该子树（`room_button_size.dart:144-153`）。

**建议落点**
- 在 `:234-251` 两个 `RoomTap` 附近加「减」与「归零」控件（例如把每个 `奖励 N` 拆成 `- / 奖励 N / +` 三个小控件，或长按减、双击归零），回调 `local.setBonus(local.bonus - 1)` / `local.setBonus(0)`（`penalty` 同理，`enabled: editable` 保持）。
- 新增控件给稳定 key（建议扩 `GpDiceBarKeys`：`bonusMinus/bonusPlus/bonusReset/penaltyMinus/...`）；**只要新增固定尺寸控件，必须进 `rollGroup`/`tailGroup` 的 `.map(clampBtnText)`**（`:274/:365`）或套 `RoomTapTile`（内部已钳），否则 1.3/1.5/2.0 字号会溢出。
- ⚠ **项数变化连坐切行**：`gp_dice_bar.dart:83-96/155-157` 注释与 `diceBalancedRowSizes` 都假设「当前 9 项 → 3/3/3」，`diceMaxPerRow`（`:69-76`）以 90 宽算。加 4 个控件后 `items.length` 变，`_balancedRows`（`:158-166`）行数组合改变，`test/p16_button_unify_test.dart:440-447` 的 `diceBalancedRowSizes(9,3)=[3,3,3]` 等纯函数断言虽仍绿（函数不改），但**几何/行数类用例会红**。

**会撞到的既有测试**：`test/room_ui_roll_test.dart:231-293`（点 `GpDiceBarKeys.bonus` ×3 → `bonus:3/penalty:0`；`:261-293` 惩罚与互斥）—— 改 `onTap` 或拆按钮会红；`test/p16_button_unify_test.dart:199-208`（`gpDiceBar` 分组恰 8 个 key）、`:377-404`（几何逐点 `getSize`）、`:431-466`（`diceMaxPerRow`/`diceBalancedRowSizes`/`kDiceTileW`）；`test/p10_t6_layout_test.dart:303-311`（骰子条 7 个 key 列表）；`test/p10_t3_layout_test.dart:297`（`GpDiceBarKeys.bonus` 在工具栏可见断言）；`test/p10_t7_layout_test.dart:189-211`（`otherDice` 弹层）。

---

### C-4　素材舞台无公开素材时改白色背景（白板，亮暗主题都白）

**一行结论**：`gp_map_stage.dart` 有两处底色（`ColoredBox` + 内层 `Container`）都取自 `theme.colorScheme.surfaceContainerHighest`，判空口径是 `assets.isEmpty`；改成 `Colors.white`（硬白，不跟主题）即可，注意别影响 P16 的 KP 战斗态切换与 C-1 的全局半透明。

**证据**
- 判空：`lib/ui/room/widgets/gp_map_stage.dart:253` `final assets = publicAssets(state);`（`lib/ui/room/view/scene_view.dart:94` `publicAssets`）；`:262-263` `final cover = assets.isEmpty ? null : assets.last;`；空态文字判据 `:315` `if (assets.isEmpty && strokes.isEmpty && marks.isEmpty)`（**三空**），`:317-324` `Text(... style: theme.textTheme.bodySmall)`。
- 两处底色：
  - `:268-269` `ColoredBox(color: theme.colorScheme.surfaceContainerHighest, child: Center(...))` —— 整个格子。
  - `:294-306` 内层 `Container` `color: cover == null ? theme.colorScheme.surfaceContainerHighest : Colors.transparent`（`:301-303`），`border: Border.all(color: theme.dividerColor)`。
- `room_game_page.dart:824-826`（`gpPlMap`→`_mapStage(readOnly:true)`）、`:885-890` `_mapStage` 唯一构造处；`_slotView` `:774-777` 给 `gpMap/gpPlMap/gpKpLeft` 紧约束 `ClipRect`（本批不动）。

**建议落点**
- `gp_map_stage.dart:268-269` 与 `:301-303`：当 `assets.isEmpty`（或 `cover == null`）时用 `Colors.white`（**硬编码白，不跟 theme，满足「亮暗主题都白」**），有公开素材时保持 `Colors.transparent`（内层）/ 原样（外层可保留或一并白，按视觉口径定）。
- 同步把 `:317-324` 空态提示文字改成深色（否则暗色主题下 `bodySmall` 浅字压在白板上看不清）；`:380-383` KP 素材计数文字同理。
- ⚠ **不要影响 P16「KP 战斗态 gpMap 换战斗列表」**：`room_game_page.dart:818-820` `if (isKp && isCombat(...)) return _combatStageCell(...)`、`:902-922` `_combatStageCell`（`combatPanelCollapsed` 二选一舞台/列表）。C-4 只改 `GpMapStage` 内部绘制，**不要动 `_bodyOf`/`_combatStageCell`**。
- ⚠ **C-1 的全局半透明**：P16 改的是 `lib/theme.dart` 的 `cardTheme.color = Palette.surface.withValues(alpha: 0.85)`；舞台是 `ColoredBox`/`Container` 不是 `Card`，不受影响，但**别把白色写成 `.withValues(alpha:…)`**（否则又半透明、露出游戏页背景图），也别把白色抬到页面/Theme 层。
- ⚠ 与 **C-2 冲突**：白板（亮暗都白）后，C-2 的标签取色必须按「实际画布底色」算对比色，不能只用 `theme.colorScheme.onSurface`（暗色主题是白字 → 白底白字）。两项须同批协同。

**会撞到的既有测试**：`test/p10_t7_layout_test.dart:302`（注释断言 `Container(color: surfaceContainerHighest)` 不透明铺满会盖住底图 —— 改「无素材」分支不影响「有底图」分支，但要确认用例测的是哪种状态）；`test/p10_t7_c_combat_test.dart:874-897`（`combatPanelCollapsed` 默认 false → 战斗列表）；`test/room_ui_wiring_test.dart`（gpMap/gpPlMap 槽位接线）；`test/p16_wave1_theme_test.dart`（主题类断言）。Grep 未发现**直接按 `surfaceContainerHighest` 颜色值**断言的测试。

---

## 三、APP 首页 1 项

### H-1　头图文字调整

**一行结论**：全部在 `lib/ui/home_page.dart` 的 `_HomeHeader`（`:478`，build `:546-674`）；删 `COC 7th`（`:574-581`）与「车卡器」（`:650-657`），把版本号 `Text`（`:662-670`，key `home_app_version`）移到 Header 第二行；**版本号现在在第三行**（车卡器文字下方）。

**证据（逐控件）**
- `home_page.dart:58-64` `CustomScrollView` slivers：`_HomeHeader(repo: repo)` → `_AdventureSection()` → `_RosterEntry(...)`；「开始冒险」栏 = `_AdventureSection` 的 `SectionBanner(title: '开始冒险')`（`:150-154`）。
- `_HomeHeader.build`（`:546-674`）是一个 `Column`：
  - `:553-648` `Row`：`Expanded(Text('骰境TRPG'))`（`:557-569`，26 号 `Palette.goldStr`）→ `SizedBox(10)` + `Container(1×18, Palette.borderStr)` + `SizedBox(10)`（`:571-573`）→ **`Text('COC 7th')`（`:574-581`，12 号 `Palette.textMute`）** → `PopupMenuButton(key: Key('home_menu'))`（`:582-645`）→ `SizedBox(6)`。
  - `:649` `SizedBox(height:6)`。
  - **`:650-657` `Text('克苏鲁的呼唤 第七版 · 车卡器')`**（12.5 号 `Palette.textMute`）—— Header 第二行。
  - `:658` `SizedBox(height:3)`。
  - **`:662-670` `Text(kAppVersionLabel, key: const Key('home_app_version'))`**（11 号 `Palette.textMute.withValues(alpha:0.8)`）—— Header **第三行 = 版本号现在的位置**。
- 版本号真源 `lib/app_version.dart`：`kAppVersion='2.29.0'`(`:15`)、`kAppBuildNumber=99`(`:18`)、`kAppVersionShort`(`:21`)、**`kAppVersionLabel='v$kAppVersion ($kAppBuildNumber)'`**(`:24`)、`kAppTitle='骰境TRPG'`(`:27`)。首页 `:21` `import '../app_version.dart';`。
- 文案常量核实：首页这 5 处**都是字面量，没有独立 key/常量**（`COC 7th` 的规范常量是 `lib/domain/rules_coc7.dart:873` `shortName='COC 7th'`，但首页**没引用它**；`kAppTitle` 也未被首页使用，首页写死 `'骰境TRPG'`）。搜过的关键词：`COC 7th|克苏鲁的呼唤|骰境TRPG|开始冒险|version|版本号|buildName|packageInfo` → 首页命中全部集中在 `home_page.dart:5/21/74/151/555/559/575/651/659-664`（另有 `app.dart:85` 的 `title:'骰境TRPG'`，非首页头图）。

**建议落点（精确）**
1. 删 `home_page.dart:574-581` 的 `Text('COC 7th')`；建议一并删 `:571-573` 的分隔线 `SizedBox+Container+SizedBox`（否则标题行右侧留一段孤立竖线），保留 `PopupMenuButton`（`home_menu`，多个测试依赖）。
2. 删 `home_page.dart:650-657` 的 `Text('克苏鲁的呼唤 第七版 · 车卡器')`。
3. 把 `:662-670` 的版本号 `Text` 上移到原「车卡器」位置（即 `:649` 的 `SizedBox(height:6)` 之后、`开始冒险` 栏之前的 Header 第二行），**保留 `key: const Key('home_app_version')` 与 `kAppVersionLabel` 文案不变**；`:658` 的 `SizedBox(height:3)` 一并清理。
4. 用户口径纠正见 §五：COC 7th 现状与「骰境TRPG」**同一行右侧**，不是「下方」；按括号说明「骰境TRPG 下方、开始冒险栏上方」施工 = 放到 Header 第二行。

**会撞到的既有测试**
- `test/app_version_test.dart:47-57`：只 `find.byKey(Key('home_app_version'))` + `t.data == kAppVersionLabel`，**不断言位置/几何** → 保留 key 与文案即**仍绿**。
- `test/create_flow_widget_test.dart:77/91/273`：`find.text('骰境TRPG')`、`find.text('克苏鲁的呼唤 第七版')` —— 后者是**规则选择页**（`step_rules.dart`）的文案，与首页 `'克苏鲁的呼唤 第七版 · 车卡器'` 是不同字符串，**不受影响**；`find.text('骰境TRPG')` 保留。
- 不受影响但要注意：`test/p8_home_ui_test.dart:72/151-173`、`test/p12_banner_inset_test.dart:29/66`（`开始冒险` 几何/颜色）、`test/p12_emoji_a_test.dart:58/160`、`test/p7_theme_test.dart:150/188`、`test/settings_page_test.dart:266`、`test/card_detail_edit_test.dart:219`（都用 `home_menu` / `开始冒险` / `骰境TRPG`）；`test/p7_share_badge_test.dart`、`test/p7_rule_registry_test.dart`、`test/p7_ai_caps_ui_test.dart` 里的 `COC 7th` 都是 `RuleRegistry.shortName` / share badge 数据，**不是首页 Header 文字**。
- Grep 未发现任何测试断言 `find.text('COC 7th')` 或 `find.text('克苏鲁的呼唤 第七版 · 车卡器')` 在首页上下文中 → **H-1 基本零转红**，是本批最安全的一项。

---

## 四、跨项重叠文件清单（施工单切批用）

| 文件 | 涉及项 | 冲突/协同点 |
|---|---|---|
| `lib/ui/room/widgets/gp_pl_char_card.dart` | **P-1**（属性区加 LUK）、**P-3**（申请按钮落点候选 + 锁定审查 + `保存到已保存` 补 `!locked`）、**C-1**（删 `aiBtn` / `aid.apply`） | **3~4 项同文件、且都动 `:194-299` 那一栏**，必须同批协同：`roomTapFixedGrid2` 固定 2 列（`:231`、`:298`）在 C-1 删掉 2 个按钮后只剩 2 个短按钮，P-3 若再加按钮会重新撑列；`p16_button_unify_test.dart` 的 `gpPlCharCard` 分组表要一次改到位 |
| `lib/ui/room/room_game_page.dart` | **P-2**（`kPlExpandedSlots` / `roomExpandedSlots` / `_foldedContent`）、**P-4**（`_buildToolbar` 扩展注入）、**C-4**（`gpMap`/`gpPlMap` 槽位、`_combatStageCell` 别动）、**C-1**（`miscToolsKey`/`treatKey` 定义 `:242-249`） | 4 项；`_bodyOf`(`:808-878`) 与 `roomDockPlanOf` 不许被任一项误改 |
| `lib/ui/room/widgets/gp_toolbar.dart` | **P-4**（删 2 按钮、重排）、**P-3**（锁定统一禁用的闸门注入点） | 同一 `Wrap`（`:107-186`）；P-3 的 `enabled` 叠加 `!locked` 会撞 T-30（`gp_toolbar.dart:16-18`） |
| `lib/ui/room/widgets/gp_dice_bar.dart` | **P-4**（按钮清单/重排）、**C-3**（加减归零）、**P-3**（锁定统一禁用） | `rollGroup`/`tailGroup` 项数变化连坐 `_balancedRows`/`diceBalancedRowSizes(9,…)`；新增控件须过 `.map(clampBtnText)` |
| `lib/ui/room/room_ui_local.dart` | **P-2**（`folded` / `setFold` / `combatPanelCollapsed`）、**C-3**（`bonus`/`penalty`/`setBonus`/`setPenalty`） | 两段互不冲突，但都在此文件，建议同批 |
| `lib/ui/room/widgets/gp_map_stage.dart` | **C-2**（`MarksPainter(marks, labelColor)` 构造处 `:312`）、**C-4**（`:268-269`/`:301-303` 白板 + 空态文字色） | **强冲突**：C-4 白板（亮暗都白）决定 C-2 标签必须取「按画布底色的对比色」，不能只按主题取 `onSurface`；两项必须同批 |
| `lib/ui/room/painter/stroke_painter.dart` | **C-2**（`MarksPainter` `:81-125`） | ⚠ 别误改 `:135` `DoodlePainter` 的 `0xff000000`（P16 已改，`p16_wave1_theme_test.dart:64` 钉死） |
| `lib/ui/room/sheets/sheet_misc.dart` | **P-3**（两个申请按钮首选落点 `:255-286`）、**C-1**（AI RP 指引件已删，`:282-284`） | 同一「本机工具」区；新增「申请」节与既有节要分开 |
| `lib/ui/room/sheets/sheet_treat.dart` | **P-3**（备选落点 `_kTreatKinds` `:65-69`） | 若选此落点须改「选队友」流程（`sheet.healwound`/`madness.cure` 只能治自己） |
| `lib/ui/room/widgets/room_button_size.dart` | **P-4** / **C-3**（`RoomBtnSize.*` 档位、`clampBtnText`、textScaler） | 只读复用，不建议改常量（会连坐 `p16_button_unify_test.dart:453-466`） |
| `lib/ui/home_page.dart` | **H-1** 独占 | 与其它 8 项零重叠 |
| 只读参考（禁改） | `lib/domain/room_types.dart`（POLICY）、`lib/domain/room_model_host_intent.dart`（`_passSelf`）、`lib/domain/room_model_actions_sheet.dart`（`healWound`/`cureIndefinite`）、`lib/ui/room/sheets/sheet_kp_directives.dart`（载荷范式）、`lib/ui/room/room_request_watcher.dart`（KP 接收）、`lib/ui/room/view/sheet_view.dart`（`attrRows`/`vitalsOf`）、`lib/ui/room/view/member_view.dart`（`operationLocked`/`bodyViewOf`） | P-1/P-3 的字段与载荷依据，均**不改** |

---

## 五、用户口径与代码现状不符的地方（单列，逐条）

1. **C-1「聊天栏和玩家工具栏有相同的按钮」——不属实**。
   - 聊天栏确有 AI RP **真入口**（`gp_feeds.dart:785-800`，`GpFeedsKeys.aiRp`，魔棒图标 → `openAiRpSheet`）；玩家**工具栏没有** AI RP 入口（`room_game_page.dart:1016-1068` 只有 `GpDiceBar`/`更多工具`/`治疗`，「更多工具」弹层的 AI RP 条目 P16 已删，`sheet_misc.dart:14-15/282-284`）。
   - 玩家**工具栏没有急救 `aid.apply` 按钮**；只有 `treatKey`「治疗」打开本机聚合弹层（`openTreatSheet`），弹层内才有「急救」分支（`sheet_treat.dart:66`）。`RoomKeys.action('aid.apply')` 只钉在**角色卡**（`gp_pl_char_card.dart:247`），`room_game_page.dart:248` 注释明确「不挂该 key」。
   - 正确口径：删的是**角色卡状态栏**里的「AI RP 指引」与「急救」两个短按钮；删后 AI RP 走聊天输入行魔棒、急救走工具栏「治疗」弹层，功能不丢，但**不是「删重复按钮」**。

2. **P-4「全屏图标」实际是「重置缩放」**。`gp_toolbar.dart:139-145` 的 `RoomKeys.gpZoomReset` 图标是 `Icons.center_focus_strong`（hint `'重置缩放'`），并非全屏；真正的全屏入口在角色卡 `GpPlCharCardKeys.fullscreen`（`gp_pl_char_card.dart:118-129`）与素材舞台 `GpMapStageKeys.fullscreen`（`gp_map_stage.dart:365-371`）。

3. **P-4「下一轮 / 转战斗是 KP 专属按钮」——权限属实、渲染口径不符**。POLICY 确为 `[kp]`（`room_types.dart:296/257`），但这两个按钮在 **kp/player/spectator 三视角都恒渲染**（只是玩家侧 `enabled=false`），`test/room_ui_permission_test.dart:625-640` 明确断言「三视角都存在」。用户说的「KP 专属」是**功能**专属，不是**显示**专属；删按钮会改变这条既有契约。

4. **H-1「COC 7th 在骰境TRPG 下方」——不符**。`home_page.dart:553-581` 里 `COC 7th` 与 `骰境TRPG` 在**同一个 `Row`**（标题右侧、分隔线之后）。「骰境TRPG 下方、开始冒险栏上方」当前是「克苏鲁的呼唤 第七版 · 车卡器」(`:650-657`) + 版本号(`:662-670`) 两行。**建议按用户括号里的位置语义施工**（把版本号放到 Header 第二行），而不是字面「原来 COC 7th 的行内位置」。

5. **P-3「申请治愈疯狂状态」的语义边界**。`madness.cure`（`room_model_actions_sheet.dart:1955-1993`）只治「不定疯狂 / 潜在疯狂」；「临时疯狂」提示点「推进 1 轮」自消，「永久疯狂」是撕卡（不可治）。`sheet.healwound`（`:1497-1559`）**只能治自己**，且要求当前 `重伤/濒死/昏迷`。按钮文案/`hint` 不能承诺「治愈所有疯狂 / 治别人」。

6. **P-3「昏迷或疯狂时什么都不能操作，只能点『推进1轮』和『更多工具』」——现状不符合**（详见 P-3(b)）：角色卡 4 个短按钮与「推进 1 轮」符合，但 `保存到已保存`（`gp_pl_char_card.dart:317-344`）仍可点、**整棵工具栏**（`gp_toolbar.dart` / `gp_dice_bar.dart` / `_buildToolbar`）零 `operationLocked` 判定，掷骰/奖惩/暗骰/战技/对抗/治疗/更多工具/缩放全部仍可点。权威端 `room_model_host_intent.dart:128-133` 已拦，UI 未同步 → 属「口径不一致」而非「功能全通」。另：用户说的两个白名单入口之外，角色卡 `保存到已保存` 是**第 3 个漏网按钮**，施工时要一并处理。

7. **C-4「无公开素材」的判空口径不唯一**。`gp_map_stage.dart:262-263` 用 `assets.isEmpty`（`cover==null`）决定是否画底图；`:315` 空态文字用 `assets.isEmpty && strokes.isEmpty && marks.isEmpty`（三空）。「无公开素材 → 白板」应以 `assets.isEmpty` 为准，但白板上若已有笔迹/标点，空态文字就不该出现 —— 两个判据要统一说明，别顺手把「有笔迹但无素材」也判成空白。

8. **P-2「自动展开到所有信息流最上方」——工程里没有现成「置顶」机制**。全库搜 `RoomFeedFlash|pinned|置顶|pin(` 零命中；`FeedFlashTracker` / `RoomFlashBoard` / `_PaneFlash` 全是「新消息角标」，与置顶无关；`RoomUiLocal` 也没有 pin 字段。「自动展开」要新建（改 `kPlExpandedSlots` + 顺序 + 战斗态忽略 `isFolded`），不是接现成开关。

---

## 六、预计转红的既有测试清单（按项汇总，供施工单排回归）

| 项 | 测试文件:行号 | 转红原因 |
|---|---|---|
| **P-4（必红）** | `test/p10_t3_layout_test.dart:291-302`、`:322-330` | key 列表含 `act/round.next`、`act/scene.mode`，`getRect(find.byKey)` 找不到 |
| **P-4（必红）** | `test/room_ui_permission_test.dart:625-640` | `alwaysRendered=['round.next','scene.mode']` 三视角 `findsOneWidget` |
| **P-4（必红）** | `test/p16_button_unify_test.dart:188-198`（`_p16ButtonGroups` 主组/扩展分组）、`:974` | 分组表钉死按钮集合 |
| **P-4/C-3** | `test/p16_button_unify_test.dart:431-466`（`diceMaxPerRow`/`diceBalancedRowSizes`/`kDiceTileW`/`charTile`）、`:199-208/:377-404` | 按钮数/尺寸/行数变化 |
| P-4 | `test/p10_t6_layout_test.dart:303-311`、`test/p10_t5_music_synonym_layout_test.dart:381-387`、`test/p10_t3_layout_test.dart:276-289` | 工具栏/骰子条几何、高度、Wrap 结构 |
| **C-1（必红）** | `test/room_ui_entry_test.dart:785` | 源码字符串断言 `card.contains('GpPlCharCardKeys.aiBtn')` |
| **C-1（必红）** | `test/p16_button_unify_test.dart:230-237`、`:650-653`、`:984-987`、`:688` | `gpPlCharCard` 分组含 `aid.apply`/`aiBtn`，逐点 `getSize` |
| C-1 | `test/room_ui_pl_test.dart:245-248`、`test/room_ui_gap_fill_test.dart:118-120`、`test/qa_p5_priv_probe_test.dart:479`、`test/room_ui_permission_test.dart:587` | 按钮存在/不存在、权限探针 |
| C-1 | `test/p16_wave1_theme_test.dart:131-142`、`test/p16_wave1_sheets_test.dart:610-617` | `aid.apply` 载荷源码断言、治疗弹层分支 |
| **C-3（必红）** | `test/room_ui_roll_test.dart:231-293` | 点 `bonus` ×3 → `bonus:3`；拆分/改 `onTap` 后点击路径变 |
| C-3 | `test/p10_t3_layout_test.dart:297`、`test/p10_t6_layout_test.dart:303-311`、`test/p16_button_unify_test.dart:199-208/:377-404` | 骰子条 key 集合与几何 |
| **P-3（必红，若动 `enabled`）** | `test/room_ui_permission_test.dart:587` 及全部 T-30 探针、`test/qa_p5_priv_probe_test.dart:475-479`、`test/room_ui_pl_test.dart:242-248`、`test/room_ui_gap_fill_test.dart:104-120` | `enabled` 叠加 `!locked` 违反「恰好等于 `gate.can(op)`」 |
| P-3 | `test/room_actions_test.dart:294-296`、`test/room_ui_kp_test.dart:892-899`、`test/room_view_test.dart:318-328` | POLICY / KP 定向指令 / `operationLocked` 契约（新增按钮若复用 `RoomKeys.action` 要注意探针） |
| P-1 | `test/room_view_test.dart:288`、`:583-628` | **仅当改 `attrRows` 时**；只改 Wrap 则绿 |
| P-2 | `test/room_ui_wiring_test.dart:131`、`test/p10_t3_layout_test.dart:111-130` | 前者不改 `_bodyOf` 即绿；后者别动 `roomDockPlanOf` |
| P-2 | 折叠档展开纯函数断言（`roomExpandedSlots`/`roomFoldedSlots`/`roomOrderedContentSlots`） | 改白名单/顺序后需同步 |
| C-2 | `test/p16_wave1_theme_test.dart:64` | **仅当误改 `DoodlePainter` 默认笔色 `0xff000000` 时**；改 `MarksPainter` 不影响 |
| C-2/C-4 | `test/p10_t7_layout_test.dart:302`、`test/p10_t7_c_combat_test.dart:874-897` | 舞台 `Container` 不透明铺盖 / KP 战斗面板切换 |
| **H-1（基本不红）** | `test/app_version_test.dart:47-57` | 只按 `home_app_version` key + `kAppVersionLabel` 文案，**不断言位置** → 保留 key 与文案即绿 |
| H-1 | `test/create_flow_widget_test.dart:77/91/273`、`test/p8_home_ui_test.dart`、`test/p12_banner_inset_test.dart`、`test/p12_emoji_a_test.dart`、`test/p7_theme_test.dart` | 用 `骰境TRPG`/`开始冒险`/`home_menu`，均不受删两段文字影响；`克苏鲁的呼唤 第七版` 是规则选择页文案（不同串） |

**契约红线提醒**：`test/fixtures/room_actions.json`（`:34/36/204-206/216-218/5989…` 含 `round.next`/`scene.mode` 的 POLICY oracle）是**逐字节契约，禁改**；删 UI 按钮不需要动 fixtures，但 `room_ui_permission_test`/`p16_button_unify_test` 这类断言「按钮恒渲染」的用例必须同步重写，不能靠改 fixtures 绕过。

---

## 七、未找到 + 搜过的关键词

- **`RoomFeedFlash` 类 / pin / 置顶机制**：搜 `RoomFeedFlash|pinned|置顶|class .*Flash|pin\(`，范围 `lib/ui/room/**/*.dart` → 零命中（只有 `FeedFlashTracker`@`room_feed_flash.dart:38`、`RoomFlashBoard`@`room_layout.dart:513`、`_PaneFlash`@`:478`，全是角标语义）。**结论：工程无置顶机制**。
- **`room_view.dart` 里的 `bodyViewOf` 之类取值 helper**：`bodyViewOf` 实际在 `lib/ui/room/view/member_view.dart:124-132`（`room_view.dart:96` 只有 `isCombat`）；搜 `bodyViewOf` 全库命中 `member_view.dart`、`sheet_view.dart:113`、`room_game_page.dart:40/1096`、`gp_pl_char_card.dart` 注释。**`room_view.dart` 里没有 bodyViewOf**。
- **首页 `COC 7th` / 车卡器文字的独立 key 或文案常量**：未找到 —— 都是 `home_page.dart:575` / `:651` 的字面量；搜 `COC 7th|克苏鲁的呼唤|骰境TRPG|开始冒险|version|版本号|kAppTitle` 确认 `kAppTitle`/`kAppVersion*` 在 `lib/app_version.dart:15-27`、`COC 7th` 常量在 `lib/domain/rules_coc7.dart:873`（首页未引用）。`COC 7th` 无 widget key。
- **玩家工具栏里的 AI RP / 急救按钮入口**：未找到 —— 搜 `aiBtn|aiRp|aid.apply|treatKey|miscToolsKey` 后确认 `GpFeedsKeys.aiRp` 在 `gp_feeds.dart:50/787`，`aid.apply` 按钮只在 `gp_pl_char_card.dart:247`，工具栏只有 `RoomGamePage.treatKey`（`room_game_page.dart:249/1058`，打开弹层）。
