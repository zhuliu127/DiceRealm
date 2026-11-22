# P7 真机反馈修复批次 · QA 独立回归复核报告

> 执行：QA 工程师严过关（Yan / `software-qa-engineer-3`）
> 日期：2026-11-10
> 对象：工程师寇豆码 `_p7_transport2.txt`（P7 第二批，7 项真机实测失败一次修复，自评 `IS_PASS: YES`）
> 工程：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`（非 git 仓库，零改动一律用 mtime + sha256 佐证）
> 立场：**不采信工程师日志**，全部自检独立重跑；自己写探针、自己证伪、自己逐字节恢复。
> 本轮为 **Round 1**（最多 2 轮硬限），本轮即结论轮。

---

## 0. 结论速览与智能路由

| 复核项 | 结论 |
| --- | --- |
| 四项自检（全量并发 / 串行 / analyze / 两门禁 / 独立出包） | **全部独立复现**，数值与工程师报值逐字符一致 |
| 1555 账目 | **算平**：19+11+12+11+3=56，1499+56=1555；发现并说明 1 处**口径差**（非差错） |
| ★ 预言机开关是否被架空 | **真实隔离、P4 契约未被架空，接受**（自证伪：关开关即红） |
| 三条生成路径 + AI 拒收闸门 | **成立**，独立探针 4 档 cap × 2 口径 × 3 路径全合法 |
| 大厅门控翻转断言 | **不是「为了绿放宽」**（双向自证伪：恒 true 9 红 / 恒 false 1 红，成对守卫齐备） |
| B / C / D / E 四项 | **独立验收通过** |
| 疑点 1 云分享不带规则标记 | **如实边界，接受**；登记「范围待确认」交用户/PM 决策（详见 §7.1） |
| 疑点 2 `newCharacter()` 兜底 | **无遗漏，接受**（旧版同源契约；给出全调用点清单） |
| 附带判定 A 丢零头 | **上限语义下的可接受取舍**，非需求违约 |
| 红线扫描 | **零违规**（jsStr 14 / domain 纯 / 冻结文件零改动 / build junction 完好） |
| 真机清单 | 已订正头部指纹 + 新增 P1 回归 7 条 + 尾部 1555 + 补登技术债第 5 条 |

**智能路由结论：`NoOne`** —— 未发现需要回工程师的源码 Bug，未发现需要 QA 自修的测试代码问题；两疑点均判「如实边界，接受」并如实登记范围待确认项。**本批不打回工程师**。
唯一需要主理人向用户确认的是「云分享链接是否也要显示规则徽标」这一**范围问题**（§7.1 / 清单 P2 观察项），若用户确认要，则升级为新需求另开批次。

---

## 1. 四项自检独立重跑（不采信工程师日志）

所有测试命令前一律：
`export PATH=/d/dev/flutter/bin:$PATH` + `unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy` + `export NO_PROXY=127.0.0.1,localhost`
（本次环境实际代理值是 `http://127.0.0.1:5151`，仍按红线逐条清除；全程无 WebSocket 报错。）

### 1.1 全量 `flutter test`（默认并发）

```
FULL_TEST_EXIT=0
=== tail ===
00:55 +1554: ... step_background_test.dart: 疯狂表第 9 条（恐惧症）点开 100 条子表
00:56 +1555: All tests passed!
```

### 1.2 全量串行 `flutter test --concurrency=1`

```
SERIAL_TEST_EXIT=0
=== tail ===
03:47 +1554: ... wizard_steps_test.dart: 属性：没填完 / 非法值 / 超总和 各有准确文案
03:47 +1555: All tests passed!
```

### 1.3 `dart analyze`（全项目）

```
ANALYZE_EXIT=0
Analyzing dice-realm...
No issues found!
```

### 1.4 两道静态门禁

```
P4_EXIT=0
[OK]   61 个 POLICY action 全部分支零缺口
[OK]   三个禁改文件存在，且 dice/rules_coc7 未被 P4 反向依赖
==== 合计 13 条，失败 0 条 ====
P4_GATE IS_PASS: YES

P5_EXIT=0
[OK]   jsStr( 命中 ≤ 14 且只在白名单 6 文件
       实际 14 处：room_session_local.dart×3, room_session_remote.dart×3,
       room_text.dart×1, gp_combat_list.dart×5, gp_scene_check_pl.dart×1,
       gp_status.dart×1；白名单外 无
[OK]   门禁字面量不入注释（零命中）—— 扫描 64 个文件
[OK]   弹层不走裸 showDialog —— 扫描 64 个文件，零命中
==== 合计 14 条，失败 0 条 ====
P5_UI_GATE IS_PASS: YES
```

### 1.5 `bash tool/build_apk.sh` 独立出包 + 校验

```
BUILD_EXIT=0
[2/4] 构建 release APK
√ Built build\app\outputs\flutter-apk\app-release.apk (57.8MB)
[3/4] 校验 AOT 产物
  8323976  lib/arm64-v8a/libapp.so
  9273928  lib/armeabi-v7a/libapp.so
  8586120  lib/x86_64/libapp.so
[4/4] 恢复 native assets
===== 出包成功 =====
-rw-r--r-- 60635735 2026-11-10 11:09 build/app/outputs/flutter-apk/app-release.apk
c17cf06b01c25d1540a4a28db3b9948692603dc9c76f7249e0d4ec07da0b622f
```

独立复核（不读脚本自报，另起一条）：
```
60635735 bytes  2026-11-10 11:09:32 +0800
c17cf06b01c25d1540a4a28db3b9948692603dc9c76f7249e0d4ec07da0b622f *.../app-release.apk
unzip -l | grep libapp.so → 三行齐全：8323976 / 9273928 / 8586120
OK: 60635735 >= 50MB（不是白屏坏包）
enable-native-assets: true          ← 出包后已恢复
build -> /d/dev/dice-build          ← junction 完好，未删、未 flutter clean
```
**对账**：字节数 / SHA256 `c17cf06b…` / 三 ABI 尺寸 / debug 签名与主理人已核实值、工程师报值**逐字符一致**。

### 1.6 出包后全量冒烟（确认临时探针删除后回到 1555、native-assets 可跑）

```
SMOKE_EXIT=0
01:04 +1555: All tests passed!
红数 = 0
```

---

## 2. 账目独立算平

### 2.1 新增 5 文件：声明数 vs 运行时数（各自单独跑，不采信报告）

| 文件 | `test(` 声明 | `testWidgets(` | 动态注册 | 独立实跑 |
| --- | --- | --- | --- | --- |
| `test/p7_attr_cap_test.dart` | 16 | 0 | `for cap in [400,460,300,403]` 内 1 个声明注册 4 次 → 16−1+4 | **+19** |
| `test/p7_ai_caps_ui_test.dart` | 3 | 8 | 无 | **+11** |
| `test/p7_fate_test.dart` | 9 | 3 | 无 | **+12** |
| `test/p7_rule_registry_test.dart` | 8 | 3 | 无 | **+11** |
| `test/p7_lobby_gate_test.dart` | 0 | 3 | 无 | **+3** |
| **合计** | | | | **56** |

`19 + 11 + 12 + 11 + 3 = 56`；`1499 + 56 = 1555`，与全量并发 / 串行 / 出包后冒烟三处 `+1555` 一致。

### 2.2 修改的 3 个测试文件（用例数不变，只翻期望 / 加开关）

| 文件 | 声明数 | 独立实跑 | 本批改动 |
| --- | --- | --- | --- |
| `test/room_ui_lobby_test.dart` | 1 + 17 = 18 | **+18** | 招募期期望翻 `findsNothing` + `_gameHost` 三处游戏期正向守卫 |
| `test/qa_p5_priv_probe_test.dart` | 1 + 12 = 13 | **+13** | A-1 招募期期望 + 游戏期守卫 |
| `test/oracle_preset_test.dart` | 13 | **+16** | 仅加 `setUp/tearDown` 切 legacy 开关，fixture 零改动 |

### 2.3 ★ 一处口径差（如实标注，不是账目差错）

工程师报告把 `oracle_preset_test.dart` 记为「13」，那是**显式 `test(` 声明数**；实际运行时为 **16**：`OracleFixture.run()` 会按 `fn` 动态注册 `generateOne（110 例）`、`generate（13 例）` 两个 test，再加 `fixture 覆盖完整性` 1 个 → `13 + 3 = 16`（已读 `test/support/oracle.dart:62-119` 确认 `test(...)` 注册逻辑未被跳过）。
本批对该文件**只加 setUp/tearDown**，声明数与运行时数**均未变**，故 `1499 + 56 = 1555` 不受影响。除此之外 5 个新文件除 4-cap 循环外无其它动态注册，账目无第二处差异。

---

## 3. ★ 预言机开关是否被架空（本批最高危判定）

### 3.1 源码取证（`lib/domain/ai_caps.dart`）

- `bool legacyAttrCapForOracle = false;`（:118）——**默认 false = 生产走新算法**。
- `bool applyAttrCap(...) { if (legacyAttrCapForOracle) return applyAttrCapLegacy(profile, cap); return _applyAttrCapGrid(profile, cap); }`（:133-136）——真实委托，无恒 true / 恒 false 后门。
- `_applyAttrCapGrid`（:161-256）六条不变式 I1–I6 写在注释（:141-155）并被测试逐条钉住：I1 未超限返回 false 原样不动、I2 逐项 `%genStep==0`、I3 `[genMin,genMax]`、I4 总和 ≤ 上限（宁低不反弹）、I5 相对高低非增（相邻倒置交换）、I6 `withLuck` 只对参与求和的 keys 生效；物理下界 `keys.length × genMin` 如实说明且优先 I3。
- `applyAttrCapLegacy`（:263-363）与旧版 `coc7th-card-app/web/js/core/ai.js:458-520` **逐字对照**：`ATTR_MIN=15 / ATTR_MAX=99`、`t.floor()` 后 `min(99,max(15,·))`、余数按小数降序每项 +1（首轮 + 后续 g2 循环）、`total` 只累计初始 floor 之和**不含补齐的 +1**（这一微妙点两边完全一致）、超上限从最高项 −1、按原始值降序稳定排序后相邻倒置交换、写回。确认是**逐字等价**，不是近似实现。

### 3.2 预言机文件取证（`test/oracle_preset_test.dart`）

- `setUp`（:53-56）保存原值 → 置 `true`；`tearDown`（:57-59）恢复保存值。**顶层 setUp 只作用于该文件**（Dart 每个测试文件独立 isolate），不泄漏。
- `fixture.run(<...>{'generateOne':…, 'generate':…})`（:62-74）仍在跑；`test/support/oracle.dart:_expectJsonMatch`（:134-175）是**逐字段深比较 + 键集合一致 + 随机数消耗数一致**，未被注释 / 跳过 / 放宽。
- 冻结 fixture `preset.json` 有 **123 例**，其中 **4 例 `attrCap>0`**（420 / 380 / 500 / 另一例），`expect` 里就是旧 JS 的非 5 倍数输出 —— 这 4 例是 legacy 与旧 JS 等价性的直接证据。

### 3.3 冻结 fixture 零改动（mtime + sha256）

| 文件 | mtime | size | sha256 |
| --- | --- | --- | --- |
| `test/fixtures/preset.json` | 2026-11-08 14:55:52 | 4,541,338 | `3b2e2b3c75e952d3e6f3cca4378c762b7963b8bd99739f5d1adca4b0552e57c3` |
| `test/fixtures/qa_p3_ai_oracle.json` | 2026-11-08 17:33:32 | 156,429 | `350c8f60970aca36f8bc04c190ace8e39af053e3185ef19a13857b88f5652327` |
| `test/fixtures/room_sequences.json` | 2026-11-09 03:53:05 | 828,314 | `1d5f71f29c0fa71e87dc1093e643699f3658765d32adf04bb42e4c6dde90fcd7` |

三份 mtime / size 与工程师报告一致，且全部**早于本批**（11-10 08:2x–10:1x），零改动。

### 3.4 自己写临时探针（跑完删除）

`test/qa_p7_probe_test.dart`（7 组 T1–T7，与预言机文件**同批次**跑，验 isolate 隔离）：

```
PROBE_EXIT=0
00:04 +23: All tests passed!        （7 组探针 + 16 组预言机）
失败标记数 = 0
```

探针内容：T1 断言本 isolate `legacyAttrCapForOracle == false`（开关未串味）；T2 6 档 cap × 两口径逐项 `%5==0` / `[15,90]` / 总和 / 相对高低；T3 未超限返回 false 且原样；T4 `applyAttrCapLegacy` 与开关路径逐字段一致且 legacy 输出确实非 5 倍数；T5 三条生成路径（自造输入 + 自造 seed `Lcg(771103)`）；T6 `attrsFromAi` 拒收且原 Map 不被就地规整；T7 卡带标记 / 云分享投影不带 / 注册表兜底（疑点 1、2 代码级证据）。

**探针实测压缩输出（与工程师测试不同的一组输入）**：

```
[T2] cap=400 luck=true  → str=35 con=60 siz=25 dex=55 app=15 int=65 pow=30 edu=50 luck=65   (Σ=400)
[T2] cap=400 luck=false → str=45 con=75 siz=30 dex=65 app=20 int=75 pow=35 edu=55 luck=99   (8 项 Σ=400，luck 原样 99 未动)
[T2] cap=460 luck=true  → str=45 con=70 siz=25 dex=60 app=20 int=75 pow=35 edu=55 luck=75   (Σ=460)
[T2] cap=300 luck=true  → str=30 con=45 siz=15 dex=40 app=15 int=50 pow=20 edu=35 luck=50   (Σ=300)
[T2] cap=403 luck=true  → ... Σ=400  (非 5 倍数上限，丢 3 点零头，绝不反弹)
[T2] cap=140 luck=true  → 15×8 + 20 = 140
[T2] cap=50  luck=true  → 9×15 = 135  (低于物理下界，优先 I3 压到规则下界，如实说明)
```

### 3.5 自证伪（比工程师的「摘 5 倍数规整」更直接命中开关本身）

临时把 `test/oracle_preset_test.dart:55` 的 `legacyAttrCapForOracle = true;` 改成 `false;`：

```
ORACLE_FALSE_EXIT=1
失败标记数 = 1
  generateOne / generateOne/caps#1.attributes.str：实际 55 ≠ 期望 57
Failing tests: preset.js → preset_gen.dart 等价性 generateOne（110 例）
```

→ 证明：① 预言机**确实在逐字段比对冻结 fixture**（不是被跳过 / 恒绿）；② legacy 开关**真实生效、 indispensable**；③ 生产算法输出 55（5 倍数）与旧 JS 期望 57（非 5 倍数）**确实不同**，隔离是真的。

恢复：
```
diff -q /tmp/qa_p7_oracle.bak test/oracle_preset_test.dart   → 零输出（逐字节一致）
恢复前/后 sha256 均 = d025dc32eecf1635d2ff2f72ba1559a2a88b29a170084063415a814dde71cdbc
RESTORE_EXIT=0 → 00:04 +16: All tests passed!
```

### 3.6 判定

> **真实隔离、P4 契约未被架空，接受。**
> 旧算法一行未改地保留给预言机，生产走 5 倍数网格；开关默认 false、只在预言机文件 setUp/tearDown 内切换、tearDown 恢复原值、跨文件独立 isolate 无串味；冻结 fixture 零改动；预言机仍逐字段 + 随机数消耗数比对且关掉开关立刻变红。**没有为了绿放宽断言、没有悄悄改 fixture 期望、没有用「有意偏离旧版」掩盖 P4 契约被架空。**

---

## 4. 三条生成路径合法性 + AI 拒收闸门

### 4.1 多档上限 × 两口径（独立探针 T2/T5）

上限覆盖 `400 / 460 / 300 / 403（非 5 倍数）/ 140（极小可行）/ 50（低于物理下界）`，`withLuck` 两口径全测：逐项 `%5==0`、落在 `[15,90]`、总和 ≤ 上限（低于物理下界时压到 `9×15=135` 或 `8×15=120` 并优先 I3）、相对高低非增、不含幸运时 `luck` 原样不动。另 403 专门验「不因取整反弹」。全部通过。

### 4.2 三条同源路径（独立探针 T5）

- **AI 卡**：`applyAttrCap(profile, caps)` → `preset.buildFrom(..., PresetOptions(caps, ruleSystemId))`；
- **5 张随机卡**：`preset.generate(5, PresetOptions(caps, ruleSystemId))`，逐张验；
- **彩蛋卡**：`preset.generateOne(PresetOptions(profile: egg.toProfile(...), caps, ruleSystemId))`。

三路径在 4 档 cap 下均逐项合法、总和达标、`ruleSystemId` 正确，且都走同一份 `_applyAttrCapGrid`（`preset_gen.dart:1453-1467 _build` 是唯一造卡点）。

### 4.3 `attrsFromAi` 拒收闸门

`preset_gen.dart:204` 起：全 5 倍数且在 `[15,90]` 收下；任一项非 5 倍数 → **整块拒收**（探针 T6 额外断言原 Map 的 `str` 仍是 53，**没有被就地规整**，即不存在第二套规整实现）；缺 `luck` 也拒收；越界 `100` / 负数拒收。拒收后由规则层 `genRandom()` 重掷（`p7_attr_cap_test.dart:331-359` 已验证重掷出的卡合法）。

### 4.4 未超限 I1

`applyAttrCap` 返回 `false` 且属性 Map **逐字节不变**（探针 T3，故意喂 `str=53` 非 5 倍数验证「未超限也不许动」）。

### 4.5 `attrFieldError` 未被改松

`lib/ui/create/chargen_logic.dart:26-33` 仍是 `v < genMin || v > genMax` → 区间文案、`v % genStep != 0` → `'必须是 5 的倍数'`，与 P3 移植时一致。**没有为了迁就压缩算法而放宽 UI 校验**；反过来是压缩算法去满足它。

---

## 5. 大厅门控：翻转断言不是「为了绿放宽」

### 5.1 成对守卫取证

- `test/room_ui_lobby_test.dart:195-245` 招募期：`closeRoom / room.close / kpStartGame / members` 仍 `findsOneWidget`，同时 `explore / kpTools / openKpPanel / GpStatus / GpDiceBar` 全部 `findsNothing`，并写明「不是『为了绿放宽』」；`:462-490` 的 R10 用例在招募期 `findsNothing` 之后，紧接着 `pumpWidget(_gameHost(boot))` 断言游戏期 `kpPanelKey findsOneWidget`。
- `test/p7_lobby_gate_test.dart`：`inGame:true` KP 视角对 `GpStatus / GpDiceBar / kpPanelKey / GpKpTools / GpMapStage` **5 处 `findsOneWidget`**（:57-67）；招募期对 8 个 key + 2 个 type `findsNothing`，并对 `closeRoom / copyInvite / kick('p1') / kpStartGame` `findsOneWidget`（:102-110）；玩家视角另有一组（:114-131）。
- `test/qa_p5_priv_probe_test.dart:88-126` A-1 组同样是「招募期 `findsNothing` + 游戏期 `RoomGamePage findsOneWidget`」成对。
- 统计：`room_ui_lobby_test.dart` 内 `findsNothing` 30 处 / `findsOneWidget` 23 处，**不是把 `findsOneWidget` 一改了之**。

### 5.2 产品代码门控（`lib/ui/room/room_lobby_page.dart:143-186`）

```
final inGame = isInGame(state);
if (isKp) ...[ _startBlock, if (!inGame) _roomLifecycleBlock(context) ]     // 招募期保留关房
if (inGame) ...[ if (isKp) _kpManageBlock, _exploreBlock,
                 if (isKp) _kpToolsBlock, const GpStatus(),
                 SectionBox(title:'掷骰', child: const GpDiceBar()) ]        // 5 类块仅游戏期
```
`closeRoom`（:646/653/657）、`copyInvite`（:253）、`kick`（:449/452/457）、`kpStartGame`（:618）招募期仍在；`_roomLifecycleBlock` 只 `!inGame && isKp`；`_kpManageBlock` 挂 `inGame && isKp`（T-30 修复点）。

### 5.3 双向自证伪（自己改、自己恢复）

```
基线 sha256 = 613d740255c828a3dde7da46be48a00e1ffd353e1619aad7662d13e99b4efebd
反向 1：final inGame = true;   → GATE_TRUE_EXIT=1，失败标记 9
         （招募期冒出 5 类块，Expected: no matching candidates ×6；
           room_ui_lobby_test 「招募期大厅 R10」等变红）
反向 2：final inGame = false;  → GATE_FALSE_EXIT=1，失败标记 1
         （room_ui_permission_test.dart「T-30 运行时等价 大厅页 × 三视角」变红）
```

### 5.4 逐字节恢复证据

```
cp /tmp/qa_p7_lobby.bak lib/ui/room/room_lobby_page.dart
diff -q → 零输出（逐字节一致）
sha256sum → 613d7402...（恢复前后、备份三处完全一致）
RESTORE_EXIT=0 → 00:07 +53: All tests passed!（4 个相关文件分片复跑全绿）
```
★ 该 SHA `613d740255c828a3dde7da46be48a00e1ffd353e1619aad7662d13e99b4efebd` 与工程师报告第四节「反向 C」给的基准 SHA **逐字符一致** —— 说明我拿到的产品源码与工程师出包时的源码是同一份字节，排除「临时改完忘恢复 / 用旧源码凑绿」。

### 5.5 T-30 权限回归独立复核（确认不是被放宽）

`test/room_ui_permission_test.dart` `_boot` 用 `inGame: true`（:214），即 T-30 故意在游戏期渲染 `RoomLobbyPage` 查锚点。旁观者断言 `actEnabled(tester), isEmpty`（:427，理由「一个 act 锚点都不该有才是正确结果……这是结构断言，不是放宽」）+ `expectGateEquivalence(..., requireAtLeastOne:false)`（:429-430）+ 每个 `kick` `findsNothing`（:432）。`expectGateEquivalence` 仍逐点断言 `enabled == gate.can(op)`（:275），`gate.can` 口径在 `room_lobby_page.dart` 10 处全部保持 `enabled: gate.can(op)`。**工程师自报的 T-30 回归是收紧产品代码（`_kpManageBlock` 补 `isKp`），不是放宽测试**；恒 false 自证伪也证明 T-30 现在真的会红。

### 5.6 判定

> 翻转断言**成对存在、有正向守卫、双向可证伪、恢复逐字节** → 不是「为了绿放宽」，接受。

---

## 6. 其余四项独立验收（B / C / D / E）

| 项 | 独立取证 | 结论 |
| --- | --- | --- |
| **B 房规自定义** | `parseAiCapInput`（`ai_create_page.dart:115-126`）纯函数：空→0、负数/非数字/>9999 → `value:null` + 可见文案；`_applyCustomCaps`（:679-699）**零 await**，非法时「设置里一个字节都不写」只 `setState` 上屏；`SettingsRepoCapsSavePort.save() => unawaited(repo.save())` 同步 `void`（:135）；`SettingsRepo.applyToDomain() => preset.presetSettings = _settings`（:220）同步；`presetSettings` 是变量（:69）、`activeCaps` 现读（:122）→ 填完立即生效。测试 `p7_ai_caps_ui_test.dart:102-151` 断言 `settings.aiAttrCap==380` + `presetSettings['aiAttrCap']==380` + `capsFromSettings(...).attrCap==380` + `port.saves>0` + 常显 `caps.text` + 「自定义」Chip 与三档互斥；:184 验 0/空=不限；:216/:234 验非法拒收 + UI 前置过滤；:257 验随机卡与 AI 卡都吃到 300。AI 页 3 处 `await` 全在**既有** AI 生成/取消链（`makeCharacter` / `_generate` / `finally ticker.cancel()`），房规保存路径零 await、零 Timer / Future.delayed / AnimationController | **通过** |
| **C 规则前置** | `_ruleSelected => RuleRegistry.isAvailable(_selectedRuleId)`（:256）；6 个生成入口全部挂 `_canStart`：`ai_generate`（:650）、`ai_use_random_from_config`（:571）、`ai_retry`（:958）、`ai_fallback_random`（:977）、`ai_regenerate`（:1004）、`ai_random_batch`（:1123）；`_runAi`（:296）与 `_generateRandom`（:388）内部还有二次守卫；两处引导 `ai_rule_hint`（:526）/ `ai_generate_rule_hint`（:660）；未开放项 `onSelected: null`（:507-514）。测试 :312-360 断言 `onPressed isNull`、`calls==0`（K7 不放假按钮）、选规则后启用；:362-389 断言 `1 / 8` 首步「基本资料」+ `StepRules findsNothing`；:391-397 断言手动新建仍 `1 / 9` 首步「规则」；:399 验分母/编号/末步自洽。`CreateFlowPage({skipRules = false})`（:30）、`WizardSteps({skipStepIds = const <String>{}})`（:179）带默认值，`app.dart:63 const CreateFlowPage()` 未破。`validateRules(Character c) => null`（`wizard_steps.dart:81`）数据层恒通过 | **通过** |
| **D 规则标记** | `rule_registry.dart` 纯 Dart，`all/placeholders/availableRules/defaultRule/byId/resolve/shortNameOf/effectiveId/isAvailable` 齐备，COC7 字段全部取自 `Coc7` 常量、`available:false` 占位如实标注不可选；`preset_gen.dart:106 ruleSystemIdOf`、`:1467 newCharacter(ruleSystemIdOf(opts))` 去硬编码、`:1857 summaryOf` 补标记；三处徽标 `summary_rule_badge` / `card_rule_badge_<id>` / 详情「规则」行（测试 :212-260 逐个 `findsOneWidget`）；老卡 `normalize` 补默认且不伪造出处（:153-170）；单卡导出 / 全量存档 / 导入往返、非默认标记不改写（:172-208）；**全库 `lib/ui` 对 `== 'coc7'` 零命中** | **通过** |
| **E 天命** | `chargen_logic.dart`：`isValidFateN`（2–10）、`rollFate` 唯一随机源 `genRandom()`（:347）且 `assert` 逐项 `%5==0 && [genMin,genMax]`（:350-353）、掷出后 `f['rolled']=true` 且 `rollFate` 早退 `return false`（:342）、`pickFate` 写回 9 项 + `picked` + `attributeMode='fate'`（:368-380）；`draft.raw['fate']` 纯数据；`step_attrs.dart` 第三档 + 5选1/10选1 快捷 + `readOnly: rolled`（:173）+ `onPressed: rolled ? null : _rollFate`（:211）+ 选组按钮锁定（:290）；`wizard_steps.dart:101-109` 硬拦截文案逐字对齐旧版「天命还没掷出：先点「掷出天命」」/「请先从 N 组天命里选一组」；`checkAttributes` 的 `enforceCap` 只在 `pointBuy` 生效（:113）。`p7_fate_test.dart` 12 组覆盖 N 边界 1/2/10/11、JSON 往返、切换模式不串、硬拦截（:226-236）及**反向守卫**（:238-263 同卡切 pointbuy 确实被拦，防恒绿） | **通过** |

---

## 7. 两个疑点的明确判定（智能路由）

### 7.1 疑点 1：云分享载荷不带规则标记

**用户口径**：主理人派工转述用户明确要求「**人物卡一旦生成，就打上规则标记**」，本轮 7 条真机反馈之一是「卡缺规则标记」（用户在 App 里看卡时发现）。

**代码级 / 历史级证据链**：

1. 旧版 `coc7th-card-app/.../js/core/store.js:64-69`：
   ```js
   function newCharacter(ruleSystemId) {
     return { id: uid(), userId: 'local', ruleSystemId: ruleSystemId || 'coc7', ... }
   }
   ```
   **卡实体的 `ruleSystemId` 字段旧版本来就有**（冻结 fixture `preset.json` 的 expect 里出现 164 次 `ruleSystemId:'coc7'`，可复验）。
2. 旧版 `.../js/app.js:761`：`h('span.tag.rule-tag', { text: ruleLabel(c.ruleSystemId) })` —— **旧版卡列表本来就有规则徽标**。用户报的「卡缺规则标记」是 Flutter 移植时漏了这枚 tag，本批 D 是**补齐旧版已有能力**，不是新造字段。
3. 旧版 `.../js/core/share.js:71-97` `buildPayload(c)` 的 `data` 字段：`characterName / playerName / basicInfo / attributes / derivedStats / status / assets / background / skills / weapons / items / mythos / history / unitName / sharedAt` —— 与 `lib/net/share_client.dart:89-135 buildSharePayload()` **逐字对应，两者都不含 `ruleSystemId`**。注释明写「这是**精简视图**，不是完整存档：目的是让对方能看、不能改；完整卡仍在本机，导出/导入走另一条路径」。
4. 本批 D 已覆盖需求验收面：`c.raw['ruleSystemId']` 写入、卡面/卡列表/详情三处徽标可见、单卡导出 / 全量存档 / 导入落库三条往返不丢标记且非默认值不改写（`p7_rule_registry_test.dart:153-208`）。
5. `lib/net/**` 冻结是**主理人本批派工明确设定的红线**（「零改动：`lib/net/**`」），不是工程师自设的挡箭牌。工程师在 `_p7_transport2.txt` 遗留 #3 明确写「**如实记为缺口**」「若要让云分享链接也带规则徽标，需另开批次并先解除 `lib/net/**` 冻结」，**未宣称已满足、未写「不是需求违约」**。这与前两批 QA 抓到的「把实现约束写成已知限制掩盖需求违约」有本质区别：那次是不如实 + 判 PASS，这次是如实登记 + 给出修复前提。

**判定：`如实边界，接受`（本批不打回工程师）。**
理由：用户要求的「卡一旦生成就打上规则标记」验收面 = 生成 → 卡实体带标记 → **App 内可见** → 导出/存档/导入不丢，已全部覆盖并有针对性用例；云分享是旧版同源的**独立只读投影**（连 `avatar` 都剔除），不属于「生成」阶段，也从不写回卡实体；扩展它要改出站结构并解除冻结，属范围外。

**但不默认接受 / 不掩盖**：已在真机清单 P1 新章节末尾登记 **「范围待确认（P2 观察项）」**，并在技术债第 5 条如实写明。若用户/PM 确认「分享出去的链接也必须显示 COC 7th 徽标」属于本轮需求，则**升级为功能缺口**，按路由回报主理人中转工程师、另开批次（先解除 `lib/net/**` 冻结）。请主理人在真机统一测试时向用户确认这一条。

### 7.2 疑点 2：`newCharacter()` 无参兜底仍保留 `'coc7'`

**全库 `newCharacter(` 调用点清单（`lib/**`）**：

| 位置 | 调用 | 是否传规则 id |
| --- | --- | --- |
| `lib/domain/character.dart:91` | 定义 `newCharacter([String? ruleSystemId])`，:97 `(null/空) ? 'coc7' : ruleSystemId` | 兜底（**旧版 `ruleSystemId \|\| 'coc7'` 契约逐字移植**，非本批新造） |
| `lib/domain/character.dart:246` | `Character([raw]) : raw = raw ?? newCharacter()` | 无参；**生产代码里没有直接 `Character()` 调用**（`grep 'Character()'` 只命中定义与注释） |
| `lib/domain/normalize.dart:39` | `newCharacter(rsRaw == null ? null : jsStr(rsRaw))` | 老卡缺标记时补默认（符合「不伪造出处」） |
| `lib/domain/preset_gen.dart:1467` | `Character(newCharacter(ruleSystemIdOf(opts)))` | **显式**经 `RuleRegistry.effectiveId` |
| `lib/ui/create/create_flow_page.dart:59` | `Character(newCharacter(RuleRegistry.defaultRule.id))` | **显式**经注册表 |
| `lib/net/ai_create.dart:_land`（:159） | `preset.buildFrom(profile, sid, PresetOptions(caps: caps))` | 未显式传所选 id，但 `_build` 内 `ruleSystemIdOf(opts)` → `RuleRegistry.effectiveId(null)` → `defaultRule.id`（**注册表常量，非字面量硬编码**）；UI 出口 `ai_create_page.dart:171` 与 `:340-341` 两处覆盖写为 `RuleRegistry.effectiveId(_selectedRuleId)` |
| `lib/ui/room/sheets/sheet_bind_char.dart:195` | `Character(<String, Object?>{})` | 传空 Map（**不走 `newCharacter()` 兜底**），是「清空房卡数值」的 payload，不是人物卡生成 |
| 其它 `Character(raw)` | `card_transfer.dart:170` / `character_repo.dart:181,193` / `room_state_writer.dart:63` / `ai_create_page.dart:1080` | 从已有 raw 构造，保留原标记 |

**其余证据**：`lib/ui` 对 `== 'coc7'` **零命中**；`'coc7'` 字面量只剩 `character.dart` 兜底、`normalize.dart` 注释、`preset_gen.dart` / `rule_registry.dart` / `create_flow_page.dart` 注释、`rules_coc7.dart:868 Coc7.id` 常量，以及 `room_model_save.dart:76` / `room_model_state.dart:54` 的**房间 meta `rules` 默认值**（P4 基线敏感，与人物卡注册表不是同一概念，本批未动）。

**判定：`无遗漏，接受`，不构成真缺陷。**
所有生成路径都经 `ruleSystemIdOf` / `RuleRegistry`；不存在「不传规则 id 就产出硬编码且不可查的卡」的生成路径；`newCharacter()` 无参兜底是旧版数据契约 + domain 防环的最低兜底，其值语义与 `Coc7.id` 一致。

**如实标注一处架构细节（潜在风险，非当前缺陷）**：`AiCreateService._land`（`lib/net/**` 冻结）不带用户所选规则 id，靠 UI 两处覆盖写回。当前只有 COC7 已开放，`effectiveId` 恒为 `coc7`，结果等价；**将来扩展多规则时**，若出现不经过 `AiCreatePage` 的调用方直接用 `AiCreateService`，那张卡会带默认规则标记而非所选规则 —— 需在那批次一并处理。

### 7.3 附带判定：A 的「网格压缩后总和可能低于上限（丢零头）」

- 用户诉求是「别太强 / 不超上限」，且属性**必须**是 5 倍数（规则合法）。在 `genStep=5` 的整数网格上，非 5 倍数上限必然产生 `< 5` 点零头，不可能精确命中；I4 明确选择「宁可略低于上限，绝不因取整反弹超限」。
- 探针实测：`cap=400/460/300/140` 精确等于上限；`cap=403` → 400（丢 3）；`cap=50`（低于物理下界 135）→ 135，此时 I4 无法成立，算法优先 I3（规则区间），工程师在 `ai_caps.dart:151-154` 注释**如实说明**且 `p7_attr_cap_test.dart:193-202` 逐条钉住，调用方不会拿到非法属性。
- **判定：`上限语义下的可接受取舍`，不是需求违约。**

### 7.4 智能路由

> 源码 Bug → 无（无需回报 `team-lead` 中转工程师）
> 测试代码问题 → 无（无需 QA 自修）
> 设计取舍 → 三处均写进本报告「接受」并登记范围待确认项
> **结论：`NoOne`**

---

## 8. 红线扫描

| 红线 | 独立证据 | 结论 |
| --- | --- | --- |
| `jsStr(` 仍 14 处、零新增、零白名单扩充 | `grep -rho "jsStr(" lib/ui/room` = **14**，分布 6 个白名单文件；P5 UI 门禁第 1 条 `[OK] 白名单外 无` | ✅ |
| `lib/domain/**` 纯度 | 全目录零 `package:flutter` / `dart:io` / `dart:ui`；`ai_caps.dart` 只 import `js_compat.dart` + `rules_coc7.dart show genMax,genMin,genStep`（同层纯 domain）；`rule_registry.dart` 只 import `rules_coc7.dart show Coc7` | ✅ |
| `pubspec.yaml` / `lib/net/**` 零改动 | mtime `2026-11-08 18:55` / `lib/net` 最晚 `2026-11-09 21:55`，全早于本批（11-10 08:2x 起） | ✅ |
| 冻结 fixture 零改动 | 见 §3.3（mtime + size + sha256 三证） | ✅ |
| `LogRecord.toWireJson()` / `SendPlan.toJson()` / 出站结构零改动 | 定义文件 `lib/domain/room_types.dart` mtime `2026-11-08 20:59`，早于本批 | ✅ |
| `build` junction 完好、未 `flutter clean` | `build -> /d/dev/dice-build`；`build/app/outputs/flutter-apk/` 下 APK 与 `.sha1` 均在；脚本只 `rm -f "$APK"` | ✅ |
| 零 `Timer` / `Future.delayed` / `AnimationController` / 裸 `showDialog`（车卡 UI 新增部分） | `ai_create_page.dart` / `step_attrs.dart` / `chargen_logic.dart` 四者全零命中；P5 门禁「裸 showDialog 零命中」「showModalBottomSheet 只 1 处」 | ✅ |
| `gate.can(op)` 与旁观者零发包口径不变 | `room_lobby_page.dart` 10 处 `enabled: gate.can(op)` 全在；含 T-30 在内的四个相关文件分片复跑 `+53: All tests passed!`；旁观者 `actEnabled isEmpty` 结构断言未放宽 | ✅ |
| `const` 构造与既有调用点未破 | `const CreateFlowPage({skipRules=false})` / `const AiCreatePage(...)` / `WizardSteps({skipStepIds=const <String>{}})` 均带默认值；`app.dart:63,69` 的 `const` 构造一行未改；全量 1555 编译通过 | ✅ |
| 未跑 adb / 模拟器 / 真机联调 | 本轮命令仅 `flutter test` / `dart analyze` / `node 门禁` / `build_apk.sh` / `stat` / `sha256sum` / `unzip` / `grep` / `sed` / `cp` / `diff` / `node` / Read / Write / Edit | ✅ |
| 非 git 仓库，用 mtime + sha256 佐证 | 全程未用 `git status` / `git diff` | ✅ |

---

## 9. 真机清单更新点（`_manual_test_checklist.md`，只登记不执行）

- **头部 APK 订正**：`60,602,967 / f143a0b8…` → **`60,635,735 字节 / 57.8MB / c17cf06b01c25d1540a4a28db3b9948692603dc9c76f7249e0d4ec07da0b622f` / 三 ABI / debug**；「最近一次订正」改为 P7 真机反馈修复批次，并加注「由 QA 独立重新出包、三 ABI / 字节数 / SHA256 独立复核、本批未跑 adb / 模拟器 / 真机」。
- **新增 `## P1 · 真机反馈修复回归（2026-11-10）` 章节**（插在 `P0 · 出包与启动` 与既有 `P1 · 车卡器` 之间），7 条可操作步骤逐条对应用户实测的 7 个问题：① AI 卡 5 倍数 + 继续完善不卡死；② 随机 5 张逐张合法；③ 房规四项自定义即时生效 / 互斥 / 非法提示 / 0 空不限 / 杀 App 后落盘；④ 先选规则 + 6 个入口停用 + 两处引导 + 三处徽标 + `1/8` vs `1/9`；⑤ 天命 N 选一 / 快捷 / N 2–10 / 锁定 / 硬拦截文案 / 每组 5 倍数 / 不误套购点上限；⑥ 招募期不出现 5 类游戏期块；⑦ 开始游戏后 5 类块都在 + 旁观者不越权。末尾附 **「范围待确认（P2 观察项）」** 登记云分享链接不带规则徽标。
- **尾部「自动化已验证」**：`全量测试 1499 组 0 红` → **`1555 组 0 红`**，证据栏同步写明本批 QA 独立回归 + 双向自证伪恢复后复跑 + 出包后冒烟。
- **「已知技术债」1~4 逐条复核**：与现状**均无矛盾**（多播锁 / 存档落盘 / 奖惩骰 K16 / debug 签名本批都未改变），故一条未删、未改口径；第 4 条仅补注「本批重出的包仍是 debug 签名」。**新增第 5 条**如实登记本批两处边界：房规设置「发起即返回」落盘未在真机验证、云分享精简视图不带规则徽标。
- 篇幅 301 → **329 行**；`grep -n '^##'` 显示全部 17 个章节，原有 16 个章节与 P0/P1/P2 条目**一条未删**。

---

## 10. 遗留问题 / 已知边界（如实，不掩盖）

1. **7 个真机问题的实际装机复验仍待用户统一真机测**（本批严禁 adb / 模拟器 / 真机）；清单已登记 7 条可操作步骤，本批一个字未执行。
2. **B 的平台边界**：`SettingsRepoCapsSavePort` 是「发起即返回、不等待」的 `unawaited(repo.save())`，失败只记 `SettingsRepo.lastError`；真机文件系统行为 / 进程被杀时的持久化未验证（清单第 3 条第 ⑦ 点顺带验）。
3. **云分享载荷不带规则标记**：判「如实边界，接受」但**范围待用户/PM 确认**；若确认属需求则升级为新需求，另开批次并先解除 `lib/net/**` 冻结（清单 P2 观察项 + 技术债 5）。
4. **A 有意偏离旧版压缩算法**：已用 `applyAttrCapLegacy` + 开关隔离预言机、P4 冻结基线零影响；将来若用生产算法重新生成 `preset.json` 的 caps 用例，期望值会变，届时需同步基线并写明依据，不能悄悄改（关掉开关即红的证据见 §3.5）。
5. **服务层不带用户所选规则 id**：`AiCreateService._land` 靠 UI 两处覆盖；当前仅 COC7 等价，扩展多规则时需处理（§7.2）。
6. **`newCharacter()` 无参兜底**：旧版同源契约 + domain 防环保留，所有生成入口显式经注册表。
7. **大厅门控 F 的取舍**：招募期保留关闭房间·结团 / 踢人 / 复制邀请 / 准备 / 绑卡 / 开始游戏；切模式 / 战斗准备 / 结束战斗 / 探索 / KP 工具 / 待办 / 掷骰移到游戏期由 `RoomGamePage` 承载。
8. **APK 仍 debug 签名**：可侧载安装、不可上架；真机测完再谈 release 签名。
9. **未跑 adb / 模拟器 / 真机联调**；本轮所有结论限于「代码 + 自动化 + 出包产物」。

---

## 11. 最终判定

```
IS_PASS: YES（代码 + 自动化 + 出包产物层面）
智能路由: NoOne
Round: 1 / 2（本轮即结论轮，不进入 Round 2）
```

复核未发现需要打回工程师的源码缺陷，未发现「为了绿放宽断言 / 架空门禁」的行为；预言机隔离、大厅门控翻转、账目 1555、四项自检、独立出包指纹均经独立取证与自证伪成立。两个点名疑点判「如实边界，接受」并如实登记范围待确认项，交由主理人在真机统一测试时向用户确认。**真机 7 条复验仍待用户执行**，清单已备好。

> 附：本轮创建的唯一临时文件 `test/qa_p7_probe_test.dart` 已删除（`ls` 零残留）；`test/oracle_preset_test.dart` 与 `lib/ui/room/room_lobby_page.dart` 两处临时改动均 `cp` 备份 + `diff -q` 零输出 + sha256 双证逐字节恢复；恢复后分片 `+53`、预言机 `+16`、出包后全量 `+1555` 三次复跑全绿。`qa_p7_close_report.md` 与工程师源码一字未改。
