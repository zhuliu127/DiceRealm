# P17 波1-D 施工报告 · C-2 舞台单位名字可读性 + C-4 无素材白板

- 施工人：寇豆码（Flutter）
- 批次：v2.30.0 波1-D（`gp_map_stage.dart` + `painter/stroke_painter.dart`，**同一人同批**，因取色强耦合）
- 工程根：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
- 结论：两项已落地；`dart analyze` 两文件 **No issues found**；未跑 `flutter test`；未改既有测试；未新增测试。

---

## 0. 一句话结论

无公开素材时舞台两处底色（外层收边 + 内层画布）都变成**硬白 `Colors.white`**（亮暗主题都白、alpha 恒 1），白板上所有文字改用深色；同批把 `MarksPainter` 的写死标签色换成「按画布类型取的对比色 + 反调描边」，因此**有素材（底图明暗不可控）与无素材（白板）两种画布、亮暗两种主题，四种组合都可读**。

---

## 1. 逐项落点（行号 + 片段）

> 行号均以**改后**文件为准。

### 1.1 `lib/ui/room/widgets/gp_map_stage.dart`（C-4 主体 + C-2 取色决策）

**① 常量与纯函数（新增，:134-171）**

```dart
// :134-143  说明块（为什么必须按画布类型取色、为什么白板不能用 withValues(alpha:)）
// :145-146
/// 白板（无公开素材）底色：硬白，亮暗主题一致。
const Color stageBoardColor = Colors.white;
// :148-149
/// 白板上的主提示文字色（对白对比度 15.9:1）。
const Color stageBoardInk = Color(0xff222222);
// :151-152
/// 白板上的次要文字色（计数/注意提示，对白对比度 6.7:1，过 AA）。
const Color stageBoardInkSoft = Color(0xff5c5c5c);
// :154-159  外层收边色
Color stageBackdropColor(Map<String, Object?>? cover, ColorScheme scheme) =>
    cover == null ? stageBoardColor : scheme.surfaceContainerHighest;
// :161-167  内层画布色
Color stageCanvasColor(Map<String, Object?>? cover, ColorScheme scheme) =>
    cover == null ? stageBoardColor : Colors.transparent;
// :169-171  辅助文字色（null = 不覆盖主题默认）
Color? stageInkColor(Map<String, Object?>? cover, {bool soft = false}) =>
    cover == null ? (soft ? stageBoardInkSoft : stageBoardInk) : null;
```

判空口径与既有底图判空**同一处**：`:302-303` `final cover = assets.isEmpty ? null : assets.last;`（`publicAssets(state)`，`:299`）。不新增第二套判据。

**② 外层铺满格子的 `ColoredBox`（:311-313）**

```dart
return ColoredBox(
  // ★ P17 C-4：无公开素材（cover == null）→ 硬白板，否则保持主题底色。
  color: stageBackdropColor(cover, theme.colorScheme),
```

改前：`color: theme.colorScheme.surfaceContainerHighest,`（原 :269）。

**③ 内层画布 `Container`（:345-347）**

```dart
color: stageCanvasColor(cover, theme.colorScheme),
```

改前：`color: cover == null ? theme.colorScheme.surfaceContainerHighest : Colors.transparent,`（原 :301-303）。**有素材分支仍是 `Colors.transparent`（P10 第 7 期真 bug 的修法原样保留）**。

**④ 标点标签取色注入（:356-362）**

```dart
// ★ P17 C-2：标签色按**画布类型**取，不跟主题
//   （白板 + 暗色主题用 onSurface 会白底白字）。
foregroundPainter: MarksPainter(
  marks,
  labelColor: stageMarkLabelColor(cover != null),
  labelHalo: stageMarkLabelHalo(cover != null),
),
```

**⑤ 空态文字（:365-379）**

```dart
if (assets.isEmpty && strokes.isEmpty && marks.isEmpty)   // 三空判据原样保留
  Center(child: Text(
    widget.readOnly ? '暂无可查看的素材' : '暂无公开素材 · 点左栏「上传素材」',
    key: GpMapStageKeys.empty,
    textAlign: TextAlign.center,
    style: (theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12))
        .copyWith(color: stageBoardInk),
  )),
```

该分支必然 `assets.isEmpty`（白板）→ 无条件深色。三空判据未改，所以「有笔迹/标点但无素材」仍不画空态文字（`_p17_player_common_landing.md:395` 第 7 条要求）。

**⑥ 「点击落点…」提示（:380-390）**：白板深色，有素材时 `style: null`（保持主题默认渲染，与改前一致）。

**⑦ KP 素材计数（:434-447）**：`theme.textTheme.bodySmall?.copyWith(color: inkSoft) ?? TextStyle(color: inkSoft)`。`inkSoft == null`（有素材）时 `copyWith(color: null)` 保留原色 → **有素材时渲染逐字不变**。

### 1.2 `lib/ui/room/painter/stroke_painter.dart`（C-2 标签绘制）

**① 取色纯函数（新增，:80-103）**

```dart
// :80-95 说明块
Color stageMarkLabelColor(bool hasCover) =>
    hasCover ? const Color(0xfff5f5f5) : const Color(0xff222222);   // :98-99
Color stageMarkLabelHalo(bool hasCover) =>
    hasCover ? const Color(0xcc000000) : const Color(0xccffffff);   // :102-103
```

**② `MarksPainter` 构造契约（:109-122）**——位置参数不动，只加两个**可选具名**参数：

```dart
const MarksPainter(
  this.marks, {
  this.labelColor = const Color(0xff222222),   // 默认值与改前写死值一致
  this.labelHalo = const Color(0xccffffff),
});
```

改前：`const MarksPainter(this.marks);`、`:114` `style: const TextStyle(color: Color(0xff222222), fontSize: 11)`。

**③ 标签双趟绘制（:149-176）**：先画 `labelHalo` 的 stroke 层（`strokeWidth: 2.5`、`strokeJoin: round`、不设 `color`——`TextStyle.color` 与 `foreground` 互斥），再画 `labelColor` 的填充层，两层共用同一个 `Offset(o.dx - fill.width / 2, o.dy + 10)`（描边不改变字宽，对齐不漂）。

**④ `shouldRepaint`（:181-185）**：加 `labelColor` / `labelHalo` 比较（否则主题/画布切换时标签色不刷新）。

**⑤ `BoardPainter`（原报告里的 `DoodlePainter`；:188-196）：`this.color = 0xff000000` 在 :195，一字未动**（P16 断言钉死的是它）。本报告所称「DoodlePainter」= 该 `BoardPainter`。

### 1.3 sha256（改后）

```
fdf5c1807c703ace779947a56659cd21172ae08c36f67fb5f6e9c499c3a94e87  lib/ui/room/widgets/gp_map_stage.dart
fcfa19b21f2fdc09d1054ab9a50d241010d15b0e1f8eabac173181c13106fa64  lib/ui/room/painter/stroke_painter.dart
```

### 1.4 门禁自检

| 检查 | 结果 |
|---|---|
| `dart analyze`（两文件） | `No issues found!` |
| `lib/ui/room/**` 零 emoji（U+1F300–1FAFF 代理对） | 两文件均 0（`★` 为 U+2605，BMP，不违规；未新增变体选择符） |
| 新增 `jsStr(` | 0（两文件 `jsStr(` 计数为 0） |
| `flutter test` | **未跑** |
| 既有测试文件 | **未改**；未新建测试 |
| `pubspec.yaml` / `pubspec.lock` / `app_version.dart` | **未碰** |
| `room_game_page.dart` / `room_theme.dart` / `theme.dart` | **只读**，零改动（P16「KP 战斗态 gpMap 换战斗列表」链路 `:818-820` / `_combatStageCell` 未受影响） |
| `kDrawColors`（`room_theme.dart:11-17`） | 未动（它仍是纯 Dart 画笔色） |
| 固定尺寸控件 | **未新增**；改动的 3 处都是流式 `Text`（`Center` / `Positioned` 内），无 `minSize`、无高度约束，天然接受 textScaler 1.3/1.5/2.0，无需 `withClampedTextScaling` |

---

## 2. C-2 / C-4 取色决策表

判据只有一条：`cover == null`（⇔ `publicAssets` 为空 ⇔ 白板）。**不看 `Theme.brightness`**。

| 画布类型 | 主题 | 外层 `ColoredBox`（收边） | 内层画布 `Container` | 标点标签填充 | 标点标签描边 | 空态文字 | 「点击落点…」 | KP 计数 |
|---|---|---|---|---|---|---|---|---|
| **无公开素材（白板）** | 亮 | `Colors.white` | `Colors.white` | `#222222` | `#CCFFFFFF` | `#222222` | `#222222` | `#5C5C5C` |
| **无公开素材（白板）** | 暗 | `Colors.white` | `Colors.white` | `#222222` | `#CCFFFFFF` | `#222222` | `#222222` | `#5C5C5C` |
| **有公开素材（底图）** | 亮 | `scheme.surfaceContainerHighest` | `Colors.transparent` | `#F5F5F5` | `#CC000000` | 不出现（三空才出现，有素材即非空） | 主题默认 | 主题默认 `bodySmall` |
| **有公开素材（底图）** | 暗 | `scheme.surfaceContainerHighest` | `Colors.transparent` | `#F5F5F5` | `#CC000000` | 不出现 | 主题默认 | 主题默认 `bodySmall` |

「有公开素材」两行的外层/内层/计数/提示**与改前逐字等价**（同一表达式 `scheme.surfaceContainerHighest` / `Colors.transparent` / `copyWith(color: null)`），即**不动既有渲染**。

### 2.1 为什么四种情况都可读（对比度实算）

公式与 `test/p7_theme_test.dart:56-75` 同一套（WCAG 2.x 相对亮度 + `(hi+0.05)/(lo+0.05)`）：

```
ch(v)      = v<=0.04045 ? v/12.92 : ((v+0.055)/1.055)^2.4      # v = 通道/255
lum(c)     = 0.2126*ch(r) + 0.7152*ch(g) + 0.0722*ch(b)
contrast(a,b) = (max(lum)+0.05)/(min(lum)+0.05)
```

| 场景 | 前景 | 背景（最坏情况合成后） | 对比度 | 阈值 |
|---|---|---|---|---|
| 白板 · 标签 | `#222222` | `Colors.white` | **15.91** | ≥ 7（AAA 正文） |
| 白板 · 空态文字 | `#222222` | `Colors.white` | **15.91** | ≥ 4.5 |
| 白板 · KP 计数 | `#5C5C5C` | `Colors.white` | **6.69** | ≥ 4.5（AA） |
| 底图 · 标签 vs 自身描边 | `#F5F5F5` | 描边 `#CC000000` **合成在最亮底（纯白）上** = `#333333` | **11.59** | ≥ 7 |
| 底图 · 标签 vs 自身描边 | `#F5F5F5` | 描边合成在最暗底（纯黑）上 = `#000000` | **19.26** | ≥ 7 |

要点：
- **白板**：白底 + 深灰字，不依赖任何底图，亮暗主题同一结果（`#222222`/白 = 15.9:1）。
- **底图**：底图明暗不可知，所以不赌「底图亮/暗」，而是**赌「字与字边」**——描边 alpha 0.8 意味着无论底下是纯白还是纯黑，紧贴文字的像素都落在 `#333333`～`#000000` 之间，与 `#F5F5F5` 的对比度最低 11.59:1。这就是「按素材平均亮度自动反色」的确定性替代（不需要读像素、不会因为一张半亮灰图失效）。
- 白板上的标签描边是 `#CCFFFFFF`（白）：在白底上不可见（无副作用），但当标签压在**白板上的彩色笔迹/标点圆点**（`#e74c3c`/`#f1c40f`/`#3498db`）上时，白色描边把深灰字从深色圆点里「抠」出来，避免糊成一团。

### 2.2 边界情况（已知且可接受）

| 情况 | 表现 | 判定 |
|---|---|---|
| `assets` 非空但 base64 解码失败（`_coverImage` 返回 `SizedBox.shrink`） | 内层透明 → 透出外层 `surfaceContainerHighest`（暗色主题为深） → 标签是 `#F5F5F5` + 黑描边 | 可读（深底白字 19:1）。不改行为 |
| 白板但已有笔迹/标点 | 底色仍是白板（判据是 `assets.isEmpty`），不画空态文字 | 符合规范 §「两个判据要统一说明」 |
| 全屏只读（`_openFullscreen` → `readOnly: true`） | 同一个 `GpMapStage` state，取色逻辑一致 | 一致 |

---

## 3. 给波4 的验收用例口径（四条）

> 建议放进新建的 `test/p17_w2_stage_palette_test.dart`（波4 独占既有测试；波1 不建测试）。
> 纯函数断言不需要 widget pump，最省事也最咬得住。

### ① 无公开素材 → 画布 `Colors.white`（真值断言，不给近似色）

```dart
// 纯函数层（两种主题都要真值白）
for (final Brightness b in <Brightness>[Brightness.dark, Brightness.light]) {
  final ColorScheme scheme = buildTheme(b).colorScheme;
  expect(stageBackdropColor(null, scheme), Colors.white, reason: '外层收边必须硬白');
  expect(stageCanvasColor(null, scheme), Colors.white, reason: '画布必须硬白');
  expect(stageCanvasColor(null, scheme).a, 1.0, reason: '不许半透明（C-1 教训）');
}

// 组件层（真机渲染值，不是函数返回值）
final Container box = tester.widget<Container>(find
    .descendant(of: find.byKey(GpMapStageKeys.canvas), matching: find.byType(Container))
    .first);
expect((box.decoration as BoxDecoration).color, Colors.white);
final ColoredBox backdrop = tester.widget<ColoredBox>(find
    .descendant(of: find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpMap)),
                matching: find.byType(ColoredBox))
    .first);
expect(backdrop.color, Colors.white);
```

反向证伪：把 `stageCanvasColor` 的 `cover == null` 改成 `false` → ① 必红。

### ② 有素材时底色不被改

```dart
final Map<String, Object?> cover = <String, Object?>{'id': 'a', 'kind': 'map'};
expect(stageBackdropColor(cover, scheme), scheme.surfaceContainerHighest);
expect(stageCanvasColor(cover, scheme), Colors.transparent);
```

并**保留** `test/p10_t7_layout_test.dart:336-352` 的组件级断言（canvas 子 Container 的 `decoration.color` 必须是 null/transparent/alpha 0）——该用例继续绿，不许改口径。

### ③ `BoardPainter` 默认笔色仍是 `0xff000000`（P16 断言逐字保留）

`test/p16_wave1_theme_test.dart:60-70` **一字不改**：`BoardPainter(const <Map<String, Object?>>[]).color == 0xff000000`，`reason` 文案也保留。

### ④ 标签色在两种画布下都过对比度阈值

```dart
// 公式：与 p7_theme_test.dart:56-75 同一套
double ch(double v) => v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
double lum(Color c) => 0.2126*ch(c.r) + 0.7152*ch(c.g) + 0.0722*ch(c.b);
double contrast(Color a, Color b) { final la = lum(a), lb = lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05); }

// 白板：标签 vs 白底
expect(contrast(stageMarkLabelColor(false), stageBoardColor), greaterThanOrEqualTo(7.0)); // = 15.91
// 有素材：标签 vs 它自己的描边（最坏情况把描边合成在纯白底上 → #333333）
final Color worstHalo = Color.alphaBlend(stageMarkLabelHalo(true), Colors.white);
expect(contrast(stageMarkLabelColor(true), worstHalo), greaterThanOrEqualTo(7.0));       // = 11.59
// 防退化：两种画布不能取同一个颜色
expect(stageMarkLabelColor(true), isNot(stageMarkLabelColor(false)));
// 白板标签真值（钉死具体值，避免有人改成 0xff555555 混过去）
expect(stageMarkLabelColor(false), const Color(0xff222222));
```

反向证伪：把 `stageMarkLabelColor(false)` 改成 `const Color(0xffffffff)` → ④ 的 15.91 断言必红。

---

## 4. 预计会转红的既有测试清单 + 建议口径

**结论：预计 0 条必红。** 本次行为变更只发生在「无公开素材」分支与 `MarksPainter` 的绘制细节，全库既无按 `surfaceContainerHighest` 颜色值断言，也无按 `Color(0xff222222)` 断言标签文字，也无金图测试（`grep matchesGoldenFile` 0 命中）。以下逐条给出「为什么仍绿」与「若要补强该写在哪、怎么写得更强」：

| # | 文件:行 | 与本批的关系 | 当前结果 | 建议口径 |
|---|---|---|---|---|
| 1 | `test/p16_wave1_theme_test.dart:60-70` | 钉 `BoardPainter` 默认 `0xff000000` | **仍绿**（`stroke_painter.dart:195` 一字未动） | 逐字不动。**若有人把它改成 `${stageMarkLabelColor}` 之类就错了** —— 那条断言的 `reason`（`原 0xff222222`）针对的是画笔，不是标签 |
| 2 | `test/p10_t7_layout_test.dart:295-352`（T6 公开素材渲染） | 有底图时 canvas 子 `Container` 必须透明 | **仍绿**（有素材分支仍 `Colors.transparent`） | 保留不动；**新增**「无素材 → `Colors.white`」请另起断言（见 §3 ①），**不要替换** T6 的 `reason` |
| 3 | `test/p10_t7_layout_test.dart:100-110`（stage 严格 16:9） | 几何 | **仍绿**（`AspectRatio`/key 未动） | 不动 |
| 4 | `test/p10_t7_c_combat_test.dart:855-897`（KP 战斗态 gpMap 换战斗列表） | P16 的 `_combatStageCell` | **仍绿**（`room_game_page.dart` 零改动） | 不动 |
| 5 | `test/room_ui_blocks_test.dart:565-710`（舞台标点落点 / 画布 tap / 只读） | 舞台交互 | **仍绿**（未断言颜色，`MarksPainter` 多画一层描边不影响 `map.mark` 载荷与 `takeException`） | 不动 |
| 6 | `test/p7_theme_test.dart:56-104`（主题对比度） | 通用主题 | **仍绿**（未碰 `theme.dart`） | 不动 |
| 7 | `test/room_ui_wiring_test.dart:94/132-190`、`test/room_ui_shell_test.dart:289-304`、`test/p7_lobby_gate_test.dart:79-109`、`test/room_ui_permission_test.dart:622`、`test/p10_t3_layout_test.dart:171/227/237` | 舞台槽位接线 / readOnly 传递 | **仍绿**（`GpMapStage` 构造参数未变） | 不动 |
| 8 | `test/p16_wave1_theme_test.dart:73-80`（源码断言 `gp_pl_sketch.dart` 含 `color: Colors.white`） | 手绘板白板 | **仍绿**（本批没碰 `gp_pl_sketch.dart`） | 若波4 想给舞台加同类源码断言，注意本批舞台的白是 `stageBoardColor = Colors.white`，源码串是 `contains('stageBoardColor = Colors.white')`，别写成 `color: Colors.white`（舞台里没有这个字面串） |

> 唯一需要留意的**间接**影响：`MarksPainter` 现在每次画标签会 layout 两个 `TextPainter`（描边 + 填充）。任何按「绘制次数/绘制耗时」计数的用例不存在（已 grep 确认无 `matchesGoldenFile`、无 `debugPaintCount` 类断言），故无连坐。

---

## 5. 声明

1. **未跑 `flutter test`**（并发期纪律）；只用 `dart analyze lib/ui/room/widgets/gp_map_stage.dart lib/ui/room/painter/stroke_painter.dart` → `No issues found!`。
2. **未修改任何既有测试文件，未新建任何测试文件**。
3. **只改了自己文件集内的两个文件**：`lib/ui/room/widgets/gp_map_stage.dart`、`lib/ui/room/painter/stroke_painter.dart`。未碰 `room_game_page.dart` / `room_theme.dart` / `theme.dart` / `gp_pl_sketch.dart` / `pubspec.yaml` / `pubspec.lock` / `lib/app_version.dart`，未 `flutter clean`。
4. 未新增 `jsStr(`；`lib/ui/room/**` 零 emoji（U+1F300–1FAFF）。
5. 既有 key 全部保留（`GpMapStageKeys.*` 7 个、`RoomSlot.gpMap/gpPlMap` 接线不变）；`MarksPainter` 位置参数 `marks` 与 `DoodlePainter`/`BoardPainter` 的 `color` 默认值均未破坏，只加了可选具名参数。
6. 未跑 adb / 模拟器 / 真机。真机待测项：**C-4 白板**（无素材房间在亮/暗主题下舞台均为纯白、无半透明透底）、**C-2 标签**（白板上深色标点名可读；上传一张深色底图后标点名变浅色带黑描边、可读）。
