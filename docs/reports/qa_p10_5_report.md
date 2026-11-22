# QA 独立复核报告 · P10 第 3 期 B 批

- 复核人：严过关（QA / software-qa-engineer-4）
- 工程：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
- 被复核交付：`_p10_transport5.txt`（332 行，工程师 寇豆码 / software-engineer-5）
- 上批基线（我自己跑的）：**1879** 全绿 / APK `531e80ac…b07a59` / 70,001,068 B
- 复核原则：**所有数字自己跑出来**；上批 `qa_p10_4_report.md` §10 的 4 条技术债是我提的，本批按**原判据**验，不因被采纳而放水。

---

## 0. 一句话结论

**PASS / 智能路由：Send To: NoOne**（本批无需返工）。

- 五项自检全部复现，**串行是工程师没跑、我补跑的**：全量 **1905** 全绿、`--concurrency=1` **1905** 全绿、`dart analyze` 零、P4 **13/13**、P5 **14/14**。
- **独立出包与工程师逐字节一致**：70,001,068 B / `8e2bf6e4…536d0c` / 三 ABI 全同。
- 两处既有断言改动**都不是「为绿放宽」**：一处是「约定 → 机械保证」的升级，一处是把上批我判的「前提陈旧假绿」改成**正向真实覆盖**，两处我都做了反向证伪（改回旧实现即变红）。
- consent 三段式接线**行为级成立**（跨会话 PUBLIC 骰 + 权威技能值 + 拒绝不掷骰 + 摘卡），秘密口径四条反证全绿、`vis:kp` 的 DICE 哨兵已被 reduce 闸门堵死。
- **两条下一批登记项**（不阻断本批）：① consent 对**非 check.request 状态变更请求**不发 REQUEST-done（我用探针实测「卡片不消失」且 `pending` 残留）；② `roomOrderedContentSlots` 接线后仍缺一条 **widget 级方块顺序断言**（现在是源码文本靶子 + 纯函数）。

---

## 1. 五项自检（原始输出，全部自己跑）

| # | 项 | 命令 | 我的实测 | 与工程师报告 |
|---|----|------|---------|-------------|
| 1 | 全量（默认并发） | `flutter test` | `01:13 +1905: All tests passed!` | ✅ 1905 复现 |
| 2 | **串行**（工程师本批未跑，我补） | `flutter test --concurrency=1` | `04:59 +1905: All tests passed!` | ✅ **无顺序依赖** |
| 3 | 静态分析 | `dart analyze` | `Analyzing dice-realm... No issues found!` | ✅ 零 |
| 4 | P4 门禁 | `node tool/qa/qa_p4_gate.js` | `==== 合计 13 条，失败 0 条 ====` / `P4_GATE IS_PASS: YES` | ✅ 13/13 |
| 5 | P5 UI 门禁 | `node tool/qa/qa_p5_ui.js` | `==== 合计 14 条，失败 0 条 ====` / `P5_UI_GATE IS_PASS: YES` | ✅ 14/14 |

`jsStr(` 实测 **14 处**（`room_session_local×3 / room_session_remote×3 / room_text×1 / gp_combat_list×5 / gp_scene_check_pl×1 / gp_status×1`，白名单外 0）；P5 的 `lib/domain 纯 Dart（零 Flutter / IO / UI）` 亦为 `[OK]`，我另用 `grep -rn "dart:ui" lib/domain/` 得 **0**（连注释里字面量都没有，上批工程师在这里被打过两次）。

恢复全部证伪改动后我又跑了一遍：`01:15 +1905: All tests passed!` + `dart analyze → No issues found!`。

### 1.1 独立出包（只走 `bash tool/build_apk.sh`）

```
[2/3] 校验 AOT 产物
  8782728  lib/arm64-v8a/libapp.so
  9749064  lib/armeabi-v7a/libapp.so
  9044872  lib/x86_64/libapp.so
===== 出包成功 =====
70001068  build/app/outputs/flutter-apk/app-release.apk
8e2bf6e4c78aabf94d531c7a5d5adaf6eded85bd05688e2532ca039784536d0c *.../app-release.apk
```

| 项 | 工程师 | 我 | 判定 |
|----|--------|-----|------|
| 字节数 | 70,001,068 | **70,001,068** | ✅ |
| SHA256 | `8e2bf6e4…536d0c` | **`8e2bf6e4…536d0c`** | ✅ **逐字节一致**（与 A 批一样，字节数三批巧合相同、SHA 不同，以 SHA 为准） |
| 三 ABI | 8,782,728 / 9,749,064 / 9,044,872 | **全同** | ✅ |
| native-assets | true | `flutter config --list` → `enable-native-assets: true` | ✅ |
| build junction / clean | 完好 | `build -> /d/dev/dice-build` 仍在，未 clean | ✅ |

**AOT 实证**（`lib/arm64-v8a/libapp.so` 8,782,728 B，中文按 UTF-16LE）：

```
同意并完成了                utf-16le=1   ← consent 同意分支
忽略了检定请求              utf-16le=1   ← consent 拒绝分支
非 PUBLIC 的 DICE 事件已丢弃 utf-16le=1   ← reduce 机械闸门告警
潜在疯狂                    utf-16le=8
侦查                        utf-16le=67
```

⇒ 本批新代码确实进了 AOT。⚠️ **「视口最小高度判据」是写在 `test/room_ui_layout_test.dart` 里的测试断言，按定义不会进 release APK**；进包的是它保护的生产接线（`room_game_page.dart#_foldedContent`），这点如实区分，不把测试断言当 AOT 证据。

---

## 2. 账目（1879 + 26 = 1905）

| 项 | 独立计数 | 结果 |
|---|---|---|
| 新文件 `test/p10_t3b_rule_diff_test.dart` | `grep -cE "^\s+(test|testWidgets)\("` = **26**；逐条列出 T1×5 / T2×1 / T3×3 / T4×6 / T5×3 / T6×2 / T7×4 / T8×2 = **26** | ✅ 与分组账相符 |
| `for` 动态注册 | 全文 26 个注册点均为静态；循环只出现在**测试函数体内**（如 T2-1 的 7 分支表驱动） | ✅ 文件内注册数 == 运行数 |
| 被改 3 个测试文件 | `room_intent_dark_dice_privacy_test` **10 组 / 3 group**、`room_ui_entry_test` **22 组 / 10 group**（与上批我数的 22 一致）、`room_ui_layout_test` **17 组 / 5 group**（与上批清单 12→17 一致） | ✅ 无整组消失 |
| 不该动的文件 | `p10_t3_broadcast_potential_png_test.dart` **18**（mtime 02:13）、`qa_p10_4_verify_test.dart` **8**（02:32）、`p10_t2_avatar_test.dart` **19**（02:13）—— 都早于 B 批 07:xx | ✅ 一字未动 |
| 总量 | 1905 − 26 = **1879** = 上批我自己实测的基线 | ✅ **算得平、无既有用例被删** |

我本批的 9 条独立探针写在**临时文件** `test/_qa5_probe_test.dart`，跑完即删，**不入库** ⇒ 交付树仍是 1905，不会被误记成「工程师多写了 9 条」。

---

## 3. ★★ 重点 1：两处既有断言改动裁决

### 3.1 `room_intent_dark_dice_privacy_test.dart:314-338` ⑧ —— **不是放宽，是升级**

改前：`expect(block.contains('vis'), isFalse)` —— 用「DICE 分支里不许出现 `vis`」来守「方案 ①（reduce 不看 vis + 暗骰不 emit DICE）未被采用」这条**约定**。
改后：四条正向静态判据（`evt.vis != null` / `evt.vis != RoomVis.public` / `reduceGateWarnings.add` / `break;`）+ 第五条 `dice.add(...)`（PUBLIC 骰点照原样落）。

| 核查项 | 结论 |
|---|---|
| ① 注册数 / 整组 | 文件仍 **10 组 / 3 group**，⑧ 用例仍在（只是改名改判据），无删除 |
| ② 原意「SEAT/非 PUBLIC 骰点绝不进公共 `state.dice`」 | **从约定升级为机械保证**：`reduceRoomState` 的 DICE 分支现在显式 `if (evt.vis != null && evt.vis != RoomVis.public) { 记 warning; break; }`，`apply()` 把 `reduceGateWarnings` 汇入 `host.warnings`。行为级反证由 T5-1/T5-2/T5-3 承担；⑧ 只钉源码结构，防有人把闸门删回「只看约定」 |
| ③ 摘掉闸门是否⑧ + T5-1 **同时**红 | **我自己动手验了**：删掉整段 `if (...) {…break;}` 后跑两个文件 → `⑧ 静态：…` **红**（`Expected: true / Actual: <false>`）+ `T5-1 非 PUBLIC 的 DICE 被丢弃并记 warning` **红**（`Expected: empty / Actual: [`），共 2 红，其余全绿。逐字节恢复 `533d7166…` |

**裁决：接受，覆盖不降反升。** 唯一保留意见：⑧ 本身仍是**源码文本靶子**（不是行为），真正的行为保证是 T5 组；两者配套才完整，工程师在用例注释里写清了分工。另：`reduceGateWarnings` 是模块级全局可变表，我核过所有 `reduceRoomState(` 调用点只有 2 个（host `apply()` 会立即清空、client `receive()` 恒传 `vis:null` 不触发），串行跑 1905 也全绿 ⇒ 无跨用例串味、无顺序依赖。

### 3.2 `room_ui_entry_test.dart:589-600` —— **按新口径真实覆盖，覆盖没改没**

上批我判它「前提陈旧的假绿、接受 + 下一批改文案」。本批改法：

```dart
final expectSheet = _stripVolatile(cardToRoomSheet(card))
  ..['avatar'] = autoPng;                       // autoPng = 'data:image/png;base64,AAAB'
expect(_stripVolatile(asMap(payload['sheet'])), equals(expectSheet));   // 逐字段仍在
expect(asMap(payload['sheet'])['avatar'], autoPng,
    reason: '没上传头像也应带自动头像 PNG（广播判据只收 png/jpeg/webp）');
```

- 该用例在 `setUp(_stubAutoAvatarPng)`（全局返回空串）之外**局部覆盖**成返回确定 PNG，于是断言变成**正向**「载荷真的带上自动头像 PNG」，而不是「载荷里不许有 avatar 键」。
- 逐字段 `equals(expectSheet)` 与 dex / skills / HP / SAN 抽查**一字未删**；`_stripVolatile` 只去 `at`。
- **反向证伪（我自己做）**：把 `card_sheet_payload.dart` 的自动头像那一步 `if (thumb.isEmpty)` 改成 `if (false && thumb.isEmpty)` → `room_ui_entry_test` 的「★ 选中一张卡 → 发 INTENT.CHAR，载荷 sheet 与搬运函数逐字段一致」**立即红**（`Expected: { … avatar: AAAB } / Actual: { … 无 avatar }`）。⇒ 新断言真的在守新行为，不是恒真。恢复 `ebb9fcfe…`。

**裁决：接受。** 上批那处假绿已被真实覆盖替换。

### 3.3 降级路径仍被钉住（核过，未被动）

| 守卫 | 状态 |
|---|---|
| `T6-2 两条生成器都拿不到东西 → 删 avatar 键` | 新增，仍是 `containsKey('avatar') isFalse` + `name` 非空 |
| `p10_t2_avatar_test` E1 / E3 | mtime 02:13，**未动**（19 组） |
| `p10_t3_broadcast_potential_png_test` C4 / C5 / C6 / C8 | mtime 02:13，**未动**（18 组） |
| 我上批的 `qa_p10_4_verify_test.dart` R4 / R5 | mtime 02:32，**未动**（8 组） |

⇒ 正向（PNG 真生成 / 跨会话渲染成 Image）与降级（生成失败删键）**两侧都有人守**。

---

## 4. ★ 重点 2：consent → check.request 三段式（行为级，不采信报告）

### 4.1 两边原文对拍

老 APP `core/room-model.js:1546-1569`（我读的原文）：
`req.op === 'check.request'` → 同意 `out.concat(_rollCheckRequest(seat, req))` + `_settleRequest(seat, req.id, true, '同意并完成了「sk」检定')`；拒绝 `_settleRequest(..., false, '忽略了检定请求')`。
`:3106-3131 _rollCheckRequest`：目标值优先级 `① _skillBaseOf(mem, pl.skill) → ② pl.base → ③ 100`，难度取载荷，`diceRoll` → PUBLIC 全员；注释明写这是 v2.1.0 修的「要求检定点了同意没反应」。
`:3138-3151 _settleRequest`：`list.splice` + `pending.filter` + `emit(EVT.REQUEST, {done:true}, VIS.SEAT, seat)` +（verb 非空才）公共 sys。

新 `room_model_host_intent.dart:340-365`：同意 `rollCheckRequest(seat, req)` + `settleRequest(..., true, '同意并完成了「$sk」检定')`；拒绝 `settleRequest(..., false, '忽略了检定请求')`；**没有**先 `list.removeAt(idx)`。新 `settleRequest`（`combat.dart:1002-1024`）与老 `_settleRequest` 逐项一致（摘卡 + 清 pending + REQUEST-done SEAT + 可选 verb）。
⇒ **三段式逐项对齐，接线正确。**

### 4.2 我自己的 9 条临时探针（全部跑通，跑完删）

| 探针 | 做法 | 结果 |
|---|---|---|
| V1-1 跨视角 | KP 推「侦查」→ p1 同意 → `SendPlan` 按 `to` 分发进 p1/p2 两个真实 `RoomClient` | **p2** 的 `state.dice` 有 1 行：`seat=p1 / label=侦查 / levelText 非空`；`collectFeeds(p2.state)` 命中 `FeedKind.dice + nickname=甲 + text.startsWith('侦查：') + '1D100 →'`；p1 客户端 `state.requests` 空（REQUEST-done 生效） |
| V1-2 客户端伪造 | 同意时回传 `skill:'伪造技能', base:1, difficulty:'EXTREME', label:'伪造标签'` | 与基线骰结果签名 `label\|total\|level\|levelText` **完全相同** ⇒ consent 只读 `id/agree`，客户端字段无效 |
| V1-3 权威目标值 | 把权威端**存下来的请求载荷** `payload['base']` 改成 5（模拟载荷被污染） | `rollCheckRequest` 仍从角色卡重算 `侦查=60`，骰等级与基线一致 ⇒ 不信载荷 base |
| V1-4 拒绝 | `agree:false` | 零 DICE；权威端 + 玩家端待办卡都空 |
| V2-1/2/3 | reduce 闸门与秘密口径（见 §5） | 全绿 |
| V3-1 | 遗留登记探针（见 §8） | 输出实证 |
| V4-1 | `aSeat:''` 的 `check.opposed` | 3 条计划、**零 CHECK 事件** ⇒ D14 `targets` 空串差异在现有意图入口确实不可达 |

### 4.3 反向证伪

把 `if (req['op'] == 'check.request')` 改成 `if (req['op'] == '__never__')`：
**T7-1 红**（`Expected: an object with length of <1> / Actual: []`，即「点了同意没反应、一颗骰都没有」）；我的 V1-1 同样 `Expected length 1 / Actual []`、V1-2 `'NO_DICE'`、V1-3 空等级、V1-4 待办卡不摘。逐字节恢复 `bb1109a5…`。

### 4.4 「接线而非删掉」是否成立 —— **成立**

老 APP 有 `consent → _rollCheckRequest` 的真实调用链且是为修用户报障加的；删掉 `rollCheckRequest` 会把「死代码」换成「功能缺失」，与「按老 APP 抹平差异」相反。本批接线后 `rollCheckRequest` 从 0 调用点变成 1 个（`host_intent.dart`），我核过全库调用点，无误。

---

## 5. ★ 重点 3：reduce 闸门改完，秘密口径没被误伤

### 5.1 四条秘密口径独立重跑（命名过滤，逐条）

```
--plain-name "A4 反向"              → +1: All tests passed!
--plain-name "A5 反向"              → +1: All tests passed!
--plain-name "R1 · 暗骰"            → +2: All tests passed!   （我上批 R1 + R1b）
--plain-name "KP 暗骰（darkRoll）"  → +1: All tests passed!
```
并跑两个文件全量 → `+26: All tests passed!`。

### 5.2 上批 §3b 那处机械缺口现在被堵上（我自己的探针）

`emit(RoomEvt.dice, {label:'SENTINEL_12' /* 11 字符，< cleanText(label,20) */, total:42, levelText:'常规成功'}, vis: RoomVis.kp)`，**payload 不带 `secret` 键**（绕开 `kSecretKeys` scrub）：

- 权威端 `state['dice']` 空；`host.warnings` 多一条 `t==dice && reason.contains('非 PUBLIC')`；
- 用 `syncFor('p2')` 喂给第三人 `RoomClient`：**整份 `jsonEncode(state)` 零命中**、`collectFeeds` 零命中、`buildRoomHistoryExportText` 导出文本零命中；
- `vis: RoomVis.seat, to:'p1'` 同样丢弃；
- **`vis == null`（客户端回放）仍按 PUBLIC 落骰**（`reduceRoomState` 直调后 `state.dice` 长度 1），没被误伤；
- 暗骰 `secret:true` 走 `RoomEvt.private_`：本人 + KP 都搜得到哨兵（探针前置）、第三人 `jsonEncode` 零命中 + `state.dice` 空。
- 出站：`grep -rn "toWireJson" lib/` 的 9 处全是**注释 + 一处方法定义**，零调用；全库 `reduceRoomState(` 仍恰好 2 个调用点（P4 门禁约束），`client.receive()` 恒传 `vis:null`。

⇒ **A4/A5/R1/R1b 四条 + 我新造的 `vis:kp` 哨兵，全绿。**

---

## 6. ★ 重点 4：3 条「真规则差异」逐条对拍（读两边原文）

### 6.1 D07 潜在疯狂 + 单次 ≥5 SAN

老 APP `room-model.js:5198`：`if (loss >= 5 && !isFaded)`，注释（`:5193-5197`）明写「FADED 态损失 SAN **只走 ④ 复发**，避免一次性获得 2 个症并叠加临时疯狂标签」。`isFaded` = `MENTAL_INDEF_FADED` = 老名「不定疯狂（症状消失）」= 新名「潜在疯狂」。
新 `sheet.dart:1211` `isPotential = mental_state.isPotentialMadness(mentalNow)`；`:1246` `if (loss >= 5 && !isPotential)`。
**反向证伪**：改回 `if (loss >= 5)` → **T3-3 红**（`Expected: false / Actual: <true>`，即重新叠加临时疯狂路径）。恢复 `323ab8b9…`。✅ 真按老 APP 改了，且未动 ④ 复发分支。

### 6.2 D14 载荷形状（判定核心不许动）

- 我上批判定的**判定核心** `room_rules_opposed.dart` / `room_rules.dart` mtime **2026-11-08 20:18 / 20:25**，早于本批 ⇒ **一字未动**（level → fightback/dodge 同级短路 → value → 重掷≤10 → fallback）。
- 真改的两处：① `combat.dart:1305` `targets` 从 `.where((x) => x != null)` 改 `.where(jsTruthy)`（对齐老 `:5888 .filter(Boolean)`）；② `emitOpposedCheck` 秘密卡 `summary || '（秘密对抗）'` / `at || now()` 从 Dart `??` 改 `jsTruthy(...)`（对齐 JS falsy，空串/0 也兜底）。我逐行核过两处实现与老 APP `:5811-5824` 一致。
- T1-1（完整键集合 + 全员广播）、T1-2（秘密侧零 CHECK PUBLIC）、T1-3（**p1/p2 两个真实 RoomClient** 的 `opp` 恰好 9 键 `a/b/winner/tie/reaction/decidedBy/fallback/rounds/damage` 且 `redacted=false`）、T1-5（空串 summary → `（秘密对抗）`、`at=0` → 回落当前时钟）全部在全量里绿。
- 工程师报告 §3.3 说「另两处载荷 `:1693`/`:2348` 本来就是 `!= null && != ''`」——我核到 `:1705` 确实是 `!= null && != ''`，但 **`:2360` 是 `targets: [seat]` 完全没有过滤**（单元素，seat 来自意图入参，实践中非空）。这是**表述精度小瑕疵**，不影响结论，但下一批按图施工时别被带偏。

### 6.3 T1-4「静态形状靶子 + 正常入参正例」是不是假绿 —— **可接受，但要写明边界**

我用自己的探针 V4-1 独立证实「不可达」：`aSeat:''` → `resolveActorSkill` 返回 `ok:false / reason:'未指定对抗单位'` → `checkOpposed` 提前 return（`甲方无效`），**根本走不到 `targets` 装配**（实测 3 条计划、零 CHECK 事件）。
⇒ T1-4 用**源码文本靶子**（`block.contains('.where(jsTruthy)')`）+ 正常入参正例（`'p1','p2'`）来钉形状，是**诚实登记**而非「为绿放宽」：行为级差异在这条入口不存在，硬造行为用例只能绕过 `resolveActorSkill`、反而测的不是生产路径。
**裁决：接受**。但必须记住它**不是行为级证明**；若要升级，下一批应把「载荷形状装配」提成可单测的纯函数，再直接喂空串做对拍（P3）。

---

## 7. ★ 重点 5：5 条技术债逐条验

| 技术债 | 我的独立验证 | 判定 |
|---|---|---|
| ① `card_sheet_payload.dart:143` 改传原始 avatar | T6-1 用「卡 avatar 已是 `data:image/png;base64,AAAB`」→ 缩略链路收到**原始值**、载荷 `avatar == thumb`。**我自己反向**：把该行改回 `avatarThumbEncoder(localAvatarRel(card.raw['avatar']))` → **T6-1 红**（`test\p10_t3b_rule_diff_test.dart:628`）。恢复 `ebb9fcfe…` | ✅ 真修 |
| ② `roomOrderedContentSlots` **接线**不是删 | `grep -rn "roomOrderedContentSlots(" lib/` = 定义 1 处 + **`room_game_page.dart:518 final squares = roomOrderedContentSlots(roomFoldedSlots(slotList, role), spec)`** 真实渲染调用 1 处；T8-1 同时断言源码接线 + 折叠档 `first == gpPriv` / 多列档不打乱。既有 3 条纯函数断言（`room_ui_layout_test.dart:195/204/209`）现在通过这条调用链保护真实界面 | ✅ 真接线。⚠️ 仍**没有 widget 级方块顺序断言**（T8-1 是源码文本靶子 + 纯函数），见 §10 登记 |
| ③ 视口判据 `viewport.height > 120` | **强证伪**：把生产 `Expanded(child:_zoomHost(...))` 换成 `SizedBox(height:25, …)`（用固定 `height`，不是上批踩过的「`maxHeight` 不是固定高度」坑）→ `room_ui_layout_test` 里 `gpToolbar / gpTopbar 的祖先链上没有 Transform` **红**：`Expected: a value greater than <120> / Actual: <25.0>`；**再把断言临时退回 `greaterThan(0)`，同样 25dp 立刻 `+1: All tests passed!`** ⇒ 正是这条新断言堵住了「压成一条缝也全绿」。两处逐字节恢复（`bbd911a7…` / `ad61fb47…`） | ✅ 真堵住 |
| ④ `check.push` 结论 | 我独立 `grep -rn "check\.push"` 老 APP 全库：只有 `room-model.js:222` POLICY 登记、`room-model.js:1810` 是 **`scene.check.push`**（另一条引擎分支）、`room-panels.js:5857 / :4572` 全是 `scene.check.push`；`applyAction :1795-1830` 整条链**无 `check.push` 处理器** ⇒ 「允许但无行为的历史占位」**成立**。新工程 `combat.dart:93` 接 `checkRequest` 是无调用方增强，T7-4 钉住同行为 | ✅ 结论站得住 |
| ⑤ `rollCheckRequest` 接线不删 | 见 §4.4：老 APP 有真实调用链，接线后从 0 → 1 个调用点 | ✅ 成立 |

---

## 8. ★ 重点 6：工程师新登记的遗留 —— 属实，但**不阻断本批**

### 8.1 两边原文

老 `:1569`（状态变更请求）：`out = out.concat(this._settleRequest(seat, req.id, !!p.agree, null));` → `_settleRequest`（`:3138-3151`）会 `list.splice` + `pending.filter` + **`emit(EVT.REQUEST, {done:true}, VIS.SEAT, seat)`**。
新 `consent` 的非 `check.request` 分支：`list.removeAt(idx)` → 拒绝只 `sys('…拒绝了…')`；同意 `syncMembers()` + 公共 LOG，**没有 REQUEST-done、没有清 `pending`**。
客户端 `state['requests']` 只由 `RoomEvt.request(self && done)` 裁剪（`room_model_reduce.dart:313`），`syncMembers()` 动的是 `members`，碰不到 `requests`。

### 8.2 我的行为级探针（V3-1，实测输出）

```
QA5_V3: 客户端剩余待办卡=1, 发了 REQUEST-done=false, 权威端待办=0, pending=1
```

⇒ **属实且比工程师描述更具体**：① 玩家端点同意后待办卡**不消失**；② 权威端 `pending` 还残留一条（`state.request` 记账）没清，工程师只提了卡片。该入口在两边 UI 都真实存在（新 `sheet_kp_directives.dart:76 '请求修改状态'`；老 `room-panels.js:5857`），不是纸面路径。

### 8.3 严重性裁决：**P2，登记下一批优先修，不判本批返工**

理由：
1. **不是本批引入的回归**：`consent` 的状态变更分支本批一字未动；本批只新增了 `check.request` 分支。全量 1905 全绿、无失败用例，没有「本批把什么弄坏了」的证据可返工。
2. **本批施工范围明确**：team-lead 派工只要求处理 `check.request` 分支；顺手改状态分支会**改变出站计划数**（多一条 SEAT REQUEST-done），牵动既有计划数断言与 `syncMembers` 顺序，属计划外扩散。
3. **可恢复**：权威端 `requestsBySeat` 已摘空，玩家下次全量 sync（`_requestsView` 读权威表）卡片就会消失；症状是「本次会话内不消失」，不是状态永久错乱。
4. 但**必须升级为下一批 P1**：用户可见、且是「按老 APP 抹平差异」清单里明确残留的一条，不该无限期挂着。

**给下一批的具体修法**：把 `list.removeAt(idx)` 换成走 `settleRequest(seat, id, agree, null)` 的等价收尾（它已实现「摘卡 + 清 pending + REQUEST-done SEAT」，verb 传 null 不会多发公共 sys；现有同意/拒绝的公共 LOG 保持）。必须同时补两条用例：① 同意状态请求 → 玩家端 `state.requests` 为空 + 有 REQUEST-done；② `host.pending` 不再残留 `state.request` 记账。

---

## 9. 反向证伪表（全部自己动手，逐字节恢复）

| # | 注入的反向变更 | 变红的用例 / 症状 | 恢复校验 |
|---|---|---|---|
| ① | 摘掉 `reduce` 的 DICE 闸门整段 | **⑧ 静态守卫**（`Expected true / Actual false`）+ **T5-1**（`Expected empty / Actual [`）**共 2 红** | `533d7166…` `cmp -s` OK |
| ② | `consent` 分支判据 → `'__never__'` | **T7-1**（`Expected length 1 / Actual []` =「点了同意没反应」）+ 我的 V1-1/2/3/4 共 5 红 | `bb1109a5…` OK |
| ③ | 去掉 `&& !isPotential` | **T3-3**（`Expected false / Actual true` = 双路径叠加） | `323ab8b9…` OK |
| ④ | 生产内容区固定 `height:25`（`SizedBox`，真钉死） | `gpToolbar / gpTopbar 的祖先链上没有 Transform` → **`Expected >120 / Actual 25.0`**；把断言临时退回 `>0` 后同样 25dp **全绿** ⇒ 新判据是真钉子 | `bbd911a7…` / `ad61fb47…` 两处 OK |
| ⑤ | 摘掉 `card_sheet_payload` 自动头像 PNG 一步 | `room_ui_entry_test` 绑卡载荷断言红（`Expected {… avatar} / Actual {… 无 avatar}`）⇒ 证明改后的正向断言不是恒真 | `ebb9fcfe…` OK |
| ⑥ | `:143` 改回 `localAvatarRel(...)` | **T6-1 红** | `ebb9fcfe…` OK |

恢复后复跑：全量 `01:15 +1905: All tests passed!`、`dart analyze → No issues found!`。6 个备份哈希与工程师 §4 报告里的恢复哈希（`533d7166 / bb1109a5 / 323ab8b9 / bbd911a7 / ebb9fcfe`）**完全一致** ⇒ 我拿到的源码就是他测过的那份，没有「报告与代码不同版」的风险。

---

## 10. 红线扫描

| 红线 | 实测 |
|---|---|
| 不跑 adb / 模拟器 / 真机 | ✅ 全程未跑；M1–M6 清单**只登记未执行**（章节内全是「怎么看 / 通过标准」，无任何实测结果） |
| 只走 `bash tool/build_apk.sh` 出包 | ✅ 唯一出包入口 |
| `build` junction / 不 `flutter clean` | ✅ `build -> /d/dev/dice-build` 完好 |
| `pubspec.yaml` / `tool/qa/*` | ✅ mtime `2026-11-10 21:35` / `2026-11-09 04:31`、`2026-11-11 00:24`，均早于 B 批 |
| `lib/domain/**` 零 `package:flutter` / `dart:io` / `dart:ui`（连注释） | ✅ `grep -rn "dart:ui" lib/domain/` = **0**；P5 第 07 条 `[OK]` |
| `RoomEvt.values` / `kRoomPolicy` / `jsStr(` | ✅ **27 / 61 / 14**（白名单外 0） |
| `RoomSlot` / `RoomKeys` 不增删 | ✅ `lib/ui/room/room_keys.dart` mtime `2026-11-09 12:40`，未动 |
| `qa_*_report.md` 未动 | ✅ `qa_p10_4_report.md` mtime `02:39` 未动（本文件 `qa_p10_5_report.md` 是新建） |
| `test/qa_p10_4_verify_test.dart` 8 条未动 | ✅ mtime `02:32`、8 组 |
| 出站只 `SendPlan.toJson()`、零 `LogRecord.toWireJson()` 调用 | ✅ 全库 9 处全是注释 + 1 处方法定义，零调用 |
| 全量只增不减 | ✅ 1879 → 1905（+26，新文件），无既有用例被删 |
| 另一工作区 `overview.md` | 当前工作区内未发现该文件；我未改动任何工作区外文件 |
| 生产源码 | ✅ 6 处证伪改动全部 `cp` + `sha256` + `cmp -s` 逐字节还原；临时探针文件与 `.qa5_bak/.qa5_tmp` 全部删除 |

---

## 11. 真机清单核对（M1–M6 / 指纹 / 回滚行）

| 核对项 | 结果 |
|---|---|
| M1–M6 是否「只登记未执行」 | ✅ 6 条全是「怎么看 / 通过标准」，无「已通过 / 实测」字样；章节头明确 `本批未跑 adb / 模拟器 / 真机` |
| 头部指纹是否更新 | ✅ `8e2bf6e4c78aabf94d531c7a5d5adaf6eded85bd05688e2532ca039784536d0c`（与我独立出包逐字节一致） |
| 旧 SHA 保留作回滚行 | ✅ `上上一版（P10 第 3 期 A）… 531e80ac…b07a59` 完整保留 |
| 我发现的清单精度问题（已订正） | ① 技术债 9/10/11/12/13 仍写「下一批改 / 建议下一批」，但 B 批已处理 ⇒ 我逐条加「✅ P10-3B 已处理」标注，避免下批重复施工；② 自动化表里 A 批的 APK 行仍标「本次交付」⇒ 改为历史并补 B 批行；③ 头部补一条 B 批 QA 独立出包 + 串行复跑记录；④ 新增技术债 15（consent 状态请求分叉，附我的探针实证）与 16（折叠档顺序缺 widget 级断言） |

---

## 12. 遗留 / 下一批建议（按优先级）

1. **P1** consent 对非 `check.request` 状态请求不发 REQUEST-done（§8），含 `pending` 残留；修法与用例已给。
2. **P2** D14 `targets` 空串差异只有静态形状靶子（T1-4），可把载荷装配提成纯函数后做行为级对拍；顺带订正报告 §3.3「另两处本来就是 `!= null && != ''`」的表述（`:2360` 是 `[seat]` 无过滤）。
3. **P3** 折叠档方块顺序**缺 widget 级渲染断言**：现在 `room_ui_layout_test` 的 3 条是纯函数、T8-1 是源码文本靶子，靠「同一函数被 `_foldedContent` 调用」间接保护真实界面。建议补一条 360×640 折叠档真渲染后按 `RoomKeys.keyOfSlot` 读方块顺序的用例。
4. **P3** `reduceGateWarnings` 是模块级全局可变表（当前只有 host `apply()` 会清空、client 恒 `vis:null` 不触发，串行 1905 全绿 ⇒ 无实际问题），但属于「靠调用点自觉」的轻微设计味道；若将来新增第 3 个 `reduceRoomState` 调用点需同步清理。
5. **P3** D11（精神分析）/ D04 部分分支只有间接靶子，未做全参数笛卡尔积对拍（工程师 §7 已如实登记）。
6. 自动头像 PNG 精确字符数仍只在测试里断言区间（>500 且 ≤20000）；C4 用真编码器，量级远低于上限，无需降档。
7. 未跑 adb / 模拟器 / 真机（按约定由用户统一测）。

---

## 13. 智能路由判定

**Send To: NoOne（PASS）**。
- 无失败用例、无生产 bug、无覆盖被削弱；两处既有断言改动均经我独立反向证伪确认「真的在守」。
- §8 的 consent 状态请求分叉是**既有差异、本批未动、范围外**，不属于返工项 → **登记下一批 P1**，并在真机清单技术债 15 写明根因与自愈条件，供用户真机踩到时对照。
- 若主理人仍决定本批顺手修 §8，请把它作为**独立小改 + 2 条新用例**派回工程师，不要混进本批复核结论。
