# P17 波1-E · H-1 头图文字调整 · 施工报告

- worker：p17-w1e（Flutter 工程师「寇豆码」）
- 独占文件：`lib/ui/home_page.dart`（只改这一份）
- 目标：删「COC 7th」「克苏鲁的呼唤 第七版 · 车卡器」两段文字；版本号上移到 Header 第二行
- 依据：`_p17_construction_spec.md` §0/§1/§2-H-1/§4、`_p17_player_common_landing.md` §三 H-1 + §五 第 4 条

---

## 1. 改动前后 Header 结构对照

### 1.1 改动前（v2.29.0+99，675 行）

`_HomeHeader.build`（`:546-674`）是 `Padding(LTRB 18,18,8,10) > Column`：

| 位置 | 结构 | 行号 |
|---|---|---|
| 标题行 | `Row`：`Expanded(Text('骰境TRPG', 26/金))` → `SizedBox(10)` → `Container(1×18, borderStr)` → `SizedBox(10)` → `Text('COC 7th', 12/mute)` → `PopupMenuButton(key: home_menu)` → `SizedBox(6)` | `:553-648` |
| 第二行 | `SizedBox(height:6)` + `Text('克苏鲁的呼唤 第七版 · 车卡器', 12.5/mute)` | `:649-657` |
| 第三行 | `SizedBox(height:3)` + `Text(kAppVersionLabel, key: home_app_version, 11/mute@0.8)` | `:658-670` |

即：**标题行右侧**是「竖线 + COC 7th」，车卡器文案与版本号各占一整行在下方。

### 1.2 改动后（662 行，净 −13 行）

```dart
Column(
  children: [
    Row(                                        // :553-641
      Expanded(Text('骰境TRPG', 26/金)),          // :557-570  原样保留
      // 竖线 + SizedBox(10) + COC 7th 全部删除    // 原 :571-581
      PopupMenuButton(key: home_menu),           // :575-638  原样保留
      SizedBox(width: 6),                        // :639
    ),
    SizedBox(height: 6),                         // :642
    Text(kAppVersionLabel,                       // :649-657  从原 :662-670 上移
         key: const Key('home_app_version'),
         style: 11 / textMute@0.8 / letterSpacing 0.4),
  ],
)
```

具体删除项（逐条）：

1. `:571` `const SizedBox(width: 10)` —— 标题与竖线之间的空隙。
2. `:572` `Container(width: 1, height: 18, color: Palette.borderStr)` —— 分隔竖线。它是 `COC 7th` 的分隔装饰，文字删掉后就是一条没有任何依附对象的孤立短线，按「不留空占位」一并清掉。**删后本文件已无 `Palette.borderStr` 引用**，`Palette` 其余静态色仍在用，`dart analyze` 无 unused 提示。
3. `:573` `const SizedBox(width: 10)`。
4. `:574-581` `Text('COC 7th')` 整段。
5. `:650-657` `Text('克苏鲁的呼唤 第七版 · 车卡器')` 整段。
6. `:658` `const SizedBox(height: 3)` —— 它原本是「车卡器文案 ↔ 版本号」之间的 3dp 间隙，随上一行一起失去归属，清掉。

保留（一字未动）：

- `:557-570` `Expanded(Text('骰境TRPG', …))` 的字号/字重/字色/字距/字体族，以及 `maxLines: 1` + `TextOverflow.ellipsis`。
- `:575-638` `PopupMenuButton(key: const Key('home_menu'))` 及其三个菜单项（导出全部角色 / 导入角色 JSON / 设置）。
- `:63` 版本号 `key: const Key('home_app_version')` 与文案 `kAppVersionLabel`（真源 `lib/app_version.dart:24`）。
- `:151` `SectionBanner(title: '开始冒险')`、四张入口横幅、`_RosterEntry`，全部未碰。

### 1.3 哈希

| 阶段 | sha256 |
|---|---|
| 改动前 | `10b36f76e1c5e127d3e7a097af0ff16160106bc0e47a69fbfaf23e2d2532319a` |
| **改动后** | **`54bd7d56ee0333eca238458717ba5df88e352391e484e3378593d311e34c3da8`** |

`diff -u` 实测：只有上述 3 个 hunk（注释行 `:555`、删 `COC 7th` 段、删车卡器段 + 版本号上移），**其它区块零改动**。

### 1.4 静态分析

```
$ dart analyze lib/ui/home_page.dart
Analyzing home_page.dart...
No issues found!   (exit 0)
```

---

## 2. 版本号新位置的落点与「位置语义」理解

### 2.1 「位置语义」怎么理解

用户原话是「删掉『COC 7th』和『克苏鲁的呼唤 第七版 · 车卡器』，**版本号移到原来 COC 7th 的位置**」，并补充括号语义「`骰境TRPG` 下方、`开始冒险` 栏上方」。

但代码现状与字面口径不符（已由研究报告 §五 第 4 条确认、本人口径复核一致）：

- `COC 7th` **不在** `骰境TRPG` 下方，而是同一 `Row` 内、标题右侧（竖线之后）；
- `骰境TRPG` 下方那一块，原本是「车卡器文案（第二行）」+「版本号（第三行）」。

所以「原来 COC 7th 的位置」这句话**无法按字面同时满足**：要么放在标题右侧行内（那是字面位置），要么放在标题下方（那是括号里的语义）。

**我的判断：以括号里的语义为准，不按字面行内位置。**

理由：

1. 用户这句话的**信息主干是排序**——「骰境TRPG → 版本号 → 开始冒险」，括号是他自己给这段排序下的注脚。括号是对主句的解释，不是补充选项。
2. 「版本号移到标题右侧、和 26 号金字同一行」在视觉上等于把一行副信息塞进主标题行，正是他这次要清理掉的那种拥挤感（他删 COC 7th 的动机就是嫌头图字多）。
3. 版本号是「安装包标识」，天生属于副信息层级；放在主标题正下方（第二行）才和「主标题 → 副行」的层级一致，也正好接上原来车卡器文案腾出来的那一格。

### 2.2 最终视觉顺序（自上而下）

```
骰境TRPG                        [⋮ 菜单]
v2.29.0 (99)                     ← 版本号（Header 第二行）
────────────────────────────
开始冒险（SectionBanner）
四张入口横幅 2×2
角色档案（SectionBanner）
...
```

即：主标题行（标题 + 菜单）→ 版本号副行 → 开始冒险栏。用户要的「骰境TRPG 下方、开始冒险 栏上方」被完整满足；「原 COC 7th 的位置」按语义（副信息位）落地。

### 2.3 为什么没有把版本号塞回标题 `Row`

技术上可以（`Row` 里加个 `Text` 即可），但那样在 320dp + textScaler 2.0 下标题可用宽度会被再吃掉约 150dp，标题会从「骰境TR…」缩到「骰…」，且与「头图去拥挤」的用户意图相反。故采用独立第二行。

---

## 3. 窄屏 320dp × textScaler 1.0/1.3/1.5/2.0 溢出结论（静态推演）

> ⚠️ 本轮纪律禁止 `flutter test`，以下为**静态推演**，非实测；已把每条结论的依据写到可复核的程度。

### 3.1 依据（约束链）

- `HomePage` → `SafeArea` → `ContentFrame`（`Center` + `ConstrainedBox(maxWidth: 760)`，`lib/ui/responsive.dart`，**无额外内边距**）→ `CustomScrollView` → `SliverToBoxAdapter(_HomeHeader)`。
- `_HomeHeader` 外层 `Padding(LTRB 18,18,8,10)` → 320dp 下可用行宽 = 320 − 18 − 8 = **294dp**。
- 标题行 `Row` 的固定宽子项：`PopupMenuButton`（M3 `IconButton`，20 号图标 + 8 padding，视觉宽 ≤ 48dp；点击区 48dp）+ 尾部 `SizedBox(width: 6)`。
- ⇒ `Expanded` 标题的**最坏可用宽** = 294 − 48 − 6 ≈ **240dp**。
- 纵向：`SliverToBoxAdapter` 给子树的纵向约束是**无界**，`Column` 高度完全由子项固有高度累加，`Row` 高度 = `max(标题行高, 菜单 48)`。**结构上不存在纵向溢出/定高裁切**，也就不存在「删行后留下固定高度空块」——高度是算出来的，不是钉死的。

### 3.2 逐档推演

标题 `骰境TRPG`：2 个 CJK（推进宽 ≈ 1.0em）+ 4 个大写拉丁（≈ 0.6~0.72em），字号 26，`letterSpacing: 3`（按 Flutter 口径字距不随 `TextScaler` 缩放，即便按同步缩放算结论也不变）。

| textScaler | 标题估算宽 | 最坏可用宽 240dp | 结论 |
|---|---|---|---|
| 1.0 | ≈ 141dp（4.72em×26 + 18） | 240 | 完整显示，余量 ~99dp |
| 1.3 | ≈ 178dp | 240 | 完整显示，余量 ~62dp |
| 1.5 | ≈ 202dp | 240 | 完整显示，余量 ~38dp |
| 2.0 | ≈ 264dp（> 240） | 240 | **触发 `maxLines:1` + `ellipsis`**，显示「骰境TR…」，**不溢出**（`Text` 自己省略，`Row` 拿到的是 ≤240 的宽） |

版本号 `v2.29.0 (99)`（11 号，12 个字符，拉丁/数字 ≈ 0.55em + 标点 + `letterSpacing 0.4`）：

| textScaler | 估算宽 | 可用宽 294dp | 结论 |
|---|---|---|---|
| 1.0 | ≈ 78dp | 294 | 单行 |
| 1.3 | ≈ 100dp | 294 | 单行 |
| 1.5 | ≈ 115dp | 294 | 单行 |
| 2.0 | ≈ 151dp | 294 | 单行（未触发换行，更不会溢出） |

### 3.3 结论与「为什么没有加 textScaler 钳制」

- 2.0 档唯一的宽度压力在标题上，而标题**本来就有** `Expanded` + `maxLines:1` + `ellipsis` 三重保护（`:557-562`，P8 为窄屏 50px 溢出加的），省略即不溢出。
- 版本号是**不定宽不定高**的 `Text`，纵向由无界滚动承接、横向 294dp 余量充足，不属于「固定尺寸控件」。
- 按施工单 §0.7「固定尺寸控件必须过 textScaler，钳制只能钳该控件子树、不许抬到页面/Theme 层」：本 Header **不存在固定尺寸控件**（无定高 `SizedBox` 包文字、无固定尺寸卡片、图标是 `Icon` 的固定 20 不随 `textScaler` 变），因此**不需要也不应该**引入 `MediaQuery.withClampedTextScaling`。强行钳 1.0 反而会把用户的系统字号偏好压掉，属过度修改。

### 3.4 关于「高度塌陷 / 大块留白」

删两行后 Header 自身高度从（1.0 档）约 103dp 降到约 83dp，**减少的正是被删两行的高度，不是被钉住的空白**：

- `Column` 里除两处间距（`SizedBox(height:6)`）外没有任何定高容器；
- 被删的 `SizedBox(height:3)` 是「车卡器文案 ↔ 版本号」的行间空隙，随上一行一起删除；
- 因此视觉上是「头图变紧凑」，不会出现空槽，也不会把下方「开始冒险」栏拉开距离（`_AdventureSection` 紧跟 `SliverToBoxAdapter` 之后，靠自身内边距定位）。

### 3.5 菜单按钮不会被挤掉（硬约束核对）

`Row` 的子项顺序是 `[Expanded(标题), PopupMenuButton, SizedBox(6)]`。`Expanded`（`flex: 1`）只在**剩余空间**里分配，最小可被压到 0；固定宽度的菜单按钮永远排在其后、永远拿到自己的 48dp。因此无论 320dp 还是 textScaler 2.0，`home_menu` 都不可能被标题挤出可视区。

---

## 4. 预计转红的既有测试

### 4.1 复核方法与结论：**预计零转红**

对 `test/` 全量 grep 关键词：

```
grep -rn "COC 7th"            test/   → 27 处 / 4 个文件：p7_share_badge_test.dart 22、p7_ai_caps_ui_test.dart 2、
                                       p7_rule_registry_test.dart 2（全是 RuleRegistry.shortName / share badge 数据断言）、
                                       oracle_rules_test.dart 1（文件头注释）—— **无一处在首页 Header 语境**
grep -rn "车卡器"              test/   → 1 处：test/p11_status_bar_test.dart:12，是注释
grep -rn "克苏鲁的呼唤"         test/   → 6 处：create_flow_widget_test.dart:91 断言的是 '克苏鲁的呼唤 第七版'
                                       （规则选择页 step_rules.dart，无「· 车卡器」后缀，是**另一个字符串**）；
                                       p7_rule_registry_test / p7_ai_caps_ui_test 是 RuleRegistry.name；p11_overlay_test 是注释
grep -rn "home_app_version"   test/   → 仅 test/app_version_test.dart:51
grep -rn "matchesGoldenFile"  test/   → 零命中（无 golden 测试，不存在截图对拍转红）
```

### 4.2 逐个确认（关键 6 条）

| 测试 | 依赖点 | 改动影响 | 结果 |
|---|---|---|---|
| `test/app_version_test.dart:47-57` | `find.byKey(Key('home_app_version'))` + `t.data == kAppVersionLabel` + `contains(kAppVersion)` | key 与文案**一字未动**，只换了 Column 里的位置；该测试**不断言位置/几何** | **仍绿** |
| `test/create_flow_widget_test.dart:77 / 273` | `find.text('骰境TRPG')` `findsOneWidget` | 标题原样保留，且全工程 `'骰境TRPG'` 在该页仍只有一处 | 仍绿 |
| `test/create_flow_widget_test.dart:91` | `find.text('克苏鲁的呼唤 第七版')` | 断言的是规则选择页文案（无「· 车卡器」），与首页被删串不同 | 仍绿 |
| `test/p8_home_ui_test.dart:72 / 151-173` | 两个 `SectionBanner` 左右边界相等、`home_menu` 点击、`开始冒险` 取色 | Header 变化不影响 `_AdventureSection`/`_RosterEntry` 的内边距与 `SectionBanner` 宽度 | 仍绿 |
| `test/p12_banner_inset_test.dart:29 / 66` | `SectionBanner.titleInsetFor` 与 `开始冒险` 渲染位置 | 该测试自建 `MaterialApp` 单测 `SectionBanner`，不 pump 首页 | 仍绿 |
| `test/settings_page_test.dart:22 / 266`、`test/card_detail_edit_test.dart:219 / 269`、`test/p7_theme_test.dart:150 / 188`、`test/p12_emoji_a_test.dart:58 / 160` | `tapKey('home_menu')` / `find.text('骰境TRPG')` | 菜单 key 与标题均保留；菜单按钮 x 位置右移约 60~70dp，但测试用 key 查找、非坐标点击 | 仍绿 |

### 4.3 若真出现转红，建议口径（备用，本轮无需启用）

- 若是某测试断言了首页**不再存在**的文字（`find.text('COC 7th')` 或 `find.text('克苏鲁的呼唤 第七版 · 车卡器')`）→ 属**产品行为真变了**，应把该断言改成**正向断言**：`expect(find.text('COC 7th'), findsNothing)` + 新增 `expect(find.byKey(Key('home_app_version')), findsOneWidget)`，比原断言更强（同时钉住「删了」和「版本号还在」），不得直接删用例。
- 若是几何断言（某测试依赖 Header 高度推算 y 坐标）→ 建议改用 `find.byKey` + `tester.getRect` 相对定位，不要写死绝对坐标。
- **本轮我自己没有改任何测试，也没有新建测试。**

---

## 5. 声明

- ✅ 只改 `lib/ui/home_page.dart` 一个文件；未碰 `lib/app_version.dart`（只读）、`pubspec.yaml`、`pubspec.lock`、任何 `test/**`、任何他人独占文件。
- ✅ **未执行 `flutter test`**（本轮纪律）；校验手段只有 `dart analyze lib/ui/home_page.dart`（零问题）与 `diff -u` 对拍（只有 3 个预期 hunk）。
- ✅ **未改既有测试、未新建测试**。
- ✅ 注释全部中文；首页其它区块（开始冒险四宫格 / 角色档案入口）零改动。
- ✅ 保留 `home_app_version` key、`kAppVersionLabel` 文案、`home_menu` 菜单、`开始冒险` 栏、`骰境TRPG` 标题。
- ⚠️ 需真机/实机确认项（建议 QA 登记）：320dp 极窄屏 + 系统字号 2.0 时标题呈「骰境TR…」是否符合预期；亮/暗主题下 11 号 `textMute@0.8` 版本号紧跟 26 号金字是否观感可接受。
