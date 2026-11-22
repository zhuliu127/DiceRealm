# QA 报告 · P13 横屏游戏页背景接入（A1）独立验证

> 验证人：QA 工程师 严过关（Yan / `software-qa-engineer`）
> 验证性质：**独立验证（fresh eyes）**，不复用工程师寇豆码的自验结论；本轮**未修改任何生产源码**（`lib/**` 零字节改动）
> 工程根：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`，`version: 2.26.0+96`（未升版本、未出包、未推 GitHub）
> 架构师审查报告 `_p13_asset_audit.md`：只读参考，未改动
>
> **结论速览：`IS_PASS: YES / NoOne`** —— 全量 **2167** 条全绿；新增 widget 级 wiring 测试真正锁住「调用点是否把 `landscape` 传进去」；接线级反向证伪**真变红**且生产源码**逐字节恢复**。

---

## 一、被验证的改动（逐文件实读确认，非凭描述）

| 文件 | 实读结论 |
| - | - |
| `lib/ui/art.dart:153-165` | `gameBg` = `e1_game_bg_9x16.webp`（暗竖）、`gameBgLight` = `e1_game_bg_light_9x16.webp`（亮竖）、`gameBgLand` = `e2_game_bg_land_16x9.webp`（暗横，无亮色版）。`gameBgFor(Brightness b, {bool landscape = false})`：`!landscape` 走 `pick(gameBg, gameBgLight, b)`，`landscape` 走 `pick(gameBgLand, gameBgLight, b)`；`pick(dark,light,b) = b==dark ? dark : (light ?? dark)`（`:75-76`）。`ArtImage` 是 `StatelessWidget`（`:240-252`），公开字段 `final String path`，构造第一个位置参数即 path。 |
| `lib/ui/room/room_game_page.dart:276-277, 296-304` | `:276` `final Size screenSize = MediaQuery.of(context).size;`、`:277` `final bool landscape = screenSize.width > screenSize.height;`；`:300-303` 背景层 `Positioned.fill(child: ArtImage(Art.gameBgFor(Palette.brightness, landscape: landscape), fit: BoxFit.cover))` —— **确实用 `ArtImage` 渲染**（不是 `artDecoration`），因此 `ArtImage.path` 的 widget finder 可精确命中。选图读的是**全局 `Palette.brightness`**，不是 `Theme.of(context).brightness`。 |
| `test/p13_landscape_bg_test.dart` | 5 条**纯函数**单测，锁 `gameBgFor` 四格语义 + 素材实体存在 + 一条恒真守卫。 |

**工程师如实登记的缺口（本轮核心）**：`p13_landscape_bg_test.dart` 只测纯函数，`p12_game_e2e_test.dart` 只测「布局不崩」，二者**都不验证页面有没有把 `landscape` 传进 `gameBgFor`**。若把 `:301` 改回 `Art.gameBgFor(Palette.brightness)`（漏传参），现有全部测试依然全绿。

---

## 二、★ 补齐的空白：接线（wiring）验证

### 2.1 新增文件

`test/p13_landscape_bg_wiring_test.dart` —— **10 条 widget 级用例**，复用 `p12_game_e2e_test.dart:24-55` 的 `_app` / `_bootGame` 脚手架与 `test/support/room_ui_harness.dart` 的 `RoomUiFixture.boot(inGame: true)`（真实 `room.start` + `scene.mode` 开团，玩家带完整卡）与 `useRoomScreen(tester, w, h)`（`:623-635`，设 `physicalSize = w*3 × h*3`、`dpr = 3.0`，并在 `addTearDown` 里 `resetPhysicalSize` / `resetDevicePixelRatio`）。

### 2.2 覆盖矩阵（5 场景 × KP / 玩家双视角 = 10 条）

| # | 场景 | 屏幕 | 皮肤 | 期望被选中（**硬编码常量**） | 必须不存在 | KP | 玩家 | 证伪注入后 |
| - | - | - | - | - | - | - | - | - |
| 1 | 横屏平板 / 暗色 | 1280×800 | dark | `Art.gameBgLand` | `gameBg`, `gameBgLight` | ✓ | ✓ | **红**（2 条） |
| 2 | 横屏小窗 / 暗色 | 780×320 | dark | `Art.gameBgLand` | `gameBg`, `gameBgLight` | ✓ | ✓ | **红**（2 条） |
| 3 | 横屏平板 / 亮色 | 1280×800 | light | `Art.gameBgLight` | `gameBgLand`, `gameBg` | ✓ | ✓ | 绿（见 §3.3） |
| 4 | 竖屏手机 / 暗色 | 360×640 | dark | `Art.gameBg` | `gameBgLand`, `gameBgLight` | ✓ | ✓ | 绿（见 §3.3） |
| 5 | 竖屏平板 / 亮色 | 820×1180 | light | `Art.gameBgLight` | `gameBgLand`, `gameBg` | ✓ | ✓ | 绿（见 §3.3） |

任务书要求的三个必测场景（横屏暗色 / 竖屏暗色 / 横屏亮色）全部覆盖，且两个视角各自跑完全部 5 个场景（优于「至少各覆盖一次」）。

### 2.3 每条用例的断言口径（全部精确、全部带 `reason:`）

1. `find.byType(RoomGamePage), findsOneWidget` + `tester.takeException(), isNull` —— 页面确实渲染、无布局溢出。
2. **屏幕方向守卫**：`MediaQuery.of(ctx).size` 的 `width > height` 必须等于用例声明的 `landscape`。widget test 默认视口 800×600 是横屏，若 `useRoomScreen` 没生效，竖屏用例会先在这里红 —— 杜绝「竖屏分支被默认横屏掩盖」的假绿。
3. **皮肤守卫**：`Palette.brightness == c.brightness` 且 `Theme.of(ctx).brightness == c.brightness`。页面选图读全局色板，若没切到目标皮肤，下面断言测的其实是另一套皮肤。
4. **主断言**：`find.byWidgetPredicate((w) => w is ArtImage && w.path == expected)` → `findsOneWidget`；`forbidden` 每张 → `findsNothing`。**未放宽成 `findsWidgets`**。
5. **加固断言（更强，非放宽）**：把页面里所有 path ∈ {`gameBg`, `gameBgLight`, `gameBgLand`} 的 `ArtImage` 收成集合，断言恰好等于 `{expected}`，杜绝「两张背景叠在一起」。

### 2.4 防止假绿 / 假红的三个设计决定

- **期望路径硬编码为 `Art.*` 常量，绝不调用 `Art.gameBgFor(...)` 生成期望值** —— 否则等于用被测实现验证被测实现，接线回归时断言会跟着一起「正确」，退化成恒真假保护。
- **显式同步全局色板**：`_app()` 在 `pumpWidget` 前调 `Palette.useBrightness(b)`；壳用 `MaterialApp`（同 p12），不经过 `lib/app.dart:76` 的 `DiceRealmApp` 每帧按 settings 重置，因此亮色可稳定生效（已由皮肤守卫实证）。`setUp` / `tearDown` 复位到 `dark`，避免全局状态污染同文件其它用例。
- **显式设屏幕尺寸并恢复**：`useRoomScreen` 内部 `addTearDown`；另加方向守卫把生效事实钉死。

---

## 三、★ 反向自证伪（针对「接线」，不是纯函数）

脚本 `.qa_p13_falsify.sh`（Git Bash `cp` / `cmp -s` / `sha256sum` / `sed` / `grep`，备份落在工程内 Windows 可见路径，**未使用原生 Windows Python 处理 MSYS `/tmp`**；`trap restore EXIT` 保证任何退出路径都恢复）。证伪窗口内独占 `room_game_page.dart`，无并行命令。

### 3.1 注入真的发生（锚点命中次数，先打印再跑测试）

| 检查 | 注入前 | 注入后 |
| - | - | - |
| 锚点 `Art.gameBgFor(Palette.brightness, landscape: landscape)` 命中次数 | **1** | **0** |
| 无参调用 `Art.gameBgFor(Palette.brightness)` 命中次数 | **0** | **1** |

注入后 `:299-304` 原文确认为 `Art.gameBgFor(Palette.brightness),`；文件 sha256 变为 `2a2858fd44039f3afbe526d495efd93eb21fe9e1cddb227d008f4479e2b9b452`（与基线不同）—— 排除「assert 失败但测试仍绿」的假证伪。

### 3.2 证伪窗口内确实变红

`flutter test test/p13_landscape_bg_wiring_test.dart` → **exit 1**，`+6 -4: Some tests failed.`，**4 条红**（场景 1、2 各 × KP / 玩家）：

```
Expected: exactly one matching candidate
  Actual: _WidgetPredicateWidgetFinder:<Found 0 widgets with ArtImage(path:
assets/images/e_game/e2_game_bg_land_16x9.webp): []>
   Which: means none were found but one was expected
横屏平板 1280×800 / 暗色 / KP：页面里应恰好有 1 个 path == .../e2_game_bg_land_16x9.webp 的
ArtImage；findsNothing 说明 room_game_page.dart:301 没把 landscape 传进去（选图回退到旧竖版 / 漏接 A1）
```

失败用例：`KP / 玩家 · 横屏平板 1280×800 / 暗色`、`KP / 玩家 · 横屏小窗 780×320 / 暗色`。这证明 **wiring 测试真的能抓住「漏传 `landscape`」这一接线回归**，而纯函数测试对此无感。

### 3.3 为什么另外 6 条仍绿（设计使然，不是证伪不彻底）

- 竖屏用例：`landscape=false`，`gameBgFor(b)` 与 `gameBgFor(b, landscape: false)` 逐字等价 → 本就不该被这个注入影响。
- 横屏亮色用例：无亮色横版图，`gameBgFor(light)` 与 `gameBgFor(light, landscape: true)` 都回退到 `gameBgLight` → 本就不该被这个注入影响。

即三张背景、四个象限里**只有「横屏 + 暗色」一格能区分「接了」与「没接」**；任务书要求的「至少横屏暗色那条变红」已满足，且是 4 条双红（`findsOneWidget` 变 `findsNothing`，`findsNothing(gameBg)` 同步变 `findsOneWidget`）。

### 3.4 逐字节恢复证据

| 项 | 值 |
| - | - |
| `cmp -s` 与备份 | **逐字节一致: true** |
| 恢复后 sha256 完整 | `b90fcdd28ae1dd9bd4c928867ec8d2044d815c6eafdcb78ca06be7285df3b9bd` |
| **恢复后 sha256 前 16 位** | **`b90fcdd28ae1dd9b`** |
| 改动前基线前 16 位 | `b90fcdd28ae1dd9b` |
| **逐字节一致** | **true** |
| 锚点命中次数（恢复后） | **1**；无参调用 **0** |
| 连续 3 次哈希采样 | 三次均 `b90fcdd2…3b9bd`，稳定 |
| 恢复后复跑 wiring | **10 条全绿，exit 0** |
| 其余生产 / 既有测试文件哈希 | `art.dart` `95cae25c…93cf1`、`p13_landscape_bg_test.dart` `3c42df7f…4eba` —— 与基线一致，未变 |

---

## 四、全量回归结果

| 检查项 | 命令 | 结果 |
| - | - | - |
| 全库静态分析 | `flutter analyze`（修复后） | **`No issues found! (ran in 5.9s)`**，exit 0 |
| **全库测试** | **`flutter test`（不带文件名，串行）** | **`01:31 +2167: All tests passed!`**，exit 0 |
| `did not complete` | 全量日志检索 | **0 处**（无 Windows `flutter_tester` 并发瞬时挂起，无需复跑，也未用 `--concurrency=4` 掩盖） |
| `[E]` / `Failing tests:` | 全量日志检索 | **0 处** |
| 定向复核 | `test/p12_game_e2e_test.dart` | **13 条全绿**（4 档屏幕 × KP / 玩家布局） |
| 定向复核 | `test/p12_banner_inset_test.dart` | **7 条全绿** |
| 定向复核 | `test/p13_landscape_bg_test.dart` | **5 条全绿** |
| 新增 wiring | `test/p13_landscape_bg_wiring_test.dart` | **10 条全绿**（恢复后 / 全量中均通过） |

**通过条数核对**：历史基线 **2152** + 工程师新增 `p13_landscape_bg_test.dart` **5** + QA 新增 wiring **10** = **2167**，与全量输出 `+2167` 完全吻合 —— 证明跑的是**全库**而非定向子集（P10 第 7 期「只跑 15 个定向文件漏掉全仓源码守卫」的坑未重现）。

> 首轮 `flutter analyze` 曾报 1 个 issue，归属 QA 自己的测试代码，已自修后重跑为 `No issues found!`，详见 §七。按测试轮次控制，这属于 Round 1 内的 QA 自修，未进入 Round 2 的生产源码往返。

---

## 五、`pubspec.lock` 基线证据

跑任何 flutter 命令前先备份 `.qa_p13_backup_pubspec.lock.bak`，全程（含 `flutter analyze`、多次定向 `flutter test`、全量 `flutter test` 触发的自动 `pub get`）结束后：

| 项 | 实测 | 基线要求 | 判定 |
| - | - | - | - |
| sha256 完整 | `fa69e59604415960b7449e0b5827fb5ec7eec0926a607d6078edca176504d86c` | — | — |
| sha256 前 16 位 | `fa69e59604415960` | `fa69e59604415960` | ✓ |
| `https://pub.dev` 次数 | **82** | 82 | ✓ |
| `pub.flutter-io.cn` 次数 | **0** | 0 | ✓ |
| `cmp -s` 与备份 | **逐字节一致: true** | — | ✓ |

**本次未被 `PUB_HOSTED_URL` 镜像改写，因此未触发恢复动作**（脚本已内置「若改写则 `cp` 备份逐字节恢复、版本号 / sha256 不变、只换 url 行」分支，未执行）。全程 `unset` 代理并 `export NO_PROXY=127.0.0.1,localhost`，先 `source /d/dev/env.sh`，命令前台执行。

---

## 六、资源在包核验

交付包：`C:/Users/60965/WorkBuddy/2026-11-08-13-25-14/dice-realm-v2.26.0.apk`（70,561,384 B）

| 检查 | 结果 |
| - | - |
| `unzip -l` 横版背景 | `assets/flutter_assets/assets/images/e_game/e2_game_bg_land_16x9.webp`，**10014 B**，确实已在包内 ✓ |
| 包内 `assets/images/` 条目数 | **106**（`unzip -Z1 \| grep -c 'assets/images/'`） |
| 工程 `assets/images/` 文件数 | **106**（`find -type f`）；14 个子目录 |
| 差异 | **0**，完全一致，无差异来源需说明 |

结论：该素材属于架构师报告中的**差集 C（已在包但未渲染）**，本次改动只是让它「被选中」，**不需要重新打素材、不需要改 `pubspec.yaml`**（`assets/images/e_game/` 已在 `:71` 声明）。

---

## 七、发现的问题清单

| # | 问题 | 归属 | 处置 | 状态 |
| - | - | - | - | - |
| 1 | **接线覆盖空白**：`p13_landscape_bg_test.dart` 只锁纯函数、`p12_game_e2e_test.dart` 只锁布局；把 `:301` 漏传 `landscape` 时全部既有测试仍全绿 | 测试覆盖缺口（工程师主动登记，**非生产 bug**） | 新增 `test/p13_landscape_bg_wiring_test.dart` 10 条 widget 级用例；接线级反向证伪实测 4 条变红，证明补得上 | **已闭环** |
| 2 | 首轮 `flutter analyze` 1 个 info：`library_private_types_in_public_api`（`test/p13_landscape_bg_wiring_test.dart:76` —— 公开名 `kCases` 用了私有类型 `_Case`） | **QA 自己新增的测试代码**，与生产源码无关 | 自行把常量改名为 `_kCases`（含一处引用），**断言一字未动、用例一条未删、无 skip、无恒真**；修复后 `No issues found!` | **已自修闭环** |
| 3 | 生产源码 bug | — | **未发现**。`art.dart` / `room_game_page.dart` 实现与 PRD / 架构设计一致：横屏暗色取 16:9、横屏亮色回退亮色竖版、竖屏维持 9:16 | — |
| 4 | 已知边界（架构师 §4.5 已登记，非缺陷） | 设计取舍 | 背景选图用 `MediaQuery.size` 宽高比，`RoomGridSpec.of` 在 `LayoutBuilder` 内另用 `c.maxWidth > c.maxHeight`；两者在状态栏 / 键盘 / 分屏极窄边界可能不同向，但背景不影响几何与档位；亮色横版专属图尚未出图（按 `pick` 回退） | 记录，不影响交付 |

---

## 八、硬约束遵守情况（逐条）

| 约束 | 本轮实际情况 |
| - | - |
| 不改生产源码 `lib/**` | ✓ 全程零改动；证伪窗口内临时注入 `:301` 后 `cp` 逐字节恢复，恢复哈希 = 基线 `b90fcdd28ae1dd9b`，连续采样稳定 |
| 既有测试文件一个都不许改 | ✓ `p12_game_e2e_test.dart` / `p12_banner_inset_test.dart` / `p13_landscape_bg_test.dart` 哈希全程不变 |
| 不放宽断言 / 不删用例 / 不 skip / 不改恒真 | ✓ 全部 `findsOneWidget` / `findsNothing`，每条带 `reason`，另加三条守卫与一条集合加固断言 |
| 不动 `skills.dart` / `occupations.dart`（GENERATED）、`oracle_*`、门禁 `FROZEN = 4` | ✓ 未触碰（全量 2167 条含这些守卫均通过） |
| 不升版本 / 不出包 / 不推 GitHub | ✓ `pubspec.yaml` `version: 2.26.0+96` 未动，未执行 build / git push |
| 不改 `_p13_asset_audit.md` | ✓ 只读引用 |
| 不顺手接其它素材 | ✓ 架构师 74 项判定仅 A1 需接入，本轮只验证 A1，未触碰其余 73 项 |
| `pubspec.lock` 基线 | ✓ 逐字节一致，82 / 0 |
| `build/` 实目录 | ✓ 已核实为实目录，未改成 junction |

交付新增文件仅 2 个：`test/p13_landscape_bg_wiring_test.dart`（测试）、`qa_p13_landscape_bg_report.md`（本报告）；证伪脚本 / 日志 / 备份等临时产物已清理。

---

## 九、智能路由判定

> ## **`IS_PASS: YES / NoOne`**

**理由**：

1. **全量回归干净**：`flutter analyze` → `No issues found!`；不带文件名的全库 `flutter test` → `+2167: All tests passed!`，无 `did not complete`、无失败条目；条数 2152 + 5 + 10 = 2167 与全库口径吻合。
2. **接线真的被验证到**：新增 10 条 widget 级用例直接检查页面里 `ArtImage.path`，5 场景 × KP / 玩家双视角，含屏幕方向守卫与皮肤守卫，精确口径、全带 `reason`。
3. **证伪真红且恢复干净**：去掉 `:301` 的 `landscape: landscape` 后 4 条用例变红（`Found 0 widgets with ArtImage(path: e2_game_bg_land_16x9.webp)`），注入前/后锚点命中次数 1→0 确认注入发生；恢复后 `逐字节一致: true`、sha256 前 16 位 `b90fcdd28ae1dd9b`、连续采样稳定、复跑全绿。
4. **未发现生产源码 bug**：唯一 issue 是 QA 自己测试文件的 lint，已自修闭环；资源在包、`pubspec.lock`、既有测试文件哈希全部符合基线。

因此**无需交回工程师（Engineer）**，也不存在需要 QA 再次修复的测试代码问题（自修已完成并复验全绿）—— 路由 `NoOne`，可交付主理人收尾。
