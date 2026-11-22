# QA 独立复核报告 · P10 第 4 期

- 复核人：严过关（QA / software-qa-engineer-4）
- 工程：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
- 被复核交付：`_p10_transport6.txt`（271 行，工程师 寇豆码 / software-engineer-5）
- 上批基线（我自己跑的）：**1905** 全绿 / APK `8e2bf6e4…536d0c` / 70,001,068 B
- 复核原则：所有数字自己跑出来；A 是**我上批 §8 登记并判「下一批 P1」的遗留**，按当初写下的原判据验，不因是自己提的就放水。

---

## 0. 一句话结论

**PASS / 智能路由：Send To: NoOne**（无需返工）。

- 五项自检全部复现：全量 **1918** 全绿、串行 **1918** 全绿、`dart analyze` 零、P4 **13/13**、P5 **14/14**；**独立出包与工程师逐字节一致**（70,033,836 B / `fd9b05c9…5072`）。
- **用户硬约束「UI 布局不要改」成立**：独立 mtime + 哈希双证，`lib/ui/room/**` 本批零写入；生产改动恰好 3 个文件。
- A 的「计划数变更」**没有放宽任何既有用例**（既有测试文件本批**零改动**，逐行复现了影响表）；行为级探针把上批实测的 `客户端剩余待办卡=1 / REQUEST-done=false / pending=1` 翻成 **卡片消失 / REQUEST-done=true / pending=0**。
- B 的**两个真 widget 搜索框**我都自己跑通；54/54 覆盖、双向可搜、不污染、不显示、职业搜索不接的结论都有独立数据支撑；5 处反向证伪全部逐字节恢复。

---

## 1. 五项自检（原始输出）

| # | 项 | 我的实测 | 与工程师 |
|---|----|---------|---------|
| 1 | `flutter test`（默认并发） | `01:12 +1918: All tests passed!` | ✅ 1918 复现 |
| 2 | `flutter test --concurrency=1` | `04:54 +1918: All tests passed!` | ✅ 工程师本批自己跑了（04:50），我仍独立复跑，无顺序依赖 |
| 3 | `dart analyze` | `Analyzing dice-realm... No issues found!` | ✅ 零 |
| 4 | `node tool/qa/qa_p4_gate.js` | `==== 合计 13 条，失败 0 条 ====` / `P4_GATE IS_PASS: YES` | ✅ 13/13 |
| 5 | `node tool/qa/qa_p5_ui.js` | `==== 合计 14 条，失败 0 条 ====` / `P5_UI_GATE IS_PASS: YES` | ✅ 14/14 |

`jsStr(` 实测 **14 处**（`room_session_local×3 / room_session_remote×3 / room_text×1 / gp_combat_list×5 / gp_scene_check_pl×1 / gp_status×1`，白名单外 0）；P5 的 `lib/domain 纯 Dart（零 Flutter / IO / UI）` 为 `[OK]`，我另 `grep -rn "dart:ui" lib/domain/` = **0**（连注释里字面量都没有，新表是纯 Dart）。

**关于「首轮 2 条 analyze 告警」**：我独立核过 `test/` 全部文件 mtime —— 本批 08:00 之后**只有新增的 `p10_t4_synonym_request_done_test.dart`（08:31）**被写，没有任何既有测试文件被改。两条告警（`engine.dart show` 了不存在的 `syncSkills`、unused import）都出在**新增测试文件自身**的 import 行，修法是 `show recalc` + 删多余 import（`syncSkills` 实际来自 `chargen_logic.dart`，新文件现在两者都正确导入）。⇒ **无生产问题、没有靠放宽 lint / 加 ignore 压下去**，analyze 归零是真实修复。

恢复 5 处证伪改动后又跑一遍：`01:10 +1918: All tests passed!` + `dart analyze → No issues found!`。

---

## 2. ★ 用户硬约束：`lib/ui/room/**` 布局零改动（独立证据）

**证据 1 · 施工窗内全库写入清单**（`find lib test tool -newermt "2026-11-11 08:00"`）：

```
2026-11-11 08:23:39  lib/domain/room_model_host_intent.dart
2026-11-11 08:23:46  lib/ui/create/skill_groups.dart
2026-11-11 08:24:36  lib/domain/skill_synonyms.dart     （新增）
2026-11-11 08:31:32  test/p10_t4_synonym_request_done_test.dart （新增）
```

⇒ 生产改动**恰好 3 个文件**，与工程师报一致；`lib/ui/room/**` **一个文件都没被写**。`find lib/ui/room -newermt "2026-11-11 08:00"` 结果为空。

**证据 2 · `lib/ui/room/**` 最晚 mtime**（全部早于 08:23 施工窗）：

```
07:58  sheets/card_sheet_payload.dart
07:53  room_game_page.dart
02:11  widgets/gp_feeds.dart      02:10 view/feed_view.dart
01:55  widgets/room_layout.dart   01:37 widgets/gp_toolbar.dart
01:31  widgets/room_panel_kit.dart   ... 其余更早
```

`room_keys.dart` = **11-09 12:40**，`room_feed_flash.dart` 等全部早于本批。

**证据 3 · 逐字节哈希对照（比 mtime 更强）**：我把两个最近被 touch 的布局文件与我上批（第 3 期 B）结束时记录的哈希对比：

| 文件 | 第 3 期 B QA 基线 | 现在 | 判定 |
|---|---|---|---|
| `lib/ui/room/sheets/card_sheet_payload.dart` | `ebb9fcfec6520f395fc59aa53f00bfa836a1f0af27371c24390168393ad19653` | **完全相同** | 内容一字未动 |
| `lib/ui/room/room_game_page.dart` | `bbd911a7a2062b1ce602ff8edb04563767e24c0457b9f2c55be580f767ecf86b` | **完全相同** | 内容一字未动 |

⇒ 即使 07:58/07:53 有过 touch，**内容也没变**。用户硬约束**成立**。

---

## 3. ★ 重点 1：A 的「计划数变更」有没有被放宽 —— **没有**

### 3.1 独立扫描（不采信报告表格）

`grep -rln "RoomIntent.consent|state.request|consent(" test/*.dart` 命中 **3 个文件**：`p10_t3b_rule_diff_test.dart`、`p10_t4_synonym_request_done_test.dart`（新增）、`room_ui_blocks_test.dart`。我逐个核了 `hasLength / .length / plan( / sent.length / plans.length` 断言，并逐行复现工程师影响表：

| 既有用例 / 断言 | 我读到的原文 | 是否触及 consent 出站计划数 | 裁决 |
|---|---|---|---|
| `room_ui_blocks_test.dart:442-469` | `:451 requestsBySeat['p1'] hasLength(1)`（**前置出队前**）、`:464 _lastP(f, RoomIntent.consent)` 读 **UI 发出的 intent**、`:468 requestsBySeat isEmpty` | ❌ | 无需改，实测仍绿 |
| `qa_p4_final_gate_test.dart:284/341` | `expect(out, hasLength(1))` 是 **F4 掷骰**（`diceDirect`），与 consent 无关 | ❌ | 无需改 |
| `p10_t3b_rule_diff_test.dart:671/682/740` | T7-1/2/3 是 **check.request 三段式**分支 | ❌ 本批该分支一字未动 | 无需改 |
| `room_actions_test.dart:210` | POLICY 61 action 分支存在性 | ❌ | 无需改 |
| `room_ui_kp_test.dart:241/308` | KP 待办面板 `kpUnreadCount` 渲染 | ❌ | 无需改 |

**更强的证据**：`find test -newermt "2026-11-11 08:00"` 只有新增文件 ⇒ **既有测试文件本批零改动**，因此「把 `hasLength(n)` 降级成 `isNotEmpty`」「整组删用例」在物理上不可能发生。全量 1918 = 1905 + 13 也反证无删减。

### 3.2 老 APP 原文对拍（我自己读的）

- `room-model.js:1569`：`out = out.concat(this._settleRequest(seat, req.id, !!p.agree, null));`（**先结算再落账**）
- `:3138-3151 _settleRequest`：`list.splice` + `pending.filter(x.id !== id)` + `emit(EVT.REQUEST, {self,id,done,at}, VIS.SEAT, seat)` + `if (verb) sys(...)`
- 新 `host_intent.dart` 状态分支：`settleRequest(seat, id, agree, null)`；新 `settleRequest`（`combat.dart:1002-1024`）= `list.removeWhere` + `pending.removeWhere` + `emit(RoomEvt.request{...}, vis: seat, to: seat)` + `if (verb != null && verb.isNotEmpty) sys(...)`。

⇒ **逐项等价**，`verb=null` 确实不多发公共 sys（我 W1-1 探针断言公共 LOG 恰好 1 条、无「同意并完成了」verb 文案）。`agree` 参数在老 `_settleRequest` 里本就未被使用，新签名保留但同样不影响行为。

### 3.3 用户文案 / check.request 分支未动

`grep` 核实 5 条文案全部原样：`这条请求已经处理过了` / `拒绝了状态变更请求` / `KP 调整了 … 的状态` / `忽略了检定请求` / `同意并完成了「$sk」检定`。
`check.request` 三段式分支（含 `rollCheckRequest` + `settleRequest`、不先 `removeAt`）与我上批读到的**逐字相同**；T7-1/T7-2 与我的 W1-3 跨视角探针全绿（p2 收到 `label=侦查` 且 `levelText` 非空的 PUBLIC 骰、请求卡摘净）。

**裁决：出站计划确实净增 1 条 SEAT REQUEST-done + N 条 skip 水位，但这是协议层的正确对齐（老 APP 本就如此），没有任何既有用例被放宽、删除或降级。接受。**

---

## 4. ★ 重点 2：A 行为级 + 秘密口径（自己动手，12 条临时探针全绿，跑完删除）

我写 `test/_qa6_probe_test.dart`（12 条 W1×4 / W2×8），跑完即删，**交付树仍是 1918**。

| 探针 | 结果 |
|---|---|
| **W1-1 同意** | 造 `state.request` → 把 `SendPlan` 按 `to` 分发进 **p1/p2 两个真实 RoomClient**：p1 `state.requests` **空**（上批是 1）；`h.pending` 中该 id **0 条**（上批是 1）；出站**恰好 1 条** `to=='p1' && done==true` 的 REQUEST（上批是 0）；**没有任何 REQUEST-done 发给 `*` 或 p2**，p2 `state.requests` 空、`jsonEncode(p2.state)` 搜不到请求 reason「剧本效果」；公共 LOG 恰好 1 条且文案 `KP 调整了 甲 的状态`，无 verb sys |
| **W1-2 拒绝** | 待办卡消失 + `pending` 清 + 零 DICE + 「拒绝了状态变更请求」提示仍在 |
| **W1-3 check.request 未坏** | p2 视角拿到 `侦查` + 成功等级的 PUBLIC 骰，`collectFeeds` 命中「侦查：」，p1 待办卡消失 |
| **W1-4 秘密口径** | `vis:kp` 且**不带 secret 键**的 DICE 带 `SENTINEL_12`（11 字符，避开 `cleanText(label,20)` 截断假绿）→ 权威 `state.dice` 空 + `host.warnings` 留告警；第三人 `jsonEncode(state)` / **导出文本**零命中；`vis:null` 回放仍按 PUBLIC 落骰；暗骰本人+KP 收得到（前置）、第三人零命中 |

另外**命名过滤逐条重跑**上批四条秘密反证 + T5 组：

```
A4 反向 → +1 All tests passed!   A5 反向 → +1 All tests passed!
R1 · 暗骰 → +2 All tests passed!  KP 暗骰（darkRoll）→ +1 All tests passed!
T5-1 → +1 All tests passed!
```

出站：`grep -rn "toWireJson" lib/` 的 9 处全是注释 + 1 处方法定义，**零调用**；A 新增的是 `RoomEvt.request` 的 **SEAT→本人**，不是 PUBLIC。⇒ K3 未被 A 的出站事件改动所伤。

---

## 5. ★ 重点 3：B 的两个搜索框都真生效（我自己跑真 widget）

两个框传的 Map 形状确实不同，我读原文确认：
- `step_skills.dart:68-73 _matches` 传技能实例（`id`/`key`/`name`/`sub`）；
- `step_skills.dart:1015-1035 _options` 弹窗传 `{'skill': s['id'], 'sub', 'name'}`，**没有 `id` 键**；组技能子类行 `name` 是显示名「格斗（斗殴）」≠ 正式名「格斗」。

| 探针 | 做法与结果 |
|---|---|
| **W2-5 主搜索框（真 widget）** | 真 `StepSkills` 页面 → `skill_search` 输入「魅惑」→ `find.byKey(Key('skill_row_charm'))` **命中 1**；把**结果行**全部 `Text.data` 拼起来，逐个断言 `魅惑 / 讨好 / 恭维 / 迷人 / charm` **零命中**、只有「取悦」；搜索框 `hintText/labelText` 同样零命中 |
| **W2-6 任选弹窗（真 widget）** | 点 `btn_pick_free_<reqId>` 打开 → `free_picker_search` 输入「魅惑」→ `CheckboxListTile` **恰好 1** 且文本是「取悦」；`话术` 零命中、近义词零显示 |
| **W2-3 8 条 special 全部子类行** | 逐条构造 `{'skill':id,'sub':subName,'name':'组名（子类）'}`，**85 个子类行**全部 `skillSynonymIdOf(row)==id` 且能用该 id 的近义词搜到 ⇒ 第二级 `skill` 回退真的被用上 |

**RV4 裁决（工程师说「B3 红、B7 仍绿属合理」）**：我自己复现了 —— 删掉 `skill` 键回退后 **B3 红**（`Expected 'language_other' / Actual null` 来自我的 W2-3 独立探针），**B7 仍绿**。解释**站得住，不是掩盖漏测**：B7 测的是非 special 的 `charm` 行，其 `name` 恰是正式名「取悦」，第三级 name 反查本就该兜住；而「只能靠 `skill` 键」的是 85 个子类行，由 B3（以及我的 W2-3）专门钉住。三级回退的设计本就如此，两级覆盖互补。

---

## 6. ★ 重点 4：覆盖 / 双向 / 不污染 / 不显示 / 零回归

| 项 | 我的独立数据 |
|---|---|
| **54/54 覆盖** | `cocSkills` = **54**、`skillSynonyms` = **54**，逐 id 断言非空、无多余 id；`special:true` **8** 条全有近义词；口语词总数 **191**（不是工程师写的「≈200」估算，实测 191，分布 3~5 个/条） |
| **取悦↔魅惑双向** | 两种 Map 形状下 `skillMatchesKeyword(...,'取悦')` / `(...,'魅惑')` 都 true；`synonymsOf(def/picker).contains('魅惑')` 都 true；`synonymOwnersOf('魅')` / `('惑')` 都**只有 `charm`** |
| **不依赖 desc 偶然文案** | 我把 `charm` 定义的 `desc` 清空后 `skillMatchesKeyword(noDesc,'魅惑')` **仍 true**；RV3 删表里「魅惑」保留 desc → B2/B3/B4/B6/B7 全红 ⇒ 用例守的是表不是 desc |
| **不带出相邻技能** | `fast_talk` / `persuade` / `intimidate` 两种形状搜「魅惑」全 false；54 条全表只 `charm` 命中 |
| **职业解析别名不冲突** | `occupation.dart:96-99` 的 `'魅惑'/'取悦'→charm` 语义未动（mtime 11-08 15:19，早于本批）；`skillMatches(charm,'魅惑')==true` |
| **不显示（结构性）** | 近义词只进 `skill_groups.dart#skillMatchesKeyword` 的局部 `fields`（`...synonymsOf(skill)`），不写回 `name/desc/sub`、不改 `hintText`、不改任何 `Text`；W2-5 结果行 Text.data 逐字零命中、只有「取悦」 |
| **原有能力零回归** | 子串「侦」→侦查 / 去分隔符「spot」→`spot_hidden` / 顺序子序列「图书使」→图书馆使用 / 不存在的词不命中，全部实测通过（W2-4 + B5） |
| **GENERATED 零改动** | `lib/domain/data/skills.dart` mtime **11-10 19:48**、`occupations.dart` **11-08 15:15**、`occupation.dart` **11-08 15:19**，全部早于本批；oracle 夹具零风险 |

---

## 7. ★ 重点 4 附：职业搜索「不接」的裁决 —— **接受，且理由有实测数据**

我读 `occupation.dart:1003-1025 searchTextOfOccupation`：它把每个相关技能的 `skillSearchText(def)` **整段并进职业文本**（`:1020`），而 `skillSearchText` 目前只含 `id/name/category/desc/aliases`。若把 191 个近义词并进去，职业搜索面会整体放大。

**我自己量了误命中面宽**（`searchOccupations` 对 230 条职业实测）：

```
search → 0 条      搜寻 → 2 条     讨好 → 0 条
魅惑 → 138 条     开锁 → 9 条     侦查 → 80 条     取悦 → 138 条
```

⇒ 具体放大例子：搜 `search` 现在 **0 条**，若并入 `spot_hidden` 的近义词「search」，所有要求「侦查」的 **80 条职业**都会命中；搜「讨好」现在 **0 条**，若并入 `charm` 的近义词，约 **138 条**职业会命中。这确实是「为了一个搜索框污染另一个搜索框」。

B8 的双边证据我也独立复跑：`skillMatches(spot,'search')==false`（职业侧没被污染）、`skillMatchesKeyword(spot,'search')==true`（车卡侧生效）、`skillSearchText(spot).contains('search')==false`、`skillMatches(charm,'魅惑')==true`（职业别名语义不动）。

**裁决：不接成立，且是明确结论不是遗漏。** 若产品后来要求职业页也支持口语词，应另做「白名单式收窄 + 误命中对拍」，不要直接把整张 191 词表并进 `searchTextOfOccupation`。（同意工程师 §7 遗留 1 的登记方式。）

---

## 8. 反向证伪表（5 处全部自己动手、`cp`+`sha256`+`cmp -s` 逐字节恢复）

| # | 注入的反向变更 | 变红用例 | 恢复校验 |
|---|---|---|---|
| ① | `consent` 状态分支退回 `list.removeAt(idx)` + `if (!jsTruthy(p['agree']))` | **A1 / A2 / A3 / A4 共 4 红**（`Expected empty / Actual [`、`Expected false / Actual true`、`Expected length 1 / Actual []`）—— 症状正是「待办卡不消失 + pending 残留 + 无 REQUEST-done」 | `6b88c696…` `cmp -s` OK |
| ② | 摘掉 `...synonymsOf(skill),` | **B3 / B4 / B5 / B6 / B7 / B8 共 6 红**（工程师报 5 红 + 1 条，我实测是 B8 也红） | `1259cf6e…` OK |
| ③ | 从表里删「魅惑」，**保留 `desc` 里那句偶然文案** | **B2 / B3 / B4 / B6 / B7 共 5 红** ⇒ 证明用例守的是表不是 desc | `08abfae6…` OK |
| ④ | `skillSynonymIdOf` 的 `skill` 键回退改成空串 | **B3 红**；我自己的 **W2-3 也红**（`Expected 'language_other' / Actual null`）；**B7 仍绿**（见 §5 裁决：name=取悦 被第三级反查兜住，合理） | `08abfae6…` OK |
| ⑤ | 给 `persuade` 塞「魅惑」 | **B4 红**（防污染判据真的在守） | `08abfae6…` OK |

恢复哈希 `6b88c696 / 1259cf6e / 08abfae6` 与工程师 §5 的恢复哈希**完全一致** ⇒ 我拿到的源码就是他测过的那份。恢复后 `flutter test` → `01:10 +1918: All tests passed!`、`dart analyze → No issues found!`。临时探针与 `.qa6_bak/.qa6_tmp` 全部删除。

---

## 9. 账目（1905 + 13 = 1918）

| 项 | 独立计数 | 结果 |
|---|---|---|
| 新文件 `test/p10_t4_synonym_request_done_test.dart` | `grep -cE "^\s+(test\|testWidgets)\("` = **13**；逐条 A1-A5 ×5 / B1-B8 ×8 = **13** | ✅ |
| `for` 动态注册 | 13 个注册点均为静态；循环出现在 **B1/B3/B4 测试函数体内**（B1 逐 id、B3 逐子类行、B4 两种形状遍历），注册数不变 | ✅ |
| 既有测试文件 | `find test -newermt "08:00"` **只有新增文件** ⇒ 既有测试文件零改动，不可能整组删用例；`qa_p10_4_verify_test.dart` 仍 8 条（mtime 02:32） | ✅ |
| 总量 | 1918 − 13 = **1905** = 上批我自己实测的基线 | ✅ **算得平、无既有用例被删** |

我本批 12 条独立探针为临时文件、跑完即删，**交付树仍是 1918**。

---

## 10. 独立出包比对 + AOT

```
[2/3] 校验 AOT 产物
  8782728  lib/arm64-v8a/libapp.so
  9781832  lib/armeabi-v7a/libapp.so
  9044872  lib/x86_64/libapp.so
===== 出包成功 =====
70033836  build/app/outputs/flutter-apk/app-release.apk
fd9b05c9c36f13c20d1a1b2514163ad0ea4e9382a01687da1b92ce22c9d85072 *.../app-release.apk
```

| 项 | 工程师 | 我 | 判定 |
|----|--------|-----|------|
| 字节数 | 70,033,836 | **70,033,836** | ✅（前三批都是 70,001,068，本批变了） |
| SHA256 | `fd9b05c9…5072` | **`fd9b05c9…5072`** | ✅ **逐字节一致** |
| 三 ABI | 8,782,728 / 9,781,832 / 9,044,872 | **全同** | ✅（armeabi-v7a 较上批 +32,768 B） |
| native-assets | true | `flutter config --list` → `enable-native-assets: true` | ✅ |
| build junction / clean | 完好 | `build -> /d/dev/dice-build` 仍在，未 clean | ✅ |

**AOT 实证**（`lib/arm64-v8a/libapp.so`，中文 UTF-16LE）：

```
讨好 1   恭维 2   迷人 2   搜查 4   查资料 1     ← 新表独有字面量
魅惑 134   取悦 4
拒绝了状态变更请求 1   KP 调整了 1   这条请求已经处理过了 1   ← consent 段仍在、未被 tree-shake
```

⚠️ 如实区分：**A 的改动是「换调用」（`list.removeAt` → 已有的 `settleRequest`），不会产生新的专属字面量**；能证明的是「既有 consent 文案仍在 AOT + 包体/SHA 变化 + armeabi-v7a AOT 增大 32,768 B + 行为级 12 条探针与 4 条反向证伪全绿」。B 的新表则有明确的 AOT 字面量证据。

---

## 11. 红线扫描

| 红线 | 实测 |
|---|---|
| 不跑 adb / 模拟器 / 真机 | ✅ 全程未跑；Q1–Q6 只登记未执行 |
| **UI 布局零改动** | ✅ 见 §2，mtime + 哈希双证 |
| `pubspec.yaml` / `tool/qa/*` | ✅ mtime `11-10 21:35` / `11-09 04:31`、`11-11 00:24`，均早于本批 |
| `qa_*_report.md` 未动 | ✅ 全部 mtime ≤ 08:00（`qa_p10_5_report.md` 08:00 是我上批产出，本批未改）；本文件 `qa_p10_6_report.md` 为新建 |
| `test/qa_p10_4_verify_test.dart`(8 条) | ✅ mtime `02:32`，未动 |
| GENERATED 文件 | ✅ `data/skills.dart` / `occupations.dart` / `occupation.dart` 均早于本批 |
| `RoomEvt.values` / `kRoomPolicy` / `jsStr(` | ✅ **27 / 61 / 14**（白名单外 0） |
| `RoomSlot` · `RoomKeys` 不增删 | ✅ `room_keys.dart` mtime 11-09 12:40，未动 |
| `lib/domain` 纯 Dart | ✅ `grep -rn "dart:ui" lib/domain/` = 0；P5 第 07 条 `[OK]` |
| 出站零 `LogRecord.toWireJson()` 调用 | ✅ 9 处全是注释 + 1 处定义 |
| 全量只增不减 | ✅ 1905 → 1918（+13，新文件） |
| 生产源码证伪改动逐字节还原 | ✅ 3 个文件 `cmp -s` 全 OK；临时探针/备份目录已删 |
| 另一工作区 `overview.md` | 当前工作区内未发现该文件；未改动任何工作区外文件 |

---

## 12. 真机清单核对（Q1–Q6 / 指纹 / 回滚行）

| 核对项 | 结果 |
|---|---|
| Q1–Q6 只登记未执行 | ✅ 6 条全是「怎么看 / 通过标准」，无「已通过 / 实测」字样；章节头明确 `本批未跑 adb / 模拟器 / 真机`。Q6 正是用户硬约束「布局没变化」的真机验收项 |
| 头部指纹更新 | ✅ `fd9b05c9c36f13c20d1a1b2514163ad0ea4e9382a01687da1b92ce22c9d85072` / 70,033,836 B / 三 ABI 8,782,728 · 9,781,832 · 9,044,872 |
| 旧 SHA 回滚行 | ✅ `上一版（P10 第 3 期 B）… 8e2bf6e4…536d0c / 70,001,068 B` 完整保留 |
| 技术债 15 | ✅ 已改为「★ P10 第 4 期已处理」（我上批登记的遗留） |
| 我的精度订正（不删条目） | ① 自动化表/APK 表里仍标「P10 第 3 期 B，本次交付」的两行改为**历史**；② 新增第 4 期 APK 指纹行（含 AOT 证据）与 1918 行的 QA 独立复跑证据；③ 头部补第 4 期 QA 独立出包 + 布局零改动举证行 |

---

## 13. 遗留 / 下一批建议（如实报，均不阻断本批）

1. **职业搜索未接入近义词表**：明确结论（§2.6）不是遗漏；若产品后来要求，需另做「白名单式收窄 + 误命中对拍」，别直接并整张 191 词表。我的实测数据（§7）可作为对拍基线。
2. **组技能子类名没有各自独立的近义词**：B3/W2-3 覆盖的是「靠 `skill` 键命中组名近义词」；「搜『手枪』命中射击子类」属下一批需求（工程师 §7 已如实登记）。
3. **`settleRequest` 清 `pending` 按 `x['id']==id` 匹配**：本批 `state.request` 记账 id 与请求 id 同源（我的 W1-1/W1-2 实测 pending 归零），当前全库无 id 形状复用；将来若复用需收紧（工程师 §7 登记为设计留意项，我复核认同）。
4. **出站计划数变化**（+1 条 SEAT REQUEST-done + N 条 skip）是协议行为变化而非 bug；若有外部工具按计划条数做监控需知会（工程师 §7 已登记）。
5. `dart analyze` 首轮两条告警都在**新增测试文件自身**的 import，已真实修复，不是靠 lint 放宽（§1）。
6. 未跑 adb / 模拟器 / 真机（按约定由用户统一测）。

---

## 14. 智能路由判定

**Send To: NoOne（PASS）**。

- 无失败用例、无生产 bug、无覆盖被削弱；用户硬约束（UI 布局零改动）有独立 mtime + 哈希双证。
- A 的遗留按我上批原判据**真还上了**：`客户端剩余待办卡=1 / REQUEST-done=false / pending=1` → `卡片消失 / REQUEST-done=true / pending=0`，且计划数变更没有放宽任何既有用例。
- B 的两个真 widget 搜索框、54/54 覆盖、双向可搜、不污染、不显示、职业搜索不接的结论都有独立数据支撑；RV4「B7 仍绿」经我复现 + 独立 W2-3 反证，判定**合理而非掩盖漏测**。
- 5 处反向证伪全部逐字节恢复、恢复后全量 1918 全绿；独立出包与工程师逐字节一致。
- §13 六条遗留均属「明确结论 / 下一批需求 / 协议行为知会」，**无一条需要本批返工**。
