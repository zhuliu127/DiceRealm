# QA 报告 — 2.45.0+115 关键事件遮罩「320dp 标题被吃字」修复独立验证

**ROUTE: NoOne** —— 修复正确、范围干净、全量回归 191 文件 / 2699 用例全绿（0 失败 / 0 skip），
工程师的两条附加结论（`combatStartSubtitle` 需 3 行、`deathSubtitle` 只需 2 行）经我独立复算**完全一致**。

- 工程：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
- 版本：2.45.0+115（pubspec / app_version.dart / android/local.properties 三处逐字一致）
- 被测实现：`lib/ui/room/widgets/room_event_banner.dart`（`_textBlock` 标题与副行 `maxLines: 2 → 3`）
- QA 交付物：`test/qa_245_title_fit_test.dart`（72 条，新增，未改动任何既有测试）

---

## 1. 独立实测表（真实 App 主题 `buildTheme(Brightness.dark)`）

排版宽度换算（契约，由用例锁住）：`内容宽 = min(720, 屏宽 − 2×32) − 2×28 − 2×1`
→ 320:198dp / 360:238 / 375:253 / 400:278 / 412:290 / 860:662

「T」= 标题需要几行，「S」= 副行需要几行；`ok` = `didExceedMaxLines == false`，
`TRUNC` = 被省略号截断。

| 模板 | 320 T/S | 360 T/S | 375 T/S | 400 T/S | 412 T/S | 860×400 T/S |
|---|---|---|---|---|---|---|
| combatStart / 5 人（满 4 名字 + 等 5 人） | 1 / **3** ok | 1 / 2 ok | 1 / 2 ok | 1 / 2 ok | 1 / 2 ok | 1 / 1 ok |
| combatStart / 2 人 | 1 / 2 ok | 1 / 2 ok | 1 / 1 ok | 1 / 1 ok | 1 / 1 ok | 1 / 1 ok |
| combatEnd | 1 / 1 ok | 1 / 1 ok | 1 / 1 ok | 1 / 1 ok | 1 / 1 ok | 1 / 1 ok |
| death（撕卡 —— 该角色只能通过聊天框交流） | 1 / **2** ok | 1 / 2 ok | 1 / 2 ok | 1 / 1 ok | 1 / 1 ok | 1 / 1 ok |
| ripped（沈砚清 陷入永久疯狂 / 撕卡 —— SAN 已归零） | 2 / 2 ok | 2 / 1 ok | 2 / 1 ok | 1 / 1 ok | 1 / 1 ok | 1 / 1 ok |
| madness / 临时 + N 轮 | 2 / 1 ok | 2 / 1 ok | 2 / 1 ok | 1 / 1 ok | 1 / 1 ok | 1 / 1 ok |
| madness / 不定 | 2 / 1 ok | 2 / 1 ok | 2 / 1 ok | 1 / 1 ok | 1 / 1 ok | 1 / 1 ok |
| madness / 若干轮 | 2 / 1 ok | 2 / 1 ok | 2 / 1 ok | 1 / 1 ok | 1 / 1 ok | 1 / 1 ok |
| **newSymptom（最长标题）** | **3** ok | 2 ok | 2 ok | 2 ok | 2 ok | 1 ok |

**全部 54 格：无一条截断、无一条抛出渲染异常。**

### 对工程师两条附加结论的独立复算

| 工程师结论 | 我的复算 | 判定 |
|---|---|---|
| ① `combatStartSubtitle`（4 满名字形态）在 320dp 下**需要 3 行**，2 行会被截 | 实测标题页宽 198dp 下 **S = 3 行**（28 字 × 15px = 420dp > 2×198）；`didExceedMaxLines` 在 2 行上限下为 true、3 行下为 false | **一致，成立** |
| ② `deathSubtitle` 在 320dp 下**只需 2 行**、本来就完整 | 实测 **S = 2 行**（18 字 × 15px = 270dp ≤ 2×198），且 `maxLines: 3` 没有让它多占高度（段落高 = 2 行） | **一致，成立** |
| ③ `maxLines: 3` 只是上限，360dp 起不会凭空多一行 | 360/375/400/412 最长标题 **T = 2**，860 横屏 **T = 1**；段落占位高度 = 实际行数高（不是 3 行高） | **一致，成立** |

**核心前提核对（防「修假问题」）**：320dp 下 `newSymptomTitle` 用两条独立路径（渲染 + 按文案重排）
都得到 **3 行** → 2 行上限必然吃字，本批修的是**真问题**。

### 一个口径提示（不影响本批结论，给工程师备注）

`_textBlock` 的 `Text` 没有显式设 `letterSpacing`，它会从 `DefaultTextStyle` **继承主题值**：
- 产品真实主题 `lib/theme.dart#_textTheme()` 的 `bodyMedium` **不带** letterSpacing → 0；
- 既有测试用的 `ThemeData.dark(useMaterial3: true)` 的 `bodyMedium` 带 **0.25**。

所以实现注释里「字号被钳死 → 行数是确定的」**不完全准确**：行数还受继承字距影响。
实测差异举例（320dp）：`rippedSubtitle`「撕卡 —— SAN 已归零」在真实主题下 1 行、在 M3 默认主题下 2 行
（195dp + 13×0.25 = 198.25 > 198）。两者都在 3 行上限内，**本批结论不变**；
我的测试以真实主题为主口径，并额外加了一条「M3 默认主题（letterSpacing 0.25）下也不许截断」的余量用例。

---

## 2. 全量回归

| 项 | 值 |
|---|---|
| 测试文件 | **191**（既有 189 + 工程师 p21b + 我的 qa_245；`ls test/*.dart` 实测） |
| 用例总数 | **2699** |
| 失败 | **0** |
| 跳过 / skip | **0**（检查每文件最终行的 `~N`，全为 0；日志里出现的 `~` 均为用例名中的 `DEX ~/ 2`、`60~99`） |
| 运行方式 | `flutter test --no-pub -j 1 <单文件>` 串行逐文件，共 10 批，每批前把 `build/{test_cache,unit_test_assets,native_assets}` 改名为 `*_qa245b<N>`（跑完已清理） |
| 退出码 | 191/191 文件 rc=0 |

重点文件复核：

| 文件 | 用例 | 结果 |
|---|---|---|
| `test/p21_event_banner_mask_test.dart`（遮罩结构/点击/队列） | 17 | 全绿 |
| `test/qa_244_event_mask_test.dart`（遮罩 22 条） | 22 | 全绿 |
| `test/p21b_banner_title_fit_test.dart`（工程师本批） | 7 | 全绿 |
| `test/qa_245_title_fit_test.dart`（本报告） | 72 | 全绿 |
| `test/room_ui_lobby_test.dart`（隐私白名单门禁） | 18 | 全绿 |
| `test/room_ui_permission_test.dart`（锚点 op=25 / policy=62 门禁） | 21 | 全绿 |
| `test/app_version_test.dart`（版本单一真源） | 3 | 全绿 |

---

## 3. 反向证伪（改坏 → 必须真红 → 逐字节恢复）

基线 sha256：`fe3dc049e443384ae4567f7c03a060943ec94a6972685563e6ca687a47da83d9`（`room_event_banner.dart`）

| # | 改法 | 红的样子（真断言失败，非编译/脚本错） | 恢复后 |
|---|---|---|---|
| 1 | 标题 `maxLines: 3 → 2` | 5 条 `[E]`：核心用例 `★320×568 最长标题完整显示…[E]` → `Expected: false / Actual: <true>`（`didExceedMaxLines`）；`newSymptom 320×568` 矩阵用例同样红；`文字块高度` 用例 `Expected: within <2.0> of <93.0> / Actual: <62.0>` | 逐字节恢复，`sha256sum` = 基线值，72/72 全绿 rc=0 |
| 2 | 文字块 `maxTextWidth: 720 → 200` | 70 条 `[E]`：`布局契约常量` → `Expected: <720.0> / Actual: <200.0>`；宽屏组 5 条全红 `Expected: a value less than or equal to <2>`（360/375/400/412 最长标题变成 3 行）—— 证明「宽屏不截断」断言**不是恒真** | 逐字节恢复，`sha256sum` = 基线值，72/72 全绿 rc=0 |

自检用 `grep '\[E\]'`（不锚行首），未出现假 INVALID。

---

## 4. 口径变化表

**无既有断言被放宽**：本批我**没有修改任何既有测试文件**（`find test -newermt 19:35` 只有工程师的 `p21b` 与我的 `qa_245`），
没有降级 `findsOneWidget`、没有删用例、没有 `skip`、没有把断言改成恒真。
新增用例全部是追加（72 条），既有 39 条遮罩断言（17+22）原样保留且全绿。

---

## 5. 未改动面核验（实测值）

| 项 | 实测 |
|---|---|
| `pubspec.lock` sha256 | `6484c4bf5bc696dec8661cab037aab161313d326d0352f8567df2d01694f560f`（= 基准，未变） |
| `url: "https://pub.dev"` 处数 | **82** |
| 镜像串（`flutter-io.cn` 等）处数 | **0** |
| NUL 字节扫描 | 7 个改动/相关文件（banner / app_version / pubspec.yaml / pubspec.lock / p21b / qa_245 / local.properties）全部 `nul_bytes=0` |
| 本批 `lib/**` 实际改动文件 | **仅 2 个**：`lib/app_version.dart`(19:41) + `lib/ui/room/widgets/room_event_banner.dart`(19:51) |
| `lib/domain/**` | 最新 mtime `2026-11-21 15:21`（远早于本批 19:41）→ **本批 0 改动**；协议/存档相关测试全绿 |
| `lib/ui/room/critical_event_tracker.dart` | mtime `15:25` → **本批 0 改动** |
| `lib/ui/room/event_banner_copy.dart` | mtime `15:25` → **本批 0 改动**（文案仍单一真源，我的用例全部经它取字） |
| `lib/ui/room/room_ui_local.dart`（队列） | mtime `18:49`（2.44.0 批次）→ **本批 0 改动**；队列 7 条断言（连推 5 条不丢 / 点击只关当前条 / 连发短时长…）全绿 |
| 锚点门禁 | `room_ui_permission_test.dart` 的 `table.length, 25` 与 9 个文件里的 `kRoomPolicy.length, 62`（共 10 处）**数值未被放宽**，全部通过 |
| 版本三处 | `pubspec.yaml: 2.45.0+115` / `app_version.dart: kAppVersion='2.45.0', kAppBuildNumber=115` / `local.properties: flutter.versionName=2.45.0, versionCode=115` |
| 静态分析 | `flutter analyze` 本批 3 个文件：**No issues found** |

---

## 6. 遗留风险（均为本批范围外，无阻塞）

1. **更窄于 Android 最小宽度仍会截断**：实测 280×568 仍完整（3 行），**260×480 起标题与副行都截断**
   （副行 28 字 × 15px = 420dp 需要 4 行）。换算阈值：屏宽 < **≈262dp** 时 truncation 复现；
   Android 最小支持 320dp，实际机型无关。
2. **极矮屏**：最坏叠加（3 行标题 + 3 行副行）文字块整块高 ≈201dp。实测 320×568 / 320×480 / 860×400 / **320×320** 全部整块在屏内、
   无 overflow；只有屏高 <≈210dp（分屏极端）才会越界。
3. **未来文案变长没有余量**：3 行已是 `combatStartSubtitle`「4 名字 + 等 N 人」的天花板
   （320dp 下正好 3 行）。若以后允许列 5 个名字或加长措辞，会重新截断 —— 建议届时用本报告的复算口径重测。
4. **继承字距依赖（见第 1 节口径提示）**：若未来把 `bodyMedium` 的 `letterSpacing` 调大，每行能放的字更少、行数会上浮。
   已加「M3 默认 0.25」余量用例；更大幅度的字距变化需要重算。
5. **`textScaler` 钳制未被破坏**：外层注入 3× 字号后，遮罩内段落 `textScaler.scale(10) == 10`、字号仍 26/15、行数不变、
   无 overflow（320×568 与 860×400 各一条用例）。另有既有 `p21` 用例守 1.3/1.5/2.0 三档，均绿。

---

## 7. 附：本报告对应用例清单（`test/qa_245_title_fit_test.dart`，72 条）

- 布局契约常量 2 条（720/32、六档内容宽）
- 320dp 核心回归 5 条（最长标题 3 行复算 / 战斗副行 3 行复算 / 死亡副行 2 行复算 / 9 副行模板仅 1 条需 3 行 / M3 字距最坏主题）
- 9 模板 × 6 宽度 = 54 条（逐条：排版宽度契约、字号行高、双路径行数互印、不截断、maxLines 覆盖、占位高度、无异常）
- 文字块整块在屏内 4 条（320×568 / 320×480 / 860×400 四边不越界 + 320×568 整块高度构成）
- 宽屏不许凭空多一行 5 条（360/375/400/412/860）
- textScaler 钳 1.0 未被破坏 2 条（320×568 / 860×400）
