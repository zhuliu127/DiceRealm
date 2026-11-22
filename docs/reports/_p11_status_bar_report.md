# P11 修 ·「玩家视角自己的 HP / MP / SAN 是空的，显示成 -」· 报告

工程根：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
交付日期：2026-11-11
用户原话：「跑团房间里，玩家视角看自己角色，HP / MP / SAN 三个数值都是空的，显示成『-』。」

---

## 0. 一键结论

| 项 | 结果 |
|---|---|
| 用户看到的 `-` 出自哪一行 | **不是任何一处「输出 `-`」的代码**。它出自 `lib/ui/room/view/member_view.dart:63-69` 的 `_pick(..., 0)`（缺键回退 0）+ `lib/ui/room/widgets/room_panel_kit.dart#StatBar`（`max <= 0 → ratio 0`，只剩一条**空轨道**，视觉上就是一条横线），以及紧挨着的 `lib/ui/room/view/sheet_view.dart:85` 的八项属性 `—`。触发条件只有一个：**该成员没有任何卡数据**（进房了但没绑卡 / 数值没同步到），而 `GpPlCharCard` 只判「人不在」不判「卡不在」 |
| 真因（一句话） | 「未初始化」被画成了「一张 HP 0 / 0 的假卡」——「取不到就显示 0」的典型掩盖 |
| 改了几个文件 | 生产代码 **2** 个（`view/member_view.dart` 新增 1 个纯函数；`widgets/gp_pl_char_card.dart` 1 个分支条件 + 文案） |
| 布局 | **零改动**（同槽位 / 同 SectionBox / 同 child 位置，只换文案） |
| 新建用例 | `test/p11_status_bar_test.dart` **9 组全绿** |
| 既有用例 | `test/room_ui_pl_test.dart` 1 组**口径更新**（同一组，未增删；见 §5，需 lead 过目） |
| `flutter analyze` | **No issues found!**（全量） |
| 全量 `flutter test` | **1980 组全绿**（基线 1959 + 本批 9 + 并行队友新增 12） |
| 反向自证伪 | 摘掉修复判据 → 2 组**变红**（正是「未初始化」那两组）；逐字节恢复后 `sha256sum -c` + `cmp -s` 全通过 |

---

## 1. 第 1 步 · 事实清单（先复现，不修）

### 1.1 三个候选位置逐个数一遍（完整卡 · 玩家 `p1` · 360×640 · 游戏期）

| 位置 | 字段来源 | 实测渲染文本 | 有 `-` 吗 |
|---|---|---|---|
| `GpPlCharCard`（`RoomSlot.gpPlCharCard`） | `memberStats` / `vitalsOf` → `StatBar` | `[HP]` `[12 / 12]`、`[MP]` `[10 / 10]`、`[SAN]` `[56 / 99]` | **没有** |
| `GpPlMates`（`RoomSlot.gpPlMates`） | `hpText/sanText(full:false)` | `HP 12 · SAN 57`、`HP 12 · SAN 57` | **没有** |
| `GpStatus`（`RoomSlot.gpStatus`） | 只画「需我同意」请求卡 | 无 HP/MP/SAN 字样 | **没有** |

四档屏幕（`360×640` / `780×320` / `820×1180` / `1280×800`）× 三种卡形（完整卡 / 老卡 / 空白卡）
逐个 `Text` 抓取：**HP/MP/SAN 一律是 `<现值> / <上限>`，进度条数字矩形都完整落在槽位内**（`inside=true`，无裁剪、无 RenderFlex 溢出）。

三种卡形的实测值：

| 卡形 | 实测 |
|---|---|
| 完整卡（`recalc` 过，带 `derivedStats`） | `12 / 12`、`12 / 12`、`60 / 60`，八项属性 `STR 60 …` |
| 老卡（只有 `status`，无 `attrs`/`derivedStats`） | `9 / 13`、`7 / 11`、`44 / 60`（白名单把 `attrs` 补成 0，不补 `—`） |
| 「清空房卡数值」后的空白卡 | `0 / 0`、`0 / 0`、`0 / 0`（真的是 0） |

**结论 1：全库（`lib/`）搜 `'-'` / `'—'` / `'--'` / `'-–'` 等字面量，`room` 目录下只有 `sheet_view.dart:85`（八项属性）、`feed_view.dart:219`（骰子无 total）、`room_history_export.dart`（KP 名 / 导出时间）。HP/MP/SAN 三处**没有**任何一处会打印破折号。**

### 1.2 决定性复现：**成员在房间里，但没有任何卡数据**

```dart
final f = RoomUiFixture();
await f.boot(inGame: true, withSheets: false);   // 进房了，但 p1 没绑卡
// pump RoomGamePage(p1)
```

实测渲染（`GpPlCharCardKeys.root` 下逐条 `Text`）：

```
我的角色卡
玩家1                     ← nickname（不是卡名！）
正常
HP   0 / 0                ← 进度条 ratio = 0 → 一条空轨道（视觉上就是「—」）
MP   0 / 0
SAN  0 / 0
STR —  CON —  SIZ —  DEX —  APP —  INT —  POW —  EDU —
状态管理 / 急救 / 物品 / AI RP / 保存到已保存 / ⏩ 推进 1 轮
```

`stateOf('p1')['members']` 里该成员：`{seat, role, nickname, online, ready, charId: null, charName: null, spec, joinedAt, cid}` —— **没有 `sheet`、没有 `runtime`**。

**这一屏就是用户报的那一屏**：三个数值是「空的」（进度条空 + `0 / 0`），并且紧挨着出现一串「-」（八项属性的 `—`）。

### 1.3 为什么「三源回退」没能救回来

`sanitizeSheet`（`raSanitizeSheet`）产出的房卡里，`status` 的 10 个键**总是存在**、`attrs` 的 9 个键**总是存在**（缺的补 0）。
所以只要**有过一次绑卡**，三源回退必然有值，绝不会是空 —— 这解释了为什么「完整卡 / 老卡 / 空白卡」全都正常。
反过来说，能画出空卡的前提只有一个：**`sheet` 根本不存在**（三源全空），此时 `_pick(..., 0)` 静默返回 0。

---

## 2. 真因（代码行）

1. `lib/ui/room/widgets/gp_pl_char_card.dart:72`（改前，现在同一判断在 :84）
   ```dart
   if (me == null) { … '还没有绑定角色卡' … }
   ```
   **只判「人不在房间」，没判「人到了但卡数据没到」。** 于是「进房未绑卡」的玩家掉进完整卡片分支。
2. `lib/ui/room/view/member_view.dart:63-74`（未改）
   ```dart
   final hp = _pick(st['currentHP'], rt['hp'], sh['hp'], 0);   // 三处都取不到 → 0
   ```
   这是「取不到就显示 0」的掩盖点 —— 0 点血和「不知道」被压成同一个东西。
3. `lib/ui/room/widgets/room_panel_kit.dart:270`（未改）
   ```dart
   final ratio = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
   ```
   `max = 0` → 进度条**只有空轨道**，用户眼里就是一条横线「—」。
4. `lib/ui/room/view/sheet_view.dart:85`（未改）
   ```dart
   (raw == null || raw == '') ? '—' : _fmt(roomNumber(raw, 0)),
   ```
   八项属性在这张卡上唯一的字面破折号 —— 用户说的「-」。

---

## 3. 修法（生产代码 2 个文件）

### 3.1 新增纯函数 `hasCardVitals`（`lib/ui/room/view/member_view.dart:88-110`）

```dart
/// 该成员有没有**真实的** HP/MP/SAN 数值（区别于 memberStats 的「取不到给 0」）。
bool hasCardVitals(Map<String, Object?>? mem) { … }
```

- 判据与 `memberStats` **完全同源**（`status` → `runtime` → `sheet` 顶层），只要**任意一处**有有限数字就算「有数值」。
- `0` 是合法值（真的 0 点血）→ 空白卡照实显示 `0 / 0`；只有「三处都取不到」才算未初始化。
- 纯 Dart、零 UI 依赖，可单测。

### 3.2 `GpPlCharCard` 增加「卡数据在不在」这一层判断（`widgets/gp_pl_char_card.dart:84-96`）

```dart
if (me == null || !hasCardVitals(me)) {
  final bound = roomText(me?['charId']).isNotEmpty || roomText(me?['charName']).isNotEmpty;
  return SectionBox(key: root, title: '我的角色卡', child: Text(
    bound ? '角色卡的数值还没同步到（重新绑定一次角色卡即可）'
          : '还没有绑定角色卡（等 KP 或房间页绑定）',
    key: GpPlCharCardKeys.unbound, …));
}
```

- 走**已有的**占位分支（同一个 `SectionBox`、同一个 `child` 位置、同一个 key `GpPlCharCardKeys.unbound`）→ **布局零改动**。
- 两种文案区分两种事实：
  - 没绑卡（`charId`/`charName` 都空）→ 「还没有绑定角色卡（等 KP 或房间页绑定）」
  - 卡名在、数值没到（数据缺失）→ 「角色卡的数值还没同步到（重新绑定一次角色卡即可）」

**没有动的**：`memberStats` 的三源顺序、`StatBar`、`attrRows`、槽位表、flex、尺寸、顺序。

---

## 4. 为什么这不是「用显示 0 / 显示 — 来掩盖」

- **改前**才是掩盖：明明没有卡，却画出一张 `HP 0 / 0` + 八项属性 `—` 的假卡 —— 用户据此以为「我的卡坏了 / 游戏坏了」。用户报的 bug 正是这条掩盖链的产物。
- **改后**不再画数值，而是回答「为什么没有数值」：没绑卡 → 去绑卡；有卡名没数值 → 重新绑一次。**能让用户下一步动作的话，比 0 有信息量。**
- **没有把真实 0 也吃掉**：空白卡（「清空房卡数值」）的三条数值仍是 `0 / 0`（用例 2.3 正向钉住），`0` 与「不知道」在数据层就被区分开（`_finite(0) != null`）。
- **没有碰三源回退**：老卡（只有 `status`）、只写 `runtime` 的路径、他人裁剪视图 —— 各自的正向用例都在（§5 组 2、组 3）。

---

## 5. 反向自证伪（逐字节）

把 `if (me == null || !hasCardVitals(me))` 改回 `if (me == null)`（只摘掉修复判据，其余不动）：

```
00:03 +7 -2: Some tests failed.
Failing tests:
  p11_status_bar_test.dart: 1 · 未初始化 … 没绑卡的玩家 → 明确说没绑卡；不再出现 0 / 0、也不出现「—」
  p11_status_bar_test.dart: 1 · 未初始化 … 有卡名但数值没到（ACT 通道 char.share 丢 sheet 的遗留数据）→ 说没同步到
```

**恰好 2 红，且正是「未初始化 ≠ 0」那两组；其余 7 组（完整卡 / 老卡 / 真 0 / 他人裁剪 / 布局守卫）保持绿** ——
证明修复只作用于「没有数据」这一种情况，没有掩盖任何真实数值。

恢复（`cp` 回来）后：

```
lib/ui/room/widgets/gp_pl_char_card.dart: OK
lib/ui/room/view/member_view.dart: OK
cmp OK 逐字节一致

267164c9607ab5d5898b920a6ace83dab0f9de80461ada5643bdb86643452946  gp_pl_char_card.dart
38ac3a06f9738d10733d73b947f969d3bc5d6b9215f9a8ae16a504e84a058a84  member_view.dart
```

---

## 6. 测试账目

### 6.1 新建 `test/p11_status_bar_test.dart`（9 组）

| 组 | 用例 | 钉住什么 |
|---|---|---|
| 0 | 完整卡 · 三个候选位置逐个数 | **事实清单**：`12 / 12`、`10 / 10`、`56 / 99`；队友行 `HP 12 · SAN 57`（无 `/`）；状态条无 HP；整卡无 `—` / 无 `-` |
| 1 | 没绑卡的玩家 | 明确说「还没有绑定角色卡」；**不得出现 `0 / 0`、不得出现 `—`、不得出现 `HP` 标签** |
| 1 | 有卡名但数值没到（ACT `char.share` 遗留数据） | 明确说「数值还没同步到」；不得 `0 / 0` |
| 2 | 完整卡（`derivedStats` → status 满值） | `12 / 12` ×2、`60 / 60`、`STR 60`；无 `—`；不出现「未绑定」 |
| 2 | 老卡（只有 `status`） | `9 / 13`、`7 / 11`、`44 / 60` |
| 2 | 真的 0（清空房卡数值） | 三条 `0 / 0` **照实显示**（0 是事实） |
| 3 | `p1` 看 `p2`（他人视角） | 数据层 `maxSAN == null`、`attrs` 整个不存在；渲染层队友行只有当前值、无 ` / `；自己那张仍是 `56 / 99` |
| 3 | `p2` 自己的视角 | `57 / 99` + `DEX 57`（证明拿到的是自己那份**完整**卡，不是被裁过的那份） |
| 4 | 布局守卫 | `gpPlCharCard` 槽位在、`GpPlCharCard` 在、HP/MP/SAN 三个标签各一条、零异常 |

### 6.2 既有用例口径更新 1 组（**需 lead 过目**）

`test/room_ui_pl_test.dart`「★ 没有角色卡的座位（旁观者）：属性显示「—」而不是 0（K4 缺键 ≠ 0）」

- **改前**：断言旁观者（无卡）看到 `STR —`，也就是**一张属性全 `—` 的空卡**。
- **改后**：断言同一场景**根本不画数值**（`unbound` 占位 + 无 `STR —` + 无 `HP` 标签）。
- **这不是放宽，而是加严**：K4「缺键 ≠ 0」从「显示 `—`」升级为「连 0 和 `—` 都不出现」。
  该组原有语义（「没有卡就没有技能行」「root 仍在」）全部保留。
- 副作用为零：`attrRows` 的 `—` 分支仍在（他人裁剪 / 防御路径），只是不再被「无卡」触发。

### 6.3 账目

| 项 | 数 |
|---|---|
| 基线 | 1959 全绿 |
| 本批新增 | **+9**（`p11_status_bar_test.dart`） |
| 当前全量 `flutter test` | **1980 组全绿**（含并行队友新增的 12 组） |
| `flutter analyze` | No issues found!（全量） |

---

## 7. 附带发现（**本批未修**，供 lead 决定是否排期）

| # | 位置 | 事实 | 影响 |
|---|---|---|---|
| A | `lib/domain/room_model_actions_room.dart:632-649` `roomActionCharShare`（ACT 通道的 `char.share` 别名） | 收下 `p['sheet']` 却**整个丢掉**，只写 `charName` / `charId`（与 INTENT 通道的 `shareSheet` 不等价） | 任何走 ACT 通道上卡的客户端（老客户端 / 事件重放 / 外部客户端）都会造出「有卡名没卡数据」的成员 —— 本批的 §1.2 第二种文案就是为它准备的。我们的 UI 只走 INTENT，所以真机正常路径不受影响。**建议**：让它委托 `shareSheet(...)`（`room_model_save.dart`），一行改动即可收敛；本批没动是为了不碰 P4 oracle 的 `char.share` 分支 |
| B | `lib/ui/room/sheets/sheet_bind_char.dart:215` `_clear`（清空房卡数值） | 用 `Character(<String, Object?>{})` 造空白卡 → `card.characterName` 是 `jsStr(null) == 'null'` → 房间里的**卡名变成字符串 `null`** | 清空后卡片标题显示「null」。**建议**：`cardToRoomSheet` 里把 `characterName` 换 `roomText` 口径（或 `_clear` 直接给 `name: ''`） |
| C | `lib/ui/room/widgets/gp_pl_mates.dart:143` 队友行 | 队友**没绑卡**时显示 `HP 0 · SAN 0` | 同类「未初始化伪装成 0」，但用户没报、且队友栏没有「没卡」的占位设计；本批未动（避免扩大改动面） |
| D | `lib/ui/room/widgets/gp_pl_sketch.dart:237` | 手绘板信息行同样固定拼 `HP 0/0` | 同上 |

---

## 8. 铁律自检

- 布局零改动：槽位表 / flex / 尺寸 / 顺序 / `SectionBox` 结构全部未动（用例 4 显式守卫）。
- 只读派生层未变：`memberStats` 三源顺序、`StatBar`、`attrRows`、`hasMaxSan` 裁剪语义全部未动（组 3 正向钉住）。
- 生产代码 2 个文件、净增约 30 行（含注释与文档）；无新依赖、无 I/O、无 Flutter 依赖进入 `view/`。
- 未改 domain / net / repo；未改存档格式、未改网络帧。
