# QA 独立回归复核报告 · P10 第 7 期 B/C 批

> 复核人：QA 工程师 严过关（Yan / software-qa-engineer-5）
> 性质：**独立回归复核**——自己跑、自己怀疑、自己证伪；不采信工程师报告结论，全部数字为本人在磁盘上实跑所得
> 工程根：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
> 全程中文输出 · 未跑 adb / 模拟器 / 真机 · 未 `flutter clean` · 未删改 `build` 实目录 · 未改 `pubspec.yaml` / `lib/app_version.dart` / `lib/domain/**`
> 每条 flutter 命令前：`unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy` + `export NO_PROXY=127.0.0.1,localhost`；每条 flutter 命令后：`cp pubspec.lock.t7bak pubspec.lock` 并核 `sha256==fa69e596…` / `pub.dev=82` / `flutter-io=0`

---

## 0 · 复核前静态基线（本人实跑，Round 1 起手）

| 项 | 实测值 | 判定 |
|---|---|---|
| `build` 目录 | `drwxr-xr-x`，PowerShell `Attributes: Directory`、`LinkType: (空)`、`IsReparsePoint: False` | ✅ 实目录，非 junction |
| `pubspec.lock` sha256 | `fa69e59604415960b7449e0b5827fb5ec7eec0926a607d6078edca176504d86c`（与 `.t7bak` 逐字节一致） | ✅ 未漂移 |
| `grep -c pub.dev` / `flutter-io` | `82` / `0` | ✅ |
| `pubspec.yaml` sha256 | `be110a37b56db8c7769f1e8ee4f26c28e740a91b2a2446068b7f4f239d33d887` | ✅ 未被本批误改（与 C-A 报告记录值一致） |
| `lib/app_version.dart` sha256 | `7dead8a9992cda6c1f6f20ec46832230bf4428080bd0415f5c5c5381cbf783b5` | ✅ 未被本批误改 |
| 最终态 14 个文件 `sha256sum -c` | **14/14 OK**（10 个 lib + 4 个 test，逐条见 §5 清单） | ✅ 无中途漂移 |
| `lib/domain/**` 最新 mtime | `2026-11-11 13:53`（`room_model_actions_combat.dart`），三份交付报告写于 `11-12 08:29~09:48` | ✅ domain 时间线早于本批，零改动 |
| `lib/domain/data/skills.dart` | `d8f39a909b520b80a536d41df29ffe65f7b0cf732e477f8c6eca05f0ecb94d9e` | 记录基线 |
| `lib/domain/data/occupations.dart` | `e3bcb0a69ac87cb54d23f3a17667620871f64a36c45e07580000eef49e850307` | 记录基线 |
| `test/` 顶层 `*_test.dart` 文件数 | **152** | 与主理人给的口径一致 |
| NUL 扫描 `lib/`+`test/`+`tool/` | 实扫 **408** 个文件，含 NUL 文件数 **0** | ✅ |
| 临时残留 `.bak/.orig/*_clean_*/…`（排除 build/.dart_tool/android/.gradle） | **0 个** | ✅ 无前序残留 |
| 静态门禁脚本 | `tool/qa/qa_p4_gate.js` (12920B)、`tool/qa/qa_p5_ui.js` (16907B) 均存在 | ✅ |
| `oracle_*` 测试 | 8 个（`oracle_dice / engine / madness / normalize / occupation / preset / rules / skillmodel`） | 记录，见 §2 |
| `FROZEN = 4` | 仅 `tool/qa/qa_p5_ui.js:165` 注释中提及（P4 收口口径），未发现被改写 | 见 §2 |

> 注：本工程无 `.git`（`git status` 报 `not a git repository`），故「未改动」一律以 **sha256 逐字节核对 + 文件 mtime 时间线** 作为独立证据，不依赖 VCS。

## 1 · 全量回归 + 静态门禁（Round 1，本人独占串行窗口实跑）

### 1.1 全仓 `flutter test --concurrency=1`

| 项 | 实测 |
|---|---|
| 命令 | `unset 代理; NO_PROXY=127.0.0.1,localhost; flutter test --concurrency=1` |
| 时间 | `09:56:13 → 10:02:58`（**6m45s**） |
| 文件数 | `test/` 顶层 **152** 个 `*_test.dart` |
| 结果 | **`06:37 +2150 -2: Some tests failed.` ⇒ 总 2152 条，2150 通过 / 2 失败，EXIT=1** |
| 命令后 lock | `fa69e596…` / `pub.dev=82` / `flutter-io=0` ✅ |

**Failing tests（日志原文）**：
```
  test/p12_emoji_b_test.dart: B · 源码守卫 lib/ui/room/**/*.dart 里没有任何 1F300–1FAFF 表情字符
  test/room_ui_lobby_test.dart: 门禁 · jsStr 预算（冻结，防新增泄漏） lib/ui/room 的 jsStr 只允许出现在审计过的位置
```

### 1.2 全仓 `--concurrency=4`（顺序依赖 / 并发偶发失败排查）

| 项 | 实测 |
|---|---|
| 时间 | `10:07:25 → 10:09:35`（2m10s） |
| 结果 | **`02:03 +2150 -2: Some tests failed.` ⇒ 总 2152 条，2150 通过 / 2 失败，EXIT=1** |
| 失败名单 | 与 1.1 的 c1 **逐字相同**（同样那 2 条），无新增、无消失 |

⇒ **无顺序依赖、无并发偶发失败**；两条失败在串行与并发两种调度下稳定复现。

### 1.3 其余门禁（同一独占窗口内串行执行，每条后恢复 lock）

| # | 检查 | 命令 | EXIT | 原始输出 | 判定 |
|---|---|---|---|---|---|
| S1 | 两门禁隔离复跑 | `flutter test test/p12_emoji_b_test.dart test/room_ui_lobby_test.dart --concurrency=1` | **1** | `00:06 +28 -2: Some tests failed.`，失败名单同上 | 稳定复现（非偶发） |
| S2 | 静态分析 | `dart analyze lib test` | **0** | `Analyzing lib, test...` + **`No issues found!`** | ✅ |
| S3 | P4 门禁 | `node tool/qa/qa_p4_gate.js` | **0** | **29 行**；`==== 合计 13 条，失败 0 条 ====`；**`P4_GATE IS_PASS: YES`** | ✅ **13/13** |
| S4 | P5 UI 门禁 | `node tool/qa/qa_p5_ui.js` | **1** | **31 行**；`==== 合计 14 条，失败 1 条 ====`；**`P5_UI_GATE IS_PASS: NO`** | ❌ **13/14** |
| S5 | 版本文件单测 | `flutter test test/app_version_test.dart --concurrency=1` | **0** | `00:00 +3: All tests passed!` | ✅ 版本文件未被误改 |

> S3/S4 的「原始输出行数」为 `wc -l` 实测。三条门禁失败彼此印证，**工程师三份交付报告均未跑 `p12_emoji_b_test.dart` / `room_ui_lobby_test.dart` / `qa_p5_ui.js`**，其「全绿 / 14-14」结论是定向子集造成的假绿。

### 1.4 三条红的完整证据与独立定位（不引用工程师结论）

**R1 · `test/p12_emoji_b_test.dart:125`「B · 源码守卫」**
```
  Expected: empty
    Actual: ['lib/ui/room\\widgets\\gp_combat_strip.dart']
  这些房间文件里还有表情符号：[lib/ui/room\widgets\gp_combat_strip.dart]
  package:matcher expect / test\p12_emoji_b_test.dart 125:7
```
本人用 node 按 code point 扫 `lib/ui/room` 五个本批文件，命中：
```
lib/ui/room/widgets/gp_combat_strip.dart:44  🎯 U+1F3AF  |  /// 「🎯 轮到你行动了」提示（空串 = 不显示）。
lib/ui/room/widgets/gp_combat_strip.dart:75  🎯 U+1F3AF  |  '🎯 轮到你行动了',
```
门禁源码实读（:117-126）：`kEmoji.hasMatch(f.readAsStringSync().replaceAll('★',''))` → 只豁免 `★`，`U+1F3AF` 正落在 1F300–1FAFF 禁止区间。**注释与字符串两处都算违规**。

**R2 · `test/room_ui_lobby_test.dart:758`「jsStr 预算（冻结）」**
```
  Expected: empty
    Actual: [ 16 行 … ]
  ★ 新增了 jsStr 直接渲染：
  lib/ui/room/sheets/sheet_combat.dart:126 /130 /131 /137 /139 /182 /183 /187 /190 /209 /210 /214 /218 /460
  test\room_ui_lobby_test.dart 758:7  _jsStrBudgetGroup.<fn>.<fn>
```
门禁源码实读（:727-758）：白名单只有 6 个既有文件 `room_session_local.dart / room_text.dart / gp_scene_check_pl.dart / gp_status.dart / gp_combat_list.dart / room_session_remote.dart`，`sheet_combat.dart` 不在其中；`leaks = hits.where(!allowed…)`，`expect(leaks, isEmpty)`。`jsStr` 会把 null 渲染成字面量 `"null"`（既有 bug class，`ai_rp_prompt_test.dart` 亦在防）。

**R3 · `tool/qa/qa_p5_ui.js` 第 4 条**
```
[FAIL] jsStr( 命中 ≤ 14 且只在白名单 6 文件
       实际 29 处：room_session_local.dart×3, room_session_remote.dart×3,
       room_text.dart×1, sheet_combat.dart×15, gp_combat_list.dart×5,
       gp_scene_check_pl.dart×1, gp_status.dart×1；白名单外 lib/ui/room/sheets/sheet_combat.dart
==== 合计 14 条，失败 1 条 ====
P5_UI_GATE IS_PASS: NO
```
与 R2 同源：`sheet_combat.dart` 新增 15 处 `jsStr(` 把冻结预算从 14 顶到 29。

**独立排除「测试被改坏」**：`test/p12_emoji_b_test.dart` mtime `2026-11-11 15:12:08`、`test/room_ui_lobby_test.dart` mtime `2026-11-11 02:16:41`，两者都不在本批 4 个被改测试文件之列（本批只动了 `p10_t7_b_assets_actors_test.dart` / `p10_t7_c_feeds_test.dart` / `p10_t7_c_combat_test.dart` / `room_ui_kp_test.dart`）⇒ 门禁是既有文件、未被删/改/skip/放宽，失败归因确凿是**本批源码违反既有约束**。
`dart analyze` 零问题恰好说明这不是类型/编译错误，只有静态门禁能抓到。

### 1.5 Round 1 结论

- **结论口径（按主理人 Round 2 触发消息明确）**：`IS_PASS: NO` · `路由: Engineer` · **阻断 2 条**。
  - **「阻断 2 条」= 2 条 `Failing tests` / 2 个根因 / 2 个待修生产文件**：① `gp_combat_strip.dart:44/:75` 的 `U+1F3AF 🎯`（打红 R1）；② `sheet_combat.dart` 15 处新增 `jsStr(`（打红 R2、R3）。
  - **静态门禁红 3 条 ≠ 阻断 3 条**：R1（emoji flutter 门禁）、R2（jsStr flutter 门禁）、R3（jsStr P5 node 门禁）是**门禁输出计数**；其中 R2 与 R3 是**同一个 jsStr 根因**在两个门禁上的两次报红，故按「独立待修问题」计 **2 条**。§1.4 标题「三条红」与此不矛盾。
- **智能路由判定：`Engineer`**（断言期望的是既有正确约束，得到错误输出 ⇒ 源码 bug）。本人未改任何生产代码、未改任何既有用例、未跑 adb/模拟器/真机、未 `flutter clean`；两条阻断由 team-lead 转 `software-engineer-8` 独占修复（本人按指令未自行改这两个文件、未改任何门禁测试）。
- **IS_PASS: NO**（Round 1 当时状态），已通过 SendMessage 回传 team-lead 并给出复现步骤与修复建议；**Round 2 已完成并全绿，最终结论见 §5 / §7（IS_PASS: YES）**。
- 阶段 A 末尾 `sha256sum -c` **14/14 OK**，证明这段时间磁盘无中途漂移。

---

## 2 · 逐条证伪「口径更新不是放宽」（本人逐行读盘 + grep，未引用工程师结论）

### 2.1 `test/room_ui_kp_test.dart` 的 `战斗弹层：combat.start 带 pcSeats / actors`（实读 :1017-1072）

**逐字保留的核心不变量（6 项，行号为本人 Read 实测）**

| 保留项 | 逐字内容 | 行 |
|---|---|---|
| 原用例名 | `testWidgets('战斗弹层：combat.start 带 pcSeats / actors', …)` | 1017 |
| root 存在 | `expect(find.byKey(CombatSheetKeys.root), findsOneWidget);` | 1031 |
| `sent != null` | `final sent = f.lastSent(action: 'combat.start'); expect(sent, isNotNull);` | 1037-1038 |
| `pcSeats` 非空 | `expect((p['pcSeats']! as List).isNotEmpty, isTrue);` | 1041 |
| `actors` 非空 | `expect((p['actors']! as List).isNotEmpty, isTrue);` | 1042 |
| 无异常 | `expect(tester.takeException(), isNull);` | 1069 |
| 卸载收尾 | `pumpWidget(const SizedBox.shrink()); await tester.pump();` | 1070-1071 |

**「直接点」→「先勾选」的改动（唯一口径变更）**：:1035 新增
`await _tap(tester, find.byKey(CombatSheetKeys.monsterToggle('la1')));`，:1036 才
`await _tap(tester, find.byKey(RoomKeys.action('combat.start')));`。此前塞怪的 fixture（:1020-1028）与 `f.clearSent()`（:1032）均未删。

**新增的更强正向断言（7 组，全部为加严）**：
1. :1047-1048 `actorIds` 恰为 `['la1']`（旧版只有 `actors.length == 1`）
2. :1049-1050 `pcSeats` 恰为默认全选的 `f.playerSeats`
3. :1053-1054 `actors` 中 `kind=='pc'` 的记录数 == `f.playerSeats.length`
4. :1055-1062 逐条 PC 记录断言 `seat` 非空、`id.startsWith('p-')`、`containsKey('dex')`/`hp`/`hpMax`
5. :1063-1064 非 PC（怪物）记录恰好 1 条
6. :1065-1068 `CombatSheetKeys.deployCount` 文案含「怪物 1」「玩家 N」
7. :1074-1097 **新增独立用例**「不勾怪物直接部署 → 不发 combat.start + 明确提示」：`lastSent('combat.start') isNull` + `local.notice contains('至少选择 1 个怪物/NPC')` + `takeException() isNull`

→ 结论：这是**用逐字段结构断言替换单一长度断言 + 追加 1 条独立门禁用例**，属加严，不是放宽。

### 2.2 「没有删用例 / 没有弱化」的独立证据（不靠报告自述）

- **mtime 时间线（本人 `find -newermt 2026-11-12`）**：本批窗口内 `test/` 只动了 **4 个**文件——`p10_t7_b_assets_actors_test.dart`(08:23)、`room_ui_kp_test.dart`(08:30)、`p10_t7_c_feeds_test.dart`(08:34)、`p10_t7_c_combat_test.dart`(09:39)；其余 **148 个既有 `*_test.dart` 的 mtime 全部早于 11-12**，物理上不可能被删用例或改断言。
- **用例数交叉验证（本人 grep 计数）**：`room_ui_kp_test.dart` = **35** 条、`qa_p5_priv_probe_test.dart` = **13** 条。B 批报告记录命令「`room_ui_kp_test.dart + qa_p5_priv_probe_test.dart` = 47/47」→ 47−13 = **34** 条（B 批时的 room_ui_kp），C-B 批 +1 条 = **35**，与实测完全自洽 ⇒ 只增不删。
- **弱化模式扫描**：`room_ui_kp_test.dart` 中 `skip:` **0**、`findsWidgets` **0**、`isNotNull` **13** 处、`takeException` **22** 处；对 3 个新测试文件 + 更新文件扫 `skip:` / `findsWidgets` / `expect(true…)` / `expect(1, 1)` → **零命中**（仅 2 处命中是注释里「不用 findsWidgets 放宽」的声明文字）。
- **被明令禁动的既有文件**：`test/room_ui_permission_test.dart` mtime `2026-11-11 01:28:39`（19 条）、`test/room_ui_feeds_test.dart` mtime `2026-11-09 10:33:51`（14 条），均早于本批，一字未动。

### 2.3 GENERATED / oracle_* / FROZEN / 版本文件

| 项 | 本人实测 | 判定 |
|---|---|---|
| `lib/domain/data/skills.dart` | `d8f39a909b520b80a536d41df29ffe65f7b0cf732e477f8c6eca05f0ecb94d9e` | GENERATED FILE，记录基线 |
| `lib/domain/data/occupations.dart` | `e3bcb0a69ac87cb54d23f3a17667620871f64a36c45e07580000eef49e850307` | GENERATED FILE，记录基线 |
| `lib/domain/**` 全树最新 mtime | `2026-11-11 13:53:15`（`room_model_actions_combat.dart`），三份交付报告写于 `11-12 08:29~09:48` | ✅ domain 零改动（时间线独立证据） |
| `test/oracle_*.dart` | 8 个：`oracle_dice / engine / madness / normalize / occupation / preset / rules / skillmodel` | ✅ 存在且 mtime 早于本批 |
| `FROZEN = 4` | 全仓仅 `tool/qa/qa_p5_ui.js:165` 注释提及（P4 收口口径），无被改写痕迹；实跑门禁见 §1 | ✅ |
| `pubspec.yaml` / `app_version.dart` | sha256 与 C-A 报告记录值一致，mtime 均 `2026-11-11 21:53:41` | ✅ 未被误改 |

---

## 3 · 独立反向证伪（本人动手改坏 → 跑红 → 恢复 → 复绿，5 条）

**执行方式**：全部在**独占串行窗口**内完成（前序所有后台 flutter 任务均已结束），单条 Bash 脚本以 `trap 'cp "$BAK" "$FILE"' EXIT` 保证任何中断自动恢复；每条严格按「`cp` 干净备份 → 精确改坏 → `flutter test` **必须红** → `cp` 恢复 → 核 sha256 与最终态一致 → `flutter test` **必须全绿**」，每条 flutter 命令后 `cp pubspec.lock.t7bak pubspec.lock`。改坏期间无任何其他 flutter 进程。

### 3.0 我自己新造的探针（工程师没测过的边界）

C-A 交付报告 §七.3 自认：「全屏编辑器的『系统返回键』路径（`pop` 结果为 `null` → 从 `chatDraft` 回填）已按设计实现，**但未写专门用例**」。
本人新建临时探针 `test/qa_t7_yan_probe_test.dart`（QA 临时文件，跑完删除）：打开全屏编辑器 → `enterText` 一段草稿 → `Navigator.pop()` 无结果（等价系统返回键）→ 断言原 `RoomKeys.gpChatInput` 文本 == 草稿、光标在末尾、`local.chatDraft` 仍为草稿、`RoomIntent.chat` 未发、`takeException() isNull`。
**基线实跑 `+1: All tests passed!`（EXIT=0）** ⇒ 当前实现在该未测边界上确实正确，不是纸面声明。

### 3.1 五条证伪明细

| # | 组 | 改坏动作 | 跑红命令 | RED 结果（失败用例） | 失败断言原文 | 恢复后 sha256 | GREEN |
|---|---|---|---|---|---|---|---|
| F1 | **B** | `gp_kp_left.dart::_assetThumb` 把 `Image.memory(…)` 整块换成 `picture = _thumbPlaceholder();` | `flutter test test/p10_t7_b_assets_actors_test.dart --concurrency=1` | **EXIT=1** `+6 -2: Some tests failed`，转红 **TB1 / TB2** | `Expected: exactly one matching candidate` / `Actual: _DescendantWidgetFinder:<Found 0 widgets with type "Image" descending from widgets with key …>` | `74f7c46578b1df0a3c369bfc382867f073a5983650f4e2d88cefe19dd78385f6` | `+8: All tests passed!` |
| F2 | **C-A** | `gp_feeds.dart` 全屏 `body` 从 `_LiveFeedBody` 换回 `KeyedSubtree(key: liveBody) > FeedList(items: items)` 快照（保留 `liveBody` key，确保红在「实时」本身而非 key 缺失） | `… test/p10_t7_c_feeds_test.dart --concurrency=1` | **EXIT=1** `+8 -2`，转红 **③ 全屏实时 / ④ 无陈旧行** | `Expected: exactly one matching candidate` / `Actual: _DescendantWidgetFinder:<Found 0 widgets with key [<'gpFeeds/row/8'>] descending from [<'gpFeeds/liveBody'>]>` | `43018cef55441d2630dbe5c926c59dc0904d7e13e8c647bd0d8512e57319af75` | `+10: All tests passed!` |
| F3 | **C-B** | `gp_toolbar.dart` 的 `scene.mode` `onTap` 换回直发 `hostAction('scene.mode', {mode:'combat'})` | `… test/p10_t7_c_combat_test.dart --concurrency=1` | **EXIT=1** `+16 -2`，转红 **① 探索态先弹层 / ⑥ 战斗态只发 combat.end** | `Expected: exactly one matching candidate` / `Actual: _TextWidgetFinder:<Found 0 widgets with text "战斗模式 · 选择参战单位": []>`；另 `Expected: not null` / `Actual: <null>`（combat.end 未发） | `13f1a5f3a35ace26715768b6aabe12305dfe5255d4a624f9c847c0597e4b5ca3` | `+18: All tests passed!` |
| F4 | **C-B** | `gp_combat_list.dart` 的 `GpCombatStrip(isKp:…, seat:…)` → `const SizedBox.shrink()` | 同上 | **EXIT=1** `+16 -2`，转红 **⑦ 轮次信息栏两条** | `Expected: exactly one matching candidate` / `Actual: _KeyWidgetFinder:<Found 0 widgets with key [<'gpCombat/strip'>]: []>` | `a3b7d23ac19201c95591ead65cfa14a1a7541d18bebec20546c2a54d0c7887e2` | `+18: All tests passed!` |
| F5 | **自造探针** | `gp_feeds.dart::_openComposer` 的 `final String draft = result ?? local.chatDraft;` → `result ?? ''` | `… test/qa_t7_yan_probe_test.dart --concurrency=1` | **EXIT=1** `+0 -1`，探针 `:75` 转红 | `Expected: '系统返回键也要保住这段还没发完的草稿'` / `Actual: ''` / `Which: is different. Both strings start the same, but the actual value is missing…` | `43018cef55441d2630dbe5c926c59dc0904d7e13e8c647bd0d8512e57319af75` | `+1: All tests passed!` |

> 归因核查：F1 红在「缩略图不存在」、F2 红在「弹层里找不到刚注入的新行」、F3 红在「弹层标题不存在 / combat.end 未发」、F4 红在「strip key 不存在」、F5 红在「草稿变空」——**全部精确命中所改行为**，没有一条是编译失败或无关用例误红，证明这些断言是真在守护对应行为，不是恒真/空转。

### 3.2 恢复后 sha256 清单（每条恢复即刻核对 + 末尾全量复核）

| 文件 | 恢复后 sha256 | 出现轮次 |
|---|---|---|
| `lib/ui/room/widgets/gp_kp_left.dart` | `74f7c46578b1df0a3c369bfc382867f073a5983650f4e2d88cefe19dd78385f6` | F1 |
| `lib/ui/room/widgets/gp_feeds.dart` | `43018cef55441d2630dbe5c926c59dc0904d7e13e8c647bd0d8512e57319af75` | F2、F5（两次均一致） |
| `lib/ui/room/widgets/gp_toolbar.dart` | `13f1a5f3a35ace26715768b6aabe12305dfe5255d4a624f9c847c0597e4b5ca3` | F3 |
| `lib/ui/room/widgets/gp_combat_list.dart` | `a3b7d23ac19201c95591ead65cfa14a1a7541d18bebec20546c2a54d0c7887e2` | F4 |
| 其余 10 个最终态文件 | `sha256sum -c` **14/14 OK** | 末尾全量复核 |
| `pubspec.lock` | `fa69e59604415960b7449e0b5827fb5ec7eec0926a607d6078edca176504d86c` / `pub.dev=82` / `flutter-io=0` | 每条 flutter 命令后 |

**清理**：临时探针 `test/qa_t7_yan_probe_test.dart` 已删除（`probe file present? NO`），`/tmp/qa10_*.bak` 全部删除，工程内 `.bak` / `.orig` / `*_clean_*` 残留 **0 个**。

> 过程留痕：首次批处理中 F2 因替换串缩进差 2 空格未命中（脚本 `OLD NOT FOUND` 后按 `trap` 安全恢复并以 EXIT=1 终止，未留下改坏状态）；本人实读源码精确文本后改用「按关键行定位」的鲁棒 patch 重跑 F2–F5，全部一次成功。这属于 QA 自身证伪脚本的问题（判定 `QA` 自修），**与生产代码、与交付结论无关**，未改任何生产文件。

---

## 4 · 契约与一致性专项（静态审读部分；行为断言见 §1 / §3）

### 4.1 T-30：`enabled` 恰好等于 `gate.can(op)`，没叠业务前置

本人 grep 出的所有 `enabled:` 赋值（10 个改动文件内）：

| 文件:行 | 断言式 |
|---|---|
| `gp_toolbar.dart:130` | `enabled: gate.can('round.next')` |
| `gp_toolbar.dart:139` | `enabled: gate.can('scene.mode')` |
| `sheet_combat.dart:235` | `enabled: gate.can('combat.start')` |
| `sheet_combat.dart:277` | `enabled: gate.can('combat.end')` |
| `sheet_combat.dart:299` / `:325` | `enabled: gate.can('combat.damage')` |
| `sheet_combat.dart:378` | `enabled: gate.can('combat.actor')` |
| `sheet_combat.dart:391` | `enabled: gate.can('combat.pool.set')` |

全部**恰好** `gate.can(op)`，无 `&&` / `? :` 叠加。★「至少 1 怪」门禁写在 `sheet_combat.dart:257` 的 **`onTap` 内**：
`if (monsters.isNotEmpty && selectedMonsterIds.isEmpty) { …showNotice('至少选择 1 个怪物/NPC'); return; }`，
以及 :241-247 的三分支 `hint`，**均未进入 `enabled`**。

### 4.2 空池兼容裁决两面（静态口径）

- 条件精确为 `monsters.isNotEmpty && selectedMonsterIds.isEmpty`（:257）——与主理人 `_p10_transport10_cb.md` §8 定稿一致。
- ① 候选池非空未勾：:258-260 `showNotice('至少选择 1 个怪物/NPC')` + `return`，**不发** `combat.start`；:245 `hint` 为「至少选择 1 个怪物/NPC」。
- ② 候选池全空：:242-243 `hint` 为「当前无怪物候选，将以纯玩家战斗开始」，**无**门禁提示；`actors` 只剩 :138-139 的 PC 记录，仍走 :263-270 `hostAction('combat.start', …)` 历史纯 PC 路径。
- `test/room_ui_permission_test.dart:631-646` 的 T-30 权限探针文件 mtime `11-11 01:28`（未动），实跑结果见 §1。

### 4.3 三处加怪入口口径一致

| 入口 | 表单 | 提交 | 逐字段 |
|---|---|---|---|
| 工具窄栏 `gp_kp_tools.dart` | `ActorFields` + `ActorFieldKeys` | `addLocalActor(…)` :444-450 | name/kind/dex/hp/actionsPerRound 全传 |
| 左窄栏 `gp_kp_left.dart` | `ActorFields` :161（复用 B 批组件） | `addLocalActor(…)` :184-190 | 同上，全传 |
| 战斗弹层 `sheet_combat.dart` | `ActorFields` :356-367（复用 B 批组件） | `_actorPayload(_fields)` :383 | 逐字段读 controller |

- `ActorFieldsController` getter 一律 `int.tryParse(…) ?? 默认`（`gp_kp_tools.dart:122 dex 50 / :123 hp 10 / :124 actions 1`），`kindValue` :120 只认 `monster`/`npc`。
- `addLocalActor` 函数体 :279-281 静默夹 `actionsPerRound` 到 1–10；`hpMax` 与 `hp` 同值。
- `_actorPayload` (:485-499) **无硬编码常量**：`id='u'+name.hashCode.abs()`、`name` 空则「单位」、`kind/dex/hp` 全读 `c.*`、`hpMax=hp`、`ap` 夹 1–10。
- `combat.pool.set` :393-398 载荷 `{'actors': [...local.pendingActors]}`，**候选池整体替换**语义未变。
- `actorSummaryText` 被两处窄栏共用（`gp_kp_left.dart:202` / `gp_kp_tools.dart:462`）。

### 4.4 战斗载荷 + 独立证伪施工图 C2 的错误

- `sheet_combat.dart:135-140`：`actors` = 勾选怪物候选 **`+ _pcActor(m)` 显式 PC 记录**；:266 `actorIds` = `selectedMonsterIds`；:268 `pcSeats` = `selectedPcSeats`。
- `_pcActor` (:459-477) 字段：`id='p-'+seat`、`name`、`kind:'pc'`、`seat`、`dex: memberDex(m)`、`actionsPerRound:1`、`hp/hpMax: memberStats(m)`，取不到给 0，不编默认值。
- ★ **本人独立读 domain 证伪施工图 C2 原话**：`lib/domain/room_model_actions_combat.dart:170-197` 的 `combatStart` 里 `var pool = asList(p['actors'])`（:172），`actorIds` 仅用于 `pool.where(m['kind']=='pc' || ids.contains(id))`（:177-184），`pcSeats` 仅用于过滤已有 PC（:185-197）。**全函数没有任何创建 PC 记录的代码**——「domain 自动带 PC」是施工图 C2 的错误，主理人纠正正确，UI 显式塞 PC 是必需且已落地。

### 4.5 聊天全屏 / 4.6 信息栏实时（源码逐行）

- `gp_feeds.dart:765` `RoomKeys.gpChatInput` 仍在树里；:766-777 `controller` / `enabled` / `onChanged` / `onSubmitted` 全保留；新增 :775 `onTap: editable ? () => _openComposer(context) : null`。
- :800-807 独立 `GpFeedsKeys.chatFullscreen` 入口同样 `if (editable)` → **旁观者不弹全屏**（:760 `editable = role != spectator`）。
- `_send()` :714-721：`setChatDraft('')` + `_text.clear()` + `sendIntent(RoomIntent.chat, {'text': text})` ⇒ 发送清空草稿且发包。
- AI RP :788-796 `onFilled` 只 `_text.text = text` + `setChatDraft(text)`，**不发包**。
- `_openComposer` :733-755 的 `result ?? local.chatDraft`（:751）是「系统返回键草稿回填」路径——**C-A 报告 §七.3 承认未写专门用例**，已选为本人独立新探针靶点（见 §3 证伪 4）。
- 全屏 body :335 = `_LiveFeedBody(pane: pane, limit: widget.limit)`；`_LiveFeedBody` :383-395 用 `getInheritedWidgetOfExactType<RoomScope>()` 空防御后 `RoomScope.of(context)` **订阅**，每帧重算 `collectChats/collectFeeds`（同一 `limit` 口径）。
- `_tailChanged` :475-480 判据为 `now.last.seq != before.last.seq`（**末条 seq，非 length**），cap 打满仍跟随；空列表边界仍按 `length`。:494 `if (!_tailChanged(old) || !_atBottom()) return;` 的 **`!_atBottom()` 早退一字未动**（`_atBottom` :482-486 `< 32`）。`FeedFlashTracker.check` / `_deriveFlash` :183-184 / :295 判定链仍在。
- 主列表 :346-351 `FeedList(items: items, …)` 未删，:290-292 `collectFeeds/collectChats` 未截断；「最新 4 条」只是 :305-311 的 `Text` 标签；:532 `padding: EdgeInsets.zero`。

### 4.7 禁止面（本人 mtime + grep）

- `lib/domain/**` 全树 mtime 最早于本批（最新 `11-11 13:53`）⇒ 零改动。
- 10 个改动文件内 `RoomKeys.action('…')` 的 op 全部是既有 8 个：`round.next / scene.mode / combat.start / combat.end / combat.damage / combat.actor / combat.pool.set / combat.next`；`RoomIntent` 仅 `chat / dice / confirm` 既有枚举；`RoomEvt.` **零命中** ⇒ 无新增 intent / evt / domain action。
- `room_game_page.dart` mtime `2026-11-11 21:51:52`（早于本批，Column/Stack 骨架未动），`RoomSlot.gpCombatStrip` 两个分支 :183 / :732 仍在，兜底分支未被推翻。
- `RoomSlot` / `RoomKeys` 命名、`dock/folded` 档位与共用 gap 机制所在 `room_layout.dart` 本批**仅注释**（mtime 08:21，`:92 270→260`，代码 `:249 return 260;`）。

### 4.8 A 批几何不回归

由 `test/p10_t7_layout_test.dart`（T1 两档间距同源 / T6 舞台 16:9 与 `Image.memory` / T7 去重 / T8 三按钮 ≥48×48 不出格）与 P5 静态门禁 14/14 验证，实跑结果见 §1。A 批其余 5 项（顶栏去重、D100/其他骰子、亮色标题色、素材按 id 去重）由对应既有全量用例 + P5 门禁覆盖，全量结果见 §1。

### 4.9 行为断言专项（本人单跑取数，不引用工程师报告）

| 主理人要求 | 独立验证方式 | 实测结果 |
|---|---|---|
| `room_ui_permission_test.dart:631-646` T-30 权限探针保持全绿 | 源码实读 :631-646（「选槽位后：enabled 仍恒等闸门」，靠**空候选池**直接点 `combat.start` + `combat.enqueue` 造参战槽位，:640-641 注释明确「载荷带的是空的本地候选池」）+ 单跑 | Round 1 单跑 `+19: All tests passed!`；Round 2 12 文件组含该文件全绿；该文件 mtime `11-11 02:16` 未被改动 |
| 空池兼容裁决**两面** | 实读 `p10_t7_c_combat_test.dart:666-706`：**场景 A 空池** → `hint contains('纯玩家战斗')`、`isNot(contains('至少选择 1 个怪物/NPC'))`、`enabled == gate.can('combat.start')`；**场景 B 有怪未勾** → `hint contains('至少选择 1 个怪物/NPC')`、**`expect(f.lastSent(action:'combat.start'), isNull)`（未发包）**、`notice contains(...)`、`enabled` 恒等闸门。另有 :218-239 历史纯 PC 路径（notice 无门禁提示、`actors`/`order` 恰为 PC 数）、:182-193 空手部署未发包 | `p10_t7_c_combat_test.dart` **18 条全绿** |
| 三处加怪入口逐字段 / 载荷 | `p10_t7_b_assets_actors_test.dart`（TB3/4/5/6 逐字段 + TB8 T-30）、`p10_t7_c_combat_test.dart` ⑨ 3 条（DEX33/HP27/每轮3/NPC、非法回落、夹 1–10 + pool.set 整体替换）、`room_ui_kp_test.dart` 口径更新 + 新增用例 | **8 / 18 / 35 全绿** |
| domain `combat.order` 同时有 pc 与 monster 槽 | 实读 `p10_t7_c_combat_test.dart:333-362`：`order 长度 = 1 怪槽 + 2 PC 槽`、`kinds.contains('pc') isTrue`、`kinds.contains('monster') isTrue`、首槽 `isCurrent` | 18 条全绿 |
| 聊天全屏 `enterText` 14 条不回归 | `test/room_ui_feeds_test.dart` 单跑 | `+14: All tests passed!` |
| 信息栏实时 / 闪烁链 | `p10_t7_c_feeds_test.dart`(10) + `room_feed_flash_test.dart`(14) + `room_feed_flash_wiring_test.dart`(10) | Round 2 12 文件组全绿 |
| A 批几何 9 条 | `test/p10_t7_layout_test.dart` 单跑（T1 两档间距同源 / T6 舞台 16:9 与 `Image.memory` / T7 去重 / T8 三按钮 ≥48×48） | `+9: All tests passed!` |
| 12 个关键文件修复后合并回归 | 一条 `flutter test` 传 12 个文件 `--concurrency=1` | **`+207: All tests passed!`（EXIT=0）** |

**A 批 6 项未被打破的独立判据**：本批 `lib/` 只动了 10 个文件且全部位于 `lib/ui/room/`，A 批涉及的 `room_layout.dart` **仅注释**（`:92 270→260`，代码 `:249 return 260;` 未动）；其余 A 批文件 mtime 均早于本批；`p10_t7_layout_test.dart` 9/9 + P5 门禁 14/14 + 全量 2152 条全绿 ⇒ 16:9 舞台、顶栏去重、D100/其他骰子、亮色标题色、素材按 id 去重五项均未被本批回归。

## 5 · Round 2 回归（修复后最终态 —— 决定能否出包）

工程师于 `10:20:04` / `10:21:18` 落盘修复。本人**独立核修法、未采信其结论**：

| 项 | 独立核对结果 |
|---|---|
| `gp_combat_strip.dart` | 新 sha `d6476108aa61cf87d76003aebd9269d4cf9c055fe5541b2ce4d24e9c667b0f7e`；node code-point 扫 `U+1F300–1FAFF` **命中 0 行**；:44 注释 / :75 文案改为纯文字「轮到你行动了」，语义保留 |
| `sheet_combat.dart` | 新 sha `7c3cc69d2e860237ccfde2b00d43a29a0d793889ec4fb31401503ade76d5aa44`；`grep -c "jsStr("` = **0**（原 15 处全改 `roomText(`） |
| 修法等价性 | 实读 `room_text.dart:21`：`String roomText(Object? v) => v == null ? '' : jsStr(v);` ⇒ 对非 null 的 seat/id 完全一致，对 null 返回空串而非字面量 `"null"` ⇒ **语义等价且更严**，正是 jsStr 冻结门禁要的修法 |
| 是否放宽 | **没有改任何测试门禁文件**（`p12_emoji_b_test.dart` / `room_ui_lobby_test.dart` / `qa_p5_ui.js` mtime 均早于本批）；其余 **12 个最终态文件 sha256 全 OK**；mtime 窗口内只新增这两个文件 |

### 5.1 Round 1 → Round 2 逐项对照（全部本人实跑）

| 检查 | Round 1（修复前） | Round 2（修复后） | 判定 |
|---|---|---|---|
| 两门禁 `p12_emoji_b` + `room_ui_lobby` | EXIT=1 `+28 -2` | **EXIT=0 `+30: All tests passed!`** | ✅ 复绿 |
| `qa_p5_ui.js` | EXIT=1／31 行／`合计 14 条，失败 1 条`／**`IS_PASS: NO`** | **EXIT=0／31 行／`合计 14 条，失败 0 条`／`P5_UI_GATE IS_PASS: YES`** | ✅ 14/14 |
| `qa_p4_gate.js` | EXIT=0／29 行／13 条 0 失败／`IS_PASS: YES` | EXIT=0／29 行／13 条 0 失败／`IS_PASS: YES` | ✅ 13/13 |
| `dart analyze lib test` | `No issues found!` | `No issues found!` | ✅ |
| `app_version_test.dart` | `+3: All tests passed!` | `+3: All tests passed!` | ✅ |
| 12 个关键文件 | 前 5 个单跑 19 / 14 / 9 / 35 / 8 全绿（后 7 个因并发缓存竞态中断） | **一次编译 `+207: All tests passed!`** | ✅ |
| 全仓 `--concurrency=1` | **2150 通过 / 2 失败 = 2152**，EXIT=1 | **`+2152: All tests passed!`，EXIT=0** | ✅ **全绿** |
| 全仓 `--concurrency=4` | 2150 / 2 = 2152，失败名单与 c1 相同 | 首跑 EXIT=1（5 条 `did not complete`）→ **诊断重跑 EXIT=0 `+2152: All tests passed!`** | 见 5.2 |

### 5.2 一次并发偶发（如实登记，不隐瞒也不夸大）

- R2-B3 首次 c4 全仓 `Failing tests` 的 5 条**全部**是 `test/p8_wizard_nav_test.dart: … (did not complete)`，**无任何 `Expected/Actual` 断言失败**；日志里同一用例名被重复打印数十次（flutter_tester 并发输出交错/挂起）。
- 该文件属 **P8 向导页导航**，与本批唯一改动面 `lib/ui/room/**` 无依赖关系；Round 1 的 c4 全仓时该文件无异常，Round 2 的 c1 串行全仓 2152 全绿。
- 本人独立复验：① `flutter test test/p8_wizard_nav_test.dart --concurrency=1` → **EXIT=0 `+6: All tests passed!`**；② 全仓 `--concurrency=4` 重跑 → **EXIT=0 `+2152: All tests passed!`**。
- ⇒ **判定：Windows 上 flutter_tester 并发调度/编译缓存瞬时挂起**（与 10:18 的 `PathExistsException errno=183` 同源），**非断言失败、非本批回归、不阻断出包**。按主理人「看有无顺序依赖 / 并发偶发失败」的要求如实登记为**一次并发偶发**；出包判据以串行全量 2152/2152 全绿为准。
- 处置留痕：仅备份并清除 `build/test_cache/build/*.cache.dill.track.dill` **1 个**残留编译缓存文件让其自动重建（before=1 / after=0）；`build` 仍是 `drwxr-xr-x` 实目录，**未 `flutter clean`、未删 build 目录、未改 native_assets**。

### 5.3 修复后新基准的 2 条独立反向证伪 + 连续采样哈希（主理人 Round 2 触发消息要求补做）

**动机**：§3 的 5 条证伪靶点是修复前 / 交付初态的业务行为；主理人要求针对 **Round 2 修复后的两个新最终态文件**（`gp_combat_strip.dart` = `d6476108…`、`sheet_combat.dart` = `7c3cc69d…`）再独立证伪，证明「修复点本身被既有门禁真实守护，且恢复逐字节一致」。两条都用**真实代码回退**（工程师修法的精确反面），不是注释注入。

**独占窗口与前置核对（本人实读）**：`11:01` 检测到 `10:58:35` 启动过一个 `flutter build apk --release`（PID 8232 / 23948，父 10200），说明出包动作已发生；`11:01:58` 用 WMI 精确复查 **NO dart / dartvm / flutter_tester process、无 flutter.bat**，出包已结束、窗口干净后方动手，期间未动任何生产文件（lock 仍 `fa69e596…` / 82 / 0，两文件 sha 与新基准一致）。动手前已 SendMessage 请 team-lead 在窗口内不启动任何 flutter / dart 命令。
另补记一次环境事件：Round 1 阶段 A 曾出现 `PathExistsException errno=183` 并发编译缓存争用，处置仅备份并清除 `build/test_cache/build/*.cache.dill.track.dill` **1 个**残留文件令 flutter 自动重建（before=1 / after=0）；**未删 build 目录、未 `flutter clean`、未改 native_assets**；属环境事件、非代码缺陷、不作失败项（详见 §5.2）。本轮证伪前已用干净态双门禁单跑预热编译缓存，全程未再复现。

**干净态基线（本人实跑，作为「红」的对照）**：

- `node tool/qa/qa_p5_ui.js` → `==== 合计 14 条，失败 0 条 ====` / `P5_UI_GATE IS_PASS: YES`；其中 `jsStr( 命中 ≤ 14 且只在白名单 6 文件` 打印 `实际 14 处`（**恰好等于 BUDGET=14**、白名单外无）⇒ 任何新增 1 处 `jsStr(` 都必然破预算。
- `flutter test test/p12_emoji_b_test.dart test/room_ui_lobby_test.dart --concurrency=1` → `+30: All tests passed!`（EXIT=0）。
- 干净备份 `/tmp/qa10_r2_clean/{strip,sheet}.dart` 的 sha 逐字节等于新基准。

| # | 靶文件（新基准） | 改坏动作（真实代码） | 指定门禁 | RED | 改坏态 sha | 恢复后 sha | GREEN |
|---|---|---|---|---|---|---|---|
| **R2-F1** | `gp_combat_strip.dart` | `:75` `'轮到你行动了'` → `'🎯 轮到你行动了'`（重新注入 U+1F3AF，真实字符串，非注释） | `flutter test test/p12_emoji_b_test.dart --concurrency=1` | **EXIT=1** `+11 -1: Some tests failed`，`B · 源码守卫` 单条转红 | `6d10f2bd…` | `d6476108aa61cf87d76003aebd9269d4cf9c055fe5541b2ce4d24e9c667b0f7e` **OK** | emoji code-point 归 0 |
| **R2-F2** | `sheet_combat.dart` | `:29` `show asMap;` → `show asMap, jsStr;`；`:126` 同一行两处 `roomText(m['seat'])` → `jsStr(m['seat'])`（修法精确回退，可编译） | ① `node tool/qa/qa_p5_ui.js`；② `flutter test test/room_ui_lobby_test.dart --concurrency=1` | ① **EXIT=1** `P5_UI_GATE IS_PASS: NO`；② **EXIT=1** `门禁 · jsStr 预算` 单条转红 | `85628d5d…` | `7c3cc69d2e860237ccfde2b00d43a29a0d793889ec4fb31401503ade76d5aa44` **OK** | `jsStr(` 归 0 |

**R2-F1 失败断言原文**（`/tmp/qa10_r2_f1_red.log`）：

```
00:01 +4 -1: B · 源码守卫 lib/ui/room/**/*.dart 里没有任何 1F300–1FAFF 表情字符 [E]
  Expected: empty
    Actual: ['lib/ui/room\\widgets\\gp_combat_strip.dart']
  这些房间文件里还有表情符号：[lib/ui/room\widgets\gp_combat_strip.dart]
00:02 +11 -1: Some tests failed.
Failing tests:
  … test/p12_emoji_b_test.dart: B · 源码守卫 lib/ui/room/**/*.dart 里没有任何 1F300–1FAFF 表情字符
```

改坏态自检：node code-point 扫 `U+1F300–1FAFF` 命中 **1**（`U+1F3AF`），证明改坏确实落在门禁检测面上。

**R2-F2 失败断言原文**（`/tmp/qa10_r2_f2_red_p5.log` 与 `/tmp/qa10_r2_f2_red_ft.log`）：

```
[FAIL] jsStr( 命中 ≤ 14 且只在白名单 6 文件
       实际 16 处：room_session_local.dart×3, room_session_remote.dart×3, room_text.dart×1,
       sheet_combat.dart×2, gp_combat_list.dart×5, gp_scene_check_pl.dart×1, gp_status.dart×1；
       白名单外 lib/ui/room/sheets/sheet_combat.dart
==== 合计 14 条，失败 1 条 ====
P5_UI_GATE IS_PASS: NO
```

```
00:03 +17 -1: 门禁 · jsStr 预算（冻结，防新增泄漏） lib/ui/room 的 jsStr 只允许出现在审计过的位置 [E]
  Expected: empty
  ★ 新增了 jsStr 直接渲染：
  lib/ui/room/sheets/sheet_combat.dart:126  if (!_pcOff.contains(jsStr(m['seat']))) jsStr(m['seat']),
  test\room_ui_lobby_test.dart 758:7  _jsStrBudgetGroup.<fn>.<fn>
00:03 +17 -1: Some tests failed.
Failing tests:
  … test/room_ui_lobby_test.dart: 门禁 · jsStr 预算（冻结，防新增泄漏） lib/ui/room 的 jsStr 只允许出现在审计过的位置
```

改坏态自检：`grep -o 'jsStr(' sheet_combat.dart | wc -l` = **2**，且 `show asMap, jsStr` 命中 1，证明两处都是**真实代码行**（`qa_p5_ui.js:303` 用 `read(rel).match(/jsStr\(/g)` 不剥离注释、`room_ui_lobby_test.dart:737` 逐行 `contains('jsStr(')` 不剥离注释，均能命中）。

**每条完整链路**：`cp` 干净备份 → node **按唯一锚点定位**精确改坏（不硬编码缩进，规避 §3 末尾「F2 首次缩进坑」）→ 自检改坏特征确实存在 → 指定门禁**必须红并贴断言原文** → `trap restore EXIT INT TERM` + 显式 `cp` 恢复两个生产文件与 lock → 核 sha256 == 新基准 → 内容级归零自检 → 复绿。改坏窗口内无其他 flutter 进程。

**复绿（一次编译，本人实跑）**：`flutter test test/p12_emoji_b_test.dart test/room_ui_lobby_test.dart test/p10_t7_c_combat_test.dart --concurrency=1` → **`+48: All tests passed!`（EXIT=0）**（含 C-B「加单位填数值」「空池兼容裁决 ⑩」等业务断言）；`node qa_p5_ui.js` → **14/14 `IS_PASS: YES`**；`node qa_p4_gate.js` → **13/13 `IS_PASS: YES`**。每条 flutter 命令后 `cp pubspec.lock.t7bak pubspec.lock`。

**连续采样哈希（确认无「改坏残留」）**：恢复后对 `/tmp/qa10_expected_r2.sha` 的 **14 个**最终态文件连续 `sha256sum -c` **3 次**（`11:08:11` / `11:08:11` / `11:08:12`），每次 **OK=14 / FAILED=0**；日志 `/tmp/qa10_r2_sample_{1,2,3}.log`。并做内容级归零：`sheet_combat.dart` 内 `jsStr(` = **0**、`show asMap, jsStr` = **0**、`gp_combat_strip.dart` U+1F300–1FAFF code-point = **0** ⇒ 不只哈希一致，改坏特征串也已彻底消失。

**恢复后 sha256 清单（新基准两个修复文件）**：

| 文件 | 恢复后 sha256 | 与基准 |
|---|---|---|
| `lib/ui/room/widgets/gp_combat_strip.dart` | `d6476108aa61cf87d76003aebd9269d4cf9c055fe5541b2ce4d24e9c667b0f7e` | ✅ 逐字节一致 |
| `lib/ui/room/sheets/sheet_combat.dart` | `7c3cc69d2e860237ccfde2b00d43a29a0d793889ec4fb31401503ade76d5aa44` | ✅ 逐字节一致 |
| 14 个最终态文件 | 连续 3 次 `sha256sum -c` 全 **14/14 OK** | ✅ 无漂移 |
| `pubspec.lock` | `fa69e596…` / pub.dev=82 / flutter-io=0 | ✅ |
| `build` | `drwxr-xr-x` 实目录 | ✅ 未删 / 未 clean |

**完整性**：`test/` 顶层仍 **152** 个 `*_test.dart`；工程内本轮临时残留（`*_clean_*` / `*qa_t7_yan*` / `*.bak` / `*.orig`）**0 个**；所有备份与日志均在 `/tmp`（系统临时目录，不在交付树内）；扫描命中的 `ai_probe.dart` / `qa_probe_test.dart` / `qa_p5_priv_probe_test.dart` / `lan_probe_test.dart` mtime 为 `11-08~11-11`，均为历史文件、非本轮产生。

---

## 6 · 完整性与最终文件清单

| 项 | 最终实测 | 判定 |
|---|---|---|
| NUL 扫描（Round 2 末重扫） | `lib/` + `test/` + `tool/` 实扫 **408** 个文件，含 NUL 文件 **0**（`android/.gradle/**/*.lock` 17B 二进制锁文件按约定排除） | ✅ |
| `pubspec.lock` | `fa69e59604415960b7449e0b5827fb5ec7eec0926a607d6078edca176504d86c`／`pub.dev=82`／`flutter-io=0`（每条 flutter 命令后均 `cp` 恢复） | ✅ |
| `build` | `drwxr-xr-x` 实目录；PowerShell `Attributes: Directory`、`LinkType: (空)`、`IsReparsePoint: False` | ✅ 非 junction |
| 临时残留 | `.bak` / `.orig` / `*_clean_*` / 临时探针 **0 个**；`test/qa_t7_yan_probe_test.dart` 已删；`test/` 顶层仍 **152** 个 `*_test.dart` | ✅ |
| 禁改面 | `pubspec.yaml` `be110a37…`、`app_version.dart` `7dead8a9…` 未动；`lib/domain/**` 最新 mtime `11-11 13:53`（早于本批）；GENERATED `skills.dart` / `occupations.dart` 哈希见 §0；8 个 `oracle_*` 与 `FROZEN = 4` 未动 | ✅ |
| 未跑真机 | 全程未跑 adb / 模拟器 / 真机；未跑 `build_apk.sh`、未动 `android/gradle.properties`、未升版本 | ✅ |

### 6.1 本批所有新增 / 修改文件 + 最终 sha256（14 个交付文件，本人 `sha256sum -c` 14/14 OK）

| # | 组 | 文件 | 状态 | 最终 sha256 |
|---|---|---|---|---|
| 1 | B | `lib/ui/room/widgets/gp_kp_left.dart` | 改（缩略图 + 共享表单） | `74f7c46578b1df0a3c369bfc382867f073a5983650f4e2d88cefe19dd78385f6` |
| 2 | B | `lib/ui/room/widgets/gp_kp_tools.dart` | 改（共享 `ActorFields` 等） | `a207b4bbe18bfd7f0f8612dc6f79e248513bb9c47ed0b08092606be6cf53d5ad` |
| 3 | B | `lib/ui/room/widgets/room_layout.dart` | 仅注释 | `a8146d5431b9620d0f0cf2bb9cb22e2ed8949fae3fac97b8417af1b8f458d21b` |
| 4 | C-A | `lib/ui/room/widgets/gp_feeds.dart` | 改（`_LiveFeedBody` + 贴底 + 全屏编辑） | `43018cef55441d2630dbe5c926c59dc0904d7e13e8c647bd0d8512e57319af75` |
| 5 | C-A | `lib/ui/room/sheets/sheet_chat_composer.dart` | **新建** | `f6821c29922fcd9544a18bd851cfe58a0d9deaa2ba3617ba655082abe7ac214c` |
| 6 | C-B | `lib/ui/room/widgets/gp_toolbar.dart` | 改（onTap） | `13f1a5f3a35ace26715768b6aabe12305dfe5255d4a624f9c847c0597e4b5ca3` |
| 7 | C-B | `lib/ui/room/sheets/sheet_combat.dart` | 改（勾选 + 载荷 + 门禁 + 表单）**★Round2 修复** | `7c3cc69d2e860237ccfde2b00d43a29a0d793889ec4fb31401503ade76d5aa44` |
| 8 | C-B | `lib/ui/room/widgets/gp_combat_list.dart` | 改（strip 渲染 + 顶部文案） | `a3b7d23ac19201c95591ead65cfa14a1a7541d18bebec20546c2a54d0c7887e2` |
| 9 | C-B | `lib/ui/room/widgets/gp_combat_strip.dart` | **新建** **★Round2 修复** | `d6476108aa61cf87d76003aebd9269d4cf9c055fe5541b2ce4d24e9c667b0f7e` |
| 10 | C-B | `lib/ui/room/view/combat_view.dart` | 改（新增 `initiativeText`） | `9c03efd201823af9ccb2b010f162a755bfa0ec9c6f5652295604cc6f5445cfc8` |
| 11 | B | `test/p10_t7_b_assets_actors_test.dart` | **新建**（8 条） | `d8712265ed479c8804cb7e849b2a20b66a0b14c2bda419214977caea9be3446d` |
| 12 | C-A | `test/p10_t7_c_feeds_test.dart` | **新建**（10 条） | `c5a52e8147cbb61a5de7245e67f903736fd8ef8938bbc008ff49e939b5cad475` |
| 13 | C-B | `test/p10_t7_c_combat_test.dart` | **新建**（18 条） | `80401e2b86782caf1c65d3357b31ae0915742bfbeabf2163b5c83faca7a63222` |
| 14 | C-B | `test/room_ui_kp_test.dart` | 改（1 条加严口径更新 + 1 条新增，共 35 条） | `ec9d97b05ee0e7845a85a2651bddbf260df1bf60832ab911565a54199d8228bb` |

> 附：本批另有三份工程师交付报告 `_p10_transport10_b.md` / `_p10_transport10_ca.md` / `_p10_transport10_cb.md`、只读施工图 `_p10_t7_research.md`，以及本报告 `qa_p10_10_report.md`（QA 独立产出，逐块写盘）。QA 临时探针 `test/qa_t7_yan_probe_test.dart` 已删除，不在交付清单内。
> ★ 第 7 / 9 项为主理人转工程师 Round 1 修复后的**新最终态**，已替换主理人最初给的 `26aebc44…` / `e677de14…`；请出包前以此表为准。

---

## 7 · 智能路由判定 / IS_PASS / 遗留 / 真机待测

### 7.1 智能路由判定（严格按「最多 2 轮」执行）

- **Round 1**：`flutter test` 全量 **2 条 Failing tests**（3 条门禁红 / 2 个根因 / **阻断 2 条**），断言期望的是既有正确约束而得到错误输出 ⇒ 判定 **`Engineer`** / `IS_PASS: NO`；未自己改任何生产代码，把文件/行号/失败断言原文/复现步骤回传 team-lead 转 software-engineer-8。
- **QA 自修 1 处**：反向证伪脚本 F2 的替换串缩进差 2 空格导致 `OLD NOT FOUND`（脚本按 `trap` 安全恢复并终止，未留改坏状态）⇒ 属测试脚本 bug，本人实读源码后改「按关键行定位」的鲁棒 patch 重跑成功，未碰生产代码。
- **Round 2**：修复落盘后全量回归全绿 ⇒ 最终判定 **`NoOne`**。

### 7.2 IS_PASS

> ## **IS_PASS: YES**
> 依据（Round 2 最终态）：全仓 `--concurrency=1` **2152/2152 全绿**；`--concurrency=4` 重跑 **2152/2152 全绿**；两门禁 `+30` 全绿；**P4 13/13 `IS_PASS: YES`**、**P5 14/14 `IS_PASS: YES`**；`dart analyze lib test` **No issues found**；`app_version_test` 3/3；12 关键文件 **207/207**；**§3 旧基准 5 条 + §5.3 新基准 2 条 = 共 7 条反向证伪**全部「红→恢复→绿」，新基准复绿 `+48: All tests passed!`；**新基准连续 3 次采样哈希 `sha256sum -c` 均 14/14 OK（FAILED=0）**；14/14 最终态 sha256 OK；NUL 0；无临时残留；lock / build 干净。
> **阻断出包问题：无**（Round 1 的 **2 条阻断 / 3 条门禁红** 已全部复绿，且修法未放宽任何门禁；口径见 §1.5）。

### 7.3 遗留问题（均非阻断）

1. **一次并发偶发**：`--concurrency=4` 出现过 1 次 `p8_wizard_nav_test.dart` 5 条 `(did not complete)`；串行与复跑全绿。与本批无关，建议出包/后续 CI 以 `--concurrency=1` 为准（详见 §5.2）。
2. **候选池仍用 `local.pendingActors`（本机内存、不进存档）**：研究文档 C1 列为「可选、推荐但可延后」，本批未纳入，建议主理人排后续期。
3. **全屏编辑器/信息栏的极端边界**（工程师报告自认，widget 层已覆盖主路径）：「合法 base64 但非图片字节」在真机解码的 `errorBuilder` 降级分支；`ListView.builder` 对行高差异极大数据的首帧贴底可能需 1 帧收敛；单条消息高度超过面板时贴底只能看到下半部分。
4. **轮次信息栏挂载位置**：按最小方案只渲染在 `gp_combat_list.dart` 战斗面板内，`room_game_page.dart` 的 `RoomSlot.gpCombatStrip` 仍是零尺寸兜底分支，未做「横屏地图上方叠加」。
5. `room_ui_kp_test.dart:694` 固有的 `tap()` hit-test **warning**（点 tab 文本命中祖先 InkWell），非失败、非本批引入，全量日志可复现。

### 7.4 真机待测项建议（**只登记，本人未跑 adb / 模拟器 / 真机**）

| # | 用户诉求 | 真机验收点 |
|---|---|---|
| 1 | 问题 2 | 上传素材后缩略图出现；点「公开」后素材栏 +1 且公开栏显示该素材、按 id 不重复；坏图/空图静默占位 |
| 2 | 问题 3 | 三处加怪入口（工具窄栏 / 左窄栏 / 战斗弹层）都能填 DEX / HP / 每轮次数 / 类型；非法输入静默回落默认、每轮夹 1–10 |
| 3 | 问题 5 | 点聊天输入框变全屏多行编辑器；**物理系统返回键**草稿保留（本人 widget 层 `pop` 探针已绿，真机需验实际返回键）；「完成」回填不发、「发送」发包并清草稿；旁观者不弹全屏；AI RP 只填不发 |
| 4 | 问题 6 | 公开信息栏默认可见最新 4 条；全屏打开后再来新消息实时出现；用户上滚回看时新消息**不抢**滚动位置（P0-06） |
| 5 | 问题 10 | 点「转战斗」出现「战斗模式 · 选择参战单位」弹层（玩家默认全选、怪物默认全不选）；候选池非空未勾时提示「至少选择 1 个怪物/NPC」且不开战；候选池全空时 hint 明示「纯玩家战斗」 |
| 6 | 问题 10 | 开战后「第 1 轮 · 当前行动：X」轮次信息栏可见、槽条首槽高亮、`combat.next` 后高亮右移且文案同步；玩家视角隐藏 HP 显示「隐藏」而非 `HP 0` |
| 7 | A 批不回归 | 平板横屏 16:9 舞台、顶栏去重、D100/其他骰子、亮色标题色、三素材按钮热区 ≥48×48 不出格 |

> 出包、升版本、AOT 排雷均由主理人收口；本人未执行 `build_apk.sh`、未改 `android/gradle.properties`、未升版本。

