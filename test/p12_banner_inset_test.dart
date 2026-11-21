// ============================================================
// test/p12_banner_inset_test.dart — 横幅标题别再压到素材里的星星
//
// 用户 2026-11-11 真机报（平板横屏，暗色/亮色主题都复现）：
//   首页「开始冒险」「角色档案」、规则选择页「规则系统」三个标题栏，
//   「图里的星星和第一个字重叠了」。用户还提醒「手机横屏好像也这样」。
//
// 根因：`a3_section_{adventure,archive}_6x1` 素材左侧约 2.4% 处**烧了一颗
// 四角星**，位置随横幅宽度线性右移；而 SectionBanner 的文字左边距原来是
// **固定 14dp**。手机竖屏（约 360dp）星星在 8.6dp 勉强错开，平板横屏 /
// 手机横屏（760dp+）星星移到 18dp 以上，就把第一个字压住了。
//
// 修法：`SectionBanner.titleInsetFor(width)` 按宽度取 5%（钳 18..46dp），
// 只挪文字，不动素材 / 布局结构 / 字号。
// ============================================================

import 'package:dice_realm/ui/art.dart' show Art;
import 'package:dice_realm/ui/widgets.dart' show SectionBanner;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _banner(double width) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: SectionBanner(
              title: '开始冒险',
              hint: '四个入口都在这',
              art: Art.sectionAdventure,
            ),
          ),
        ),
      ),
    );

void main() {
  test('旧值 14dp 在宽屏确实不够 —— 反向自证伪', () {
    // 不是放宽断言，而是证明这条用例真的能抓住用户报的那个 bug：
    // 760dp 横幅里星星中心在 18.2dp，加半颗星的宽度后 14dp 必然重叠。
    const double oldFixedInset = 14;
    const double width = 760;
    final double starCenter = width * SectionBanner.starInsetRatio;
    expect(oldFixedInset, lessThan(starCenter + 4),
        reason: '若旧值本来就安全，说明这条用例抓不住 bug');
  });

  test('titleInsetFor 在多档宽度下都越过素材左侧星星', () {
    for (final double w in <double>[320, 360, 480, 600, 760, 900, 1000, 1200]) {
      final double inset = SectionBanner.titleInsetFor(w);
      final double starCenter = w * SectionBanner.starInsetRatio;
      expect(inset, greaterThan(starCenter + 8),
          reason: '宽 ${w}dp 时文字边距 $inset 仍会撞上星星 $starCenter');
    }
  });

  for (final double w in <double>[360, 600, 760, 1000]) {
    testWidgets('${w.toInt()}dp 横幅：标题实际渲染位置在星星右侧',
        (WidgetTester tester) async {
      await tester.pumpWidget(_banner(w));
      await tester.pump();

      final double bannerLeft =
          tester.getTopLeft(find.byType(SectionBanner)).dx;
      final double textLeft = tester.getTopLeft(find.text('开始冒险')).dx;
      final double inset = textLeft - bannerLeft;
      // 用 LayoutBuilder 实际拿到的宽度：超宽时父约束会把它钳到屏幕宽，
      // 断言必须跟渲染口径一致，否则测的是「我以为的宽」而不是真实宽。
      final double actualW = tester.getSize(find.byType(SectionBanner)).width;
      final double starCenter = actualW * SectionBanner.starInsetRatio;

      expect(inset, greaterThan(starCenter + 8),
          reason: '宽 ${actualW}dp：文字距左 $inset，星星在 $starCenter —— 会重叠');
      expect(inset, SectionBanner.titleInsetFor(actualW),
          reason: '渲染出来的边距要等于单一真源 titleInsetFor()');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('亮色主题同样不重叠', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.light(useMaterial3: true),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 760,
            child: SectionBanner(
              title: '角色档案',
              hint: '已保存 0 张 · 长眠 0 位',
              art: Art.sectionArchiveLight,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    final double bannerLeft = tester.getTopLeft(find.byType(SectionBanner)).dx;
    final double inset = tester.getTopLeft(find.text('角色档案')).dx - bannerLeft;
    expect(inset, greaterThan(760 * SectionBanner.starInsetRatio + 8));
    expect(tester.takeException(), isNull);
  });
}
