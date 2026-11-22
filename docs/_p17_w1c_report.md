# P17 波1-C 交付报告（玩家角色卡：P-1 幸运 / C-1 删两按钮 / P-3 保存按钮加锁）

- 施工人：寇豆码（p17-w1c）
- 独占文件：`lib/ui/room/widgets/gp_pl_char_card.dart`（**本批只改这一个文件**）
- 改动后：**453 行**
- 改动后 sha256：`628994da4ecc0ceae0b62646dec57bdb07d2aad6170fb9230f264f61dfb2a328`
  - ⚠️ 以上为最终值；若后续有人再动本文件请重新登记（见文末「哈希登记」一节的实际命令）
- 静态自检：`dart analyze lib/ui/room/widgets/gp_pl_char_card.dart` → **No issues found!**
- 门禁自检：本文件 emoji（U+1F300–1FAFF 代理对）命中 **0**；`jsStr(` 命中 **0**

---

## 1. 逐项落点（行号以改动后文件为准）

### 1.1 P-1 加 LUK（幸运）

**(a) 取值与文案（新增，`:109-121`）**

```dart
    final attrs = attrRows(me);
    // ★ P17 P-1：属性区补 LUK（当前幸运点）。
    //   `vitals.luck`（= `status.currentLuck`，见 `sheet_view.dart:69`）一直取到
    //   却没在任何地方画出来：属性区只跑 `attrRows`，而它按 `_attrLabels`
    //   （8 项，不含 luck）截断，`kRaAttrKeys` 里的 `luck` 永远到不了界面。
    //   ★ **不改共享纯函数 `attrRows`**：它还被 `sheet_char_view.dart:153`（全屏
    //     只读详情）与 `room_view_test.dart` 的 8 项断言复用，改它会连带改口径。
    //     只在本卡片补一项。
    //   ★ 缺键显示「—」而不是 0：与八项属性同一 K4 口径（缺键 ≠ 0）。必须读
    //     **原始** status —— `roomNumber(null)` 也返回 0，从 `vitals.luck` 上
    //     区分不出「真的 0」与「没这个键」。
    final Object? luckRaw = asMap(asMap(me['sheet'])['status'])['currentLuck'];
    final String luckText =
        (luckRaw == null || luckRaw == '') ? '—' : _fmtNum(vitals.luck);
```

**(b) 渲染（`:211-224`，原 `:194-201` 的 8 项 Wrap 变 9 项）**

```dart
          const SizedBox(height: 6),
          // ★ P17 P-1：从 8 项变 9 项（末尾追加 LUK）。这是**柔性 Wrap**，
          //   多一项只会多一行，不会溢出；卡片所在的两种宿主都是可滚动的
          //   （折叠档整页 `SingleChildScrollView`、平板横屏 `_slotView` 格内
          //   竖向滚动），所以 textScaler 1.3/1.5/2.0 下高度增长只增加滚动量。
          Wrap(
            spacing: 8,
            runSpacing: 2,
            children: <Widget>[
              for (final row in attrs)
                Text('${row.k} ${row.v}', style: const TextStyle(fontSize: 11)),
              // 第 9 项：幸运（当前幸运点）。取值口径见 build 顶部的注释。
              Text('LUK $luckText', style: const TextStyle(fontSize: 11)),
            ],
          ),
```

**(c) 数值格式化（新增私有函数，`:447-452`）**

```dart
/// 数值 → 最短文本：整数不带 `.0`，其余保留一位小数。
///
/// ★ 为什么不用 `num.toString()`：`status.currentLuck` 常是 `'60'` 这类字符串，
///   `roomNumber` 归一后是 `double 60.0`，直接插值会显示成 `LUK 60.0`。
/// ★ 与 `sheet_view.dart` 的私有 `_fmt` 同口径（那边不导出，复制 2 行比
///   改共享文件的可见性更安全）。
String _fmtNum(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
```

> **口径选择说明**：属性区的 8 项走 `attrRows`（`sheet.attrs`，幸运**属性值**）；
> LUK 这一项显示的是**当前幸运点**（`status.currentLuck` → `Vitals.luck`），
> 与全屏只读详情 `sheet_char_view.dart:141`「幸运 ${v.luck}」完全同源。
> 这样「属性 luck」与「可花费的当前幸运」不会在同一张卡上出现两个数字打架。

### 1.2 C-1 删两个按钮

| 删的是 | 改前行号（v2.29.0+99） | 改后 |
|---|---|---|
| 「急救」`RoomTapTile`（挂 `RoomKeys.action('aid.apply')`） | `:244-268`（含 `if (gate.can('aid.apply'))`） | 整块删除，`:273-275` 留中文说明 |
| 「AI RP」`RoomTapTile`（挂 `GpPlCharCardKeys.aiBtn`） | `:277-297` | 整块删除，`:289-293` 留中文说明 |

剩余两个短按钮（`stateBtn` / `itemsBtn`）位置不变：`:260-286`。

**key 常量保留（测试编译不受影响）**：

- `GpPlCharCardKeys.aiBtn`：`:45-49`，改为带说明的声明
  ```dart
  /// ★ P17 C-1：角色卡的「AI RP」指引按钮已删（真入口在聊天输入行的魔棒）。
  ///   key 常量**保留**：多处既有测试按字符串 / 按 key 引用它，删常量会让
  ///   测试编译期就断裂；语义上这一项 P17 起已无 UI 使用点。
  static const Key aiBtn = ValueKey<String>('gpPlCharCard/aiBtn');
  ```
- `RoomKeys.action('aid.apply')` 是 `room_keys.dart` 的工厂方法，天然不需要动；
  本文件里**已零命中**（注释里也刻意不写字面量，见 1.2 的说明）。

**关于「删后留大空白」的实测结论（静态推算，见 §2.2）**：不会留空白。剩余 2 个
tile 恰好 = `2×104 + 4 = 212`，正是 `roomTapFixedGrid2` 钳制的宽度，正好填满一行。

### 1.3 P-3 `保存到已保存` 加锁（**只改这一个按钮**）

`:305-353`（原 `:317-344`；`enabled` 在 `:337`）：

```dart
              child: RoomTapTile(
                roomKey: GpPlCharCardKeys.saveBtn,
                size: RoomBtnSize.fullRow40,
                fullWidth: true,
                icon: Icons.save_outlined,
                label: '保存到已保存',
                // ★ P17 P-3：`gate.can(op) && !locked`（前者是本按钮的结构性
                //   前置，后者是本次新增的操作锁）。锁定态按钮变灰、点了不发。
                enabled: scope.controller.gate.can('state.self') && !locked,
                hint: locked
                    ? '昏迷 / 疯狂发作期间不可保存（只能「推进 1 轮」或申请治愈）'
                    : '把当前 HP/MP/SAN、物品、状态写回本机这张角色卡（覆盖同一张）',
```

**改前 `enabled` 的语义**（先读清再改）：`enabled: gate.can('state.self')`，
而承载它的 `Padding` 外层就是 `if (gate.can('state.self'))`，即 **enabled 与外层
条件同源 → 恒为 true**（渲染即恒可点）。所以本次不是「把某个有效判定改坏」，
而是给一条**恒真**补上真正的业务判据 `!locked`，语义严格变强。

`locked` 来自 `:123` `final locked = operationLocked(me);`（`member_view.dart:167-175`，
与权威端 `_passSelf` 同源）。`RoomTap` 对 `enabled == false` 会把 `onTap` 置 null
（`room_panel_kit.dart:230-234`），所以是**真禁用**，不是只变灰。

**为什么没有把保存按钮挪进 `if (!locked)`**：
用户口径是「昏迷 / 疯狂时其余全禁」，不是「撕卡式隐藏」；而且这张卡在锁定态必须
继续显示终局数值。所以保持「渲染 + 禁用」，与 4 个短按钮的「不渲染」（T-20）是
两条不同的合法分支，互不冲突。

---

## 2. 布局复查

### 2.1 短按钮区（`roomTapFixedGrid2`，固定 2 列）

- 结构：`Align(centerLeft) → SizedBox(width: 2×104+4 = 212) → Wrap(spacing 4, runSpacing 2)`
  （`room_button_size.dart:284-300`）。
- 改后本栏**恒为 2 个** tile（`state.self` 玩家恒有；旁观者更早一步就在
  `:90-104` 的「未绑定 / 未同步」分支 return 了，根本走不到这一栏）：
  `2×104 + 4 = 212` = 钳制宽 → **恰好一行、右侧零空白**。
- 窄档（< 212 可用宽）由 `Wrap` 自动掉成 1 列，不裁切、不 overflow（既有设计）。
- 极端档（`state.self` 拿不到，只剩 `物品` 1 个）会留 ≈108dp 空白。当前不可达；
  已在 `:255-258` 写明「届时传 `columns: 1`，**不要加按钮填空**」。

### 2.2 LUK 加入后的列数与换行（含 textScaler 1.3 / 1.5 / 2.0）

⚠️ 本批**禁止跑 `flutter test`**，以下为**静态推算**（不是实测）：
字号 11 的字符宽按 P16 已实测口径换算 —— `room_button_size.dart:99` 注明测试字体
每字 13.25dp @ fontSize 13，即 ≈ `fontSize × 1.019`；故字号 11 每字符 ≈ 11.21dp。
一项 `STR 60` = 6 字符 ≈ 67.3dp，项间 `spacing: 8` ⇒ 每项占位 ≈ 75.3dp。
行高约 `11×scale×1.2 + runSpacing 2`。

| 档位 | 可用内容宽 | 每行项数（8 项 → 9 项） | 行数变化 |
|---|---|---|---|
| 1280×800 平板横屏（dock 格） | 223.2 | 3 → 3 | **3 行不变** |
| 320×640 | ≈276 | 3 → 3 | **3 行不变**（9 项正好 3+3+3，更整齐） |
| 360×640 | ≈316 | 4 → 4 | 2 行 → 3 行（4+4+**1**），+1 行 |
| 412×915 | ≈368 | 4 → 4 | 2 行 → 3 行（4+4+**1**），+1 行 |

textScaler 三档（按 360×640 与 dock 格两种最紧的宿主）：

| textScaler | 360×640（316） | dock 格（223.2） | 结论 |
|---|---|---|---|
| 1.0 | 4 项/行，2 行 → 3 行 | 3 项/行，3 行 → 3 行 | +1 行（≈16dp） |
| 1.3 | 3 项/行，3 行 → 3 行 | 2 项/行，4 行 → 5 行 | 最多 +1 行（≈19dp） |
| 1.5 | 2 项/行，4 行 → 5 行 | 2 项/行，4 行 → 5 行 | +1 行（≈22dp） |
| 2.0 | 2 项/行，4 行 → 5 行 | 1 项/行，8 行 → 9 行 | +1 行（≈28dp） |

**不会 `RenderFlex overflow` 的结构性理由（这是硬结论，不依赖上面的估算数字）**：

1. 属性区是 **`Wrap`**（柔性、主轴可换行），不是 `Row`/固定高容器 —— 宽度不够只会
   多一行，永远不溢出。
2. 两种宿主都是**可滚动**的：
   - 折叠档（手机竖/横、平板竖）：`room_game_page.dart:570`
     `SingleChildScrollView(child: body)` 包整页；
   - 平板横屏 dock：`_slotView`（`room_game_page.dart:750-806`）对 `gpPlCharCard`
     这类槽位给的是 `SingleChildScrollView`（**格内竖向滚动**）；只有
     `gpMap/gpPlMap/gpKpLeft` 走紧约束 `ClipRect` 分支，本卡不在其中。
3. 因此 LUK 造成的 +1 行只增加滚动量，不会顶破格子。

**没有给属性区加 `clampBtnText` 的理由**：它是正文信息（不是固定尺寸控件），
按字形可读性应该跟随系统字号；`clampBtnText` 的适用前提是「`SizedBox(W,H)` 紧约束 +
定宽文案」——本 Wrap 不满足，硬钳会违反规格 §0.7「只钳固定尺寸控件子树」。

---

## 3. C-1：用户口径核实结论（**用户说法不属实**，务必写进最终交付说明）

用户原话：「角色卡上的『AI RP』和『急救』，聊天栏和玩家工具栏有相同的按钮（删掉角色卡这两处）」。
逐条核实后 —— **「聊天栏和玩家工具栏有相同的按钮」不成立**：

| 用户以为 | 实际情况 | 证据 |
|---|---|---|
| 聊天栏也有 AI RP 按钮（所以角色卡的是重复） | **成立**：聊天输入行有 AI RP **真入口**（魔棒 `Icons.auto_awesome` → `openAiRpSheet`，结果只回填输入框） | `gp_feeds.dart:50`（`GpFeedsKeys.aiRp`）、`:785-800`；`room_ui_entry_test.dart:776-780` 源码锚点 |
| 玩家工具栏也有 AI RP 按钮 | **不成立**：工具栏 `extensions` 只有 `GpDiceBar` + 「更多工具」+「治疗」；「更多工具」弹层里的 AI RP 条目 P16 已删（`MiscSheetKeys.aiEntry/aiHint` 常量保留但不再渲染） | `room_game_page.dart:1016-1068`；`sheet_misc.dart`；`room_ui_entry_test.dart:768-773` |
| 玩家工具栏也有「急救」按钮 | **不成立**：工具栏只有「治疗」`treatKey` 打开 `openTreatSheet` 聚合弹层，弹层里才有 急救 / 医学 / 精神分析 三分支；`aid.apply` 的 act 锚点**只**钉在角色卡急救按钮上，工具栏刻意不挂 | `room_game_page.dart:248`（注释明说「不挂 `RoomKeys.action('aid.apply')`」）、`:1054-1066`；`sheet_treat.dart:65-69` |

**结论**：用户把「角色卡内的 AI RP 指引 / 急救」与「聊天栏的 AI RP 真入口 / 工具栏的
治疗弹层」混成了「同一批重复按钮」。**删除仍然安全且符合用户本意**（角色卡上那份
AI RP 只是「去哪儿找」的指引，属于冗余；急救走「治疗」弹层能力更全）：

- AI RP → 聊天输入行魔棒（唯一真入口，未受影响）
- 急救 → 工具栏「治疗」弹层（`sheet_treat.dart` 三分支，未受影响，
  `p16_wave1_sheets_test.dart:610-617` 覆盖）

**但对外口径必须写成「删除角色卡上的 AI RP 指引与急救两个入口」，不能写成
「删除重复按钮」**，否则与代码事实不符。

---

## 4. P-3 的边界说明 + 交给波2 的「其余漏网入口清单」

> ⚠️ **行号版本说明**：本节 §4.2 表里的 `gp_toolbar.dart` / `gp_dice_bar.dart` /
> `room_game_page.dart` 行号取自 **v2.29.0+99 基线**（施工单与研究报同一版）。波2-A/2-B
> 落地后该文件已位移（`room_game_page.dart` 现 1215 行，「治疗」的 `enabled: !locked`
> 现在在 `:1141` 而不是基线里的 `:1121`）。**改代码前请 `grep -n` 重新定位**，别按死行号。

### 4.1 我只改了「一个按钮」

- 本批**只**给 `GpPlCharCardKeys.saveBtn` 的 `enabled` 叠加 `!locked`（`:337`）。
- **没有**碰 `gp_toolbar.dart` / `gp_dice_bar.dart` / `room_game_page.dart` 的
  `_buildToolbar`（那是波2-B / 波2-A 的文件集）。
- 角色卡内其余入口现状（本批未改，均**已符合**用户口径）：
  - `stateBtn` / `itemsBtn`：在 `if (!locked)` 内 → 锁定态**不渲染**（T-20）；
  - `madness.advance`（推进 1 轮）：白名单，锁定态**仍渲染且可点**（`:352-370`）；
  - `fullscreen`（全屏只读查看）：不产生动作，建议**保持放行**（只读，不改房间态）；
  - 技能行 / 属性 / StatBar：纯展示，不可点。

### 4.2 交给波2 的「其余漏网入口清单」（我读源码核对过的，按文件分）

| # | 位置 | 现状 | 应做 |
|---|---|---|---|
| 1 | `gp_toolbar.dart:129-174`（整组：缩放百分比 / 复位 / `round.next` / `scene.mode` / BGM 场景 / KP 面板 / 更多工具） | `enabled` 只依 `gate.can(op)` 或与缩放无关，**零 `operationLocked` 判定** | 统一闸门（推荐在 `_buildToolbar` 一处派生 `bool actionsEnabled = !selfLocked(...)` 传下去，内部一律 `actionsEnabled && 原判据`），**别逐按钮硬编码** |
| 2 | `gp_dice_bar.dart:234-365`（奖惩 / D100 / 其他骰子 / 自定义掷 / 暗骰 / 战技 `combat.roll` / 对抗 `check.opposed`） | `enabled` 只依 `editable`（`role != spectator`）或 `gate.can(op)` | 同上；另需核对骰结果行内的「花幸运 / 推动」入口（同属骰子条子树） |
| 3 | `room_game_page.dart:1006-1070` `_buildToolbar` 注入的「治疗」`treatKey` | 只看 `!isKp` / `canOpenMisc`，与 locked 无关 | 按用户口径锁定态应**禁用**（治疗 = 发起 `aid.apply`，权威端 `_passSelf` 本来就拦） |
| 4 | 同一处的「更多工具」`miscToolsKey` | 与 locked 无关 | **必须保持放行**（用户口径白名单二项之一：推进 1 轮 + 更多工具）；注意 §6-Q5 待拍板，若最终改成「也锁」，波2 一次性改这里 |
| 5 | `sheet_misc.dart` 的「申请治愈疯狂 / 申请治愈重伤」（波2-C 新增） | 尚未落地 | 落在「更多工具」弹层内 → 天然满足「锁定态仍可打开」，**不要**再给它们叠加 locked 判据 |
| 6 | `gp_pl_sketch.dart:186`（`selfLocked` → 不落笔）、`gp_scene_check_pl.dart:79`（`locked` → 不渲染检定按钮） | **已合规** | 不要动（`qa_p5_priv_probe_test.dart:481-483` 已钉死） |

⚠️ **T-30 契约提醒（给波2）**：`gp_toolbar.dart:16-18` / `gp_dice_bar.dart:16-17`
明写「挂了 `RoomKeys.action(op)` 的按钮，`enabled` 必须**恰好**等于 `gate.can(op)`」，
`test/room_ui_permission_test.dart` 用 `actEnabled()`（扫 `act/` 前缀的 `ValueKey`）
逐点读 `RoomTap.enabled`。整棵工具栏叠加 `!locked` 会让**所有** act 探针漂移
→ 必须同步把探针口径改成 `gate.can(op) && !locked`（更强），并做一次反向证伪
（把 `!locked` 去掉必须红）。

**我这个按钮为什么不撞 T-30**：`saveBtn` 的 key 是 `gpPlCharCard/saveBtn`，
**不是** `act/state.self`，`actEnabled()` 按 `act/` 前缀过滤，扫不到它
（`test/room_ui_permission_test.dart:258-269`）。这也是我能在本批安全加锁的原因。

---

## 5. 预计转红的既有测试 + 建议口径（交波4 统一处理）

| # | 测试:行 | 会怎样 | 建议口径（更强或等价） |
|---|---|---|---|
| 1 | `test/room_ui_entry_test.dart:778-786` | ⚠️ **会意外变绿**：断言是 `card.contains('GpPlCharCardKeys.aiBtn')`，而 key **定义**与注释里仍有这个字样 | 语义已反转，**必须改**：`expect(card.contains("roomKey: GpPlCharCardKeys.aiBtn"), isFalse)`（证明渲染点真的撤了），并保留同用例里 `gp_feeds.dart` 的两条正向断言（AI RP 真入口不能删） |
| 2 | `test/p16_button_unify_test.dart:230-238`（`_p16ButtonGroups['gpPlCharCard']`） | 组表仍列 `aid.apply` / `aiBtn` → 大字体溢出用例 `_innerOverflows` 找不到 widget | 组表改成 4 项：`stateBtn` / `itemsBtn` / `saveBtn` / `madness.advance` |
| 3 | `test/p16_button_unify_test.dart:646-670`（P16-08） | `_expectUniform(..., 4 个短按钮)` + `getSize(aid.apply/aiBtn)` 必红 | 改「2 个短按钮各 104×40、同一行、left 相差 108（104+4）」；长按钮仍 `save == adv` 且满宽。**建议再补**：`expect(find.byKey(RoomKeys.action('aid.apply')), findsNothing)`、`expect(find.byKey(GpPlCharCardKeys.aiBtn), findsNothing)`（正反向双咬） |
| 4 | `test/p16_button_unify_test.dart:966-1010`（P16-17，六档屏） | 期望 `列=2 / 行=2 / perRow=[2,2]`，改后只有 1 行 | 改「**恰好 1 行 2 列**」：`lefts.length == 2`、`centers.length == 1`、`perRow == [2]`、四个宽度集合 `== {104}`；六档屏照跑（这仍能咬住「列数被钉死」这条不变量） |
| 5 | `test/p16_button_unify_test.dart:688` `'p1：aid.apply'` | **不是**角色卡断言（是 `RoomRequestCard` 的请求文案 `text: 'p1：aid.apply'`） | **保持不动**，别顺手改（与本次删按钮无关） |
| 6 | `test/p16_wave1_theme_test.dart:131-142`（P-4 急救 payload 源码断言） | 必红 3 条：`"'skill': '急救'"` / `"'targetSeat': seat"` / `"'seat': seat"` 随按钮消失；`contains("RoomKeys.action('aid.apply')")` 也已零命中（我把该字面量从注释里去掉了） | 反向重写：`expect(src, isNot(contains("aid.apply")))`（角色卡不再发该动作）+ 保留 `contains('state.self')`（保存按钮仍在）；「急救 payload 非空」的正向断言由 `p16_wave1_sheets_test.dart:610-617`（治疗弹层 → `aid.apply` + `skill=急救/医学`）承担，**不丢覆盖面** |
| 7 | `test/room_ui_pl_test.dart:242-248`、`test/room_ui_gap_fill_test.dart:113-125`、`test/qa_p5_priv_probe_test.dart:475-479`、`test/room_ui_permission_test.dart:578-592` | **保持绿**（都是 `findsNothing` 负向断言；key 常量仍在，编译不受影响） | 无需改。可选增强：把 `GpPlCharCardKeys.aiBtn` 从这些「锁定态不渲染」清单里删掉（现在它永远不渲染，断言恒真 = P16 踩过的恒真陷阱），改用 `roomKey` 源码门禁覆盖 |
| 8 | `test/room_ui_permission_test.dart:321`（`expect(table.length, 30)`）与 `kFrozenNoAnchor` | **不变，仍绿** —— 关键：`aid.apply` **仍有** act 锚点，来源是 KP 定向指令 `sheet_kp_directives.dart:49` `KpDirective(op: 'aid.apply', label: '急救/医学')`；本批只是把它的**挂载点从角色卡迁走** | 无需改；但建议在该测试的注释里登记「`aid.apply` 的锚点现在只在 `sheet_kp_directives.dart:49`」——否则将来谁删 KP 定向指令会连带打红锚点表 |
| 9 | `test/p10_t1_room_exit_save_test.dart:418-461`（点保存真落盘） | **保持绿**（未锁定态 `gate.can && !locked == true`） | 无需改 |
| 10 | `test/p11_status_bar_test.dart:124-160 / 224-240`（`card.where((t) => t.contains('—')).isEmpty`） | **保持绿**：全卡夹具 `_fullCard()` 的 `attributes.luck = 60` 经 `recalc` 写入 `status.currentLuck`（`engine.dart:132`），老卡夹具也带 `currentLuck: 30` → LUK 显示真实数字，不出「—」 | 无需改；**建议新增**「LUK 出现在卡上且等于 currentLuck」一条（`expect(card, contains('LUK 60'))`），这是 P-1 的正向守卫 |

### 5.1 需要波4 **新增**的守卫（本批行为变更目前无人守）

1. **P-1**：`expect(card, contains('LUK 60'))`（`p11_status_bar_test` 的 `_fullCard` 夹具现成可用）。
2. **P-3**：锁定态下 `tester.widget<RoomTap>(find.byKey(GpPlCharCardKeys.saveBtn)).enabled == false`，
   且未锁定态 `== true`（**必须读 widget 字段，不要断言「不抛异常」** —— P16 的恒真教训）。
3. 以上两条都要求**反向证伪**：改坏（删 `!locked` / 删 LUK）→ 必须红 → 逐字节恢复 → 必须绿。

---

## 6. 给同批队友的信息（已顺手核对，避免重复劳动）

- **波2-B（工具栏/骰子条）**：本批没有动 `gp_toolbar.dart` / `gp_dice_bar.dart`，
  `RoomBtnSize.charTile`（104×40）**未被修改**（消费方从 4 个降为 2 个），
  `diceBalancedRowSizes` / `_balancedRows` 与本次无关。
- **波2-A（页面总装）**：`gpPlCharCard` 的槽位归属未变（`RoomKeys.plSlots` 第 2 位），
  `_slotView` 的格内滚动兜底我复核过是有效兜底，不需要为 LUK 加任何布局补丁。
- **波2-C（更多工具）**：`sheet_misc.dart` 里 P16 留下的 `MiscSheetKeys.aiEntry/aiHint`
  常量现状不变；P-3 的两申请按钮落进「更多工具」即可，无需与本文件联动。
- **所有人**：`gp_pl_char_card.dart` 导出的顶层函数 `selfLocked(state, seat)`
  （`:442-443`）**签名未变**，仍被 `gp_pl_sketch.dart:29/186` 与
  `gp_scene_check_pl.dart:24/79` 依赖。

---

## 7. 声明

- **未跑 `flutter test`**（并发期纪律），只用 `dart analyze lib/ui/room/widgets/gp_pl_char_card.dart` 做静态自检 → No issues found。
- **未改任何既有测试**，**未新建测试**（本批只交生产代码 + 本报告）。
- **未碰别人文件集**：`room_game_page.dart` / `gp_toolbar.dart` / `gp_dice_bar.dart` /
  `sheet_misc.dart` / `member_view.dart` / `sheet_view.dart` 等一律**只读**。
- **未改** `pubspec.yaml` / `pubspec.lock` / `lib/app_version.dart`。
- **未执行** `flutter clean` / 未跑 adb / 模拟器 / 真机。
- 本文件 `lib/ui/room/**` 门禁：emoji 代理对 0 命中、`jsStr(` 0 命中。

### 哈希登记

```bash
sha256sum lib/ui/room/widgets/gp_pl_char_card.dart
# 628994da4ecc0ceae0b62646dec57bdb07d2aad6170fb9230f264f61dfb2a328
```

> 若与实测不一致，说明本报告生成后文件又被改动过 —— 以实测值为准并回问施工人。

---

## 8. 追加：撕卡文案裁决登记（A 案，2026-11 收口）

team-lead 裁决 = **A**：聊天锁定只覆盖「昏迷 / 濒死 / 疯狂发作」，**不含撕卡**。
落点是 W2-A 在 `room_game_page.dart` 新增 `_chatLockedOf`（`operationLocked && !ripped`）
**只**喂 `GpFeeds.locked`（`:873`），工具栏 / 骰子条 / 治疗继续用含撕卡的 `_lockedOf`
（`:1057`）。因此：

- 本文件 `:181-188` 的 `ripped ? '已撕卡 / 无法行动：只能聊天' : '操作受限：只能「推进 1 轮」或申请治愈'`
  与 `GpPlCharCardKeys.locked`（`:186`）**原样保留，零改动** —— 撕卡后聊天确实可用，文案准确。
- `test/qa_p5_priv_probe_test.dart:463-484`（撕卡后 `gpChatInput findsOneWidget` +
  reason「撕卡后仍能聊天」）**断言与 reason 都不用改**。
- 本报告 §5 的 10 条转红项**无一以「撕卡文案要改」为前提**，故 A 案下无一条需要划掉或改写。

### 8.1 波4 建议新增的靶子（A 案下的「反向那半边」）

现有用例只证明「撕卡仍能聊天」，缺少「**昏迷态必须禁聊天**」这半边，建议补一条（口径由
p17-w1b 给出，代码在其报告 §6.8）：

1. 夹具把 `p1` 打到**昏迷**（`status.unconscious = true`，不要用死亡 —— 死亡是 A 案要
   **放行**的那个态，用它测会得到相反结论）；
2. `expect(tester.widget<TextField>(find.byKey(RoomKeys.gpChatInput)).enabled, isFalse)`；
3. 聊天输入行三个 `RoomTap` 全部 `enabled == false` —— **按 key 逐个读，不要数个数**；
4. 点发送后 `sent` 里**没有**新的 `chat`。

**已核实的落点（`gp_feeds.dart` 终版：933 行 / sha256 `27b5a4e0c8153368f884d8d210e9f903736992b7ac548056684101ddc0dc26cd`）**：
`final bool writable = editable && !widget.locked;`（`:858`）是单一变量，同时喂
`TextField.enabled`（`:869`，key 在 `:867`）、`TextField.onTap`（`:881`，
`writable ? () => _openComposer(context) : null`）与三个图标的 `enabled`；
三个图标的 key / enabled 分别是 `GpFeedsKeys.aiRp`（`:891` / `:894`，外面套了
`if (editable)`，`:889`）、`GpFeedsKeys.chatFullscreen`（`:911` / `:914`）、
`GpFeedsKeys.send`（`:920` / `:925`）。锁定态连全屏编辑器都进不去，这条也值得断言
（`expect(field.onTap, isNull)`）。

> ⚠️ 行号有版本性：以上按 `gp_feeds.dart` **933 行**的终版登记（与 p17-w1b 报告 §6.8
> 的锚点表逐行一致）。若波4 执行时该文件行数/哈希已变，**先用 `grep -n "final bool writable"`
> 重新定位**，别按死行号改代码。

```dart
for (final Key k in <Key>[
  GpFeedsKeys.aiRp, GpFeedsKeys.chatFullscreen, GpFeedsKeys.send,
]) {
  expect(tester.widget<RoomTap>(find.byKey(k)).enabled, isFalse, reason: '昏迷态 $k 必须禁用');
}
expect(tester.widget<TextField>(find.byKey(RoomKeys.gpChatInput)).enabled, isFalse);
```

> 为什么不写「本行 `RoomTap` 数量 == 3 且全 false」：`aiRp` 被 `if (editable)` 包着，
> **旁观者只有 2 个**；而且这种计数式断言在有人增删图标时会静默变成「测了别的东西」，
> 属于 P16 那类假绿。按 key 读 + `widget<RoomTap>` 找不到时直接抛红，咬得住。

> ⚠️ 恒真陷阱提醒：第 2 条必须读 `TextField.enabled` 字段，不要断言「点了没反应」——
> `RoomTap` 在 `enabled == false` 时把 `onTap` 置 null（`room_panel_kit.dart:230-234`），
> 用「点击无效」验会与「没有回调」混淆，且容易被 `tester.tap` 的 warnIfMissed 吞掉。
