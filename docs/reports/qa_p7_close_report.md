# 骰境 TRPG · P7 收尾交付期第一批 · QA 独立回归复核报告

**执行**：QA 工程师 严过关（Yan / software-qa-engineer）
**日期**：2026-11-10
**工程**：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
**对象**：工程师寇豆码 `_p7_transport1.txt`（P2-06「导出文本」真功能 + 注释/设计文档订正 + P5 结项 L1 补写 + 三项技术债核查）
**轮次**：**Round 1（唯一一轮）** —— 全绿即退出，按硬上限不开 Round 2
**独立口径**：不采信工程师截图 / 日志 / 自报数字；四条自检全部自己重跑，所有结论自己取证、自己证伪

---

## 0. 结论速览

| 项 | 结果 |
| --- | --- |
| 全量 `flutter test`（默认并发） | `00:52 +1499: All tests passed!`，0 红，EXIT=0 |
| 全量 `flutter test --concurrency=1` | `03:37 +1499: All tests passed!`，0 红，EXIT=0 |
| `dart analyze` | `No issues found!`，EXIT=0 |
| P4 门禁 / P5 UI 门禁 | `13 条 0 失败 IS_PASS: YES` / `14 条 0 失败 IS_PASS: YES` |
| 独立出包 | `60,602,967 字节 / 57.8MB`、三 ABI 带 `libapp.so`、SHA256 `f143a0b8…6032`，与工程师报值**逐字符一致** |
| `enable-native-assets` | 出包后 `true` 已恢复（复跑全量验证） |
| 1499 账目 | **算平**：1475 + 24 = 1499；24 条静态定义、9 处 `for` 全在造数据/断言内、零动态注册、零删用例 |
| 反向验证（我自己做） | **成立**：摘入口 `+19 -5`（5 条正例变红）；摘 P5 内层门控 `+12 -1`（双保险用例变红）；三文件逐字节恢复有 `diff -q` + sha256 双证 |
| P5 结项 L2 | **覆盖面扩大，接受**（QA 反向证伪证明双保险用例非恒绿） |
| 疑点 A / B / C | **全部判为设计取舍，接受**；无源码 Bug |
| 红线扫描 | 全部守住，见 §7 |
| 智能路由 | **NoOne**（不打回工程师、无需自修测试代码、Round 1 即通过） |
| **整体 IS_PASS** | **YES**（代码 + 自动化验收层；真机 / 系统分享 / 剪贴板 / 横屏 / 旁观者口径均如实登记，见 §10） |

> 判定口径：本批**没有**发现源码 Bug，**没有**发现需要自修的测试代码错误。三条疑点均为「多给能力 vs 少给能力」「内存里生成 vs 出站位」「额外入口是否越权」这类**设计取舍**，按派工写进报告「接受」，并附证据与改进建议。全程未直接联系工程师。

---

## 1. 四项自检原始输出（末几行摘录，QA 独立重跑）

命令前一律：
```bash
cd "C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm"
export PATH=/d/dev/flutter/bin:$PATH
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy
export NO_PROXY=127.0.0.1,localhost
```
本工程**不是 git 仓库**（`fatal: not a git repository`），故「零改动」用 mtime + sha256 + 门禁口径佐证，不用 `git diff`。

### 1.1 全量 `flutter test`（默认并发）

```
00:52 +1499: All tests passed!
  [flutter test exit=0]
```

### 1.2 全量 `flutter test --concurrency=1`（串行复核）

```
03:37 +1499: All tests passed!
  [serial exit=0]
```

### 1.3 `dart analyze`（全项目）

```
Analyzing dice-realm...
No issues found!
  [analyze exit=0]
```

### 1.4 两道静态门禁

```
==== 合计 13 条，失败 0 条 ====
P4_GATE IS_PASS: YES
  [p4 exit=0]
```

```
[OK]   jsStr( 命中 ≤ 14 且只在白名单 6 文件
       实际 14 处：room_session_local.dart×3, room_session_remote.dart×3,
       room_text.dart×1, gp_combat_list.dart×5, gp_scene_check_pl.dart×1,
       gp_status.dart×1；白名单外 无
[OK]   showModalBottomSheet 只许 sheets/room_sheet.dart 一处
[OK]   弹层不走裸 showDialog           扫描 64 个文件，零命中
[OK]   门禁字面量不入注释（零命中）      扫描 64 个文件的注释行，零命中
==== 合计 14 条，失败 0 条 ====
P5_UI_GATE IS_PASS: YES
  [p5 exit=0]
```

### 1.5 `bash tool/build_apk.sh` 独立出包 + 复核

```
[4/4] 恢复 native assets（否则 flutter test 跑不了）
===== 出包成功 =====
-rw-r--r-- 1 60965 197609 60602967 2026-11-10 08:47 build/app/outputs/flutter-apk/app-release.apk
f143a0b8f228df05a63404b7aa0289f4e94452c6daac9bf5a346524d84db6032 *.../app-release.apk
签名：debug（可侧载安装、不可上架）
  [build exit=0]

########## 7) APK SIZE / SHA256 / 3 ABI ##########
60602967 bytes
f143a0b8f228df05a63404b7aa0289f4e94452c6daac9bf5a346524d84db6032 *.../app-release.apk
  8323976   lib/arm64-v8a/libapp.so
  9241160   lib/armeabi-v7a/libapp.so
  8586120   lib/x86_64/libapp.so

########## 8) NATIVE-ASSETS RESTORED? ##########
  enable-native-assets: true
```

**对账结论**：字节数、SHA256、三 ABI `libapp.so` 尺寸、debug 签名、`enable-native-assets: true` 与 `_p7_transport1.txt` 第四节第 6 条**全部一致**；`57.8MB > 50MB`（不是无 AOT 的白屏坏包）。`build` 经 PowerShell 独立确认 `LinkType=Junction / Target=D:\dev\dice-build`，未删、未 `flutter clean`。

---

## 2. 测试账目核对（独立算，不照抄）

### 2.1 新增用例数

`test/room_history_export_test.dart` 独立 Grep `^\s*(test|testWidgets)\(` 得到 **24 条**静态定义：

| 分组 | 条数 | 行号 |
| --- | --- | --- |
| ① 纯函数：格式与旧版对齐 | 4 | 195 / 219 / 245 / 258 |
| ② K3 脱敏红线 | 3 | 275 / 355 / 383 |
| ③ 纯函数边界（空态/null/截断/上限/视角/时间） | 7 | 423 / 434 / 478 / 497 / 508 / 548 / 566 |
| ④ 静态口径 | 3 | 585 / 620 / 648 |
| ⑤ 接线（内存后端） | 7 | 676 / 726 / 786 / 841 / 891 / 910 / 923 |
| **合计** | **24** | 17 个 `test` + 7 个 `testWidgets` |

与工程师「14 纯函数 + 3 静态 + 7 接线 = 24」的拆分一致（①②③ = 14）。

### 2.2 动态注册排查

独立 Grep `for\s*\(` 共 **9 处**（234 编号行断言、334 哨兵遍历、402 内部键遍历、512/520 造 130/70 条数据、590/623 禁用词遍历、657/659 文件与禁用词遍历）——**全部在造数据或断言体内部**，无一处 `for (...) test(...)` / `testWidgets(...)` 动态注册。这一点很关键：上一批 `room_sync_epoch_test.dart` 有表驱动动态注册（12−1+6=17），本批没有，静态定义数 = 实测增量。

### 2.3 算式

```
P6 基线 1475（qa_p6_close_report.md §8.2 已算平：1454+2+2+17）
  + 本批 24（静态定义，无动态注册）
  = 1499
```
默认并发 `+1499`、串行 `+1499`、反向验证恢复后 `+1499` 三份全量完全对上。**零计数差**。

### 2.4「为了绿删用例」排查

- P5 基线 1475 来自上一批已核验的 QA 报告，本批没有删改任何既有测试文件（本批新增 1 个测试文件、改 5 个文件里没有 `test/` 下的既有文件）。
- 反向验证恢复后五个源码文件 sha256 与改动前基线**逐字节一致**（§3.4），不存在「临时改完忘了恢复、用旧测试凑绿」。
- 结论：**不存在删用例 / 放宽断言凑数**。

---

## 3. 断言复核与自证伪过程

### 3.1 K3 脱敏断言不是「什么都不输出也能假绿」

`test/room_history_export_test.dart:275-353`：
- 造了含明文 `p` 的 log（`PLAINTEXT_P_SECRET`）、`wire.p`（`WIRE_SECRET`）、暗骰 `opp`（`DARK_ROLL_SECRET`）、`DARK_ROLL_LABEL`、`SECRET_DETAIL`、私密笔记（`PRIVATE_NOTE_SECRET`）、私有素材（`PRIVATE_ASSET_SECRET`）、本机笔记（`LOCAL_NOTE_SECRET`）、角色卡 SAN（`SHEET_SAN_SECRET`）、其它座位私有字段（`OTHER_SEAT_PRIVATE_SECRET`）——**10 个哨兵串**逐一 `expect(text.contains(secret), isFalse)`。
- **正例防线确在**（:349-352）：`expect(text.contains('公开记录正文'), isTrue)`、`expect(text.contains('公开聊天正文'), isTrue)`、`expect(text.contains('玩家1（调查员甲）'), isTrue)`。即「把导出函数改成 `return ''`」会立刻变红，**不能靠什么都不输出骗过断言**。✓
- 第二条脱敏用例（:355-381）还专门用 `_numbered(text).single` 只扫编号记录行，避免抬头「成员」里的「玩家2」造成假红；这是工程师首轮自己踩坑后收紧的口径，复核认为**断言更强而非更弱**。

### 3.2「零发包零网络零 state」是真值前后对比，不是查文案

`:841-889` 在点入口 / 复制 / 分享**之前**取四项真值：
```dart
final sentBefore   = f.sent.length;
final seqBefore    = f.sessionOf(kHostSeat).lastSeq;
final stateBefore  = jsonEncode(f.stateOf(kHostSeat));
final noticeBefore = f.localOf(kHostSeat).notice;
```
动作后逐一 `expect(..., before)`，并用 `expect(port.copies + port.shares, 2)` 作**前置守卫**（证明两个动作确实执行了，否则「没变化」毫无信息量）。`jsonEncode(stateOf)` 是整份房间态的深比较，`f.sent.length` / `lastSeq` / `local.notice` 都是权威侧真值。✓ 不是「文案里有没有『发包』两个字」。

### 3.3 生产 `SystemRoomHistoryExportPort` 真的调平台 API，widget 侧零 await

静态（`sheet_history_export.dart`）：
- `:60 void copy(String text) => unawaited(_copy(text));` → `:67 await Clipboard.setData(ClipboardData(text: text));`
- `:63 void share(String text) => unawaited(_share(text));` → `:75 await SharePlus.instance.share(ShareParams(text: text, subject: '跑团游戏历史记录'));`
- `_copy()` / `_share()`（widget 侧 :159-172）**零 await**：先 `setState` 同步上屏反馈，再 `widget.port.copy/share(...)`；`unawaited` fire-and-forget 是本批刻意设计（躲 fake-async 挂死），异常在 `:68/:78` 空 catch 吞掉，文本仍完整可见。

**QA 运行时探针**（`test/_qa_p7_probe_test.dart`，临时文件，跑完即删）：
- 探针②：mock `SystemChannels.platform` 后调 `const SystemRoomHistoryExportPort().copy('QA_CLIP_SENTINEL_5b7d')`，让出 5 次 microtask，断言平台通道**真的收到** `Clipboard.setData` 且 `arguments['text'] == 完整哨兵文本`。→ **3/3 探针全过**，证明不是空 port 假装能用。
- 探针③：源码形态断言 `_copy` 真调 `Clipboard.setData`、`_share` 真调 `SharePlus.instance.share`，且 widget 段（从 `void _copy()` 到 `build` 前）`contains('await ') == false`、`setState(` / `widget.port.copy(` / `widget.port.share(` 均在。

### 3.4 我自己再证伪一次（改源码 → 跑 → 逐字节恢复）

**备份基线**（改动前，与工程师 `_p7_transport1.txt` 第四节第 7 条给出的反向验证前基准**完全相同**）：
```
58be7c119bec6b0bd8d1a589aa5662d50690f5d3d87d00edf516eb7db4189b0f  sheet_misc.dart
e1fcde0a60e8e30c639046a7d33c2cfc5ea7f5ad06510cba8142a378fff9ea0e  sheet_history_export.dart
3213159739758a024a1b4326b5d29e7e71449e26f3b7b1f44d8a007cb97038be  sheet_self_state.dart
c2b4e3782c88fb9a52ea2a592969f73c00772487bff6d16e13a8e838fbca8c1e  room_game_page.dart
4bdede500f1fa37426b8ee8cf602ce3fad16f6dc7edd4f0b8fa544f84ed7bdcb  room_history_export.dart
```

| 反向 | 临时改动 | 分片结果 | 判定 |
| --- | --- | --- | --- |
| **A** | `sheet_misc.dart:243` 的 `if (gate.can(kRoomHistoryExportPolicyOp))` → `if (false)`（入口恒不渲染） | `00:04 +19 -5: Some tests failed.`，EXIT=1 | **5 条正例变红**（≥3 达标）：入口可点→弹层出现、复制/分享真动作、空 port 底线、零发包四项真值、玩家视角入口存在；失败形态含 `line 919` 的 `findsOneWidget` 落空 |
| **B** | `sheet_self_state.dart` 两处 `if (!gate.can(kSelfStateInstantOp))` → `if (false)`（放行内层门控） | `00:06 +12 -1: Some tests failed.`，EXIT=1 | **唯一变红的正是 P5「双保险」用例**，证明它不是恒绿断言（详见 §4） |

**恢复与双证**：
```
########## DIFF -Q ##########
  sheet_misc.dart: IDENTICAL
  sheet_self_state.dart: IDENTICAL
  sheet_history_export.dart: IDENTICAL
########## SHA256 AFTER RESTORE ##########
58be7c119bec6b0bd8d1a589aa5662d50690f5d3d87d00edf516eb7db4189b0f  sheet_misc.dart
3213159739758a024a1b4326b5d29e7e71449e26f3b7b1f44d8a007cb97038be  sheet_self_state.dart
e1fcde0a60e8e30c639046a7d33c2cfc5ea7f5ad06510cba8142a378fff9ea0e  sheet_history_export.dart
```
`diff -q` 三处零输出 + sha256 与基线逐字符一致；最终复跑后五文件 sha256 再次与基线一致。

**恢复后回归**：
```
分片 test/room_history_export_test.dart   00:05 +24: All tests passed!   [exit=0]
分片 test/qa_p5_priv_probe_test.dart     00:06 +13: All tests passed!   [exit=0]
全量 flutter test                        00:53 +1499: All tests passed! [exit=0]
```

**临时文件清理**：
```
probe file: DELETED OK
backup dir: DELETED OK
```
探针测试文件与 `.qa_p7_bk/` 备份目录均已删除，**工程交付树零临时残留**；全量仍是 `+1499`（若探针未删会变成 +1502，已用最终全量反证清理干净）。

**常驻反向**：`_SilentPort`（空 port，:978-987）+ 用例 :786-839 断言「平台动作什么都不做时文本仍完整可见、反馈仍如实、不出现『已导出成功 / 文件已保存』」——等价反向一直留在测试文件里，不是临时改出来的。

---

## 4. P5 结项遗留 L2 独立复核（本轮必须闭合）

**背景**：`_p5_acceptance.txt:114-117` 记着 P5-T05 翻转了 `test/qa_p5_priv_probe_test.dart` 的 A-4 两条断言，原断言「记录缺陷存在（`findsOneWidget`）」→ 现断言「入口不渲染（`findsNothing`）」，配套新增「双保险」用例覆盖绕过入口强行 `openSelfStateSheet` 的路径；要求 QA 判「覆盖面扩大」还是「为绿放宽」。

### 4.1 ① 翻转后的断言是否对应修复后的正确期望 —— **是，不是裸改**

- 修复发生在**实现侧**，不是改测试放过缺陷：`_p5_fix_5red.txt:30-36` 记的双保险修法，我在现状源码里逐条核实：
  - `lib/ui/room/widgets/gp_pl_char_card.dart`：`stateBtn` 外包 `gate.can('state.self')` 闸门（旁观者结构上不渲染）；
  - `lib/ui/room/sheets/sheet_self_state.dart:111-114 / :138-141 / :155-158`：`_submitNumbers` / `_applyBody` / `_applyMental` **三个方法开头都还有** `if (!scope.controller.gate.can(kSelfStateNumbersOp / kSelfStateInstantOp)) { scope.local.showNotice('你没有权限…'); return; }`。
- 因此 `findsNothing` 是**修复后应有的正确期望**，不是「把红改绿的裸改」。若只是裸改，实现侧不会有这三处门控，QA 的反向 B 也不会变红。

### 4.2 ② 双保险用例是否真能防「绕过 UI 入口直接调弹层」 —— **能，且经反向证伪**

`test/qa_p5_priv_probe_test.dart:337-384`：
- 用 `Builder` + `TextButton(onPressed: () => openSelfStateSheet(ctx))` **绕过入口门控直接打开弹层**；
- 先 `expect(find.byKey(GpSelfStateKeys.root), findsOneWidget)` 作前置守卫（否则「找不到」可能是页面没画，无信息量）；
- 取 `f.stateOf('sp1')` 快照 → `f.clearSent()` → 点 `GpSelfStateKeys.body('轻伤')` → 断言：① `f.sent` 无 `state.self`；② 权威态 `members` 前后一致；③ `local.notice isNot(contains('已更新'))`。
- **QA 反向证伪**：临时把 `sheet_self_state.dart` 两处内层 `gate.can` 改成 `if (false)` 放行 → 该分片 `+12 -1`，**唯一变红的正是这条双保险用例**（`_applyBody` 会真的 `hostAction('state.self')` + `showNotice('身体状态已更新（立即生效）')`）。→ **证明这条用例不是恒绿，内层门控真在起作用**。

### 4.3 ③ 内层门控还在、无权时只说明事实不宣称成功 —— **确认**

`showNotice('你没有权限提交数值 / 修改身体状态 / 修改精神状态')` 三句只说明事实；「已更新」类文案只在门控**通过之后**才执行（:149 / :165）。符合 K7「不乐观提示成功」。

### 4.4 覆盖面是扩大而非缩小 —— **确认**

A-4 组现状共 **4 条**用例（不是 2 条）：
1. `:241-264` 玩家正向守卫：`stateBtn findsOneWidget` + 点「轻伤」真的发 1 条 `state.self`（**保留**，证明 `findsNothing` 不是因为页面没画）；
2. `:266-295` 原宽松用例（条件式点击 + 零发包断言）—— **保留未删**；
3. `:297-335` 新增：`stateBtn findsNothing` + `GpSelfStateKeys.root findsNothing` + **点遍页面上所有 enabled `RoomTap`**（泛化扫描，能抓任何漏网入口）+ 零发包 + 权威态不变；
4. `:337-384` 新增：绕过入口强行开弹层的双保险。

原断言覆盖的「旁观者不该发 `state.self`」现由 2/3/4 三条共同覆盖，且 3 是泛化扫描、4 补了「内层」这一原本完全没测的攻击面。玩家侧正向守卫与「前提：弹层确实打开」两条反向守卫都在。

### **P5 L2 结论：「覆盖面扩大，接受」，遗留 L2 本轮闭合。**

---

## 5. 三个疑点的判定与证据（智能路由）

### 5.1 疑点 A · 旁观者被排除在导出之外 —— **设计取舍，接受（NoOne）**

**事实核对（工程师陈述属实）**：
- `lib/domain/room_types.dart:243`：`'chat': RoomPolicyEntry(<String>[RoomRole.kp, RoomRole.player], null)` → POLICY `chat = [kp, player]`，**不含 spectator**；`kRoomHistoryExportPolicyOp = 'chat'`（`sheet_history_export.dart:35`）。
- `lib/domain/room_model_host_core.dart:520-537` `makeSync`（`syncFor` 调它）：`'chats' / 'logs' / 'dice'` 是 `roomClone(st[...])` **无条件下发**；只有 `'members': _cropMembers(members(), seat)` 与 `'privates': privateBySeat[seat]` 按 seat 裁剪。→ **旁观者数据层确实收到公开 chats/logs/dice**，工程师没夸大也没隐瞒。

**PRD 口径**：
- `_p5_prd.md:174`：「旁观者只看得到公开信息；且**不是靠 UI 隐藏**（客户端本来就没收到）」；
- `:189` US-5：「作为旁观者，我想**围观聊天与公开记录**，但不能操作任何东西、也看不到任何私密信息」；
- `:307/:358` 聊天列表「全部；输入框旁观禁用」；`:366` 工具栏「非旁观」；
- `:383`：「旁观者**不得**出现任何『做了会静默失败』的可用按钮；按钮的可见性与 `POLICY` 的 `roles` 必须同源」；
- `P2-06` 原文 `:764`：「游戏历史归档 | 只读历史记录 + 导出文本」—— **未规定角色范围**，既没要求「所有能看的人都能导出」，也没禁止旁观者导出。

**判定**：**合理的保守口径，不是 PRD P2-06 的功能违约**。
1. PRD 授予旁观者的是「**在屏幕上围观**公开聊天与公开记录」；「导出 / 复制 / 系统分享」是把同一份公开信息**带出应用到其它设备**的新能力，PRD 未授予，本工程也没有旧版先例（旧版 `UI.saveFile` 导出的是结团归档，不是旁观视角）。
2. 派工明确要求「权限不足不渲染入口」；工程师复用既有 `gate.can(op)`、不新增 POLICY op、不另写一套权限判断，符合「不新增权限实现」的设计约束，也符合 PRD `:383` 的「可见性与 POLICY roles 同源」。
3. 排除旁观者是**少给能力**，不会造成越权 / 泄密 / 假成功；反过来放行才需要重新论证 K3 与出站位。
4. 测试 `:891-908` 钉死「旁观者结构上不渲染入口 + `gate.can('chat') == false` + 零发包」，`:910-921` 用玩家视角 `findsOneWidget` 作反向守卫。

**如实登记的潜在意图偏差**：旁观者屏幕上看得到公开历史，**却不能导出同一份公开文本**——这是能力口径上的不对称，不是缺陷。若将来用户明确要求「旁观者也能导出只读公开记录」，工程师说「只改一处常量映射」在技术上成立（`kRoomHistoryExportPolicyOp`），但要注意新增含 spectator 的 op 会动到 P4 门禁冻结的 61 条 POLICY 分支，代价不止一行。真机清单 P2-06 第 5 条按「**看不到**入口」验收，不按「应能导出」。

### 5.2 疑点 B · 先生成完整文本、再传 `canExport` 二次防御 —— **设计取舍，接受（NoOne）**，附改进建议 + 一处覆盖缺口

**代码级证据**：
- `sheet_history_export.dart:102-127` `openRoomHistoryExportSheet()`：`final text = buildRoomHistoryExportText(session.state, ...)` 在 `:110` **无条件执行**；`:121-126` 才把 `canExport: scope.controller.gate.can(kRoomHistoryExportPolicyOp)` 传进 `RoomHistoryExportSheet`。→ 权限不足时，完整导出文本**确实在内存里生成过**，并作为 `widget.text` 字段持有到弹层 dispose。任务点名的这一事实**成立**。
- 但 `RoomHistoryExportSheet.build():180-194`：`if (!widget.canExport)` 直接 `return` 只含一句 `denied` 说明的 `Column`，**不构建** `SelectableText`、不构建 copy / share 两个 `RoomTap`。
- 纯函数 `room_history_export.dart:159-218` **零出站位**：只读 `codeOf / roomNameOf / kpNameOf / membersOf / roleText / collectFeeds / collectChats / checkLine / roomText`，不写 `state[...]`、不发 intent、不联网、不落文件、不进剪贴板 / 分享、不碰 `privates` / `logs` 原始行 / `p` / `wire` / `rolls` / 角色卡。K3 十条哨兵断言（§3.1）保证文本里没有秘密字段。
- `session.state` 是「按座位裁剪过的会话态」；由 §5.1 的 `syncFor` 可知公开 `chats/logs/dice` 对**所有** seat 一致，私密字段按 seat 裁剪。→ 生成的文本严格等于**当前视角屏幕上本就能看到的公开信息流**，没有越出该视角的可见边界，也没有跨座位取数。

**QA 运行时探针①（临时文件，已删）**：
- `canExport: false` + `text: 'QA_DENIED_SENTINEL_9c1e'` → `root findsOneWidget`（前置）、`denied findsOneWidget`、`text` / `copy` / `share` 三个 key **全部 findsNothing**、`find.textContaining(sentinel) findsNothing`；
- `canExport: true` 正例 → `SelectableText` 上屏且 `.data == 完整哨兵文本`，copy / share 两个 key 存在（防「什么都不渲染也能假绿」）。
- 探针 3/3 通过。

**判定**：**不构成实质泄漏面，属可接受**。生成的 String 只是内存里的一次性中间值：无 I/O、无网络、无持久化、无跨座位、不上屏、送不出去（denied 分支连按钮都不构建）；内容又是当前视角本就可见的公开信息。**不是**「把实现约束写成已知限制、掩盖需求违约」的情形——工程师在 `_p7_transport1.txt` 第七节第 1/2/3 条主动、如实地交代了旁观者口径 / 非 .txt / 非结团归档三处边界，没有掩盖。

**改进建议（非缺陷，不回工程师）**：纵深防御上更稳的写法是**先判 `gate.can`、无权就不调用纯函数**（或给弹层传空串），这样连「内存里生成过」这个事实都不存在，也省掉一次无意义的字符串拼接。当前写法在功能与安全性上无缺口，故不判红。

**一处测试覆盖缺口（如实登记，不擅自改交付测试）**：现有 24 组用例里，弹层 `canExport: false` 的 **denied 分支没有专门的常驻 widget 测试**——`:723` 只在 KP 视角断言 `denied findsNothing`（反向守卫），`:891-908` 旁观者用例只测「入口不渲染」，没有打开弹层验证二次防御。若将来有人误删 `if (!widget.canExport)` 或把 `widget.text` 渲染移到分支外，现有测试抓不到。QA 已用临时探针①做了运行时验证（跑完删除），**未修改任何交付测试文件**——这是刻意的：本批跨成员账目已锁定 1499，擅自补一条会让账目变 1500、与工程师 / 设计文档 / 清单口径失配。建议**下一批**补一条常驻用例并同步更新账目。

### 5.3 疑点 C · 玩家工具栏新增「更多工具」 —— **无缺陷，接受（NoOne）**；横屏挤压只登记不判红

**权限放大排查**：`room_game_page.dart:434-464`
```dart
final isKp = role == RoomRole.kp;
final canOpenMisc = RoomScope.read(context).controller.gate
    .can(kRoomHistoryExportPolicyOp);          // chat = [kp, player]
...
if (isKp)      RoomTap(key: kpPanelKey, onTap: showKpPanel...),
if (!isKp && canOpenMisc) RoomTap(key: miscToolsKey, onTap: openMiscSheet),
```
- **旁观者**：`isKp=false` 且 `canOpenMisc = gate.can('chat') = false` → **不渲染**，`miscToolsKey` 找不到 → 没有顺手把旁观者放进 MiscSheet。
- **KP**：`isKp=true` → 走 KP 面板，不重复摆「更多工具」。
- **玩家**：`!isKp && canOpenMisc=true` → 渲染。
- 测试 `:923-950` 三视角逐一钉死：玩家 `miscToolsKey findsOneWidget` + `kpPanelKey findsNothing`；KP `kpPanelKey findsOneWidget` + `miscToolsKey findsNothing`；旁观者 `miscToolsKey findsNothing`。
- 即便绕进 `MiscSheet`：`sheet_misc.dart:157` 的物品删除有 `gate.can('item.del')` 闸门、`:243` 的导出入口有 `gate.can(chat)` 闸门；音乐控制台 / AI RP 指引是纯本机 / 只读，无写动作。→ **无越权写操作**。

**const 与布局约束**：
- `RoomGamePage` 仍是 `const RoomGamePage({...})`（`:144`）；`miscToolsKey` 是 `static const Key`（`:184`）；`:382 / :385` 两个 `const GpFeeds(pane: ...)` 一行未动。→ **未破坏 const 构造**。
- `GpToolbar`（`gp_toolbar.dart:69-128`）用 `SizedBox(height: 56)` + `SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(...))` 承载 `extensions`。多一个 `RoomTap` 只会让横向内容变长、可滚动，**结构上不会 overflow 崩溃**；但窄档下是否挤压 / 需要横向滚才能看到属真机项。按派工「这条属真机，只需登记、不判红」→ 已登记清单 P2-06 第 7 条。

### 5.4 智能路由结论

| 判定 | 结论 |
| --- | --- |
| 源码 Bug → Engineer | **无**（三条疑点均为设计取舍；反向验证证明断言非恒绿、实现门控都在） |
| 测试代码问题 → QA 自修 | **无错误需修**。疑点 B 附带的「denied 分支缺常驻用例」是**覆盖缺口 / 改进建议**，非错误断言；QA 用临时探针自取证后删除，刻意不动交付测试以保住 1499 跨成员账目，登记为遗留 |
| 设计取舍 → 报告「接受」 | 疑点 A / B / C **全部接受**，证据见 §5.1~5.3 |
| **最终路由** | **NoOne** —— Round 1 全绿，直接退出，不开 Round 2；未联系工程师 |

---

## 6. 断言与文案的「假成功」专项排查（上一批教训）

任务点名警惕「导出是完整文本上屏 + 复制 / 系统分享，**不是下载 .txt 文件**」被写成「已实现文件导出」。逐条取证：

| 位置 | 实际内容 | 判定 |
| --- | --- | --- |
| `sheet_history_export.dart:161-163` 复制反馈 | `复制已触发：完整文本已送入系统剪贴板；若设备不支持，请长按上方文本全选复制。` | 前缀「已触发」+ 兜底指引；无「已导出成功 / 文件已保存 / .txt」 |
| `:169` 分享反馈 | `系统分享已触发；若面板未出现，请长按上方文本全选复制。` | 如实，未宣称面板一定出现 |
| `:203-205` 弹层说明 | 「完整文本…可长按全选复制，也可以用下面两个按钮交给系统处理。私密笔记、暗骰结果与其它座位的私有字段都不在其中。」 | 如实交代边界 |
| `:255` 初始反馈 | `尚未执行导出动作；文本已完整显示，可直接复制。` | 无假成功 |
| `:238 / :247` 按钮 | `复制全文` / `系统分享`，hint 写「放进系统剪贴板 / 调起系统分享面板发送完整文本」 | 无文件名、无本地文件写入 |
| 测试 `:837-838` | `feedback isNot(contains('已导出成功'))` / `isNot(contains('文件已保存'))` | 显式防线 |
| `_p7_transport1.txt` 第七节第 2 条 | 「导出 ≠ 下载 .txt 文件…没有文件名、没有本地文件写入…报告不把它写成『已实现文件导出』」 | 如实 |
| 真机清单新增 P2-06 表头 | 「★ 边界：**不是下载 .txt 文件**…弹层与报告都不得出现『已导出成功 / 文件已保存』这类假话」 | 已写入 |

→ **没有发现「已实现文件导出」的假成功**。`saveFile` / `.txt` 文件名 / `已导出成功` / `文件已保存` 在本批新增 / 改动文件里 Grep 零命中（活代码）。

**一处轻微乐观措辞（如实登记，不判红）**：「完整文本**已送入**系统剪贴板」这句在 `_copy()` 的 `setState` 里**先于** `widget.port.copy()` 发出；生产 port 是 `unawaited` fire-and-forget，`Clipboard.setData` 尚未完成、甚至可能失败（`:68` 空 catch 吞掉）。严格说是完成态措辞先于完成。但：① 前缀「复制已触发」已限定为触发；② 有「若设备不支持，请长按上方文本全选复制」兜底；③ K7 底线（完整文本 SelectableText 上屏 + 可全选复制）守住；④ 无任何「生成文件」暗示。**判为措辞改进建议**，可改成「已请求复制 / 正在送入」，非缺陷、不回工程师，登记 §10。

---

## 7. 全局红线扫描（独立执行）

| 红线 | 证据 | 结果 |
| --- | --- | --- |
| `lib/domain/**` / `pubspec.yaml` / `lib/net/**` 零改动 | 本工程**非 git 仓库**；改用 mtime：`pubspec.yaml` 2026-11-08 18:55 / **4068 字节**（与工程师报告一致）；`lib/domain/` 最新 2026-11-09 12:14、`lib/net/` 最新 2026-11-09 21:55；本批日期 2026-11-10 在这些目录**零文件** | ✅ |
| `build` junction 完好、未 `flutter clean` | PowerShell `LinkType=Junction / Target=D:\dev\dice-build / Attributes=Directory, ReparsePoint`；自检首行 `build -> /d/dev/dice-build` | ✅ |
| 零新增 `jsStr(` | P5 UI 门禁：`实际 14 处 … 白名单外 无`；本批 4 文件 Grep：`sheet_misc.dart` 零命中、`room_game_page.dart` 零命中（只有两处 `const GpFeeds`）、纯函数层零命中、弹层零命中 | ✅ |
| 零裸 `showDialog` | P5 UI 门禁 `扫描 64 个文件，零命中`；`showModalBottomSheet` 只 `sheets/room_sheet.dart` 一处 | ✅ |
| 零 `toWireJson()` | 全 `lib/` Grep 命中仅 `lib/net/lan_server.dart:16/183`、`lib/net/room_frame.dart:11` 的**回顾性注释**（写明「禁止碰，含明文 p」），活代码零调用；本批文件零命中 | ✅ |
| 零 `Timer` / `Future.delayed` / `AnimationController` | 本批 4 文件：纯函数层零命中；`sheet_misc.dart` / `room_game_page.dart` 零命中；`sheet_history_export.dart` 唯一 `Timer` 命中在 **:13 头注释**「零 Timer / 零延迟 / 零动画控制器」（正是工程师记录的「朴素 grep 假红」坑），活代码只有 `dart:async show unawaited` + `unawaited(_copy/_share)` | ✅ |
| `lib/` 用户可见过期字面量为零 | Grep `下一期\|后续版本提供\|当前没做\|未申请` 全 `lib/` → **No matches found**（连注释都零命中，比工程师报告口径更干净） | ✅ |
| 冻结的 QA 产物 / 脚本未被工程师改动 | `qa_p6_close_report.md` 2026-11-09 22:53、`tool/build_apk.sh` 2026-11-09 18:02、`qa_p4_gate.js` 2026-11-09 04:31、`qa_p5_ui.js` 2026-11-09 16:10，均 ≤ 本批前一日；`_manual_test_checklist.md` 由 **QA 本轮**订正（见 §8） | ✅ |
| `_p6_design.md §11` 订正 | `:315`「全量 **1475** 组 0 红」、`:320`「**多播锁已实现**」 | ✅ |
| 未跑 adb / 模拟器 / 真机 | 本轮命令仅 flutter test / analyze / node 门禁 / build_apk.sh / stat / sha256 / unzip / Grep / Read / Write；无任何 adb·emulator·真机联调 | ✅ |
| 跨成员信息流 | 全程未向 `software-engineer` 发消息；仅最终向 `team-lead` 回传 | ✅ |

---

## 8. 真机待测清单 `_manual_test_checklist.md` 更新点（只登记、不执行）

保持原有 P0/P1/P2 分级与风格，**不重写整篇、不删任何既有条目**，共 6 处订正：

1. **头部 APK 信息**：`57.7MB / 60,521,003 字节 / e81eae68…` → `57.8MB / 60,602,967 字节 / f143a0b8…6032 / 三 ABI / debug 签名`；订正说明改为「2026-11-10，P7 收尾交付期第一批由 QA（严过关）**独立重新出包**并刷新指纹」。
2. **新增 `## P2 · 游戏历史导出文本（P2-06 · 本批新增，真机待测）`** 章节，**7 条**可操作步骤（超出要求的 6 条）：① 玩家与 KP 都能从「更多工具」进入并看到入口；② 点开后完整文本可见、可长按全选复制；③ 「复制全文」后到系统剪贴板粘贴验证逐字一致；④ 「系统分享」面板真能出现且带出完整文本；⑤ 旁观者**看不到**该入口（不是灰着）；⑥ 导出全程不产生网络请求、不改房间状态（无新消息 / 无 seq 变化）；⑦ 横屏 / 窄档下玩家工具栏「更多工具」不挤压其它按钮。表头另加「**不是下载 .txt 文件**」边界说明与「不得出现已导出成功 / 文件已保存」判据。
3. **P2 · 弹层可达性** 清单补一项：`更多工具 → … / 本机工具（音乐控制台 · 导出游戏历史，详见 P2-06 表）`，使既有可达性清单与现状一致。
4. **尾部「自动化已验证」**：`全量测试 1475 组 0 红` → **`1499 组 0 红`**，证据列补「P7 第一批 QA 独立回归 + 反向验证恢复后复跑」。
5. **技术债第 3 条（K16）**：按工程师 D1 口径改准确 —— 明确「**已接受的取舍，不是需求违约**」，写明旧版 `room-model.js:612` 的 `EVT.DICE` 字段逐项一致、同样不落 `bonus`/`penalty`、P2-06 未要求复盘奖惩语义、不列为待修缺陷；保留真机验证动作与「若将来补需先确认新需求 + 单开批次」。
6. **技术债第 1 条**：「需要真机确认效果」→「**真机只需确认 ROM 是否放行**」，与 `_p6_design.md §11`「多播锁已实现」口径对齐。

**技术债 1~4 逐条读过的结论**：第 2 条（存档已落盘 `FileRoomSaveStore` + 内存兜底文案）与现状一致、第 4 条（debug 签名）与独立出包一致，均**不改**；第 1 / 3 条按上述订正；无与现状矛盾的其它表述。第 212 / 227 行出现的「下一期（P2）」「后续版本提供（U9）」是**历史叙述**（说明当时把占位改成了什么），不是当前 UI 字面量，按「不删既有条目」保留。

---

## 9. 覆盖与结论边界

- 本轮**只做自动化回归 + 清单登记**，符合用户「真机测试等全部做完再统一测」的要求。
- 自动化能证明：纯函数格式 / 脱敏 / 边界、静态口径、接线（入口可点 → 完整文本上屏 → 复制 / 分享真动作 → 四项真值前后不变）、权限结构性不渲染、生产可达路径三视角、生产 port 真调平台通道、反向验证非恒绿。
- 自动化**不能证明**：系统剪贴板与系统分享面板在真机上的实际表现、横屏窄档工具栏观感、APK 装机启动、局域网联机、旁观者真实体验。这些全部保留在真机清单，未删一条。

---

## 10. 遗留问题 / Known Issues（如实登记，不掩盖）

1. **旁观者导出权限口径（疑点 A）**：保守排除旁观者；旁观者屏幕上看得到公开历史但不能导出同一份公开文本，属能力口径不对称。若用户要求放行，需改 `kRoomHistoryExportPolicyOp` 映射（新增含 spectator 的 op 会动到 P4 门禁冻结的 61 条 POLICY，代价不止一行）。真机清单第 5 条按「看不到入口」验收。
2. **弹层 `canExport=false` 的 denied 分支缺常驻 widget 测试（疑点 B 附带发现）**：QA 已用临时探针运行时验证通过（探针已删、未改交付测试，保住 1499 账目）。建议下一批补一条常驻用例并同步更新账目与设计文档。
3. **「完整文本已送入系统剪贴板」措辞略乐观**：`setState` 先于 `unawaited` 平台动作发出，建议改成「已请求复制 / 正在送入」。不影响 K7 底线、无「生成文件」假话，非缺陷。
4. **导出 ≠ 下载 .txt 文件**：完整文本上屏 + 复制 / 系统分享，无文件名、无本地文件写入；报告与 UI 均未写成「已实现文件导出」。
5. **导出对象 = 当前会话视角的公开信息流，不是结团归档**：抬头是「导出时间」并多两行说明，无 `endedAt` / 归档 members；严格复刻旧版归档导出属新需求。
6. **系统分享面板 / 剪贴板 / 横屏窄档观感未验**：真机清单 P2-06 第 3 / 4 / 7 条。
7. **APK 仍 debug 签名**：可侧载、不可上架；release keystore 依赖用户提供，真机测完再签更合理。
8. **P2-05 三条子项**（错峰堆叠播报 / 角标持续脉冲 / 轮次提示音）维持不做（U7 裁决 + 测试环境硬约束），未放假入口。
9. **K16 奖惩骰语义**为旧版同源的已接受取舍，按 D1 口径订正清单措辞，不列为待修缺陷。
10. **未跑 adb / 模拟器 / 真机联调**：按用户要求统一安排；本轮 P0/P1/P2 真机清单条目一律保留。
11. **本工程非 git 仓库**：「零改动」结论基于 mtime + sha256 + 门禁口径，而非 `git diff`；已在 §1 / §7 如实说明取证方式。

---

## 11. 最终智能路由与轮次

| 判定 | 结论 |
| --- | --- |
| 自动化回归 | **PASS**：1499 组 ×3 遍全绿（默认并发 / 串行 / 反向恢复后）、analyze 零、门禁 13/13 + 14/14、账目算平 |
| 独立出包 | **PASS**：SHA256 `f143a0b8…6032` 与工程师报值一致、三 ABI 齐全、57.8MB、native-assets 已恢复 |
| 反向验证 | **成立**：`+19 -5` / `+12 -1`，逐字节恢复 `diff -q` + sha256 双证，临时文件清理干净 |
| P5 L2 | **闭合**：覆盖面扩大，接受 |
| 疑点 A / B / C | **设计取舍，全部接受**；无源码 Bug |
| 测试代码 | **无错误需自修**；一处覆盖缺口登记为下一批改进项 |
| 路由 | **NoOne** —— 不打回工程师，Round 1 即通过，不开 Round 2 |
| **IS_PASS** | **YES** |

> 依据：四条自检全部独立重跑通过；新增 24 组用例账目算平且经两轮反向证伪证明非恒绿；P5 历史遗留 L2 经源码 + 反向证伪闭合；三条疑点均有代码级 / PRD 级证据支撑「设计取舍」判定；红线全部守住；真机清单已按独立出包实测值订正并补登 P2-06 七条待测项。所有未能自动化的部分按用户要求只登记、不执行、不隐瞒。

---

**附：本轮自产临时文件（均已删除）**
- `test/_qa_p7_probe_test.dart`（QA 三探针：denied 分支 / 生产 port 平台通道 / 源码形态）—— `DELETED OK`
- `.qa_p7_bk/`（三份源码 `cp` 备份 + 反向验证 / 探针 / 分片日志）—— `DELETED OK`
- 最终全量 `+1499` 反证清理干净，工程交付树零残留、源码五文件 sha256 与基线逐字节一致。
