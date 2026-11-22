# QA 独立复核报告 · P10 第 5 期

- 复核人：严过关（QA / `software-qa-engineer`）
- 工程：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
- 被复核交付：`_p10_transport7.txt`（工程师 寇豆码 / `software-engineer`）
- 上批基线：全量 **1918** 全绿 / APK `fd9b05c9…5072` / 70,033,836 B
- 复核原则：所有数字自己跑出来，不采信工程师报告与锚点；反向证伪、独立出包、逐字节比对、智能路由。
- 环境：flutter/dart 来自 `source /d/dev/env.sh`（`/d/dev/flutter/bin`）；**所有 `flutter test` 均带 `NO_PROXY=127.0.0.1,localhost,::1`**；工程**无 .git**，基线一律用哈希 / `cmp -s` / 工程师开工时（09:42）留下的 `/tmp/p10t5_baseline/` 改前副本比对。

---

## 0. 一句话结论

**PASS / 智能路由：Send To: NoOne（无需返工）。**

五项自检全部独立复现（1934 并发 / 1934 串行 / analyze 零 / P4 13/13 / P5 14/14），独立出包与工程师**逐字节一致**，依赖解锁专项证据链完整，旧音乐用例口径更新是**加严不是放宽**，音乐真播放「切场景必停旧」与纯本机边界成立，缩放几何实测通过，子类近义词覆盖/不污染/不显示成立，8 处反向证伪全部真红且逐字节恢复，红线零违反。

**★ 一处需订正的「报告论据」问题（非代码缺陷，不触发返工）**：工程师 §6.2/§11 称「给工具栏加可见标题的两种做法都打穿既有断言」。我独立复现：② 把标题并进 `zoomPercent` 的 label → `room_ui_layout_test.dart S2.4` 确实红（`Found 0 widgets with text "100%"`）；**① 加独立 `const Text('界面缩放')` → `room_ui_layout_test.dart` + `room_ui_wiring_test.dart` + `p10_t5_music_synonym_layout_test.dart` 共 44 条全绿**，即「必打穿 S2.4」不成立。结论不受影响（用户诉求对象不是工具栏，见 §5），但报告表述需订正。

---

## 1. 五项自检（全部自己跑，原始输出）

| # | 命令 | 原始输出（关键行） | 退出码 |
|---|---|---|---|
| 1 | `flutter test`（默认并发，NO_PROXY） | `01:09 +1934: All tests passed!`（耗时 1m15s） | 0 |
| 2 | `flutter test --concurrency=1`（串行，NO_PROXY） | `05:00 +1934: All tests passed!`（耗时 5m05s） | 0 |
| 3 | `dart analyze` | `Analyzing dice-realm...` / `No issues found!` | 0 |
| 4 | `node tool/qa/qa_p4_gate.js` | `合计 13 条，失败 0 条` / `P4_GATE IS_PASS: YES`（`POLICY=61，分支=67，缺失=无`） | 0 |
| 5 | `node tool/qa/qa_p5_ui.js` | `合计 14 条，失败 0 条` / `P5_UI_GATE IS_PASS: YES` | 0 |

P5 原始关键行（独立跑出）：

```
[OK]   lib/domain 纯 Dart（零 Flutter / IO / UI）   扫描 58 个 .dart，零命中
[OK]   jsStr( 命中 ≤ 14 且只在白名单 6 文件
       实际 14 处：room_session_local.dart×3, room_session_remote.dart×3,
       room_text.dart×1, gp_combat_list.dart×5, gp_scene_check_pl.dart×1,
       gp_status.dart×1；白名单外 无
[OK]   门禁字面量不入注释（零命中）   扫描 70 个文件的注释行，零命中
```

**恢复全部证伪改动后再复跑一遍**（报告硬要求）：

```
=== [QA FINAL] flutter test (post-restore) ===
01:14 +1934: All tests passed!          FINAL TEST EXIT=0
=== [QA FINAL] dart analyze (post-restore) ===
Analyzing dice-realm...  No issues found!   FINAL ANALYZE EXIT=0
```

> 环境坑复核：`HTTP_PROXY=http://127.0.0.1:3991` 确实存在；带 `NO_PROXY` 后两次全量均无 `WebSocketException` 假红。未设 NO_PROXY 的场景本轮未跑（按派工单要求直接带正确设置）。

---

## 2. ★ 依赖解锁专项（本批头号风险，独立核）

### 2.1 `pubspec.yaml` 恰好只加一行 —— 三方交叉铁证

- 本批开工时工程师留下的改前副本 `/tmp/p10t5_baseline/pubspec.yaml` sha256 = **`ebb6c72e036698c7846a3371601ef7ec1a78c8b8dc82746d0c9c27ceb17173db`**
- 另一工作区独立副本 `_gh_backup/pubspec.yaml` = 同值；`qa_p10_2_report.md:217` 历史记录 `ebb6c72e…` = 同值 ⇒ 基线可信
- 当前 `pubspec.yaml` = `92b281e4…`；`diff -u` **唯一差异**：

```
@@ -37,6 +37,7 @@
   file_picker: ^13.3.2^M$
+  audioplayers: ^6.8.1^M$
 ^M$
 dev_dependencies:^M$
```

- 第 40 行原始字节 `  audioplayers: ^6.8.1\r\n`（全文件 CRLF 一致）；`awk 'NR!=40'` 后按 CRLF 还原重算 = `ebb6c72e…73db`，`cmp -s` 与 `_gh_backup` **IDENTICAL**
- 版本号 `2.17.0+83`、`environment: sdk: ^3.13.7`、12 项 assets、其它依赖、dev_dependencies **一字未改**

### 2.2 `pubspec.lock` 只由 `flutter pub get` 生成

- 基线 `dd81c3b4…`（09:42 副本）→ 当前 `ab25d0fe30b16094f260eea1aaf9c52f33e12ac8d2c22880ffccb2339c83456f`
- `diff -u` 结果：**只新增 11 个包块**，另有 1 行自动变更 `sdks.flutter: ">=3.41.0" → ">=3.44.0"`（audioplayers 约束所致，pub 自动生成），**没有任何包被删/改版本/手工插行**
- 独立 `flutter pub get`（保留 `HTTP_PROXY`，未加任何跳过约束的参数）：

```
Resolving dependencies...
Downloading packages...
  cross_file 0.3.5+5 (0.4.0 available)
  cupertino_icons 1.0.9 (2.0.0 available)
  material_color_utilities 0.13.0 (0.13.1 available)
  test_api 0.7.12 (0.7.15 available)
Got dependencies!
4 packages have newer versions incompatible with dependency constraints.
PUBGET EXIT=0
lock sha BEFORE = ab25d0fe…456f   AFTER = ab25d0fe…456f   （完全一致）
```

### 2.3 11 个包真的都来自 audioplayers 依赖树（无夹带）

实读 pub cache 各包 `pubspec.yaml`：

| 包 | 来源 |
|---|---|
| `audioplayers 6.8.1` (direct main) | 本次新增的直接依赖 |
| `audioplayers_android 5.3.0` / `_darwin 6.5.0` / `_linux 4.3.0` / `_web 5.3.0` / `_windows 4.4.1` / `_platform_interface 7.2.0` | `audioplayers` 的 `dependencies` 逐条声明的 6 个平台实现 |
| `http 1.6.0` | `audioplayers: http: '>=0.13.1 <2.0.0'` |
| `http_parser 4.1.2` | `http: http_parser: ^4.0.0` |
| `typed_data 1.4.0` | `http_parser: typed_data: ^1.3.0` |
| `synchronized 3.6.1+1` | `audioplayers: synchronized: ^3.0.0` |

`audioplayers` 其余依赖（`file` / `meta` / `path_provider` / `uuid` / `collection` / `plugin_platform_interface` / `web` / `flutter_web_plugins`）基线 lock 中已存在，故不计入新增。**11 个全部可溯源，零夹带无关包。**

### 2.4 版本兼容（不是靠跳过约束）

- 包声明：`environment: sdk ^3.6.0 / flutter ">=3.44.0"`（7 个 audioplayers 包一致）
- 本机：`Flutter 3.47.9 • Dart 3.13.7`（`flutter --version` / `dart --version` 原始输出已取）
- lock：`sdks: dart ">=3.13.7 <4.0.0" / flutter ">=3.44.0"` —— 是约束正常交集
- `pub get` 退出码 0、无 version-check 报错、lock 前后同哈希 ⇒ **未用 `--no-version-check`、未忽略约束**

### 2.5 `http` 传递依赖与「不联网」边界

- 全库 `import 'package:http'` / `import 'package:dio'` = **0**
- 本批 4 个新增/重写文件中 `RoomEvt|hostAction|sendIntent|toWireJson|LogRecord|hub.|repo.save|lastSeq|RoomIntent|WebSocket|HttpClient|package:http|UrlSource` 扫描 **全部零命中**
- `lib/ui/room/**` + `lib/domain/**` 中 `UrlSource` / `package:http` = **0**；生产端口只用 `AudioPlayer.play(DeviceFileSource(abs))`（本机私有目录文件），AOT 中 `DeviceFileSource`×2
- **如实指出措辞问题**：工程师「应用代码零网络请求」不严谨 —— `lib/net/**`、`lib/repo/**` 既有 LAN 房间 / 云房间 / AI 客户端用 `dart:io` 的 `HttpClient`/`WebSocket`（既有功能，与本批无关）。准确表述应为：**音乐功能全程零发包零联网；应用代码未引入 `package:http`，http 仅为 audioplayers 的传递依赖**。结论（音乐纯本机）成立。

### 2.6 门禁 / 出包 / AOT / 环境

- P4 13/13、P5 14/14 未被新依赖/新文件打穿（原始输出见 §1）
- **独立出包**（见 §8）：`bash tool/build_apk.sh` 一次成功，SHA 与工程师逐字节一致
- AOT 实证（从 QA 自己出的包重新解 `lib/arm64-v8a/libapp.so`，按 UTF-16LE）：`后日谈`×1 / `场景音频插槽`×1 / `先停旧曲`×7 / `下面这排百分比按钮`×1 / `BGM 场景快捷键`×1，ASCII `pistol`×1、`handgun`×1；中文 UTF-8 全 0（反证 UTF-16LE 口径）
- `enable-native-assets: true`（`flutter config --list`）；`build -> /d/dev/dice-build` junction 完好；全程未 `flutter clean`
- `android/gradle.properties`：出包前 `964d9ef7…84a1` / `proxyPort=9194`；临时改 `3991` 出包后 `cmp -s IDENTICAL OK` + SHA `964d9ef7…84a1` + 端口 `9194` 恢复。**未改 `tool/build_apk.sh` 一个字节**

---

## 3. ★ 旧音乐用例「口径更新」独立裁决：**不是放宽，是加严**

### 3.1 用例卫生（自己数，含 `for` 动态注册陷阱）

- 改前 `/tmp/p10t5_baseline/sheet_music_test.dart` 与改后 `test/sheet_music_test.dart` 的 `test(`/`testWidgets(` 注册数**均为 5**；逐行 diff 确认无整组消失
- 无 `skip:`、无 `skip =`、无 `for(...) test(...)` 动态注册、无 `contains(...)` 改恒真条件；两文件里的 `for` 都是断言循环，不是注册循环
- **banned 词表一条没少，反而扩充**：
  - 弹层 banned：改前 4 条（`下一期/后续版本/已播放/播放成功`）→ 改后 **8 条**（新增 `没有内置播放器/点了没反应/后台播放/如实说明面板`）
  - 静态 banned：**11 条全保留**（`dart:io/dart:ui/http/AiClient/Clipboard/sendIntent/hostAction/showDialog/Timer/Future.delayed/AnimationController`）+ `showRoomSheet`
  - 占位 banned 2 条（`下一期/后续版本提供`）完全保留
  - **新增 9 条正向源码断言**（`MusicConsoleController/MusicPort/kMusicScenes/MusicSheetKeys.play|pause|stop|pick(|scene(/openMusicSceneQuickSheet`）
- 纯本机用例由「只打开弹层」**加强为**：先执行 选文件/切场景/播放/暂停/停止 一整串动作，再验 `f.sent` / `lastSeq` / `state` / `local.notice` / `f.saves` **五项不变**

### 3.2 报告 §4 十行表逐行复现与独立裁决

| # | 旧断言 → 新断言（我自己 diff 复现） | 独立裁决 |
|---|---|---|
| 1 | `noFakeButton` findsOneWidget → 删除过时 key，改为 选文件/播放/暂停/停止 逐一 `findsOneWidget` + `enabled==true` + `onTap!=null` + Fake 记到真实调用 | **NoOne**：从「写一句没有假按钮的说明」升级为「可点件逐一验真行为」，可证伪（RV3 已证） |
| 2 | `status.contains('没有内置播放器')` → `未播放/尚未选定场景` + 播放后 `播放中`+场景名+文件名 | **NoOne**：正向能力断言 |
| 3 | `status.contains('点了没反应')` → 该词进 banned（不许再写）+ A5「没选定/没配置点播放给真提示、不乱播」 | **NoOne**：文案声明 → 行为证明 |
| 4 | `howto.contains('后台播放')` → `howto.contains('自备')` + 真用法（选文件/播放/暂停/停止/重启仍在） | **NoOne**：旧替代方案已不适用 |
| 5 | `honest.contains('如实说明')` → `localOnly` 验 `不联网/不同步/不打包任何音频`，`why` 验 `不打包音频/不联网` | **NoOne**：1 条 → 6 条独立断言 |
| 6 | ban `已播放`/`播放成功` → **保留**并扩到 8 条 | **NoOne**：加严 |
| 7 | `find.byType(RoomTap) findsNothing` → 3 控制 + 5 选文件 + 5 场景键共 13 个可点件逐 key 验真 | **NoOne**：「没有可点件」→「可点件都有真实行为」，RV3 空回调即红 |
| 8 | 静态 11 banned → **11 条全留** + 新增 9 条正向 needed | **NoOne**：摘掉实现即红 |
| 9 | `全 room/ 不再有「下一期/后续版本提供」` → **完全保留不变** | **NoOne** |
| 10 | 纯本机（零发包/零状态）→ 保留并加强（新增整串动作 + 存档快照第五项） | **NoOne**：加严 |

### 3.3 「不许放禁用按钮假装能用」精神是否被保留

**保留且更硬。** 断言的是「按钮 `enabled==true` + `onTap!=null` **且点了 Fake 记到真实调用**」（`fake.calls` / `saveCalls` / `saved` / `activeStreams`），不是仅「按钮存在」。RV3 把 `onTap: _c.play` 改成空回调 → 新口径用例立刻红：`Expected: a value greater than or equal to <2> / Actual: <1>`，症状正是「点了没反应」。

### 3.4 自己造探针的证伪（不采信 RV 表）

- 摘掉 `switchScene` 的 `_port.stop()` → **4 条红**：A1（`Expected >=0 / Actual -1`）、A2（`Expected ['stop'] / Actual []`）、sheet_music 新口径、A6 ⇒ 症状「旧曲没停 / 空槽没停」
- 播放按钮改空回调 → 新口径用例红 ⇒ 症状「点了没反应」

---

## 4. 音乐真播放行为级 + 纯本机边界（独立证明）

- **5 场景插槽**：`kMusicScenes` = 日常/探索/悬疑/战斗/后日谈（5），每槽有 `slot/slotName/slotState/pick`，`已配置 · 文件名` / `未配置` 如实上屏
- **配置本机持久化**：`saveSlots` 把字节复制进应用私有目录 `dice_realm/music/<scene>.<ext>`，只存 `relPath + displayName`；`MusicSlot.fromJson` 拒绝 `..` 与 `://`（不存 `content://` 临时授权 URI）；写盘用 tmp + rename
- **切场景必停旧**：`switchScene` 同步 `stop() → play()`，Fake 记录 `['stop','play:music/combat.mp3']`；`overlaps==0`、`activeStreams==1`；空槽 = `['stop']` 只停不播；生产 `_play` 内还有 `await p.stop()` 双保险
- **播放/暂停/停止**三按钮真行为，状态文本 `播放中 · 战斗 · battle.mp3` / `已暂停` / `已停止`；空槽/未选定给真提示（A5）
- **纯本机五项不变**：`f.sent` / `lastSeq` / `stateOf` / `localOf.notice` / `f.saves`（sheet_music 纯本机用例 + A6 房间页用例），前置 `expect(fake.calls, isNotEmpty)` 保证动作真的发生
- **零新增事件**：`RoomEvt.values` 仍 **27**（`room_types.dart:158` 实点 27 项，`room_coverage_test.dart:110` 断言）；新增 4 个生产文件零 `RoomEvt.`、零 `hostAction`、零 `toWireJson()`、零 `LogRecord`
- **KP 权限**：A6 KP 侧 `findsOneWidget`；A7 玩家/旁观 `findsNothing`（结构上不渲染）；入口按 `gate.can('scene.mode')`，5 个场景键收进 `quickRoot` 弹层，工具栏不被挤爆
- **可注入端口**：`MusicPort` 覆盖 `play/pause/stop/release/loadSlots/saveSlots/importAudio` 全部 7 个方法；单一全局 `musicPort`，测试 `musicPort = FakeMusicPort()` + `addTearDown(() => musicPort = systemPort)` 还原（顶层 `final systemPort` 在注入前捕获，规避延迟初始化陷阱）；播放类同步 void、Future 立即完成 ⇒ fake-async 下 A6/A7 与 3 条 widget 用例全部跑完
- **如实说明保留**：不打包音频 / 不联网 / 不同步 / 自备 / 只在本机（`localOnly`/`howto`/`why` 逐条断言）

---

## 5. 缩放按钮几何实测 + ★「工具栏未加标题是否满足用户需求」明确裁决

### 5.1 独立几何实测与反向证伪

- B1 五档宽度 **320/360/480/700/900** 逐个 `tester.getRect(...).top`，`tops.toSet() == 1`（同一行）、`zoomRow isA<Wrap>`、`find.text('界面缩放')` 与 `zoomHint` 均 `findsOneWidget`（全量与单文件均绿）
- 几何算术复核：改前 `5×58 + 4×4 = 306dp` > 320dp 弹层可用 296dp（会换行）；改后 `5×54 + 4×3 = 282dp` ✅；`minSize 58→54`、`spacing 4→3` 由 diff 确证；全局 `RoomTap.tapMinSize`(48dp) 未动
- **RV4**：把 `Wrap` 退回 `Column` → B1/B3 红，`Expected: <Instance of 'Wrap'> / Actual: Column` ✅
- **RV5b**：删掉可见说明 `zoomHint` → B1/B3 红，`Found 0 widgets with key [<'misc/zoomHint'>]` ✅（首版探针因多删一行导致编译失败，已修正重跑，不采信编译失败那次）

### 5.2 `gp_toolbar.dart` 逐字节零改动（独立哈希）

```
/tmp/p10t5_baseline/gp_toolbar.dart   099ada0965f65649666472082a22aad67e468bff211520bb84be1faeea9c2bd6
lib/ui/room/widgets/gp_toolbar.dart   099ada0965f65649666472082a22aad67e468bff211520bb84be1faeea9c2bd6
cmp -s: IDENTICAL OK
```

（mtime 10:28 是工程师试改后 `cp` 恢复所致，**内容零改动**。）

### 5.3 ★ 明确裁决：**用户诉求已满足，属合理工程取舍，路由 NoOne，不返工**

**对象判定（我自己查证，不采信工程师转述）**：

1. 用户原话是「**工具箱里几个百分比数字按钮没标题、一行一个**」。杂项弹层 `MiscSheet` 的标题正是「**更多工具**」，里面恰好有 **5 个**百分比按钮（`60/70/80/90/100%`），且历史上是「一行一个」——完全对应。底部 `GpToolbar` 只有 **1 个**循环百分比按钮 + 1 个重置（图标、无百分比数字），既不是「几个」，也不存在「一行一个」。
2. 交付清单 `_manual_test_checklist.md:44` 的 **Z1** 把验收口径写死为「**「更多工具」里看「界面缩放」那一块**」，要求「可见标题『界面缩放』+ 一句说明 + 五个按钮同一行」；**Z2** 对工具栏只要求「不挤爆、不需横向拖动、切档不跳位」。
3. 该处**早已有可见标题 `Text('界面缩放')` + `Wrap` 一行**（第 2 期 B 已修），本批又补了**可见说明** `zoomHint`「下面这排百分比按钮用来缩放界面（60%–100%），点一下立即生效。」并把 5 档压到 282dp 保证 320dp 窄屏不换行。

⇒ **用户诉求（标题 + 一行）在正确的对象上已满足；工具栏未加独立可见标题不是需求缺口，是「别把工具栏挤爆」下的合理取舍。判 NoOne，不路由 Engineer。**

**★ 但工程师的论据要订正（如实报）**：我复现了 §6.2 的两种加法——

| 做法 | 我实测结果 |
|---|---|
| ② 标题并进 `zoomPercent` 的 label | `room_ui_layout_test.dart S2.4` **红**：`Found 0 widgets with text "100%"`（与工程师一致 ✅） |
| ① 在 `Wrap` children 首位加独立 `const Text('界面缩放')` | `room_ui_layout_test.dart` + `room_ui_wiring_test.dart` + `p10_t5_music_synonym_layout_test.dart` 共 **44 条全绿** ⇒ 「必打穿 S2.4（before.top=243.2/after.top=288.0）」**我复现不成立**（可能与插入位置/Text 尺寸/档位有关） |

结论不受影响（用户没要求工具栏加标题），但 `_p10_transport7.txt` §6.2 / §11 的「两种做法都打穿」表述需改为「内联 label 打穿文案断言；独立 Text 在本次复现下未打穿，撤回主要基于对象判定与 Z2 约束」。

**若产品后续确要给工具栏加标题，最小可行修法**（写清备用，不要求本批改）：在 `GpToolbar._bar` 的 `Wrap(key: GpToolbarKeys.quickRow)` children 首位插入 `const Text('界面缩放'),`；我实测 3 个相关测试文件 44 条全绿、无需改任何既有断言；仅需真机 Z2 核窄屏观感。

### 5.4 §6.2 九处候选按钮扫查表逐行复现

| 位置 | 我实测 RoomTap / Wrap / Column | 与工程师表 | 裁决 |
|---|---|---|---|
| `sheet_misc.dart` 缩放 5 档 | 5 / 2 / 2 | ✅ | 唯一改动处（低密度、可安全合并） |
| `gp_toolbar.dart` | 4 / 2 / 0 | ✅ | 零改动 |
| `gp_kp_tools.dart`（9） | 9 / 1 / 1 | ✅ | 不改 |
| `sheet_kp_panel.dart`（8） | 8 / 3 / 4 | ✅ | 不改 |
| `gp_pl_char_card.dart`（7） | 7 / 2 / 3 | ✅ | 不改 |
| `sheet_dice_tools.dart`（5） | 5 / 0 / 4 | ✅ | 不改 |
| `room_lobby_page.dart`（21） | 21 / 4 / 8 | ✅ | 不改 |
| `gp_dice_bar.dart`（7，0 Column） | 7 / 1 / 0 | ✅ | 已横向 |
| `sheet_music.dart`（本批新增 7） | 7 / 3 / 2 | ✅ | 新按钮从一开始就不竖排 |

⇒ 「只改确属低密度且可安全合并的 1 处」**没有扩大成布局大改**。

### 5.5 布局骨架零改动

- `room_keys.dart` mtime `2026-11-09 12:40`、`widgets/room_layout.dart` mtime `2026-11-11 01:55`，均早于本批开工 09:42 ⇒ 未动，`RoomSlot`/`RoomKeys` 命名与 key 未增删
- `room_game_page.dart`：基线 `bbd911a7…`（`/tmp/p10t5_baseline/`，= `qa_p10_6_report.md:70` 上批 QA 记录）→ 当前 `f0b4f679…`；`diff -u` 显示改动**严格限于** 1 行 import + `_buildToolbar` 内（`canOpenMisc` 拆出 `final gate` 的等价重构 + 注释 + `final canQuickBgm` + **1 个** KP `RoomTap`）；dock/folded 骨架零改动

---

## 6. 组技能子类独立近义词

- 新表 `lib/domain/skill_subskill_synonyms.dart`（197 行 / 10,897 B，只 import 同目录纯 Dart 文件）：**8 组 / 85 个子类行 / 321 个近义词值，全部非空、零重复、零空表**（我自己按数据表区间解析统计）
  - 口径差异如实报：工程师「约 406 词条」= 数据表内 414 个引号字符串 − 8 个组 key = 85 个子类名 + 321 个值；文件注释写「86 个子类行」是**笔误**（实际 85，C1 断言 `>=85` 且 `tableRows == rows.length`）
- GENERATED `skills.dart`（mtime 11-10 19:48）/ `occupations.dart`（11-08 15:15）**早于本批，一字未动**；C6 断言 `skills.dart` 无 `pistol`、有 `'name': '手枪'`
- 正例：搜「手枪」命中 `firearms::手枪`；`pistol/短枪/handgun` 亦命中（C2 并断言 `pistol` 不在 name/id/sub/desc/组级词里，不是假绿）；6 个探针词（`pistol/短枪/拳脚/堪舆/法医/necronomicon`）在 131 个全量选项里各恰好命中 1 行（C3）；「魅惑」仍只命中 `charm::`
- 分层不串：`skillSynonymIdOf` 三级回退只解析组 id；组级词与子级词零交集、子级词零重复（C4）；上批 54/54 覆盖、取悦↔魅惑、两搜索框形状、`侦`/`spot`/`图书使`/`讨好` 零回归（C5）
- **不显示近义词**：`subskillSynonymsOf` 调用点唯一且只在 `skillMatchesKeyword` 的局部 `fields` 列表里；`step_skills.dart` 零引用；不写回 `name/desc/sub`、不改 hintText、不改任何 Text（C6 静态 + 上批 B6 运行时 + 全量绿）
- **RV2**：摘掉 `...subskillSynonymsOf(skill),` → C2 `Expected true / Actual false`、C3 `Expected ['firearms::手枪'] / Actual []`、C6 `Expected <1> / Actual <0>` ✅
- **「徒手/brawl」取舍裁决：合理，未削弱用户举例**。`徒手`/`brawl` 是上批 `fighting` 的**组级**词，若并进子类表，搜它们会把格斗 7 个子类一起带出来（跨子类串味）。本批给 `fighting::斗殴` 专属 `拳脚/空手/unarmed/赤手`（用户举例中的「拳脚」已落地），`徒手`/`brawl` 仍留在组级表、照旧能搜到格斗（斗殴）行。既守「分层不串」又不丢可达性。

---

## 7. 反向证伪表（全部自己动手、`cp` + `sha256` + `cmp -s` 逐字节恢复）

> 首轮用 Windows Python `subprocess('bash')` 误触 WSL 拦截产生**假红**（0.6s 完成 6 次测试），已识别并**全部作废**，改用纯 Git Bash 驱动 `flutter test` 重跑。以下为真实结果。

| # | 生产改动 | 跑的文件 | 结果 / 红的症状 | 恢复 |
|---|---|---|---|---|
| RV1 | 摘掉 `switchScene` 的 `_port.stop()` | `p10_t5` + `sheet_music` | **4 红**：A1 `Expected >=0 / Actual -1`；A2 `Expected ['stop'] / Actual []`；新口径用例；A6 ⇒「旧曲没停」 | `cmp -s IDENTICAL`，sha `3b76150e…` 回原 |
| RV2 | 摘掉 `...subskillSynonymsOf(skill),` | `p10_t5` | **3 红**：C2/C3/C6，`Expected ['firearms::手枪'] / Actual []` | `cmp -s IDENTICAL`，sha `160ec6a9…` 回原 |
| RV3 | 播放按钮 `onTap: _c.play` → `() {}` | `sheet_music` | **1 红**：新口径用例 `Expected >=2 / Actual 1` ⇒「点了没反应」 | `cmp -s IDENTICAL`，sha `aa557644…` 回原 |
| RV4 | 缩放 `Wrap` → `Column` | `p10_t5` | **2 红**：B1 `Expected Wrap / Actual Column`、B3 | `cmp -s IDENTICAL`，sha `aa3a5097…` 回原 |
| RV5b | 删可见说明 `zoomHint` | `p10_t5` | **2 红**：B1 `Found 0 widgets with key misc/zoomHint`、B3 | `cmp -s IDENTICAL`，sha `aa3a5097…` 回原 |
| RV6b | 工具栏标题并进 `zoomPercent` label | 3 文件 | **1 红**：S2.4 `Found 0 widgets with text "100%"`（复现工程师②） | `cmp -s IDENTICAL`，sha `099ada09…` 回原 |
| RV6c | 工具栏加独立 `Text('界面缩放')` | 3 文件 | **44 条全绿**（工程师①「必打穿」不成立） | `cmp -s IDENTICAL`，sha `099ada09…` 回原 |
| RV6 | 同上（单跑 `room_ui_layout_test.dart`） | 1 文件 | 17 条全绿 | `cmp -s IDENTICAL` |

另有 RV5 首版探针因删行范围多切一行造成编译失败，已修正为 RV5b 重跑并以 RV5b 为准。

---

## 8. 账目 + 独立出包比对

### 8.1 用例账目（1918 + 16 = 1934 算平）

- `test/p10_t5_music_synonym_layout_test.dart` 独立数 **16** 条（A1–A7 / B1–B3 / C1–C6），无 `for` 动态注册
- `test/sheet_music_test.dart` 改前 **5** → 改后 **5**，未整组消失、零 skip
- `test/qa_p10_4_verify_test.dart` **8** 条、mtime 11-11 02:32（本批未动）；`test/*.dart` 顶层 **132** 个；`test/support/*.dart` 9 个（新增 `music_fakes.dart` 在 support 不占顶层）
- 本批 `find -newermt 09:42` 命中文件恰好 = 工程师 §10 清单（生产 8 + 测试 3 + 配置 2 + 文档 2），无额外写入
- `1934 − 16 = 1918` ✅ 全量只增不减

### 8.2 独立出包（只走 `bash tool/build_apk.sh`）

```
[1/3] 构建 release APK（native-assets 保持开启）
Running Gradle task 'assembleRelease'...  71.8s
√ Built build\app\outputs\flutter-apk\app-release.apk (67.1MB)
[2/3] 校验 AOT 产物
  8913800  lib/arm64-v8a/libapp.so
  9863752  lib/armeabi-v7a/libapp.so
  9110408  lib/x86_64/libapp.so
[3/3] 完成
BUILD EXIT=0
-rw-r--r-- 70329708 ... app-release.apk
fdc5ab49af897ecc9cdf465e7dbfb9265d3e610772665e90ddc99f1a98c558b5 *...
enable-native-assets: true
lrwxrwxrwx build -> /d/dev/dice-build
```

| 项 | 工程师报 | QA 独立出包 | 判定 |
|---|---|---|---|
| 字节数 | 70,329,708 B | **70,329,708 B** | ✅ |
| SHA256 | `fdc5ab49…c8b5` | **`fdc5ab49af897ecc9cdf465e7dbfb9265d3e610772665e90ddc99f1a98c558b5`** | ✅ 逐字节 |
| arm64-v8a | 8,913,800 | **8,913,800** | ✅ |
| armeabi-v7a | 9,863,752 | **9,863,752** | ✅ |
| x86_64 | 9,110,408 | **9,110,408** | ✅ |
| 包体增量 | +295,872 B | `70329708−70033836 = 295872` | ✅ |
| 三 ABI 增量 | +131,072 / +81,920 / +65,536 | `131072 / 81920 / 65536` | ✅ |
| libapp.so 合计增量 | +278,528 B | `278528` | ✅ |

出包时临时把 `gradle.properties` 的 `9194` 改 `3991`，出包后 `cmp -s IDENTICAL OK` + SHA `964d9ef7…84a1` + 端口 `9194` 恢复；**未改脚本、未删 build junction、未 `flutter clean`**。

---

## 9. 红线扫描

| 红线 | 独立结果 |
|---|---|
| 不跑 adb / 模拟器 / 真机 | ✅ 本轮全程未跑；清单只登记未执行 |
| `pubspec.yaml` 除一行外不动 | ✅ 见 §2.1，`cmp -s` 铁证 |
| `lib/domain/**` 零 `package:flutter`·`dart:io`·`dart:ui`（含注释） | ✅ 58 文件全量扫描 **0 命中**；`lib/ui/room/**` 注释行门禁字面量 **0 命中** |
| `RoomEvt.values=27` | ✅ `room_types.dart:158` 实点 27；`room_coverage_test.dart:110` 断言 |
| `kRoomPolicy=61` | ✅ P4 门禁 `POLICY=61，分支=67，缺失=无`；`room_types.dart:242` 起 61 条 |
| `jsStr(` = 14、白名单外 0 | ✅ P5 门禁实测 14 处 / 6 白名单文件 |
| `RoomSlot`·`RoomKeys` 不增删不改 key | ✅ `room_keys.dart`/`room_layout.dart` mtime 早于本批 |
| GENERATED 两文件、`tool/qa/*`、`qa_*_report.md`、`test/qa_p10_4_verify_test.dart`(8) | ✅ mtime 均早于本批开工；既有 6 份 `qa_p10_*_report.md` 最新 08:57 |
| 另一工作区 `overview.md` 未改 | ✅ 头部仍是上批第 4 期（1918 / `fd9b05c9…5072`），零本批内容，mtime 09:13 早于 09:42 |
| 全量只增不减 | ✅ 1918 + 16 = 1934 |
| 零新增 RoomEvt / intent / 广播事件、出站零 `toWireJson()` | ✅ 见 §4 |

---

## 10. 真机清单核对

- P0 · P10 第 5 期（`_manual_test_checklist.md:28-47`）共 **10 条**：`M1–M6`(6) + `Z1–Z2`(2) + `S1–S2`(2)。派工单写「**12 条**」为算术笔误（6+2+2=10），已如实记录。
- 全部**只登记、未执行**；头部明确写「本轮未跑 adb / 模拟器 / 真机」「真实音频解码 / 文件授权 / 重启持久化 / 听感叠播都必须在真机确认」。
- 头部指纹 `fdc5ab49af897ecc9cdf465e7dbfb9265d3e610772665e90ddc99f1a98c558b5` / 70,329,708 B / 三 ABI 与我独立出包一致 ✅
- 旧 SHA 回滚行完整保留：`上一版（P10 第 4 期）… 70,033,836 字节 / fd9b05c9c36f13c20d1a1b2514163ad0ea4e9382a01687da1b92ce22c9d85072 / 8,782,728 · 9,781,832 · 9,044,872` ✅

---

## 11. 智能路由判定

**Send To: NoOne**

- 源码 bug：**无**（8 处反向证伪全部按预期变红，说明实现与测试互相钉死；独立出包逐字节一致）
- 测试 bug：**无**（口径更新经 diff 逐行复现为加严；首轮 Python 假红是 QA 自身工具链问题，已作废重跑，未污染交付）
- 遗留 / 非阻塞项（**不需返工，交给 team-lead 决策**）：
  1. `_p10_transport7.txt` §6.2 / §11 关于「工具栏加独立 Text 必打穿 S2.4」的论据，我复现 44 条全绿 ⇒ 建议订正表述（真实打穿的是内联 label 的文案断言）。
  2. `skill_subskill_synonyms.dart` 文件注释「86 个子类行」笔误（实际 85）；工程师报告「~406 词条」为含子类名的口径（实际纯近义词值 321）。均为文档口径，不影响功能与测试。
  3. 工程师「应用代码零网络请求」措辞不严谨（`lib/net/**` 既有联机功能用 `dart:io`），准确表述见 §2.5。
  4. 真机 10 条待用户执行；清单「12 条」为笔误。

**结论：可以交付用户。**
