// ============================================================
// p11_overlay_test.dart — P11「去掉发灰的蒙版」验收用例
//
// 用户原话（本轮）：
//   「英灵殿和已保存角色卡的背景图一个有字一个没字…你给弄成一样的…
//     而且这两个按钮感觉有一层暗色蒙板，让这两个 ui 显得灰蒙蒙的，去掉吧，
//     直接用原图显示。已保存的角色卡 UI 好像 4 个边角被裁切掉了（仅亮色
//     主题），不太好看，修复。」                        → 需求 2
//   「一键出卡出的角色栏位信息，背景图最上方的两条杠和该角色的默认头像、
//     名字、规则交叉了，不好看，改掉这里的背景图。」      → 需求 3
//   「亮色主题选择规则，『克苏鲁的呼唤第七版』这个卡片也灰灰的。去掉这层灰的
//     蒙板，直接显示原图。」                            → 需求 5
//
// 断言原则：每条都盯「结构 / 数值」，不盯"看着像"——
//   · 蒙版用**扫子树里所有黑色叠加的最大 alpha** 来量化，亮色必须≈0；
//   · 圆角用 ClipRRect 的半径数值 + 「不超过素材自身圆角」来锁；
//   · 候选卡顶部横线用**全透明带必须盖住头像行**来锁。
//
// 最后一条是**反向自证伪**：同一个检测器喂进旧版的 `Colors.black@0.78`，
// 必须判定为"重黑蒙版" —— 证明前面那些 findsNothing / <= 0.05 不是空断言。
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/repo/character_repo.dart';
import 'package:dice_realm/repo/settings_repo.dart';
import 'package:dice_realm/theme.dart';
import 'package:dice_realm/ui/art.dart';
import 'package:dice_realm/ui/create/rule_pick_page.dart';
import 'package:dice_realm/ui/random_create_page.dart';
import 'package:dice_realm/ui/summary_card.dart' show kCardFaceFade;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

void _resetPalette() => Palette.useBrightness(Brightness.dark);

/// 一张可落库的卡（属性齐备、已 recalc）
Character _card(String id, String name, {bool dead = false}) {
  final Character c = Character(newCharacter());
  c.raw['id'] = id;
  c.raw['characterName'] = name;
  c.basicInfo['age'] = 31;
  c.raw['age'] = 31;
  for (final String k in <String>[
    'str',
    'con',
    'siz',
    'dex',
    'app',
    'int',
    'pow',
    'edu',
    'luck',
  ]) {
    c.attributes[k] = 50;
  }
  recalc(c);
  if (dead) c.status['body'] = '死亡';
  return c;
}

/// 纯黑判据：RGB 三通道都几乎为 0
bool _isBlack(Color c) => c.r < 0.06 && c.g < 0.06 && c.b < 0.06;

/// 一个装饰会不会构成「重黑蒙版」：有渐变/底色，且最重的一档
/// **是黑色且 alpha > [threshold]**。
///
/// 这就是本文件的核心判据（也是"反向自证伪"那条用例喂的东西）：
/// 旧版横幅 = `black@0.55 → black@0.05`、旧版规则卡 = `black@0.78 → 0`，
/// 都必然被判为重黑蒙版；新版亮色是白色渐变，判不出来。
bool isHeavyBlackScrim(Decoration decoration, {double threshold = 0.5}) {
  if (decoration is! BoxDecoration) return false;
  final Color? color = decoration.color;
  if (color != null && _isBlack(color) && color.a > threshold) return true;
  final Gradient? gradient = decoration.gradient;
  if (gradient is LinearGradient) {
    for (final Color c in gradient.colors) {
      if (_isBlack(c) && c.a > threshold) return true;
    }
  }
  return false;
}

/// 子树里所有「黑色叠加」的最大 alpha（0 = 一点黑都没叠）
double maxBlackAlpha(WidgetTester tester, Finder root) {
  double worst = 0;
  void consider(Color c) {
    if (_isBlack(c) && c.a > worst) worst = c.a;
  }

  for (final DecoratedBox box in tester.widgetList<DecoratedBox>(
    find.descendant(of: root, matching: find.byType(DecoratedBox)),
  )) {
    final Decoration d = box.decoration;
    if (d is! BoxDecoration) continue;
    final Color? color = d.color;
    if (color != null) consider(color);
    final Gradient? g = d.gradient;
    if (g is LinearGradient) {
      for (final Color c in g.colors) {
        consider(c);
      }
    }
  }
  return worst;
}

/// 子树里存不存在「重黑蒙版」（供反向自证伪的负例使用）
bool subtreeHasHeavyBlackScrim(WidgetTester tester, Finder root) {
  for (final DecoratedBox box in tester.widgetList<DecoratedBox>(
    find.descendant(of: root, matching: find.byType(DecoratedBox)),
  )) {
    if (isHeavyBlackScrim(box.decoration)) return true;
  }
  return false;
}

/// 某个入口卡自己的 `ClipRRect` 半径
BorderRadiusGeometry _bannerRadius(WidgetTester tester, Key key) {
  final Finder clip = find
      .descendant(of: find.byKey(key), matching: find.byType(ClipRRect))
      .first;
  return tester.widget<ClipRRect>(clip).borderRadius;
}

void main() {
  setUp(_resetPalette);
  tearDown(_resetPalette);

  /* ==========================================================
   * 需求 2（上半）· 两张入口卡不许有黑色蒙版
   * ========================================================== */
  group('需求 2 · 入口卡不再压黑（改用原图）', () {
    testWidgets('亮色：两张卡都没有黑色叠加（最大黑 alpha <= 0.05）', (tester) async {
      final SettingsRepo settings = await newMemorySettings();
      settings.isDarkTheme = false;
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('alive01', '在世的'));
      await repo.save(_card('dead01', '长眠的', dead: true));
      await pumpApp(tester, repo: repo, settings: settings);
      expect(Palette.brightness, Brightness.light);

      for (final String k in <String>[
        'home_roster_saved',
        'home_roster_valhalla',
      ]) {
        final Finder banner = find.byKey(Key(k));
        expect(banner, findsOneWidget);
        expect(
          maxBlackAlpha(tester, banner),
          lessThanOrEqualTo(0.05),
          reason: '亮色下这张卡压了黑 → 就是用户说的"灰蒙蒙"（$k）',
        );
        expect(
          subtreeHasHeavyBlackScrim(tester, banner),
          isFalse,
          reason: '亮色下不许出现 black@0.5+ 的蒙版（$k）',
        );
      }
    });

    testWidgets('暗色：允许薄的黑色侧渐变，但不许 >=0.5 的重黑蒙版', (tester) async {
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('dead01', '长眠的', dead: true));
      await pumpApp(tester, repo: repo);
      expect(Palette.brightness, Brightness.dark);

      for (final String k in <String>[
        'home_roster_saved',
        'home_roster_valhalla',
      ]) {
        final Finder banner = find.byKey(Key(k));
        final double alpha = maxBlackAlpha(tester, banner);
        expect(
          alpha,
          greaterThan(0.2),
          reason: '暗色下左侧仍需要一层很薄的压暗来兜文字对比度（$k）',
        );
        expect(alpha, lessThan(0.5), reason: '暗色也不许整张压黑（$k）');
      }
    });

    testWidgets('两张卡都有可见标题（图里已经没字，App 这层是唯一的）', (tester) async {
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('alive01', '在世的'));
      await repo.save(_card('dead01', '长眠的', dead: true));
      await pumpApp(tester, repo: repo);

      // ★ P19：首页入口图标题改「角色卡」
      expect(find.text('角色卡'), findsOneWidget);
      expect(find.text('英灵殿'), findsOneWidget);
    });
  });

  /* ==========================================================
   * 需求 2（下半）· 四角不再被裁：两张卡同一个 Radii.md、不放大
   * ========================================================== */
  group('需求 2 · 入口卡圆角（四角不被削）', () {
    testWidgets('两张卡的 ClipRRect 半径完全相同', (tester) async {
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('dead01', '长眠的', dead: true));
      await pumpApp(tester, repo: repo);

      final BorderRadiusGeometry saved = _bannerRadius(
        tester,
        const Key('home_roster_saved'),
      );
      final BorderRadiusGeometry fallen = _bannerRadius(
        tester,
        const Key('home_roster_valhalla'),
      );
      expect(saved, fallen, reason: '两张入口必须同一个圆角');
    });

    testWidgets('半径是全站统一的 Radii.md，且没有放大/裁切（新素材方角全出血）', (
      tester,
    ) async {
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('dead01', '长眠的', dead: true));
      await pumpApp(tester, repo: repo);

      for (final String k in <String>[
        'home_roster_saved',
        'home_roster_valhalla',
      ]) {
        final Finder banner = find.byKey(Key(k));
        final BorderRadius radius = _bannerRadius(tester, Key(k)) as BorderRadius;
        /* 旧版按宽度算 w*0.045（≈14.8dp），而上一代素材自己带 ~9dp 圆角，
           裁切线比图上圆角还大 → 切进金框的弧里，四角像被削掉。
           新素材是方角全出血，ClipRRect 是唯一圆角来源，统一成 Radii.md。 */
        expect(radius.topLeft.x, Radii.md);
        expect(radius.topRight.x, Radii.md);
        // 不许靠放大/裁切去"凑"圆角
        expect(
          find.descendant(of: banner, matching: find.byType(OverflowBox)),
          findsNothing,
        );
        expect(
          find.descendant(of: banner, matching: find.byType(Transform)),
          findsNothing,
        );
        expect(
          find.descendant(of: banner, matching: find.byType(FittedBox)),
          findsNothing,
        );
      }
    });
  });

  /* ==========================================================
   * 需求 5 · 亮色规则卡不再灰蒙蒙
   * ========================================================== */
  group('需求 5 · 规则卡压层跟随皮肤', () {
    testWidgets('亮色：可选项无整体 Opacity，压层里一点黑都没有', (tester) async {
      final SettingsRepo settings = await newMemorySettings();
      settings.isDarkTheme = false;
      await pumpApp(
        tester,
        settings: settings,
        home: const RulePickPage(next: RulePickTarget.wizard),
      );
      expect(Palette.brightness, Brightness.light);

      final Finder card = find.byKey(const Key('rule_pick_coc7'));
      expect(card, findsOneWidget);
      // 可选项不许用透明度表达状态
      expect(
        find.descendant(of: card, matching: find.byType(Opacity)),
        findsNothing,
      );
      // 压层不许是黑的（亮色下压黑 = 灰蒙蒙）
      expect(
        maxBlackAlpha(tester, card),
        lessThanOrEqualTo(0.05),
        reason: '"克苏鲁的呼唤第七版"这张卡在亮色下还是黑的压层',
      );
      expect(subtreeHasHeavyBlackScrim(tester, card), isFalse);
    });

    testWidgets('暗色：压层仍是左侧黑渐变，但 <= 0.6 且右侧透明', (tester) async {
      await pumpApp(
        tester,
        home: const RulePickPage(next: RulePickTarget.wizard),
      );
      expect(Palette.brightness, Brightness.dark);

      final Finder card = find.byKey(const Key('rule_pick_coc7'));
      final Finder scrim = find.descendant(
        of: card,
        matching: find.byWidgetPredicate(
          (Widget w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).gradient is LinearGradient,
        ),
      );
      expect(scrim, findsOneWidget);
      final LinearGradient g =
          (tester.widget<DecoratedBox>(scrim).decoration as BoxDecoration)
                  .gradient!
              as LinearGradient;
      expect(g.colors.first.a, lessThanOrEqualTo(0.6));
      expect(g.colors.first.a, greaterThan(0.4));
      expect(g.colors.last.a, lessThan(0.05), reason: '右半张必须露原图');
    });
  });

  /* ==========================================================
   * 需求 3 · 一键出卡候选卡：图内双线金框不许穿到头部行
   *
   * 根因：底纹图 `b1_card_face_3x4` 自己画了一圈双线金框（实测横线在
   * 0.2% / 1.9% 图高处），`BoxFit.cover` 铺进偏高的候选卡后正好落在卡片顶端,
   * 从序号 / 头像 / 姓名 / 规则徽标背后穿过 —— 用户截图里那"两条杠"。
   * ========================================================== */
  group('需求 3 · 候选卡头部的两条杠', () {
    testWidgets('底纹顶部是一条全透明带，宽度覆盖图内金框（0.2% / 1.9%）', (tester) async {
      await pumpApp(
        tester,
        home: const RandomCreatePage(initialRuleId: 'coc7'),
      );

      // 遮罩本身：必须是 dstIn（"擦掉"底纹），不能是叠色
      final List<ShaderMask> masks = tester
          .widgetList<ShaderMask>(find.byType(ShaderMask))
          .toList();
      expect(masks, isNotEmpty, reason: '底纹必须套顶部淡出遮罩，否则金框横线会穿到头部');
      expect(masks.first.blendMode, BlendMode.dstIn);

      // 常量级：前两档 alpha 必须是 0，且全透明带盖过 1.9% 的金框线
      expect(kCardFaceFade.colors[0].a, 0);
      expect(kCardFaceFade.colors[1].a, 0);
      expect(
        kCardFaceFade.stops![1],
        greaterThan(0.019),
        reason: '图内第二条金线在 1.9% 图高，全透明带必须盖住它',
      );
      expect(kCardFaceFade.stops![2], greaterThanOrEqualTo(0.09));
    });

    testWidgets('候选卡：头像整块落在全透明带里（横线不可能穿过它）', (tester) async {
      await pumpApp(
        tester,
        home: const RandomCreatePage(initialRuleId: 'coc7'),
      );

      final Finder card = find.byKey(const Key('random_candidate_0'));
      final Rect cardRect = tester.getRect(card);
      final Finder mask = find.descendant(
        of: card,
        matching: find.byType(ShaderMask),
      );
      expect(mask, findsOneWidget);
      final Rect maskRect = tester.getRect(mask);
      // 底纹铺满整卡：只让开卡片自己那圈 1px 描边（上下各 1px，肉眼无感）
      expect(maskRect.top - cardRect.top, greaterThanOrEqualTo(0));
      expect(
        maskRect.top - cardRect.top,
        lessThanOrEqualTo(1.5),
        reason: '底纹铺满整卡，淡出带必须从卡片最上沿开始',
      );
      expect(maskRect.height, closeTo(cardRect.height, 2.5));

      // 头像 = 卡内第一个 ArtImage（头部行：序号 → 头像 → 姓名/徽标）
      final Rect avatar = tester.getRect(
        find.descendant(of: card, matching: find.byType(ArtImage)).first,
      );
      final double transparentBand = kCardFaceFade.stops![1] * maskRect.height;
      expect(
        avatar.top - maskRect.top,
        lessThan(transparentBand),
        reason: '头像顶部必须在这段全透明带内 —— 否则图内金框会从它背后穿过',
      );
    });

    testWidgets('头像 / 姓名 / 规则徽标的 Key 与位置未变（只动背景装饰）', (tester) async {
      await pumpApp(
        tester,
        home: const RandomCreatePage(initialRuleId: 'coc7'),
      );

      final Finder card = find.byKey(const Key('random_candidate_0'));
      // P7-D / P10 起按名依赖的两个徽标与按钮
      expect(
        find.descendant(
          of: card,
          matching: find.byKey(const Key('summary_rule_badge')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.byKey(const Key('result_use_this_0')),
        ),
        findsOneWidget,
      );
      // 头部行仍在卡片顶部：头像要比卡片中心更靠上
      final Rect avatar = tester.getRect(
        find.descendant(of: card, matching: find.byType(ArtImage)).first,
      );
      expect(avatar.top, lessThan(tester.getRect(card).center.dy));
    });
  });

  /* ==========================================================
   * 反向自证伪：检测器真的能抓到旧版的黑色蒙版
   * ========================================================== */
  group('反向自证伪 · 判据不是空断言', () {
    test('旧版横幅的 black@0.55→0.05 会被判成重黑蒙版', () {
      final BoxDecoration old = BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[
            Colors.black.withValues(alpha: 0.55),
            Colors.black.withValues(alpha: 0.05),
          ],
        ),
      );
      expect(isHeavyBlackScrim(old), isTrue);
    });

    test('旧版规则卡的 black@0.78→0.46→0 会被判成重黑蒙版', () {
      final BoxDecoration old = BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            Colors.black.withValues(alpha: 0.78),
            Colors.black.withValues(alpha: 0.46),
            Colors.black.withValues(alpha: 0),
          ],
        ),
      );
      expect(isHeavyBlackScrim(old), isTrue);
    });

    test('新版亮色的 white@0.38→0 不会被误判', () {
      final BoxDecoration now = BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            Colors.white.withValues(alpha: 0.38),
            Colors.white.withValues(alpha: 0),
          ],
        ),
      );
      expect(isHeavyBlackScrim(now), isFalse);
    });
  });
}
