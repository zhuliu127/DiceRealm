# P9 · 规则选择前置 + 结果页按钮拆分 + 保存回首页 + 头图统一 + 档案入口图 — 交付报告

工程：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
角色：flow-rework（流程重构）
结论：**IS_PASS**（`flutter analyze` 零问题；全量 `flutter test` 1678 通过 / 1 失败，唯一失败是并发端口 flake，见 §五.1）

---

## 一、改动清单（逐文件）

### 1. 新增 `lib/ui/create/rule_pick_page.dart`
- `RulePickPage({required RulePickTarget next, List<RuleMeta>? rules})`：
  - `next` 是枚举 `RulePickTarget { room, ai, random, wizard }`（switch 全覆盖，新增去向不会漏处理）；
  - `rules` 为 null 时取 `RuleRegistry.all`，非 null 时按传入列表渲染（测试注入口，用于自证「遍历注册表而不是写死三条」）。
- 页面：`AppBackground` + `AppBar('选择规则系统')` + `ContentFrame` + `ListView`：顶部 `SectionBanner`（内部已是 `BannerSlot` 钳高 96px），下方竖排 **2:1** 大卡片，`Key('rule_pick_<id>')`。
- 卡面：`ArtImage(Art.ruleCardFor(rule.id, Palette.brightness), cover)` + 自下而上渐变压暗；文字 = 规则全名（衬线金字）+ `shortName` 药丸 + `rulebook` + 一句状态（`可选 · 点这张卡进入…` / `未开放 · 规则层尚未实现，敬请期待`）。
- 未开放（`available == false`）：`Opacity(0.5)` + 右上角「未开放」标签 + **`InkWell.onTap == null`**（真没回调）。
- 跳转：`room` → `pushNamed(AppRoutes.room)`；`ai` → `AiCreatePage(initialRuleId:)`；`random` → `RandomCreatePage(initialRuleId:)`；`wizard` → `CreateFlowPage(initialRuleId:, skipRules: true)`。

### 2. `lib/ui/home_page.dart`
- **四入口前置**：`fab_room` / `fab_ai_create` / `entry_random` / `fab_new_card` 的 Key 全不动，目标改为 push `RulePickPage(next: …)`。
- **「角色档案」改成两张 2:1 入口图**（追加需求）：
  - 竖排、等宽、`AspectRatio(2)`，与「开始冒险」四宫格同一套视觉；
  - 底图 `Art.homeBannerCardsFor(...)` / `Art.homeBannerValhallaFor(...)`；
  - 文字画在图上（不烧进图）：标题（已保存的角色卡 / 英灵殿）+ 左侧竖条，副标题在有卡时是「N 位调查员」/「N 位长眠者」，空态时沿用原空态文案（「还没有角色卡，从上方「按流程车卡」开始」/「还没有英雄长眠于此」）—— 老用例断言的就是这两句，空态语义没变；
  - Key：`home_roster_entry` 挂在**第一张**外面（`KeyedSubtree`，不产生 RenderObject，`tester.tap` 仍落在里面那张可点的卡上，老用例零改动）；两张卡各自 `home_roster_saved` / `home_roster_valhalla`；
  - 全页只保留**一处**「英灵殿」三字（卡片标题），分区头 hint 改成「已保存 N 张 · 长眠 M 位」，避免 `qa_probe_test` 的 `find.text('英灵殿') findsOneWidget` 变多；
  - 删除不再使用的 `_RosterSummaryRow`（死代码）。

### 3. `lib/ui/ai_create_page.dart`
- 新增 `initialRuleId`（保留旧 `initialRuleSystemId` 作为兼容别名，同时传时新参数优先）。
- 有值时**不再渲染那排 `ChoiceChip`**，改一条只读说明 `Key('ai_rule_current')`；无值时保留原芯片行为（老入口/老用例不变）。
- 结果卡按钮拆分（需求 6）：`Key('result_use_this')`「就用这张」= 落库 + 回首页；`Key('result_continue_edit')`「继续完善」= 进 8 步向导、不落库。原 `ai_adopt` 单按钮删除。
- **追加：页头图** —— `ClipRRect` + `SizedBox(height: 64, width: double.infinity, child: ArtImage(Art.wizardHeaderFor(...), cover))`，`Key('ai_header')`，放在 `body` 的 `SafeArea` 内、滚动区之外（`Column` + `Expanded(ListView)`）。**不用 `AspectRatio`**，宽屏不膨胀。

### 4. `lib/ui/random_create_page.dart`
- 新增 `initialRuleId`；`_ruleId = RuleRegistry.effectiveId(...)` 传给 `preset.generate`（沿用既有 `PresetOptions(ruleSystemId:)`）。
- 页头加只读 `Key('random_rule_current')`。
- 每张候选卡两个按钮：`onUseThis`（落库 + 回首页）、`onContinueEdit`（进向导，不落库）。
- **追加：头图统一** —— 去掉裸 `AspectRatio(3)`，改为 `ClipRRect` + `SizedBox(Key('random_header'))` + `BannerSlot(aspectRatio: 3, maxHeight: 120, minHeight: 64)`，Art 常量与向导页同一个。

### 5. `lib/ui/summary_card.dart`（候选卡公共组件）
- 删除 `onAdopt` / `adoptLabel`；新增 `onUseThis` / `onContinueEdit` / `keySuffix`。
- 键：`result_use_this$keySuffix` / `result_continue_edit$keySuffix` —— AI 结果页后缀为空，一键出卡为 `_0…_4`（一屏 5 张，键必须唯一）。

### 6. `lib/ui/create/create_flow_page.dart`
- 新增 `initialRuleId`：`RuleRegistry.effectiveId(...)` → `newCharacter(ruleId)`；带卡进来时 `draft.raw['ruleSystemId'] = ruleId`（与 `steps/step_rules.dart` 同一条写入路径，占位规则由 `effectiveId` 兜住，永不写进卡）。
- 新增 `backToHome(NavigatorState)` = `popUntil(r.isFirst)`；`_save()` 由 `navigator.pop()` 改为 `backToHome(navigator)`（需求 8）。
- **追加：头图统一** —— 固定 68px 的 `SizedBox` 改为 `SizedBox(Key('wizard_header'))` + `BannerSlot(aspectRatio: 3, maxHeight: 120, minHeight: 64)`，与一键出卡页同一个 `Art.wizardHeaderFor` + 同一组参数（两处注释互相指向，防止以后走偏）。

### 7. `lib/ui/art.dart`
- **已无重复定义**（我接手清理时它已经收敛成一份；`flutter analyze lib` 零问题）。当前状态：
  - `ruleCardCoc7 / ruleCardCoc7Light / ruleCardDnd5e / ruleCardDnd5eLight / ruleCardCustom / ruleCardCustomLight` + `_ruleCards` 表 + `ruleCardFor(String, Brightness)` 各一份（G 段）；
  - `homeBannerCards / homeBannerCardsLight / homeBannerCardsFor`、`homeBannerValhalla / homeBannerValhallaLight / homeBannerValhallaFor`、`roomEntryHeaderFor` 全部在位（首页角色档案两张图就用它们）。
  - 我这侧没有再写入任何 art 常量，页面只**调用** `Art.*`。

### 8. `lib/app.dart`
- **未改动**：入口直接 push 页面，不需要新增 `/rules` 命名路由与 arguments 解析（加一个没人用的路由常量属死代码）。既有 `/ai` `/random` `/room` `/create` 与深链全部保留。

---

## 二、老测试改动（逐条，都是产品行为变更，无一条放宽断言）

| 文件 | 改动 | 理由 |
| --- | --- | --- |
| `ai_create_page_test.dart` | 入口用例：点 `fab_ai_create` 后先断言 `RulePickPage` 存在、`AiCreatePage` 不存在，再点 `rule_pick_coc7`；另 2 处入口点击各补一行选规则 | 需求 5：入口不再直达 AI 页 |
| 同上 | `ai_adopt` → `result_continue_edit` | 需求 6：单按钮拆两个，旧键已删 |
| 同上 | `adopt_candidate_$i` → `result_use_this_$i` + `result_continue_edit_$i`（5 张逐张） | 按钮从 5 个变 10 个，断言变**多** |
| `p7_ai_caps_ui_test.dart` | `ai_adopt` → `result_continue_edit` | 同需求 6 改名 |
| `p8_home_ui_test.dart` | 「一键出卡」用例拆两步：先断言 `RulePickPage` 且 `RandomCreatePage` 不存在，再点 COC 进随机页 | 需求 5，并新增「选规则前不许已进随机页」 |
| 同上 | `expect(find.text('1'), findsWidgets)` → `expect(find.text('1 位调查员'), findsOneWidget)` | 追加需求：计数从「单独数字」变成入口图副标题整句。仍是「首页必须显示张数」，语义更明确 |
| `create_flow_widget_test.dart` | `_gotoAttrs` 去掉「规则步 → 基础资料」的 `btn_next`，改点 `rule_pick_coc7`；① 用例补 `expect(find.text('1 / 8'))` | 需求 5：跳过 rules 步，首屏即基本资料 |
| 同上 | 步数断言 `3 / 9` → `2 / 8`（2 处）、`5 / 9` → `4 / 8` | 分母 9→8、序号前移 1。校验文案断言一条未动 |
| 同上 | 「取消返回」用例：取消后停在 `RulePickPage`，再 `pageBack` 回首页 | 取消 = 返回上一页（规则选择页）；「保存后回首页」由需求 8 用例单独守 |
| `create_extra_steps_test.dart` | `_gotoAssets` 补 `rule_pick_coc7`、去首个 `btn_next`；`9 / 9` → `8 / 8`、`6 / 9` → `5 / 8` | 同上；数据契约断言全部未动 |
| `step_background_test.dart` | `_gotoBackground` 补 `rule_pick_coc7`、去首个 `btn_next`；`8 / 9` → `7 / 8` | 同上 |
| `room_ui_entry_test.dart`(3 处) / `room_ui_lobby_test.dart`(1 处) | 点 `fab_room` 后补 `rule_pick_coc7`，再断言房间页 | 需求 5：跑团房间也先选规则。房间内部断言全部原样 |

未改动且仍绿：`p7_theme_test`（入口几何）、`p7_rule_registry_test`、`wizard_fix_jump_test`、`p8_wizard_nav_test`（直连 `CreateFlowPage()`，仍 9 步）、`card_detail_edit_test`、`qa_probe_test`。

---

## 三、新增测试 `test/p9_rule_pick_test.dart`（15 组，全绿）

**A–E 主体（12 组）**
1. 跑团房间：先 `RulePickPage` 且 `RoomEntryPage` 不存在；选 COC 才进。
2. AI 车卡：先 `RulePickPage`；选完 `ai_rule_coc7` 芯片 **findsNothing**，`ai_rule_current` 含 `COC 7th` + 规则书。
3. 一键出卡：先 `RulePickPage`；`ChoiceChip` **findsNothing**，`random_rule_current` 含 `COC 7th`。
4. 按流程车卡：进向导后 `StepRules` **findsNothing**，`step_progress == '1 / 8'`。
5. 未开放规则：`InkWell.onTap == null` + 「未开放」标签 + 真点一次页面不变；对照已开放卡 `onTap != null`。
6. 列表来源：`rule_pick_` 前缀控件数 **== `RuleRegistry.all.length`**。
7. 注入注册表外的假规则 → 渲染且可点（证明遍历渲染）。
8. AI「就用这张」：落库 1 张、卡上 `ruleSystemId == coc7`、`AiCreatePage` 已出栈、`HomePage` 为顶层。
9. AI「继续完善」：进 `CreateFlowPage`、`StepRules` 不在、`repo.all` **为空**。
10. 一键出卡「就用这张」：落库 1 张、随机页消失、回首页。
11. 一键出卡「继续完善」：进向导、仓库仍空。
12. `RuleRegistry.effectiveId` 对占位/未知/null 一律回退默认规则。

**追加（3 组）**
13. 头图等高：`wizard_header` 与 `random_header` 高度**相等且 == 120**（1200dp 宽下被 `maxHeight` 钳住，而不是 3:1 的 400px）。
14. AI 页头图：`ai_header` 高度 **== 64**，宽度 > 0，无异常。
15. 首页角色档案：`home_roster_saved` / `home_roster_valhalla` 都在、**两张都是 2:1**、等宽、竖排、文案画在图上（`1 位调查员`）、首页 `find.text('英灵殿')` **恰好一处**、点第二张也能进 `RosterPage`。

可证伪性：第 5 组（把 `onTap` 改成非 null 立红）、第 6/7 组（写死三条后 6 立红、7 立红）、第 9/11 组（「继续完善」顺手落库立红）、第 13 组（把任一页改回固定高度立红）、第 15 组（改回单列计数行立红）。

---

## 四、测试结果

```
flutter analyze                → No issues found!
flutter test（全量）           → 1678 passed / 1 failed（1m40s）
  · 唯一失败：test/p6_lan_room_host_test.dart「端口被占用时启动失败」
    → 单跑该文件 4/4 全绿，属并发跑所有用例时的端口竞争 flake，与本批无关。
受影响的 8 个文件批量跑          → 103 passed / 0 failed
  p8_home_ui_test / card_detail_edit_test / qa_probe_test / p7_theme_test
  p8_wizard_nav_test / create_flow_widget_test / ai_create_page_test / p7_ai_caps_ui_test
p9_rule_pick_test              → 15 passed / 0 failed
```

---

## 五、遗留 / 备注

1. **全量跑中的 1 条失败是端口竞争 flake**：`p6_lan_room_host_test.dart#端口被占用时启动失败`。单文件复跑全绿（4/4），且该用例只用真实 socket、不涉及本批任何文件。并发跑全套时与其他 LAN/socket 用例抢端口。建议给该用例换一个随机高位端口或串行标记。
2. **「规则写进 draft」的独立可观测性**：写的是既有路径（`newCharacter(ruleId)` / `raw['ruleSystemId']`），但当前**只有 COC 7th 一套可用规则**，写入值与默认值相同，UI 层无法把「真写了」与「默认值碰巧一样」区分。已用第 12 组守住「占位 id 一定回退」；第二套规则开放后应补一条「选 DND 5E 进向导 → 卡上 == dnd5e」。
3. **卡详情页「编辑保存」未改**：`lib/ui/card_detail_page.dart` 不在允许清单内；需求 8 只覆盖三条车卡落库路径（向导末步 / AI 就用这张 / 随机就用这张）。
4. **头图在窄手机上不是严格 3:1**：按指定的 `BannerSlot(aspectRatio: 3, maxHeight: 120, minHeight: 64)`，宽 412dp 时理论高度 137 会被钳到 120（实际比 3:1 略扁）。这是给定参数的必然结果，两页一致、且不会再随宽屏膨胀；若要求「手机严格 3:1」，把 `maxHeight` 提到 160 即可（两处同步改）。
5. **取消/返回语义**：从规则选择页 push 进目标页后，返回/取消回到规则选择页（可改选规则），只有保存成功才强制回首页。若产品要求「取消也直接回首页」，把 `RulePickPage._pick` 改为 `pushReplacement`（一行），我再同步 `create_flow_widget_test` 的取消用例。
6. **`/room` 前置只做排序不加参数**：`RoomEntryPage` 目前不接收规则 id（房间侧规则沿用房间自身的 `room_rules`）；本批只按需求把「选规则」放到房间入口之前，房间内规则绑定留待后续。
