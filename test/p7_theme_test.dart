// ============================================================
// p7_theme_test.dart — 双皮肤（暗色「深渊」/ 亮色「羊皮卷」）+ 首页四宫格
//
// 这一批最容易「看起来做了、其实没生效」的两个点，各用一条硬断言守住：
//
//   ① 换肤：设置里点了亮色，**叶子节点的颜色必须真的变**。
//      只断言 `SettingsRepo.theme == 'light'` 是不够的 —— 那只能证明值存下来了，
//      证明不了 `Palette` 门面与 ThemeData 真的跟着换（`static final` 缓存、
//      忘记 notifyListeners、MaterialApp 没重建，任何一种都能让它悄悄不生效）。
//      所以这里直接读某个 Text 的 `style.color`，切前切后各断言一次。
//
//   ② 首页入口：四个必须**平铺且全部在首屏**，不允许再出现横向滚动列表。
//
// 另外补 `Palette` 门面的取值、`buildTheme` 的两种亮度、以及
// `isDarkTheme` 的「没选过 = 暗色」口径（不改旧版 `theme` 键的默认值）。
// ============================================================

import 'dart:math' as math;

import 'package:dice_realm/repo/settings_repo.dart';
import 'package:dice_realm/theme.dart';
import 'package:dice_realm/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// 每个用例前后都把全局门面复位，避免顺序依赖
void _resetPalette() => Palette.useBrightness(Brightness.dark);

void main() {
  setUp(_resetPalette);
  tearDown(_resetPalette);

  group('Palette 门面', () {
    test('切换皮肤后取值跟着变，复位后回到暗色', () {
      _resetPalette();
      expect(Palette.bg, AppPalette.dark.bg);
      expect(Palette.isDark, isTrue);

      Palette.use(AppPalette.light);
      expect(Palette.isDark, isFalse);
      expect(Palette.bg, AppPalette.light.bg);
      expect(Palette.text, AppPalette.light.text);
      // 强调金在浅底上必须变深，否则金色文字会糊掉
      expect(Palette.goldStr, AppPalette.light.goldStr);
      expect(Palette.goldStr, isNot(AppPalette.dark.goldStr));

      _resetPalette();
      expect(Palette.bg, AppPalette.dark.bg);
    });

    test('两套皮肤的正文色对各自底色都有足够对比（不靠肉眼）', () {
      // 用相对亮度比算 WCAG 对比度，正文要求 ≥ 4.5:1
      double lum(Color c) {
        double ch(double v) {
          final s = v / 255;
          return s <= 0.03928
              ? s / 12.92
              : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
        }

        return 0.2126 * ch(c.r * 255) +
            0.7152 * ch(c.g * 255) +
            0.0722 * ch(c.b * 255);
      }

      double contrast(Color fg, Color bg) {
        final a = lum(fg);
        final b = lum(bg);
        final hi = a > b ? a : b;
        final lo = a > b ? b : a;
        return (hi + 0.05) / (lo + 0.05);
      }

      for (final AppPalette p in <AppPalette>[
        AppPalette.dark,
        AppPalette.light,
      ]) {
        expect(
          contrast(p.text, p.surface),
          greaterThanOrEqualTo(4.5),
          reason: '${p.brightness} 的正文压在卡片上对比度不足',
        );
        expect(
          contrast(p.text, p.bg),
          greaterThanOrEqualTo(4.5),
          reason: '${p.brightness} 的正文压在页面底色上对比度不足',
        );
      }
    });

    test('buildTheme 按亮度产出不同的 scaffold 底色与文字色', () {
      final dark = buildTheme(Brightness.dark);
      final light = buildTheme(Brightness.light);

      expect(dark.scaffoldBackgroundColor, AppPalette.dark.bg);
      expect(light.scaffoldBackgroundColor, AppPalette.light.bg);
      expect(dark.scaffoldBackgroundColor, isNot(light.scaffoldBackgroundColor));

      // 亮色的正文必须比暗色深（用亮度比较，避免写死十六进制）
      final darkText = dark.textTheme.bodyLarge!.color!;
      final lightText = light.textTheme.bodyLarge!.color!;
      expect(lightText.computeLuminance(), lessThan(darkText.computeLuminance()));

      // 顺带把门面也带成对应皮肤，避免「主题换了色板没换」
      expect(Palette.bg, AppPalette.light.bg);
      _resetPalette();
    });
  });

  group('SettingsRepo.isDarkTheme 口径', () {
    test('从没选过 → 暗色；旧版 theme 键仍是 light（两个键互不干扰）', () async {
      final s = await newMemorySettings();
      // defaultSettings() 一定会把 theme 预填成 'light'，所以皮肤开关必须
      // 走独立键 uiTheme；否则所有老用户升级后会被动变成亮色。
      expect(s.isDarkTheme, isTrue, reason: '没选过应默认暗色');
      expect(s.theme, 'light', reason: '旧版契约不能动');
    });

    test('选了亮色 → false 且落盘；改回暗色 → true', () async {
      final storage = MemorySettingsStorage();
      final s = SettingsRepo(storage: storage);
      await s.load();

      s.isDarkTheme = false;
      await s.save();
      expect(s.isDarkTheme, isFalse);

      // 换一个实例重新读盘，确认真的持久化了
      final s2 = SettingsRepo(storage: storage);
      await s2.load();
      expect(s2.isDarkTheme, isFalse);

      s2.isDarkTheme = true;
      await s2.save();
      final s3 = SettingsRepo(storage: storage);
      await s3.load();
      expect(s3.isDarkTheme, isTrue);
    });
  });

  group('设置页换肤（真机路径）', () {
    testWidgets('点「亮色」：MaterialApp 主题与叶子文字色都真的变了', (tester) async {
      final settings = await newMemorySettings();
      await pumpApp(tester, settings: settings);
      _resetPalette();

      // 进设置页：先开右上角「数据」菜单，再点「⚙ 设置」
      await tester.tap(find.byKey(const Key('home_menu')));
      await tester.pumpAndSettle();
      await tapKey(tester, 'menu_settings');
      expect(find.byType(SettingsPage), findsOneWidget);

      // 切换前：暗色
      final before = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(before.theme!.scaffoldBackgroundColor, AppPalette.dark.bg);

      final labelBefore = tester.widget<Text>(find.text('暗色 · 深渊'));
      expect(labelBefore.style!.color, AppPalette.dark.text);

      // 点亮色
      await tester.tap(find.byKey(const Key('settings_theme_light')));
      await tester.pumpAndSettle();

      // 切换后：主题与叶子同时变 —— 这是本组的关键断言
      final after = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(after.theme!.scaffoldBackgroundColor, AppPalette.light.bg);

      final labelAfter = tester.widget<Text>(find.text('暗色 · 深渊'));
      expect(
        labelAfter.style!.color,
        AppPalette.light.text,
        reason: '叶子节点没跟着换色，说明 Palette 没被重建（只存了设置值）',
      );

      // 值也落到了仓库
      expect(settings.isDarkTheme, isFalse);
    });

    testWidgets('再点回「暗色」能切回去（不是单向开关）', (tester) async {
      final settings = await newMemorySettings();
      settings.isDarkTheme = false;
      await settings.save();
      _resetPalette();

      await pumpApp(tester, settings: settings);
      await tester.tap(find.byKey(const Key('home_menu')));
      await tester.pumpAndSettle();
      await tapKey(tester, 'menu_settings');

      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!
            .scaffoldBackgroundColor,
        AppPalette.light.bg,
      );

      await tester.tap(find.byKey(const Key('settings_theme_dark')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!
            .scaffoldBackgroundColor,
        AppPalette.dark.bg,
      );
      expect(settings.isDarkTheme, isTrue);
    });
  });

  group('首页四个入口平铺', () {
    testWidgets('四个入口全部可见，且没有横向滚动列表', (tester) async {
      await pumpApp(tester);
      _resetPalette();

      for (final String k in <String>[
        'fab_room',
        'fab_ai_create',
        'entry_random',
        'fab_new_card',
      ]) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: '缺少入口 $k');
      }

      // 「不要滑动」= 入口区不再有横向 ListView
      expect(
        find.byWidgetPredicate(
          (Widget w) => w is ListView && w.scrollDirection == Axis.horizontal,
        ),
        findsNothing,
        reason: '入口区不应再有横向滚动',
      );
    });

    testWidgets('四个入口都在首屏内（不需要滚动即可点到）', (tester) async {
      await pumpApp(tester);
      _resetPalette();

      final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      for (final String k in <String>[
        'fab_room',
        'fab_ai_create',
        'entry_random',
        'fab_new_card',
      ]) {
        final Rect r = tester.getRect(find.byKey(Key(k)));
        expect(
          r.bottom,
          lessThanOrEqualTo(screen.height),
          reason: '$k 掉出首屏，用户要滚动才看得到',
        );
        expect(r.top, greaterThanOrEqualTo(0), reason: '$k 顶部被裁');
        expect(r.width, greaterThan(0));
        expect(r.height, greaterThan(0));
      }
    });

    testWidgets('四张卡两两成行：同一行的顶边对齐、宽度相等', (tester) async {
      await pumpApp(tester);
      _resetPalette();

      final r1 = tester.getRect(find.byKey(const Key('fab_room')));
      final r2 = tester.getRect(find.byKey(const Key('fab_ai_create')));
      final r3 = tester.getRect(find.byKey(const Key('entry_random')));
      final r4 = tester.getRect(find.byKey(const Key('fab_new_card')));

      expect(r1.top, moreOrLessEquals(r2.top, epsilon: 0.5));
      expect(r3.top, moreOrLessEquals(r4.top, epsilon: 0.5));
      expect(r1.width, moreOrLessEquals(r2.width, epsilon: 0.5));
      expect(r3.width, moreOrLessEquals(r4.width, epsilon: 0.5));
      expect(r1.width, moreOrLessEquals(r3.width, epsilon: 0.5));
      expect(r1.left, lessThan(r2.left));
      expect(r3.top, greaterThan(r1.bottom), reason: '第二行应在第一行下方');
    });
  });
}
