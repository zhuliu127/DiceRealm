# P17 v2.30.0 · 波2-C 施工报告（P-3 申请按钮 + KP-8 音乐上移 + KP-3 入口核对）

- 施工人：寇豆码（p17-w2c）
- 工程根：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
- 独占文件集（只改这两个）：
  - `lib/ui/room/sheets/sheet_misc.dart`
  - `lib/ui/room/sheets/sheet_kp_panel.dart`
- `dart analyze` 结果：**两个文件 `No issues found!`**
- 未跑 `flutter test`；未改 `pubspec.yaml` / `pubspec.lock` / `app_version.dart`；未改任何既有测试、未新建测试。

改动后 SHA256：

```
aa01500d92449a8426314342237925d5ee698142119fdc7bf452f412ff15fec8  lib/ui/room/sheets/sheet_misc.dart      (381 行)
d3994958165bb9376e45e3a0262335e78098d84b3a69403832223a72d762c556  lib/ui/room/sheets/sheet_kp_panel.dart  (451 行)
```

---

## 1. P-3：玩家「更多工具」新增「申请」一节（两个申请按钮）

### 1.1 落点（`sheet_misc.dart`）

- 文件头注释 `:2-24`：补「本机工具 / 玩家申请」两句，写明音乐控制台**已上移一级**、申请节**刻意不加锁**的依据。
- import `:29` 新增 `import '../../../domain/room_types.dart' show RoomRole;`（判 role 用）。
- import `:34` 删除 `import 'sheet_music.dart' show openMusicSheet;`（该入口已移出本文件，留着会触发 `unused_import`）。
- role 判据 `:133-135`：

```dart
// P17 / P-3：申请按钮只在玩家侧渲染 —— KP 走「定向指令」弹层（同一批 op，
// 且能指定目标），两边共用本弹层时重复放一遍会变成两个入口。
final isPlayer = scope.session.role == RoomRole.player;
```

- 新增一节 `:309-363`（**追加在「本机工具」之后**，既有条目顺序未动）：

```dart
if (isPlayer) ...<Widget>[
  const Divider(height: 18),
  Text('申请（由 KP 确认后生效）',
      key: MiscSheetKeys.applySection,
      style: theme2.textTheme.titleSmall),
  ...
  if (scope.controller.gate.can('madness.cure'))
    RoomTap(
      key: MiscSheetKeys.applyMadnessCure,
      icon: Icons.healing,
      label: '申请治愈疯狂状态',
      hint: '提交申请给 KP：治愈「不定疯狂 / 潜在疯狂」（临时疯狂点「推进 1 轮」自消）',
      minSize: const Size(150, 40),
      onTap: () => scope.controller.hostAction(
        'madness.cure', <String, Object?>{'seat': seat},
      ),
    ),
  if (scope.controller.gate.can('sheet.healwound'))
    RoomTap(
      key: MiscSheetKeys.applyHealWound,
      icon: Icons.medical_services,
      label: '申请治愈重伤',
      hint: '提交申请给 KP：治愈自己的重伤 / 濒死 / 昏迷（只能治自己）',
      minSize: const Size(130, 40),
      onTap: () => scope.controller.hostAction(
        'sheet.healwound', <String, Object?>{'seat': seat},
      ),
    ),
],
```

### 1.2 稳定 key（`sheet_misc.dart:83-94`）

| key 常量 | 字面值 |
|---|---|
| `MiscSheetKeys.applySection` | `misc/applySection`（节标题） |
| `MiscSheetKeys.applyMadnessCure` | `misc/applyMadnessCure` |
| `MiscSheetKeys.applyHealWound` | `misc/applyHealWound` |

命名风格与既有 `itemsEmpty` / `zoomPct` / `historyExport` / `musicEntry` 一致（camelCase 属性名 + `misc/xxx` 值）。

**为什么不用 `RoomKeys.action(op)`**：`room_ui_permission_test.dart:321` 钉死「`act/<op>` 静态锚点表恰好 30 个 op」，新挂锚点会连带改锚点表口径；而本处两按钮的闸门由文件内 `gate.can` 承担，无需进 T-30 采集。已在 `:86-90` 写进注释。

### 1.3 载荷（与 KP 定向指令同口径）

对齐 `sheet_kp_directives.dart:157-160`：`case 'madness.cure': case 'sheet.healwound': return {'seat': seat};`
→ 本处发 `{'seat': scope.session.seat}`，**只有一个字段**，没臆造 `targetSeat` / `skill`。

链路（静态已核，未跑测试）：

1. `ctl.hostAction(op, {'seat': seat})`（`room_controller.dart:74`）→ `RoomIntent.act`；
2. `room_model_host_intent.dart:110-148` `intent()`：锁定态 `_passSelf` 白名单 `:106-108` **放行** `madness.cure` / `sheet.healwound`；
3. `:288-338` `act()`：`verdict.confirm == RoomConfirm.kp` 且发起者非 host → 入 `pending`（去重键 `by + op + jsonEncode(p)`），回系统提示「已向 KP 发起治愈申请，等待同意」；
4. KP 侧 `room_request_watcher.dart:160-179` 弹窗 →「同意」发 `INTENT.CONFIRM {op, by}` → 应用 `healWound` / `cureIndefinite`。

### 1.4 权限闸门现状（**未叠加锁定条件**）

| 视角 | `gate.can('madness.cure')` | `gate.can('sheet.healwound')` | 渲染结果 |
|---|---|---|---|
| player | true（POLICY `room_types.dart:269-272` `[player,kp] + RoomConfirm.kp`） | true（`:307-310` 同上） | 两个按钮都渲染，**昏迷/疯狂锁定态也照样可点** |
| kp | true | true | 整节不渲染（`isPlayer == false`）—— KP 用「定向指令」弹层（同批 op，且能指定目标） |
| spectator | false | false | 整节不渲染（role 不是 player） |

- **显式不加 `operationLocked`**：用户口径「锁定态只放行『推进 1 轮』+『更多工具』」，申请就长在「更多工具」里；在这里再叠一层锁会把锁定态唯一的自救出口锁死。权威端 `_passSelf`（`room_model_host_intent.dart:95-111`）本就放行这两个 op，口径自洽。注释在 `:312-317`。
- 文案如实：`madness.cure` 只治「不定/潜在疯狂」（临时疯狂点「推进 1 轮」自消），`sheet.healwound` 只能治自己且要求重伤/濒死/昏迷 —— 未承诺「治愈所有疯狂 / 治别人」。

---

## 2. KP-8：音乐控制台按钮上移一级（两处改动）

### 2.1 改动一：`sheet_misc.dart` 删入口（保留 key 常量）

- 删除原 `:259-266`（旧文件行号）的 `RoomTap(key: MiscSheetKeys.musicEntry, ... onTap: () => openMusicSheet(ctx))`；「本机工具」节还在，只剩「导出游戏历史」。`sheet_misc.dart:277-308`：

```dart
// ---- 本机工具（P2-06 游戏历史导出） ----
// ★ P17 / KP-8：音乐控制台入口已上移一级到「KP 工具」弹层
//   （`sheet_kp_panel.dart` 的 KpPanel），本节只剩游戏历史导出。
//   标题 key `MiscSheetKeys.musicSection` 刻意沿用（既有测试按名引用）。
Text('本机工具', key: MiscSheetKeys.musicSection, ...),
Wrap(... if (gate.can(kRoomHistoryExportPolicyOp)) RoomTap(key: historyExport ...) ...),
```

- key 常量 `musicEntry`（`:61-67`）与 `musicSection`（`:69-70`）**都保留**，并注明「入口已换宿主、常量刻意保留」。
- **新口径**：`更多工具`（MiscSheet）**不含** `MiscSheetKeys.musicEntry`；标题「本机工具」仍在（`musicSection` 仍能取到）。

### 2.2 改动二：`sheet_kp_panel.dart` 加按钮

- import `:43`：`import 'sheet_music.dart' show openMusicSheet;`（复用原入口，没有另写一套）。
- key `KpPanelKeys.music`（`:131-135`）= `kpPanel/music`；与 `MiscSheetKeys.musicEntry` 刻意分成两个 key，便于「一处不含 / 一处含」双向断言。
- 按钮 `:379-388`，插在「工具 · 房间管理」组的「更多工具」之后、「保存本局」之前（既有条目相对顺序未变，危险操作仍在最后）：

```dart
// ★ P17 / KP-8：音乐控制台上移一级 —— 真入口直接开本机播放控制台
//   （与「更多工具」里的旧入口是同一个 `openMusicSheet`，不另写一套）。
//   纯本机、不联网、不进存档，所以不动闸门。
RoomTap(
  key: KpPanelKeys.music,
  label: '音乐控制台',
  icon: Icons.music_note_outlined,
  hint: '本机 BGM：选本机音频、5 个场景插槽、播放 / 暂停 / 停止（不联网、不打包音频）',
  onTap: () => openMusicSheet(context),
),
```

- 可达性：KpPanel 唯一生产入口 `room_game_page.dart:1019-1028`（`if (isKp)`，「KP」按钮）→ 因此音乐入口天然只对 KP 可达，与原来「KP → 更多工具 → 音乐」的权限面等价，甚至少一层。
- 不动 `kKpSheetIds` / `openKpSheet`：音乐是**本机弹层**、不是 KP 分组弹层，直接 `openMusicSheet` 更贴合「上移一级」字面，也避免给 `openKpSheet` 加一个非分组 case。

### 2.3 「按钮排布不溢出」推演（含 textScaler 1.3 / 1.5 / 2.0）

口径：`RoomTap` 宽度 = `max(minSize.width, 内容宽)`，内容宽 = 左右 padding 12 + icon 18 + 间隙 4 + `Text(fontSize 13 × 缩放 × 字数)`（CJK 字宽按 fontSize 取上界）。

**最窄屏可用宽**：320dp 屏 → 弹层宽 320 − RoomSheet padding 24 − Card margin 8（`panelGap/2 ×2`）− SectionBox padding 20 = **268dp**。

KP 面板「房间管理」组（新增后 6 件：存档槽 / 更多工具 / 音乐控制台 / 保存本局 / 结束房间 / 结团）：

| 倍率 | 单件最宽（「音乐控制台」5 字） | 6 件合计（含 5×4 间距） | 268dp 下排布 | 是否溢出 |
|---|---|---|---|---|
| 1.0 | 12+18+4+65 = 99 | ≈ 510 | 2 行（3+3） | 否（单件 99 ≤ 268） |
| 1.3 | 12+18+4+84.5 = 118.5 | ≈ 616 | 3 行 | 否 |
| 1.5 | 12+18+4+97.5 = 131.5 | ≈ 653 | 3 行 | 否 |
| 2.0 | 12+18+4+130 = 164 | ≈ 776 | 4 行 | 否 |

- 关键：**单件宽度始终 < 268dp**，`Wrap` 只增加「行数」（纵向变高），不会出现 `RenderFlex overflow`；弹层 body 是 `SingleChildScrollView` + `maxHeight = 屏高 × 0.72`（`room_sheet.dart:62-73`），变高即滚动。
- KP 实际使用面是**平板横屏**（§0.3），弹层宽 ≥ 800dp（可用 ≥ 748dp）：1.0–1.5 全部一行；2.0 时 6 件 776 > 748 → 2 行，仍无溢出。
- 加音乐按钮**没有改变 320dp / 1.0 倍率下的行数**（加之前 5 件 407 → 2 行 3+2；加之后 510 → 2 行 3+3）。
- 申请节（MiscSheet）：`「申请治愈疯狂状态」8 字` 内容宽 1.0/1.3/1.5/2.0 → 138 / 169 / 190 / 242（实际宽取 `max(minSize 150, 内容)`，仍 ≤ 268）；`「申请治愈重伤」6 字` → 112 / 135 / 151 / 190（取 `max(minSize 130, …)`）。单件均不超宽。
- **不需要 `MediaQuery.withClampedTextScaling`**：本批新增控件**没有固定宽高**（只用 `minSize` 下限 + `Wrap` 流式 + 可滚动父级），不满足「固定尺寸控件」的钳制前提；硬钳反而会让面板正文不跟随系统字号（`p16_button_unify_test.dart` 的 `_expectPanelTextNotClamped` 反向守卫正是这个意思）。

---

## 3. KP-3：对抗入口核对（**只核对，未改一行**）

两条入口最终落到**同一个**弹层函数：

| 入口 | 行号 | 动作 |
|---|---|---|
| KP 工具面板「对抗」 | `sheet_kp_panel.dart:327-332`：`_action(op: 'check.opposed', onTap: () => opener(context, 'opposed'))` | → `openKpSheet` `case 'opposed'`（`:161-163`）→ `showOpposedSheet<void>(context)` |
| 骰子条「对抗」 | `gp_dice_bar.dart:356-362`：`showOpposedSheet<void>(context)` | → `showOpposedSheet`（`sheet_opposed.dart:249-255`，标题「对抗」，body `OpposedSheet`） |

结论：**入口一致**，无需改任何一行。

- 弹层内部按 role 分支（`sheet_opposed.dart:106` `role: session.role` → `kpOpposedCanApply` `:52-60`），KP/玩家共用同一个 `OpposedSheet`，不存在「KP 指向另一个对抗弹层」。
- 闸门一致：两处都是 `gate.can('check.opposed')`，且都挂 `RoomKeys.action('check.opposed')` 锚点 → T-30 采样到多处同名 op，`enabled` 均等于 `gate.can`（`sheet_opposed.dart:120-133` 的「通用对抗」也是同一 op 同一闸门）。
- 唯一差异是**渲染惯例**：骰子条 `if (gate.can(...))` 结构上不渲染；KP 面板 `_action` 恒渲染 + 置灰。这是 P16 之前就存在的两套惯例，不是本次要统一的入口分歧。
- **谁该改哪一行**（KP-3 剩余部分，归 W3-B）：
  - 删「武器对抗」独立入口：`sheet_opposed.dart:144-153`（`OpposedSheetKeys.weapon`）。
  - 补 `aSkill` / `bSkill` 输入并改 `check.opposed` 载荷：`sheet_opposed.dart:121-133`（通用对抗 `kind:'general'` 那段）。
  - 裁定 / 选目标载荷对齐：`sheet_opposed.dart:182-196`、`:225-239`。
  - **`sheet_kp_panel.dart` 的对抗入口（`:327-332`）不用改**；W3-B 只要保证 `showOpposedSheet` 仍是「对抗」弹层、标题不变，KP 入口就继续正确。
  - 我**没有**改 `sheet_opposed.dart`、**没有**改 `gp_dice_bar.dart`、**没有**改任何对抗逻辑。

---

## 4. 红线自检（两文件）

| 检查 | sheet_misc.dart | sheet_kp_panel.dart |
|---|---|---|
| 代理对 emoji（U+1F300–1FAFF） | 0 | 0 |
| 新写 `jsStr(` | 0 处 | 0 处 |
| `state[...] =` 权威快照赋值 | 0 | 0 |
| `enabled: false` 假按钮 | 0 | 0 |
| `revealed`（P16 波1 gate 禁词） | 0 | 0 |

既有 key 常量全部保留（含 `musicEntry` / `aiEntry` / `aiHint`）；两块弹层的既有条目顺序未重排（只在末尾「新增一节」、在「更多工具」后「加一个」、删掉那个已上移的入口）。

---

## 5. 预计转红的既有测试 + 建议口径

> 按 §4 纪律，以下只登记，不在本波改测试，交波4 统一处理。

### 5.1 必红

1. `test/room_ui_entry_test.dart:751-761`
   - 现断言：在 `MiscSheet` 宿主里 `tester.widget<RoomTap>(find.byKey(MiscSheetKeys.musicEntry))`（隐含 `findsOneWidget`）+ `enabled` + `onTap != null` + `hint` 含「本机」。
   - 现结果：`musicEntry` 已不在本弹层 → `findsNothing` → 该行抛 `StateError`。
   - **建议新口径（更强，条数不减）**：
     ```dart
     // ① 更多工具不含音乐入口
     expect(find.byKey(MiscSheetKeys.musicEntry), findsNothing,
         reason: 'P17/KP-8：音乐入口已上移一级到 KP 工具');
     // ② KP 工具含音乐入口，且仍是真入口
     final music = tester.widget<RoomTap>(find.byKey(KpPanelKeys.music));
     expect(music.enabled, isTrue);
     expect(music.onTap, isNotNull, reason: '可点但没回调 = 假入口');
     expect(music.hint, contains('本机'));
     expect(music.hint, isNot(contains('下一期')));
     ```
     （需把该用例宿主从 `openMiscSheet` 改成 `showKpPanel`，或另起一条 KP 面板用例。）
   - `:760` 的 `MiscSheetKeys.musicSection` 断言**仍绿**（「本机工具」标题保留），可不改。

2. `test/sheet_music_test.dart:98-112`、`:121`、`:260`（3 处）
   - 现断言：`_scopedApp(f, const MiscSheet())` 后取/点 `MiscSheetKeys.musicEntry`。
   - **建议**：宿主换成 `const KpPanel()`（`_scopedApp` 已挂 `RoomScope`，KpPanel 只需 `RoomScope.of`），key 换 `KpPanelKeys.music`；其余断言（`enabled` / `onTap` / hint 含「本机」/ 无「下一期」/ 点开后 `MusicSheetKeys.*` 全在 / 切场景停旧）**逐字保留**。

3. `test/sheet_music_test.dart:365`
   - 现断言：`File('lib/ui/room/sheets/sheet_misc.dart')` 源码 `contains('openMusicSheet') isTrue`。
   - 现结果：本文件已删除该 import 与调用 → false。
   - **建议**（等价转位、并加反向守卫）：
     ```dart
     expect(misc.contains('openMusicSheet'), isFalse,
         reason: 'P17/KP-8：音乐入口已从「更多工具」移出');
     final kpPanel = File('lib/ui/room/sheets/sheet_kp_panel.dart').readAsStringSync();
     expect(kpPanel.contains('openMusicSheet'), isTrue,
         reason: 'P2-03 要接成真入口：入口上移一级到 KP 工具，不是删掉');
     ```

### 5.2 已核：**预计不红**（附理由，波4 可据此快速定位）

| 测试 | 结论 |
|---|---|
| `test/p16_button_unify_test.dart` | `_p16ButtonGroups()`（`:187-245`）只列 gpToolbar / gpDiceBar / gpKpTools / gpKpLeft / gpScene / gpPlScene / gpPlCharCard / gpFeeds / gpPrivates，**不含 MiscSheet / KpPanel** → 新增 3 个 `RoomTap` 不进该清单，不红。若波4 要把新按钮纳入统一档，需同时加 `KpPanelKeys.music` / `MiscSheetKeys.applyMadnessCure` / `applyHealWound`。 |
| `test/room_ui_permission_test.dart` T-30 静态锚点表（`:307-345`） | 我**没有**挂 `RoomKeys.action` 新锚点 → `table.length == 30` 不变；也不会有「未在 kRoomPolicy 登记的未知 op」。⚠️ 反向提醒：将来谁要给音乐入口加闸门，**不要**用 `RoomKeys.action('xxx')` —— 它不是 POLICY op，会打红 `:323-328` 的 unknown 断言。 |
| `test/room_ui_permission_test.dart:361-366`（`KpPanel × 三视角`） | `expectGateEquivalence` 只采集 `act/<op>` 前缀的 key；`KpPanelKeys.music` = `kpPanel/music`，不参与采集。既有 9 个 `act/` 锚点 `enabled` 仍严格 `= gate.can(op)`，未动。 |
| `test/room_ui_kp_test.dart:1140+`（11 文件零命中门禁） | 禁词 `RoomHost` / `rules?.check(` / `rollExpr(` / `opposedFull(`：两文件 0 命中（已 grep 自检）。 |
| `test/p16_wave1_sheets_test.dart:631-658`（源码红线） | `revealed` / emoji / `jsStr(` / `state[...] =`：`sheet_misc.dart` 0 命中。 |
| `test/room_ui_lobby_test.dart:435-465` | 按 `KpPanelKeys.misc` / `saveSlots` 点开，按钮插入不影响按 key 定位。 |
| `test/room_history_export_test.dart`、`test/room_ui_gap_fill_test.dart` | 「申请」节**追加在**「本机工具」之后，`historyExport` / `itemDel` 的位置与顺序未变（仍可 `ensureVisible`）。 |
| `test/p10_t5_music_synonym_layout_test.dart:390-396` | 静态扫的是 `zoomRow` / `spacing: 3,` / `Size(54, 34)` / 缩放文案 —— 全部原样保留（`:246-258`）。 |

### 5.3 建议新增的正向守卫（波4 可选，自证咬得住）

- `MiscSheet` 玩家侧：`applyMadnessCure` / `applyHealWound` `findsOneWidget`，`onTap != null`，点一次后 `f.lastSent(op: 'madness.cure')` 的载荷 **恰好** `{'seat': 'p1'}`（无 `targetSeat`）。
- `MiscSheet` KP 侧：`applySection` / 两个按钮 `findsNothing`（KP 走定向指令）。
- **锁定态（昏迷/疯狂）**：玩家 `operationLocked == true` 时，两申请按钮仍 `enabled`（与「工具栏全禁」形成对照，正是 P-3 的用户口径）。
- `KpPanel`：`KpPanelKeys.music` `findsOneWidget` + hint 含「本机」。

---

## 6. 声明

1. 未跑 `flutter test`（并发期纪律）；只跑 `dart analyze lib/ui/room/sheets/sheet_misc.dart lib/ui/room/sheets/sheet_kp_panel.dart` → **No issues found!**
2. 未修改任何既有测试、未新建测试文件。
3. 未碰别人的文件集：`room_game_page.dart` / `gp_toolbar.dart` / `gp_dice_bar.dart` / `sheet_treat.dart` / `sheet_opposed.dart` / `room_types.dart` / `sheet_kp_directives.dart` 全部**只读未改**。
4. 未改 `pubspec.yaml` / `pubspec.lock` / `lib/app_version.dart`；未 `flutter clean`；未碰 `build`。
5. 真机待测项（供 QA 登记）：① 昏迷/疯狂锁定态下「更多工具 → 申请治愈重伤 / 申请治愈疯狂状态」仍可点且 KP 能收到弹窗；② KP 工具里「音乐控制台」直接开本机播放控制台，且「更多工具」里不再有音乐入口；③ 平板横屏 + 系统大字号（1.3/1.5/2.0）下 KP 工具「房间管理」组排布不溢出、可滚动。
