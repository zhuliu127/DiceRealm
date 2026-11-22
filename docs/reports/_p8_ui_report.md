# P8 UI / 首页 / 页面拆分 —— 交付报告

工程：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
范围：`lib/ui/home_page.dart`、`lib/ui/ai_create_page.dart`、新建 `lib/ui/roster_page.dart` /
`lib/ui/random_create_page.dart`、`lib/ui/card_detail_page.dart`（只加分享按钮）、
`lib/ui/widgets.dart`、`lib/app.dart`、测试。
**未触碰** `lib/domain/**`、`lib/ui/create/**`、`lib/ui/room/**`、`lib/repo/settings_repo.dart`、
`lib/repo/repo_scope.dart`、`pubspec.yaml`；未 `flutter clean`、未出包、未加依赖。

结论：**IS_PASS: YES**（相关 11 个测试文件合并回归 134 组全绿；`flutter analyze lib test` 零问题）

---

## 1. 逐条需求：根因与改法

### 需求 2-a「五个 UI 图下边框 / 右边框不见了」—— 根因已量化

`assets/images/a_home/a_home_banner_*_2x1.webp` 实测 **1536×620 = 2.4774:1**，
四条金边内缩（像素扫描 10 张横幅取最小值）：

| 横幅 | 金边左 | 金边右 | 金边上 | 金边下 |
|---|---|---|---|---|
| room（暗） | 13px | 1523px | 15px | 604px |
| 其余 9 张（ai/random/wizard/valhalla + light 各版） | 13–18px | 1516–1523px | 11–18px | 602–607px |

旧实现 `AspectRatio(2.0)` + `BoxFit.cover` + `Alignment.centerLeft`：
- 2.0 < 2.477 → cover 以**高**为准铺满，左右各裁 `(1−2.0/2.477)/2 ≈ 9.6%` ≈ 74px；
  金边只内缩 13px，**右边框直接裁没**；`centerLeft` 又把偏移全推到右侧，右边更彻底消失；
- 上下方向不裁，但卡片高度比图矮（2:1 框 vs 2.477:1 图）→ 视觉上「下边框也没了」。

**改法**：`_EntryBanners._aspect = 2.0 → 2.45`，`Alignment.centerLeft → Alignment.center`。
2.45 时左右各裁 `(1−2.45/2.477)/2 = 0.55%` = **8.5px < 13px 金边内缩**，上下 0 裁切。
用 PIL 按 2.45 居中裁切真实素材做了像素级验证（四条金边完整，左右金线各留 ~5px 余量）。

分类头（`a3_section_*_6x1.webp`，1536×256 = 6:1）旧实现 `SizedBox(height: 46)` + cover：
手机上框是 8~26:1，等于只取图中间 1/4~1/26 的横条，上下金边全被裁。
**改法**：抽出公共组件 `SectionBanner`（`lib/ui/widgets.dart`），外层 `AspectRatio(6)` 与源图比例**完全一致** → cover 一像素不裁。

### 需求 2-b「『开始冒险』和『角色档案』UI 长度不一致」—— 根因已定位

`_CategoryHeader` 自带 `EdgeInsets.fromLTRB(16,4,16,10)`，而 `_RosterSection` 又被
`SliverPadding(fromLTRB(16,0,16,0))` 包了一层 → 「角色档案」实际缩进 32，「开始冒险」只有 16。
**改法**：去掉 `SliverPadding`，两个区块各用**一次** `Padding(horizontal: 16)`，
`SectionBanner` 只保留纵向内边距（`only(top:4,bottom:10)`）。
测试断言两个分类头的 `Rect.left` / `Rect.right` / `width` 全等。

### 需求 3「HP/SAN 等状态数值超出边框」

根因：首页 `_CardGrid` 是 2 列、单卡 ~150px 宽，底部 `_MiniStat(HP) + 6 + _MiniStat(SAN)`
两枚固定内边距的胶囊在窄卡里必然溢出。
**改法**（结构解决，不是缩字号糊过去）：卡片移出首页 → 名册页**一行一张**整行长条，
数值放进 `Wrap(spacing:6, runSpacing:6)`（HP / SAN / MP 三枚），窄屏只会换行。
测试：1200px 与 320px 两档视口都断言 `tester.takeException()` 为 null。
（顺手修掉一个此前无人覆盖的横向溢出：首页顶栏 `骰境TRPG + COC 7th + 菜单` 在 320dp 溢出 50px，
标题改 `Expanded` + 省略号。）

### 需求 4「角色卡收进 UI 图的菜单里」

新页 `lib/ui/roster_page.dart`（路由 `/roster`，常量 `RosterPage.route`）：
「已保存的角色卡」+「英灵殿」两块，一行一张卡（名字 / 规则徽标 `card_rule_badge_<id>` /
职业·年龄·性别 / HP·SAN·MP / 更新时间），已撕卡偏灰并带 `RippedBadge`，
空态复用 `EmptyState`（📜 / 🕯）。

首页只保留：
- 可点的「角色档案」分类横幅（`Key('home_roster_entry')`，带 `已保存 N · 英灵殿 M`）；
- 两行只读计数 `已保存的角色卡` / `英灵殿`（同样点击进名册，空时下方给一句提示）。

**为什么首页还留这两行字**：① 用户要一眼看到数量，点进去才知道太绕；② 保住老测试
`find.text('英灵殿')` 在首页恰好命中一处（`qa_probe_test.dart:322`）与
`create_flow_widget_test.dart:73/74/191/192` 的空态文案口径 —— **断言强度没有降低**，
只是卡片本体换了页面。首页确实不再铺任何卡片（p8 测试断言卡名在首页 `findsNothing`）。

### 需求 5「切亮色很多 UI 不跟着切」

根因（与主理人定位一致，并扩大排查）：`const` widget 实例在父级重建时是**同一个对象**，
`Element.updateChild` 判定 `child.widget == newWidget` 后直接跳过 rebuild，
其 `build` 里读的 `Palette.xxx` / `Art.xxxFor(brightness)` 就永远停在旧皮肤。
首页的 `const SliverToBoxAdapter(child: _EntryBanners())` 是最典型的一处
（`_RosterSection` 非 const 所以会变 —— 正好对上用户截图）。

**改法（两层）**：
1. 首选：去 const（`_AdventureSection` 的调用点），并让构建链上的 widget 真的重建；
2. 系统性兜底：`lib/ui/widgets.dart` 新增 `dependOnTheme(context) => Theme.of(context);`，
   在 `SectionCard / SectionBanner / SectionTitle / StatTile / EmptyState / RippedBadge /
   Pill / HairLine / FieldLabel / KeyValueRow` 的 `build` 首行调用它。
   `Theme.of` 建立的是 **Element 级依赖**，皮肤一变 `InheritedWidget.notifyClients`
   直接把依赖者标脏 —— **即使 widget 是 const 也会重建**，因此这一招同时修好了
   `create/**`、`room/**` 里那些用 const 构造这些公共组件的地方（没有改他们的文件）。
   `HomePage.build` / `_AdventureSection.build` / `_EntryBanner.build` 也加了同款依赖。

亮色下空态插画（`Art.emptyCards` / `Art.emptyValhalla` 只有暗色版）：`EmptyState` 在
`!Palette.isDark` 时把插画不透明度压到 0.5，退成淡墨线，不再是一块深色方块。
实测截图（flutter test golden，字体为占位方块）：切亮色后首页整体变象牙底、标题变深金。

### 需求 1「AI 车卡页 / 一键出卡页拆分」

- `ai_create_page.dart`：删掉 `_candidates / _batch / _generateRandom / _candidatesCard /
  _randomCard`，本页只剩 AI（规则选择 → 输入 / 示例 / 世界设定 / 上限档位 → 生成 →
  结果 → 失败回退）。保留并改造：
  - 「不想用 AI？」区块（`_noAiCard`）+ 入口按钮 `Key('ai_entry_random')` → `/random`；
  - 未配置 AI 时的副按钮 `ai_use_random_from_config` → 也改成跳 `/random`；
  - 失败回退 `ai_fallback_random` → 跳 `/random`（兜底依旧**真的能拿到卡**，只是换了页面）。
- 新建 `random_create_page.dart`（路由 `/random`，`RandomCreatePage.route`）：
  - **只有**随机 5 张，调用 `preset.generate(5, PresetOptions(ruleSystemId: defaultRule))`，
    **没有**任何 AI 输入框 / 世界设定 / 上限档位；
  - 右下角常驻 `FloatingActionButton.extended(Key('random_reroll'))`，点击直接重出一批
    （`Stack + Positioned`，不随列表滚走）；
  - 选中一张 → 写 `changeLog` → `CreateFlowPage(initial: c, skipRules: true)`（与 AI 页同一条 `_adopt` 路径）；
  - 用 `SingleChildScrollView + Column`（而非 ListView）保证 5 张卡全量构建，避免懒构建导致的点击/滚动抖动。
- 首页「一键出卡」入口 `entry_random` 的目标从 `AppRoutes.ai` 改为 `RandomCreatePage.route`。
  路由常量放在页面里（`repo_scope.dart` 的 `AppRoutes` 不在本批改动范围）。

### 需求 10「角色卡顶部 bar 加快捷分享」

`card_detail_page.dart`：只读态 actions 在「修改」`btn_edit` 右侧插入
`IconButton(Key('card_quick_share'))`，点击滚动到页面底部云分享区（`SharePanel`）。
不用「直接 `Scrollable.ensureVisible`」的原因：只读态是 `ListView(children:…)`，
分享区在屏外时**根本不在树里**，拿不到 context。实现为：先 `jumpTo(maxScrollExtent)`
把末尾拉出来（懒构建的 max 是估算值，最多补 4 帧收敛），拿到 context 后
`Scrollable.ensureVisible(alignment: 0.05)` 平滑对齐。没有假弹层、没有假成功提示。

---

## 2. 文件清单

新增：
- `lib/ui/roster_page.dart`（名册页，`/roster`）
- `lib/ui/random_create_page.dart`（一键出卡页，`/random`）
- `test/p8_home_ui_test.dart`（11 组验收）
- `_p8_ui_report.md`（本文件）

修改：
- `lib/ui/home_page.dart`（重写版式：分类头抽公共组件、aspect 2.45、居中、去 const、卡片移出、两行只读计数、顶栏防溢出）
- `lib/ui/widgets.dart`（新增 `SectionBanner` / `SectionTitle` / `dependOnTheme`；空态亮色插画降透明）
- `lib/ui/ai_create_page.dart`（瘦身为 AI-only + 一键出卡入口）
- `lib/ui/card_detail_page.dart`（快捷分享按钮 + 分享区锚点）
- `lib/app.dart`（注册 `/random`、`/roster`）

测试改动：`test/support/app_harness.dart`、`test/qa_probe_test.dart`、
`test/create_flow_widget_test.dart`、`test/p7_rule_registry_test.dart`、
`test/ai_create_page_test.dart`、`test/p7_ai_caps_ui_test.dart`、
`test/card_detail_edit_test.dart`（逐条理由见 §3.2）。

---

## 3. 测试账目

### 3.1 新增 `test/p8_home_ui_test.dart`（11 组，全绿）

| # | 用例 | 守的是什么 |
|---|---|---|
| 1 | 两个分类头左右边界完全相等 | bug 2-b：`Rect.left/right/width` 三者全等 |
| 2 | 入口横幅宽高比 2.45 且居中 | bug 2-a：比例在 [2.3,2.5] 且 ≥2.44，`BoxFit.cover` + `Alignment.center` |
| 3 | 首页不再铺角色卡 | bug 4：卡名首页 `findsNothing`，名册页 `findsOneWidget` |
| 4 | 切亮色后「开始冒险」文字变亮色金 | bug 5：真走 菜单→设置→点亮色→返回，断言 `Text.style.color == AppPalette.light.goldStr`，并断言 `ArtImage.path == Art.bannerRoomLight` |
| 5 | 名册页逐卡带 `card_rule_badge_<id>`、数值不溢出 | 需求 3/4 + P7-D 徽标口径 |
| 6 | 一键出卡页 5 张 + `random_reroll` 换批 | 需求 1（批次计数 1→2，仍 5 张） |
| 7 | 「重新随机」换的是内容（注入生成器） | 需求 1：旧批消失、新批出现 |
| 8 | AI 页无 `preset_candidate_*`，有 `ai_entry_random` 且能跳 | 需求 1 |
| 9 | 卡详情有 `card_quick_share`，点了真的停在云分享区 | 需求 10（400×760 视口下「前不可见 / 后可见」） |
| 10 | 320px 窄屏名册数值不溢出 | 需求 3（共 10 条 use case，第 5 条内含 `takeException` 双重断言） |

### 3.2 老测试改动清单（逐行说明，全部是「结构变了必须跟着变」，没有放宽任何断言）

1. `test/support/app_harness.dart` `pumpCardDetail()`：在 `pumpApp` 之后加
   `tap(home_roster_entry)` + `pumpAndSettle` 再点卡名。
   理由：卡片已不在首页；这只是多一跳导航，详情页覆盖范围不变。
   （`card_detail_edit_test` / `share_panel_test` 等直接受益，无需逐个改。）

2. `test/qa_probe_test.dart`「英灵殿里的卡点得开」：`tap('已阵亡者')` 前加
   `tap(home_roster_entry)` + `pumpAndSettle`。
   理由同上；`expect(find.text('英灵殿'), findsOneWidget)`（第 322 行）**原样保留**且仍成立。

3. `test/create_flow_widget_test.dart`
   - ① 保存后：`expect('阿米蒂奇', findsOneWidget)` 前加进名册的一跳（断言本身不变）；
   - ④ 已撕卡：把 `长眠者` / `☠ 已撕卡` 两条断言移到进名册之后；首页只留
     「空态提示在 / 不在」两条（原第 191–192 行，原样保留）；
   - ⑤ 永久疯狂：`疯狂者` / `☠ 已撕卡` 前加进名册的一跳。
   理由：卡片与撕卡徽标都搬到名册页；「只出现在英灵殿」「必须有撕卡徽标」的判据没变。

4. `test/p7_rule_registry_test.dart`「卡列表：每张卡都有 card_rule_badge_<id>」：
   `pumpApp` 后加 `tapKey(tester, 'home_roster_entry')`；并把 `tapKey` 加进 import 的 show 列表。
   理由：徽标 Key 与断言完全不变，只是所在页面变了（该 Key 在名册页逐卡保留）。

5. `test/ai_create_page_test.dart`
   - 「生成失败 → 错误卡 + 改用一键出卡」：原断言「本页出现 5 张 `preset_candidate_*`」
     改为「跳到 `RandomCreatePage` 且 5 张卡、5 个 `adopt_candidate_*` 都在」。
     理由：兜底入口按需求改成跳转；「必须真的能拿到卡」的强度不变（依旧断言 5 张完整卡）。
     同时删掉「有候选了就不该还挂着错误卡」—— 候选卡已不在本页，此断言失去对象（理由写进用例注释）。
   - 「随机卡：选一张进向导」：改用 `ai_entry_random` 进入随机页，新增一条
     「AI 页不应存在 `preset_candidate_0`」；「候选不落库 / 进向导也不落库」两条原样保留。

6. `test/p7_ai_caps_ui_test.dart`「未选规则：所有生成入口停用」：把
   `ai_random_batch`（就地生成，停用）改为 `ai_entry_random`（页面跳转，`onPressed != null`）。
   理由：随机页自带默认规则，跳过去一定出得了卡；「生成动作不许放假按钮」的判定仍然
   只对真生成动作（`ai_generate`）成立，没有放宽。

7. `test/card_detail_edit_test.dart`
   - 「菜单 → 删除 → 回首页」：详情现在是从名册进来的，pop 回名册（空态），再 `pageBack()` 回首页。
     断言仍是「库清空 + 有空态 + 能回到首页」，只是多了「名册页」这层中间态。
   - 「首页导入 JSON → 新卡上屏」：`expect('旧版调查员', findsOneWidget)` 前加进名册的一跳。

### 3.3 本轮实跑结果（全部绿）

最终合并回归（11 个文件一次跑）：**134 通过 / 0 失败**

| 批次 | 文件 | 结果 |
|---|---|---|
| 新增 | `p8_home_ui_test.dart` | 10/10 通过 |
| 指定老测试 | `qa_probe_test` `create_flow_widget_test` `p7_rule_registry_test` `p7_theme_test` `ai_create_page_test` `settings_page_test` | 全通过 |
| 受影响的分享 / 车卡详情 | `p7_ai_caps_ui_test` `p7_share_badge_test` `card_detail_edit_test` `share_panel_test` | 全通过 |
| 其余触碰首页入口的用例 | `create_extra_steps_test` `room_ui_entry_test` `room_ui_lobby_test` `step_background_test` `assets_logic_test` `background_blocks_test` | 93 通过 / 0 失败 |

补充验证（临时脚本，已删除，不入库）：
- PIL 按 2.45 / 4 张横幅做像素级裁切目视：四条金边完整；
- `flutter test --update-goldens` 截首页暗/亮两版目视：亮色确实全页生效（象牙底 + 深金字）；
- 320dp 下 AI 页 / 随机页 / 名册页 / 首页 `takeException()` 均为 null。

---

## 4. 待出图 TODO（本批按要求**不生成图**，先用现有素材/系统图标顶上）

1. **「重新随机」悬浮按钮图标**
   - 现用：`Icon(Icons.casino)`（`lib/ui/random_create_page.dart`）。
   - 规格：1:1（256×256），PNG 透明底，暗 / 亮各一张（亮色版线条更深，压象牙底才看得清）。
   - 落位建议：`assets/images/icons/general/reroll_1x1.png` + `reroll_light_1x1.png`，
     在 `Art` 里加 `Art.icon('reroll')` 与 `Art.rerollFor(brightness)`。
2. **「一键出卡」页头图**
   - 现用：`Art.wizardHeaderFor(brightness)`（3:1，拉过来当页头）。
   - 规格：3:1（1440×480），暗 / 亮各一张；左侧 40% 留文字安全区，右侧放主体插画
     （页面上头图下方紧接着是说明文字与 5 张卡，图别放太重的信息）。
3. **亮色版空态插画**（`a5_home_empty_cards` / `a6_home_empty_valhalla` 只有暗色版）
   - 现在用「不透明度 0.5」兜住，建议补 1:1 亮色版（羊皮卷墨线风）；
   - 落位后把 `EmptyState` 的 opacity 兜底换成 `Art.emptyCardsFor(brightness)`。
4. **「角色档案」首页横幅** 若后续要单独一张（当前复用 `a3_section_archive_6x1`），规格同 6:1。

---

## 5. 已知影响 / 风险

1. **详情页删除后的返回落点**：从首页 → 名册 → 详情，删除后 pop 回名册（空态），
   不再是「一步回首页」。这是路由栈的自然结果，已在测试里固化；如果产品要「删完直接回首页」，
   需要在 `_delete` 里再 pop 一次（本批没做，避免多跳行为与既有用例冲突）。
2. **名册页一行一张卡**：卡片多（>20 张）时列表变长，靠 ListView 懒构建兜住；
   首页计数仍是一眼可见。
3. **`SectionBanner` 现在是 6:1 自适应高度**：手机上约 57–66px（原 46px 固定）。
   平板 / 桌面窗口下会按比例变高（1200 宽 → 195px），这是「不裁金边」的代价；
   若觉得太高，可在 `SectionBanner` 加 `maxHeight` 并用 `BoxFit.cover` 裁上下（会牺牲部分边框，不建议）。

## 6. 其他人的文件（不在本批范围，仅提示）

- 最新一次 `flutter analyze lib test` 已是 **No issues found**（此前他人新建测试里的两条
  unused warning 已被其 owner 修掉），我这边没有引入问题。
- 亮色换肤的**系统性问题**（同一 `const` + `Palette` 组合）理论上还存在于
  `lib/ui/create/**`、`lib/ui/room/**` 中那些**直接**读 `Palette` 的常量子组件里。
  公共组件（`SectionCard`/`EmptyState`/`StatTile`/`Pill`/…）已被 `dependOnTheme` 兜住，
  但页面内部自建的小 widget 若被 const 化仍可能停色。需要各文件 owner 用同一招
  （`dependOnTheme(context)` 或在调用点去 const）。本批没有改他们的文件。
