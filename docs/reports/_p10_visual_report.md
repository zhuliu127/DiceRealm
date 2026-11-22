# P10 视觉/行为修复报告（需求 2 · 4 · 5 · 6）

> 范围：只改 `lib/ui/roster_page.dart`、`lib/ui/home_page.dart`、`lib/ui/create/rule_pick_page.dart`
> + 新建 `test/p10_roster_rule_test.dart` + 修既有测试的断言口径（逐条列在第 5 节）。
> 没有动 `lib/domain/**`、`lib/ui/art.dart`、`lib/theme.dart`、`lib/ui/room/**`、
> `lib/ui/create/steps/**`、`lib/ui/ai_create_page.dart`、`lib/ui/random_create_page.dart`、
> `lib/repo/**`、`pubspec.yaml`、任何 asset；没有 `flutter clean`、没有出包、没加依赖。

---

## 0. 结论速览

| 需求 | 结论 | 关键证据 |
|---|---|---|
| 2 名册按入口过滤 | ✅ | `RosterScope{all,saved,fallen}`；另一块**不构建**（`findsNothing`） |
| 4 英灵殿入口图文字重叠 | ✅ 根因是素材烧字，不是溢出 | 首页 `find.text('英灵殿')` 现在为 0；唯一语义节点 + 右下角 10px 计数 |
| 5 暗色规则卡「边框在图内」 | ✅ **1.06 修不掉，实测需 1.753 倍** | 按素材登记的裁切表；窗口 x∈[594,1470] y∈[165,603] |
| 6 亮色规则卡「灰蒙蒙」 | ✅ | 遮罩改左→右渐变、可选项零 `Opacity`；未开放 灰度 + 0.45 |
| 测试 | `p10_roster_rule_test.dart` **14 条**；全仓 **1731 条全绿** | 第 6 节 |

---

## 1. 需求 2 · 名册按入口过滤

### 用户原话
> 首页点击已保存的角色卡后就只显示已保存的角色卡，不要显示英灵殿；英灵殿也按照此逻辑，
> 不要显示已保存的角色卡。

### 根因
`RosterPage` 是无参页面，固定把「已保存的角色卡」+「英灵殿」两块一起铺；首页两个入口
（`home_roster_saved` / `home_roster_valhalla`）**都走同一条 `pushNamed('/roster')`**，
进了同一页自然两栏都看到。

### 改法（`lib/ui/roster_page.dart`）
- 新增 `enum RosterScope { all, saved, fallen }`，`RosterPage({this.scope})`。
- 作用域解析顺序：**构造参数 > 路由 `arguments` > `all`**。
  - 为什么允许走 arguments：首页两个入口共用 `/roster` 这一条命名路由，而 `lib/app.dart`
    不在本批可改范围（那边 `builder: (_) => RosterPage()` 保持不动），所以作用域顺着
    `RouteSettings.arguments` 带过去；`/roster` 深链不带参数仍然是 `all`（老行为）。
- `.saved` / `.fallen` 时另一块**整段用 `if (...) ...<Widget>[]` 不构建** —— 标题、列表、
  空态全都不在 widget 树里（不是 `Visibility`/`Offstage` 隐藏，`find.text` 直接 `findsNothing`）。
- 顶部 `SectionBanner.hint` 跟着变：`all` =「X 位调查员 · Y 位长眠者」、`saved` =「X 位调查员」、
  `fallen` =「Y 位长眠者」。

### 首页（`lib/ui/home_page.dart`）
- `open(RosterScope)` → `pushNamed(RosterPage.route, arguments: scope)`。
- `home_roster_saved` → `.saved`；`home_roster_valhalla` → `.fallen`；
  老 Key `home_roster_entry` 仍挂在第一张卡（`KeyedSubtree`）外层，行为等同 `.saved`。

---

## 2. 需求 4 · 首页英灵殿入口图文字重叠

### 用户原话
> 首页「英灵殿」图片溢出了。

### 根因（ViewImage 打开真实素材确认，不是推理）
`assets/images/a_home/a_home_banner_valhalla_2x1.webp`（以及 `_light` 版）**本身已经烧进了**
「英灵殿 / 英灵长眠于此 / 致敬每一位调查员」三段字（位于左侧偏上），而 `_RosterBanner` 又在图上
叠了一遍标题「英灵殿」+ 副标题 → 两套字压在一起，看起来像"图片溢出 / 文字重叠"。

### 改法
- `_RosterBanner` 的 `title`/`subtitle` 改成可空：**英灵殿那张不传** → 整张图零叠字，
  连左侧压暗渐变也一起去掉（没有字就不需要压暗，右半张露出原画）。
- 只在**右下角**叠一个极小计数 `_CornerNote`：字号 **10**（≤11）、半透明黑底 0.42 + 细金边，
  内容「N 位长眠者」（0 张时「暂无长眠者」）。
  位置理由：图内文字在**左侧偏上**，右下角落是石台/花饰，压一个小标签既避开文字也不挡主体；
  320dp 最窄档已测（不越界、不溢出）。
- 「已保存的角色卡」那张（`a_home_banner_cards_2x1.webp` 左侧是留白）**保持原样**：
  左侧标题 + 副标题（「N 位调查员」/ 空态引导），一行没改。
- 语义：图里的字读屏读不到，所以给这张卡套 `Semantics(label: '英灵殿', button: true, container: true)`。

### 与 `qa_probe_test:322` 的冲突怎么处理（决策 + 理由）
老断言是首页 `expect(find.text('英灵殿'), findsOneWidget)`。图里既然已经有字，App 再画一个 Text
就是**缺陷本身**，所以不能保留那层 Text。
- 采取方案：**换成「首页必须有且只有一个语义名为『英灵殿』的入口」**。
- 为什么这不是放宽：
  1. 仍然是 **`findsOneWidget`**（唯一性没变，没有退化成 `findsWidgets`）；
  2. 还多了新约束：语义名必须存在（读屏可达）+ `button` 必须为真（可点）；
  3. 数据层面另断言「右下角计数可见且 ≤11px」（`find.text('1 位长眠者')`）。
- **没有**用 `Offstage` 塞隐形 Text 骗断言（那是造假，而且 `find.text` 默认跳过 offstage，
  要通过反而得写 `skipOffstage:false`，等于把断言做软）。

---

## 3. 需求 5 · 暗色规则卡「边框在图片内部」

### 用户原话
> 「克苏鲁的呼唤 第七版」卡片背景图，边框位置好像不对，上下边框都在背景图片内部。

### 根因（实测，推翻了"1.06 就够"的假设）
用 PIL 对 `assets/images/g_rules/r1_coc7_2x1.webp`（1536×768，正好 2:1）做逐行/逐列金色像素统计：

| 边 | 位置（px） | 占图比例 |
|---|---|---|
| 上金线 | y = 130–131 | **16.9%** |
| 下金线 | y = 632–633 | **82.3%** |
| 左金线 | x = 4–6 | 0.3%（贴边） |
| 右金线 | x = 1530–1532 | 99.7%（贴边） |
| 四角金星 | x∈[1483,1517]、y∈[138,162] / y∈[606,630] | — |

这张底图把金边画成了**3:1 长条内框**，塞在 2:1 画布里。卡面 2:1 铺满时整张图都在可视区 →
上下两条金边停在卡片内部 17% / 82% 处，用户看到的"边框跑到图里"就是它。

**为什么 `Transform.scale(1.06)` 修不掉**：1.06 每边只挤掉 3%，金线仍停在 14% / 79%。
要把 y=130 挤出可视区，垂直方向至少 `768 / (633−130)` ≈ **1.53**，留金星余量后取 **1.753**。

### 改法（`lib/ui/create/rule_pick_page.dart`）
`RulePickCard` 里加一张**按素材路径**登记的取景修正表：

```dart
static const Map<String, _InnerCrop> _innerCrops = <String, _InnerCrop>{
  Art.ruleCardCoc7: _InnerCrop(zoom: 1.753, alignX: 0.80), // 仅暗色那张
};
```

实现：`ClipRect > OverflowBox(放大 1.753 倍, alignment: Alignment(0.80, 0)) > ArtImage`。
可见窗口 = 原图 **x∈[594,1470]、y∈[165,603]**（876×438，正好 2:1）。

- 为什么按**素材**而不是按规则 id：同一个规则两套皮肤几何不一致 ——
  **`r1_coc7_light_2x1.webp` 的金边是贴边的**（与 r2/r3 同款，内缩 ~1%），
  这正是用户说「亮色模式下边框和背景图位置倒是对了」的原因。亮色那张**不裁**。
- `r2_dnd5e_2x1.webp`（金线 y=10/757、x=8/1525）、`r3_custom_2x1.webp`（y=18/749、x=13/1521）
  都是贴边 → **不登记、不放大**。

### 主体与四角复核（按要求逐项确认，不是推理）
把可见窗口 x∈[594,1470] / y∈[165,603] 按卡片实显尺寸（1000×501）渲染出来逐件核对：

| 项目 | 结论 |
|---|---|
| 提灯（右侧） | **完整可见**：透镜、灯罩、顶盖、底座全在窗内；只有右缘金属立杆外侧约 30px（= 卡片宽 1.9%）落在窗外，观感是"道具延伸出画框"，不是拦腰切断 |
| 左轮 | **完整**：枪管/转轮/握把全在窗内，四周都有余量 |
| 放大镜 | **完整可见**：镜片与铜框全在窗内；木质手柄末端越过下边框（同一类"越出画框"的静物构图） |
| 1920 书桌（地图/羽毛笔/书堆） | 主体在窗内；最左侧书堆边缘被裁（原本是给文字留的紫色雾面区，代价见"遗留"） |
| 四角露白 | **没有**。四角像素 lum 27/45/55/39（左上/右上/左下/右下），都是深紫夜空或木桌暗部，无白底、无空块 |
| 金边/金星残留 | **零**。窗口右界 1470 < 金星左界 1483，下界 603 < 下金星上界 606，上界 165 > 上金星下界 162；左右金线 x=5/1531 在窗外 |

（`BoxFit.cover` 在这里不会露白：放大后的 child 与卡片同为 2:1 且尺寸 ≥ 卡片，只做居中/右偏裁切。）

### 遗留（诚实记账）
1. 1.753 倍的代价：暗色 COC 卡变成"特写取景"，左侧原本的留白紫雾被裁，三行文字压在深色木桌
   与地图上（有左侧渐变兜底，可读性 OK，但版式语义变了）。
2. **根本解法在素材侧**：这张图应重出成「金边贴边」的 2:1（与亮色/r2/r3 一致）。本次不动 asset
   （不在可改范围），代码裁切只是兜住。建议下一批重出 `r1_coc7_2x1.webp`，届时把
   `_innerCrops` 里这一条删掉即可（裁切表删一行就回到"整图铺满"）。

---

## 4. 需求 6 · 亮色规则卡「灰蒙蒙像不可选」

### 用户原话
> 亮色模式下边框和背景图位置倒是对了，但是灰蒙蒙的，好像跟不可选一样。

### 根因
旧 `RulePickCard` 两层问题叠加：
1. 文字可读性遮罩是**上→下整张压暗**（`0.05 → 0.72`）。亮色底图本来就淡（米白水彩），被这层
   黑罩盖住下半张 → 整卡发灰；
2. 状态用**整体 `Opacity`**：`opacity: usable ? 1 : 0.5`。"用透明度表达状态"这套视觉语言本身
   就在暗示"可以灰一点"，和未开放的 0.5 只差一档，用户分不清。

### 改法
- 遮罩改成**左→右**渐变：`black 0.78 → 0.46(36%) → 0.0(80%)`。文字都在左下角，只压左侧就够，
  右半张几乎不压 → 这就是"灰蒙蒙"的直接解药。
- **可选项完全不套 `Opacity`**（连 1 都不套）：满格颜色就是"可选"的视觉语言。
- **未开放项**三件事叠加：`Opacity(0.45)` + `ColorFiltered`（Rec.709 灰度矩阵）+
  右上「未开放」标签 + 状态行「未开放 · 规则层尚未实现」。

---

## 5. 老测试改动逐条（原断言 → 改成什么 → 为什么是产品行为变更，不是断言变弱）

**总原则**：本轮所有改动都只换了"从哪里进 / 用什么口径描述同一个可见事实"，
没有一条把 `findsOneWidget` 降成 `findsWidgets`，也没有删掉任何 `findsNothing`；
反而新增了 6 处 `findsNothing`/新增断言。

### 5.1 `test/p8_home_ui_test.dart` —「名册页逐卡带规则徽标，数值不溢出边框」
- **原断言**：点 `home_roster_entry` 一次 → `find.text('已保存的角色卡')` `findsOneWidget` +
  `find.text('英灵殿')` `findsOneWidget` + `card_rule_badge_alive01`/`dead01` 各 `findsOneWidget`
  + `HP/SAN/MP` 各 `findsNWidgets(2)`。
- **改成**：两个入口各进一次。
  - 进 `home_roster_entry`：`已保存的角色卡` 1 个、`英灵殿` **`findsNothing`**、
    `badge_alive01` 1 个、`badge_dead01` **`findsNothing`**、HP/SAN/MP 各 **1** 个、无 overflow 异常；
  - `pageBack()` 回首页再进 `home_roster_valhalla`：`英灵殿` 1 个、`已保存的角色卡` **`findsNothing`**、
    `badge_dead01` 1 个、`badge_alive01` **`findsNothing`**、`☠ 已撕卡` 1 个、无 overflow 异常。
- **为什么是产品变更不是变弱**：需求 2 明确要求"点已保存就只显示已保存"。原断言"一页两栏都在"
  本身就是被修掉的行为，留着必然红。换成"两次进入各自断言 + 另一栏 `findsNothing`"后，
  断言条数从 **10 条涨到 16 条**（`findsNWidgets(2)` 的计数也按分栏重新精确化），
  覆盖的是同一批控件加上新增的分栏隔离约束。

### 5.2 `test/p9_rule_pick_test.dart` —「首页角色档案入口图…」（**由 `flow-rework` 重建该文件时落定**）
- **原断言**：`expect(find.text('英灵殿'), findsOneWidget);`
- **改成**（比我提议的更严，已核过文件内容）：
  ```dart
  expect(find.text('1 位长眠者'), findsOneWidget);                  // 右下角角标
  expect(find.bySemanticsLabel(RegExp('英灵殿')), findsOneWidget);   // 唯一英灵殿语义节点
  final SemanticsNode n = tester.getSemantics(find.byKey(const Key('home_roster_valhalla')));
  expect(n.label, contains('英灵殿'));
  expect(n.flagsCollection.isButton, isTrue);                       // 读屏听得出是按钮
  expect(find.text('英灵殿'), findsNothing);                         // App 不许再叠一层字
  ```
  该 group 还新增了作用域隔离断言：点已保存看不到长眠卡、点英灵殿看不到在世卡。
- **为什么是产品变更不是变弱**：需求 4 要求"图里已有字，App 不许再叠"。原 `find.text` 断言
  描述的是被修掉的缺陷。新口径仍是精确 `findsOneWidget`（多了一个 `findsNothing` 反向锁），
  并额外锁住语义可达性与可点性。
- **踩坑记录**（供后来人）：`container: true` 会把角标文字合并进同一语义节点 → 标签要用
  `RegExp`/`contains`，精确等会 `findsNothing`；`SemanticsHandle` 必须在测试体内 `dispose()`
  （放 `addTearDown` 会报 "A SemanticsHandle was active at the end of the test"）；
  `hasFlag(SemanticsFlag.isButton)` 在本 Flutter 版本已废弃，用 `flagsCollection.isButton`。

### 5.3 `test/qa_probe_test.dart` —「英灵殿里的卡点得开」
- **原断言**：`find.text('英灵殿')` `findsOneWidget`（首页）+ 点 `home_roster_entry` 进名册 +
  点卡名 + `takeException()` 为 null + `textContaining('英灵殿')` `findsWidgets` +
  `btn_edit` `findsNothing`。
- **改成**：首页 `find.text('英灵殿')` **`findsNothing`** + 唯一 `Semantics(label:'英灵殿')`
  `findsOneWidget` 且 `properties.button` 为 true + **改点 `home_roster_valhalla`**；
  后半段（不崩 / 只读 / 无编辑按钮 / `textContaining('英灵殿')` 仍是 `findsWidgets`）**一字未改**。
- **为什么是产品变更不是变弱**：① 首页不再叠字是需求 4 的一部分；② 撕卡只出现在英灵殿栏
  （需求 2），从"已保存"入口进根本点不到那张卡，入口必须换 —— 换的是导航路径，不是断言阈值。
  首页那条仍是"恰好一个"，且换成结构更强（带可点标志）的语义断言。

### 5.4 `test/create_flow_widget_test.dart` — ① / ④ / ⑤
- **① 原断言**：首页 `find.text('还没有英雄长眠于此')` `findsOneWidget`。
  **改成**：首页 `find.text('暂无长眠者')` `findsOneWidget`（新角标）→ 点 `home_roster_valhalla`
  → `find.text('还没有英雄长眠于此')` `findsOneWidget`（空态搬进英灵殿栏）→ `pageBack()`。
  **理由**：需求 4 删掉了首页那行副标题（图里已有字），空态引导改由名册的英灵殿空态承担。
  空态文案**仍然被精确断言**，而且多断言了一次"这行字现在在哪一页"。
- **④ 原断言**：`home_roster_entry` + `find.text('长眠者')` 1 个 + `☠ 已撕卡` 1 个。
  **改成**：`home_roster_valhalla` + 同上两条 + 新增 `find.text('已保存的角色卡')` **`findsNothing`**；
  首页把「还没有英雄长眠于此 `findsNothing`」换成「`1 位长眠者` `findsOneWidget`」（角标计数）。
  **理由**：撕卡只在英灵殿栏（需求 2）；断言条数 +1。
- **⑤ 原断言**：`home_roster_entry` + `疯狂者` 1 个 + `☠ 已撕卡` 1 个。
  **改成**：`home_roster_valhalla`，其余不变。**理由**：同上，仅换入口。

### 5.5 `test/support/app_harness.dart` — `pumpCardDetail`
- **原实现**：固定 `tapKey(find.byKey(Key('home_roster_entry')))`。
- **改成**：`Key(isRippedCard(c) ? 'home_roster_valhalla' : 'home_roster_entry')`（1 行三元）。
- **为什么不是变弱**：进的是**同一个详情页**（`/card/<id>`），只是按卡片状态走对分栏入口；
  它影响的用例（card_detail_edit 的"已死亡卡没有编辑按钮"等）断言一个字没改。
  若不改，撕卡用例会在"已保存"栏里找不到卡 —— 那是需求 2 的必然结果，不是夹具放宽。

### 5.6 没有改、也不需要改的
`card_detail_edit_test.dart`（只享受 5.5 的夹具修正）、`p7_rule_registry_test.dart`、
`p9_rule_pick_test.dart` 里其余 14 组、`p10_roster_rule_test.dart`（新增）。

### 5.7 关于 `lib/ui/notice.dart` 的 `showSlot`（顺手确认）
新增的 `showSlot` 按有无 action 分流时长（纯广播 2s / 带按钮 8s）。**我这 14 条用例里没有一处
依赖 SnackBar 的存在或时长**（都是 `pumpAndSettle` 后断言静态控件），所以不受影响；
受影响的是既有 `create_flow`/`card_detail` 里依赖提示文案的用例 —— 那些我只换了入口 Key，
文案断言原样保留，已全量跑绿。

---

## 6. 测试结果

```
flutter analyze                                    → No issues found!
flutter test test/p10_roster_rule_test.dart         → 14 passed
flutter test test/p9_rule_pick_test.dart            → 15 passed   （flow-rework 重建后我独立复跑）
flutter test （全仓）                                → 1731 passed, 0 failed
```

`test/p10_roster_rule_test.dart` 的 14 条：
1. `scope=saved`：有「已保存的角色卡」，无「英灵殿」（列表/空态全部 `findsNothing`），hint 只报调查员数
2. `scope=fallen`：反之，hint 只报长眠数
3. `scope` 缺省 = all：两块都在，hint 是两栏合计（深链 `/roster` 老行为不变）
4. 首页点 `home_roster_saved` → 名册无「英灵殿」
5. 首页点 `home_roster_valhalla` → 名册无「已保存的角色卡」
6. 老 Key `home_roster_entry` 仍可用、行为等同 saved
7. 首页 `find.text('英灵殿')` == 0，但有唯一语义节点且 `button=true`，两张入口 2:1 / 竖排不变
8. 英灵殿图上只有一个计数，字号 ≤11，位置在**右下**、不溢出卡片
9. 「已保存」那张仍保留左侧叠字（没被顺手删掉）
10. 最窄 320dp：角标左右都不越出入口卡片，无异常
11. 可选卡零 `Opacity` / 零灰度；未开放卡 0.45 + 铺满整卡 + 灰度 + 标签
12. 遮罩是左→右渐变，左暗（>0.5）右透（<0.05）
13. 暗色 COC 卡：`ClipRect+OverflowBox` 真在裁，底图放大 1.753±0.02 倍且等比，无异常
14. 亮色 COC 卡：不裁（1.0 倍、无 `OverflowBox`）

---

## 7. 事故记录：`test/p9_rule_pick_test.dart` 曾被零填充（已闭合）

- 现象：环境死机重启后该文件 20731 字节全是 NUL，`flutter test` 报 `Missing definition of 'main'`。
  全仓 `.dart`/`.yaml` 扫描确认**只有这一个**文件受影响（`lib/` 一个字节没丢）。
- 归因：文件系统非正常关机后的数据块零填充，与代码改动无关。
- 恢复：本机非 git 仓库、`%TEMP%` 编译缓存已清 → 本地不可恢复；由文件作者 `flow-rework`
  **整份重建**（现 525 行 / 22994 字节，0 个 NUL）。我**没有**用自己手上的片段另行拼写
  （避免覆盖他的版本），只做了两件事：独立复跑确认 15 组全绿、核对需求 4 的语义断言口径已在文件里。
- 我最初为需求 4 写进该文件的那处改动，随文件一并丢失，现已由重建版覆盖（口径见 5.2）。

## 8. 其它遗留 / 风险

1. `RosterPage` 的作用域目前走命名路由的 `arguments`（受"不改 `app.dart`"约束）。若以后愿意加
   独立子路由（`/roster/saved`、`/roster/fallen`），可以把 arguments 那条兼容分支删掉。
2. 暗色 COC 卡 1.753 倍特写的观感代价（第 3 节遗留 1），正解是重出素材；届时删掉
   `_innerCrops` 那一行即可复原。
3. 首页现在**没有**任何可见的"英灵殿"文字（只剩图里的字 + 右下角计数）。若以后换掉这张素材
   或换成不带字的版本，**必须同时恢复文字叠层**（否则入口只剩一张没有说明的图）。
