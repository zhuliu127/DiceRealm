// ============================================================
// p21b_banner_title_fit_test.dart — 关键事件遮罩「文字块排版」窄屏适配
//                                  （2.45.0 / build 115）
//
// 守的是 QA 遗留的一条（用户点单）：
//   320dp 极窄屏 + 最长标题「沈砚清 获得 1 项新的疯狂症状」会被省略号
//   吃掉约 2 个字；360dp 以上正常、不崩。
//
// 断言口径（重要）：
//   ★ 只验「行为」——`RenderParagraph.didExceedMaxLines` 是否真的超出，
//     以及「在该宽度下本来需要几行」（用同一个 `TextPainter` 重排一遍算出来）。
//     **不**把 `maxLines == 3` 当主要断言（那只是抄实现）；`maxLines >= 需要
//     的行数` 只作为附带的结构性说明。
//
// 为什么这一批同时把副行 2 → 3 行：
//   实测（见下面「全部模板」用例）`combatStartSubtitle` 在 320dp 下需要
//   3 行（「共 5 名行动者：沈砚清、顾长夜、白露、林间 等 5 人」），与标题
//   属同一类缺陷，一并修掉。最长的 `deathSubtitle` 在 320dp 下只需 2 行，
//   仍有用例锁住它完整可见。
//
// 尺寸换算（决定 3 行是否够用）：
//   文字块内容宽 = 屏宽 - 2×32(gutter) - 2×28(底衬 padding)
//                = 320 - 64 - 56 = 200dp
//   字号被 `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.0)` 钳死，
//   所以行数是确定的，不随系统字号漂移。
// ============================================================

import 'package:dice_realm/ui/art.dart' show Art;
import 'package:dice_realm/ui/room/event_banner_copy.dart' show EventBannerCopy;
import 'package:dice_realm/ui/room/widgets/room_event_banner.dart'
    show RoomBannerItem, RoomEventBanner, RoomEventBannerKeys;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一条待测的横幅文案（名字都取「沈砚清」——与 QA 报的现场一致）。
class _Copy {
  const _Copy(this.label, this.title, this.subtitle);

  /// 报告里用的模板名。
  final String label;

  /// 标题（已由 `EventBannerCopy` 生成，本用例**不手写字面量**）。
  final String title;

  /// 副行；空串表示该模板没有副行。
  final String subtitle;
}

/// 全部文案模板（覆盖 5 类事件 + `combatStartSubtitle` 的「满名字」形态）。
///
/// ★ 文案一律走 `EventBannerCopy` 的真源函数，避免测试里另写一套字面量
///   导致「测的字和线上显示的字不是同一个」。
final List<_Copy> _allCopy = <_Copy>[
  _Copy('combatStart / 5 人', EventBannerCopy.combatStartTitle(),
      EventBannerCopy.combatStartSubtitle(<String>[
        '沈砚清',
        '顾长夜',
        '白露',
        '林间',
        '第五人',
      ])),
  _Copy('combatStart / 2 人', EventBannerCopy.combatStartTitle(),
      EventBannerCopy.combatStartSubtitle(<String>['沈砚清', '顾长夜'])),
  _Copy('combatEnd', EventBannerCopy.combatEndTitle(),
      EventBannerCopy.combatEndSubtitle()),
  _Copy('death', EventBannerCopy.deathTitle('沈砚清'),
      EventBannerCopy.deathSubtitle()),
  _Copy('ripped', EventBannerCopy.rippedTitle('沈砚清'),
      EventBannerCopy.rippedSubtitle()),
  _Copy('madness / 临时 + N 轮',
      EventBannerCopy.madnessTitle('沈砚清', '临时疯狂'),
      EventBannerCopy.madnessSubtitle('临时疯狂', rounds: 3)),
  _Copy('madness / 不定', EventBannerCopy.madnessTitle('沈砚清', '不定疯狂'),
      EventBannerCopy.madnessSubtitle('不定疯狂')),
  _Copy('madness / 若干轮', EventBannerCopy.madnessTitle('沈砚清', '临时疯狂'),
      EventBannerCopy.madnessSubtitle('临时疯狂')),
  _Copy('newSymptom（最长标题）', EventBannerCopy.newSymptomTitle('沈砚清'), ''),
];

/// 一条「最坏情况」：最长标题 + 最长副行同时出现。
const String _kLongestTitle = '沈砚清 获得 1 项新的疯狂症状';
final String _kLongestSubtitle = '共 5 名行动者：沈砚清、顾长夜、白露、林间 等 5 人';

/// 把测试视图改成 w×h 逻辑像素（dpr = 3，与 `useRoomScreen` 同口径）。
void _useScreen(WidgetTester tester, double w, double h) {
  tester.view.physicalSize = Size(w * 3, h * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 直接挂一条遮罩（不需要房间夹具：本文件只验文字块排版）。
///
/// 用真实 `RoomEventBanner` 而不是自己拼一个 Text —— 否则量到的是
/// 「测试里的排版」而不是「线上那一份排版」。
Future<void> _pumpBanner(
  WidgetTester tester, {
  required int id,
  required String title,
  required String subtitle,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: RoomEventBanner(
          banner: RoomBannerItem(
            id,
            title,
            subtitle,
            Art.e18BannerMadness,
            DateTime(2026, 10, 9),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// 取某一行的 `RenderParagraph`（`Text` 内部真正的排版对象）。
RenderParagraph _para(WidgetTester tester, Key key) {
  final Finder richText = find.descendant(
    of: find.byKey(key),
    matching: find.byType(RichText),
  );
  expect(richText, findsOneWidget, reason: '该行必须真的渲染出 RichText');
  return tester.renderObject<RenderParagraph>(richText);
}

/// 同样的文字 / 字号，在同样宽度下**本来需要几行**（不受 maxLines 影响）。
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

/// 断言「这一行完整可见」——行为口径，不是 maxLines 口径。
void _expectFullyVisible(
  WidgetTester tester,
  Key key,
  String what, {
  required String sizeLabel,
}) {
  final RenderParagraph p = _para(tester, key);
  final int needed = _neededLines(p);
  expect(
    p.didExceedMaxLines,
    isFalse,
    reason: '★ $sizeLabel 下「$what」必须完整显示：本宽度需要 $needed 行，'
        '允许 ${p.maxLines} 行 → 被省略号截断了',
  );
  // 附带：上限至少覆盖实际需要的行数（结构性说明，不是主断言）。
  expect(p.maxLines, greaterThanOrEqualTo(needed),
      reason: '$sizeLabel 下「$what」需要 $needed 行，maxLines=${p.maxLines} 太紧');
}

void main() {
  group('关键事件遮罩 · 窄屏标题/副行完整显示（2.45.0）', () {
    // ------------------------------------------------------------
    // ① 核心回归：320dp 最长标题（改前必红）
    // ------------------------------------------------------------
    testWidgets('★ 320×568：最长标题「沈砚清 获得 1 项新的疯狂症状」完整显示',
        (WidgetTester tester) async {
      _useScreen(tester, 320, 568);
      await _pumpBanner(
        tester,
        id: 1,
        title: EventBannerCopy.newSymptomTitle('沈砚清'),
        subtitle: '',
      );

      _expectFullyVisible(
        tester,
        RoomEventBannerKeys.title(1),
        EventBannerCopy.newSymptomTitle('沈砚清'),
        sizeLabel: '320×568',
      );

      // 320dp 下内容宽 200dp：这条标题**确实需要 3 行**（2 行必被吃字），
      // 于是这条断言同时证明「3 行上限不是随手给的余量」。
      final RenderParagraph title =
          _para(tester, RoomEventBannerKeys.title(1));
      expect(_neededLines(title), 3,
          reason: '前提核对：320dp 下这条标题就是需要 3 行（QA 报的「吃掉 2 字」'
              '即由此而来；若这里不是 3，说明尺寸换算变了，需重新取值）');
      expect(title.constraints.maxWidth, closeTo(198, 0.5),
          reason: '文字块内容宽 = 320 - 2×32(gutter) - 2×28(底衬 padding) '
              '- 2×1(金色边框) = 198dp');

      expect(tester.takeException(), isNull, reason: '320dp 下不许抛任何渲染异常');
    });

    // ------------------------------------------------------------
    // ② 320dp 最长副行（用户担心的第二条）
    // ------------------------------------------------------------
    testWidgets('★ 320×568：最长副行 deathSubtitle「撕卡 —— 该角色只能通过聊天框交流」完整显示',
        (WidgetTester tester) async {
      _useScreen(tester, 320, 568);
      await _pumpBanner(
        tester,
        id: 1,
        title: EventBannerCopy.deathTitle('沈砚清'),
        subtitle: EventBannerCopy.deathSubtitle(),
      );

      _expectFullyVisible(
        tester,
        RoomEventBannerKeys.subtitle(1),
        EventBannerCopy.deathSubtitle(),
        sizeLabel: '320×568',
      );
      expect(tester.takeException(), isNull, reason: '320dp 下不许溢出');
    });

    // ------------------------------------------------------------
    // ③ 320dp 时**另一条**真的会超的副行：combatStartSubtitle（满名字）
    //    —— 这就是「副行也提到 3 行」的实测依据。
    // ------------------------------------------------------------
    testWidgets('★ 320×568：战斗开始副行（4 个名字 + 等 N 人）完整显示',
        (WidgetTester tester) async {
      _useScreen(tester, 320, 568);
      final String subtitle = EventBannerCopy.combatStartSubtitle(<String>[
        '沈砚清',
        '顾长夜',
        '白露',
        '林间',
        '第五人',
      ]);
      await _pumpBanner(
        tester,
        id: 1,
        title: EventBannerCopy.combatStartTitle(),
        subtitle: subtitle,
      );

      _expectFullyVisible(
        tester,
        RoomEventBannerKeys.subtitle(1),
        subtitle,
        sizeLabel: '320×568',
      );

      final RenderParagraph p = _para(tester, RoomEventBannerKeys.subtitle(1));
      expect(_neededLines(p), 3,
          reason: '前提核对：这条副行在 320dp 下需要 3 行 —— 若副行上限仍是 2 行，'
              '它和标题是同一类截断缺陷');
      expect(tester.takeException(), isNull);
    });

    // ------------------------------------------------------------
    // ④ 全部模板 × 320dp：逐条量（标题与副行分开断言）
    // ------------------------------------------------------------
    testWidgets('★ 320×568：9 个文案模板的标题与副行全部完整（无一条被吃字）',
        (WidgetTester tester) async {
      _useScreen(tester, 320, 568);

      int id = 0;
      for (final _Copy c in _allCopy) {
        id++;
        await _pumpBanner(tester, id: id, title: c.title, subtitle: c.subtitle);

        _expectFullyVisible(
          tester,
          RoomEventBannerKeys.title(id),
          '${c.label} / 标题「${c.title}」',
          sizeLabel: '320×568',
        );

        if (c.subtitle.trim().isEmpty) {
          expect(find.byKey(RoomEventBannerKeys.subtitle(id)), findsNothing,
              reason: '${c.label} 没有副行，整块不渲染');
        } else {
          _expectFullyVisible(
            tester,
            RoomEventBannerKeys.subtitle(id),
            '${c.label} / 副行「${c.subtitle}」',
            sizeLabel: '320×568',
          );
        }

        expect(tester.takeException(), isNull,
            reason: '${c.label} 在 320dp 下不许溢出 / 抛异常');
      }
    });

    // ------------------------------------------------------------
    // ⑤ 正常宽度不许被「为 320 的改动」带坏
    // ------------------------------------------------------------
    testWidgets('★ 360 / 375 / 400 / 412 宽：最长标题仍完整（一行都不许被吃）',
        (WidgetTester tester) async {
      // 屏幕尺寸 → 320dp 之上常见的那几档（含 411/412 的 Pixel 系）。
      for (final List<double> size in <List<double>>[
        <double>[360, 640],
        <double>[375, 667],
        <double>[400, 860],
        <double>[412, 915],
      ]) {
        final String label = '${size[0].toInt()}×${size[1].toInt()}';
        _useScreen(tester, size[0], size[1]);

        for (final _Copy c in _allCopy) {
          await _pumpBanner(
            tester,
            id: 1,
            title: c.title,
            subtitle: c.subtitle,
          );

          _expectFullyVisible(
            tester,
            RoomEventBannerKeys.title(1),
            '$label / ${c.label} / 标题「${c.title}」',
            sizeLabel: label,
          );
          if (c.subtitle.trim().isNotEmpty) {
            _expectFullyVisible(
              tester,
              RoomEventBannerKeys.subtitle(1),
              '$label / ${c.label} / 副行「${c.subtitle}」',
              sizeLabel: label,
            );
          }
          expect(tester.takeException(), isNull, reason: '$label 下不许溢出');
        }
      }
    });

    // ------------------------------------------------------------
    // ⑥ 横屏矮屏：最长标题 + 最长副行同时出现，只许更宽不许溢出
    // ------------------------------------------------------------
    testWidgets('★ 860×400 横屏：最长标题 + 最长副行同时出现 → 无 overflow 异常',
        (WidgetTester tester) async {
      _useScreen(tester, 860, 400);
      await _pumpBanner(
        tester,
        id: 1,
        title: _kLongestTitle,
        subtitle: _kLongestSubtitle,
      );

      expect(tester.takeException(), isNull,
          reason: '★ 横屏 400dp 高下不许 RenderFlex overflow（黄黑条纹）');

      _expectFullyVisible(tester, RoomEventBannerKeys.title(1), _kLongestTitle,
          sizeLabel: '860×400');
      _expectFullyVisible(
          tester, RoomEventBannerKeys.subtitle(1), _kLongestSubtitle,
          sizeLabel: '860×400');

      // 文字块（标题 + 副行）必须整块落在屏内。
      final Rect title = tester.getRect(find.byKey(RoomEventBannerKeys.title(1)));
      final Rect sub =
          tester.getRect(find.byKey(RoomEventBannerKeys.subtitle(1)));
      expect(title.top, greaterThanOrEqualTo(0.0));
      expect(sub.bottom, lessThanOrEqualTo(400.0),
          reason: '副行底边 ${sub.bottom} 不许超出 400dp 屏高');
    });

    // ------------------------------------------------------------
    // ⑦ 最坏叠加：320dp 下「3 行标题 + 3 行副行」也必须整块在屏内
    //    （3 行上限是否会撑爆矮屏 —— 用尺寸算，不靠感觉）
    // ------------------------------------------------------------
    testWidgets('★ 320×568 最坏叠加：3 行标题 + 3 行副行仍整块在屏内',
        (WidgetTester tester) async {
      _useScreen(tester, 320, 568);
      await _pumpBanner(
        tester,
        id: 1,
        title: _kLongestTitle,
        subtitle: _kLongestSubtitle,
      );

      expect(tester.takeException(), isNull,
          reason: '★ 320dp 下双 3 行不许溢出（黄黑条纹）');

      final RenderParagraph title =
          _para(tester, RoomEventBannerKeys.title(1));
      final RenderParagraph sub = _para(tester, RoomEventBannerKeys.subtitle(1));
      // 行高按像素取整（每行 ceil 到整数 dp），故用 ±2 的容差而不是精确值：
      // 标题 3 行 ≈ 3 × 26 × 1.2 = 93.6dp，副行 3 行 ≈ 3 × 15 × 1.3 = 58.5dp。
      expect(title.size.height, closeTo(3 * 26 * 1.2, 2.0),
          reason: '标题 3 行高 ≈ 3 × fontSize(26) × height(1.2) = 93.6dp');
      expect(sub.size.height, closeTo(3 * 15 * 1.3, 2.0),
          reason: '副行 3 行高 ≈ 3 × fontSize(15) × height(1.3) = 58.5dp');

      final Rect titleRect =
          tester.getRect(find.byKey(RoomEventBannerKeys.title(1)));
      final Rect subRect =
          tester.getRect(find.byKey(RoomEventBannerKeys.subtitle(1)));
      expect(titleRect.top, greaterThanOrEqualTo(0.0),
          reason: '★ 文字块居中后不许顶出屏幕上沿（实际 top=${titleRect.top}）');
      expect(subRect.bottom, lessThanOrEqualTo(568.0),
          reason: '★ 文字块居中后不许顶出屏幕下沿（实际 bottom=${subRect.bottom}）');
    });
  });
}
