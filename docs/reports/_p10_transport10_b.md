# P10 第 7 期 B 批交付报告 · 素材缩略图 + 加怪/NPC 数值表单

> 施工人：软件工程师 寇豆码（Kou / software-engineer-6）
> 施工依据（只读）：`_p10_t7_research.md`（老 APP 2.13.13 对照，A2 节字段口径）
> 工程根：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
> 性质：纯 UI 改动，**未动 domain / pubspec.yaml / app_version.dart / 任何既有测试文件**

---

## 1. 交付文件清单与 sha256（最终态，反向证伪已恢复）

| 文件 | 变更 | sha256 |
|---|---|---|
| `lib/ui/room/widgets/gp_kp_left.dart` | 素材缩略图 + 共享数值表单 + 候选行字段 + 新 key | `74f7c46578b1df0a3c369bfc382867f073a5983650f4e2d88cefe19dd78385f6` |
| `lib/ui/room/widgets/gp_kp_tools.dart` | 新增共享组件（ActorFieldKeys / ActorFieldsController / ActorFields / actorSummaryText）+ 新 key + 调用点传全 4 值 + 候选行 | `a207b4bbe18bfd7f0f8612dc6f79e248513bb9c47ed0b08092606be6cf53d5ad` |
| `lib/ui/room/widgets/room_layout.dart` | **仅注释**：第 92 行 `270` → `260`（代码一行未动，`:249` 实际为 `260`） | `a8146d5431b9620d0f0cf2bb9cb22e2ed8949fae3fac97b8417af1b8f458d21b` |
| `test/p10_t7_b_assets_actors_test.dart` | **新建**：8 个 widget test（TB1~TB8） | `d8712265ed479c8804cb7e849b2a20b66a0b14c2bda419214977caea9be3446d` |
| `_p10_transport10_b.md` | 本报告 | — |
| `pubspec.lock` | 全程保持干净版（每条 flutter 命令后立即 `cp pubspec.lock.t7bak pubspec.lock` 恢复） | `fa69e59604415960b7449e0b5827fb5ec7eec0926a607d6078edca176504d86c`（`grep -c pub.dev` = 82、`grep -c flutter-io` = 0） |

---

## 2. 实现要点

### 任务 1 · 上传素材后要有缩略图
- `GpKpLeft._assetThumb(Map a)`：按 `gp_map_stage.dart:399-418` 的 `_coverImage` 同一口径，取 `a['data']` 逗号后的 base64 → `base64Decode` → `Image.memory(40×40, BoxFit.cover, ClipRRect 圆角)`。
- **坏数据双重兜底**：`try/catch`（base64 解析失败）+ `Image.errorBuilder`（解码失败）→ 一律静默降级为 `Icons.image_outlined` 占位；`data` 为空直接走占位。绝不因一张图炸掉整栏。
- 稳定 key：`GpKpLeftKeys.thumb(String id)`。公开 / 未公开用一圈极细 `foregroundDecoration` 边框区分（金色 / 白 24%），**不参与布局、不挤占空间**。
- 名字行改为 `Row([缩略图, 6dp, Expanded(Text)])`；**第 7 期 A 批「名字一行 + 按钮 Wrap 一行」结构原样保留**，三个 48×48 按钮未被移动或压缩（TB7 / A 批 T8 实测通过）。
- 按 id 去重合并（`localAssets` 优先、`public` 补缺）逻辑**一行未动**，A 批 T7 不变量保留。

### 任务 2 · 增加怪物 / NPC 能填数值
- 严格按老 APP 2.13.13 的 **A2 字段口径**：只有 `name` / `kind`(怪物|NPC 二选一) / `dex`(50) / `hp`(10，同时写 `hpMax`) / `actionsPerRound`(1，静默夹 1–10)。
  **明确未加**：DB / 护甲 / 格斗 / 闪避 / MOV / 单独 HP 上限 / 怪物库 / 数值越界提示；越界只静默夹取（夹取在 `addLocalActor` 函数体，**函数体零改动**）。
- **共享组件**（放 `gp_kp_tools.dart` 并由 `gp_kp_left.dart` import 复用，避免两套实现漂移）：
  - `ActorFieldKeys`：7 个稳定 key 的注入口（两个窄栏各传自己的一套）。
  - `ActorFieldsController`：4 个 `TextEditingController`（默认 `'怪物' / '50' / '10' / '1'`）+ `kind`，提交 getter 一律 `int.tryParse(...) ?? 默认值` 静默回落，不弹错。
  - `ActorFields`：`Wrap` 内联小表单（名称 TextField / 两个 `ChoiceChip` 怪物·NPC / DEX / HP / 每轮，均 `TextInputType.number`），**不新增弹层**；组件本身不挂提交按钮。
  - `actorSummaryText`：候选行文本 `名称（kind） · DEX n · HP n`，`actionsPerRound > 1` 追加 `· 每轮 k 次`（老 APP `:4112-4130` 口径），两个窄栏共用。
- 两处既有 key **全部保留**：`GpKpToolsKeys.actorName / addActor`、`GpKpLeftKeys.actorName / addActor`。新增稳定 key：`actorDex / actorHp / actorActions / actorKind / actorKindMonster / actorKindNpc`（两套命名空间各自独立，整页同时渲染不冲突）。
- 工具窄栏 `gp_kp_tools.dart` 与左窄栏 `gp_kp_left.dart` 的调用点**都把 4 个值一起传进** `addLocalActor(local, name:…, kind:…, dex:…, hp:…, actionsPerRound:…)`。
- 候选列表：左栏把「名称（kind）」扩成完整摘要；工具窄栏原只有计数，补上逐行摘要。
- ★ **T-30 契约**：挂 `addActor` 的 `RoomTap.enabled` 恰好 = `ctl.gate.can('combat.start')`（工具窄栏用 `gate.can`、左栏用 `ctl.gate.can`，同一对象），**未叠加任何表单前置条件**（TB8 在表单全清空后仍断言 enabled 不变）。

### 任务 3 · 注释笔误
`room_layout.dart:92` 的 `270` → `260`；`:249` 代码 `return 260;` 一行未动。已用内容检索复核（注释 :92 = 260、代码 :249 = 260）。

---

## 3. 测试

### 新增用例数：**8**（`test/p10_t7_b_assets_actors_test.dart`，全部 `testWidgets`，无 `skip`、无恒真、无 `findsWidgets` 降级）

| 用例 | 覆盖 |
|---|---|
| TB1 | 合法 1×1 PNG dataURL → `Image.memory` 且 `MemoryImage.bytes` 非空、`BoxFit.cover`；非法 base64 / 空 `data` → 不抛异常、无 Image、显示占位图标 |
| TB2 | A 批 T7 去重口径逐字保留（一行、`公开 1 · 未公开 0`）+ **新增正向断言**缩略图恰好一张 |
| TB3 | 工具窄栏填 DEX30/HP25/每轮2/NPC → `pendingActors` 逐字段 `dex=30, hp=25, hpMax=25, kind='npc', actionsPerRound=2`；并反向断言**没有** db/armor/dodge/mov/fighting |
| TB4 | 非法数字静默回落 50/10/1；`12 → 10`、`0 → 1` 夹取，零异常 |
| TB5 | 候选行含 `DEX 30` / `HP 25` / `每轮 2 次`；k=1 时不追加 |
| TB6 | 左窄栏共享表单同样能填并生效 + 候选行文本 |
| TB7 | 1280 档整页：三个素材按钮 rect 不出格、热区 ≥48×48（`tester.getRect`） |
| TB8 | T-30：`addActor.enabled` 两处恒等 `gate.can('combat.start')`，表单清空后不变 |

### 执行结果（每条 flutter 命令前 `unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy` + `export NO_PROXY=127.0.0.1,localhost`；每条后立即恢复 lock 并核对 `sha256 == fa69e596…`、`pub.dev=82`、`flutter-io=0`）

| # | 命令 | 结果 |
|---|---|---|
| 1 | `dart analyze` 对 4 个改动文件 | **No issues found!** |
| 2 | `flutter test test/p10_t7_b_assets_actors_test.dart --concurrency=1` | **8/8 All tests passed!** |
| 3 | `flutter test test/p10_t7_layout_test.dart --concurrency=1` | **9/9 All tests passed!**（含 T1 两档几何、T6 舞台底图、T7 去重、T8 三按钮热区） |
| 4 | `flutter test test/room_ui_kp_test.dart test/qa_p5_priv_probe_test.dart --concurrency=1` | **47/47 All tests passed!**（既有 `actorName`/`addActor` 用例、KP 面板门禁探针、工具窄栏 A-2 全绿） |

> 说明：命令 4 输出里有一条 `flutter_test` 固有的 `tap() … would not hit test on the specified widget` **warning**（`room_ui_kp_test.dart:694` 用 `find.text('素材')` 点 tab 文本，命中其祖先 `ActionChip` 的 InkWell 而非 Text 本身）。这是既有测试的固有告警，用例仍通过（`local.leftTab` 成功切到 2），与本批改动无关；**未修改任何既有测试**。

### 断言口径声明
本批**未放宽任何断言**：无删用例、无 `skip`、无恒真、`findsOneWidget` 未降级为 `findsWidgets`。既有测试全部原样通过，无需「口径更新」。TB2 在 A 批 T7 核心不变量逐字断言之外**新增**正向断言（缩略图恰好一张），属加严。

---

## 4. 反向证伪（只在自己独占文件集内、独占窗口进行）

每次改坏前先 `cp` 干净版备份；改坏后用**同一条 Bash 命令**跑红测试 → `cp` 恢复 → 核对 sha256 → 复跑全绿 → 恢复 lock，并用 `trap … EXIT` 保证任何中断都自动恢复。临时备份 `_t7b_clean_*.bak` 已删除。

### 证伪 1 · 把「4 个值一起传」改回只传 `name`
- 改坏：`gp_kp_tools.dart` 与 `gp_kp_left.dart` 两处 `onTap` 改为 `addLocalActor(local, name: _fields.nameValue)`。
- **RED**：`flutter test test/p10_t7_b_assets_actors_test.dart --concurrency=1` → exit **1**，`+4 -4 Some tests failed`。
  失败用例：**TB3 / TB4 / TB5 / TB6**（典型证据：`Expected: <30> Actual: <50>`，即 DEX 吃了默认 50；TB6 左栏同红）。
- 恢复后立即核对：`gp_kp_tools.dart = a207b4bb…`、`gp_kp_left.dart = 74f7c465…`（与干净版一致）。
- **GREEN**：复跑 → exit **0**，`+8 All tests passed!`。

### 证伪 2 · 去掉缩略图的 `Image.memory`
- 改坏：`gp_kp_left.dart::_assetThumb` 的 `Image.memory(...)` 整块换成 `picture = _thumbPlaceholder();`。
- **RED**：exit **1**，`+6 -2 Some tests failed`。
  失败用例：**TB1 / TB2**（典型证据：`_DescendantWidgetFinder: Found 0 widgets with type "Image" descending from key ['gpKpLeft/thumb/a1']`）。
- 恢复后立即核对：`gp_kp_left.dart = 74f7c465…`、`gp_kp_tools.dart = a207b4bb…`。
- **GREEN**：复跑 → exit **0**，`+8 All tests passed!`。

### 恢复后 sha256 清单（两次证伪各自复跑前核对，最终态再次核对）

| 文件 | 证伪 1 恢复后 | 证伪 2 恢复后 | 最终态 |
|---|---|---|---|
| `gp_kp_tools.dart` | `a207b4bbe18bfd7f0f8612dc6f79e248513bb9c47ed0b08092606be6cf53d5ad` | `a207b4bbe18bfd7f0f8612dc6f79e248513bb9c47ed0b08092606be6cf53d5ad` | `a207b4bbe18bfd7f0f8612dc6f79e248513bb9c47ed0b08092606be6cf53d5ad` |
| `gp_kp_left.dart` | `74f7c46578b1df0a3c369bfc382867f073a5983650f4e2d88cefe19dd78385f6` | `74f7c46578b1df0a3c369bfc382867f073a5983650f4e2d88cefe19dd78385f6` | `74f7c46578b1df0a3c369bfc382867f073a5983650f4e2d88cefe19dd78385f6` |
| `pubspec.lock` | `fa69e59604415960b7449e0b5827fb5ec7eec0926a607d6078edca176504d86c` | `fa69e59604415960b7449e0b5827fb5ec7eec0926a607d6078edca176504d86c` | `fa69e59604415960b7449e0b5827fb5ec7eec0926a607d6078edca176504d86c`（`pub.dev=82`、`flutter-io=0`） |

---

## 5. 全局一致性审查（所有文件写完后一次性审查）

| 检查项 | 结论 |
|---|---|
| 跨文件 import：`gp_kp_left → gp_kp_tools` 单向，`gp_kp_tools` 不反向依赖 | ✅ 无循环依赖；`dart analyze` 零问题 |
| 接口契约：`ActorFieldKeys` 7 字段两处传全；`ActorFieldsController` 由父持有并 `dispose`；`addLocalActor` 签名零改动、两处调用参数齐全 | ✅ |
| 数据流：TextField → `int.tryParse ?? 默认` → `addLocalActor` → `pendingActors` → `actorSummaryText` → 候选行 | ✅ 类型/字段一致（TB3/TB4/TB5/TB6 逐字段断言） |
| 无重复实现：表单组件、候选行文本、`addLocalActor` 各只有一份 | ✅ |
| T-30：两处 `addActor.enabled` 恰好 `gate.can('combat.start')`，无业务前置 | ✅ TB8 + `qa_p5_priv_probe` A-2 |
| A 批结构：名字一行 + 按钮 Wrap 一行；按 id 去重；槽位/key 命名与布局骨架 | ✅ TB7 + `p10_t7_layout_test` 9/9 |
| 硬约束：未动 domain / GENERATED FILE / oracle_* / FROZEN / pubspec.yaml / app_version.dart / 其它 worker 文件 / 既有测试；未跑 adb / 模拟器 | ✅ |
| `room_layout.dart` 仅注释 270→260，代码未动 | ✅ 内容检索复核（:92 注释 260、:249 代码 260） |

**IS_PASS: YES**

---

## 6. 遗留问题 / 说明（无阻断项）

1. **候选池仍用 `local.pendingActors`（本机内存、不进存档）**：研究文档 C1 把它列为「可选、推荐但可延后」（同步到 `host.localActors` / `combat.pool.set` 以持久化）。本批按施工单「只做用户点名的两件事」未纳入，需主理人决定是否排后续期。
2. **战斗准备弹层 `sheet_combat.dart` 的 `_actorPayload()` 仍硬编码 `dex:50/hp:10/…`**：该文件属 **C 批**（software-engineer-8）独占，本批未碰；两批合流后需确认弹层内新增单位是否也复用同一套数值录入口径（本批共享组件已 export，可直接复用）。
3. 既有测试 `room_ui_kp_test.dart:694` 的 `tap()` hit-test warning 属 flutter_test 固有告警，非失败、非本批引入；未改既有测试。
4. 未执行真机 / 模拟器验证（按分工由用户统一测）；未升版本号（由主理人统一升）。
5. 缩略图在真实设备上的 `Image.memory` 解码失败会走 `errorBuilder` → 占位，与舞台 `_coverImage` 同口径；测试已用空 data / 非法 base64 覆盖降级路径，未覆盖「合法 base64 但非图片字节」在真机解码的分支（该分支由 `errorBuilder` 保证，逻辑与舞台一致）。
