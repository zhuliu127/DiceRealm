# P10 第 7 期 C 批 B 组 · 交付报告（转战斗选参战单位 + 战斗轮次信息栏）

> 工程师：寇豆码（software-engineer-8） · 全程中文 · 快速模式（一次性代码 + 测试 + 报告 + 自检）
> 工程根：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
> 施工依据：`_p10_t7_research.md`（B1–B4 / C2）+ 主理人施工单（含对 C2「domain 自动带 PC」的纠正）
> 用户原话：「现在点『转战斗』进入战斗模式，没有让我选择哪些怪物和玩家进入战斗，而且进入战斗模式，没有出现战斗轮次信息栏位。」

---

## 0 · 结论先行

- 根因确认：**两个问题都是 UI 没接，不是 domain 没做**。`combatStart` 只从 `p['actors']` 取池子，`kind=='pc'` 只是在 `actorIds` 过滤时保留已有 PC，**不会凭空创建 PC 槽位**（`lib/domain/room_model_actions_combat.dart:170-197`）。因此本批在 UI 层显式构造 PC 记录塞进 `actors`，与老 APP `pcActors(ctx).concat(monsterActors)` 对齐。
- `dart analyze lib test`：**No issues found!**（零问题）
- **最终态 15 个测试文件 / 254 条用例全绿**：主体阶段 14 文件 245 条（主测试 17 条）主理人已采信；本轮「追加项 + 裁决」收尾把主测试加到 **18 条（主体 14 + 追加 3 + 裁决 1）**，并新增第 15 个文件 B 批 `test/p10_t7_b_assets_actors_test.dart`（8 条，验证共享 `ActorFields` 未被带坏）。本轮主理人指定的 4 个测试文件重跑（**18 / 35 / 19 / 8 = 80 条**）+ `dart analyze` 全部全绿。
- **4 次反向证伪**全部「改坏 → 跑红 → 恢复 → 核 sha256 → 复跑全绿」：主体 3 次（第 5 节）+ 追加项 1 次「`_actorPayload` 改回硬编码 → 第 ⑨ 组转红」（第 7 节）。主体证伪窗口未重开、未破坏。
- **IS_PASS: YES**（全局一致性审查，第 4 节；追加项 + 裁决复审仍 YES，见第 7 / 8 节）。
- ★ **主理人追加项**已完整落地并单列成节：战斗弹层「加单位」也能填 DEX / HP / 每轮次数 / 类型，只读复用 B 批 `ActorFields`，见**第 7 节**。
- ★ **主理人裁决**已定稿并单列成节：空池兼容口径保留纯 PC 开战、空池 hint 明示「将以纯玩家战斗开始」，见**第 8 节**；被禁止的既有测试文件一字未动。

---

## 1 · 文件清单与 sha256

| # | 文件 | 动作 | sha256 |
|---|---|---|---|
| 1 | `lib/ui/room/widgets/gp_toolbar.dart` | 改（仅 onTap + import） | `13f1a5f3a35ace26715768b6aabe12305dfe5255d4a624f9c847c0597e4b5ca3` |
| 2 | `lib/ui/room/sheets/sheet_combat.dart` | 改（勾选 + 载荷 + 门禁 + 文案 + key + **主理人追加数值表单** + **裁决空池 hint**，见第 7 / 8 节） | `26aebc44255b70140a88fa5f9e871c45eb68e814f009b830a855a128472059c0` |
| 3 | `lib/ui/room/widgets/gp_combat_list.dart` | 改（顶部文案 + strip 渲染 + 4 个 key） | `a3b7d23ac19201c95591ead65cfa14a1a7541d18bebec20546c2a54d0c7887e2` |
| 4 | `lib/ui/room/widgets/gp_combat_strip.dart` | **新建**（行动顺序条 widget + key 类） | `e677de14e2a59b1cdc032ee239b2640559735895194a153e007c90a40f0c824d` |
| 5 | `lib/ui/room/view/combat_view.dart` | 改（新增纯函数 `initiativeText`，`roundText` 原样保留） | `9c03efd201823af9ccb2b010f162a755bfa0ec9c6f5652295604cc6f5445cfc8` |
| 6 | `test/room_ui_kp_test.dart` | 改（1 条口径更新 + 1 条新增） | `ec9d97b05ee0e7845a85a2651bddbf260df1bf60832ab911565a54199d8228bb` |
| 7 | `test/p10_t7_c_combat_test.dart` | **新建**（18 条＝主体 14 + 主理人追加 3 + 裁决 1） | `80401e2b86782caf1c65d3357b31ae0915742bfbeabf2163b5c83faca7a63222` |
| 8 | `_p10_transport10_cb.md` | **新建**（本报告） | — |

**未触碰**（施工单禁止 / 他组独占）：`gp_kp_left.dart` / `gp_kp_tools.dart`（**只读 import**，最终 sha256 `a207b4bbe18bfd7f0f8612dc6f79e248513bb9c47ed0b08092606be6cf53d5ad` 与主理人给出的 B 批落盘值逐字节一致，证明未写）/ `room_layout.dart` / `gp_feeds.dart` / `sheet_chat_composer.dart` / `room_game_page.dart`（Column / Stack 骨架与 `RoomSlot.gpCombatStrip` 兜底分支）/ `lib/domain/**` / `pubspec.yaml` / `lib/app_version.dart` / GENERATED FILE / `oracle_*` / `FROZEN = 4` / 房间布局骨架与 `RoomSlot`·`RoomKeys` 命名。未新增 `RoomEvt` / intent / domain action。

**lock 保护**：每条 `flutter` / `dart` 命令后立刻 `cp pubspec.lock.t7bak pubspec.lock`，全程核对
`sha256 == fa69e59604415960b7449e0b5827fb5ec7eec0926a607d6078edca176504d86c`、`grep -c pub.dev == 82`；
末尾最终值同上。`build` 为实目录，未 clean / 未删目录 / 未改链接。未跑 adb / 模拟器 / 真机。

> **环境故障处置（非代码问题，已在第 7.4 节留证）**：本轮收尾首跑时 flutter 工具连续 4 次报「failed to delete `build\native_assets\windows\native_assets.json`」。实查该文件 ACL 正常（当前用户 FullControl）、无进程句柄占用、内容合法（45B，`{"format-version":[1,0,0],"native-assets":{}}`），是 Windows 文件监视器/杀软对 flutter 自生成缓存的瞬时删除时序问题。处置：先 `cp` 备份该单个 45B 缓存文件到 `/tmp/t7cb_native_assets.json.bak`，再 `del /f /q` 清掉**这一个文件**（flutter 下次 build 自动重建，已验证重建成功）；`build` 目录结构、`build/test_cache/...` 全部未动，未执行 `flutter clean`。清后主测试立刻 18 条全绿，磁盘可用 28G（非空间不足）。

---

## 2 · 实现要点

### 2.1 工具栏「转战斗」（`gp_toolbar.dart`）
- `RoomKeys.action('scene.mode')` 这个 key **继续挂在该按钮上**，`enabled` 仍**恰好** `gate.can('scene.mode')`，`label` / `icon` / `hint` 一字不动；**只换 `onTap`**。
- 探索态 → `showCombatSheet<void>(context)`（弹层），**不直发 `scene.mode`**；战斗态 → `controller.hostAction('combat.end')`（老 APP `modeSwitch` :286-289 口径）。
- 删掉了改后不再使用的 `domain/room_types.dart` import；`dart analyze` 零问题。
- `p10_t3_layout_test.dart:271,301` 的几何矩形断言、`room_ui_permission_test.dart:581-596` 的三视角 `enabled == gate.can(op)` 均保持绿。

### 2.2 战斗准备弹层（`sheet_combat.dart`）
- 两个勾选列表：**玩家默认全选**（反选集合 `_pcOff`，key 不存在 = 选中）、**怪物 / NPC 默认全不选**（正选集合 `_monsterOn`，初始为空）。行文案：玩家「昵称（seat）」；怪物「名字 · 类型 · DEX n · HP n · 每轮 k 次」（k>1 才带次数）；空池提示「候选池是空的。点左栏「NPC·怪物」先添加。」
- 弹层标题「战斗模式 · 选择参战单位」；说明「勾选要进入战斗的玩家与怪物/NPC（玩家默认全选）。系统按 CoC 7th 规则自动排行动顺序。」；主按钮「⚔️ 战斗部署完毕（怪物 n · 玩家 m）」。
- **新增稳定 key**：`CombatSheetKeys.pcToggle(seat)` / `monsterToggle(id)` / `deployCount` / `deploy`（`deploy` 用 `KeyedSubtree` 包住主按钮，按钮自身仍挂 `RoomKeys.action('combat.start')`，两处都可点/可查）。既有 `root/prepare/pool/damage/damageInput/actorName/addActor/slot` 与 `RoomKeys.action('combat.start'/'combat.end'/'combat.actor'/'combat.pool.set'/'combat.damage')` **全部保留**（`prepare` / `damage` / `addActor` 还顺手挂到了对应 SectionBox / 按钮外层，`room_ui_kp_test.dart` 的「11 个文件纯净」门禁仍绿）。
- **T-30**：`combat.start` 的 `RoomTap.enabled` 恰好 `gate.can('combat.start')`，「至少 1 怪」只写进 `hint` + 点后 `RoomScope.read(context).local.showNotice('至少选择 1 个怪物/NPC')` 并 return（K7，与 `combat.damage`「请先选择槽位」同款）。
- **载荷**（施工单纠正后的正确口径）：
  ```
  actorIds = 勾选的怪物/NPC id
  actors   = [ ...勾选的怪物候选, ...勾选玩家映射出的 PC 记录 ]
  pcSeats  = 勾选的玩家座位
  ```
  PC 记录字段 `{'id':'p-'+seat, 'name':角色名/昵称/seat/'玩家', 'kind':'pc', 'seat', 'dex', 'actionsPerRound':1, 'hp', 'hpMax'}`；**DEX / HP 复用 `view/member_view.dart` 的既有纯函数 `memberDex`（只认 `sheet.attrs.dex`）与 `memberStats`（status → runtime → sheet 顶层逐项回退）**，取不到给 0，绝不编默认值；撕卡 PC 由 domain :198-214 自动过滤，UI 不判。

### 2.3 战斗轮次信息栏（`combat_view.dart` + `gp_combat_strip.dart` + `gp_combat_list.dart`）
- `combat_view.dart` **新增纯函数** `initiativeText(state)`（读 `combat.round` + `curSlot(state)['name']`，输出「第 N 轮 · 当前行动：X」），**`roundText` 函数体原样保留**（`room_view_test.dart:464` 依赖）。
- `gp_combat_list.dart` 顶部文案改为 `initiativeText`，下方渲染新建的 `GpCombatStrip(isKp:, seat:)`；**只在战斗面板内渲染**，未动 `room_game_page.dart`。
- `GpCombatStrip` 复用 `combatRows(state, isKp:)`，每槽：`x/y`（`actionsPerRound>1` 时，按去 `#` 的 actorId 分组累加）+ 名字 + `PC`/`怪物`/`NPC` + HP 条或「隐藏」；`isCurrent` 用 `primaryContainer` 高亮；`SingleChildScrollView + Row` 横向排，单槽固定 104dp 不撑破。**K4**：`hpHidden` 只显示「隐藏」，绝不把缺键当 0；**S5**：进度条带 `hpMax > 0` 守卫。订阅 `RoomScope.of(context)`，`combat.next` 后自动重算（测试已验证高亮右移 + 文案同步）。
- **新增稳定 key**：`GpCombatKeys.strip` / `stripSlot(id)` / `stripCurrent` / `stripHeader`。前 3 个**引用** `GpCombatStripKeys`（定义在 `gp_combat_strip.dart`）以保单一真相源、避免循环 import；`stripHeader` 挂在 `gp_combat_list.dart` 的顶部 Text 上。

---

## 3 · 测试与结果

### 3.1 新建 `test/p10_t7_c_combat_test.dart` — **18 条，全绿**（主体 14 + 主理人追加 3 + 裁决 1）

| 组 | 用例 | 覆盖 |
|---|---|---|
| ① | 探索态点 `scene.mode` → 弹层标题 + `sent` 无 `scene.mode`；弹层标题/说明/计数/空池提示 | 验收 1 |
| ② | 玩家默认全勾、怪物默认全不勾；空手点部署 → 不发 `combat.start` + notice；门禁不进 `enabled`；历史路径空池纯 PC 开战 | 验收 2 |
| ③ | 勾 1 怪 + 2 玩家 → `actorIds`/`pcSeats`/`actors` 逐字段 + 计数/按钮文案；取消 1 玩家 → 同步减少 | 验收 3 |
| ④ | 载荷喂 domain（loopback host 真应用）→ `order` 长度 = 怪槽 + PC 槽、同时有 pc/monster、首槽 `isCurrent` | 验收 4 |
| ⑤ | 三视角（KP/p1/sp1）`scene.mode` 与 `combat.start` 的 `enabled` 恒等 `gate.can(op)` | 验收 5 / T-30 |
| ⑥ | 战斗态点按钮只发 `combat.end`、不发 `scene.mode` | 验收 6 |
| ⑦ | 开战 `strip` 可见 / `stripHeader` 含「第 1 轮 · 当前行动：」/ 首槽高亮 / `combat.next` 后高亮右移且文案同步；玩家侧 `hpHidden` 槽显示「隐藏」不显示 `HP 0` | 验收 7 / K4 |
| ⑧ | `initiativeText` / `roundText` 纯函数口径 | 保留性 |
| ⑨ | **主理人追加**：DEX 33 / HP 27 / 每轮 3 / NPC → `combat.actor` 载荷逐字段；非法数字静默回落默认；夹 1–10 + `combat.pool.set` 仍是候选池整体替换 | 第 7 节 |
| ⑩ | **主理人裁决**：空池 hint 明说「纯玩家战斗」且无门禁提示 + `enabled` 恒等闸门；有怪未勾时门禁严格生效（hint + notice + 未发包） | 第 8 节 |

### 3.2 口径更新 `test/room_ui_kp_test.dart`（**加严，不放宽**）
- 原用例名 **逐字保留**：`战斗弹层：combat.start 带 pcSeats / actors`。
- **核心不变量逐字保留**：`find.byKey(CombatSheetKeys.root) findsOneWidget`、`sent != null`、`pcSeats 非空`、`actors 非空`、`takeException() == null`。
- 只把「直接点按钮」改成「先 `tap` `CombatSheetKeys.monsterToggle('la1')` 勾选那只怪再点」（怪物默认全不选 + 至少 1 怪门禁后的必然口径）。
- 旧断言 `actors.length == 1` 升级为：`actorIds == ['la1']`、`pcSeats` 恰为全选座位、`actors` 含 2 条 `kind=='pc'` 且带 `seat`/`id`/`dex`/`hp`/`hpMax`、怪物记录恰好 1 条、`deployCount` 文案含「怪物 1」「玩家 2」。
- **加严理由**：旧断言只允许「1 条候选怪」，与「domain 不会自动带 PC、必须显式塞 PC」的正确载荷直接矛盾；新口径把单一长度断言升级为逐字段结构断言，同时钉住怪物侧与 PC 侧，覆盖面更广、约束更强，不是放宽。
- **新增独立用例**：`战斗弹层：不勾怪物直接部署 → 不发 combat.start + 明确提示`（断言 `combat.start` 未发 + `local.notice` 含「至少选择 1 个怪物/NPC」）。
- 未删用例、未 `skip`、未改恒真、`findsOneWidget` 未降级。

### 3.3 测试结果汇总（全部 `--concurrency=1`，每条命令后恢复 lock）

| 测试文件 | 用例数 | 结果 |
|---|---:|---|
| `test/p10_t7_c_combat_test.dart` | **18** | ✅ All tests passed（主体 14 + 追加 3 + 裁决 1；本轮重跑） |
| `test/room_ui_kp_test.dart` | 35 | ✅ All tests passed（含口径更新 1 条 + 新增 1 条；「11 个文件纯净」门禁绿；本轮重跑） |
| `test/room_ui_permission_test.dart` | 19 | ✅ All tests passed（T-30 锚点表 30 op、三视角等价、combat.damage 两段式；本轮重跑） |
| `test/p10_t7_b_assets_actors_test.dart` | **8** | ✅ All tests passed（**B 批共享组件回归**：确认只读 import 的 `ActorFields` 未被带坏；本轮主理人指定新增） |
| `test/p10_t3_layout_test.dart` | 13 | ✅ All tests passed（工具栏几何不回归） |
| `test/p10_t7_layout_test.dart` | 9 | ✅ All tests passed（A 批几何不回归） |
| 主动加跑 `test/room_ui_blocks_test.dart` | 24 | ✅（GpCombatList 的 `30 / 30` isFalse / 「隐藏」/「已倒下」断言不回归） |
| 主动加跑 `test/room_ui_gap_fill_test.dart` | 7 | ✅ |
| 主动加跑 `test/room_ui_harness_test.dart` | 14 | ✅（`:104` fixture 直接调 `hostAction('scene.mode')` 不受按钮影响） |
| 主动加跑 `test/room_view_test.dart` | 33 | ✅（`roundText` 纯函数口径不变） |
| 主动加跑 `test/room_ui_wiring_test.dart` | 11 | ✅ |
| 主动加跑 `test/room_ui_shell_test.dart` | 17 | ✅ |
| 主动加跑 `test/room_ui_layout_test.dart` | 17 | ✅ |
| 主动加跑 `test/qa_p5_priv_probe_test.dart` | 13 | ✅ |
| 主动加跑 `test/p10_t5_music_synonym_layout_test.dart` | 16 | ✅ |
| **合计** | **254** | **全绿** |

> 本轮「追加项 + 裁决」收尾按主理人清单重跑了 `dart analyze lib test` + 4 个测试文件（`p10_t7_c_combat` 18 / `room_ui_kp` 35 / `room_ui_permission` 19 / `p10_t7_b_assets_actors` 8 = **80 条**），全部 `All tests passed!`；`dart analyze lib test` → **No issues found!**（全项目，非仅本批文件）。表中其余 9 个周边回归为主体阶段已采信结果，本轮未重开（不破坏主体反向证伪窗口）。每条 flutter 命令后均已 `cp` 恢复 lock 并核对 `fa69e596…` / 82。

---

## 4 · 全局一致性审查

按「一次整体通读、不做逐文件评审」执行，覆盖 7 个产出文件：

1. **跨文件 import 一致、无循环**：`gp_toolbar → sheet_combat`（单向，`sheet_combat` 不回引工具栏）；`gp_combat_list → gp_combat_strip`（单向，`gp_combat_strip` 不回引列表）；`sheet_combat → member_view / room_view / combat_view / room_text / js_compat / room_panel_kit / room_sheet / room_keys / room_scope`，全部为叶子模块。`dart analyze` 零 unused / 零缺失导入。
2. **接口契约**：`showCombatSheet<T>(BuildContext)` 签名未变（`sheet_kp_panel.dart:158` 既有调用点仍可用）；`CombatSheetKeys` / `GpCombatKeys` 既有常量全部保留；`RoomKeys.action('scene.mode')` / `combat.start` 的 `enabled` 恒等 `gate.can(op)`；未新增任何 `RoomKeys.action` 的新 op（T-30 静态锚点表仍 30 op，`kFrozenNoAnchor` 未漂移）。
3. **数据流**：`CombatSheet` 装配 `actorIds/actors/pcSeats` → `RoomController.hostAction` → `LocalLoopbackSession.hostAction` → `domain combatStart`（`actors` 过滤 → `initiativeOrder` → `state.combat.order` + `meta.mode=combat`）→ `combatRows` → `GpCombatStrip` / 顶部 `initiativeText`。用例 ④ 与 ⑦ 从 `host.state` 与裁剪后 `stateOf('p1')` 双向验证，PC 槽与怪物槽真实存在、K4 隐藏口径成立。
4. **无重复实现**：strip 的 3 个 key 以 `GpCombatStripKeys` 为单一真相源由 `GpCombatKeys` 别名引用；DEX/HP 复用 `member_view` 纯函数而非另造一份；`roundText` 只在 `combat_view.dart` 定义一次；无重复 widget。
5. **禁止面**：未动 domain / 布局骨架 / 他组独占文件 / GENERATED / oracle / FROZEN。

**IS_PASS: YES**（一轮通过，无需二轮）

---

## 5 · 反向证伪（只在本人文件集内）

备份：`/tmp/t7cb_gp_toolbar.dart.bak`、`/tmp/t7cb_sheet_combat.dart.bak`、`/tmp/t7cb_gp_combat_list.dart.bak`（备份时 sha256 与交付态一致）。每次改坏后跑 `flutter test test/p10_t7_c_combat_test.dart --concurrency=1`，随后 `cp` 恢复 + 核 sha256 + 恢复 lock。

| # | 改坏动作 | 跑测结果 | 转红用例（归因正确） |
|---|---|---|---|
| ① | `gp_toolbar.dart` 的 `onTap` 换回直发 `scene.mode` | `exit=1`，`+12 -2: Some tests failed` | `① 探索态点 scene.mode 按钮 → 出现选择参战单位弹层，且 sent 无 scene.mode`（**用例 1 红** ✅）；`⑥ 战斗态点按钮走 combat.end`（`combat.end` not null 断言拿到 `<null>`） |
| ② | `sheet_combat.dart` 的 `actors` 去掉 PC 记录 | `exit=1`，`+9 -5: Some tests failed` | `③ 勾 1 怪 + 保留 2 玩家 → 载荷逐字段`（`Expected <2> Actual <0>`）、`④ domain 侧真实生效`（`Expected <3> Actual <1>`）（**用例 3/4 红** ✅）；另带红 ②历史路径、③取消玩家、⑦轮次条（PC 槽消失的连带效应） |
| ③ | `gp_combat_list.dart` 去掉 `GpCombatStrip` 渲染 | `exit=1`，`+12 -2: Some tests failed` | `⑦ 战斗轮次信息栏` 两条全部转红：`Expected: exactly one matching candidate / Actual: Found 0 widgets with key [<'gpCombat/strip'>]`（**用例 7 红** ✅） |
| ④ | **主理人追加项**：`sheet_combat.dart` 的 `_actorPayload` 改回硬编码常量（不读表单） | `exit=1`，`+16 -2: Some tests failed` | 第 ⑨ 组两条转红：`DEX 33 / HP 27 / 每轮 3 / NPC → 载荷逐字段`（`Expected <33> Actual <50>` 等逐字段失配）、`每轮次数静默夹 1–10`（`Expected <10> Actual <1>`）；归因正确（硬编码不再读 KP 输入）；⑩ 裁决用例与主体 14 条仍绿（见第 7.3 节） |

**恢复后 sha256 清单**（每次恢复后即刻核对，末尾最终复跑再次核对，数值与备份/交付态完全一致）：

| 恢复轮次 | 恢复文件 sha256 | `pubspec.lock` sha256 | `grep -c pub.dev` |
|---|---|---|---|
| ① 后 | `13f1a5f3a35ace26715768b6aabe12305dfe5255d4a624f9c847c0597e4b5ca3`（gp_toolbar.dart） | `fa69e59604415960b7449e0b5827fb5ec7eec0926a607d6078edca176504d86c` | 82 |
| ② 后 | `2b3837ab8b9317c71b2dd635ba85da5c85e6be6fa52a9180d1d723a79c5ff54a`（sheet_combat.dart） | `fa69e59604415960b7449e0b5827fb5ec7eec0926a607d6078edca176504d86c` | 82 |
| ③ 后 | `a3b7d23ac19201c95591ead65cfa14a1a7541d18bebec20546c2a54d0c7887e2`（gp_combat_list.dart） | `fa69e59604415960b7449e0b5827fb5ec7eec0926a607d6078edca176504d86c` | 82 |
| ④ 后 | `26aebc44255b70140a88fa5f9e871c45eb68e814f009b830a855a128472059c0`（sheet_combat.dart，与备份 `/tmp/t7cb_sheet_combat.final.bak` 逐字节一致） | `fa69e59604415960b7449e0b5827fb5ec7eec0926a607d6078edca176504d86c` | 82 |
| 最终复跑后 | 7 个文件全部见第 1 节表（含追加项 / 裁决后的最终 sha256） | `fa69e59604415960b7449e0b5827fb5ec7eec0926a607d6078edca176504d86c` | 82 |

> 注：表「② 后」的 `2b3837ab…` 是**主体交付态**（追加项之前）`sheet_combat.dart` 的历史恢复值，属主体证伪窗口的如实留痕；本轮追加项 + 裁决又改了该文件，故**最终态**以第 1 节表的 `26aebc44…` 为准，二者不矛盾。④ 是本轮追加项证伪，恢复值即最终态。

**复跑全绿**：恢复后重跑 `dart analyze lib test`（零问题）+ 5 个强制测试文件，全部 `All tests passed!`（输出见第 3.3 节最终态）。

---

## 6 · 遗留问题 / 主理人裁决结果

> ★ **本节矛盾已由主理人于本轮裁决定稿**（见第 8 节「主理人裁决：空池兼容口径」）：接受 `monsters.isNotEmpty && selectedMonsterIds.isEmpty` 兼容条件，不授权改 `room_ui_permission_test.dart`。以下 6.1 保留原始分析作为决策留痕。

### 6.1 施工单内部矛盾（已用最小兼容方案处理并经主理人裁决定稿，**未改被禁止的测试文件**）
施工单要求「若 `_monsterOn.isEmpty` → 不发 `combat.start`」，同时要求「`test/room_ui_permission_test.dart` 全绿」且「除此之外不动任何既有测试文件」。但 `room_ui_permission_test.dart:642` 的「选槽位后」用例在**候选池完全为空**时直接点弹层的 `combat.start` 进入战斗态，再用 `combat.enqueue` 造槽位；`combatEnqueue` 在 `state.combat` 不存在时直接拒答（domain :313-317）。若严格按字面挡住，该用例必红（首轮实跑确实红了一条：`开战并追加入场后权威态应有参战槽位：null`）。

**处理**：门禁条件实现为 `monsters.isNotEmpty && selectedMonsterIds.isEmpty` —— 只要**候选池非空**（本批所有门禁用例都塞了怪，主理人验收点 2 亦然），门禁严格生效、不发 `combat.start` + 一次性提示；仅当「候选池完全为空、根本没有可勾的怪」时保留历史「纯 PC 开战」路径。已新增专门用例 `历史路径：候选池完全为空时仍可部署纯 PC 战斗` 显式钉住该兼容契约（断言 `actorIds` 为空、`pcSeats` 全选、`actors`/`order` 都恰为 PC 数、且**没有**「至少选择 1 个怪物/NPC」提示），避免被误读为门禁漏洞。

**主理人裁决（本轮，已定稿）**：亲自复核 `room_ui_permission_test.dart:631-646` 后确认该用例是 **T-30 权限探针**（验证 `combat.damage` 的 `enabled` 恒等闸门），「空候选池直接点 `combat.start`」只是造参战槽位的手段，并非在测开战门禁；且「纯 PC 开战」是本工程既有能力，砍掉属未经授权的功能回退。⇒ **接受 `monsters.isNotEmpty && selectedMonsterIds.isEmpty` 兼容条件**，不授权改该文件（门禁性质文件，不该为 UI 需求动它）。同时要求两点补强：① 空池时部署按钮 `hint` 必须明说「当前无怪物候选，将以纯玩家战斗开始」；② 报告单列裁决节并写清 QA 复核要点。两点均已落地，见第 8 节。

### 6.2 两处实现口径说明（非缺陷）
- `actors` 只放**勾选**的怪物 + **勾选**玩家的 PC 记录（而非「全量候选 + 全量 PC 再靠 domain 过滤」）。施工单写的是「勾选/全量的怪物候选」可选口径，且验收点 3 明确要求「1 怪 + 2 个 PC 记录」；本实现与 `actorIds` / `pcSeats` 完全自洽，domain 的过滤为幂等，结果一致、载荷更小。
- `stripHeader`（`initiativeText` 文案）挂在 `gp_combat_list.dart` 顶部 Text 上，`GpCombatStrip` 内部只画槽条 + 可选「🎯 轮到你行动了」。这样 `strip` / `stripSlot` / `stripCurrent` / `stripHeader` 四个 key 都能稳定检索，且 strip widget 可独立复用（调用方自行配 header）。

### 6.3 建议 QA 复核注意
- 门禁用例请**务必先往 `local.pendingActors` 塞至少 1 只怪**（`_addMonster` 口径），否则命中的是 6.1 的历史兼容路径而非门禁路径。
- 轮次条的「隐藏」断言请在**玩家视角**（`isKp=false`）下做；KP 视角 `combatRows(isKp:true)` 会用 secret 补全 HP，`hpHidden` 恒为 false（这是既有 S1 契约，非本批改动）。

---

## 7 · 主理人追加：战斗弹层「加单位」数值表单

> 本节是**主理人追加项**（中途补发指令）的专项交付说明。用户问题 3 原话：「增加怪物、NPC，没有让我填数值（比如HP、DEX等）」覆盖三处加怪入口；B 批已修 `gp_kp_tools.dart` / `gp_kp_left.dart` 两处窄栏，本批补上第三处 `sheet_combat.dart` 的「加单位」区，消除同 App 内三处「加怪」行为漂移。

### 7.1 只读复用的 B 批组件（先读 API 再接线，未写该文件）
`lib/ui/room/widgets/gp_kp_tools.dart` 的 export 组件，最终 sha256 `a207b4bbe18bfd7f0f8612dc6f79e248513bb9c47ed0b08092606be6cf53d5ad` **与本轮开工前/收尾后三次核对值逐字节一致，证明只读未写**：
- `ActorFieldsController`：`nameCtrl`（默认「怪物」）、`dexCtrl`（50）、`hpCtrl`（10）、`actionsCtrl`（1）、`kind`（`'monster'`）；getter `nameValue` / `kindValue`（只认 monster/npc）/ `dexValue` / `hpValue` / `actionsValue` 均为 `int.tryParse(...) ?? 默认`，**非法输入静默回落、不弹错**；`dispose()` 由父组件调用。
- `ActorFieldKeys({name, kindRow, kindMonster, kindNpc, dex, hp, actions})`：每个控件一套稳定 key，两处窄栏各传自己的，避免 `findsOneWidget` 退化。
- `ActorFields` 内联小表单（`Wrap` 自动换行、类型用 ChoiceChip），本身不挂按钮（T-30 归父组件）。

`sheet_combat.dart` 只加一行 `import '../widgets/gp_kp_tools.dart' show ActorFieldKeys, ActorFields, ActorFieldsController;`。

### 7.2 实现（全部在 `sheet_combat.dart` 内）
- `CombatSheetKeys` 新增 6 个**独立**稳定 key：`actorDex` / `actorHp` / `actorActions` / `actorKind` / `actorKindMonster` / `actorKindNpc`，值全部带 `combatSheet/` 前缀——弹层与整页窄栏可能同树，独立 key 才不会让 `findsOneWidget` 退化成 `findsWidgets`。既有 `CombatSheetKeys.actorName` 继续挂在名称输入框上。
- `_CombatSheetState` 用 `final ActorFieldsController _fields = ActorFieldsController();` 取代原单 `_actorName`，`dispose()` 里 `_fields.dispose()`。
- 「加单位」SectionBox 的单行 TextField 换成 `ActorFields(controller: _fields, keys: ActorFieldKeys(...6 个 key...))`。
- `_actorPayload` 签名从 `_actorPayload(String name)` 改为 **`_actorPayload(ActorFieldsController c)`**，逐字段读表单值，与 B 批 `addLocalActor` 口径**逐字段一致**：
  ```
  id   = 'u' + name.hashCode.abs()      name = 空则「单位」否则原名
  kind = c.kindValue（仅 monster/npc）   dex  = c.dexValue（默认 50 / 非法回落）
  hp   = c.hpValue                       hpMax = hp（同值写，老 APP 口径）
  actionsPerRound = c.actionsValue 静默夹 1–10
  ```
  **不再有硬编码常量**；老 APP 没有的字段（DB / 护甲 / 闪避 / MOV / 单独 HP 上限 / 怪物库）一律不加。
- `RoomKeys.action('combat.actor')` 的 `onTap` 载荷 `{'actor': _actorPayload(_fields)}` 带齐 `id/name/kind/dex/hp/hpMax/actionsPerRound`。
- `RoomKeys.action('combat.pool.set')` **保持原语义**：`{'actors': <Object?>[...local.pendingActors]}` 整体替换候选池，未改成从表单拼一条。
- `combat.actor` / `combat.pool.set` 两个按钮的 `enabled` 仍**恰好** `gate.can(op)`（T-30，见 ⑨ 组用例逐 op 断言），未叠任何表单前置。

### 7.3 追加测试 / 反向证伪
- 并入 `test/p10_t7_c_combat_test.dart` 第 ⑨ 组 **3 条**：① 填 DEX 33 / HP 27 / 每轮 3 / NPC → `combat.actor` 载荷逐字段（`dex=33, hp=27, hpMax=27, actionsPerRound=3, kind='npc'`，且 `takeException()==null`）；② 非法数字静默回落默认（dex 50 / hp 10 / 每轮 1，覆盖三个字段，不弹错）；③ 每轮次数夹 1–10（99→10）+ `combat.pool.set` 仍是候选池整体替换。**主体 14 条一字未动**。
- **反向证伪 ④**（本轮专做）：把 `_actorPayload` 临时改回硬编码 `kind:'monster', dex:50, hp:10, hpMax:10, actionsPerRound:1` → 跑主测试 `+16 -2: Some tests failed`，第 ⑨ 组**转红 2 条**：「DEX 33 / HP 27 / 每轮 3 / NPC → `combat.actor` 载荷逐字段」（`dex/hp/hpMax/actionsPerRound/kind` 逐字段失配）、「每轮次数静默夹 1–10」（`Expected <10> Actual <1>`），归因正确（硬编码不再读 KP 输入）；第 ⑨ 组「非法数字回落默认」、主体 14 条与 ⑩ 裁决用例仍绿 → `cp /tmp/t7cb_sheet_combat.final.bak` 恢复 → 核 sha256 `26aebc44255b70140a88fa5f9e871c45eb68e814f009b830a855a128472059c0`（与备份一致、无「反向证伪临时改动」残留）→ 复跑 18 条全绿。**恢复后 sha256 清单见第 5 节表「④ 后」行**。

### 7.4 本轮重跑结果（每条命令后恢复 lock）
| 命令 | 结果 |
|---|---|
| `dart analyze lib test` | `No issues found!` |
| `flutter test test/p10_t7_c_combat_test.dart --concurrency=1 --no-pub` | `+18: All tests passed!` |
| `flutter test test/room_ui_kp_test.dart --concurrency=1 --no-pub` | `+35: All tests passed!` |
| `flutter test test/room_ui_permission_test.dart --concurrency=1 --no-pub` | `+19: All tests passed!` |
| `flutter test test/p10_t7_b_assets_actors_test.dart --concurrency=1 --no-pub` | `+8: All tests passed!`（**B 批共享组件回归，确认未被带坏**） |

每条后 `cp pubspec.lock.t7bak pubspec.lock`，均核对 `fa69e596…` / `pub.dev=82`。收尾首跑遇 flutter 工具删除 `native_assets.json` 缓存失败（环境故障，非代码），单文件备份 + 清除后自愈、build 实目录完整，详见第 1 节说明。

### 7.5 追加项最终态 sha256
| 文件 | sha256 |
|---|---|
| `lib/ui/room/sheets/sheet_combat.dart` | `26aebc44255b70140a88fa5f9e871c45eb68e814f009b830a855a128472059c0` |
| `test/p10_t7_c_combat_test.dart` | `80401e2b86782caf1c65d3357b31ae0915742bfbeabf2163b5c83faca7a63222` |
| `lib/ui/room/widgets/gp_kp_tools.dart`（只读参照，未写） | `a207b4bbe18bfd7f0f8612dc6f79e248513bb9c47ed0b08092606be6cf53d5ad` |
| `pubspec.lock`（恢复后） | `fa69e59604415960b7449e0b5827fb5ec7eec0926a607d6078edca176504d86c` |

---

## 8 · 主理人裁决：空池兼容口径

> 本节记录主理人本轮对第 6.1 节施工单内部矛盾的**裁决结果与落地**。

### 8.1 裁决结论（定稿）
- **兼容条件**：`monsters.isNotEmpty && selectedMonsterIds.isEmpty` → 才触发「至少 1 怪」门禁。
- **为什么保留纯 PC 开战**：`room_ui_permission_test.dart:631-646` 是 **T-30 权限探针**（验证 `combat.damage` 的 `enabled` 恒等闸门），「空候选池直接点 `combat.start`」只是造参战槽位的手段，不是在测开战门禁；而「纯 PC 开战」是本工程既有能力，砍掉属**未经授权的功能回退**。故不授权改该文件。
- 主理人确认该方案：候选池非空时门禁严格生效（真机场景必然有怪，因为问题 3 就是让用户加怪）、空池保留历史路径、没删/改/skip 任何既有用例、反而新增专用用例钉住兼容契约（加严不是放宽）、门禁仍在 `hint` + `onTap showNotice`、`enabled` 恒等 `gate.can('combat.start')` 未动。

### 8.2 裁决要求的两点补强（均已落地）
1. **空池 hint 文案**：`combat.start` 的 `RoomTap.hint` 现在是三分支，空候选池时**明确写出**「当前无怪物候选，将以纯玩家战斗开始」，不再让用户以为点了没反应或莫名跳进战斗：
   ```
   monsters.isEmpty                        → '当前无怪物候选，将以纯玩家战斗开始'
   monsters 非空 && selectedMonsterIds 空  → '至少选择 1 个怪物/NPC'
   monsters 非空 && 已勾                   → '按勾选的参战单位开战'
   （gate 不能 'combat.start' 时）          → '只有 KP 能开战'
   ```
   三分支与 `onTap` 门禁条件**完全自洽**，`hint` 绝不参与 `enabled` 计算（T-30）。
2. **报告单列裁决节**：即本节 + 第 6 节标题/结论已改为「已定稿」，第 0 节与第 1 节同步。

### 8.3 QA 复核要点（主理人指定，已由 ⑩ 组用例钉住）
- **候选池非空时门禁必须严格生效**：`test/p10_t7_c_combat_test.dart` 第 ⑩ 组「有怪未勾」场景断言 hint 含「至少选择 1 个怪物/NPC」、`combat.start` 未发包、`local.notice` 含该提示、`enabled` 恒等闸门。
- **空池时无「至少选择 1 个怪物/NPC」提示**：第 ⑩ 组「空池」场景断言 hint 含「纯玩家战斗」、`isNot(contains('至少选择 1 个怪物/NPC'))`、`enabled` 恒等闸门；既有 ② 组「历史路径」用例另断言 `local.notice` 也无该提示且 `actors`/`order` 恰为 PC 数。
- 门禁用例务必先 `_addMonster` 塞 1 只怪（否则命中的是空池兼容路径，见 6.3）。

### 8.4 裁决落地最终态 sha256
| 文件 | sha256 |
|---|---|
| `lib/ui/room/sheets/sheet_combat.dart`（含追加数值表单 + 空池 hint） | `26aebc44255b70140a88fa5f9e871c45eb68e814f009b830a855a128472059c0` |
| `test/p10_t7_c_combat_test.dart`（18 条，含 ⑩ 组） | `80401e2b86782caf1c65d3357b31ae0915742bfbeabf2163b5c83faca7a63222` |
| `pubspec.lock`（恢复后） | `fa69e59604415960b7449e0b5827fb5ec7eec0926a607d6078edca176504d86c` / `pub.dev=82` |

**IS_PASS: YES**（追加项 + 裁决复审：跨文件 import 单向无环、`ActorFieldsController` API 逐字段对齐、T-30 两按钮 `enabled` 恒等闸门、三分支 hint 与门禁自洽、`combat.pool.set` 语义未漂移、B 批共享组件回归全绿、无重复实现、无禁止面改动）。

---

## 9 · QA Round 1 阻断修复（emoji 门禁 + jsStr 预算门禁）

> QA 独立全量回归（`flutter test --concurrency=1`，2152 条）路由回 Engineer 的 2 条失败。独占窗口，**只改 2 个文件**：`lib/ui/room/widgets/gp_combat_strip.dart`、`lib/ui/room/sheets/sheet_combat.dart`。测试、门禁文件、domain、版本文件一字未动。

### 9.1 改动清单

**① `test/p12_emoji_b_test.dart:125` 源码守卫（lib/ui/room/**/*.dart 零表情）**
- 门禁：`kEmoji = RegExp(r'[\uD800-\uDBFF][\uDC00-\uDFFF]')`，对 `lib/ui/room` 每个 .dart 做 `kEmoji.hasMatch(readAsStringSync().replaceAll('★',''))`。`🎯` = U+1F3AF，UTF-16 代理对被抓到。
- `gp_combat_strip.dart` 两处命中：`:44` 注释 `/// 「🎯 轮到你行动了」提示…`、`:75` 字符串 `'🎯 轮到你行动了',`。
- 修法：**两处都去掉 emoji**，文案统一为「轮到你行动了」（注释同步为「轮到你行动了」提示）。这是施工单标「可选」的提示，改纯文本不影响功能。没有替换为任何别的代理对区间字符 / 图标字。
- `⚔️`（U+2694 + FE0F，BMP dingbat 区）**不在**该门禁的代理对检测范围，且被 `p10_t7_c_combat_test.dart:295` 断言 `label contains('⚔️ 战斗部署完毕')`，**未动**。

**② `test/room_ui_lobby_test.dart:758` 静态冻结门禁（jsStr 预算）**
- 门禁：扫 `lib/ui/room/**/*.dart` 所有含字面量 `jsStr(` 的行 → `leaks`（不在白名单 6 文件）必须为空，且 `hits.length <= 13`。
- 修复前：`sheet_combat.dart` 有 **14 处** `jsStr(`（行 126/130/131/137/139/182/183/187/190/209/210/214/218/460），不在白名单 → leaks 非空；全树 hits = **27 > 13**。
- ★ 关键算术：白名单内恰好 13（`gp_combat_list` 4 + `room_session_local` 3 + `room_session_remote` 3 + `room_text` 1 + `gp_scene_check_pl` 1 + `gp_status` 1）。故 `sheet_combat.dart` 的 14 处**必须一处不剩**全部清掉才刚好压线 13，留任意 1 处都 FAIL。
- 修法：`:32` 已 `import '../room_text.dart' show roomText;`，`room_text.dart:21` 定义 `String roomText(Object? v) => v == null ? '' : jsStr(v);`。把 **14 处 `jsStr(` 全部替换为 `roomText(`**（替换后 `roomText(` 共 21 处 = 原有 7 + 新增 14）；同时把 `:29` 的 `import '../../../domain/js_compat.dart' show asMap, jsStr;` 收敛为 `show asMap`（`jsStr` 不再使用，避免 unused_import）。文件内 `jsStr` 字面量最终为 **0**。
- 未扩白名单、未放宽 `<= 13`、未 skip、未加 ignore 注释；两个门禁测试文件一字未动。

### 9.2 null 等价性论证（语义不变）
`jsStr(null)` 返回 `'null'`（`lib/domain/js_compat.dart:79-81`，JS 语义 oracle 不可动），`roomText(null)` 返回 `''`。但本文件 14 处输入恒为：
- `m['seat']`：来自 `playersOf(state)` 的成员 seat（集合键 / `pcToggle` / `pcSeats` 装配），业务上必存在且非 null；
- `asMap(a)['id']`：来自 `local.pendingActors`，`addLocalActor` 与 B 批 `ActorFields` 数值表单必写 id，非 null。

非 null 输入下 `roomText(v)` 直接 `return jsStr(v)`，与 `jsStr(v)` **逐字等价**；seat / id 参与的都是 `Set<String>.contains` / `ValueKey` / 字符串插值 / `hostAction` 载荷键，取值完全一致。因此不需要、也没有为「兼容 null」额外加 `?? 'null'` 把字面量引回来。6 个测试文件（含 `p10_t7_c_combat` 18 / `room_ui_kp` 35 / `room_ui_permission` 19）全绿即为等价性的动态佐证。

### 9.3 全树扫描结果（复刻门禁口径）
| 项 | 修复前 | 修复后 | 门禁要求 |
|---|---|---|---|
| 全树 `jsStr(` hits | 27 | **13** | `<= 13` ✅ |
| `sheet_combat.dart` 的 `jsStr(` | 14 | **0** | 必须 0（否则 leaks 非空）✅ |
| leaks（非白名单命中） | 非空 | **空** | `isEmpty` ✅ |
| 全树 emoji 代理对 dirty 文件 | 1（`gp_combat_strip.dart`，2 个 `🎯`） | **0** | `isEmpty` ✅ |

白名单 6 文件命中分布（修复后，合计 13）：`gp_combat_list.dart` 4 / `room_session_local.dart` 3 / `room_session_remote.dart` 3 / `room_text.dart` 1 / `gp_scene_check_pl.dart` 1 / `gp_status.dart` 1。emoji 全树扫描用 Python 复刻门禁（`[\U00010000-\U0010FFFF]` 匹配增补平面代理对 + `.replaceAll('★','')`），`dirty files = 0`。

### 9.4 验证结果（每条 flutter/dart 命令后 `cp pubspec.lock.t7bak pubspec.lock`）
| 命令 | 用例数 | 结果 |
|---|---:|---|
| `dart analyze lib test` | — | **No issues found!**（import 收敛后无 unused_import / warning / error） |
| `flutter test test/p12_emoji_b_test.dart --concurrency=1 --no-pub` | 12 | ✅ All tests passed! |
| `flutter test test/room_ui_lobby_test.dart --concurrency=1 --no-pub` | 18 | ✅ All tests passed! |
| `flutter test test/p10_t7_c_combat_test.dart --concurrency=1 --no-pub` | 18 | ✅ All tests passed!（主体 14 + 追加 3 + 裁决 1 未回归） |
| `flutter test test/room_ui_kp_test.dart --concurrency=1 --no-pub` | 35 | ✅ All tests passed! |
| `flutter test test/room_ui_permission_test.dart --concurrency=1 --no-pub` | 19 | ✅ All tests passed!（T-30 锚点表未漂移） |
| `flutter test test/p10_t7_layout_test.dart --concurrency=1 --no-pub` | 9 | ✅ All tests passed!（几何不回归） |
| **合计** | **111** | **全绿** |

每条命令前 `unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy; export NO_PROXY=127.0.0.1,localhost`；每条后恢复 lock 并核对 `sha256 == fa69e59604415960b7449e0b5827fb5ec7eec0926a607d6078edca176504d86c`、`pub.dev == 82`、`flutter-io == 0`，**全部符合**。未改 `pubspec.yaml` / `app_version.dart` / `lib/domain/**`，未 `flutter clean`，`build` 实目录完整，未跑 adb / 模拟器 / 真机。

### 9.5 两条反向证伪（独占窗口内做，恢复用 `cp` + `cmp -s` 逐字节核对）

| # | 改坏动作 | 跑红结果 | 归因 |
|---|---|---|---|
| ① | `gp_combat_strip.dart:75` 文案临时加回 `'🎯 轮到你行动了'` | `p12_emoji_b_test.dart` → `+11 -1: Some tests failed` | 「B · 源码守卫」用例转红：`Expected: empty / Actual: ['lib/ui/room\widgets\gp_combat_strip.dart']`，精确命中 ✅ |
| ② | `sheet_combat.dart:460` 一处 `roomText(` 临时改回 `jsStr(`（import 临时还原 `show asMap, jsStr;` 以免触发无关的编译错误） | `room_ui_lobby_test.dart` → `+17 -1: Some tests failed` | 「门禁 · jsStr 预算」用例转红：`leaks` 精确列出 `sheet_combat.dart:460  final String seat = jsStr(m['seat']);`，全树 hits = 14 > 13 ✅ |

**恢复后 sha256 清单**（每次 `cp` 恢复后即 `cmp -s` 与修复态备份逐字节核对，均 identical）：

| 恢复轮次 | 文件 | 恢复后 sha256 | `cmp -s` | lock sha256 | pub.dev / flutter-io |
|---|---|---|---|---|---|
| ① 后 | `gp_combat_strip.dart` | `d6476108aa61cf87d76003aebd9269d4cf9c055fe5541b2ce4d24e9c667b0f7e` | identical ✅ | `fa69e596…` | 82 / 0 |
| ② 后 | `sheet_combat.dart` | `7c3cc69d2e860237ccfde2b00d43a29a0d793889ec4fb31401503ade76d5aa44` | identical ✅ | `fa69e596…` | 82 / 0 |
| 最终复绿后 | 两文件见 9.6 | 同 9.6 | identical ✅ | `fa69e596…` | 82 / 0 |

恢复后重跑 `dart analyze lib test`（零问题）+ 6 个测试文件（111 条）全部 `All tests passed!`。备份：`/tmp/t7qa_gp_combat_strip.fixed.bak`、`/tmp/t7qa_sheet_combat.fixed.bak`（修复态），`/tmp/t7qa_*.base.bak`（改前基线）。

### 9.6 两文件最终态 sha256（冻结前连续 3 次采样稳定一致）
| 文件 | 改前基线 | 修复后最终态 |
|---|---|---|
| `lib/ui/room/widgets/gp_combat_strip.dart` | `e677de14e2a59b1cdc032ee239b2640559735895194a153e007c90a40f0c824d` | **`d6476108aa61cf87d76003aebd9269d4cf9c055fe5541b2ce4d24e9c667b0f7e`** |
| `lib/ui/room/sheets/sheet_combat.dart` | `26aebc44255b70140a88fa5f9e871c45eb68e814f009b830a855a128472059c0` | **`7c3cc69d2e860237ccfde2b00d43a29a0d793889ec4fb31401503ade76d5aa44`** |

> hash 演进说明：第 1 / 8 节记录的 `e677de14…`（strip）、`26aebc44…`（sheet）是**本轮 QA 修复前**的如实留痕；本轮两文件均有改动，最终态以本表为准。其余 6 个产出文件本轮一字未动，sha256 与第 1 节一致。冻结前连续 3 次采样值完全相同，且与修复态备份 `cmp -s` 逐字节一致。

**IS_PASS: YES**（两门禁计数精确达标、6 文件 111 条全绿、analyze 零问题、两条反向证伪归因精确且恢复逐字节一致、null 等价性成立、无禁止面改动）。
