# P11 四条「静默丢数据 / null 当文字」修复报告

**IS_PASS：是**（`flutter analyze` 零问题；全量 `flutter test` **1980 → 1987 全绿**，零失败）

工程：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
新增用例：`test/p11_misc_bug_test.dart`（7 条）

---

## 1. 四条结论（改前 → 改后 → 为什么）

### A（最重要）ACT `char.share` 把整份角色卡数据丢掉

- 位置：`lib/domain/room_model_actions_room.dart:640` `roomActionCharShare`
- **改前**：自己维护一份「只写 `charName` / `charId`」的实现，
  `p['sheet']`（整份卡数据）被整块丢弃；成员留下「有卡名、无卡数据」的坏形状，
  只能靠角色卡面板的「数值还没同步到」占位兜住。
- **改后**：委托给 INTENT 侧唯一实现
  `shareSheet(jsStr(mem['role']), target, mem, p)`（`lib/domain/room_model_save.dart:176`）。
  该函数负责：整份 `sheet` 覆盖 + `raSanitizeSheet` 白名单 + 权威端
  `tempStatus` / `items` 贴回 + `runtime` 现值写入。sheet 语义只有这一份实现，
  ACT / INTENT 两条通道从此同源。
- **保留**：函数开头的越权守卫原样（`asked != seat` → `sysTo(seat, '只能上报自己的角色卡')`；
  旁观者 → `'旁观者不需要上报角色卡'`）。用例 A-2 专门钉住。
- **为什么**：上游持续在生产坏数据。只补 UI 占位等于「兜住症状、留着病根」。

### B 「清空房卡数值」把卡名写成字符串 `null`

- 位置：`lib/ui/room/sheets/sheet_bind_char.dart:220` `_clear`
- **改前**：`cardToRoomSheetForReport(Character(<String, Object?>{}))` →
  `characterName` 取到 `jsStr(null)` → `'null'`（JS `String(null)` 语义）→
  广播出一张名叫「null」的卡。
- **改后**：显式 `Character(<String, Object?>{'characterName': ''})`。
  空串仍会被 `raSanitizeSheet` 回落到权威端保留的 `mem.charName`，
  所以「清空数值但保留卡名」的产品语义不变，只是不再写出字面量 `null`。
- **为什么**：`jsStr(null) == 'null'` 是刻意复刻的 JS 语义，不能改
  （规则层/存量数据都依赖它），所以在构造侧把值落成合法的空串。

#### `_clear` 路径字段排查清单（同一条载荷全字段过一遍）

| 字段 | 来源 | 空 map 时的取值 | 是否会被 `jsStr(null)` 污染 |
|---|---|---|---|
| `name` | `card.characterName` | `'null'` | **是 → 已修** |
| `avatar` | `cardToRoomSheetForReport` | 无缩略图 → 删键 | 否 |
| `attrs`（str/con/siz/dex/app/int/pow/edu/luck） | `raClampNumber(null)` | `0` | 否 |
| `status`（HP/MP/SAN/幸运 6 项） | `_num(null)` / `raClampNumberOrNull` | `0` / `null` | 否 |
| `status.body` | `migrateBodyStatus` | `'正常'` | 否 |
| `status.dying` / `unconscious` | `jsTruthy(null)` | `false` | 否 |
| `mental` | `null → []` | `['正常']` | 否 |
| `skills` / `madness` / `items` / `weapons` / `history` / `armors` | `asList(null)` | `[]` | 否 |
| `background` 7 项 / `assets` 5 项 / `look` / `world` / `gender` / `era` / `residence` / `birthplace` / `occupation` | `cleanText(null)` | `''` | 否 |
| `charId` | `p['id'] == ''` | 真 `null`（不是字符串） | 否 |

结论：卡名是**唯一**会输出字符串 `'null'` 的字段。用例 B-1 额外用
`_stringValues(sheet)` 递归扫描所有层级字符串值，断言不含 `'null'`，
防止以后新增字段时同类回归。

### C 玩家栏队友行：无卡成员仍拼 `HP 0 · SAN 0`

- 位置：`lib/ui/room/widgets/gp_pl_mates.dart:127` 起
- **改前**：无条件 `'${hpText(...)} · ${sanText(...)}'`。
  `memberStats` 的契约是「取不到给 0」，于是未初始化显示成「0 点血」。
- **改后**：`hasCardVitals(m)` 为真才拼数值，否则文案 `'未绑卡'`（3 字，
  与角色卡面板同一判据、同一套三源：`sheet.status` → `runtime` → `sheet` 顶层）。
- **布局零改动**：仍是同一 `Column` / 同一 `Text` 槽位，只换分支文案。

### D 手绘板状态行：无卡成员仍拼 `HP 0/0`

- 位置：`lib/ui/room/widgets/gp_pl_sketch.dart:233` 起
- **改前**：`'… · ${points.length} 点 · HP ${stats.hp}/${stats.hpMax}'` 固定拼接。
- **改后**：末段按 `hasCardVitals(me)` 分支 —— 有卡仍是
  `' · HP x/y'`，无卡是 `' · 未绑卡'`。
- **布局零改动**：仍是同一个 `Expanded + Text(maxLines:1, ellipsis)`，
  文案更短，不会新增溢出风险。

---

## 2. 反向自证伪（4 处各注入一次 → 真红 → 逐字节恢复）

注入前四个文件已 `cp` 到 `/tmp/p11_misc_bak/` 并记录 sha256：

```
dfcfc6f90d8b1b90608146151eca4cc8c605eca13015aa4a470bc1e7a6d0838f  lib/domain/room_model_actions_room.dart
07e8108204ef29c81c5e23b779810defc62ab9f14de83bb1fed4d7d6c207115c  lib/ui/room/sheets/sheet_bind_char.dart
725c5d92e04a33f1529a6e9e9e15567dddd270eb5f8e584acaf17251a7eaf606  lib/ui/room/widgets/gp_pl_mates.dart
4748edd4362e010bc36a6289fa113ae870ac7bfc1121ee1be56d08a1099d63b3  lib/ui/room/widgets/gp_pl_sketch.dart
```

| 注入 | 注入内容 | 实际输出 | 恢复校验 |
|---|---|---|---|
| A | 把 `return shareSheet(...)` 换回旧的「只写 charName/charId」 | A-1 红：`Expected: non-empty` / `Actual: {}`，「★ 修复前这里整块为空」 | `sha256` 同前，`cmp -s` 通过 → `RESTORE_OK_A` |
| B | `{'characterName': ''}` 改回空 map | B-1 红：`Expected: ''` / `Actual: 'null'` | 同上 → `RESTORE_OK_B` |
| C | 队友行改回无条件拼 HP/SAN | C-1 红：`Expected: true` / `Actual: <false>`，「★ 无卡成员必须如实说没绑卡」 | 同上 → `RESTORE_OK_C` |
| D | 手绘板改回无条件拼 HP | D-1 红，实测文案 `画笔 · 0 点 · HP 0/0` | 同上 → `RESTORE_OK_D` |

最终 `sha256sum -c` 四行全 `OK`，即生产代码与注入前逐字节一致（没有残留注入）。

---

## 3. 测试账目

| 项 | 结果 |
|---|---|
| 基线 | 1980（全绿） |
| 新增 | `test/p11_misc_bug_test.dart` 7 条：A-1 / A-2 / B-1 / C-1 / C-2 / D-1 / D-2 |
| 全量 | **1987 +，All tests passed**（`flutter test`，01:10） |
| analyze | `No issues found!` |
| 反向自证伪 | 4/4 注入真红，4/4 逐字节恢复 |

新增用例都是「正向 + 反向对照」：C-2 / D-2 证明有卡的成员不会被误判成
「未绑卡」（防止把 `hasCardVitals` 写成恒 false 也能过）。

**未做**：不跑 `flutter clean`、不改 `pubspec.yaml`、不动 `lib/ui/room/**` 布局结构、
不放宽任何断言（无 `findsOneWidget → findsWidgets`、无删 `findsNothing`）。

---

## 4. A 的 oracle 跑测结果（重点）

```
flutter test test/p11_authz_ready_test.dart test/qa_p4_fresh_oracle_test.dart \
             test/qa_p4_final_gate_test.dart test/qa_p4_alias_actions_test.dart
→ 00:00 +41: All tests passed!
```

- `oracle_*` 系列（dice / engine / madness / normalize / occupation / preset / rules /
  skillmodel）在两次全量里均通过 —— 它们都在规则层，A 只改房间动作层。
- `qa_p4_fresh_oracle_test` 绿（其中 `A:intent:char.share#42` 走 INTENT 通道，
  本来就已是完整 sheet 语义，未受影响）。
- `qa_p4_final_gate_test` / `qa_p4_alias_actions_test` / `p11_authz_ready_test` 绿。
  `room_actions.json` 里没有任何 `entry: "act"` + `char.share` 的 oracle 用例
  （已 grep 确认 count=0），因此 A 不撞 ACT 侧夹具。

**未改任何测试 / 夹具来迁就 A。** 唯一涉及测试文件的改动见下节，且**不是** oracle 夹具。

---

## 5. 需要 team-lead 裁决的一处（A 的连带影响）

`test/p11_status_bar_test.dart:192` 那条用例，改前是**靠被修的 bug 造形状**：

```dart
// 旧写法：把完整 sheet 交给旧 ACT 通道，指望它把 sheet 丢掉
hostAction('char.share', {'id': 'full01', 'name': '完整卡',
                          'sheet': cardToRoomSheet(_fullCard())});
```

A 修好后这条路会正常落库 → 卡片显示真实数值 → 该用例必红（实测确实红了）。

**我的处理（只改形状构造，断言一字未动）**：payload 去掉 `sheet`
（= 旧客户端 / 旧存档里那条「有卡名、无卡数据」记录的真实样子），
并加注释说明。两条断言原样保留：

```dart
expect(card, contains('角色卡的数值还没同步到（重新绑定一次角色卡即可）'));
expect(card.where((String t) => t.contains('0 / 0')).toList(), isEmpty);
```

如果团队认为「不许碰这个测试文件」，替代方案是直接 patch `host.roster`
（同样不动断言），或删掉这条用例（会掉 1 组基线）。请裁决。

另：`room_ui_lobby_test.dart` 的「jsStr 预算（≤13 处）」门禁把我写在
`sheet_bind_char.dart` 注释里的字面量 `jsStr(...)` 也算成泄漏，已改写措辞
（语义不变，不改门禁、不调预算）。

---

## 6. 改动文件清单

| 文件 | 改动 |
|---|---|
| `lib/domain/room_model_actions_room.dart` | `roomActionCharShare` 委托 `shareSheet`（+ 新增 `room_model_save.dart` 导入） |
| `lib/ui/room/sheets/sheet_bind_char.dart` | `_clear` 显式 `characterName: ''` |
| `lib/ui/room/widgets/gp_pl_mates.dart` | 队友行数值按 `hasCardVitals` 分支，无卡 → `未绑卡` |
| `lib/ui/room/widgets/gp_pl_sketch.dart` | 状态行末段按 `hasCardVitals` 分支，无卡 → `未绑卡` |
| `test/p11_misc_bug_test.dart` | 新增 7 条回归用例 |
| `test/p11_status_bar_test.dart` | 仅改 1 条用例的**形状构造**（见 §5），断言未动 |

无新增依赖；无新增公开 API（只多一个 extension 导入）。
