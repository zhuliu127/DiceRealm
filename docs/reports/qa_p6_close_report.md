# QA 独立回归复核报告 · 骰境 TRPG P6 收尾批次

**复核人**：严过关（QA / software-qa-engineer）
**日期**：2026-11-09
**工程**：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
**复核基调**：不采信工程师的截图与自报日志，全部自己跑、自己怀疑、自己证伪。
**轮次**：Round 1（判定两条功能性 bug → 路由 Engineer）＋ Round 2（硬上限最后一轮：验修复 / 独立出包 / 刷新清单指纹）→ **最终结论见 §0-A 与 §8**，两轮硬上限已闭合，不开第三轮。
**前置**：每条测试命令前 `unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy` + `export NO_PROXY=127.0.0.1,localhost` + `export PATH=/d/dev/flutter/bin:$PATH`；`build` junction 未删、未 `flutter clean`；未跑 adb / 模拟器 / 真机联调。

---

## 0-A. Round 2 最终结论（硬上限最后一轮）

| 项 | 结果 |
|---|---|
| 全量 `flutter test`（默认并发） | `01:01 +1475: All tests passed!`，0 红，EXIT=0 |
| 全量 `flutter test --concurrency=1`（串行复核） | `03:23 +1475: All tests passed!`，0 红，EXIT=0 |
| 反向验证①②恢复后最终全量 | `00:52 +1475: All tests passed!`，EXIT=0 |
| `dart analyze` | `No issues found!` |
| P4 门禁 / P5 UI 门禁 | `13 条 0 失败 IS_PASS: YES` / `14 条 0 失败 IS_PASS: YES`（`lib/ui/room` 62 个 .dart / 14674 行） |
| 独立出包（QA 自己跑 `bash tool/build_apk.sh`） | **新 SHA256 `e81eae681090f8980cbe2f5a29d6effe3439c4279c84b368f24459d20199d2c2`** / 60,521,003 字节 / 57.7MB / 三 ABI 带 `libapp.so` / `GOOD(>=50MB)` / `enable-native-assets: true` 已恢复 |
| 1475 账目 | **算平**：1454 + 2 + 2 + 17 = 1475；`room_sync_epoch_test.dart` 动态注册 `12−1+6=17`（§8.2 独立核验，含排除第二处非注册循环） |
| 两条缺陷是否真反转 | **是**。QA 自建 `_qa_r2_probe_test.dart` 用 `RoomUiFixture` 真实 intent 独立复现 9 条全绿；限制 2 漏 1~6 事件两列都不闪、限制 3 `jump=10` 仍必须闪（详见 §8.3） |
| `deliverForTest()` 自证循环判定 | **不是自证循环**（生产代码零调用，投帧口只跳过 socket、被测逻辑全是生产代码；widget 组用真 `host.syncFor()` 信封）。残留边界如实写入 §8.5 |
| 反向验证①② | **均成立**：epoch 恒 0 → `+1468 -7`（7 红）；加回 seq 差判据 → `+1469 -6`（6 红）；两文件 diff + sha256 双证逐字节还原，复跑全绿 |
| 覆盖与红线 | `syncEpoch` 三条补拉路径全覆盖、无漏网路径；判据唯一来源仍在 `check()`；`lib/domain/**`、`pubspec.yaml`、传输帧协议（K3）零改动；零新增 `jsStr(` / `Timer` / `Future.delayed` / `AnimationController`；`build` junction 完好；两个 `const GpFeeds(...)` 未改 |
| 自动化回归 | **PASS** |
| 最终智能路由 | **Send To: NoOne**（源码 Bug 0 条待修；测试代码问题 0 条；Round 1 两条缺陷已修并独立验证） |
| **整体 IS_PASS** | **YES** |

> §0 与 §6 / §7 为 **Round 1 时点结论（IS_PASS: NO 有条件 / 路由 Engineer）**，保留作审计轨迹；
> 已被本表与 §8 的 Round 2 结论**取代**。真机待测项按用户要求「全部做完再统一测」全部保留，未删一条。

---

## 0. 结论速览（Round 1 历史，保留作审计轨迹）

| 项 | 结果 |
|---|---|
| 全量 `flutter test`（默认并发） | `00:58 +1454: All tests passed!`，0 红，EXIT=0 |
| 全量 `flutter test --concurrency=1`（串行复核） | `03:27 +1454: All tests passed!`，0 红，EXIT=0 |
| 恢复源码后第三次全量 | `00:55 +1454: All tests passed!`，0 红，EXIT=0 |
| `dart analyze` | `No issues found!` |
| P4 门禁 / P5 UI 门禁 | `13 条 0 失败 IS_PASS: YES` / `14 条 0 失败 IS_PASS: YES` |
| 出包 | 57.7MB / 60,521,003 字节 / SHA256 `800a08c3…` / 三 ABI 带 `libapp.so` / native-assets 已恢复 true |
| 1454 账目 | **算平**：1422 + 7 + 25 = 1454，每个增量均单文件实测 |
| 反向验证 / 自证伪 | 成立：摘掉接线 → `+4 -4`（4 正例全红、4 负例仍绿），恢复后逐字节一致并复跑全绿 |
| 两条遗留限制 | **均判定为功能性 bug（真缺陷），非设计取舍** → 路由 Engineer |
| 自动化回归 | **PASS** |
| 整体 IS_PASS | **NO（有条件）**：两条缺陷需工程师修复后再跑 Round 2；若按工期接受须落 Known Issues |

---

## 1. 四条原始输出（独立重跑，末几行摘录）

### 1.1 `flutter test` 全量（默认并发，清 proxy 后）

```
00:56 +1453: C:/.../test/step_background_test.dart: 疯狂表第 9 条（恐惧症）点开 100 条子表
00:58 +1454: All tests passed!
=== EXITCODE=0 ===
```

### 1.2 `flutter test --concurrency=1` 串行复核

```
03:27 +1453: C:/.../test/wizard_steps_test.dart: 校验函数（从页面搬出来后行为不变） 非必填步骤永远放行
03:27 +1454: All tests passed!
=== EXITCODE=0 ===
```

> 串行复核是为确认工程师所说的「首轮默认并发 flutter_tester 残留挂起」不是稳定复现的环境问题。
> 结果：默认并发 00:58、串行 03:27、恢复后 00:55，**三遍全绿、零挂起**，未出现任何 `Connection closed before test suite loaded`。

### 1.3 `dart analyze`

```
Analyzing dice-realm...
No issues found!
ANALYZE_EXIT=0
```

### 1.4 两道静态门禁

```
=== P4 GATE ===
==== 合计 13 条，失败 0 条 ====
P4_GATE IS_PASS: YES
P4_EXIT=0

=== P5 UI GATE ===
[OK]   弹层不走裸 showDialog / 扫描 62 个文件，零命中
==== 合计 14 条，失败 0 条 ====
P5_UI_GATE IS_PASS: YES
[OK] lib/ui/room 共 62 个 .dart / 14619 行；view/ 6 个 / 1032 行
P5_EXIT=0
```

### 1.5 `bash tool/build_apk.sh` 出包 + 独立复核

```
√ Built build\app\outputs\flutter-apk\app-release.apk (57.7MB)
  8323976  lib/arm64-v8a/libapp.so
  9224776  lib/armeabi-v7a/libapp.so
  8520584  lib/x86_64/libapp.so
[4/4] 恢复 native assets（否则 flutter test 跑不了）
===== 出包成功 =====
-rw-r--r-- 60521003 ... app-release.apk
800a08c3d512f5a21245985cf1ff188eb01833ae15b047157de6dea2d7e7f5fa *...app-release.apk
=== BUILD_EXIT=0 ===
```

**不采信脚本自报，另跑一遍独立校验**：

```
60521003  build/app/outputs/flutter-apk/app-release.apk
800a08c3d512f5a21245985cf1ff188eb01833ae15b047157de6dea2d7e7f5fa *...app-release.apk
  8323976  lib/arm64-v8a/libapp.so
  9224776  lib/armeabi-v7a/libapp.so
  8520584  lib/x86_64/libapp.so
bytes=60521003  VERDICT=GOOD(>=50MB)
enable-native-assets: true
```

> 字节数、SHA256、三 ABI 与工程师 `_p6_transport9.txt` 报的 `800a08c3…` / 60,521,003 / 57.7MB **完全一致**；
> 出包后 `flutter config --list` 确认 `enable-native-assets: true` 已恢复（后续 `flutter test` 能跑也反证了这一点）。

---

## 2. 测试账目核对（重点，独立算平）

工程师的说法：19:08 基线 1422 → 本批新增 25 → 应为 1447，实际 1454，多出 7 条解释为「19:15 `room_notice_overlay_test.dart` 的改动未计入 19:08 基线」。

**我逐项独立核对（不采信该解释，先取证）**：

| 环节 | 证据 | 数值 |
|---|---|---|
| 19:08 基线 | `_p6_transport8.txt` 第 5 行「全量：1422 组 0 红（1394 → +28）」 | 1422 |
| 19:15 增量 | `test/room_notice_overlay_test.dart` mtime = **2026-11-09 19:15**（晚于基线 7 分钟）；单文件实跑 `00:01 +7: All tests passed!`；静态 `test/testWidgets` 计数也是 7 | **+7** |
| 本批新增 | `room_feed_flash_test.dart` 12 + `room_feed_flash_wiring_test.dart` 8 + `sheet_music_test.dart` 5；三文件**合跑实测** `00:01 +25: All tests passed!` | **+25** |
| 本批改断言 | `test/room_ui_entry_test.dart` 22 条，只翻转断言、**条数不变** | ±0 |

**算式：1422 + 7 + 25 = 1454 ✓ 完全对上。**

反证：若按最初口径「1422 + 25」只有 1447，比实际少 **7**，恰好等于 notice 文件的 7 条 → 工程师的解释**成立**，不存在「为了绿而删/放宽用例凑数」。

**额外不放过计数差**：

- 静态正则 `^\s*(test|testWidgets)\s*\(` 扫全库 `test/`（107 个 .dart）得 **1179** 条，与实测 1454 差 275。差异来自 `for` 循环动态注册的表驱动用例（`wizard_steps` / `step_background` / `qa_probe` 等），**不是计数黑洞**；本批 3 个新文件无动态注册，静态数 = 实测数（12/8/5），所以「+25」可信。
- 工程**无 `.git`**（无法逐文件 diff），改用 mtime 交叉核对：19:08（UTC 11:08）之后被改的测试文件**只有 4 个**（3 新 + `room_ui_entry_test.dart` 改），与工程师报的文件清单完全一致；`lib/domain/**` 50 个文件在该时点后**零改动**。
- `room_feed_flash.dart`（判据类）mtime 19:17，是本批接线依赖的纯类、不带用例，不影响计数。

---

## 3. 断言复核与自证伪过程

### 3.1 `room_ui_entry_test.dart` 被翻转的断言：覆盖面**扩大**，不是缩小

- 原断言（2 条）：`music.enabled == false`、`hint` 含 `P2` —— 守的是「占位存在」。
- 现断言（7 条，第 708-721 行）：`enabled isTrue`、`onTap isNotNull`、`hint` 不含「下一期」/不含 `P2`/含「本机」、`musicSection` 不含「下一期」、`ai.enabled isFalse`（防止把 AI RP 的禁用指引一起误删）。
- 判断：**从「守占位」翻成「守真入口」，断言数 2→7，覆盖面扩大**。
- 是否补了「入口真能打开面板」？**单看这一条没有**，但新增 `sheet_music_test.dart` 第 71-140 行补上了：`tester.tap(MiscSheetKeys.musicEntry)` → `MusicSheetKeys.root findsOneWidget`、8 个说明 key 逐一存在、弹层内 `find.byType(RoomTap) findsNothing`。**跨文件合计覆盖完整**，不存在「只改断言不补行为」。

### 3.2 `sheet_music_test.dart`「零发包」是真断言，不是文案检查

第 142-171 行打开弹层前后逐项对比四个真值：`f.sent.length`、`f.sessionOf(kHostSeat).lastSeq`、`jsonEncode(f.stateOf(kHostSeat))`、`f.localOf(kHostSeat).notice`。另有静态口径测试（第 174-235 行）：扫 `sheet_music.dart` 禁用词（`dart:io` / `http` / `AiClient` / `sendIntent` / `hostAction` / `showDialog` / `Timer` / `Future.delayed` / `AnimationController` 全零命中），并按门禁同款口径剥掉 `//` 注释后扫全 `lib/ui/room/` 代码行的「下一期 / 后续版本提供」。

### 3.3 `sheet_music.dart` 无假按钮（K7）、结构性纯本机

整个 widget 树只有 `Text` / `Column` / `SizedBox`；Grep `RoomTap(|enabled: false|onTap|sendIntent|hostAction|RoomScope|http|Timer` **仅命中第 47 行注释**（说明「不读 RoomScope」），零实际调用。不读 `RoomScope`、不发包、不碰 state、不发网络请求；文案明说「不打包任何音频 / 没有内置播放器 / 放一个点了没反应的按钮就是骗人」，并给出「系统音乐 App 后台播放 + 音量键」的可执行做法。不宣称播放成功、无禁用假按钮。

### 3.4 `room_feed_flash_wiring_test.dart` 反向验证不是恒绿断言

`_NeverFlash extends FeedFlashTracker` 的 `check()` 恒返回 `false` 且带 `calls` 计数（断言 `calls > 0` → 证明判据**确实被调用**，不是压根没接线）；与之成对的第 244-274 行「同一棵树把判据换回默认 → 角标重新出现」，证明差别只在判据、不由 pump 次数等恒真条件决定。**有效反向验证，非恒绿。**

### 3.5 我自己再证伪一次（摘掉接线）+ 恢复

1. 备份 `lib/ui/room/widgets/gp_feeds.dart` → `/tmp/qa_p6_gp_feeds.orig`（sha256 `87d0ef96…`）。
2. 字面把第 171 行 `if (flashing)` 改成 `if (false && flashing)`（Grep 确认该条件全文件唯一）。
3. 单跑 8 组接线测试：

```
00:01 +4 -4: Some tests failed.
=== NEGATION_EXIT=1 ===
Failing tests:
  ★★ 同一棵树里把判据从「恒不闪」换回默认 → 角标重新出现
  ★ 两个 pane 各持一个 tracker（聊天闪不会带闪记录）
  ★ 来一条别人的消息 → 角标出现
  ★ 点一下角标即收起（消退不需要 Timer）
Expected: exactly one matching candidate
  Actual: _KeyWidgetFinder:<Found 0 widgets with key [<'gpFeeds/flash/chat'>]: []>
```

**4 条正例全红、4 条负例（历史首屏 / 自己发的 / 7 条涌入 / 恒不闪判据）仍绿**，与工程师声称一致 → 「忘了挂」确实会被测出来。

4. **原样恢复**：`cp` 备份回写，`diff -q` → `RESTORE_DIFF=IDENTICAL`、sha256 仍 `87d0ef96…`、第 171 行回到 `if (flashing)`；临时取证文件 `NO_PROBE_FILE`（已删）。
5. **复跑全量**：`00:55 +1454: All tests passed!`，EXIT=0。

> 说明：自证伪期间对 `gp_feeds.dart` 的临时改动已**逐字节还原**，最终工程源码与交付态无差异；未改动工程师写的任何源码。

### 3.6 全局扫描

| 项 | 结果 |
|---|---|
| 本批 4 个 UI 文件 `jsStr(` | **零命中**（沿用 `roomText` 口径，未加白名单） |
| `LogRecord.toWireJson()` 调用 | 全库仅 1 处定义 + 6 处注释，**零调用**（K3 守住） |
| `lib/domain/**` | 50 个 dart 文件，19:08 后**零改动** |
| `pubspec.yaml` | mtime 仍 `2026-11-08 18:55`，未动 |
| `build` 链接 | `build -> /d/dev/dice-build`，完好；未 `flutter clean` |
| 全 room/ 的「下一期 / 后续版本提供」 | 仅 4 处**注释**（`room_entry_page.dart:7`、`gp_pl_char_card.dart:233`、`sheet_misc.dart:40/43`），无用户可见字面量 |

### 3.7 关于工程师「中止日志 `-1`」的自洽判定（主理人中转项）

- `/tmp/p6_full_test.log` 确实存在，尾部 `10:35 +1423 -1: Some tests failed.` + `room_model_core_test.dart: loading …`。按派工要求**未采信、不作验收依据**，已删除（`DELETE_DONE=yes`）。
- 我自己的三份全量日志（default / serial / final）grep `Connection closed|Failed to load|Some tests failed|-[0-9]+:` → **零命中**，三份尾行均为 `+1454: All tests passed!`。
- **判定：该解释与我的观察自洽。** 默认并发、串行、恢复后共 3 遍干净重跑从未出现该断连；它只发生在「人为杀掉卡住的 `flutter_tester.exe`」之后，属**一次性中止副作用（worker 断连），不可稳定复现**，不是断言失败、不是 flaky、不是本批代码问题。清 proxy 后默认并发 00:58 就干净跑完，也反证了根因是代理变量拦本地 WebSocket。

---

## 4. 两条遗留限制的判定与证据

取证方式：临时文件 `test/_qa_p6_probe_test.dart`（QA 临时取证，**跑完即删**），断言的是「当前实现的实际行为」；跑完 `00:00 +3: All tests passed!`（全绿 = 缺陷可复现），并打印 `QA_PROBE_LIMIT3 base=7 now=15 jump=8`。

### 4.1 限制 2：`reset()` 只接 session 对象替换 → **真缺陷，需回工程师修**

**代码链**：

- `_p6_design.md §5.1`：「重连成功后必补一次全量——断线期间漏掉的事件不能靠增量补回来」。
- `lib/net/lan_client.dart:289-294`：`_scheduleRetry()` 重连成功后只 `requestSync()`；座位未变时 `client` 不重建（第 176-179 行只在 `assigned != seat` 才换）。
- `lib/ui/room/room_session_remote.dart:35,55`：`onChange = _notify`（只 `notifyListeners()`），`state => _client.client.state` —— **`RemoteSession` 对象自始至终不换**。
- `lib/ui/room/widgets/gp_feeds.dart:149`：`identical(scope.session, _boundSession)` 因此为真 → **不调 `reset()`**。
- `lib/ui/room/room_feed_flash.dart:60`：`if (lastSeq - prev > floodThreshold) return false`，**只在跳跃 > 6 时抑制**。

**复现**：短断线只漏 3 个事件时，补拉后聊天列末条 seq 从 10 → 13（≤6）且是别人发的 → `check()` 返回 **true（误闪）**。取证用例实测通过。

**判定：真缺陷，不是设计取舍。** 验收项「断线重连补拉不闪」在短断线（漏 1~6 个事件）时**必然被违反**，而 `floodThreshold=6` 兜底对短断线无效。工程师自己也在限制 2 里承认「感知不到对象替换、不会显式 reset」。设计 §5.1 明确必补全量，这条路径正是真机 P0 清单第 10 步（飞行模式 10 秒）会走到的。

### 4.2 限制 3：全局 seq 与 pane 局部序列错配 → **真缺陷（功能性 bug）**

**代码链**：

- `lib/domain/room_model_reduce.dart`：chats / logs / dice 每条都写 `'seq': evt.seq`（**全局事件序号**），末尾 `state['seq'] = evt.seq`。
- `lib/ui/room/view/feed_view.dart:112-127`：`collectChats` 取 `r['seq']`（同一套全局序号），按 `at` 排序取末条。
- `gp_feeds.dart:130-141`：`_deriveFlash` 把 `items.last.seq` 交给 `check()`；`check()` 用 `lastSeq - prev > 6` 判「补拉」。
- 阈值 6 隐含的却是「**每列自己的序号**」。

**复现（多列交错，真实消息流）**：`RoomUiFixture` 真实 intent 造「2 条历史聊天 → 7 条公开骰（record 列）→ 1 条别人新聊天」，打印

```
QA_PROBE_LIMIT3 base=7 now=15 jump=8
```

聊天列末条 seq 跳跃 8（>6），`GpFeedsKeys.flash(FeedPane.chat)` **findsNothing**（PRD 期望 `findsOneWidget`）。取证 3 条用例全绿 = 缺陷可稳定复现。

**判定：功能性 bug，不是「已知限制」**，三条理由：

1. 这是**正常在线**场景（不是重连），直接违反 PRD `_p5_prd.md:763` P2-05「feed 新增闪烁」与真机验收「别人发消息出现『新』角标」。
2. 旧版 `room-ui.js:3748 feedFlashCheck` 只有「首次登记基线 + `lastChat.seat !== mySeat`」两条规则，**没有 flood 抑制**，不会漏闪（工程师 `_p6_transport9.txt` 自己也写明「旧版只在操作播报里做了这个保护，闪烁这边漏了」）。本批新加的 flood 规则与全局 seq 数据模型错配，是**本批引入的功能退化**。
3. 「派工要求不改判据、不在 UI 另写一套判断」是**实现约束**，不能把需求违约转写成「已知限制」。

### 4.3 修法方向（仅建议，不越权改工程师源码）

- **限制 2**：给 `RoomSession` 暴露「重连 / 补拉完成」信号（epoch 或回调），`GpFeeds` 在该信号上显式 `reset()`；不要靠 seq 跳跃去猜「是不是补拉」。
- **限制 3**：tracker 的 flood 判据改用**每列自己的序号 / 新增条数**（如 `items.length` 差值或 per-pane 局部计数），而不是全局事件 seq 差值；或由 UI 传「本列新增条数」。
- 两条都需补对应回归用例（含反向验证），修复后由 QA 跑 Round 2。

---

## 5. 真机清单 `_manual_test_checklist.md` 更新点

保持原有风格与 P0/P1/P2 分级，**未重写整篇、未删任何既有条目**：

1. **头部 APK 信息**：`57.6MB / 60,439,083 / 558a3b2c…` → `57.7MB / 60,521,003 字节 / 三 ABI 均带 libapp.so / SHA256 800a08c3…`（值为我独立复核后填入），并加注「P6 收尾批次数据经 QA 独立复核后订正」。
2. **新增 3 个 P2 待测小节**（均为可操作表格，只登记、不执行）：
   - `P2 · 信息流闪烁（P2-05）` 5 条：历史首屏不闪 / 别人发消息出「新」角标 / 自己发的不闪 / **断线重连补拉不闪** / 聊天与记录两列互不干扰。
   - `P2 · 音乐控制台（P2-03）` 5 条：更多工具能打开 / 内容如实（不联网·不打包音频·需系统播放器自备）/ **没有假按钮** / 点开零网络请求零房间状态改动 / 系统播放器后台播放不受接管。
   - `P2 · AI RP 指引修正` 3 条：角色卡 U9 占位改正确指引 / 更多工具禁用指引一致 / **顺带确认聊天输入行 ✨ 仍可用**。
3. **尾部「自动化已验证」**：`1341 组` → `1454 组`；`P5 UI 15 条` → `14 条`（P4 仍 13 条）。
4. **排查表第 60 行**：「也可能是多播锁问题」→「也可能是 ROM 拦了 UDP 广播（多播锁本版已实现）」，消除「当前没做」的误读。
5. **逐条核查「已知技术债」1~4**：第 1 条「Android 多播锁**已实现**，但需真机确认效果」、第 2 条「存档**已落盘**」**本来就已与现状一致，无需订正**；第 3 条 K16、第 4 条 debug 签名亦一致。真正写着「当前没做 / 多播锁未申请」的是 `_p6_design.md §11` 与另一工作区 `overview.md` 第 187-188 行——**不在本次授权修改范围，仅记录，不擅自改工程外文件**。

---

## 6. 智能路由结论（Round 1 历史，已由 §8.8 取代）

> 本章为 Round 1 时点判定。两条源码 Bug 已在 Round 2 修复并独立验证，最终路由见 §8.8。

| 判定 | 结论 |
|---|---|
| 源码 Bug | **有，2 条**（限制 2 重连补拉误闪、限制 3 全局 seq 错配漏闪）→ **Send To: Engineer（经 team-lead 中转，未直接联系工程师、未改其源码）** |
| 测试代码问题 | **无**：新增断言覆盖面扩大、反向验证有效、零发包是真值断言、自证伪成立；无需 QA 自修 |
| 自动化回归 | **PASS**：1454 组 0 红 ×3 遍、analyze 零问题、门禁 13/13 + 14/14、出包三 ABI 与 SHA256 对账一致、账目算平、无「为了绿而放宽」 |
| 整体 | **IS_PASS: NO（有条件）** —— 不建议以「IS_PASS: YES」直接收尾；两条缺陷需工程师修复后再跑 Round 2 回归。若主理人基于工期决定本批接受，必须把它们写进 Known Issues，并依赖真机清单「信息流闪烁」第 4 / 第 5 条重点验，不能当「已实现」交付 |

**测试轮次控制**：Round 1 已完成（写/跑/分析/路由 + 独立证伪）；**未进入 Round 2**（源码修复尚未发生，2 轮硬上限保留给修复后的回归）。

---

## 7. 遗留问题 / Known Issues（Round 1 历史；Round 2 更新版见 §8.9）

> 第 1、2 条已在 Round 2 修复闭环，以下保留作审计轨迹，不再是待修缺陷。

1. **限制 2**（短断线重连补拉误闪）—— Round 1 待工程师修，见 §4.1；**Round 2 已修并验证**（§8.3）。
2. **限制 3**（正常在线、聊天间夹 >6 条日志/骰子时新消息不闪）—— Round 1 待工程师修，见 §4.2；**Round 2 已修并验证**（§8.3）。
3. P2-05 三条子项（逐条播报 3 条堆叠 / 角标持续脉冲 / 轮次提示音）依 `_p5_design.md:1858` U7 裁决与 fake-async Timer/动画悬挂风险未做，且**无假入口** → **设计取舍，接受**。
4. P2-06「导出文本」未移植（只读历史已落地，无禁用占位）→ **如实缺口，接受**。
5. 空房间第一条消息不闪（判据规则 1 的表现，纯逻辑用例有断言）→ **接受**。
6. 音乐控制台不播放音频（依赖冻结 / 不打包音频），做成如实说明面板 → **接受**。
7. K16 奖惩骰语义、debug 签名等前序遗留 → **接受**。
8. **注释级过期表述**：`room_entry_page.dart:7` 仍写「局域网联机在下一期」（P5 时期历史注释，用户不可见，静态门禁按代码行口径放行）；`gp_pl_char_card.dart:233` / `sheet_misc.dart:40,43` 为回顾性注释。建议工程师顺手清理，**非功能缺陷**。
9. **工程外**：另一工作区 `overview.md:187` 仍写「多播锁未申请」、`_p6_design.md §11` 仍写「当前没做」，与现状矛盾 —— 仅记录，未越权修改。

---

## 8. Round 2 回归复核（最终轮，QA 独立执行）

> 主理人已亲自核实「工程师有没有改」，本轮不重复排查有无改动，只回答**「改了是否真的解决问题」**。
> 全程未直接联系工程师、未改工程师源码（自证伪临时改动除外，均逐字节还原）、未跑 adb / 模拟器 / 真机联调。

### 8.1 四项自检 + 独立出包（原始输出末几行摘录）

**预设**：每条测试命令前 `unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy` + `export NO_PROXY=127.0.0.1,localhost` + `export PATH=/d/dev/flutter/bin:$PATH`。

```
=== 8.1.1 flutter test（默认并发） /tmp/qa_r2_default.log ===
00:59 +1474: C:/.../test/step_background_test.dart: 疯狂表第 9 条（恐惧症）点开 100 条子表
01:01 +1475: All tests passed!

=== 8.1.2 flutter test --concurrency=1（串行） /tmp/qa_r2_serial.log ===
03:23 +1474: C:/.../test/wizard_steps_test.dart: 校验函数（从页面搬出来后行为不变） 非必填步骤永远放行
03:23 +1475: All tests passed!

=== 8.1.3 dart analyze /tmp/qa_r2_analyze.log ===
Analyzing dice-realm...
No issues found!

=== 8.1.4 两道静态门禁 /tmp/qa_r2_p4.log / qa_r2_p5.log ===
==== 合计 13 条，失败 0 条 ====          P4_GATE IS_PASS: YES
==== 合计 14 条，失败 0 条 ====          P5_UI_GATE IS_PASS: YES
[OK] lib/ui/room 共 62 个 .dart / 14674 行；view/ 6 个 / 1032 行

=== 8.1.5 bash tool/build_apk.sh（QA 独立出包） /tmp/qa_r2_build.log ===
[3/4] 校验 AOT 产物
  8323976  lib/arm64-v8a/libapp.so
  9224776  lib/armeabi-v7a/libapp.so
  8520584  lib/x86_64/libapp.so
[4/4] 恢复 native assets（否则 flutter test 跑不了）
===== 出包成功 =====
=== BUILD_EXIT=0 ===
BYTES=60521003
e81eae681090f8980cbe2f5a29d6effe3439c4279c84b368f24459d20199d2c2 *...app-release.apk
GOOD(>=50MB)
  enable-native-assets: true
```

**我不采信脚本自报，另跑一遍独立校验**（`stat` / `sha256sum` / `unzip -l` / `flutter config --list`），结果与上一致；三 ABI 齐全，`enable-native-assets: true` 已恢复。出包后再跑单文件冒烟 `test/room_sync_epoch_test.dart` → `POSTBUILD_SMOKE_EXIT=0` / `+17: All tests passed!`，反证恢复生效、后续 `flutter test` 仍能跑。

> **补洞结论**：Round 1 仓库里的 APK 是 `800a08c3…`（工程师出包），**不对应 Round 2 当前源码**。本轮新包 SHA256 已变为 `e81eae68…`，字节数仍是 60,521,003（AOT 产物尺寸一致、内容已变），且 ≥50MB、三 ABI 齐全 → 这是**对应当前源码的可用包**，已据此刷新真机清单头部指纹。
> 四份干净全量日志（default / serial / final / postbuild-smoke）grep `Connection closed|Failed to load|Invalid WebSocket|Some tests failed` → **零命中**（`ZERO_HIT`），未出现 Round 1 那次「中止 worker 断连」。

### 8.2 账目核对 1454 → 1475（重点：动态注册，独立算平）

主理人给的算式是 `12−1+6=17`。我**没有照抄**：先扫出 `room_sync_epoch_test.dart` 里其实有**两处** `for` 循环（`:116`、` :310`），逐一读代码判定哪一处才是用例注册：

- `:116 for (final row in rows)` 在 `_maxChatAt()` 里遍历 `state['chats']` 求最大 `at`，**不是用例注册**，不参与展开。
- `:310 for (final miss in const <int>[1,2,3,4,5,6])` 循环体内 `:311` 只有一个 `testWidgets('★ 短断线漏 $miss 个事件…')` 占位，展开成 **6** 条。

精确列举静态定义（12 处）：

```
208 215 226 238 249 264 275 289 311 358 400 432   → 共 12
```

其中只有 `311` 在 `:310` 循环体内 → **静态 12 − 循环占位 1 + 循环展开 6 = 17**。

单文件实测（我自己跑，不采信工程师）：

```
/tmp/qa_r2_ledger_room_feed_flash_test.log          00:00 +14: All tests passed!
/tmp/qa_r2_ledger_room_feed_flash_wiring_test.log   00:01 +10: All tests passed!
/tmp/qa_r2_ledger_room_sync_epoch_test.log          00:01 +17: All tests passed!
```

| 环节 | 静态 | 实测 | 增量 |
|---|---|---|---|
| `room_feed_flash_test.dart` | 14 | **14** | 12 → 14（+2） |
| `room_feed_flash_wiring_test.dart` | 10 | **10** | 8 → 10（+2） |
| `room_sync_epoch_test.dart`（新增） | 12 | **17** | +17（动态注册） |

**算式 `1454 + 2 + 2 + 17 = 1475` ✓ 成立**，与默认并发、串行、恢复后三份全量的 `+1475` 完全对上。**无任何计数差**，不存在用「环境抖动」带过的地方。静态定义数与实测数的差（12 vs 17）全部由 `:310` 表驱动循环解释，没有黑洞。

### 8.3 两条缺陷是否真的反转（QA 自建复现，不跑工程师现成用例）

按 Round 1 §4 的原始复现方式，我另写临时取证文件 `test/_qa_r2_probe_test.dart`（**QA 临时文件，跑完即删，`PROBE_REMOVED=yes`**），自己搭 `RoomUiFixture`、用**真实 intent** 造宿主数据，再经 `f.host.syncFor(kHostSeat).toJson()` → `LanClient.deliverForTest` → `RemoteSession` → `GpFeeds` 全链路，实测 `00:01 +9: All tests passed!`：

```
00:01 +5: QA-R2 独立取证 · 限制 2  漏 4 个事件：重连补拉后聊天列 + 记录列都不闪
00:01 +6: QA-R2 独立取证 · 限制 2  漏 5 个事件：重连补拉后聊天列 + 记录列都不闪
00:01 +7: QA-R2 独立取证 · 限制 2  漏 6 个事件：重连补拉后聊天列 + 记录列都不闪
00:01 +8: QA-R2 独立取证 · 限制 2  ★ 补拉 reset 后本次 build 重新登记基线，再来一条增量仍闪
00:01 +9: All tests passed!
```

**限制 2（短断线补拉误闪）→ 已反转**：漏 1/2/3/4/5/6 个事件，重连补拉后 `expect(lan.syncEpoch, 2)` / `expect(rs.syncEpoch, 2)`，聊天列与记录列均 `findsNothing`。Round 1 这里 seq 差够不到阈值必然误闪。第 9 条专门防止「修成永远不闪」——补拉 reset 后本次 build 重新登记基线，再来一条别人增量 `findsOneWidget`，**基线重登记有效**。

**限制 3（全局 seq 错配漏闪）→ 已反转**：2 条历史聊天 → 7 条公开骰 → 1 条别人新聊天，打印 `QA_R2_LIMIT3 base=7 now=17 jump=10`（差值比 Round 1 的 `jump=8` 更大，仍 >6），chat 角标 **`findsOneWidget`**；对照 Round 1 同场景 `findsNothing`（漏闪）。「只来记录、不来聊天 → chat 不闪」两列互不干扰亦成立。

> 差异来源：旧 `check()` 有 `if (lastSeq - prev > 6) return false`，把「差值大」当成补拉；现在该规则整体退役，补拉改由连接层 `syncEpoch` 显式告知，`check()` 只回答「有没有新条目、是不是自己发的」。

### 8.4 反向验证（我自己再做一遍，不采信工程师 `+10 -7` / `+35 -6`）

两处临时改动都在跑完后由同一条命令 `cp` 备份还原，并 `diff -q` + `sha256sum` 双证：

**① `gp_feeds.dart` epoch 读取改恒 0**：`final int epoch = scope.session.syncEpoch;` → `final int epoch = 0;`（注释标明临时）

```
=== NEG1_EXIT=1 ===
00:54 +1468 -7: Some tests failed.
  C:/.../test/room_sync_epoch_test.dart: Round 2 · 限制 2（短断线补拉误闪） ★ 短断线漏 1 个事件…
  … 漏 2 / 3 / 4 … and 3 more
RESTORE1=IDENTICAL
7169faf72f97f8174fa1d9bec90d6cf8c40b49aa877fa7bab47f290b31793146 *lib/ui/room/widgets/gp_feeds.dart
```

7 条全红且**全是限制 2 用例**（漏 1~6 共 6 条 + reset 后增量 1 条），负例仍绿 → epoch 信号确实是限制 2 修复的唯一依赖，不是摆设。

**② `room_feed_flash.dart` 加回 `if (lastSeq - prev > 6) return false;`**：

```
=== NEG2_EXIT=1 ===
00:52 +1469 -6: Some tests failed.
Failing tests:
  room_feed_flash_test.dart: ★ 判据退役：+6 / +7 / +30 只要是新条目且别人发的，都该闪
  room_feed_flash_test.dart: ★ 大跳跃不再抑制这一批，基线仍推进，下一次 +1 仍闪
  room_feed_flash_test.dart: ★ 阈值参数已彻底移除：无参构造，不同差值行为完全一致
  room_feed_flash_wiring_test.dart: ★ 一次涌入 7 条（正常在线、没有补拉信号）→ 仍该闪
  ... and 2 more
RESTORE2=IDENTICAL
7169faf7…  *lib/ui/room/widgets/gp_feeds.dart
7169faf7…  */tmp/qa_r2_gp_feeds.orig
c8c27233…  *lib/ui/room/room_feed_flash.dart
c8c27233…  */tmp/qa_r2_flash.orig
```

6 条全红且**全是限制 3 判据退役 / 接线用例**，负例仍绿 → seq 差规则确实已不在活代码里。

**恢复自证与最终全绿**：两文件 sha256 与备份逐字节一致（`RESTORE1/2=IDENTICAL`）；当前 `gp_feeds.dart:159` 为 `final int epoch = scope.session.syncEpoch;`，`room_feed_flash.dart` 中 `floodThreshold|lastSeq - prev` 仅 `:9` 一条**历史注释**（活代码零命中）；临时 probe 已删。恢复后全量 `FINAL_EXIT=0` / `00:52 +1475: All tests passed!`。

### 8.5 `deliverForTest()` 是否让测试自证循环 —— 明确判定：**不是**

主理人特别点名要「别默认接受」，我按四条逐一取证：

1. **后门调用点全库 grep**：`lib/net/lan_client.dart:249` 定义 1 处（`@visibleForTesting void deliverForTest(Map<String,Object?> msg) => _deliver(msg);`），调用点**全部**在 `test/room_sync_epoch_test.dart`（21 处，含 1 行注释）。**`lib/` 下生产代码零调用**，不是产品代码里埋的旁路。
2. **信封是否生产级合法全量**：`RoomHost.syncFor(String seat)` 定义在 `lib/domain/room_model_host_core.dart:507`，返回真实 `SyncEnvelope`（`makeSync(seat, roomClone(state['scene']))`，按 seat 裁剪）。`SyncEnvelope.toJson()` = `{'k':'sync','seq':seq,'state':state}`。而 `lan_server.dart` 首连 joined 后（`:378-381`）与 sync 请求回包（`:400-406`）都是 `RoomFrame(RoomFrameKind.plan, {'to': seat, 'msg': host.syncFor(seat).toJson()})`；`pump()` 亦用 `SendPlan.toJson()`（`{'to':to,'msg':msg.toJson()}`）发 plan 帧。`lan_client.dart:206-211` 的 plan 分支 `asMap(d['msg'])` → `_deliver(msg)`。**测试 widget 组投的 `f.host.syncFor(kHostSeat).toJson()` 与生产服务端发出的 plan 帧 `msg` 是同一份函数产出、同一形状**，不是测试自造的假信封。
3. **是否绕过真实链路导致「测试绿但真机不通」**：`deliverForTest()` 只跳过 socket 传输层（`WebSocket.connect` / `RoomFrame.parse` / `versionOk`），直接进入生产共用的 `_deliver()` → `client.receive(msg)`（`k=='sync'` 时整体替换 state、设 lastSeq、清 gapFrom）→ `result.kind=='sync'` → `syncEpoch += 1` → `onChange` → `RemoteSession.syncEpoch` → `GpFeeds.build` 的 epoch 判定 → `reset()` → `check()`。**被测的整条判定链全是生产代码，没有在测试里复制实现或硬编码期望**。QA 独立 probe（§8.3）另用 `RoomUiFixture` 真实 intent 造数据，与工程师用例不同夹具，结论一致。
4. **纯逻辑组的 `_syncFrame()` 是否合法**：`:61-97` 用 `SyncEnvelope(seq, {...}).toJson()` 自造同类合法 sync 帧（含 `meta` 为 Map、`chats/logs/dice` 数据源、额外 `mark` 诊断键用于证明 state 被整体替换而非只调大 seq），`:100` 增量用真实 `EvtEnvelope`。形状与 `SyncEnvelope.toJson()` 一致 → 是合法信封，不是绕过 `receive()` 直接改状态。

**判定：不构成自证循环。** 但如实记录两点**残留边界**（不构成缺陷、不判红）：
- 纯逻辑组用自造 `_syncFrame()`（合法同类、带 `mark` 诊断键），只有 **widget 组**用生产 `f.host.syncFor()` 原帧；两类互补，不宜笼统称「全部都是 RoomHost.syncFor」。
- socket 建连 / `RoomFrame` 版本校验 / 服务端是否真会在重连后回全量，这一层由既有 P4 集成测试与**真机 P0 清单第 10 步**（飞行模式 10 秒）覆盖，本批自动化测试没有端到端跑真 socket。按用户要求「全部做完再统一测」留待真机，已列入清单，未删条目。

### 8.6 覆盖与红线复核

**`syncEpoch` 三条补拉路径（全覆盖，无漏网）**：

| 路径 | 代码 | 是否 +1 |
|---|---|---|
| `_scheduleRetry()` 自动重连 | `lan_client.dart:311-322` 重连成功后 `requestSync()` → 服务端 `:400-406` 回 plan 帧 sync envelope → `_deliver()` | ✅ 由 `kind=='sync'` 统一推进 |
| `_deliver()` gap 自愈 | `lan_client.dart:234-237` `body['gap']==true` → `resync` + `requestSync()` → 同上回包 | ✅ 同上 |
| `RemoteSession.pullSync()` 显式 | `room_session_remote.dart:114-118` 只 `_client.requestSync()`（不发状态、不自己 +1） | ✅ 同上 |

自增点唯一收敛在 `lan_client.dart:233 if (result.kind == 'sync') syncEpoch += 1;`，且位于 `onChange?.call()`（`:240`）**之前** → UI 同一次 build 就能读到新世代。三条路径都只发请求、不自增，只有服务端真回全量并 `receive()` 应用完成才 +1，**不会把「resync→connected」误当成已补拉**。

**「补拉已发生但世代没 +1」漏网排查**：
- 首连 joined 后服务端**主动**推全量（`:377-381` 注释「加入即补一份全量」），同样走 plan 帧 → `_deliver()` → `kind=='sync'` → +1（`syncEpoch 0→1`）。测试 `:369` / `:279` 均以此断言 `epoch 1`。
- 服务端主动推全量（intent 无相关事件时兜底）：`room_model_host_intent.dart:140/142` `out.add(SendPlan(seat, syncFor(seat)))`；`room_model_actions_room.dart:1039`、`room_model_rollback.dart:126` 同款出口 → 都经 `pump()` 的 `SendPlan.toJson()` 发 plan 帧 → +1。
- HTTP `/state`（`lan_server.dart:221`）也是 `host.syncFor(seat).toJson()` 同源。
- **结论：未发现任何「全量落地但不经 sync envelope」的路径**，全量一律由 `SyncEnvelope` 承载，`ReceiveResult.sync()` 只在 `k=='sync'` 返回。

**首连 sync 会不会触发多余 reset（`_boundEpoch=-1` → 0/1）**：会触发**一次**。`gp_feeds.dart:112` `_boundEpoch=-1`、`:107` `_boundSession=null`；首屏 build 时 `!identical(session, null)` 或 `epoch != -1` 任一成立即进 reset 分支。但**无副作用**：reset 只做 `_tracker.reset()` + `_checkedSeq=-1` + `_flash=false`，首屏历史本来就该「登记基线不闪」（`check()` 首次返回 `null`）；清 `_checkedSeq=-1` 正是保证**本次** build 仍重新走进 `_deriveFlash` 登记基线，避免补拉后第一条真消息被当成「首次」而漏闪。工程师用例 `:358-393` 与我 §8.3 第 9 条都守住了这条顺序要点。判定：**一次无害的初始化 reset，不是 bug，不需要改**。

**判据唯一来源**：`gp_feeds.dart:142-154` `_deriveFlash()` 只把 `lastSeq/lastSeat/mySeat` 交给 `_tracker.check()`，`_flash` 由 `check()==true` 决定；UI 没有另写「闪/不闪」的第二套判断，`syncEpoch` 只用于 `reset()`。`room_feed_flash.dart:58-76` 的活代码只剩三条守卫（首次 `null`、`lastSeq<=prev`、`lastSeat==mySeat`），`floodThreshold` 字段 / 构造参数 / `lastSeq - prev > ...` **全库 `lib/` 仅 `:9` 一条注释**（`OK_LIB_ZERO` 除注释外零命中）。

**红线（逐项实测）**：

| 项 | 结果 |
|---|---|
| `lib/domain/**` | 4 个核心文件 mtime 均为 `2026-11-08 20:xx`，早于本轮改动（`21:10~22:43`）→ **零改动** |
| `pubspec.yaml` | `2026-11-08 18:55`，未动 |
| 传输帧协议（K3） | `room_frame.dart` / `lan_server.dart` mtime 早于本轮；`toWireJson` 全库仅 `room_types.dart:386` 定义 + 6 处注释，**零调用**；`lan_server.dart:184` 用的是 `SendPlan.toJson()` |
| 零新增 `jsStr(` | 本轮新增/改动的判据与 UI 文件（含 `sheet_music.dart`、3 个新测试）**零命中**；`room_session_remote.dart:85/163/164` 是既有读取（`seats` / `sysTo` 提示），非本批新增 |
| 零 `Timer/Future.delayed/AnimationController` | 新增判据与 UI 零命中；命中项全为**注释**（`gp_feeds.dart:71-72`、`room_feed_flash_wiring_test.dart:10,178` 说明「刻意不用真实 Timer」）；`lan_client.dart:74,316` 的 Timer 是既有重连退避，与本批无关 |
| `build` junction | `build -> /d/dev/dice-build`，完好；未 `flutter clean` |
| `room_game_page.dart` 两个 const 调用 | `:373 const GpFeeds(pane: FeedPane.chat)` / `:376 const GpFeeds(pane: FeedPane.record)` 原样未改（mtime `12:40` 早于本轮） |

### 8.7 真机清单 `_manual_test_checklist.md` 本轮更新点

保持原有风格与 P0/P1/P2 分级，**未重写整篇、未删任何条目**：

1. **头部 APK 指纹**：`800a08c3…` → QA 独立出包的 **`e81eae68…`**，字节数 60,521,003 / 57.7MB / 三 ABI / debug 签名保留；新增一行「最近一次订正：Round 2 修复回归后由 QA 独立重新出包并刷新指纹」。
2. **尾部「自动化已验证」**：`1454 组` → **`1475 组`**，证据列补「Round 2 修复后复跑」。
3. **P2-05 信息流闪烁表**：小节导语补「Round 2 已改 `syncEpoch` 显式补拉信号、退役 seq 差判据，自动化覆盖并全部通过，期望均为通过」；第 4 条步骤补「漏 1~6 条也要试」、期望标注「Round 2 已修，应通过」；表下注释把「flood 阈值 6 / 全局事件序号」两个**已知缺陷**措辞订正为「已修复、现在是应通过的验收项」，**仍要求真机亲自走一遍并记下两列事件数**。条目全部保留。
4. 音乐控制台、AI RP 指引、P0/P1 既有条目、已知技术债 1~4 **本轮未改**（Round 1 已订正到位）。

### 8.8 最终智能路由

| 判定 | 结论 |
|---|---|
| 源码 Bug | **0 条待修**。Round 1 的两条（限制 2 / 限制 3）已由工程师修复，QA 用自建复现 + 反向验证①②独立确认反转 |
| 测试代码问题 | **0 条**，无需 QA 自修。新增断言是真断言（含 `syncEpoch` 值断言、两列 `findsNothing/findsOneWidget`），动态注册账目算平，反向验证有效 |
| 设计取舍 / 已知限制 | 按 §7 第 3~9 条接受（U7 子项、P2-06、音乐控制台不播音频、K16、debug 签名、注释级过期表述等），**非缺陷** |
| 自动化回归 | **PASS**：1475 组 ×3 遍全绿、analyze 零、门禁 13/13 + 14/14、账目算平、独立出包对应当前源码、反向验证成立、红线守住 |
| **Send To** | **NoOne** |
| **整体 IS_PASS** | **YES** |

**轮次控制**：Round 1（写/跑/分析/路由 → Engineer）＋ Round 2（验修复 / 独立出包 / 刷新清单 / 最终路由）＝ **2 轮硬上限已闭合，不开第三轮**。

### 8.9 Round 2 视角的遗留 / Known Issues

1. **真机待测全部保留**（用户明确「全部做完再统一测」）：P0 局域网联机第 10 步（断线重连自动补齐）、P2-05 信息流闪烁第 4/5 条、P2-03 音乐控制台 5 条、AI RP 指引 3 条 —— 本轮**只登记不执行**，未跑 adb / 模拟器 / 真机联调。
2. **自动化测试的覆盖边界**：`deliverForTest()` 跳过 socket 建连与 `RoomFrame` 版本校验；服务端「重连后是否真回全量」由既有 P4 集成测试与真机 P0 覆盖，非本批新增缺陷（详见 §8.5）。纯逻辑组用自造合法 `_syncFrame()`，只有 widget 组用生产 `host.syncFor()` 原帧。
3. 首连 sync 触发一次无害的初始化 reset（`_boundEpoch -1→1`），判定无副作用、不需修改（§8.6）。
4. §7 第 3~9 条前序接受项（U7 三条子项、P2-06 导出文本、空房间首条不闪、音乐控制台不播音频、K16 奖惩骰语义、debug 签名、注释级过期表述、工程外 `overview.md` / `_p6_design.md §11` 矛盾）**继续接受**，仅记录、不越权修改工程外文件。
5. **未改 `_p6_transport9.txt`**（工程师产物，按派工保留）。

---

## 附：本轮日志路径（均为本会话自产）

**Round 1**

| 文件 | 内容 |
|---|---|
| `/tmp/qa_p6_default.log` | 默认并发全量 |
| `/tmp/qa_p6_serial.log` | 串行全量 |
| `/tmp/qa_p6_final.log` | 恢复源码后第三次全量 |
| `/tmp/qa_p6_analyze.log` / `qa_p6_p4.log` / `qa_p6_p5.log` | analyze / 两道门禁 |
| `/tmp/qa_p6_apk.log` | 出包脚本原始输出 |
| `/tmp/qa_p6_probe.log` | 限制 2/3 取证（`+3 All tests passed`） |
| `/tmp/qa_p6_negation.log` | 自证伪（`+4 -4`） |
| `/tmp/qa_p6_ledger_new.log` / `qa_p6_ledger_notice.log` | 账目单文件实测（`+25` / `+7`） |

**Round 2**

| 文件 | 内容 |
|---|---|
| `/tmp/qa_r2_default.log` / `qa_r2_serial.log` / `qa_r2_final.log` | 全量 ×3（`+1475` / `+1475` / `+1475`） |
| `/tmp/qa_r2_analyze.log` / `qa_r2_p4.log` / `qa_r2_p5.log` | analyze / 13 条 / 14 条 |
| `/tmp/qa_r2_ledger_room_feed_flash_test.log` / `..._wiring_test.log` / `..._sync_epoch_test.log` | 账目单文件实测（`+14` / `+10` / `+17`） |
| `/tmp/qa_r2_probe.log` | QA 自建独立复现（`+9`，含 `QA_R2_LIMIT3 base=7 now=17 jump=10`） |
| `/tmp/qa_r2_neg1.log` / `qa_r2_neg2.log` | 反向验证①②（`+1468 -7` / `+1469 -6`） |
| `/tmp/qa_r2_build.log` | QA 独立出包（新 SHA256 `e81eae68…`） |
| `/tmp/qa_r2_postbuild_smoke.log` | 出包后冒烟（`+17`，证明 native-assets 恢复） |

> 临时取证测试文件 `test/_qa_p6_probe_test.dart`（Round 1）与 `test/_qa_r2_probe_test.dart`（Round 2）均已删除（`PROBE_REMOVED=yes`）；`gp_feeds.dart` / `room_feed_flash.dart` 两轮临时改动均逐字节还原（diff + sha256 双证）。工程内最终新增/改动仅为交付要求允许的 `qa_p6_close_report.md`（本报告）与 `_manual_test_checklist.md`。
