# P10 第 1 期 · QA 独立回归复核报告

- 复核人：QA 严过关（Edward / software-qa-engineer）
- 复核时间：2026-11-11 00:10 ~ 00:30
- 工程：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`（`$P`），版本 `2.17.0+83`
- 复核方式：**自己跑、自己怀疑、自己证伪**。不采信工程师报告里的任何截图/结论；凡「已修」都要么有断言兜底，要么我亲手把它改坏一次看会不会红。
- 纪律：全程未跑 adb / 模拟器 / 真机；未删 `build` junction、未 `flutter clean`；未改工程师的生产源码（仅证伪时临时改动，已**逐字节**还原，见第 4 节）；未改 `server_deploy_report.md`。

---

## 0. 结论速览

| 项 | 结论 |
| - | - |
| 全量测试 | **1800 全绿**（默认并发 1m17s / `--concurrency=1` 4m42s 各一遍） |
| `dart analyze` | `No issues found!` |
| 静态门禁 | P4 **13/13 YES**；P5 UI **13/14 · IS_PASS: NO**（第 06 条 `await repo.save(` 6 > 冻结 4） |
| 独立出包 | **69,820,784 字节 / SHA256 `c41213ba…743849` / 三 ABI**，与工程师**逐字节一致**；`enable-native-assets: true` 已确认 |
| 账目 | 1759 + 41 = 1800 ✅（41 独立数得 10/20/11；本轮未改任何既有测试文件） |
| 门禁 13/14 裁决 | **允许升级为「显式申报清单」，不接受把 FROZEN 4 改成 6**。依据：6 处全为基线既存，且多出的 2 处**已有内存后端 widget 测试兜底**（`p9_rule_pick_test.dart`） |
| 证伪 | A2/A3（改回 `cover`+`maxHeight:96`）→ 4 组变红 ✅；B3（摘掉壳体退出接线）→ 2 组变红 ✅。均逐字节还原并复跑绿 |
| 智能路由 | **NoOne**（本轮无源码缺陷需打回；门禁那条按「文档级申报」处置，已写进清单与遗留） |

---

## 1. 五项自检独立重跑（原始输出）

命令前置（每条都做）：`export PATH=/d/dev/flutter/bin:$PATH` + `unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy` + `export NO_PROXY=127.0.0.1,localhost`。

### 1.1 `flutter test`（默认并发）

```
01:17 +1800: All tests passed!
```

### 1.2 `flutter test --concurrency=1`（串行）

```
04:42 +1799: ... test/wizard_steps_test.dart: 校验函数（从页面搬出来后行为不变） 非必填步骤永远放行
04:42 +1800: All tests passed!
```

### 1.3 `dart analyze`

```
Analyzing dice-realm...
No issues found!
```

### 1.4 `node tool/qa/qa_p4_gate.js`

```
[OK]   T05 门禁文件齐全（8 个）
       8 个齐全
==== 合计 13 条，失败 0 条 ====
P4_GATE IS_PASS: YES
```

### 1.5 `node tool/qa/qa_p5_ui.js`

```
[OK]   C7 四个死代码名在 lib/ 零命中
       扫描 193 个文件，plBottomBar / plFeeds / kpChat / kpGameLog 全零命中
[FAIL] await repo.save( 命中数不增加
       实际 6，冻结 4 —— lib/repo/card_transfer.dart:172, lib/repo/room_state_writer.dart:63, lib/ui/ai_create_page.dart:472, lib/ui/card_detail_page.dart:167, lib/ui/create/create_flow_page.dart:288, lib/ui/random_create_page.dart:166
...
==== 合计 14 条，失败 1 条 ====
P5_UI_GATE IS_PASS: NO
```

独立重跑确认：**13/14，`IS_PASS: NO`**，失败项与主理人所述一致（工程师报告未夸大也未隐瞒）。

### 1.6 独立出包 `bash tool/build_apk.sh`

```
[2/3] 校验 AOT 产物
  8717192  1981-01-01 01:01   lib/arm64-v8a/libapp.so
  9699912  1981-01-01 01:01   lib/armeabi-v7a/libapp.so
  8979336  1981-01-01 01:01   lib/x86_64/libapp.so
[3/3] 完成（native-assets 始终为开启状态，flutter test 可直接跑）

===== 出包成功 =====
-rw-r--r-- 1 60965 197609 69820784 2026-11-11 00:21 build/app/outputs/flutter-apk/app-release.apk
c41213ba82c7481797a3ef74f26d7ec2a3618817a161da0481c07ec022743849 *build/app/outputs/flutter-apk/app-release.apk
签名：debug（signingConfigs.getByName("debug")，可侧载安装、不可上架）
```

三项独立核对：

| 项 | 我的实测 | 工程师报的 | 判定 |
| - | - | - | - |
| 字节数 | `stat` → **69,820,784** | 69,820,784 | ✅ 一致（> 50MB，不是坏包） |
| SHA256 | **`c41213ba82c7481797a3ef74f26d7ec2a3618817a161da0481c07ec022743849`** | `c41213ba…` | ✅ 逐字节一致 |
| 三 ABI `libapp.so` | 8,717,192 / 9,699,912 / 8,979,336 | 三 ABI | ✅ 齐全 |
| `flutter config --list` | `enable-native-assets: true` | 已恢复 | ✅ |

> ★ 附带的反证价值：我在做完两次证伪实验（改过 `widgets.dart`、`room_entry_page.dart`）**之后**才出包，出的包 SHA256 与工程师**完全相同** —— 这反向证明我的 `cp` 还原是**逐字节无损**的，源码树与工程师出包时完全一致。

---

## 2. 账目核对（独立算）

| 项 | 数 | 证据 |
| - | - | - |
| 基线（工程师报） | 1759 | `_p10_transport1.txt` |
| 本批新增三文件 | **10 / 20 / 11 = 41** | 独立数：静态 `test(`/`testWidgets(` 行 9 + `for` 循环注册 1 = 10；20；11 |
| 三文件单独跑 | **+41: All tests passed!** | `flutter test <三个文件>` → `00:02 +41: All tests passed!` |
| 全量 | **1800** | 默认并发 + `--concurrency=1` 均 1800 |
| 加法 | 1759 + 41 = **1800** ✅ | 对得上 |

**「为了绿删用例」专项核查**（历史教训）：

- 全库 `test/*.dart` 共 **124 个文件**；按 mtime，本轮（2026-11-10 22:00 之后）**只有 3 个新文件被创建**：
  `p10_t1_room_exit_save_test.dart`(23:53) / `p10_t1_ui_paper_banner_test.dart`(23:54) / `p10_t1_cloud_room_test.dart`(23:57)。
- **没有任何既有测试文件在本轮被修改过**（最近的非本批文件是 `p11_overlay_test.dart`，21:27，属上一批）⇒ 不存在"从既有文件里删用例"的操作空间。
- 抽样核对既有文件用例数未变：`test/p9_rule_pick_test.dart` 仍含「AI 结果：就用这张 / 继续完善」（2 组）与「一键出卡结果：就用这张 / 继续完善」（2 组）；`test/ai_create_page_test.dart` 仍是 7 个 `testWidgets`（与 v 期一致）。
- 结论：**计数差为 0，无删用例迹象**。

---

## 3. ★ 门禁 13/14 的完整裁决

### 3.1 独立复算「到底几处」

我不用工程师/主理人的清单，自己按门禁算法（`code()` 先剥 `//` 行注释，再逐行正则 `/await\s+repo\.save\(/`）复算：

**原始 `grep -rn "await repo.save(" lib/` → 7 行**：

```
lib/repo/card_transfer.dart:172
lib/repo/room_state_writer.dart:4     ← 注释行！"★ 全库…唯一 await repo.save(card) 的地方。"
lib/repo/room_state_writer.dart:63
lib/ui/ai_create_page.dart:472
lib/ui/card_detail_page.dart:167
lib/ui/create/create_flow_page.dart:288
lib/ui/random_create_page.dart:166
```

`code()` 剥注释后剩 **6 处**，且**每个文件恰好 1 处**：

| # | 文件:行 | 用途 | 属 P4 收口基线？ | 有序兜底？ |
| - | - | - | - | - |
| 1 | `lib/repo/card_transfer.dart:172` | 卡在档案间转移（导入/复制） | ✅ 基线 4 之一 | 有单测（repo 层，内存后端） |
| 2 | `lib/repo/room_state_writer.dart:63` | **全库唯一的"房间状态写回"落盘入口**（C5/K11 收口），濒死卡守卫在这条路径上 | ✅ 基线 4 之一 | 有单测（C1/C2 用例直接跑这条） |
| 3 | `lib/ui/card_detail_page.dart:167` | 卡详情页编辑后保存 | ✅ 基线 4 之一 | 有 widget 测试（`pumpCardDetail` → `MemoryStorage`） |
| 4 | `lib/ui/create/create_flow_page.dart:288` | 向导末步保存 | ✅ 基线 4 之一 | 有 widget 测试（`create_flow_widget_test.dart`，内存后端） |
| 5 | `lib/ui/ai_create_page.dart:472` | AI 结果页 `_useThis()`：「就用这张」→ 落库 → 回首页 | ❌ **新增计入（基线外 2 处之一）** | ✅ `test/p9_rule_pick_test.dart:272` |
| 6 | `lib/ui/random_create_page.dart:166` | 一键出卡结果页 `_useThis()`：同上 | ❌ **新增计入（基线外 2 处之一）** | ✅ `test/p9_rule_pick_test.dart:331` |

> **订正一处细节**：主理人给的清单写的是「`room_state_writer.dart` ×2」，把**第 4 行那句注释**也算进去了（所以那份清单实际列了 7 个位置却标"6 处"）。按门禁真实算法（剥注释）是 **6 处 / 6 文件 / 每文件 1 处**，`room_state_writer.dart` 只占 1 处。行号也差 1（`ai_create_page` 是 **472** 不是 471，`random_create_page` 是 **166** 不是 165）。**申报清单必须按 6 条写，不能按 7 条写**，否则注释行也会被"申报"进去，后人照抄就会以为注释也算违规。

### 3.2 这两处是不是本轮引入的？

```
2026-11-10 20:32:39  lib/ui/ai_create_page.dart
2026-11-10 20:32:43  lib/ui/random_create_page.dart
（本轮 lib 改动全部落在 23:36 ~ 00:02 之间）
```

**20:32 早于本批开工（23:30）** ⇒ 属 P9 批次留下的基线既存，**不是本轮引入**。主理人的事实判断成立，我已独立复核。

### 3.3 ★ 到底有没有「fake-async 挂死」的真实风险？

先分清两种后端：

- `MemoryStorage`（`lib/repo/character_repo.dart:58`）：纯内存，`save` 里只有一次 Map 深拷贝，**在 FakeAsync 下正常完成**。
- `JsonFileStorage`（同文件 `:101`）：真实文件 I/O（`dir.exists()` / `create()` / `readAsString` / `writeAsString`）。在 `testWidgets` 的 FakeAsync 区里，真实 I/O 的 Future **不会被 pumpAndSettle 推进**（要 `tester.runAsync` 才行），所以**一旦 widget 测试注入 JsonFileStorage 并 `await repo.save()`，就是超时/挂死**。

风险是真的，但**是否被约束**取决于测试注入了哪个后端。我逐条查了：

```
test/support/app_harness.dart:34  Future<CharacterRepo> newMemoryRepo() => CharacterRepo(storage: MemoryStorage());
test/support/app_harness.dart:151 final r = repo ?? await newMemoryRepo();   // pumpApp 默认
```

`pumpApp` 默认注入 **MemoryStorage**；`newTempRepo()`（JsonFileStorage）只被纯 `test`（无 widget）用。

### 3.4 ★ 这两条路径真的有 widget 测试覆盖、且真跑到 `await repo.save` 吗？

**有。** 在 `test/p9_rule_pick_test.dart` 里（不在 p10 文件里，容易漏）：

- `:272 「就用这张」→ 落库 + 回首页`（AI 页）：`tapKey('result_use_this')` → `expect(repo.all.length, 1, reason: '「就用这张」必须真的落库')` + 校验卡上带所选规则。
- `:331 「就用这张」→ 落库 + 回首页（第 1 张）`（一键出卡页）：`tapKey('result_use_this_0')` → `expect(repo.all.length, 1)` + `expect(find.byType(RandomCreatePage), findsNothing)` + `expect(find.byType(HomePage), findsOneWidget, reason: '保存后必须回首页')`。
- 两者都用 `pumpApp`（默认 `newMemoryRepo`）⇒ **注入了 MemoryStorage**。

顺带否掉一个**常见误判**：`test/ai_create_page_test.dart:139/244` 那两个用例**走的不是这条分支** —— 它们点的是 `result_continue_edit(_0)`（「继续完善」→ 进向导，**不落库**），其中 244 那条还显式断言 `expect(repo.all, isEmpty, reason: '进向导也还没保存')`。所以**不能**拿这两个当"已有兜底"，真正的兜底在 `p9_rule_pick_test.dart`。

### 3.5 裁决

**我同意「升级为显式申报清单」，反对把 `FROZEN = 4` 改成 6。** 理由：

1. 改成 6 是**放宽门禁**：以后任何新增都被允许到 6，再下次 8、10……这条判据就死了。它的价值全在"数字不许涨"。
2. 但现状确实**不能判红就算完**：6 处都是合法用法，其中 2 处还是用户需求（「就用这张」要落库）。
3. 所以正确形态是**从"裸数字"变成"白名单 + 申报"**：逐条写清 `文件:行 / 用途 / 是否基线 / 由哪个测试兜底 / 注入的后端`，新增第 7 处依然会被拦（不在白名单里就是 FAIL），既有 6 处白纸黑字接受监督。
4. **并且必须补一条硬规则写进门禁注释**：任何覆盖这些路径的 widget 测试**必须注入 `MemoryStorage`**（`JsonFileStorage` 在 FakeAsync 下必挂），否则申报清单只是记账，挡不住下一个人用 `newTempRepo()` 写 widget 测试然后在 CI 上随机超时。

**判定：风险已被测试约束 → 允许升级为申报清单，但需工程师实施（我不改门禁常量、不改门禁脚本）。** 申报条目就按 3.1 那张 6 行表落地。这条列为**本期遗留 1**（唯一未闭环项，非阻塞：门禁红的是"记账方式"，不是功能缺陷）。

---

## 4. 断言复核 + 自己证伪（重点查「为了绿放宽」）

### 4.1 A1 一键出卡页角色信息栏背景

**读码结论：断言是真结构断言，且补了正例。**

- `test/p10_t1_ui_paper_banner_test.dart:78`：先 `expect(card, findsOneWidget)`（**证明卡真的渲染了**，不是整块没画也算绿）。
- `:80` 正例：卡内必须有 `ParchmentSurface`（换成纯色羊皮纸了）。
- `:94` 负例：`_decorationImagesIn(tester, card)` 必须 `isEmpty` —— 该辅助函数遍历卡内**所有** `DecoratedBox` 与 `Container` 的 `BoxDecoration.image`，一处底纹图都算失败。这正是本 bug 的机制断言（3:4 底纹图自带双线金框，宽卡 cover 按宽铺 → 左右竖线进卡内）。
- `:100` 结构约束：`ShaderMask` 仍在（P11「底纹不许在头部行画线」的约束没被这刀砍掉）。
- `:130` **第二条正例**：单独渲染 `ParchmentSurface`，断言「纯色 `ColoredBox` + ≥2 个 `Gradient` + `CustomPaint`(纸纤维)」—— 防的是"把背景删成纯白也算过"这种偷懒修法。

判定：**不是放宽，是真结构断言 + 双侧正例。**

### 4.2 A2 / A3 标题栏裁切

**断言的是什么**：不是"widget 存在"，而是**量出来的框**：

- `:163` 对首页两个 `SectionBanner` 逐个 `tester.getRect(ArtImage)`，断言 `r.width / r.height ≈ 6 (±0.02)`；平板档额外断言 `r.height > 96`（旧实现 `maxHeight:96` 会把 126.7 钳成 96）。
- `:170` 断言 `img.fit == BoxFit.cover`（比例精确时 cover = 零裁切）。
- 参数化：手机竖屏 412×888 + 平板横屏 1524×1016 各一条。
- `:180` 静态函数单测：`heightFor(760) ≈ 126.67` / `fitFor(760) == cover` / `fitFor(1524) == contain`。
- A3 `:204` 对规则页同一个组件做同一套断言。

**★ 我自己证伪一次**：把 `SectionBanner.fitFor` 改回恒 `cover`、`maxHeight` 改回 `96`（= 旧 bug 的代码形态）：

```
00:01 +2 -1: A2 412×888 [E]   Expected: a numeric value within <0.02> of <6>   Actual: <7.583333333333333>
00:01 +2 -2: A2 1524×1016 [E] Expected: ... Actual: <7.583333333333333>
00:01 +2 -3: A2 heightFor/fitFor [E] Expected: within <0.001> of <126.66666666666667>  Actual: <96.0>
00:01 +2 -4: A3 规则选择页 [E] Expected: ... Actual: <7.583333333333333>
00:02 +6 -4: Some tests failed.
```

→ **4 组变红**，且实测比例 7.583:1 与主理人描述的"框变 7.9:1、上下各裁 15px"同一数量级（728/96 = 7.583，728 是内容区扣掉左右 padding 后的宽度）。**证伪成立：这些断言真的能抓住旧 bug。**

还原证据：

```
$ cp /tmp/qa_bak/widgets.dart.bak lib/ui/widgets.dart
$ diff -q /tmp/qa_bak/widgets.dart.bak lib/ui/widgets.dart
DIFF: identical
$ sha256sum lib/ui/widgets.dart
241ea143532bb1198a0ba2b050d7b169e4948208decd93ab482ccc8bb50bc134
```

（还原后复跑三个新文件 → `+41: All tests passed!`；最终出包 SHA256 与工程师一致，见 1.6。）

### 4.3 B1 KP 审卡

- `:299` 先走**真实协议**推进一张完整卡（`RoomIntent.char` 的 `sheet` 载荷），再打开 `showCharViewSheet(seat:'p1')` —— 不是直接塞 mock widget。
- `:334` 断言 8 个分区键全在（`basics/background/history/assets/education/vitals/attrs/skills`）。
- `:345~380` 断言**内容真来自那张卡**：「沈墨白」「私人侦探」「阿卡姆图书馆」「父亲的怀表」「一桩失踪案」「厚呢大衣」「教育进步检定 1 次」逐个 `findsOneWidget`（不是空壳分区）。
- `:385` **滚动的实测断言**：取 `ScrollableState` 的 `position.pixels` 做前后对比，`tester.drag(CharViewKeys.status, Offset(0,-260))` 后 `after > before`。→ 是"真的能滚"，不是"存在一个 ScrollView"。
- `:404` 私密字段：载荷里塞 `privates` / 明文 `p`，断言**权威态 sheet 里就没有这两个键**（白名单入口挡掉），再断言文案没出现在审卡里。
- 实现侧复核：`lib/domain/room_model_actions_sheet.dart:216-284` 是 presence-gated 扩展（`if (src.containsKey(key)) extras[key] = ...`），`privates`/`p` 注释里明确排除 ⇒ **没有为了补字段而开私密口子**。

判定：B1 真修好，且断言强度足够（内容 + 滚动 + 白名单三道）。

### 4.4 B3 / B4 结团解散 / 踢人

- **B3 是真行为断言**（导航 + 提示文案）：`:236` 连点两次「结团」→ `expect(find.byType(RoomLobbyPage), findsNothing)` + `expect(find.byType(RoomEntryPage), findsOneWidget)` + 读 `RoomEntryKeys.notice` 的 `Text.data` 必须含「结团」；`:262` 对「结束房间」同形，文案含「结束房间」。第一次点击只进确认态（`expect(find.text('再点一次确认'), findsOneWidget)`），证明没退化成"一次点击就发包"。
- **★ 我自己证伪一次**：在 `_RoomShellState._onSessionChanged` 里、判定之后插一句 `if (1 == 1) return;`（= 摘掉"把页面带走"的接线，即复现旧 bug）：

```
Expected: no matching candidates
  Actual: _TypeWidgetFinder:<Found 1 widget with type "RoomLobbyPage": [
B3：结团后本机必须离开房间（旧版原地不动 = 「点了没反应」）
00:01 +7 -1: ... 「结团」连点两次 → 回到入口页，并留下原因说明 [E]
00:01 +7 -2: ... 「结束房间」连点两次 → 同样回到入口页 [E]
00:02 +18 -2: Some tests failed.
```

→ **恰好 2 组变红，其余 18 组仍绿**（说明这两条测的确实是"离开"这件事，不是别的耦合）。还原：

```
$ diff -q /tmp/qa_bak/room_entry_page.dart.bak lib/ui/room/room_entry_page.dart
DIFF: identical
$ sha256sum lib/ui/room/room_entry_page.dart
101081fe89685a9cae09d94bd4dae778f7d1b821048ea91374f3751ee35cdea5
```

- **B4 是权威端真状态断言**：`:283` 走真实 `room.kick` action → 断言花名册真的少了 `p1`、`roster.kicked` 含 `p1`、`attachPeer` 原座 `blocked == true`（踢得掉）、换座 `rejected == false`（不永久卡死）。`:318` 主动离开 → `online == false` 但成员还在、`kicked` 不含它、同座可重进。`:341` 被踢者视角：`meta.status == CLOSED` + `session.kickedByHost == true` + `roomExitOf(...) == kicked`。
- 实现侧复核：`kickedByHost` 在 `room_session_local/remote/cloud` 三处都有真实现（不是常量 false 的桩，基类 `room_session.dart:196` 才是 false 默认）；`closeConnection()` 在 `remote`/`cloud` 都有幂等实现；`room_entry_page.dart:489/512` 真的调了。

**残余风险（如实记录，非阻塞）**：B4 没有一条"KP 踢人 → 被踢那台 device 的页面真的 pop 掉"的端到端 widget 测试。它由两段拼起来覆盖：B4 证明"判定为 kicked"，B3 证明"判定成立 → 页面被带走"（同一段 `_onSessionChanged` 代码）。**逻辑上闭合**，但确实是"两段拼接"而不是"一条链路"。已列进遗留 2（建议下一期补一条 30 行的 widget 用例即可，风险低）。

### 4.5 B5 公网开房（重点查"假按钮 / 假成功"）

- **未配置时不放假的按钮**（`:570`）：`settings.roomBase = ''` → `expect(createSubmitCloud, findsNothing)` + `expect(cloudSetupHint, findsOneWidget)` + 文案含「公网开房需要先在」。实现侧 `room_entry_page.dart:672-690` 也是 `if (_cloudBase.isNotEmpty) 真按钮 else 去设置` 的二选一，`_createCloud()` 里还兜了一次空地址（`:238-240`，绝不发空地址请求）。
- **已配置时真能建连**：`:356` 用内存中继跑 `POST /api/rooms` 拿回 `code/hostToken/wsBase`；`:386` 跑通一整轮 `KP 出站 SendPlan → hub.broadcast → 玩家` + `玩家 intent → 权威端`；`:485` KP 踢人 → 中继真把那条连接关掉；`:524/:540` 连不上 / 房号错 / 人满 → **如实失败并翻成人话**（`expect(r.ok, isFalse)` + `expect(r.error, contains('人满'))`）。
- **没有把"已连接云端"写成假成功**：`:589` 已配置的用例只断言出现按钮 + **如实展示中继地址**（`find.textContaining('relay.example.com/room')`），没有任何 `expect(true)` 式的自我安慰断言。失败路径全部 `ok == false` 且 `expect(link.running, isFalse)`（不产生半成品房间）。

判定：**B5 不是假按钮、不是假成功**。但"真实双端跨网络联调"确实没做（自动化止于内存中继）——**这属如实边界，不是违约**（服务端本就未改，联调需要真机环境）。

### 4.6 C1 / C2 角色卡保存

- **C1 真的写入 repo（前后对比）**：`:369` 先在房里用真实 `sheet.damage` 打掉 5 点血 → 读出 `inRoom` 的 `currentHP`（断言 `lessThan(12)`，确保是"房间里已经变了"）→ `saver.saveNow()` → 断言 `outcome.ok` + `repo.all.length == 1`（不新建重复卡）+ `repo.get('c_p1').status['currentHP'] == inRoom`（**落盘的是房间里的新值**）。→ 前后对比成立。
- **失败不猜卡**：`:403` 没绑卡 → `ok == false`、`message` 含「绑定角色卡」、`repo.all` 仍为空。
- **UI 入口真落盘**：`:418` 点 `GpPlCharCardKeys.saveBtn` → SnackBar「已保存到『已保存的角色卡』」+ `repo.get('c_p1') != null`；`:454` 旁观者**结构性不渲染**该按钮。
- **C2 只在轮次推进时触发一次、不乱循环**：`:472` 真实 `round.next` → `autoSaved == 1`，再连发 3 次 `onStateChanged()` 仍 `== 1`（幂等靠 `_lastAutoRound` + `_busy`）；`:494` 再推一回合 → `== 2`；`:514` 招募期（没开团）→ `0`；`:527` KP / 旁观者 → `0`。
- 实现侧：`room_card_saver.dart` 的 `_lastAutoRound` 用回合号去重（不是计时器、不是 debounce），无 `Timer` 无轮询 ⇒ **不会乱循环**。

判定：C1/C2 真修好。**C1 保存集合不含属性/技能 = 如实边界**：我核了房间侧所有动作（`state.edit.self/state.self/state.edit.other/state.request/state.apply/sheet.damage/sheet.sancheck/sheet.tempstatus/sheet.item/sheet.sanloss/sheet.healwound/aid.apply/aid.psycho/madness.advance/madness.cure`），`change` 只带 `status/tempStatus/items/weapons/mental/madness`，**属性与技能在跑团中根本不产生变更事件** ⇒ "保存集合 = 可变字段全集"成立，**不是缩水**。

---

## 5. 各 bug 根因是否成立的独立判断

| 项 | 工程师报的根因 | 我的独立判断 |
| - | - | - |
| A1 | 底纹图 `b1_card_face_3x4` 自带双线金框，平板拉宽后 cover 按宽铺 → 左右竖线露进卡内 | **成立**。修法（换 `ParchmentSurface`，零资源文件）直接消灭了"图存在"这个前提，断言也对准了机制（卡内 `DecorationImage == 0`） |
| A2/A3 | `BannerSlot(aspectRatio:6, maxHeight:96)` 在 760 宽把 126.7 钳成 96 → 7.9:1 → cover 上下各裁 15px | **成立**。我复现了 7.583:1（实测容器 728 而非 760，原因是内容区左右 padding；裁剪量级一致）。修法（比例严格化 + 触顶改 contain）是对的：**宁可两侧留底色，也不裁金边** |
| B1 | 房卡摘要白名单只收对局字段 → KP 审卡是残卡 | **成立**。修法用 presence-gated 扩展（源载荷带键才输出），既补全又不破坏旧载荷兼容；`privates`/`p` 仍在白名单外 |
| B2 | 跨设备头像未打通（载荷只有相对路径） | **成立，且是"如实边界"**。同机可见 + 缺失回退首字圆点已实现并有断言；跨设备要动载荷契约，属新需求 |
| B3 | ① `room.close/end` 是 `RoomConfirm.twice`，UI 只重复发 action 被 pending 去重吞掉；② 状态变了没人把页面带走 | **成立**。第一条我用证伪间接验证（连点两次才发包，第一次只改文案）；第二条我摘掉接线后 2 组立刻变红，说明"没人带走页面"确实是可复现的缺口 |
| B4 | ①服务员端把被踢座位再分配 + hello 不看 `attachPeer` blocked → 假 joined；②被踢者收不到 members 广播（收件人按花名册算）→"不在名单"判据永不成立；③ bye 只摘 socket 不标离线 → 幽灵在线；④`RemoteSession` 离开不关 socket | **成立**。②这条我特别认：它解释了为什么"用成员表判断被踢"这个看似自然的写法会永久失效 —— 所以 `room_exit.dart` 改成 `kickedByHost` 硬信号 + 注释里明写"不能用成员表当判据"，这是对的。③④有 `detachPeer` 标离线与 `closeConnection()` 幂等实现兜底 |
| B5 | 只读核实 `room_server.py`(1967 行) → 权威端仍是 KP 手机、`hub.*/peer.*` 控制层、应用层原样透传 ⇒ 不需要改服务端 | **成立**（服务端文件 mtime 2026-11-10 13:32，本批未动；`server_deploy_report.md` 我只读未改）。代价是"真实双端联调=0"，已写进清单重点项 |
| C1 | 保存集合 = 房间协议可变字段全集 | **成立**（见 4.6，我逐个 action 核过） |
| C2 | 每人在本机保存 | **成立**（KP/旁观者 `autoSaved == 0` 有断言） |

---

## 6. 红线扫描（本批改动范围 vs 基线）

本轮被改的 `lib/**` 共 **21 个 .dart**（23:36~00:02）。逐项扫：

| 红线 | 结果 | 证据 |
| - | - | - |
| `lib/domain/**` 纯净度 | ✅ 55 个 .dart 零 `package:flutter` / `dart:io` / `dart:ui` | 门禁 07 `[OK]` |
| `pubspec.yaml` 未动 | ✅ mtime `2026-11-10 21:35`（P11 批次，早于本批 23:30 开工），版本仍 `2.17.0+83` | `stat` |
| `jsStr(` 仍 14 处零新增 | ✅ `lib/ui/room` 内 14 处，白名单 6 文件之外为 0 | 门禁 08 `[OK]` |
| 零裸 `showDialog` | ✅ `lib/ui/room` 内 0 处（门禁 11 扫 67 文件零命中）。全库 4 处 `showDialog<bool>`，均在 room 之外（`card_detail_page`×2 / `status_editor` / `share_panel`，全是二次确认，mtime 均早于本批） | 门禁 11 + `grep` |
| 零 `LogRecord.toWireJson()` 出站 | ✅ 7 处命中里 6 处是注释、1 处是 `room_types.dart:386` 的定义；**零出站调用** | `grep` 逐条看 |
| 零新增 `Timer` / `Future.delayed` / `AnimationController` | ✅ 活代码只剩 2 处 `Timer(`：`lan_client.dart:316`（11-09）、`room_ui_local.dart:74`（11-09），**均早于本批** | `grep` + `stat` |
| 未删 `build` junction / 未 `flutter clean` | ✅ 全程未执行 | 我的命令记录 |
| 未跑 adb / 模拟器 / 真机 | ✅ | 同上 |

---

## 7. 真机清单 `_manual_test_checklist.md` 的更新点

**只登记、不执行**。结构与风格保持不变（原有 22 个章节一个没删，510 → 548 行）。

1. **新增章节**「## P0 · P10 第 1 期（车卡页与房间修复回归，2026-11-11 凌晨新增，**必测**）」，10 条可操作项：
   A1（平板横屏看纯色羊皮纸、左右无竖线）/ A2（首页两条标题栏上下金边完整，平板横屏+竖屏+手机）/ A3（规则系统标题栏同上）/ B1（KP 审卡 5 个分区齐全 + **能上下滑**）/ B2（本机头像可见；**跨设备显示不出来是已知限制**，回退首字圆点算过）/ B3（结团/解散二次确认后**本机立刻离开**，另一台也被带出）/ B4（踢人后离开 + 原座拒入 + 换座/重开能进；主动离开能回原座）/ B5（未填 `roomBase` 只给「去设置」不放假按钮；填了**两台跨网络能连上**，标注"首次真机联调，重点"）/ C1（手动保存 → 回「角色档案」看到状态已更新、卡数不变）/ C2（KP 推下一回合 → 玩家设备上自动更新、各自保存）。
   章节下方附「三处如实边界」提示（B2 未打通 / B5 服务端未改且未真机联调 / C1 不含属性技能），防止真机阶段把它们误记成回归失败。
2. **订正头部 APK 信息**：改为 `69,820,784 字节 / SHA256 c41213ba…743849 / 三 ABI（8,717,192 / 9,699,912 / 8,979,336）/ debug 签名`，并加注「**P10 第 1 期由 QA 独立重新出包**」+ 与前次 SHA256 逐字节一致的说明 + "< 50MB 会白屏"的判据。上一版（P11，`b31c4035…`）保留一行供回滚对比。
3. **订正尾部「自动化已验证」**：全量测试数从 **1565（陈旧）→ 1800**（并注明 1759 + 41、两遍并发都跑）；新增 `dart analyze` 一行、门禁降级为「P4 13/13 YES；P5 UI 13/14 · IS_PASS: NO + 裁决」一行、**证伪自检**一行、B5 内存中继一轮一行；APK 三 ABI 行更新为实测字节数。原有"服务端监听 4211""外部客户端握手""界面真实渲染"三行**保留未删**。
4. **技术债**：新增第 6 条，写清三条如实边界（B2 跨设备头像未打通 / B5 服务端未改 + 无真机联调 / C1 不含属性技能）；1~4 条逐条读过，与现状**不矛盾**，未改（第 3 条仍是"旧版同源的设计取舍"，第 4 条 debug 签名仍准确）。

---

## 8. 智能路由结论

**Routing Decision: NoOne（测试代码无需自修，生产代码无需打回）。**

- 无「源码 bug 被正确断言抓住」的情况：1800 全绿，两次证伪都按预期变红。
- 无「测试代码自己写错」的情况：新用例断言均对准机制（结构/比例/导航/落库前后对比），没有 make-it-green 的迹象。
- 门禁 13/14 不是源码缺陷，是**记账方式**需要升级 —— 已给出可执行裁决（6 条申报清单 + "widget 测试必须注入 MemoryStorage"），交工程师实施，**不由我改门禁**。

---

## 9. 遗留问题（本期未闭环，均非阻塞）

1. **门禁第 06 条待升级为申报清单**（唯一的红）：需工程师把 `tool/qa/qa_p5_ui.js:160-172` 的 `FROZEN = 4` 改成**显式 6 条白名单**（按 3.1 的表：`文件:行 / 用途 / 基线与否 / 兜底测试 / 注入后端`），并在注释里写死「新路径必须先在白名单里申报，否则 FAIL」+「覆盖这些路径的 widget 测试必须注入 `MemoryStorage`」。**不动 FROZEN 数值、不删判据**。
2. **B4 缺一条端到端 widget 用例**：建议补「KP 踢人 → 被踢那台 pump 出 `_RoomShell` → 断言 `RoomLobbyPage` 消失且 `notice` 含『移出房间』」。当前由 B3（接线）+ B4（判定）两段拼合覆盖，逻辑闭合但非单链路。
3. **B2 跨设备头像**：如实边界，需另开批次（头像随载荷同步或走中继上传）。
4. **B5 真实双端跨网络联调**：自动化到内存中继为止，需真机首次验证（已列为清单 B5 第 ③ 点"重点"）。
5. **A1 的 `ParchmentSurface` 在多宽卡片下的观感**：结构上已保证"没有竖线"，但"羊皮纸质感在 700px 宽卡上会不会显得空"只能真机看（已写进 A1 验收项）。

---

## 10. 附：我执行过的全部命令（可复现）

```bash
export PATH=/d/dev/flutter/bin:$PATH
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy
export NO_PROXY=127.0.0.1,localhost

flutter test                                   # 01:17 +1800: All tests passed!
flutter test --concurrency=1                   # 04:42 +1800: All tests passed!
dart analyze                                   # No issues found!
node tool/qa/qa_p4_gate.js                     # 合计 13 条，失败 0 条 → IS_PASS: YES
node tool/qa/qa_p5_ui.js                       # 合计 14 条，失败 1 条 → IS_PASS: NO
flutter test test/p10_t1_ui_paper_banner_test.dart \
             test/p10_t1_room_exit_save_test.dart \
             test/p10_t1_cloud_room_test.dart  # +41: All tests passed!
bash tool/build_apk.sh                         # 69,820,784 / c41213ba… / 三 ABI
flutter config --list | grep native            # enable-native-assets: true

# 证伪 1（A2/A3）：改 SectionBanner，跑 paper_banner → 4 红
#   cp → diff -q (identical) → sha256 241ea143…bc134
# 证伪 2（B3）：摘掉 _RoomShell 退出接线，跑 room_exit_save → 2 红
#   cp → diff -q (identical) → sha256 101081fe…cdea5
```
