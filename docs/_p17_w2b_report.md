# P17 波2-B 交付报告 · 玩家工具栏重排（P-4）+ 奖惩骰加减归零（C-3）+ 锁定参数接入（P-3）

> worker：**p17-w2b（寇豆码）**
> 工程根 `$P = C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
> 独占文件（**只改了这两个**）：
> - `lib/ui/room/widgets/gp_toolbar.dart`
> - `lib/ui/room/widgets/gp_dice_bar.dart`
>
> 未跑 `flutter test`（并发期纪律）；自检只有 `dart analyze`（两个文件 + 全 `lib` 均 `No issues found!`）。
> 未改 `pubspec.*` / `app_version.dart` / `room_button_size.dart` / `room_game_page.dart` / 任何既有测试 / 未新建测试。

---

## 0. 一句话结论

P-4 两个废按钮（`round.next` / `scene.mode`）已三视角删除、骰子条保持 **9 条目 ⇒ 3/3/3**；C-3 把「奖励 / 惩罚」改成 `[−] [奖励N] [↺]` **三段式复合控件**（条目数不变、状态层零改动、旧语义逐字保留）；P-3 两个组件都接上了 `bool locked = false`，骰子条内全部按钮叠 `!locked`、缩放两件**故意不叠**；另加 `mainActions` 插槽，让 W2-A 能把「更多工具 / 治疗」放上第 1 行，凑成目标 **4 行 4/3/3/3**。

**改动后 sha256**
```
4f242601d99b6456dc7ce5def540999572d37128ca868b67b5d46e1b773d273d *lib/ui/room/widgets/gp_toolbar.dart   (241 行)
3cd024b3ab76ce6802599f5908d3236c1f1f3b3611959be21480a3bf1b42e3d6 *lib/ui/room/widgets/gp_dice_bar.dart (627 行)
```

---

## 1. P-4 · 删「下一轮」「转战斗」

### 1.1 删除点（`gp_toolbar.dart`）

| 原位置 | 原内容 | 现状 |
|---|---|---|
| `P16 版 :147-155` | `RoomTapTile(roomKey: RoomKeys.action('round.next'), label:'下一轮', enabled: gate.can('round.next'))` | **删除**（源码坐标为改动前的版本；现文件 `:196-211` 是一段说明注释，见下） |
| `P16 版 :156-174` | `RoomTapTile(roomKey: RoomKeys.action('scene.mode'), label: isCombat?'转探索':'转战斗', onTap: 战斗→combat.end / 探索→showCombatSheet)` | **删除** |

删除后随之清理（否则 `dart analyze` 报 unused）：
- `import '../sheets/sheet_combat.dart' show showCombatSheet;` → 删
- `import '../view/room_view.dart';`（只为 `isCombat`）→ 删
- `_bar()` 里 `final controller` / `final gate` / `final state` 三个局部 → 删

**key 常量保留说明**（现文件 `:196-211` 注释，逐字）：
```
//   ⚠️ `RoomKeys.action('round.next')` / `('scene.mode')`
//   的 key 构造器在 `room_keys.dart`，是 POLICY oracle 的锚点，
//   保留不动 —— 只是全库不再有 UI 使用点（P17 起）。
```
> 事实核对：这两个 key 由 `room_keys.dart#action(String op)` **函数生成**，不是本文件的常量，所以「保留 key 常量」= 不动 `room_keys.dart`（本批谁都没动它）。POLICY / `test/fixtures/room_actions.json` 的 `round.next` / `scene.mode` 条目**一字未改**。
>
> 能力核对（删 UI 不等于删功能）：
> - KP 的「推进回合」还有两处入口：`sheet_kp_panel.dart:299-303`（`round.next`）、战斗信息栏 `combat.next`。
> - KP 的「切战斗 / 探索」还有：`room_lobby_page.dart:744-776`（`scene.mode` + `combat.end` + `showCombatSheet`）、`sheet_kp_panel.dart:165`。
> ⇒ 删的确实只是玩家侧恒灰、KP 侧重复的**工具栏**入口。

### 1.2 重排：主组 4 → 2，靠插槽补满第 1 行

`gp_toolbar.dart:67-104`（构造契约）：
```dart
const GpToolbar({
  super.key,
  this.extensions = const <Widget>[],
  this.mainActions = const <Widget>[],   // P17 新增
  this.locked = false,                   // P17 新增（P-3 契约）
});
```
`gp_toolbar.dart:210-218`（主 Wrap 内部顺序）：
```dart
// ---- 主组动作（P17 新增插槽） ----  「更多工具 / 治疗」扁平进第 1 行
...mainActions,
// ---- 扩展插槽 ----
Wrap(key: GpToolbarKeys.extensions, spacing: 4, runSpacing: 2,
     crossAxisAlignment: WrapCrossAlignment.center, children: extensions),
```

**为什么必须新增这个插槽（实测出的布局硬事实，请 W2-A 务必照做）**：
1. 骰子条在窄档是 `Container(width: double.infinity)`（`gp_dice_bar.dart:451`）⇒ 它出现在哪个 `Wrap` 里，那个 `Wrap` 的宽度就恒等于可用宽。
2. `extensions` 是**嵌套** `Wrap`（key `GpToolbarKeys.extensions`，`room_ui_shell_test.dart:408` 钉死它必须存在），外面 `quickRow` 把这条嵌套 Wrap 当作**一个整体**换行。
3. ⇒ 只要「更多工具 / 治疗」待在 `extensions` 里，它们**永远不可能**和缩放按钮同一行：第 1 行必然只剩 2 个（实测结论，不靠猜）。
4. 放进 `mainActions` 后：`80 + 80 + 90 + 90 + 3×4 = 352 ≤ 400`（412dp 档可用宽 400）⇒ **第 1 行恰好 4 个**，接着骰子条独占一段三行 → 全栏 **4 行 = 4 / 3 / 3 / 3**。

> ⚠️ 360dp 档：`80+80+90+90+12 = 352 > 348` ⇒ 第 4 个按钮（治疗）会掉到第 2 行，变成 3/1/3/3/3。这是 360dp 的物理极限（`toolbarTile` 80、`toolbarWide` 90 两个常量本批不许改），**建议波4 的「每行 3 或 4 个」口径按 412dp 档断言，360dp 只断言「无溢出 + 行数 ≤ 5」**。

### 1.3 重排前后对照表

> 「所在行」= 手机 412dp 竖屏、`mainActions=[更多工具, 治疗]`、`extensions=[GpDiceBar]` 时的落位。

| # | 按钮 / 控件 | Key | 尺寸档 | 改前 | 改后 | `enabled` 表达式（改后） |
|---|---|---|---|---|---|---|
| 1 | 缩放百分比 | `GpToolbarKeys.zoomPercent` | `toolbarTile` 80×40（`minSize`，不定宽，实测 ≈87） | 行1 | 行1 | 恒可点（**白名单：纯视图**） |
| 2 | 重置缩放（用户口中「全屏图标」） | `RoomKeys.gpZoomReset` | `toolbarTile` 80×40 | 行1 | 行1 | 恒可点（**白名单：纯视图**） |
| 3 | ~~下一轮~~ | ~~`act/round.next`~~ | — | 行1 | **删除** | — |
| 4 | ~~转战斗/转探索~~ | ~~`act/scene.mode`~~ | — | 行1 | **删除** | — |
| 5 | 更多工具（extensions，W2-A 注入） | `RoomGamePage.miscToolsKey` | `toolbarWide` 90×40 | 行5 | **行1**（改走 `mainActions`） | 注入方定（白名单：恒可点） |
| 6 | 治疗（extensions，W2-A 注入） | `RoomGamePage.treatKey` | `toolbarWide` 90×40 | 行5 | **行1**（改走 `mainActions`） | 注入方定：**建议 `!locked`** |
| 7 | 奖励骰 `[−][奖励N][↺]` | `bonusMinus` / **`bonus`** / `bonusReset` | 三段各 `minSize` (0,40)（内容宽：30 / ≈52 / 30 ⇒ 合计 ≈112×40） | 行2（单按钮 90×40） | 行2（复合 112×40） | `editable && !locked`（三段同值） |
| 8 | 惩罚骰 `[−][惩罚N][↺]` | `penaltyMinus` / **`penalty`** / `penaltyReset` | 同上 ≈112×40 | 行2 | 行2 | `editable && !locked` |
| 9 | D100 | `GpDiceBarKeys.expr('1D100')` | `diceTile` 90×40 | 行2 | 行2 | `editable && !locked` |
| 10 | 其他骰子 | `GpDiceBarKeys.otherDice` | `diceTile` 90×40 | 行2 | 行3 | `editable && !locked` |
| 11 | 自定义骰式输入框 | `GpDiceBarKeys.customExpr` | `SizedBox(68)` 定宽 | 行3 | 行3 | `TextField.enabled = editable && !locked` |
| 12 | 掷自定义 | `GpDiceBarKeys.rollCustom` | `diceTile` 90×40 | 行3 | 行3 | `editable && !locked` |
| 13 | 暗骰开关 | `GpDiceBarKeys.dark` | `diceTile` 90×40 | 行4 | 行4 | `editable && !locked` |
| 14 | 战技 | `RoomKeys.action('combat.roll')` | `diceTile` 90×40 | 行4 | 行4 | `gate.can('combat.roll') && !locked`（结构门控 `if (gate.can(...))` 不变） |
| 15 | 对抗 | `RoomKeys.action('check.opposed')` | `diceTile` 90×40 | 行4 | 行4 | `gate.can('check.opposed') && !locked` |

行数：改前 **5 行**（412dp 实测：主组 4 → 骰子 3/3/3 → 尾随 2）；改后 **4 行 = 4 / 3 / 3 / 3**。

**切行算术没动的证明**：骰子条**条目数仍是 9**（奖惩合成 1 个条目），`diceMaxPerRow(400)=4`、`diceMaxPerRow(348)=3` ⇒ `diceBalancedRowSizes(9, 3|4)` 仍是 `[3,3,3]`；`kDiceTileW=90` / `kDiceTileGap=3` / `_balancedRows` / `RoomBtnSize.*` **一个字符都没改**（`p16_button_unify_test.dart:431-466` 的纯函数断言因此**仍绿**）。

### 1.4 宽度账（为什么复合控件是 ≈112 而不是 131）

| 段 | 内容宽 |
|---|---|
| `−`（`Icons.remove`） | 内边距 6+6 + 图标 18 = **30** |
| `奖励0`（label，无图标、无空格） | 6+6 + 3 字形 × 13.25 = **51.75** |
| `↺`（`Icons.restart_alt`） | 30 |
| 合计 | **≈111.75 × 40** |

- 412dp：内容宽 392，第 2 行 `112+112+90+2×3 = 320 ≤ 392` ✓
- 360dp：内容宽 340，`320 ≤ 340` ✓（若值段保留 `+` 图标 + 空格会是 `125×2+90+6 = 346 > 340` ⇒ 内部 Wrap 多折一行 ⇒ P16「360dp 仍 3 行」必红，所以才砍掉 `+` 图标。见 `gp_dice_bar.dart:516-526` 注释）
- 320dp（极端档）：`320 > 300`，第 2 行会折成 2 行（不 overflow、不裁切，只是变 5 行）—— 登记为已知档位限制。

### 1.5 textScaler 三档

- 复合控件三段的文字都在 `rollGroup.map(clampBtnText)` 覆盖范围内（`gp_dice_bar.dart:345`），`clampBtnText` = `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.0)` **只包该子树**。
- 主组两个缩放控件：`zoomPercent` 走 `clampBtnText(...)`（`gp_toolbar.dart:179-188`），`gpZoomReset` 走 `RoomTapTile`（内部已 `clampBtnText`）。
- 结论：三个控件都**结构上不可能**在 1.3 / 1.5 / 2.0 三档溢出（文字倍率被钳到 1.0；没有 `SizedBox` 紧约束包住新控件，宽度由内容决定 ⇒ 连「内容被撑破定宽」这条路都不存在）。

---

## 2. C-3 · 奖励骰 / 惩罚骰 加 / 减 / 归零

### 2.1 交互设计（选「显式两段」而不是「长按」的理由）

改成 **`[−] [奖励 N] [↺]`** 三段式（惩罚同构），一个条目内三个可点区：

| 段 | Key | 图标 | 点一下 |
|---|---|---|---|
| 左 | `GpDiceBarKeys.bonusMinus` | `Icons.remove` | `setBonus(bonus - 1)`（0 处仍是 0） |
| 中 | `GpDiceBarKeys.bonus`（**既有 key 不变**） | 无（只有 label `奖励N`） | `setBonus(bonus + 1)`（**与 P16 语义逐字一致**） |
| 右 | `GpDiceBarKeys.bonusReset` | `Icons.restart_alt` | `setBonus(0)` = 归零 |

**为什么不用「长按归零 / 单击减一」**（施工单允许二选一，这里选另一支，理由如下）：
1. 单击减一会把「加」弄没（用户诉求是「加减归零」三者都要），而 `RoomTap`（`room_panel_kit.dart:154-250`）**没有 `onLongPress`**，那个文件不在本批文件集，改它就是跨组改共用件。
2. 长按 / 双击都是**不可见手势**。用户当初的抱怨就是「只能加不能减」——再藏一个手势进去，可发现性和这次修 bug 的初衷相反；工具栏是密排高频区，`−` / `↺` 必须一眼看见。
3. 显式段还能让**锁定态三段同时禁用**，不会出现「能减不能加」的半残状态。

**可发现性补强**：三段各有 `hint`（Tooltip 原文）——
- `奖励骰 −1（最低 0）`
- `奖励骰 +1（与惩罚骰互斥，范围 0–5；左段 −1，右段归零）`
- `奖励骰归零`

### 2.2 上下限夹取现状（**没动，全在 `room_ui_local.dart:162-173`**）

```dart
void setBonus(int v) {
  final n = v < 0 ? 0 : (v > 5 ? 5 : v);   // 下限 0、上限 5
  bonus = n;
  if (n > 0) penalty = 0;                   // 互斥：>0 才清对面
  notifyListeners();
}
void setPenalty(int v) { /* 同构，n>0 时清 bonus */ }
```
- `−1` 在 0 处：`v = -1 → n = 0` ⇒ 不会变负，也不会误清对面（`n > 0` 不成立）。
- `↺`：`v = 0 → n = 0` ⇒ 只清自己这一侧，**不动对面**（这一条很关键：归零不是「两个都清」）。
- 上限 5 沿用原夹取；**本批没有新增任何状态字段**，也没有第二份 clamp（`_stepper` 回调直接 `local.setBonus/setPenalty`）。
- 互斥语义**未改变**：奖励 → 惩罚 仍是「惩罚一落地奖励归 0」，反之亦然。

### 2.3 落点（`gp_dice_bar.dart`）
- `:130-158`：新增 4 个 key 常量 + `_kZoneMin = Size(0, 40)`（单段最小尺寸：只给高度、宽度由内容决定 ⇒ 结构上不可能 overflow）。
- `:301-320`：`rollGroup` 里两个 `_stepper(...)`。
- `:526-570`：`_stepper` 实现（三段 `RoomTap` + `Row(mainAxisSize: min)`）。
- `:341`：`].map(clampBtnText).toList();` 覆盖复合控件（一个条目整体钳）。
- 旧的「只能 +1」两个 `RoomTap`（P16 版 `:234-251`）**已整体替换**。

---

## 3. P-3 · `locked` 参数接入（逐项清单）

### 3.1 契约（逐字实现）
```dart
GpToolbar({ ..., List<Widget> mainActions = const [], bool locked = false })
GpDiceBar({ ..., List<Widget> extensions = const [], bool locked = false })
```
两个都是**可选具名参数**、默认 `false` ⇒ `room_game_page.dart` 现在不传也照编译；W2-A 加 `locked: locked` 立刻生效。

### 3.2 叠了 `!locked` 的（黑名单，逐项）

| 组件 | 按钮 / 控件 | `enabled` |
|---|---|---|
| `gp_dice_bar.dart` | 奖励 `−` / 值(+1) / `↺`（3 段） | `editable && !locked` |
| | 惩罚 `−` / 值(+1) / `↺`（3 段） | `editable && !locked` |
| | D100 | `editable && !locked` |
| | 其他骰子（含弹层内 6 个骰式按钮） | `editable && !locked`（弹层内同样 `canRoll`） |
| | 自定义骰式**输入框** | `TextField.enabled = editable && !locked` |
| | 掷自定义 | `editable && !locked` |
| | 暗骰开关 | `editable && !locked` |
| | 战技 | `gate.can('combat.roll') && !locked` |
| | 对抗 | `gate.can('check.opposed') && !locked` |

### 3.3 **没叠** `!locked` 的（白名单，逐项）

| 组件 | 控件 | 理由 |
|---|---|---|
| `gp_toolbar.dart` | 缩放百分比 `zoomPercent` | §2-P-3 白名单第 4 条「纯视图操作」 |
| | 重置缩放 `gpZoomReset` | 同上（纯视图） |

> `gp_toolbar.dart` 里**已经没有别的按钮**了：`mainActions` / `extensions` 里的 widget 由注入方（`room_game_page.dart`）构造，其 `enabled` 由注入方按白名单判定 —— 所以 `GpToolbar.locked` 目前**没有可选叠的按钮**，参数存在是为跨组编译契约 + 语义占位。这一点已写进 `gp_toolbar.dart:92-103` 的注释，避免后人误以为漏了。

### 3.4 其它口径
- `RoomKeys.action(...)` 挂载**一处未改**（战技 / 对抗仍是同样的 key）。
- 结构门控 `if (gate.can('combat.roll'))` / `if (gate.can('check.opposed'))` **一字未改**：锁定时是「禁用」而不是「结构上消失」，否则锁定态和无权限态在 UI 上无法区分（`room_ui_permission_test.dart` 的 T-22 结构断言也因此不会被误伤）。
- 锁定态 hint 统一为：`操作受限：昏迷 / 疯狂 / 濒死期间只能「推进 1 轮」或点「更多工具」`。

---

## 4. 给波4 的验收用例口径（4 条）

1. **每行按钮数恰好 3（或 4）**
   - 412dp + `mainActions=[更多工具, 治疗]`：断言工具栏垂直方向恰好 4 个 `centerY` 层，且每层按钮数 = `[4,3,3,3]`（层内按 `Rect.center.dy` 分组，容差 1.0，沿用 `p10_t6` 的 `_rowCount` 写法）。
   - 骰子条单独断言：`diceKeys`（7 个单段 + 复合控件的 `bonus` 段）在 360dp / 412dp / 1280dp 三档都只占 3 行。
2. **奖惩骰 −1 / 归零后 `RoomUiLocal.bonus/penalty` 真变 0**
   - `tap(bonus) ×3` → `bonus == 3`；`tap(bonusMinus)` → `2`；`tap(bonusReset)` → `0`。
   - `tap(penaltyMinus)`（此时 penalty 0）→ 仍是 `0`（**不得变负**）。
   - `tap(bonus) ×2` 后 `tap(bonusReset)` → `bonus == 0` 且 `penalty` **保持不变**（归零不误伤对面）。
   - `tap(bonus) ×2` 后 `tap(penalty)` → `penalty == 1 && bonus == 0`（互斥不变）。
   - 反向证伪要求：把 `onSet(0)` 改成 `onSet(value)`（不归零）→ 必须红。
3. **锁定态下骰子全 disabled、缩放仍 enabled**
   - 构造昏迷 / 疯狂玩家（`operationLocked == true`）→ 传 `GpDiceBar(locked: true)`：
     断言 7 个单段 + 6 个复合段 + 输入框全部 disabled，且点任一个 **零发包**（`f.sent` 不含 dice）。
   - 同一页面传 `GpToolbar(locked: true)`：`zoomPercent` / `gpZoomReset` 仍 `enabled == true` 且点得动（`local.zoom` 变化）。
   - T-30 探针口径同步改成：`enabled == gate.can(op) && !locked`；白名单项（缩放两件、更多工具）**单独保留正向断言**「锁定态仍 enabled」。反向证伪：把 `&& !locked` 摘掉 → 锁定态断言必须红。
4. **textScaler 三档不溢出**
   - 1.3 / 1.5 / 2.0 × {360, 412, 1280} 逐格：`tester.takeException() == null`，且 `_expectUniform` 对「单段按钮」仍只出现 `{90×40}`、复合控件三段高度都 `40`。

---

## 5. 预计转红的既有测试 + 建议口径（交波4 统一改）

| 测试 | 行号 | 转红原因 | 建议口径（更强或等价） |
|---|---|---|---|
| `p16_button_unify_test.dart` | `:188-208`（`_p16ButtonGroups()`） | `'gpToolbar 主组'` 含 `round.next` / `scene.mode`；`'gpDiceBar'` 仍按 8 个单按钮列 | 主组改成 `[zoomPercent, gpZoomReset]`；骰子条分组改成「7 个单段 + 奖励复合的 3 段 + 惩罚复合的 3 段」，并对复合段断言「三段 `enabled` 同值」 |
| 同上 | `:333-360`（P16-01「主组 4 个 80×40」） | 两个 key 已无渲染点，`getSize` 找不到 | 改成「主组 2 个 80×40」；**新增**「`round.next` / `scene.mode` 在 kp/player/spectator 三视角都 findsNothing」（比原断言更强的删除守卫） |
| 同上 | `:370-430`（P16-02 骰子条 8 键一律 90×40 + 360dp 3 行） | 复合控件不再是 90×40 的单个 `RoomTap` | 尺寸集合断言改成「7 个单段 == {90×40}」+「复合控件：三段高 40、总宽 ∈ (100, 130)」；`_rowCount == 3` **保留不变**（条目数仍是 9） |
| 同上 | `:431-466`（`diceMaxPerRow` / `diceBalancedRowSizes` / `RoomBtnSize` 一致性） | **不红** | 本批未动这些纯函数与常量，**保持原样**（已核对：9 项、per∈{3,4} ⇒ 3/3/3） |
| `room_ui_permission_test.dart` | `:625-640`（`alwaysRendered=['round.next','scene.mode']`） | 两按钮已删 | 改成「三视角都 findsNothing」+ **新增**「KP 的 `round.next` 在 `sheet_kp_panel` 仍有入口、`combat.next` 在战斗信息栏仍有入口」正向断言（避免把「删重复入口」误测成「删功能」） |
| `room_ui_shell_test.dart` | `:411-440`（快捷按钮可点性 == POLICY，`ops=['round.next','scene.mode']`） | 两 op 已无 UI 锚点 | 探针对象换成仍在的 `act/combat.roll`、`act/check.opposed`（三角色比对 `gate.can && !locked`，`locked=false` 时等价原断言）；两个删除的 op 改成 findsNothing |
| `p10_t3_layout_test.dart` | `:291-302`、`:322-330` | key 列表含两个已删按钮 | 从列表删这两个 key（其余几何断言——在工具栏矩形内、不横向滚动、高度 > 56——**全部保留**）；建议把 `GpDiceBarKeys.bonusMinus` / `bonusReset` 加进列表补回覆盖度 |
| `p10_t6_layout_test.dart` | `:303-311`（7 键几何 + 行数 ≤4 + 无孤行 + 全部在骰子条内） | **不红**（7 个 key 都还在，复合控件变宽但仍在条内） | 保持原样；建议追加 `bonusMinus` / `bonusReset` / `penaltyMinus` / `penaltyReset` 四个 key 也「在骰子条矩形内」 |
| `room_ui_roll_test.dart` | `:231-293`（点 `bonus` ×3 → 3；惩罚互斥） | **不红**（中心段仍是 `RoomTap(key: bonus)` 且点 = +1） | 保持原样；建议**追加**「`bonusMinus` 减一 → 2」「`bonusReset` → 0」两条（C-3 的正向守卫，否则新增控件没有任何测试咬住） |
| `room_ui_blocks_test.dart` | `:120/145/244-251`（tap bonus、旁观者 `enabled == false`） | **不红**（`bonus`/`penalty` 仍是 `RoomTap`，`enabled` 仍受 `editable` 控制） | 保持原样；旁观者用例建议把 `bonusMinus/bonusReset` 也纳入 `enabled == false` 列表 |
| `p10_t7_c_combat_test.dart` | `:681-689`（`RoomKeys.action(op)` enabled == gate.can） | **不红**（未构造锁定态，`!locked` 恒 true） | 保持原样 |
| `qa_p5_priv_probe_test.dart` | `:373-433`、`T-06 旁观者零发包` `:530-556` | **不红**（旁观时 `canRoll=false`，新增段也 disabled；T-06 只点 enabled 的 `RoomTap`） | 保持原样 |
| `room_ui_entry_test.dart` / `p10_t5_music_synonym_layout_test.dart` | `p10_t5:387`（`quickRow` 是 `Wrap`）、`:399-412`（源码含 `'点按切换缩放档位`、`Wrap(`） | **不红**（两处都保留） | 保持原样 |

> **新增守卫自证咬得住（波4 执行）**：① 把 `bonusReset` 的 `onSet(0)` 改成 `onSet(value)` → 归零用例必须红；② 把 `&& !locked` 摘掉 → 锁定态用例必须红；③ 把 `mainActions` 的 `...` 删掉 → 「第 1 行 4 个」必须红。

---

## 6. 声明

- **未跑 `flutter test`**（并发期纪律），只跑 `dart analyze lib/ui/room/widgets/gp_toolbar.dart lib/ui/room/widgets/gp_dice_bar.dart`（→ `No issues found!`）。交付时 `dart analyze lib` 曾全绿；二次复核时全 lib 只剩 1 条**他人在飞文件**的告警（`gp_scene_check_pl.dart:17 unused_shown_name`，W3-A 收口），与本波两个文件无关。
- **未改任何既有测试**、未新建测试（波1/2/3 纪律）。
- **未碰别人文件集**：`room_game_page.dart` / `room_button_size.dart` / `room_ui_local.dart` / `room_keys.dart` / `room_panel_kit.dart` / `pubspec.*` / `app_version.dart` 一个字节都没动。
- 未动对抗入口（`gp_dice_bar.dart` 的 `check.opposed` 按钮本体在 P10 第 6 期已改成 `showOpposedSheet`，本批只叠 `!locked`，属 KP-3 范围的入口结构一字未改）。
- `lib/ui/room/**` 零 emoji（只匹配代理对 U+1F300–1FAFF，两个文件各 0 命中）；新代码零 `jsStr(`。
- 未跑 adb / 模拟器 / 真机。

## 7. 跨文件收口（已由 W2-A 完成）

> **最终状态（2026-11-14 二次复核）**：W2-A 已把「更多工具 / 治疗」搬到 `mainActions`；随后 team-lead 又追加了一条**与本波布局无关**的裁决（聊天锁定收窄：新增 `_chatLockedOf`，撕卡仍可聊天），工具栏 / 骰子条 / 治疗**仍用全量 `_lockedOf`（语义未变）**。
> 最新 `room_game_page.dart` = **1215 行**，sha256 `61f58635242eb33c3fc921b3de9b0764ad1403a50820763a5cec2469e70ff34f`；我这两个文件哈希未变（`4f242601…` / `3cd024b3…`）。
> 落位行号：`:1112` `mainActions:` / `:1115` 更多工具 / `:1135` 治疗（`:1141` `enabled: !locked`）/ `:1148` `extensions:` / `:1152` `GpDiceBar(locked:)` / `:1175` `...widget.toolbarExtensions`；聊天侧 `:871-874` `GpFeeds(locked: _chatLockedOf(...))`。
> 落位核对：玩家 412dp 第 1 行 = 缩放 `100%`(≈87) + 重置(80) + 更多工具(90) + 治疗(90) + 3×4 间距 = **359 ≤ 400** ⇒ 4 个；其后骰子条独占三行 3/3/3 ⇒ **全栏 4 行 = 4 / 3 / 3 / 3**（P-4 目标达成）。KP 侧 `mainActions` 恒空、`KP` / `BGM 场景` 仍在 `extensions` ⇒ KP dock 工具条与 P16 逐像素一致。
>
> ⚠️ 静态门禁：本次复核 `dart analyze lib` → **No issues found!**（全 lib 零告警，含他人文件）。过程中一度出现过 `gp_scene_check_pl.dart:17 unused_shown_name` 的告警，属 W3-A 的在飞快照，已由其自行收口（现该行是 `show asMap`，全文 `jsStr` 零命中），**当前无遗留告警**。


1. ~~必须用 `mainActions` 才能拿到 4 行 4/3/3/3~~ → **已落地**（W2-A `:1091`）。360dp 档 `359 > 348`，「治疗」掉第 2 行（3/1/3/3/3），是 `RoomBtnSize` 80/90 两个常量的物理极限 ⇒ 波4 口径：**412dp 断言 `[4,3,3,3]`；360dp 只断言「每行 3 或 4 个 / 无孤行 / 不溢出」**。
2. 「治疗」锁定态禁用、「更多工具」恒可点 —— W2-A 已写对（`:1114-1120` 治疗 `enabled: !locked`；更多工具不写 `enabled`）。二者都不是 POLICY action key，T-30 探针口径不受影响。
3. `GpToolbarKeys.extensions` 的 Wrap 仍在（玩家侧装骰子条），`room_ui_shell_test.dart:408` 照绿；全库没有「miscTools / treat 必须在 extensions 子树内」的断言 ⇒ 搬移零转红风险（W2-A 已独立核对）。


