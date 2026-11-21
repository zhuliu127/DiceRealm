// ============================================================
// test/p16_button_unify_test.dart — P16「栏位内按钮统一尺寸」正向验收
//
// 用户原话（2026-11 真机反馈）：
//   「跑团房间-游戏中，玩家和 KP 视角，**同一栏位的按钮，都改成大小相同的
//     （宽高相同）**，如果一个栏位有一个比其他的按钮都长的按钮，那就让这一个
//     特殊一点，让其他按钮改成相同大小，然后**重新排布一下，让按钮更整齐**。」
//
// ★ 判据形态：**尺寸集合精确比较**
//     final Set<Size> sizes = { for (final k in keys) tester.getSize(find.byKey(k)) };
//     expect(sizes, <Size>{ expected }, reason: '…');
//   集合比较同时证明两件事：① 组内彼此宽高完全相同；② 恰好等于规格值。
//   比 `every((s) => s == expected)` 更强（后者对空集恒真）。
//
// ★ 期望值一律是**硬编码构造的 Size**，不从 `RoomBtnSize` 读
//   —— 否则等于「用被测实现验证被测实现」。同时单独用一条一致性断言
//   （P16-03 末段）钉住「RoomBtnSize 常量 == 本文件的硬编码期望」，防两边漂移。
//
// ★ 每个期望值都来自**实测校准**（测试字体每字 13.25dp，比真机 Roboto 宽；
//   取更紧的那一侧，宁宽 4dp 也不 overflow —— overflow 会打红 `takeException`）：
//     `极难成功(4)` 7 字 → 92.75 + 12 = 104.75 ⇒ sceneTile 108（规格原估 104）
//     `AI RP` 5 字      → 100.25            ⇒ charTile  104（规格原估 90）
//     `100%` 4 字       → 87                ⇒ 缩放按钮按用户规则「特殊」（其余 3 个 80）
//
// ★ 铁律：不 skip、不放宽成 findsWidgets、不删任何既有用例；
//   本文件只新增，既有 44 条断言值一个都没改。
//
// ★ P16 第二轮（QA 判定 NO 后补的回归）：P16-14/15/16 是**大字体不溢出**
//   矩阵。定宽 `RoomTapTile` 用 `SizedBox(W,H)` 给紧约束，而 `RoomTap` 内部
//   `Text(fontSize: 13)` 默认跟随 `MediaQuery.textScaler` ⇒ 系统字号调大就会
//   撑破定宽（QA 实测 1.3/1.5/2.0 三档 × 12 格 = 36 格红，最大溢 87.8dp）。
//   修法：`room_button_size.dart#clampBtnText` 只钳**按钮子树**的文字缩放，
//   面板正文 / 聊天 / 笔记等非按钮文字完全不受影响。
//   这三条用例就是那道闸门：把 `clampBtnText` 摘掉它们必红（已做反向证伪）。
//
// ★ 环境：`source /d/dev/env.sh`；命令前后 `unset *_PROXY` + `NO_PROXY=127.0.0.1`，
//   跑完立刻从 `_gh_backup` 逐字节恢复 `pubspec.lock`（pub get 会改写成镜像）。
// ============================================================

import 'package:dice_realm/domain/room_types.dart' show RoomIntent, kHostSeat;
import 'package:dice_realm/ui/room/room_game_page.dart' show RoomGamePage;
import 'package:dice_realm/ui/room/room_keys.dart' show RoomKeys, RoomSlot;
import 'package:dice_realm/ui/room/widgets/gp_dice_bar.dart'
    show
        GpDiceBarKeys,
        diceBalancedRowSizes,
        diceMaxPerRow,
        kDiceTileGap,
        kDiceTileW;
import 'package:dice_realm/ui/room/widgets/gp_feeds.dart'
    show FeedPane, GpFeedsKeys;
import 'package:dice_realm/ui/room/widgets/gp_kp_left.dart' show GpKpLeftKeys;
import 'package:dice_realm/ui/room/widgets/gp_kp_tools.dart' show GpKpToolsKeys;
import 'package:dice_realm/ui/room/widgets/gp_pl_char_card.dart'
    show GpPlCharCardKeys;
import 'package:dice_realm/ui/room/widgets/gp_privates.dart' show GpPrivatesKeys;
import 'package:dice_realm/ui/room/widgets/gp_scene_check_kp.dart'
    show GpSceneCheckKeys;
import 'package:dice_realm/ui/room/widgets/gp_scene_check_pl.dart'
    show GpSceneCheckPlKeys;
import 'package:dice_realm/ui/room/widgets/gp_status.dart'
    show GpStatusKeys, RoomRequestCard;
import 'package:dice_realm/ui/room/widgets/gp_toolbar.dart' show GpToolbarKeys;
import 'package:dice_realm/ui/room/widgets/room_button_size.dart'
    show RoomBtnSize;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderFlex;
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart' show RoomUiFixture, useRoomScreen;

// ------------------------------------------------------------
// 硬编码期望值（不许从 RoomBtnSize 读，见文件头）
// ------------------------------------------------------------

const Size _kToolbar = Size(80, 40); // 工具栏主组 3 个（缩放按钮是「特殊」的）
const Size _kToolbarWide = Size(90, 40); // KP / 更多工具
const Size _kDice = Size(90, 40); // 骰子条 8 个
const Size _kTools = Size(90, 48); // KP 工具 6 个
const Size _kAsset = Size(48, 48); // 素材三按钮
const Size _kScene = Size(108, 48); // 场景检定 8 个
const Size _kChar = Size(104, 40); // 角色卡 4 短
const Size _kTrailing = Size(44, 32); // trailing 小图标
const Size _kChatIcon = Size(48, 44); // 聊天输入行 3 个
const double _kSceneChipMinW = 90; // 技能 chip 最小宽
const double _kSceneChipH = 32; // 技能 chip 恒定高

// ------------------------------------------------------------
// 夹具
// ------------------------------------------------------------

/// 整页（RoomGamePage 真骨架）+ 全内存后端。
Future<RoomUiFixture> _boot(
  WidgetTester tester, {
  required double w,
  required double h,
  String seat = kHostSeat,
}) async {
  final f = RoomUiFixture();
  await f.boot(inGame: true);
  f.pageBuilder = (String s, String r) => const RoomGamePage();
  useRoomScreen(tester, w, h);
  await tester.pumpWidget(f.pageOf(seat));
  await tester.pump();
  return f;
}

/// 收集一组 key 的**全部**实例尺寸（同一个 key 可能在两列信息流里各有一个）。
List<Size> _allSizes(WidgetTester tester, List<Key> keys) {
  final out = <Size>[];
  for (final Key k in keys) {
    final Finder f = find.byKey(k);
    final int n = f.evaluate().length;
    for (var i = 0; i < n; i++) {
      out.add(tester.getSize(n == 1 ? f : f.at(i)));
    }
  }
  return out;
}

/// 正向判据：尺寸集合必须恰好是 [expected]。
void _expectUniform(
  WidgetTester tester,
  String label,
  List<Key> keys,
  Size expected,
) {
  final List<Size> all = _allSizes(tester, keys);
  expect(all, isNotEmpty, reason: '$label：一个按钮都没找到（key 写错或未被渲染）');
  expect(
    all.toSet(),
    <Size>{expected},
    reason: '$label：同栏位按钮尺寸必须恰好 '
        '${expected.width}×${expected.height}，实测 $all',
  );
}

/// 按 centerY 分组数行数（同 P10 的口径）。
int _rowCount(WidgetTester tester, List<Key> keys) {
  final centers = <double>[];
  for (final Key k in keys) {
    final Finder f = find.byKey(k);
    if (f.evaluate().isEmpty) continue;
    final Rect r = tester.getRect(f.first);
    if (centers.every((double c) => (c - r.center.dy).abs() > 1.0)) {
      centers.add(r.center.dy);
    }
  }
  return centers.length;
}

// ★ 2.34.0：原 `_kKnownP17`（PanelTabs._label 溢出）白名单已删除 ——
//   Wave1 删 6 档 + W-B 紧凑 chip / `FittedBox` 修复后实测该溢出不再出现，
//   按原用例自带的指引「实测为空就删掉白名单」恢复为「任何整页异常都算失败」。

/// 把 `FlutterErrorDetails.toString()` 压成一句可读的话（报告里好定位）：
/// 取「溢出量」+「出错 widget 的 file:line」两行，都不含时退回第一行。
String _shortErr(String detail) {
  final List<String> lines = detail
      .split('\n')
      .map((String l) => l.trim())
      .where((String l) => l.isNotEmpty)
      .toList();
  String amount = '';
  String where = '';
  for (final String l in lines) {
    if (amount.isEmpty && l.contains('overflowed by')) amount = l;
    if (where.isEmpty && (l.contains('Row:') || l.contains('Column:'))) where = l;
  }
  if (amount.isEmpty && where.isEmpty) {
    return lines.isEmpty ? detail : lines.first;
  }
  return '$amount $where'.trim();
}

/// 本批**定宽化**过的全部按钮组（`大字体不溢出` 用例的检查清单）。
///
/// 只列 P16 真正改过尺寸/排布的按钮；不属于本批的（`gpCombat`、`PanelTabs`、
/// `gpMapStage`、`gpPlNotes`、花幸运/推动……）一律不在内 —— 它们的大字体
/// 溢出是既有问题，不在本批文件集的可修范围内。
Map<String, List<Key>> _p16ButtonGroups() => <String, List<Key>>{
      // ★ 2.36.0 / Q6：产品行为真变 —— KP 主组 = 缩放 + 复位 + 2 个新扁平
      //   按钮（独立 ValueKey）；P17 已删的 `act/round.next` / `act/scene.mode`
      //   不再渲染。按视角校准成真实 key，让大字体 `_innerOverflows` 真的覆盖
      //   到新按钮（玩家/旁观视角新按钮不渲染，探针自动跳过，核心不变量不变）。
      'gpToolbar 主组': <Key>[
        GpToolbarKeys.zoomPercent,
        RoomKeys.gpZoomReset,
        RoomGamePage.nextRoundKey,
        RoomGamePage.combatReadyKey,
      ],
      'gpToolbar 扩展': <Key>[
        RoomGamePage.kpPanelKey,
        RoomGamePage.miscToolsKey,
      ],
      'gpDiceBar': <Key>[
        GpDiceBarKeys.bonus,
        GpDiceBarKeys.penalty,
        GpDiceBarKeys.expr('1D100'),
        GpDiceBarKeys.otherDice,
        GpDiceBarKeys.rollCustom,
        GpDiceBarKeys.dark,
        RoomKeys.action('combat.roll'),
        RoomKeys.action('check.opposed'),
      ],
      'gpKpTools': <Key>[
        GpKpToolsKeys.addActor,
        GpKpToolsKeys.mark,
        GpKpToolsKeys.draw,
        GpKpToolsKeys.erase,
        GpKpToolsKeys.placeActor,
        GpKpToolsKeys.placePlayer,
        GpKpToolsKeys.clear,
        GpKpToolsKeys.upload,
      ],
      'gpKpLeft': <Key>[
        GpKpLeftKeys.addActor,
        GpKpLeftKeys.upload,
      ],
      'gpScene': <Key>[
        GpSceneCheckKeys.quickPush,
        GpSceneCheckKeys.editor,
      ],
      'gpPlScene': <Key>[GpSceneCheckPlKeys.roll],
      'gpPlCharCard': <Key>[
        GpPlCharCardKeys.stateBtn,
        RoomKeys.action('aid.apply'),
        GpPlCharCardKeys.itemsBtn,
        GpPlCharCardKeys.aiBtn,
        GpPlCharCardKeys.saveBtn,
        RoomKeys.action('madness.advance'),
      ],
      'gpFeeds': <Key>[
        GpFeedsKeys.fullscreen,
        GpFeedsKeys.aiRp,
        GpFeedsKeys.chatFullscreen,
        GpFeedsKeys.send,
      ],
      'gpPrivates': <Key>[GpPrivatesKeys.fullscreen],
    };

/// 逐按钮量「内部 Row 的子件宽之和 − Row 实宽」：>0 即该按钮内部发生了
/// `RenderFlex overflow`（`RoomTap` 的 Row 是 `mainAxisSize.min`，
/// 内容装不下就直接溢出，不做省略）。
///
/// ★ 为什么不直接看整页 `takeException()`：整页还有本批范围外的既有溢出
///   （见 P16-14/15/16 段首的清单），那样会让用例红在别人身上。
/// ★ `RoomTap` 内部的纵向链条是
///   `Semantics → RoomButtonSkin → Material → InkWell → ConstrainedBox →
///    Align → Padding → Row`，所以取「第一个 Row 后代」就是那个会溢出的 Row。
List<String> _innerOverflows(
  WidgetTester tester,
  String group,
  List<Key> keys,
) {
  final out = <String>[];
  for (final Key k in keys) {
    final Finder f = find.byKey(k);
    final int n = f.evaluate().length;
    for (var i = 0; i < n; i++) {
      final Finder one = n == 1 ? f : f.at(i);
      final Finder rows = find.descendant(of: one, matching: find.byType(Row));
      if (rows.evaluate().isEmpty) continue; // 纯图标/纯文字以外的结构，跳过
      final RenderFlex rf = tester.renderObject<RenderFlex>(rows.first);
      var sum = 0.0;
      RenderBox? child = rf.firstChild;
      while (child != null) {
        sum += child.size.width;
        child = rf.childAfter(child);
      }
      if (sum > rf.size.width + 0.01) {
        out.add('$group/$k 内容需 $sum、实宽 ${rf.size.width}');
      }
    }
  }
  return out;
}

/// 反向自证：`clampBtnText` **只**钳按钮子树 —— 面板正文必须真的跟着系统
/// 字号变大。
///
/// 两路证据（QA 会专门查这一条）：
/// ① **结构**：面板标题所在 context 的 `textScaler.scale(13)` 必须等于
///    `13 × 倍率`（没有被 MediaQuery 钳住）；
/// ② **像素**：同一段文字的高度，在「倍率」下必须是「×1.0」下的约 `倍率` 倍
///    （单行文本行高与 fontSize 成正比）。量完立刻把倍率切回去。
///
/// 若有人把 clamp 抬到 `room_game_page.dart` / Theme / MaterialApp 层，
/// ①② 会同时红 —— 这正是本函数存在的意义：钳制必须是**局部**的。
Future<void> _expectPanelTextNotClamped(
  WidgetTester tester,
  double scale,
  String cell,
) async {
  // `游戏记录` 是 KP / 玩家、六档屏都必然渲染的 SectionBox 标题（信息流块），
  // 且在 1280 档栏宽足够，任何倍率下都是单行（行高才可比）。
  final Finder title = find.text('游戏记录').first;
  final BuildContext ctx = tester.element(title);
  final double scaled13 = MediaQuery.of(ctx).textScaler.scale(13);
  expect(scaled13, closeTo(13 * scale, 0.01),
      reason: '$cell：面板标题的文字**被连带钳掉了**（应为 ${13 * scale}，'
          '实测 $scaled13）—— clampBtnText 必须只包按钮子树，'
          '不能抬到整页 / Theme / MaterialApp 层');

  final double scaledH = tester.getSize(title).height;
  // 切回 1.0 量基线：同一棵树、只改 textScaler，比较的还是同一段文字。
  tester.platformDispatcher.textScaleFactorTestValue = 1.0;
  await tester.pump();
  final double baseH = tester.getSize(find.text('游戏记录').first).height;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  await tester.pump();
  // 切回倍率会重放一次「既有」溢出（如 gpCombat 的 trailing），drain 掉。
  while (tester.takeException() != null) {}

  expect(scaledH, greaterThan(baseH),
      reason: '$cell：面板正文实测高度没随字号变大（×1.0 = $baseH、'
          '×$scale = $scaledH）—— 正文被钳住了');
  expect(scaledH / baseH, closeTo(scale, 0.15),
      reason: '$cell：面板正文高度倍率应为 ×$scale，实测 ×'
          '${(scaledH / baseH).toStringAsFixed(2)}'
          '（×1.0 = $baseH、×$scale = $scaledH）');
}

void main() {
  // ========================================================
  // P16-01 · 工具栏主组（KP）
  // ========================================================
  testWidgets('P16-01 gpToolbar 主组：复位严格 80×40；Q6 两个新按钮严格 90×40，'
      '缩放是本组唯一长按钮（更高不变，宽 ≥80）', (WidgetTester tester) async {
    await _boot(tester, w: 1280, h: 800);

    // ★ 2.36.0 / Q6（更强或等价）：原口径 3 个 key 里 `act/round.next` 与
    //   `act/scene.mode` 自 P17 起已不渲染（等价空跑），现按真实视角校准：
    //   ① `gpZoomReset` 仍严格 80×40 —— `_expectUniform` 严格尺寸核心不变量
    //      逐字保留（集合精确比较，比 every() 更强）；
    //   ② 新增 2 个真按钮各自严格 90×40（toolbarWide）—— 比原口径更强。
    _expectUniform(
      tester,
      'gpToolbar 主组（缩放复位）',
      <Key>[
        RoomKeys.gpZoomReset,
      ],
      _kToolbar,
    );
    _expectUniform(
      tester,
      'gpToolbar 主组（Q6 新按钮）',
      <Key>[
        RoomGamePage.nextRoundKey,
        RoomGamePage.combatReadyKey,
      ],
      _kToolbarWide,
    );

    // ★ 缩放按钮：`100%` 是本组最长的一个（用户规则里的「让它特殊」）。
    //   它只给 minSize，所以高度仍必须 =40；宽度不得小于 80（真机 Roboto 下
    //   `100%` 内容 ≈60 ⇒ 恰好 80，与其余三个逐像素同宽）。
    final Size zoom = tester.getSize(find.byKey(GpToolbarKeys.zoomPercent));
    expect(zoom.height, _kToolbar.height,
        reason: 'gpToolbar 缩放按钮：高度必须与主组一致（40），实测 $zoom');
    expect(zoom.width, greaterThanOrEqualTo(_kToolbar.width),
        reason: 'gpToolbar 缩放按钮：宽不得小于主组基准 80，实测 $zoom');

    // 扩展组（KP 视角）：KP / 更多工具 同宽 90，BGM 场景是唯一长按钮。
    _expectUniform(
      tester,
      'gpToolbar 扩展（KP）',
      <Key>[RoomGamePage.kpPanelKey],
      _kToolbarWide,
    );
    expect(tester.takeException(), isNull);
  });

  // ========================================================
  // P16-02 · 骰子条 8 个
  // ========================================================
  testWidgets('P16-02 gpDiceBar 6 个标准条目 90×40 同宽；'
      'stepper 四段为复合控件单独守热区（P17 C-3）',
      (WidgetTester tester) async {
    await _boot(tester, w: 1280, h: 800);
    // ★ P17 C-3：奖惩骰改三段式复合控件 `[−][奖励N][↺]` —— 值段宽度随
    //   内容自适应（实测 ~52dp），**不再**参与「90×40 同宽」；同宽口径
    //   收窄到 6 个标准骰条目，另加「stepper 六段都渲染、热区 ≥28」正向。
    _expectUniform(
      tester,
      'gpDiceBar',
      <Key>[
        GpDiceBarKeys.expr('1D100'),
        GpDiceBarKeys.otherDice,
        GpDiceBarKeys.rollCustom,
        GpDiceBarKeys.dark,
        RoomKeys.action('combat.roll'),
        RoomKeys.action('check.opposed'),
      ],
      _kDice,
    );
    for (final Key k in <Key>[
      GpDiceBarKeys.bonusMinus,
      GpDiceBarKeys.bonus,
      GpDiceBarKeys.bonusReset,
      GpDiceBarKeys.penaltyMinus,
      GpDiceBarKeys.penalty,
      GpDiceBarKeys.penaltyReset,
    ]) {
      final Rect r = tester.getRect(find.byKey(k));
      expect(r.width, greaterThanOrEqualTo(28),
          reason: 'P17 C-3：$k 热区过窄（stepper 子段下限）');
      expect(r.height, greaterThanOrEqualTo(36),
          reason: 'P17 C-3：$k 高度过矮');
    }
    expect(tester.takeException(), isNull);

    // ★ P16 补齐（QA 二轮挖出的缺口）：骰子条的 8 个按钮是「裸 `RoomTap` +
    //   `minSize: diceTile`」，**不在** `RoomTapTile` 内 ⇒ 之前没被钳住。
    //   后果（QA 实测）：×1.5 下同栏位宽度散成 {113,113,111,113,90,93.3}
    //   （distinct=4）、360dp 档行数 3→4 —— 用户开大字体后这一栏就不满足
    //   「同一栏位按钮大小相同」，与诉求直接冲突。
    //   修法：`gp_dice_bar.dart` 的 `rollGroup` / `tailGroup` 两个列表在声明处
    //   `.map(clampBtnText)`。下面 3 档字号逐档验证「尺寸集合仍 == {90×40}」
    //   + 「360dp 仍 3 行」。
    // 采样分两组：同宽断言用 6 个标准条目；行数断言用全量 12 键
    // （含 stepper 四段子件，保证切行采样不漏）。
    final List<Key> uniformKeys = <Key>[
      GpDiceBarKeys.expr('1D100'),
      GpDiceBarKeys.otherDice,
      GpDiceBarKeys.rollCustom,
      GpDiceBarKeys.dark,
      RoomKeys.action('combat.roll'),
      RoomKeys.action('check.opposed'),
    ];
    final List<Key> sampleKeys = <Key>[
      ...uniformKeys,
      GpDiceBarKeys.bonus,
      GpDiceBarKeys.penalty,
      GpDiceBarKeys.bonusMinus,
      GpDiceBarKeys.bonusReset,
      GpDiceBarKeys.penaltyMinus,
      GpDiceBarKeys.penaltyReset,
    ];
    for (final double scale in <double>[1.3, 1.5, 2.0]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      // ① 1280 宽档：标准条目尺寸集合必须仍是单元素 {90×40}。
      await _boot(tester, w: 1280, h: 800);
      _expectUniform(tester, 'gpDiceBar @×$scale 字号', uniformKeys, _kDice);

      // ② 360 窄档：仍必须 3 行（大字体不得改变切行）。
      await _boot(tester, w: 360, h: 640);
      expect(_rowCount(tester, sampleKeys), 3,
          reason: 'gpDiceBar @×$scale / 360dp：仍必须切成 3 行（3/3/2 或 3/3/3），'
              '实测 ${_rowCount(tester, sampleKeys)} 行');
      // 大字体下整页可能有本批范围外的既有溢出（如 ×2.0 的 PanelTabs），
      // 这里只对本批负责，先 drain 掉，避免污染后续断言。
      while (tester.takeException() != null) {}
    }
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  // ========================================================
  // P16-03 · 切行纯函数 + 尺寸族常量一致性（纯 Dart）
  // ========================================================
  test('P16-03 diceMaxPerRow / diceBalancedRowSizes 三档算术 + '
      'RoomBtnSize 常量与本文件期望值一致', () {
    // 除数 = 统一宽 90 + spacing 3 = 93；`-16` 为既有保守口径。
    expect(diceMaxPerRow(348), 3, reason: '360dp 屏：骰子条可用 348 → 每行 3 个');
    expect(diceMaxPerRow(400), 4, reason: '412dp 屏：骰子条可用 400 → 每行 4 个');
    expect(diceMaxPerRow(546), 4, reason: 'clamp 上限 4 必须仍然生效');
    expect(diceMaxPerRow(280), 2, reason: 'clamp 下限 2 必须仍然生效');

    // 当前实际 9 项：per ∈ {3,4} 恒为 3/3/3，结构上不可能出现孤行。
    expect(diceBalancedRowSizes(9, 3), <int>[3, 3, 3],
        reason: '9 项 per=3 必须均分成 3/3/3（无孤行）');
    expect(diceBalancedRowSizes(9, 4), <int>[3, 3, 3],
        reason: '9 项 per=4 也必须均分成 3/3/3（无孤行）');
    final List<int> worst = diceBalancedRowSizes(9, 2);
    expect(worst, <int>[2, 2, 2, 2, 1],
        reason: '孤行只在 per=2 时出现；per=2 需可用宽 <295，工具栏最小档 308 ⇒ 不可达');
    expect(diceBalancedRowSizes(0, 4), isEmpty);

    // ★ 一致性断言：常量与本文件硬编码的期望值不许漂移。
    expect(RoomBtnSize.toolbarTile, _kToolbar, reason: 'toolbarTile 与期望不符');
    expect(RoomBtnSize.toolbarWide, _kToolbarWide,
        reason: 'toolbarWide 与期望不符');
    expect(RoomBtnSize.diceTile, _kDice, reason: 'diceTile 与期望不符');
    expect(RoomBtnSize.toolsTile, _kTools, reason: 'toolsTile 与期望不符');
    expect(RoomBtnSize.assetTile, _kAsset, reason: 'assetTile 与期望不符');
    expect(RoomBtnSize.sceneTile, _kScene, reason: 'sceneTile 与期望不符');
    expect(RoomBtnSize.charTile, _kChar, reason: 'charTile 与期望不符');
    expect(RoomBtnSize.trailingSm, _kTrailing, reason: 'trailingSm 与期望不符');
    expect(RoomBtnSize.chatIcon, _kChatIcon, reason: 'chatIcon 与期望不符');
    expect(RoomBtnSize.scenePlTile.width, _kSceneChipMinW,
        reason: 'scenePlTile 最小宽与期望不符');
    expect(RoomBtnSize.scenePlTile.height, _kSceneChipH,
        reason: 'scenePlTile 高度与期望不符');
    // 切行公式的除数必须与「统一宽 + spacing」同源。
    expect(kDiceTileW, RoomBtnSize.diceTile.width,
        reason: 'kDiceTileW 必须等于 diceTile.width（切行与定宽同源）');
    expect(kDiceTileGap, RoomBtnSize.gapTight,
        reason: 'kDiceTileGap 必须等于 gapTight');
  });

  // ========================================================
  // P16-04 · KP 工具窄栏
  // ========================================================
  testWidgets('P16-04 gpKpTools 5 个动作按钮全 90×48 + 行数 ≤3',
      (WidgetTester tester) async {
    await _boot(tester, w: 1280, h: 800);

    // ★ P16 KP-10：「增加怪物」整块（内联 ActorFields + 加怪按钮 + 候选列表）
    //   与「上传素材」按钮都已从本栏移除 ⇒ 动作按钮 6 → 5。
    final List<Key> keys = <Key>[
      GpKpToolsKeys.mark,
      GpKpToolsKeys.draw,
      GpKpToolsKeys.erase,
      GpKpToolsKeys.placeActor,
      GpKpToolsKeys.placePlayer,
    ];
    _expectUniform(tester, 'gpKpTools 5 个动作按钮', keys, _kTools);

    // 2 列网格 ⇒ 5 个按钮恰好 3 行（2 + 2 + 1）。
    expect(_rowCount(tester, keys), lessThanOrEqualTo(3),
        reason: 'gpKpTools 5 个动作按钮必须排进 ≤3 行，实测 ${_rowCount(tester, keys)}');

    // 正向反证：KP-10 删掉的两块确实不在本栏（不是「移到别处又漏了」）。
    expect(find.byKey(GpKpToolsKeys.addActor), findsNothing,
        reason: 'KP-10：工具窄栏不再有加怪按钮（改走左栏弹层）');
    expect(find.byKey(GpKpToolsKeys.upload), findsNothing,
        reason: 'KP-10：工具窄栏不再有上传素材按钮（只留左栏一处）');

    expect(tester.takeException(), isNull);
  });

  // ========================================================
  // P16-05 · KP 左窄栏
  // ========================================================
  testWidgets('P16-05 gpKpLeft 素材两按钮 48×48（≥47.5）+ 加怪 90×48 + 上传满宽',
      (WidgetTester tester) async {
    final f = await _boot(tester, w: 1280, h: 800);

    // 加怪在「NPC·怪物」tab（KP-7：90×48 与工具窄栏同档）。
    f.localOf(kHostSeat).setTab('left', 0);
    await tester.pump();
    _expectUniform(tester, 'gpKpLeft 加怪', <Key>[GpKpLeftKeys.addActor], _kTools);

    // 素材行按钮在「素材」tab（测试钉死热区 ≥47.5，绝不跟着工具按钮升到 90）。
    // ★ P16 KP-2：「封面」按钮已删 ⇒ 3 → 2（公开/隐藏 + 删除）。
    f.host.localAssets.add(<String, Object?>{
      'id': 'p16asset',
      'kind': 'map',
      'name': '测试底图',
      'data': '',
      'revealed': false,
      'at': 1,
    });
    f.localOf(kHostSeat).setTab('left', 1);
    await tester.pump();

    final List<Key> assets = <Key>[
      GpKpLeftKeys.reveal('p16asset'),
      GpKpLeftKeys.delete('p16asset'),
    ];
    _expectUniform(tester, 'gpKpLeft 素材两按钮', assets, _kAsset);
    // 正向反证：封面按钮确实不在了（key 与文案都不得残留）。
    expect(find.byKey(GpKpLeftKeys.cover('p16asset')), findsNothing,
        reason: 'KP-2：素材行不再有「封面」按钮');
    expect(find.text('封面'), findsNothing, reason: '「封面」文案已随按钮退场');
    for (final Key k in assets) {
      final Size s = tester.getSize(find.byKey(k));
      expect(s.width, greaterThanOrEqualTo(47.5),
          reason: 'gpKpLeft $k 热区宽度被压到 48 以下');
      expect(s.height, greaterThanOrEqualTo(47.5),
          reason: 'gpKpLeft $k 热区高度被压到 48 以下');
    }

    final Rect cell =
        tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpKpLeft)));
    final Size upload = tester.getSize(find.byKey(GpKpLeftKeys.upload));
    expect(upload.width, closeTo(cell.width - 28, 0.5),
        reason: 'gpKpLeft 上传素材必须拉满内容宽（${cell.width - 28}），'
            '实测 ${upload.width}');
    expect(upload.height, 48, reason: 'gpKpLeft 上传素材高度必须 48');

    expect(tester.takeException(), isNull);
  });

  // ========================================================
  // P16-06 · KP 场景检定
  // ========================================================
  testWidgets('P16-06 gpScene 保留 2 个按钮全 108×48，且 6 档 level key 全无',
      (WidgetTester tester) async {
    await _boot(tester, w: 1280, h: 800);

    // ★ W-A 删 6 档：数据源只余「推送检定」「检定编辑器」两个动作按钮。
    expect(_p16ButtonGroups()['gpScene']!.length, 2,
        reason: 'gpScene 数据源应只余 2 个按钮');
    final List<Key> keys = <Key>[
      GpSceneCheckKeys.quickPush,
      GpSceneCheckKeys.editor,
    ];
    // 反向：6 个档位按钮确实不存在（硬编码字面量，不引用已删工厂）。
    for (final int lv in <int>[5, 4, 3, 2, 0, -1]) {
      expect(find.byKey(ValueKey<String>('gpSceneCheckKp/level/$lv')),
          findsNothing,
          reason: '删 6 档后第 $lv 档按钮不得残留');
    }
    _expectUniform(tester, 'gpScene 保留 2 个按钮', keys, _kScene);

    // 位置断言不放宽：两按钮仍分列（沿用原「不同 left 值」口径）。
    final Set<double> lefts = <double>{
      for (final Key k in keys) tester.getRect(find.byKey(k)).left,
    };
    expect(lefts.length, 2,
        reason: 'gpScene 两个保留按钮仍分两列，实测列左边界 $lefts');

    // 网格不塌陷：两按钮四边不越 root。
    final Rect grid = tester.getRect(find.byKey(GpSceneCheckKeys.root));
    expect(grid.width, greaterThan(0));
    expect(grid.height, greaterThan(0));
    for (final Key k in keys) {
      final Rect r = tester.getRect(find.byKey(k));
      expect(r.left, greaterThanOrEqualTo(grid.left - 0.5));
      expect(r.right, lessThanOrEqualTo(grid.right + 0.5));
      expect(r.bottom, lessThanOrEqualTo(grid.bottom + 0.5));
    }

    expect(tester.takeException(), isNull);
  });

  // ========================================================
  // P16-07 · 玩家场景检定
  // ========================================================
  testWidgets('P16-07 gpPlScene：技能 chip 高恒 32 且宽 ≥90（数据驱动）；检定按钮满宽',
      (WidgetTester tester) async {
    final f = await _boot(tester, w: 1280, h: 800, seat: 'p1');

    // 造 3 个不同长度的技能名，证明 chip 宽度是**数据驱动**而不是定宽。
    await f.controllerOf('p1').sendIntent(RoomIntent.char, <String, Object?>{
      'id': 'c_p1',
      'name': 'p1的调查员',
      'sheet': <String, Object?>{
        'name': 'p1的调查员',
        'attrs': <String, Object?>{'str': 50, 'dex': 56, 'pow': 60},
        'status': <String, Object?>{
          'currentHP': 12,
          'maxHP': 12,
          'currentMP': 10,
          'maxMP': 10,
          'currentSAN': 56,
          'maxSAN': 99,
        },
        'skills': <Object?>[
          <String, Object?>{'name': '侦查', 'value': 70},
          <String, Object?>{'name': '图书馆使用', 'value': 65},
          <String, Object?>{'name': '闪避', 'value': 45},
        ],
      },
    });
    await tester.pump();

    final List<Key> chips = <Key>[
      GpSceneCheckPlKeys.skill('侦查'),
      GpSceneCheckPlKeys.skill('图书馆使用'),
      GpSceneCheckPlKeys.skill('闪避'),
    ];
    final List<Size> all = _allSizes(tester, chips);
    expect(all.length, 3, reason: 'gpPlScene：3 个技能 chip 都必须渲染，实测 $all');
    for (final Size s in all) {
      expect(s.height, _kSceneChipH,
          reason: 'gpPlScene 技能 chip 高度必须恒为 32（不定宽，但高度必须一致），'
              '实测 $all');
      expect(s.width, greaterThanOrEqualTo(_kSceneChipMinW),
          reason: 'gpPlScene 技能 chip 宽度必须 ≥90（minSize 口径），实测 $all');
    }
    // 长技能名必须真的把 chip 撑宽（否则「≥90」是恒真的假证据）。
    expect(all.toSet().length, greaterThanOrEqualTo(2),
        reason: 'gpPlScene 技能 chip 宽度必须随技能名变化，实测 $all');

    // 检定按钮：本栏唯一长按钮 → 满宽 ×40。
    final Rect cell =
        tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlScene)));
    final Size roll = tester.getSize(find.byKey(GpSceneCheckPlKeys.roll));
    expect(roll.height, 40, reason: 'gpPlScene 检定按钮高度必须 40，实测 $roll');
    expect(roll.width, closeTo(cell.width - 28, 0.5),
        reason: 'gpPlScene 检定按钮必须拉满内容宽（${cell.width - 28}），'
            '实测 ${roll.width}');

    expect(tester.takeException(), isNull);
  });

  // ========================================================
  // P16-08 · 玩家角色卡
  // ========================================================
  testWidgets('P16-08 gpPlCharCard 4 短全 104×40、2 长彼此等宽且满宽',
      (WidgetTester tester) async {
    await _boot(tester, w: 1280, h: 800, seat: 'p1');

    _expectUniform(
      tester,
      'gpPlCharCard 4 个短按钮',
      <Key>[
        GpPlCharCardKeys.stateBtn,
        RoomKeys.action('aid.apply'),
        GpPlCharCardKeys.itemsBtn,
        GpPlCharCardKeys.aiBtn,
      ],
      _kChar,
    );

    final Size save = tester.getSize(find.byKey(GpPlCharCardKeys.saveBtn));
    final Size adv =
        tester.getSize(find.byKey(RoomKeys.action('madness.advance')));
    expect(<Size>{save, adv}.length, 1,
        reason: 'gpPlCharCard 两个长按钮必须彼此等宽等高，实测 save=$save adv=$adv');
    expect(save.height, 40, reason: 'gpPlCharCard 长按钮高度必须 40，实测 $save');

    final Rect cell =
        tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlCharCard)));
    expect(save.width, closeTo(cell.width - 28, 0.5),
        reason: 'gpPlCharCard 长按钮必须拉满内容宽（${cell.width - 28}），'
            '实测 ${save.width}');

    expect(tester.takeException(), isNull);
  });

  // ========================================================
  // P16-09 · 状态条
  // ========================================================
  testWidgets('P16-09 gpStatus 同意 / 拒绝 尺寸相等，且中间留出 6dp',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: RoomRequestCard(
              id: 'p16r',
              title: '状态变更请求',
              text: 'p1：aid.apply',
              onReply: (bool _) {},
            ),
          ),
        ),
      ),
    ));

    final Rect agree = tester.getRect(find.byKey(GpStatusKeys.agree('p16r')));
    final Rect reject = tester.getRect(find.byKey(GpStatusKeys.reject('p16r')));
    expect(agree.size, reject.size,
        reason: 'gpStatus 同意 / 拒绝必须等宽等高，实测 '
            'agree=${agree.size} reject=${reject.size}');
    expect(agree.height, 36,
        reason: 'gpStatus 按钮高度保持 36（本批不改尺寸），实测 ${agree.height}');
    expect(reject.left - agree.right, greaterThanOrEqualTo(6),
        reason: 'gpStatus 两按钮之间必须留 ≥6dp 间距，实测 '
            '${reject.left - agree.right}');
    expect(tester.takeException(), isNull);
  });

  // ========================================================
  // P16-10 · 信息流 trailing + 聊天输入行
  // ========================================================
  testWidgets('P16-10 gpFeeds trailing 两个 44×32；输入行 3 个 48×44',
      (WidgetTester tester) async {
    final f = await _boot(tester, w: 1280, h: 800, seat: 'p1');

    // 两条别人的消息：第 1 条让 tracker 登记基线（首次不闪），第 2 条才闪。
    for (final String text in <String>['第一条', '第二条']) {
      await f.controllerOf('p2').sendIntent(
            RoomIntent.chat,
            <String, Object?>{'text': text},
          );
      await tester.pump();
      await tester.pump();
    }

    // 记录栏 + 聊天栏各一个「新」角标 ⇒ 加上两个全屏按钮，一共 4 个 44×32。
    _expectUniform(
      tester,
      'gpFeeds trailing（新 / 全屏，记录栏 + 聊天栏）',
      <Key>[
        GpFeedsKeys.fullscreen,
        GpFeedsKeys.flash(FeedPane.record),
        GpFeedsKeys.flash(FeedPane.chat),
      ],
      _kTrailing,
    );

    _expectUniform(
      tester,
      'gpFeeds 聊天输入行 3 个图标',
      <Key>[
        GpFeedsKeys.aiRp,
        GpFeedsKeys.chatFullscreen,
        GpFeedsKeys.send,
      ],
      _kChatIcon,
    );

    // 行内小按钮（花幸运 / 推动 132×30）按规格**保持原样**，不在本批统一范围内。
    expect(tester.takeException(), isNull);
  });

  // ========================================================
  // P16-11 · 私密栏 trailing
  // ========================================================
  testWidgets('P16-11 gpPrivates trailing 44×32', (WidgetTester tester) async {
    await _boot(tester, w: 1280, h: 800, seat: 'p1');
    _expectUniform(
      tester,
      'gpPrivates trailing（全屏）',
      <Key>[GpPrivatesKeys.fullscreen],
      _kTrailing,
    );
    // 「新」角标与全屏共用同一个常量（P16-03 已钉住 trailingSm == 44×32）；
    // 它只在有新私密信息时渲染，构造成本高，故此处不做几何断言。
    expect(tester.takeException(), isNull);
  });

  // ========================================================
  // P16-12 · 反向总闸门：六档屏 × 两角色，整页零异常
  // ========================================================
  testWidgets('P16-12 六档屏 × KP/玩家 整页 takeException == null（定宽后无 overflow）',
      (WidgetTester tester) async {
    const List<List<double>> screens = <List<double>>[
      <double>[320, 568], // 小屏下限
      <double>[360, 640], // 常见安卓竖屏
      <double>[412, 915], // 荣耀 Magic9
      <double>[780, 320], // 手机横屏（折叠档的极矮档）
      <double>[1280, 800], // 通用平板横屏
      <double>[1524, 1016], // 荣耀平板 GT2 Pro
    ];
    for (final List<double> s in screens) {
      for (final String seat in <String>[kHostSeat, 'p1']) {
        await _boot(tester, w: s[0], h: s[1], seat: seat);
        expect(tester.takeException(), isNull,
            reason: '${s[0].toInt()}×${s[1].toInt()} / $seat：'
                '定宽后不允许出现 RenderFlex overflow');
      }
    }
  });

  // ========================================================
  // P16-13 · 满宽长按钮判据
  // ========================================================
  testWidgets('P16-13 三个「满宽长按钮」的宽度恰好等于所在栏位内容宽',
      (WidgetTester tester) async {
    // KP 侧：gpKpLeft 上传素材（KP-10 后工具窄栏已无上传按钮，故只剩这一个）
    final f = await _boot(tester, w: 1280, h: 800);
    double contentW(RoomSlot slot) =>
        tester.getRect(find.byKey(RoomKeys.keyOfSlot(slot))).width - 28;

    // 正向反证：满宽长按钮的判定对象已从 4 个降为 3 个。
    expect(find.byKey(GpKpToolsKeys.upload), findsNothing,
        reason: 'KP-10：gpKpTools 不再有上传素材按钮');

    f.localOf(kHostSeat).setTab('left', 1);
    await tester.pump();
    expect(
      tester.getSize(find.byKey(GpKpLeftKeys.upload)).width,
      closeTo(contentW(RoomSlot.gpKpLeft), 0.5),
      reason: 'gpKpLeft 上传素材未拉满（内容宽 ${contentW(RoomSlot.gpKpLeft)}）',
    );

    // 玩家侧：gpPlCharCard「保存到已保存」/ gpPlScene 检定按钮
    await _boot(tester, w: 1280, h: 800, seat: 'p1');
    expect(
      tester.getSize(find.byKey(GpPlCharCardKeys.saveBtn)).width,
      closeTo(contentW(RoomSlot.gpPlCharCard), 0.5),
      reason: 'gpPlCharCard 保存按钮未拉满'
          '（内容宽 ${contentW(RoomSlot.gpPlCharCard)}）',
    );
    expect(
      tester.getSize(find.byKey(GpSceneCheckPlKeys.roll)).width,
      closeTo(contentW(RoomSlot.gpPlScene), 0.5),
      reason: 'gpPlScene 检定按钮未拉满'
          '（内容宽 ${contentW(RoomSlot.gpPlScene)}）',
    );

    expect(tester.takeException(), isNull);
  });

  // ========================================================
  // P16-14/15/16 · 大字体不溢出（QA 阻塞项回归闸门）
  // ========================================================
  // 定宽 `RoomTapTile` 是紧约束，`RoomTap` 内部的 Text 默认跟随系统字号：
  // 字号一放大，内容就撑破定宽 ⇒ `RenderFlex overflowed`。
  // `clampBtnText` 把**按钮子树**的 textScaler 钳到 1.0 后，按钮文字与默认
  // 字号逐像素一致，因此这些用例一旦绿，就同时证明了「大字体下按钮内部
  // 零溢出」。
  // ★ 同时**反向自证钳制是局部的**（第 ⑤ 步）：面板标题 / 正文必须真的按
  //   倍率变大。若有人把 clamp 抬到整页 / Theme / MaterialApp 层，⑤ 立刻红
  //   —— 面板正文是用户要放大看的，绝不能连带钳掉。
  // ★ 钳制只加在 `RoomTapTile` 内部 + 工具栏那个不定宽缩放钮；`gpPlScene`
  //   的技能 chip（`minSize` 内容自适应）、`gpMapStage`、`gpFeeds` 的花幸运/
  //   推动、`gpPlNotes` 行尾这些**本来就不定宽**的裸 `RoomTap` 一律不钳。
  // ★ 未用 `ClipRect`（静默裁切比溢出更糟，QA 会判红），也未动
  //   `RoomTap` 内部的 `Text`（`maxLines`/`ellipsis` 需要改 `room_panel_kit.dart`）。
  //
  // ★ 判据分两层：**本批按钮子树**用「内部 Row 子件宽和 vs 实宽」逐按钮量
  //   （比整页 `takeException` 更精确，能指名道姓说是哪个按钮溢出）；
  //   **整页**异常另有过滤闸门（见第 ④ 步）。
  //
  // ★ 大字体溢出的三处**既有**问题（QA 第 2 轮逐行定位），本轮裁决：
  //     ① `gp_combat_list.dart` 的 trailing 双按钮（`下一个行动 ▶` + `＋加入`）
  //        —— ×1.3/×1.5/×2.0 分别撑 `SectionBox` 标题行 4.6 / 31 / 96dp。
  //        **已修**：两个 RoomTap 各包 `clampBtnText`（尺寸/文案/结构不动）。
  //     ② `gp_kp_left.dart` 的 `ConfirmTwice`「清除笔迹与标记」
  //        —— ×2.0 下需 205.75、容器 173.52，溢 32dp。
  //        **已修**：调用点包 `clampBtnText`（`ConfirmTwice` 类体不动）。
  //     ③ `room_panel_kit.dart:291` `PanelTabs._label` 的 `Row(icon + 文字)`
  //        —— ×2.0 + 1280×800 + KP 时溢 **3.1dp**。
  //        **本轮不修，留 P17**：只 3.1px、只在 ×2.0 极端档触发，而修它必须
  //        破「`room_panel_kit.dart` 0 字节变更」这条硬边界，`PanelTabs` 又是
  //        全局共用件，风险收益比不划算。P17 修法：`_label` 的 Row 包
  //        `clampBtnText`。
  //        本文件把它登记为**已知项**（见 `_kKnownP17`）：第 ④ 步会把它从
  //        「整页异常」里过滤出来**单独记录并断言出现位置**，其余任何整页
  //        异常仍然算失败 —— 没有放宽成「整页异常一律不管」。
  for (final double scale in <double>[1.3, 1.5, 2.0]) {
    testWidgets(
        'P16-1x[×$scale 字号] 6 档屏 × KP/玩家 共 12 格：按钮子树零 overflow',
        (WidgetTester tester) async {
      // 6 档真实机型 dp（320 是小屏下限，780×320 是极矮横屏）。
      const List<List<double>> screens = <List<double>>[
        <double>[320, 640],
        <double>[360, 640],
        <double>[412, 915],
        <double>[780, 320],
        <double>[1280, 800],
        <double>[1524, 1016],
      ];
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final List<String> failures = <String>[];
      for (final List<double> s in screens) {
        for (final String seat in <String>[kHostSeat, 'p1']) {
          // ★ 整页异常用 `FlutterError.onError` 自己收：`takeException()` 给回的
          //   `FlutterError` 消息里**只有**「overflowed by N pixels」，不含出错
          //   widget 的 `file:line`，无法把「已知项」和「新回归」区分开。
          final List<String> pageErrs = <String>[];
          final void Function(FlutterErrorDetails)? prevOnError =
              FlutterError.onError;
          FlutterError.onError = (FlutterErrorDetails d) => pageErrs.add(d.toString());
          await _boot(tester, w: s[0], h: s[1], seat: seat);
          FlutterError.onError = prevOnError;
          while (tester.takeException() != null) {} // 兜底清空
          final String cell =
              '${s[0].toInt()}×${s[1].toInt()} / $seat / ×$scale';

          // ① 先证明字号真的生效（避免「测了个假的大字体」）：
          //    工具栏槽位在 clampBtnText **之外**，textScaler 必须是真倍率。
          final BuildContext toolbarCtx = tester.element(
              find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpToolbar)));
          final double scaled13 =
              MediaQuery.of(toolbarCtx).textScaler.scale(13);
          expect(scaled13, closeTo(13 * scale, 0.01),
              reason: '$cell：textScaler 未生效（13dp 缩放后应为 ${13 * scale}，'
                  '实测 $scaled13）—— 这条失败说明用例造错了场景，不是产品缺陷');

          // ② 再证明按钮子树里的文字被钳回 1.0（缩放钮不在 tile 里，也是钳的）。
          final BuildContext btnCtx =
              tester.element(find.byKey(RoomKeys.gpZoomReset));
          expect(MediaQuery.of(btnCtx).textScaler.scale(13), closeTo(13, 0.01),
              reason: '$cell：按钮子树未被 clampBtnText 钳制（13dp 应恒为 13，'
                  '实测 ${MediaQuery.of(btnCtx).textScaler.scale(13)}）');

          // ③ 逐个 P16 按钮查内部 Row：子件宽之和 > 实宽 即为 RenderFlex 溢出。
          for (final MapEntry<String, List<Key>> g in _p16ButtonGroups().entries) {
            for (final String bad in _innerOverflows(tester, g.key, g.value)) {
              failures.add('$cell → $bad');
            }
          }

          // ④ ★ 整页异常：白名单已清零（PanelTabs 溢出实测消失），
          //    现在**任何**整页异常都算失败（比原先更严，不是放宽）。
          for (final String t in pageErrs) {
            failures.add('$cell → 整页溢出：${_shortErr(t)}');
          }

          // ⑤ ★ 反向自证：钳制**只**作用于按钮子树。
          //    面板标题 / 聊天正文这类非按钮文字必须**真的按倍率变大** ——
          //    如果谁把 clamp 抬到整页 / Theme / MaterialApp 层，这条立刻红。
          //    只在 1280×800 / KP 这一格量一次（同一棵树，代价最小）。
          if (s[0] == 1280 && seat == kHostSeat) {
            await _expectPanelTextNotClamped(tester, scale, cell);
          }
        }
      }
      expect(failures, isEmpty,
          reason: '大字体 ×$scale 出现按钮内部溢出 / 整页溢出：$failures');
    });
  }

  // ========================================================
  // P16-17 · gpPlCharCard 固定 2 列（QA 观察项 1）
  // ========================================================
  testWidgets('P17 C-1：gpPlCharCard 2 个短按钮单行（AI RP / 急救已删，P16-17 收口）',
      (WidgetTester tester) async {
    // P16-17 原口径「4 个短按钮 2+2」已随 P17 C-1 收口：AI RP（aiBtn）与
    // 急救（act/aid.apply）两个按钮从角色卡删除（真入口在聊天行 / 更多
    // 工具）。剩余固定 2 列网格 = stateBtn + itemsBtn 同行、saveBtn 次行。
    const List<List<double>> screens = <List<double>>[
      <double>[320, 640],
      <double>[360, 640],
      <double>[412, 915],
      <double>[780, 320],
      <double>[1280, 800],
      <double>[1524, 1016],
    ];
    final List<Key> keys = <Key>[
      GpPlCharCardKeys.stateBtn,
      GpPlCharCardKeys.itemsBtn,
    ];
    for (final List<double> s in screens) {
      await _boot(tester, w: s[0], h: s[1], seat: 'p1');
      final String cell = '${s[0].toInt()}×${s[1].toInt()}';
      // ★ P17 C-1（负向）：两个被删按钮三档屏都不渲染。
      expect(find.byKey(GpPlCharCardKeys.aiBtn), findsNothing,
          reason: 'P17 C-1：$cell 角色卡不再渲染 AI RP 按钮');
      expect(find.byKey(RoomKeys.action('aid.apply')), findsNothing,
          reason: 'P17 C-1：$cell 角色卡不再渲染急救按钮');
      final List<Rect> rects = <Rect>[
        for (final Key k in keys) tester.getRect(find.byKey(k)),
      ];
      // 列数 = 不同 left 的个数；行数 = 不同 centerY 的个数。
      final Set<double> lefts = <double>{for (final Rect r in rects) r.left};
      final Set<double> centers = <double>{
        for (final Rect r in rects) r.center.dy,
      };
      expect(lefts.length, 2,
          reason: 'gpPlCharCard @$cell：2 个短按钮必须同行 2 列，实测列左边界 $lefts');
      expect(centers.length, 1,
          reason: 'gpPlCharCard @$cell：2 个短按钮必须同行（单行 2 列），'
              '实测行中心 $centers');
    }
    expect(tester.takeException(), isNull);
  });

  // ========================================================
  // ★ P12 R1（「更强或等价」）：只**新增**两处新文案的正向断言。
  //   本文件既有 44 条定宽 / 钳制断言一字未改、一条未删、未 skip。
  // ========================================================
  group('P12 R1 · 清除文案（新增正向断言）', () {
    testWidgets('工具窄栏「清除标记」findsOneWidget，旧文案全无',
        (WidgetTester tester) async {
      await _boot(tester, w: 1280, h: 800);
      expect(find.text('清除标记'), findsOneWidget,
          reason: '★ R1：工具窄栏新文案恰好一个');
      expect(find.text('清除笔迹'), findsNothing,
          reason: '旧文案已删');
      expect(find.text('放玩家'), findsNothing,
          reason: 'KP-2a：与「放单位」重复的按钮已删');
      expect(tester.takeException(), isNull);
    });

    // ★ P13 MAP-1：地图 tab 与其面板（含「清空标记层」）整块删除。
    //   核心不变量「工具窄栏清除标记 findsOneWidget」逐字保留，
    //   已删控件改正向断言 findsNothing，不属放宽。
    testWidgets('MAP-1：地图 tab / 清空标记层 findsNothing，清除标记仍唯一',
        (WidgetTester tester) async {
      await _boot(tester, w: 1280, h: 800);
      expect(find.text('地图'), findsNothing,
          reason: '★ MAP-1：地图 tab 必须删除');
      expect(find.text('清空标记层'), findsNothing,
          reason: '★ MAP-1：随地图面板一起删除');
      expect(find.text('NPC·怪物'), findsOneWidget);
      expect(find.text('素材'), findsOneWidget);
      expect(find.text('清除笔迹与标记'), findsNothing,
          reason: '旧文案已删');
      expect(find.text('清除标记'), findsOneWidget,
          reason: '★ 工具窄栏核心文案仍恰好一个');
      expect(tester.takeException(), isNull);
    });
  });
}
