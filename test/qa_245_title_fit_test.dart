// ============================================================
// qa_245_title_fit_test.dart — QA 独立验证（2.45.0 / build 115）
//
// 验的是用户点单的那条缺陷：320dp 极窄屏下最长标题
// 「沈砚清 获得 1 项新的疯狂症状」被省略号吃掉约 2 个字。
//
// ★ 与工程师的 `test/p21b_banner_title_fit_test.dart` 的分工（刻意不同角度）：
//   1) 本文件对每一档宽度都做**两条独立路径**的复算并互相印证：
//      · 渲染路径：`RenderParagraph.didExceedMaxLines` + 真实排版结果；
//      · 解析路径：拿 `EventBannerCopy` 的**原始字符串**、按文档化字号
//        （26 / height 1.2、15 / height 1.3）另起一个 `TextPainter` 重排。
//      两条路径行数不一致 → 直接失败。
//   2) 本文件**不写文案字面量**：全部经 `EventBannerCopy` 生成。
//   3) 本文件独立复算工程师的两条附加结论（combatStartSubtitle 需 3 行、
//      deathSubtitle 只需 2 行），不照抄。
//   4) 本文件把「不许撑爆屏幕」当一等公民：最坏叠加时量文字块**整块**矩形
//      是否落在屏内（`maxLines` 调大最典型的副作用就是矮屏黄黑条纹）。
//   5) ★ 本文件用**真实 App 主题** `buildTheme()` 挂载（既有 p21/p21b 用的是
//      `ThemeData.dark(useMaterial3: true)`，其 bodyMedium 带
//      `letterSpacing: 0.25`，而产品 `lib/theme.dart#_textTheme()` 的
//      bodyMedium **不带** letterSpacing）。横幅的 `Text` 未显式设
//      letterSpacing，会继承 `DefaultTextStyle` —— 也就是说**每行能放几个字
//      受主题影响**。所以本文件以真实主题为主口径，另加一条「M3 默认主题
//      （letterSpacing 0.25）下也不许截断」的余量用例，两头都锁。
//
// 尺寸换算（与实现注释同口径，并由「契约」用例锁住）：
//   文字块内容宽 = min(720, 屏宽 - 2×32) - 2×28(padding) - 2×1(边框)
//   320 → min(720, 256) - 58 = 198dp
//   360 → 238 / 375 → 253 / 400 → 278 / 412 → 290 / 860 → 662
// ============================================================

import 'dart:math' as math;

import 'package:dice_realm/theme.dart' show buildTheme;
import 'package:dice_realm/ui/art.dart' show Art;
import 'package:dice_realm/ui/room/event_banner_copy.dart' show EventBannerCopy;
import 'package:dice_realm/ui/room/widgets/room_event_banner.dart'
    show RoomBannerItem, RoomEventBanner, RoomEventBannerKeys;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// ------------------------------------------------------------
// 契约常量（**故意写成字面量**）
//
// 这些值是「320dp 下要 3 行」这一整套推导的前提。若实现里改了它们，
// 下面的 `布局契约常量` 用例会先红 —— 那是**应当**红的：行数结论必须重算。
// ------------------------------------------------------------

/// 文字块最大宽度（平板横屏不许拉成一条长句）。
const double _kMaxTextWidth = 720;

/// 文字块与屏幕左右边缘的留白。
const double _kTextGutter = 32;

/// 文字底衬的左右 padding。
const double _kBackdropPaddingH = 28;

/// 文字底衬的边框宽度（`Container` 的 border 会吃布局宽度，1×2）。
const double _kBackdropBorder = 1;

/// 标题字号 / 行高倍数（实现里是 `fontSize: 26, height: 1.2`）。
const double _kTitleFontSize = 26;
const double _kTitleHeight = 1.2;

/// 副行字号 / 行高倍数（`fontSize: 15, height: 1.3`）。
const double _kSubFontSize = 15;
const double _kSubHeight = 1.3;

/// 一条待测横幅文案。
class _Copy {
  const _Copy(this.label, this.title, this.subtitle);

  /// 报告 / 用例名里用的模板名。
  final String label;

  /// 标题（由 `EventBannerCopy` 生成）。
  final String title;

  /// 副行；空串表示该模板没有副行。
  final String subtitle;
}

/// 全部 9 个文案模板（标题与副行成对）。
///
/// 覆盖 5 类关键事件 + `combatStartSubtitle` 的「满名字 / 少名字」两种形态
/// + `madnessSubtitle` 的三种文案分支（轮数 / 不定 / 若干轮）。
final List<_Copy> _allCopy = <_Copy>[
  _Copy(
    'combatStart/5人',
    EventBannerCopy.combatStartTitle(),
    EventBannerCopy.combatStartSubtitle(
        <String>['沈砚清', '顾长夜', '白露', '林间', '第五人']),
  ),
  _Copy(
    'combatStart/2人',
    EventBannerCopy.combatStartTitle(),
    EventBannerCopy.combatStartSubtitle(<String>['沈砚清', '顾长夜']),
  ),
  _Copy(
    'combatEnd',
    EventBannerCopy.combatEndTitle(),
    EventBannerCopy.combatEndSubtitle(),
  ),
  _Copy(
    'death',
    EventBannerCopy.deathTitle('沈砚清'),
    EventBannerCopy.deathSubtitle(),
  ),
  _Copy(
    'ripped',
    EventBannerCopy.rippedTitle('沈砚清'),
    EventBannerCopy.rippedSubtitle(),
  ),
  _Copy(
    'madness/临时N轮',
    EventBannerCopy.madnessTitle('沈砚清', '临时疯狂'),
    EventBannerCopy.madnessSubtitle('临时疯狂', rounds: 3),
  ),
  _Copy(
    'madness/不定',
    EventBannerCopy.madnessTitle('沈砚清', '不定疯狂'),
    EventBannerCopy.madnessSubtitle('不定疯狂'),
  ),
  _Copy(
    'madness/若干轮',
    EventBannerCopy.madnessTitle('沈砚清', '临时疯狂'),
    EventBannerCopy.madnessSubtitle('临时疯狂'),
  ),
  _Copy(
    'newSymptom（最长标题）',
    EventBannerCopy.newSymptomTitle('沈砚清'),
    '',
  ),
];

/// 6 档被测宽度（竖屏 5 档 + 横屏矮屏 1 档）。
const List<List<double>> _screens = <List<double>>[
  <double>[320, 568],
  <double>[360, 640],
  <double>[375, 667],
  <double>[400, 860],
  <double>[412, 915],
  <double>[860, 400],
];

/// 最坏叠加用的一条「3 行标题 + 3 行副行」。
final String _kLongestTitle = EventBannerCopy.newSymptomTitle('沈砚清');
final String _kLongestSubtitle = EventBannerCopy.combatStartSubtitle(
    <String>['沈砚清', '顾长夜', '白露', '林间', '第五人']);

String _sizeLabel(List<double> s) => '${s[0].toInt()}×${s[1].toInt()}';

// ------------------------------------------------------------
// 布局辅助
// ------------------------------------------------------------

/// 把测试视图改成 w×h 逻辑像素（dpr = 3，与真机 `useRoomScreen` 同口径）。
void _useScreen(WidgetTester tester, double w, double h) {
  tester.view.physicalSize = Size(w * 3, h * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 挂一条遮罩（用真实 `RoomEventBanner`，量到的才是线上那一份排版）。
///
/// [theme] 默认取**产品真实主题**（`buildTheme(Brightness.dark)`）；
/// 传 `ThemeData.dark(useMaterial3: true)` 可模拟「主题自带 letterSpacing」
/// 的更坏环境。
/// [textScaler] 非空时在**外层**注入放大后的 textScaler，用于验证本控件
/// 内部的 `withClampedTextScaling(1.0)` 没被破坏。
Future<void> _pumpBanner(
  WidgetTester tester, {
  required String title,
  required String subtitle,
  ThemeData? theme,
  TextScaler? textScaler,
}) async {
  Widget app = MaterialApp(
    theme: theme ?? buildTheme(Brightness.dark),
    home: Scaffold(
      body: RoomEventBanner(
        banner: RoomBannerItem(
          1,
          title,
          subtitle,
          Art.e18BannerMadness,
          DateTime(2026, 10, 9),
        ),
      ),
    ),
  );
  if (textScaler != null) {
    app = MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: app,
    );
  }
  await tester.pumpWidget(app);
  await tester.pump();
}

/// `RoomEventBanner` 在 320dp 下的**最坏主题**：M3 默认（letterSpacing 0.25）。
final ThemeData _kWorstTheme = ThemeData.dark(useMaterial3: true);

/// 取某一行（标题 / 副行）真正参与排版的 `RenderParagraph`。
RenderParagraph _para(WidgetTester tester, Key key) {
  final Finder richText =
      find.descendant(of: find.byKey(key), matching: find.byType(RichText));
  expect(richText, findsOneWidget, reason: '该行必须真的渲染出 RichText');
  return tester.renderObject<RenderParagraph>(richText);
}

/// 文字块（底衬 `Container`）的矩形 —— 「整块是否在屏内」按它量。
Rect _textBlockRect(WidgetTester tester, Key titleKey) {
  final Finder block = find.ancestor(
    of: find.byKey(titleKey),
    matching: find.byType(Container),
  );
  expect(block.evaluate().length, 1,
      reason: '文字底衬应当唯一（量整块矩形时不允许有歧义）');
  return tester.getRect(block.first);
}

/// 按实现契约算出「文字块内容宽」（屏宽 → 可排版宽度）。
double _contentWidth(double screenWidth) {
  final double blockWidth =
      math.min(_kMaxTextWidth, screenWidth - 2 * _kTextGutter);
  return blockWidth - 2 * _kBackdropPaddingH - 2 * _kBackdropBorder;
}

/// 解析路径的排版样式：字号 / 行高 / 字重取**文档化常量**，
/// 字体族 / 字间距 / 行距分布 / locale 取「该段落实际继承到的环境值」。
///
/// 为什么后者要跟随环境：`Text` 没有显式设 `letterSpacing`，它会从
/// `DefaultTextStyle` 继承 —— 这是**主题**的量，不是本控件实现的量。
/// 只要它和渲染路径用的是同一个值，两条路径就可比；若用默认 0 去算
/// 一个 letterSpacing 0.25 的环境，会得出「复算 1 行 / 实际 2 行」的假冲突。
TextStyle _analyticStyleOf(RenderParagraph p) {
  final TextStyle? inherited = p.text.style;
  final bool isTitle = (inherited?.fontSize ?? 0) >= _kTitleFontSize;
  return TextStyle(
    fontSize: isTitle ? _kTitleFontSize : _kSubFontSize,
    height: isTitle ? _kTitleHeight : _kSubHeight,
    fontWeight: isTitle ? FontWeight.w700 : FontWeight.w500,
    fontFamily: inherited?.fontFamily,
    letterSpacing: inherited?.letterSpacing,
    wordSpacing: inherited?.wordSpacing,
    leadingDistribution: inherited?.leadingDistribution,
  );
}

/// 解析路径：拿**原始文案字符串**重排，返回行数（不受 maxLines 影响）。
int _analyticNeededLines(
  String text, {
  required TextStyle style,
  required TextDirection direction,
  required TextScaler scaler,
  required Locale? locale,
  required double maxWidth,
}) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: direction,
    textScaler: scaler,
    locale: locale,
    maxLines: null,
  )..layout(maxWidth: maxWidth);
  final int lines = painter.computeLineMetrics().length;
  painter.dispose();
  return lines;
}

/// 解析路径：同上的**总高度**。
double _analyticHeight(
  String text, {
  required TextStyle style,
  required TextDirection direction,
  required TextScaler scaler,
  required Locale? locale,
  required double maxWidth,
}) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: direction,
    textScaler: scaler,
    locale: locale,
    maxLines: null,
  )..layout(maxWidth: maxWidth);
  final double h = painter.height;
  painter.dispose();
  return h;
}

/// 渲染路径：这一段文字在它**实际拿到的排版宽度**下本来需要几行。
int _neededLines(RenderParagraph p) {
  final TextPainter painter = TextPainter(
    text: p.text,
    textDirection: p.textDirection,
    textScaler: p.textScaler,
    locale: p.locale,
    maxLines: null,
  )..layout(maxWidth: p.constraints.maxWidth);
  final int lines = painter.computeLineMetrics().length;
  painter.dispose();
  return lines;
}

/// 断言「这一行完整可见」，并交叉核对两条独立路径的行数。
void _expectLineFits(
  WidgetTester tester,
  Key key, {
  required String text,
  required bool isTitle,
  required double screenWidth,
  required String what,
  required String sizeLabel,
}) {
  final RenderParagraph p = _para(tester, key);
  final double expectedWidth = _contentWidth(screenWidth);
  final double fontSize = isTitle ? _kTitleFontSize : _kSubFontSize;
  final double height = isTitle ? _kTitleHeight : _kSubHeight;

  // ① 排版宽度必须与契约换算一致（否则后面所有行数结论都失去基准）。
  expect(
    p.constraints.maxWidth,
    closeTo(expectedWidth, 0.01),
    reason: '$sizeLabel 下「$what」的排版宽度应为 $expectedWidth dp'
        '（屏宽 $screenWidth - 2×gutter - 2×padding - 2×border），'
        '实际 ${p.constraints.maxWidth}',
  );

  // ② 文档化字号 / 行高没被改动（行数结论依赖它们）。
  final TextStyle inherited = p.text.style!;
  expect(inherited.fontSize, fontSize,
      reason: '$sizeLabel 下「$what」字号应为 $fontSize');
  expect(inherited.height, height,
      reason: '$sizeLabel 下「$what」行高倍数应为 $height');

  // ③ 渲染路径：实际需要几行、是否被省略号截断。
  final int rendered = _neededLines(p);

  // ④ 解析路径：拿原始文案重排，行数必须与渲染路径一致。
  final int analytic = _analyticNeededLines(
    text,
    style: _analyticStyleOf(p),
    direction: p.textDirection,
    scaler: p.textScaler,
    locale: p.locale,
    maxWidth: expectedWidth,
  );
  expect(
    analytic,
    rendered,
    reason: '$sizeLabel 下「$what」两条独立路径行数应当一致：'
        '按文案复算 $analytic 行，实际渲染 $rendered 行',
  );

  // ⑤ 行为断言（主断言）：不许截断。
  expect(
    p.didExceedMaxLines,
    isFalse,
    reason: '★ $sizeLabel 下「$what」必须完整显示：本宽度需要 $rendered 行，'
        '上限 maxLines=${p.maxLines} → 被省略号截断了',
  );

  // ⑥ 结构性说明：上限至少覆盖实际行数。
  expect(
    p.maxLines,
    greaterThanOrEqualTo(rendered),
    reason: '$sizeLabel 下「$what」需要 $rendered 行，maxLines=${p.maxLines} 太紧',
  );

  // ⑦ 占位高度 = 实际行数 × 行高（不是被 maxLines 撑满），
  //    每行允许 ±1dp 的像素取整误差。
  expect(
    p.size.height,
    closeTo(rendered * fontSize * height, rendered * 1.0 + 0.5),
    reason: '$sizeLabel 下「$what」占位高度应约等于 $rendered 行 × $fontSize × '
        '$height，实际 ${p.size.height}',
  );
}

void main() {
  // ============================================================
  // 0. 契约：布局常量（本批所有行数推导的前提）
  // ============================================================
  group('qa245 · 布局契约常量', () {
    test('文字块上限 720 / 留白 32 未被悄悄改动', () {
      expect(RoomEventBanner.maxTextWidth, _kMaxTextWidth,
          reason: '文字块 maxWidth 变了 → 内容宽换算要重算，本文件所有行数结论失效');
      expect(RoomEventBanner.textGutter, _kTextGutter,
          reason: '左右留白变了 → 内容宽换算要重算');
    });

    test('320/360/375/400/412/860 六档内容宽换算', () {
      expect(_contentWidth(320), 198);
      expect(_contentWidth(360), 238);
      expect(_contentWidth(375), 253);
      expect(_contentWidth(400), 278);
      expect(_contentWidth(412), 290);
      expect(_contentWidth(860), 662,
          reason: '860 宽下文字块被封顶在 720（不是拉满一屏）');
    });
  });

  // ============================================================
  // 1. 320dp 核心回归（本批修的就是这条）
  // ============================================================
  group('qa245 · 320dp 核心回归', () {
    testWidgets('★ 320×568：最长标题完整显示，且独立复算确认「确实需要 3 行」',
        (WidgetTester tester) async {
      _useScreen(tester, 320, 568);
      final String title = EventBannerCopy.newSymptomTitle('沈砚清');
      await _pumpBanner(tester, title: title, subtitle: '');

      _expectLineFits(
        tester,
        RoomEventBannerKeys.title(1),
        text: title,
        isTitle: true,
        screenWidth: 320,
        what: '最长标题「$title」',
        sizeLabel: '320×568',
      );

      final RenderParagraph p = _para(tester, RoomEventBannerKeys.title(1));

      // ★ 独立复算：这条标题在 198dp 宽下**本来就需要 3 行**。
      //   若它是 2 行，说明「吃掉 2 个字」是假问题 —— 这里必须红。
      expect(_neededLines(p), 3,
          reason: '前提核对失败：320dp 下「$title」应需 3 行；'
              '若为 2 行则本批修的是假问题，须退回工程师');
      expect(_neededLines(p), greaterThan(2),
          reason: '★ 证明这是**真缺陷**：2 行上限在该宽度下必定吃字');

      // 实际占位必须体现出 3 行（≈93dp），不是 2 行的 ≈62dp。
      expect(p.size.height, greaterThan(2 * _kTitleFontSize * _kTitleHeight),
          reason: '实际占位高度 ${p.size.height} 必须超过 2 行高');

      expect(tester.takeException(), isNull, reason: '320dp 下不许抛渲染异常');
    });

    testWidgets('★ 320×568：战斗开始副行（满 4 名字 + 等 N 人）确实需要 3 行且完整显示',
        (WidgetTester tester) async {
      _useScreen(tester, 320, 568);
      final String subtitle = EventBannerCopy.combatStartSubtitle(
          <String>['沈砚清', '顾长夜', '白露', '林间', '第五人']);
      await _pumpBanner(
          tester, title: EventBannerCopy.combatStartTitle(), subtitle: subtitle);

      _expectLineFits(
        tester,
        RoomEventBannerKeys.subtitle(1),
        text: subtitle,
        isTitle: false,
        screenWidth: 320,
        what: '战斗开始副行「$subtitle」',
        sizeLabel: '320×568',
      );

      // ★ 工程师结论①的独立复算：这条副行在 320dp 下**确实需要 3 行**。
      expect(_neededLines(_para(tester, RoomEventBannerKeys.subtitle(1))), 3,
          reason: '工程师称 combatStartSubtitle 在 320dp 下需 3 行 —— '
              '若实测不是 3 行，则「副行 2→3」缺乏依据，须报出');
      expect(tester.takeException(), isNull);
    });

    testWidgets('★ 320×568：deathSubtitle 确实只需 2 行（副行 3 行上限对它是余量）',
        (WidgetTester tester) async {
      _useScreen(tester, 320, 568);
      final String subtitle = EventBannerCopy.deathSubtitle();
      await _pumpBanner(
          tester, title: EventBannerCopy.deathTitle('沈砚清'), subtitle: subtitle);

      _expectLineFits(
        tester,
        RoomEventBannerKeys.subtitle(1),
        text: subtitle,
        isTitle: false,
        screenWidth: 320,
        what: '死亡副行「$subtitle」',
        sizeLabel: '320×568',
      );

      // ★ 工程师结论②的独立复算：只需 2 行，2 行上限本来就不吃字。
      //   也就是说「副行提到 3 行」的动因**不是**它，而是 combatStartSubtitle。
      final RenderParagraph p =
          _para(tester, RoomEventBannerKeys.subtitle(1));
      expect(_neededLines(p), 2,
          reason: '工程师称 deathSubtitle 在 320dp 下只需 2 行 —— 若实测 3 行，'
              '则它不是余量而是受害者，结论要改');
      // 3 行上限没有让它凭空多占一行（高度仍是 2 行）。
      expect(p.size.height,
          lessThan(3 * _kSubFontSize * _kSubHeight - 5),
          reason: '★ maxLines: 3 只是上限：deathSubtitle 实际仍只占 2 行高');
      expect(tester.takeException(), isNull);
    });

    testWidgets('★ 320×568：9 个副行模板里只有 combatStart/5人 需要 3 行',
        (WidgetTester tester) async {
      _useScreen(tester, 320, 568);
      final Map<String, int> needed = <String, int>{};

      for (final _Copy c in _allCopy) {
        if (c.subtitle.trim().isEmpty) continue;
        await _pumpBanner(tester, title: c.title, subtitle: c.subtitle);
        needed[c.label] =
            _neededLines(_para(tester, RoomEventBannerKeys.subtitle(1)));
        expect(tester.takeException(), isNull, reason: '${c.label} 不许溢出');
      }

      expect(needed['combatStart/5人'], 3,
          reason: '副行唯一的 3 行动因：$needed');
      for (final String label in needed.keys) {
        if (label == 'combatStart/5人') continue;
        expect(needed[label], lessThanOrEqualTo(2),
            reason: '「$label」在 320dp 下只需 ${needed[label]} 行，'
                '不是本批副行改动的动因（$needed）');
      }
    });

    testWidgets('★ 320×568：主题自带 letterSpacing（M3 默认 0.25）时也不许截断',
        (WidgetTester tester) async {
      // 横幅的 Text 没设 letterSpacing，会继承 DefaultTextStyle；本用例把
      // 「每行更窄」的最坏主题也跑一遍，确保 3 行上限还有余量。
      _useScreen(tester, 320, 568);
      await _pumpBanner(
        tester,
        title: _kLongestTitle,
        subtitle: _kLongestSubtitle,
        theme: _kWorstTheme,
      );

      _expectLineFits(
        tester,
        RoomEventBannerKeys.title(1),
        text: _kLongestTitle,
        isTitle: true,
        screenWidth: 320,
        what: 'letterSpacing 0.25 主题 / 最长标题',
        sizeLabel: '320×568',
      );
      _expectLineFits(
        tester,
        RoomEventBannerKeys.subtitle(1),
        text: _kLongestSubtitle,
        isTitle: false,
        screenWidth: 320,
        what: 'letterSpacing 0.25 主题 / 最长副行',
        sizeLabel: '320×568',
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ============================================================
  // 2. 9 模板 × 6 宽度：逐条完整（标题与副行分开断言）
  // ============================================================
  group('qa245 · 9 模板 × 6 宽度全量完整显示', () {
    for (final List<double> size in _screens) {
      for (final _Copy c in _allCopy) {
        final String label = _sizeLabel(size);
        testWidgets('$label · ${c.label} · 标题/副行完整且无异常',
            (WidgetTester tester) async {
          _useScreen(tester, size[0], size[1]);
          await _pumpBanner(tester, title: c.title, subtitle: c.subtitle);

          _expectLineFits(
            tester,
            RoomEventBannerKeys.title(1),
            text: c.title,
            isTitle: true,
            screenWidth: size[0],
            what: '${c.label} / 标题「${c.title}」',
            sizeLabel: label,
          );

          if (c.subtitle.trim().isEmpty) {
            expect(find.byKey(RoomEventBannerKeys.subtitle(1)), findsNothing,
                reason: '${c.label} 没有副行 → 整块不渲染');
          } else {
            _expectLineFits(
              tester,
              RoomEventBannerKeys.subtitle(1),
              text: c.subtitle,
              isTitle: false,
              screenWidth: size[0],
              what: '${c.label} / 副行「${c.subtitle}」',
              sizeLabel: label,
            );
          }

          expect(tester.takeException(), isNull,
              reason: '$label / ${c.label} 不许溢出或抛异常');
        });
      }
    }
  });

  // ============================================================
  // 3. 不许撑爆屏幕（maxLines 调大最典型的副作用）
  // ============================================================
  group('qa245 · 文字块整块落在屏内（最坏叠加）', () {
    for (final List<double> size in <List<double>>[
      <double>[320, 568],
      <double>[320, 480],
      <double>[860, 400],
    ]) {
      final String label = _sizeLabel(size);
      testWidgets('★ $label：3 行标题 + 3 行副行整块都在屏内（无黄黑条纹）',
          (WidgetTester tester) async {
        _useScreen(tester, size[0], size[1]);
        await _pumpBanner(
            tester, title: _kLongestTitle, subtitle: _kLongestSubtitle);

        // ① 不许有 RenderFlex overflow / 任何渲染异常。
        expect(tester.takeException(), isNull,
            reason: '★ $label 下双 3 行不许溢出（黄黑条纹）');

        // ② 行数前提：窄屏（≤320）此处必须是 3 + 3（真正的最坏叠加），
        //    宽屏（860）则本来就 1 行 —— 两种都断言，防止用例在宽屏上
        //    「看着绿其实什么都没测到」。
        final RenderParagraph title =
            _para(tester, RoomEventBannerKeys.title(1));
        final RenderParagraph sub =
            _para(tester, RoomEventBannerKeys.subtitle(1));
        final int titleLines = _neededLines(title);
        final int subLines = _neededLines(sub);
        if (size[0] <= 320) {
          expect(titleLines, 3, reason: '★ 前提：$label 下标题应为 3 行');
          expect(subLines, 3, reason: '★ 前提：$label 下副行应为 3 行');
        } else {
          expect(titleLines, lessThanOrEqualTo(1),
              reason: '$label 宽屏下标题应为 1 行，实际 $titleLines');
          expect(subLines, lessThanOrEqualTo(1),
              reason: '$label 宽屏下副行应为 1 行，实际 $subLines');
        }

        // ③ 整块（含底衬 padding / 边框）四边都不越界。
        final Rect block = _textBlockRect(tester, RoomEventBannerKeys.title(1));
        expect(block.top, greaterThanOrEqualTo(0.0),
            reason: '★ $label：文字块顶边 ${block.top} 越出屏幕上沿');
        expect(block.bottom, lessThanOrEqualTo(size[1]),
            reason: '★ $label：文字块底边 ${block.bottom} 越出屏幕下沿 ${size[1]}');
        expect(block.left, greaterThanOrEqualTo(0.0),
            reason: '★ $label：文字块左边 ${block.left} 越界');
        expect(block.right, lessThanOrEqualTo(size[0]),
            reason: '★ $label：文字块右边 ${block.right} 越界');
      });
    }

    testWidgets('★ 320×568：最坏叠加时文字块高度 = 标题 + 8 + 副行 + 上下 padding + 边框',
        (WidgetTester tester) async {
      _useScreen(tester, 320, 568);
      await _pumpBanner(
          tester, title: _kLongestTitle, subtitle: _kLongestSubtitle);

      final RenderParagraph title =
          _para(tester, RoomEventBannerKeys.title(1));
      final RenderParagraph sub = _para(tester, RoomEventBannerKeys.subtitle(1));
      final Rect block = _textBlockRect(tester, RoomEventBannerKeys.title(1));

      // 段落高度 = 实际行数 × 行高（不因 maxLines: 3 而被撑满）。
      expect(title.size.height,
          closeTo(
            _analyticHeight(
              _kLongestTitle,
              style: _analyticStyleOf(title),
              direction: title.textDirection,
              scaler: title.textScaler,
              locale: title.locale,
              maxWidth: _contentWidth(320),
            ),
            2.0,
          ),
          reason: '标题占位高度必须等于「3 行文本」的高度');
      expect(sub.size.height,
          closeTo(
            _analyticHeight(
              _kLongestSubtitle,
              style: _analyticStyleOf(sub),
              direction: sub.textDirection,
              scaler: sub.textScaler,
              locale: sub.locale,
              maxWidth: _contentWidth(320),
            ),
            2.0,
          ),
          reason: '副行占位高度必须等于「3 行文本」的高度');

      final double expected = title.size.height +
          8 + // SizedBox(height: 8)
          sub.size.height +
          18 + // 底衬 padding top
          20 + // 底衬 padding bottom
          2; // 边框
      expect(block.height, closeTo(expected, 1.0),
          reason: '整块高度 = 标题 + 8 + 副行 + 上下 padding + 边框 = $expected');
    });
  });

  // ============================================================
  // 4. 宽屏不许被「为 320 的改动」带坏
  // ============================================================
  group('qa245 · 360dp 及以上不许凭空多一行', () {
    const String title = '沈砚清 获得 1 项新的疯狂症状';

    for (final List<double> size in <List<double>>[
      <double>[360, 640],
      <double>[375, 667],
      <double>[400, 860],
      <double>[412, 915],
      <double>[860, 400],
    ]) {
      final String label = _sizeLabel(size);
      testWidgets('★ $label：最长标题仍只需 ≤2 行（3 行只是上限）',
          (WidgetTester tester) async {
        _useScreen(tester, size[0], size[1]);
        await _pumpBanner(
            tester, title: EventBannerCopy.newSymptomTitle('沈砚清'), subtitle: '');

        final RenderParagraph p =
            _para(tester, RoomEventBannerKeys.title(1));
        final int needed = _neededLines(p);

        expect(needed, lessThanOrEqualTo(2),
            reason: '★ $label 下最长标题只需 $needed 行；若 >2 说明宽屏被带坏');
        expect(p.didExceedMaxLines, isFalse);

        // 关键：占位高度等于「实际行数」的高度，而不是 3 行 ——
        // 证明 `maxLines: 3` 只是上限、没有在正常尺寸上多占一行。
        final double actualLinesHeight = _analyticHeight(
          title,
          style: _analyticStyleOf(p),
          direction: p.textDirection,
          scaler: p.textScaler,
          locale: p.locale,
          maxWidth: _contentWidth(size[0]),
        );
        expect(p.size.height, closeTo(actualLinesHeight, 2.0),
            reason: '★ $label 下标题占位高度必须等于 $needed 行的高度'
                '（不是 3 行）：实际 ${p.size.height}，$needed 行应为 $actualLinesHeight');
        // 反向兜底：绝不许接近 3 行的高度。
        expect(p.size.height,
            lessThan(3 * _kTitleFontSize * _kTitleHeight - 5),
            reason: '★ $label 下标题不许被 maxLines: 3 撑成 3 行高');
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ============================================================
  // 5. textScaler 钳制（1.0）未被破坏 —— 系统大字号不进这个控件
  // ============================================================
  group('qa245 · 遮罩内字号固定（textScaler 钳 1.0）', () {
    for (final List<double> size in <List<double>>[
      <double>[320, 568],
      <double>[860, 400],
    ]) {
      final String label = _sizeLabel(size);
      testWidgets('★ $label：外层放大 3× 字号注入，遮罩内行数/字号不受影响',
          (WidgetTester tester) async {
        _useScreen(tester, size[0], size[1]);
        await _pumpBanner(
          tester,
          title: _kLongestTitle,
          subtitle: _kLongestSubtitle,
          textScaler: const TextScaler.linear(3.0),
        );

        final RenderParagraph title =
            _para(tester, RoomEventBannerKeys.title(1));
        final RenderParagraph sub =
            _para(tester, RoomEventBannerKeys.subtitle(1));

        // ① 段落拿到的 textScaler 必须是 1.0（钳制仍生效）。
        expect(title.textScaler.scale(10), closeTo(10.0, 0.001),
            reason: '★ 遮罩内 textScaler 必须钳在 1.0；实际放大到 '
                '${title.textScaler.scale(10) / 10}× —— 系统大字号会撑爆本控件');
        expect(sub.textScaler.scale(10), closeTo(10.0, 0.001));

        // ② 字号 / 行数不因外层放大而变。
        expect(title.text.style!.fontSize, _kTitleFontSize);
        expect(sub.text.style!.fontSize, _kSubFontSize);
        expect(
          _neededLines(title),
          _analyticNeededLines(_kLongestTitle,
              style: _analyticStyleOf(title),
              direction: title.textDirection,
              scaler: title.textScaler,
              locale: title.locale,
              maxWidth: _contentWidth(size[0])),
          reason: '★ 外层 3× 字号不得改变遮罩内行数',
        );
        expect(title.didExceedMaxLines, isFalse);
        expect(sub.didExceedMaxLines, isFalse);

        // ③ 字宽没被放大：段落宽度仍受文字块宽度约束。
        expect(title.size.width, lessThanOrEqualTo(size[0]));

        expect(tester.takeException(), isNull,
            reason: '外层放大字号后遮罩内不许溢出');
      });
    }
  });
}
