# P10 第 7 期 B/C · 主理人收口报告

> 收口人：齐活林（Qi）· 交付总监
> 工程根：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
> 交付副本：`C:/Users/60965/WorkBuddy/2026-11-08-13-25-14`
> 日期：2026-11-12 · 版本 **2.26.0+96**
> 性质：主理人编排汇总。专业产出分别由 B / C-A / C-B 三组工程师与 QA 独立复核输出，详见 `_p10_transport10_b.md` / `_p10_transport10_ca.md` / `_p10_transport10_cb.md` / `qa_p10_10_report.md`。

---

## 0 · TL;DR

P10 第 7 期 B/C 批四组真问题全部落地，**QA 两轮独立复核 `IS_PASS: YES` / 路由 `NoOne`**，升版本后串行全量 **2152/2152 全绿**，release APK 已出并完成 AOT 排雷。

| 项 | 值 |
|---|---|
| 版本 | `2.26.0+96`（`pubspec.yaml` + `lib/app_version.dart` 两处同改） |
| 交付 APK | `dice-realm-v2.26.0.apk` |
| 字节数 | **70,561,384 B** |
| SHA256 | `B2A17FF3D8DD7F8B29A49C2A5A11803CBE3FC5CCC1B9997BC09A7538F14D2A84` |
| 三 ABI `libapp.so` | 8,979,336 / 9,962,056 / 9,241,480 字节 |
| 全量回归 | `flutter test --concurrency=1` **2152/2152**（5m44s，EXIT=0） |
| 静态门禁 | P4 13/13、P5 UI 14/14、`dart analyze lib test` 零问题 |
| QA | Round 1 `IS_PASS: NO / Engineer` → Round 2 `IS_PASS: YES / NoOne` |
| 真机 | **未跑 adb / 模拟器 / 真机**，7 组待测项只登记 |

---

## 1 · 本批解决的用户问题（第 7 期 10 项中剩余的 4 组）

| # | 用户原话（摘要） | 落地 |
|---|---|---|
| 2 | 上传素材后没有缩略图；点公开后素材栏多一个、公开栏不显示 | B 批：`dataURL → base64Decode → Image.memory(40×40)` 缩略图、坏数据静默占位、按 id 去重；A 批已修好舞台 16:9 与底图遮盖 |
| 3 | 增加怪物 / NPC 没让填数值，对照老 APP 2.13.13 | B 批：抽出共享 `ActorFields` / `ActorFieldsController` / `ActorFieldKeys`，三处入口都能填 `kind / dex / hp / actionsPerRound`；`hp` 同写 `hpMax`，每轮次数静默夹 1–10；`addLocalActor` 函数体零改动 |
| 5 / 6 | 聊天输入框点击后变全屏；公开信息栏显示不出最新 4 条、全屏后不实时更新 | C-A：新增 `sheet_chat_composer.dart` 全屏多行编辑器（草稿双向同步、系统返回键保留、「完成」回填不发包、「发送」复用 `_send()`）；`gp_feeds.dart` 换订阅式 `_LiveFeedBody`，跟随判据由「列表长度」改为**末条 seq**（cap 打满仍跟随），保留 `!_atBottom()` 早退 |
| 10 | 点「转战斗」没让选怪物和玩家，也没有战斗轮次信息栏 | C-B：「转战斗」改开战斗准备弹层（玩家默认全选 / 怪物默认全不选 / 至少 1 怪门禁写在 `hint + onTap`，不进 `enabled` 以守 T-30）；`combat.start` 载荷**显式拼 PC 记录**；新增 `GpCombatStrip` 行动顺序条与 `initiativeText`「第 N 轮 · 当前行动：X」 |

**施工图纠错**：`_p10_t7_research.md` C2 曾写「domain 自动带 PC」，实为错误。`lib/domain/room_model_actions_combat.dart:170-197` 的 `combatStart` 只读 `p['actors']` 取池子，`actorIds` 仅用于过滤、`pcSeats` 仅用于过滤已有 PC，**不会凭空创建 PC 记录**。主理人在派工单里纠正后，UI 按老 APP `pcActors(ctx).concat(monsterActors)` 口径显式装配，QA 独立读 domain 二次证伪。

**主理人裁决**：施工单要求「至少 1 怪」严格门禁，同时要求不改 `room_ui_permission_test.dart`。实读 `:631-646` 后确认那是 T-30 权限探针，靠「空候选池直接 `combat.start`」造槽位；砍掉纯 PC 开战属未经授权的功能回退。裁决为条件 `monsters.isNotEmpty && selectedMonsterIds.isEmpty`：候选池非空未勾怪严格拦，候选池全空保留历史路径，并补空池 hint「当前无怪物候选，将以纯玩家战斗开始」。

---

## 2 · QA Round 1 抓到的两条阻断（工程师定向子集「假绿」的教训）

三组工程师报告合计只跑了定向 15 个文件 / 254 条，**漏跑两个全局源码守卫**。QA 全仓回归 2152 条发现 **2 条阻断 / 2 条 Failing tests**（`jsStr` 一个根因同时打红 flutter 门禁与 P5 静态门禁，故 **3 条门禁红 / 2 个根因**）：

| # | 门禁 | 命中 | 修法 |
|---|---|---|---|
| 1 | `test/p12_emoji_b_test.dart:125` 房间 UI 零 emoji 源码守卫（`kEmoji` 代理对正则） | `gp_combat_strip.dart:44` 注释 / `:75` 字符串的 `🎯` U+1F3AF | 两处改纯文本「轮到你行动了」，不换别的代理对字符 |
| 2 | `test/room_ui_lobby_test.dart:758` `jsStr(` 预算冻结（白名单 6 文件 + `hits <= 13`）；同源触发 `qa_p5_ui.js` 13/14 | `sheet_combat.dart` 新增 14 处 `jsStr(`，全树 hits 27 | 14 处全改已审计的 `roomText(`，import 收敛为 `show asMap`；全树 27 → **13**，压线通过 |

**关键算术**：白名单内命中恰好 13（`gp_combat_list` 4 / `room_session_local` 3 / `room_session_remote` 3 / `room_text` 1 / `gp_scene_check_pl` 1 / `gp_status` 1），所以 14 处必须一处不剩。修法**只改源码、不改门禁**：不扩白名单、不放宽阈值、不 skip、不加 ignore。两个门禁测试 mtime 仍是 `2026-11-11 15:12` / `02:16`，sha 未变 —— 不是靠放宽测试变绿。

`jsStr(null)` 返回 `'null'`，`roomText(null)` 返回 `''`；但 14 处输入恒为 `m['seat']`（`playersOf`）或 `asMap(a)['id']`（`addLocalActor` 必写），业务上不可能为 null，非 null 输入下逐字等价。

---

## 3 · QA 独立复核（两轮）

- **Round 1**：全仓 c1 `2152 条 / 2150 通过 / 2 失败`，c4 同样 2150/2 且失败名单逐字相同 ⇒ 无顺序依赖；`dart analyze` 当时即零问题、P4 13/13 —— 恰好说明只有静态门禁抓得到。判定 `Engineer`。
- **Round 2**（修复后新基准）：全仓 c1 **2152/2152 全绿**、c4 重跑 **2152/2152 全绿**；两门禁 `+30` 全绿；P4 13/13、P5 **14/14**（`IS_PASS: YES`）；`app_version_test` 3/3；12 个关键文件一次编译 207/207；`dart analyze` 零。判定 **`IS_PASS: YES / NoOne`**。
- **反向证伪 7 条**（全部「改坏 → 指定用例红 → `cp` + `cmp -s` 逐字节恢复 → 复绿」）：§3 旧基准 5 条 —— B 缩略图、C-A 全屏 body 换快照、C-B `onTap` 直发、C-B 去 strip，以及 QA 自造探针「全屏编辑器系统返回键草稿保留」（C-A 报告承认未写该用例，改坏 `result ?? ''` 后红 `Expected: '系统返回键也要保住这段还没发完的草稿' / Actual: ''`）；**§5.3 修复后新基准补做 2 条** —— R2-F1 重新注入 U+1F3AF → `p12_emoji_b_test.dart` 红（`Expected: empty`），R2-F2 精确回退 `:29 show asMap, jsStr` + `:126` 两处 `roomText` → `qa_p5_ui.js` 与 `room_ui_lobby_test.dart:758` 双红。恢复后连续 3 次 `sha256sum -c` 各 14/14 OK，内容级归零（`jsStr(`=0 / 非 BMP=0 / `show asMap, jsStr`=0），确认**无改坏残留**。临时探针已删。
- **口径更新经逐字核对为加严**：`room_ui_kp_test.dart` 保留 6 项核心不变量、新增 7 组更强正向断言 + 1 条独立门禁用例；35 = B 批 34 + 1，与「47/47 = 34+13」交叉自洽；`skip:` / `findsWidgets` / `expect(true…)` 零命中。
- **完整性**：`lib/domain/**` 零改动、无新增 `RoomEvt` / intent / domain action；`lib/ + test/ + tool/` 实扫 408 文件 NUL=0；`test/` 顶层仍 152 个；禁改文件（domain / `pubspec.yaml` / `app_version.dart` / `room_game_page.dart` / `room_ui_permission_test.dart` / `room_ui_feeds_test.dart`）mtime 全早于本批。

报告：`qa_p10_10_report.md`（**476 行 / 7 节 / 49,872 B / NUL 0 / sha256 `d669ab49…793a`**（QA 回传后又补过一处措辞，+43 B；结论未变，此处为磁盘最终真值）），同时含 Round 1 完整证据链与 Round 2 最终判定，无 APPEND-HERE 占位。

---

## 4 · 主理人收口动作（逐步实证）

| 步 | 动作 | 结果 |
|---|---|---|
| 1 | 按 QA §6.1 清单做 14 项 `sha256sum -c` | **14/14 OK**（第 7/9 项已用修复后新哈希） |
| 2 | 升版本 `2.25.0+95 → 2.26.0+96` | `pubspec.yaml:19` + `app_version.dart:15/:18` 两处同改 |
| 3 | `flutter test test/app_version_test.dart --concurrency=1` | **3/3 All tests passed**，EXIT=0 |
| 4 | 升版本后 `flutter test --concurrency=1` | **2152/2152 全绿**（5m44s，EXIT=0） |
| 5 | 清 AOT 增量缓存 | `.dart_tool/flutter_build`（36 文件）、`build/app/intermediates/flutter`（119 文件）删除，删后确认 ABSENT；`build` 仍实目录（`islink False`） |
| 6 | 备份 + 临时切 Gradle 代理 | 原 `gradle.properties` sha `964d9ef7…7d84a1`；`9194` dead → 本机活端口 `7743`（从 `HTTP_PROXY` 读出并探活） |
| 7 | `bash tool/build_apk.sh` | EXIT=0，122.0s，`√ Built ... (67.3MB)`，三 ABI `libapp.so` 齐备 |
| 8 | 恢复配置 | `gradle.properties` `cmp -s IDENTICAL`（端口回 9194）；`pubspec.lock` `fa69e596…` / `pub.dev=82` / `flutter-io=0` |
| 9 | 拷交付副本 | `dice-realm-v2.26.0.apk` 与构建产物 `cmp -s IDENTICAL` |
| 10 | 文档更新 | `_manual_test_checklist.md` 顶部新批次块 + 7 组真机待测；`overview.md` 头部与新 TL;DR；本报告 |

---

## 5 · ★ AOT 排雷（防止「看似正常的坏包」）

**逐 ABI SHA 对比**（新包 vs 上批 `dice-realm-v2.25.0.apk`）：

| ABI | v2.25.0 | v2.26.0 | 判定 |
|---|---|---|---|
| arm64-v8a | `9f5180c5…` | `6d04ad76…` | 不同 ⇒ 重编 |
| armeabi-v7a | `68893b47…` | `ad816700…` | 不同 ⇒ 重编 |
| x86_64 | `950dd8a6…` | `f305c6e6…` | 不同 ⇒ 重编 |

**字节级 UTF-16LE hex 任意偏移搜索**（`lib/arm64-v8a/libapp.so`；旧「对齐 GetString」法会漏奇数偏移中文，已弃用）：

| 字面量 | 命中 |
|---|---|
| `编辑发言` | 2 |
| `最新 4 条` | 1 |
| `轮到你行动了` | 1 |
| `战斗部署完毕` | 1 |
| `至少选择 1 个怪物/NPC` | 1 |
| `当前无怪物候选，将以纯玩家战斗开始` | 1 |
| `战斗模式 · 选择参战单位` | 1 |
| `其他骰子` | 1 |
| `2.26.0`（latin-1 单字节串） | 1 |
| `服务：本机进程内`（已删项，反向对照） | **0** |
| `2.25.0`（旧版本号，反向对照） | **0** |

⇒ 本批新代码、新版本号确实进了 AOT 快照，旧内容已清除。

---

## 6 · 交付文件清单（14 项，sha256 以 QA §6.1 为准）

| # | 组 | 文件 | sha256 |
|---|---|---|---|
| 1 | B | `lib/ui/room/widgets/gp_kp_left.dart` | `74f7c465…85f6` |
| 2 | B | `lib/ui/room/widgets/gp_kp_tools.dart` | `a207b4bb…d5ad` |
| 3 | B | `lib/ui/room/widgets/room_layout.dart`（仅注释） | `a8146d54…21b` |
| 4 | C-A | `lib/ui/room/widgets/gp_feeds.dart` | `43018cef…af75` |
| 5 | C-A | `lib/ui/room/sheets/sheet_chat_composer.dart`（新建） | `f6821c29…214c` |
| 6 | C-B | `lib/ui/room/widgets/gp_toolbar.dart` | `13f1a5f3…ca3` |
| 7 | C-B | `lib/ui/room/sheets/sheet_combat.dart`（★Round2 修复） | `7c3cc69d…5a44` |
| 8 | C-B | `lib/ui/room/widgets/gp_combat_list.dart` | `a3b7d23a…c7e2` |
| 9 | C-B | `lib/ui/room/widgets/gp_combat_strip.dart`（新建，★Round2 修复） | `d6476108…b0f7e` |
| 10 | C-B | `lib/ui/room/view/combat_view.dart` | `9c03efd2…5cfc8` |
| 11 | B | `test/p10_t7_b_assets_actors_test.dart`（新建 8 条） | `d8712265…446d` |
| 12 | C-A | `test/p10_t7_c_feeds_test.dart`（新建 10 条） | `c5a52e81…5475` |
| 13 | C-B | `test/p10_t7_c_combat_test.dart`（新建 18 条） | `80401e2b…3222` |
| 14 | C-B | `test/room_ui_kp_test.dart`（1 条加严口径更新 + 1 条新增，35 条） | `ec9d97b0…28bb` |

另：`pubspec.yaml` / `lib/app_version.dart` 由主理人收口升版本；`_p10_transport10_b.md` / `_ca.md` / `_cb.md` 为三组工程师报告，`qa_p10_10_report.md` 为 QA 报告，本报告为主理人收口，`_manual_test_checklist.md` / `overview.md` 已更新。

---

## 7 · 遗留问题（均非阻断）

1. **一次并发偶发**：`--concurrency=4` 出现过 1 次 `p8_wizard_nav_test.dart` 5 条 `(did not complete)`，无任何 Expected/Actual 断言失败；单跑该文件 6/6、全仓 c4 重跑 2152/2152 全绿，判定 Windows `flutter_tester` 并发瞬时挂起。建议后续 CI 以 `--concurrency=1` 为准。
2. **候选池仍是 `local.pendingActors`**（本机内存、不进存档）：研究文档 C1 列「可选、推荐但可延后」，本批未纳入，建议排后续期。
3. **真机极端边界**：合法 base64 但非图片字节的 `errorBuilder` 降级；`ListView.builder` 行高差异极大时首帧贴底可能需 1 帧收敛；单条消息高度超过面板时贴底只见下半部分。
4. **轮次栏位置**：按最小方案只渲染在 `gp_combat_list.dart` 战斗面板内，`room_game_page.dart` 的 `RoomSlot.gpCombatStrip` 仍是零尺寸兜底，未做「横屏地图上方叠加」。
5. `room_ui_kp_test.dart:694` 固有 `tap()` hit-test warning（点 tab 文本命中祖先 InkWell），非失败、非本批引入。

---

## 8 · 真机待测（只登记、不执行）

沿用用户约定「真机测试等全部做完了再测」，**本批未跑 adb / 模拟器 / 真机**。7 组逐项验收标准见 `_manual_test_checklist.md` 顶部新章节：

B1 素材缩略图 / 公开栏去重；B2 三处加怪数值表单；C1 聊天全屏 + 物理返回键草稿；C2 公开栏最新 4 条 / 实时 / 上滚不抢；C3 转战斗选参战单位与门禁；C4 轮次栏与 HP 隐藏；C5 A 批几何不回归。

---

## 9 · 最终判定

**IS_PASS: YES** · **路由：NoOne** · **阻断出包问题：无**

- 三组工程师产出 14 个源码 / 测试文件，逐字节 14/14 核对通过；
- QA 两轮独立复核用满，Round 1 的 **2 条阻断**（2 条 Failing tests / 3 条门禁红 / 2 个根因）全部复绿且未放宽任何门禁；
- 主理人升版本、串行全量、清缓存出包、AOT 逐 ABI + 字节级双重排雷、配置逐字节还原；收口后再做一次只读完整性核验（14/14 哈希、APK/配置 sha 未变、探针已删、进程归零）；
- 交付副本 `dice-realm-v2.26.0.apk` 已就位，真机部分按约定只登记。
============================================================
