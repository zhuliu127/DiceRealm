# P10 第 2 期 A · QA 独立回归复核报告

任务：对「骰境 TRPG」P10 第 2 期 A 批（头像跨设备 + 推回合自动保存）做**独立回归复核 + 独立出包 + 真机清单登记**。
复核人：QA 严过关（本报告所有数字均为**本人重跑**所得，不引用工程师报告的数字，对账时才并列）。
工程：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
对照：`_p10_transport2.txt`（工程师报告）/ `qa_p10_1_report.md`（上批口径）/ 老 APP `coc7th-card-app/.../assets/js/`
**红线遵守**：未跑 adb / 模拟器 / 真机；未删 `build` junction；未 `flutter clean`；未改 `pubspec.yaml`；未改生产源码（证伪实验已逐字节还原，见 §6）；出包只走 `bash tool/build_apk.sh`。

**结论：IS_PASS: YES（智能路由 → NoOne）**。四项自检全部复现，被改的那条既有断言**经证伪证明是「扩大覆盖面」而非「为了绿放宽」**，本批 2 个核心机制（TEMP_COMMIT 顺序 / 头像跨设备）在源码与用例层面都站得住。另有 5 条**不阻塞**的观察与口径订正（§9），已同步进真机清单。

---

## 1. 五项自检独立重跑（原始输出）

所有命令均先 `unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy` + `export NO_PROXY=127.0.0.1,localhost`。

### 1.1 全量 `flutter test`（默认并发）
```
01:15 +1834: All tests passed!
```
（EXIT=0，墙钟 1m20s）

### 1.2 全量 `flutter test --concurrency=1`
```
04:50 +1833: test/wizard_steps_test.dart: 校验函数（从页面搬出来后行为不变） 非必填步骤永远放行
04:50 +1834: All tests passed!
```
（EXIT=0，墙钟 4m56s）

### 1.3 `dart analyze`
```
Analyzing dice-realm...
No issues found!
```

### 1.4 门禁
```
$ node tool/qa/qa_p4_gate.js
==== 合计 13 条，失败 0 条 ====
P4_GATE IS_PASS: YES

$ node tool/qa/qa_p5_ui.js
[OK]   await repo.save( 每条写盘都在申报清单内（6 条显式声明）
       实际 6 处 / 申报 6 处 —— lib/repo/card_transfer.dart:172, lib/repo/room_state_writer.dart:63,
       lib/ui/ai_create_page.dart:472, lib/ui/card_detail_page.dart:167,
       lib/ui/create/create_flow_page.dart:288, lib/ui/random_create_page.dart:166
[OK]   jsStr( 命中 ≤ 14 且只在白名单 6 文件
       实际 14 处：room_session_local.dart×3, room_session_remote.dart×3, room_text.dart×1,
       gp_combat_list.dart×5, gp_scene_check_pl.dart×1, gp_status.dart×1；白名单外 无
==== 合计 14 条，失败 0 条 ====
P5_UI_GATE IS_PASS: YES
```
> P5 UI 由上批的「13/14 · NO」变成「14/14 · YES」，原因是第 06 条从「裸数字上限 `FROZEN=4`」改成了「**6 条显式申报清单**」（脚本 mtime `2026-11-11 00:24`，属 P10 第 1 期收口，**不是本批改的**）。我没有直接接受这个「变绿」，而是**反向验证它是不是被绕过**：新建 `lib/ui/room/tmp_gate_probe.dart` 写入一句 `await repo.save(1);` →
```
[FAIL] await repo.save( 每条写盘都在申报清单内（6 条显式声明）
==== 合计 14 条，失败 1 条 ====
P5_UI_GATE IS_PASS: NO
```
删除探针后恢复 `IS_PASS: YES`。⇒ 该条是**收紧**（任何未申报的新写盘路径都会红），不是放宽。

### 1.5 独立出包（`bash tool/build_apk.sh`，只跑这一个脚本）
```
[1/3] 构建 release APK（native-assets 保持开启）
Running Gradle task 'assembleRelease'...   84.6s
√ Built build\app\outputs\flutter-apk\app-release.apk (66.7MB)
[2/3] 校验 AOT 产物
  8782728  1981-01-01 01:01   lib/arm64-v8a/libapp.so
  9732680  1981-01-01 01:01   lib/armeabi-v7a/libapp.so
  8979336  1981-01-01 01:01   lib/x86_64/libapp.so
[3/3] 完成（native-assets 始终为开启状态，flutter test 可直接跑）

===== 出包成功 =====
-rw-r--r-- 1 60965 197609 69919088 2026-11-11 01:05 build/app/outputs/flutter-apk/app-release.apk
5f0338834a2db716f8ebf17e49adde91eaab6f571decbb46c278b90f450b1651 *build/app/outputs/flutter-apk/app-release.apk
```
`flutter config --list | grep native` → `enable-native-assets: true`（出包后已确认）；`ls -ld build` → `build -> /d/dev/dice-build`（junction 完好）。
AOT 抽检（`grep -a`，本机无 `strings`）：`tempcommit` **HIT**、`data:image/png;base64,` **HIT** ⇒ 本批新 Dart 代码确实进了 AOT，不是「拿旧包糊弄」。

### 1.6 与工程师报告对账
| 项 | 工程师自检 | QA 独立重跑 | 判定 |
|---|---|---|---|
| 全量测试（默认并发） | 1834 全绿 | **1834 全绿** `01:15` | ✅ 一致 |
| 全量测试（串行） | 1834 全绿 `04:48` | **1834 全绿** `04:50` | ✅ 一致 |
| `dart analyze` | No issues | No issues | ✅ |
| P4 门禁 | 13/13 YES | 13/13 YES | ✅ |
| P5 UI 门禁 | 14/14 YES | 14/14 YES（并已反证第 06 条不是绕过） | ✅ |
| APK 字节数 | 69,919,088 | **69,919,088** | ✅ 逐字节数一致 |
| APK 三 ABI 尺寸 | 8,782,728 / 9,732,680 / 8,979,336 | **同前** | ✅ 一致 |
| APK SHA256 | `dc1c9771…ad0a9c` | **`5f033883…0b1651`** | ⚠️ **不一致**（见 §5.3，不影响交付，但指纹以我这次实测为准） |
| native-assets 恢复 | true | true | ✅ |

---

## 2. 账目核对（只增不减）

| 项 | 数 | 依据 |
|---|---|---|
| 上一批全量 | 1800 | `qa_p10_1_report.md`：1759 + 41 = 1800（两次并发均 1800） |
| 新增 `test/p10_t2_avatar_test.dart` | **19** | 本人逐条数：A 组 8（`200×100 裁切` / `竖图裁切` / `体积≤20000` / `超限降 48` / `空与非图片` / `相对路径不存在` / `相对路径存在` / `roomAvatarDataUri 两条不放宽`）+ B 组 5（dataURI 渲染 / 圆点 / 文件优先 / 无文件回 dataURI / 都没有）+ C 组 1（远端玩家栏）+ D 组 2（条目 avatar 值 / 渲染与不渲染）+ E 组 3（无头像不带键 / 有头像带缩略 / 生成抛异常不挡绑卡）= **19** |
| 新增 `test/p10_t2_tempcommit_test.dart` | **15** | 本人逐条数：组 1 顺序 2 + 组 2 触发面 4 + 组 3 客户端落库 4 + 组 4 不进存档 2 + 组 5 取值口径 3 = **15**。文件里 3 处 `for`（:83 / :91 / :117）都在**辅助函数内部**遍历，**不注册用例**，不存在「靠 for 虚增」 |
| 合计 | 1800 + 34 = **1834** | 与实测 1834 完全吻合 |
| 是否有既有用例被删 | **没有** | `find test -newermt "2026-11-10 22:00"` → 本批只碰过 3 个文件：`p10_t2_avatar_test.dart`(新) / `p10_t2_tempcommit_test.dart`(新) / `room_ui_entry_test.dart`（1 条断言）。其余 123 个测试文件 mtime 全部早于本批开工；`test/*.dart` 仍为 **126** 个（我用于体积复算的临时文件已删，数量回到 126） |
| `room_ui_entry_test.dart` 用例数 | 22（跑全文件 `+22`） | 该文件只改了 1 条断言的期望构造方式，未增删用例 |

---

## 3. ★ 重点裁决：被改的断言「是不是为了绿放宽」—— **不是，是扩大覆盖面**

### 3.1 改动内容（`test/room_ui_entry_test.dart:575-598`）
```dart
final expectSheet = _stripVolatile(cardToRoomSheet(card))..remove('avatar');
expect(_stripVolatile(asMap(payload['sheet'])), equals(expectSheet));        // ① 仍逐字段相等
expect(asMap(payload['sheet']).containsKey('avatar'), isFalse,               // ② 新增：键不存在
    reason: '没有头像 → 不带该键（不是空串）');
// ③ 4 条抽查：attrs.dex=61 / skills.length=2 / status.currentHP / status.maxSAN
```
`_stripVolatile`（:461-462）只删 `at`，不碰 `avatar`，所以 `remove('avatar')` 不是「顺手把可疑字段丢掉不查」。

### 3.2 三个必答问题
| 问题 | 判定 | 依据 |
|---|---|---|
| ① 「逐字段相等」是否真保留（没换成模糊断言） | **是，真保留** | 仍是 `equals(...)` 全量 Map 比较（`equals` 对 Map 是深度相等，多一个键、少一个键、值差一点都红）。只把**已知口径变更的那一个键**从期望里摘掉，其余 40+ 个键照旧比 |
| ② 新增的「键不存在」断言是否真能拦住 `avatar: ''` | **能** | `containsKey('avatar')` 判的是「键在不在」，与值无关；`''` 也算在。已用**证伪**双向证明（下表 1b），失败信息为 `Expected: false / Actual: <true>` |
| ③ 4 条抽查是否足以防「两边一起错」 | **够用（辅助而非主判据）** | 主判据是 `equals`；4 条抽查覆盖了这条用例最容易被「搬运函数一起改错」的地方（属性值、技能行数、HP、SAN）。它们不是全字段覆盖，但**不作为唯一防线**，风险可接受 |

### 3.3 我的证伪（两次，不是看一遍就说「没问题」）
| # | 我改了什么 | 预期 | 实测 |
|---|---|---|---|
| 1 | 生产代码 `cardToRoomSheetForReport` 改回**总是**带 `avatar` 键（无头像时 `avatar: ''`） | 该组变红 | **红**：`弹层 · 绑定角色卡 ★ 选中一张卡 …` 失败，`Actual` 里多出 `'avatar': ''`（13+1 红 / 该文件其余 21 组仍绿） |
| 1b | 在上面基础上**再把测试的期望值退回旧写法**（`final expectSheet = _stripVolatile(cardToRoomSheet(card));`，不 `remove`）—— 也就是「假如 `equals` 这一层真被放宽了」 | 只剩 `containsKey` 一条防线，应当仍红 | **仍红**：`Expected: false / Actual: <true> / 没有头像 → 不带该键（不是空串）`。⇒ **即使 `equals` 那层失效，新增断言单独也能拦住「带 `''`」** |

恢复：`cp -p` + `diff -q` + `sha256sum` 逐字节还原，测试文件回到 `3dac8198…d513`、生产文件回到 `c09dc019…e722`，复跑 `+22 All tests passed!`。

### 3.4 老 APP 依据（口径变更**有出处**，不是工程师临时发明）
`coc7th-card-app/.../assets/js/ui/room-ui.js:4578-4607`（v2.13.7 `reportSheet`）：
```js
var afterThumb = function (thumb) {
  if (thumb) sum.avatar = thumb;
  else delete sum.avatar;                 // 没有头像 → 不占广播体积
  sendIntent(T2_INTENT().CHAR, { ... });
```
⇒ 「没有头像 → **删键**（不是空串）」是老 APP 原文行为，本批是**对齐**而非放宽。
（附带一句：老 APP 只对 `/^data:image\//` 的卡头像做缩略 —— 因为老 APP 的卡里存的就是 dataURI；Flutter 侧卡里存的是相对路径，所以改成「相对路径 → 读盘 → 压 dataURI」，这是**必要的适配**，不是随意偏离。）

**裁决：PASS。这条改动是本批唯一被允许的既有测试变更，且方向是「把口径写得更死」。**

---

## 4. tempCommit 与头像的实质正确性（不只看用例绿）

### 4.1 顺序（核心）—— 源码级确认，不靠用例转述
`lib/domain/room_model_rollback.dart:383-393`，我逐行读：
```dart
void advanceRoundInto(List<SendPlan> out, int round) {
  pushInto(out, emit(RoomEvt.round, {'round': round}));   // ① ROUND
  out.addAll(onRoundBoundaryJudgments());                 // ② 濒死每轮 CON
  out.addAll(onDayWeekTick());                            // ③ 天/周恢复（改临时卡）
  pushInto(out, emit(RoomEvt.tempCommit, {'round': round, 'at': now()})); // ④ 最后
}
```
⇒ `tempCommit` 确实排在 `onDayWeekTick()` **之后**。与老 APP `core/room-model.js:3686` 同序。
**专门钉顺序的用例存在**（不是只钉「发出了」）：`p10_t2_tempcommit_test.dart:154` 用 `_expectCommitAfterStateful()` 断言「所有 `state`/`dice` 事件的下标 < `tempCommit` 下标，且 `tempCommit` 之后只允许 `log`」；`:166`「重伤玩家周恢复发生在 tempCommit 之前」进一步**构造**重伤 + 缺 HP + 上周已检定，断言 `iState >= 0`（前提成立）且 `iCommit > iState`。两条都钉的是**顺序**，不是存在性。

### 4.2 触发面（四条全部核实）
| 声称 | 我的核实方式 | 结果 |
|---|---|---|
| `round.next` 触发 | `roomActionNextRound` → `advanceRound()` → 统一出口（`room_model_actions_room.dart:553-563`） | ✅ 有钉子用例（`lastTempCommitRound` 由 0 变 >0） |
| `rollback.round` 触发 | 同一统一出口；用例断言回合号**递增**（不是「非 0」） | ✅ |
| `combat.next` **仅整轮折返**触发 | 读 `nextTurn()`（`room_model_rollback.dart:347-350`）：`if (round != prevRound) advanceRoundInto(out, round);` —— 真条件是「`while` 折返把 `round += 1` 过」，不是「只要 nextTurn」 | ✅ 用例分两段：同轮内推进断言**不含** tempCommit、再推一次断言**含**，并断言 `combat.round` 真的 1→2（钉前提，不是空转） |
| `room.start` **不触发** | `roomActionStart()`（`room_model_actions_room.dart:552-561`）只 `setStatus(inGame)` + 在无回合时 `emit(ROUND)` + `sys('开团！')`，**不走** `advanceRoundInto` | ✅ 用例断言本批有 `round`、无 `tempCommit`、且 `lastTempCommitRound` 仍为 0 |
| `roomCode` 隔离 | Flutter 侧没有老 APP 的 localStorage 临时卡，隔离是**结构性**的（每个 session 只看自己那份 state） | ✅ 用例造「两间房并存、别房推进回合、本房不落库」真断言 |
| 同 round 幂等 | `_lastAutoRound` 作幂等键（`room_card_saver.dart:202-212`，先占回合号再落库） | ✅ 用例「同一 round 通知两次只保存一次」 |
| 存档零 tempcommit | `reduce` 无 `TEMP_COMMIT` 分支（`room_model_reduce.dart:345` 走 default） | ✅ 用例两条：存档 JSON 无字面量 + 客户端 state 无残留 |
| 失败静默 | `onStateChanged` 内 `catch` 只写 `lastError`（:227-231） | ✅ 符合 C2 原要求 |
| 单一触发源 | `room_card_saver.dart` 已不读 `meta.round` 做判据（`roundOf` 仅诊断）；生产调用点唯一（`room_entry_page.dart:973` 在 session listener 里） | ✅ 无并行入口 |

### 4.3 头像链路（白名单 → 远端视角 → 本机优先级）
- **白名单会放行**：`raSanitizeSheet`（`room_model_actions_sheet.dart:60-73`）判定 `^data:image/(png|jpe?g|webp);base64,` 且 `length <= 20000` → 保留；不合法 → `''`。本批上报的正是 `data:image/png;base64,…`，**能过**。旧行为的真因确认：`cardToRoomSheet` 里 `avatar` 是 `avatars/xx.png`（相对路径），过不了正则 → 被洗成 `''` → 远端只剩首字圆点。**真因成立**。
- **远端视角用例真实存在且可证伪**：`p10_t2_avatar_test.dart:392`「成员 sheet.avatar 是 dataURI、本机无该文件 → 队友栏显示图，不是圆点」——它先把 `avatarStore.rootOverride` 指到一个空临时目录（模拟「别人的文件不在我这台」），再让 p2 用 `INTENT.CHAR` 上报 `kTinyUri`，然后在 p1 视角渲染 `GpPlMates`，断言 `GpPlMatesKeys.avatar('p2')` 下**有 `Image`**、**没有 `Text`**（防止「有图像还叠着首字」）。这不是「断言不抛异常」的空壳。**我摘掉 dataURI 分支后它确实红**（§6 #3）⇒ 可证伪。
- **本机优先级**：`AvatarThumb._reload`（`avatar_picker.dart:132-160`）顺序为 dataURI（同步 `MemoryImage`）→ 本机相对路径（`FileImage`）→ 圆点；而 `memberAvatarValue`（`avatar_picker.dart:401-432`）**先**判「本机文件真的存在」再回 dataURI ⇒ 本机高清、远端缩略，方向正确。

### 4.4 缩略图体积 —— 我自己复算了一遍（发现工程师的口径偏乐观）
工程师样本（`p10_t2_avatar_test.dart:192` 打印，我重跑全套时也复现）：
```
[P10-T2] 64px PNG base64 长度 = 7102
```
但那只是「每 6px 一个色块」的图，压缩率偏高。我另写临时用例（跑完即删）用**逐像素伪随机噪声**（体积上界）量：
```
[QA-MEASURE] src=300x300 side=64 uriLen=13330 b64Len=13308 bytes=9979
[QA-MEASURE] src=300x300 side=48 uriLen=8178  b64Len=8156
[QA-MEASURE] src=300x300 side=32 uriLen=3814  b64Len=3792
[QA-MEASURE] src=512x512 side=64 uriLen=5074  b64Len=5052 bytes=3787
```
结论：
- **仍在上限内**（最坏 13,330 < 20,000），且超限会自动降 48（8,178）→ 32（3,814），机制有余量 ⇒ **功能安全，可接受**。
- 但「只有上限的 1/3 以内」的说法**不成立**：最坏样本是上限的 **67%**，比老 APP 的 JPEG（2–4KB）大约 **3 倍**（不是 1.5–2 倍）。已按此订正清单文案（§8），并列入观察项 O1。
- 顺带说明 `512×512` 反而更小（8×8 块平均后更平滑，PNG 更好压），所以「源图越大越危险」不成立，真正的风险是「降采样后仍高熵」的图。

---

## 5. 独立出包对账

### 5.1 三件套
```
$ stat -c '%n %s bytes' build/app/outputs/flutter-apk/app-release.apk
build/app/outputs/flutter-apk/app-release.apk 69919088 bytes
$ sha256sum build/app/outputs/flutter-apk/app-release.apk
5f0338834a2db716f8ebf17e49adde91eaab6f571decbb46c278b90f450b1651
$ unzip -l … | grep libapp.so
  8782728  lib/arm64-v8a/libapp.so
  9732680  lib/armeabi-v7a/libapp.so
  8979336  lib/x86_64/libapp.so
  （181 files）
```
- 69,919,088 字节 > 50MB ⇒ **不是坏包**（<50MB 会白屏）。
- 三 ABI 齐全且各带 `libapp.so`，尺寸与工程师报告逐项一致。
- 版本号仍 `2.17.0+83`（`pubspec.yaml` sha256 `ebb6c72e…`，本批未动）。

### 5.2 native-assets / junction / 红线
`flutter config --list` → `enable-native-assets: true`；`build -> /d/dev/dice-build` junction 完好；全程未 `flutter clean`、未跑 adb / 模拟器 / 真机。

### 5.3 ⚠️ SHA256 与工程师报告不一致（如实说明）
- 工程师：`dc1c9771a8c252195afda2001b58479ce78f8a840124bc673f28f433e7ad0a9c`
- 我这次：`5f0338834a2db716f8ebf17e49adde91eaab6f571decbb46c278b90f450b1651`
- **字节数完全相同（69,919,088）、三个 `libapp.so` 尺寸完全相同、AOT 里能查到本批新字面量**，只有内容哈希不同。
- 为排除「我这边构建不稳定」，我又跑了第二次 `bash tool/build_apk.sh`（增量 37s）：结果哈希**仍是 `5f033883…`**（稳定），说明我这两次是同源同产物；差异在「我这棵树」与「工程师那棵树」之间。
- 我无法逐字节对比工程师那份 APK（工作区里没有留存副本，`build/app/outputs/flutter-apk/` 里只有当前包与一个 40 字节的 `.sha1`）。
- 判定：**不影响交付**（字节数、ABI、AOT 内容、目录结构四项都可核），但「同源必得同哈希」这一条本批**不能宣称**。已按任务要求把清单头部指纹订正为**本次实测值**，并保留 P10 第 1 期指纹（那一批 QA 曾复现为逐字节一致）供回滚对比。建议后续把「交付 APK 副本 + sha256」一起落盘，否则哈希无法互相验证。

---

## 6. 自证伪过程（4 处，全部逐字节恢复）

基准备份（`cp -p` 保留 mtime）与哈希：
```
c09dc019492c2f37eb4016f79a43eb438fe1b69ab4f980a5a5e1642a17dee722  lib/ui/room/sheets/card_sheet_payload.dart
3673ae8e5c1731c083c2a6943039bde3f01a9550f217cd8426a2100ee2ae6688  lib/domain/room_model_rollback.dart
c25d6695482bfe52912c55314eb2a22cce24c3ca7d276cd37f880ec4feef16bc  lib/ui/widgets/avatar_picker.dart
3dac8198df06b8b6a4c9a4b9fdda086c504798c74379e730f030c4b64536d513  test/room_ui_entry_test.dart
```
> 附带一个客观交叉印证：这三个 lib 文件的哈希与工程师报告里「恢复后复跑」写的那三个哈希**完全一致** ⇒ 他上报前确实还原到了同一状态。

| # | 摘/改什么 | 实测变红 | 恢复校验 |
|---|---|---|---|
| 1 | 生产代码改回「总带 `avatar: ''`」 | `room_ui_entry_test` **1 组红**（`Actual` 多出 `'avatar': ''`） | `diff -q` 通过；`c09dc019…e722`；复跑 `+22` 绿 |
| 1b | 同上 + 期望值退回旧写法（不 `remove`） | **仍 1 组红**（`containsKey` 单独拦住） | 同上（测试文件回到 `3dac8198…d513`） |
| 2 | **整条**摘掉 `EVT.TEMP_COMMIT` | `p10_t2_tempcommit_test` **10 组红**（与工程师自报的 10 组一致） | `diff -q` 通过；`3673ae8e…6688`；复跑 `+15` 绿 |
| 2b | 只摘 `pushInto`（保留 `emit`，即「事件进了日志但没进发送计划」） | **仅 1 组红**（纯 domain 的 `combat.next`）—— 见观察项 O4 | 同上 |
| 3 | 摘掉 `AvatarThumb._reload` 的 dataURI 分支 | `p10_t2_avatar_test` **3 组红**：`② dataURI → 渲染成 Image`、`C 远端玩家…显示图，不是圆点`、`D 条目有头像 → 渲染图` | `diff -q` 通过；`c25d6695…16bc`；复跑 `+19` 绿 |

恢复后 mtime 与工程师原值一致（`card_sheet_payload/rollback/avatar_picker` 均 `2026-11-11 00:43`，`room_ui_entry_test` `00:42`），证明是用 `cp -p` 而不是「重写一遍」。

收尾联合复跑（全部证伪实验之后、出包之后）：
```
$ flutter test test/p10_t2_avatar_test.dart test/p10_t2_tempcommit_test.dart test/room_ui_entry_test.dart
00:04 +56: All tests passed!        # 19 + 15 + 22
```
最终哈希复核：`c09dc019…e722` / `3673ae8e…6688` / `c25d6695…16bc` / `3dac8198…d513` / `pubspec.yaml ebb6c72e…` 全部与基线一致，`test/*.dart` 数量回到 **126**，`lib/ui/room/tmp_gate_probe.dart` 已删除。

**关于 #2b（本批最值得说的一条测试质量发现）**：只摘 `pushInto` 时，`emit` 仍会占掉一个 `seq` 写进日志，客户端收到后续事件会发现 seq 缺口 → 自动 `INTENT.SYNC` 补拉 → 把 `tempcommit` 补回来。我加了临时诊断确认：
```
[QA-DIAG] 本批计划条数=4
[QA-DIAG] 序列=[evt:round, evt:log, evt:tempcommit, evt:log]
[QA-DIAG] tempCommit 次数=1
[QA-DIAG] 玩家端 lastTempCommitRound=2
```
⇒ 14/15 组仍然绿。这不说明代码有问题（自愈确实有效），但说明**这些用例分不清「正常推送」与「靠补拉补回」**。已列 O4 建议（不阻塞本批）。

---

## 7. 红线扫描

| 检查 | 结果 |
|---|---|
| `lib/domain/**` 零 Flutter / IO / UI | ✅ 门禁第 07 条：扫 56 个 `.dart` 零命中（`avatar_uri.dart` 只用 `dart:convert` + `dart:typed_data`） |
| 出站只有 `SendPlan.toJson()`、零新增 `jsStr(` | ✅ 门禁第 08 条：14/14，白名单外无；本批零新增 |
| 未跑 adb / 模拟器 / 真机 | ✅ 全程未调用 |
| `build` junction 未删、未 `flutter clean` | ✅ `build -> /d/dev/dice-build` |
| `pubspec.yaml` 未改 | ✅ `2.17.0+83`，sha256 `ebb6c72e…` |
| 出包只跑 `tool/build_apk.sh` | ✅ 两次都是它；脚本本身未改 |
| 未改工程师生产源码（除证伪并还原） | ✅ 四个文件哈希/mtime 均回到原值；`test/*.dart` 数量回到 126 |
| 私密内容不因头像泄漏 | ✅ `feedAvatarOfSeat` 只读成员的 `sheet.avatar`（公开字段），未新增线上字段；私密行仍只取 `{seq,title,text,at,kind}` 五键 |
| 头像不是新的外发通道 | ✅ 头像只走 `INTENT.CHAR.sheet.avatar` 这一个公开字段，且过 domain 白名单（正则 + 20000）后才进广播 |

---

## 8. 真机清单更新点（`_manual_test_checklist.md`，只登记不执行）

1. **新增章节「P0 · P10 第 2 期 A（头像跨设备 + 推回合自动保存）」**，9 条可操作验收项 D1–D9：
   D1 跨设备头像（A 上传→B 看队友栏 / KP 玩家栏，反向再验一次）、D2 本机仍高清、D3 聊天/公开记录条目小头像（无头像不占位）、D4 没设头像显示首字圆点、D5「只给你看」私密栏 KP 头像、D6 推回合自动保存（掉血/掉 SAN → KP 推进 → 玩家回档案看已更新）、D7 开局不该自动保存、D8 同回合连点只保存一次、D9 重伤周回血存的是**恢复后**的值。
2. **头部 APK 指纹订正为本次实测值**：69,919,088 字节 / `5f033883…0b1651` / 三 ABI `8,782,728 / 9,732,680 / 8,979,336`，注明「P10 第 2 期 A 由 QA 独立重新出包」，并**保留两行旧指纹**（P10 第 1 期 `c41213ba…743849`、P11 `b31c4035…dc5422e`）供回滚。
3. **尾部「自动化已验证」订正**：1800 → **1834**（并写明 1800 + 34、两次并发都是 1834、QA 独立数用例）；新增「唯一被改的既有断言不是放宽」一行、「P10 第 2 期 A 34 组会变红（4 处证伪）」一行、APK AOT 行（新数字 + AOT 字面量证据），原 P10 第 1 期的 41 组与 AOT 行**改写为「（历史）」保留**，不删。
4. **订正与现状矛盾的技术债**：
   - 技术债第 6 条 ①「B2 跨设备头像未打通」→ 改为「**已在 P10 第 2 期 A 打通**」，并列明仍未覆盖的三点（SVG 头像不参与缩略、无真机双设备实测、PNG 体积大 1.5–3 倍）。
   - P10 第 1 期章节末尾「三处如实边界」①同上口径订正（保留删除线痕迹，不删原文）。
   - 该章节 B2 表格行加注「P10 第 2 期 A 起此限制已解除，改按 D1 验收；本条不再作为『允许失败』的挡箭牌」。
   - 新增技术债第 7 条：**自动保存触发源已换成 `TEMP_COMMIT`**，列出「推进回合后没更新」的四步排查顺序，并写明「进程被杀前那一回合没收到 `TEMP_COMMIT` 不会保存（与老 APP 同口径）」。
5. **任务 3 的如实延后写进文档**：P2-05 闪烁章节补一段 —— 「只给你看」栏仍用组件自带 `_seenSeq`（行为满足、判据源未统一），工具栏加高与布局骨架延后到布局批次；真机**不要按 tracker 口径要求它**。

---

## 9. 观察项与遗留（**均不阻塞本批**，不构成「源码 bug」）

| # | 观察 | 严重度 | 建议 |
|---|---|---|---|
| O1 | **PNG 体积口径偏乐观**：工程师称「只有 20000 上限的 1/3（7,102 字符）」，我的最坏样本是 **13,330 字符（67%）**，比老 APP JPEG 大约 **3 倍**。功能安全（有 48/32 降级阶梯），但文档口径需订正（已在清单里订正） | P3（文案/口径） | 后续若嫌广播大，可考虑把 64px 默认降到 48（8,178 字符），或引 JPEG 编码包（需改 pubspec，须单开批次） |
| O2 | **自动生成头像（SVG dataURI）不参与跨设备广播**：白名单只放行 png/jpe?g/webp base64，SVG 被洗成 `''` → 远端仍是首字圆点。老 APP 会把 `data:image/svg+xml` 交给浏览器解码后转 JPEG 广播，属**已知差异**；观感接近（自动头像本身就是字圈），不列为缺陷 | P3（体验差异） | 真机 D4 顺手看一眼；要抹平需在 repo 侧解 SVG（要引入依赖，单开批次） |
| O3 | **`avatarThumbOf()` 的 dataURI 入参分支在生产路径上是死路**：`cardToRoomSheetForReport` 传的是 `localAvatarRel(card.raw['avatar'])`，而 `localAvatarRel` 对 `data:` 一律返回 null ⇒ 卡里若真存了合法 PNG dataURI（历史卡/导入卡），缩略会算成空串并**把键删掉**。实际可达性极低（本工程所有写入点只写相对路径或 SVG dataURI，`NewCharacter` 默认 `''`），且与旧行为一致（旧行为白名单也会洗成 `''`） | P3（死路径/文档不一致） | 要么让 `cardToRoomSheetForReport` 直接传 `card.raw['avatar']`（`avatarThumbOf` 自己会先试 dataURI），要么删掉那段分支与注释，避免「文档说有、实际走不到」 |
| O4 | **测试稳健性**：只摘 `pushInto`（事件进日志但不进发送计划）时，14/15 组仍绿 —— 本地回环的 `seq` 缺口 → `INTENT.SYNC` 自愈把 `tempcommit` 补了回来。现有用例能保证「玩家最终会收到」，但**不能**保证「权威端在同一个计划里就推了」。目前只有纯 domain 的 `combat.next` 用例能分辨 | P3（测试质量） | 下一批可加一条纯 domain 断言：`host.advanceRound(n)` 返回的计划里**必须**含 `tempcommit`（不经网络、不靠自愈） |
| O5 | **APK SHA256 不可互验**：字节数/ABI/AOT 内容全一致，但哈希与工程师不同，且工作区没留交付副本，无法逐字节对账 | P2（可追溯性） | 每批把交付 APK 副本 + sha256 落盘（如 `dist/`），否则「同源可复现」只能靠当批自证 |

**未发现需要退回工程师的缺陷**：两个用户点名需求的链路（绑卡 → 缩略 dataURI → 白名单 → 队友栏/KP 玩家栏/条目头像；回合推进 → 统一出口 → TEMP_COMMIT → 玩家落库）都完整、单一入口、可证伪，且与老 APP 口径可逐条对上。

---

## 10. 智能路由与最终结论

- **Round 1**：五项自检 1834/1834 全绿、analyze 零、P4 13/13、P5 14/14、APK 三 ABI。
- **证伪轮**：4 处实验全部按预期变红，逐字节还原后复绿（§6）。
- **发现的问题性质判定**：全部为「口径/文档/测试质量」级别（O1–O5），**无产品行为错误** ⇒ 不需要退回工程师改代码。
- **Routing Decision：NoOne**（全部通过；5 条观察进遗留，其中 O1 已在清单文案订正，O2 已写进「如实边界」，O4/O5 建议下一批处理）。

**IS_PASS: YES**
