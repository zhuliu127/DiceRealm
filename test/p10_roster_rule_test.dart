// ============================================================
// p10_roster_rule_test.dart — P10 视觉/行为修复的验收用例
//
// 需求 2 · 名册按入口过滤
//   「首页点已保存的角色卡后就只显示已保存的角色卡，不要显示英灵殿；
//     英灵殿也按照此逻辑」→ 只渲染对应那**一块**，另一块压根不构建。
// 需求 4 · 首页英灵殿入口图（P11 修订）
//   P10 时底图烧进了「英灵殿 / 英灵长眠于此 / 致敬每一位调查员」，App 不许
//   叠标题；P11 换成「不含文字、左侧留白」的新素材后，两张入口改成**同一套**
//   叠字（左侧标题 + 张数副标题），右下角浮动角标删除。
// 需求 5 · 暗色规则卡「边框在图片内部」（P11 已随新素材作废）
//   旧补丁是把图放大 1.753 倍裁掉图内 3:1 金框（`_innerCrops`）；新六张
//   `g_rules/r1|r2|r3`（2:1） 图内没有边框，补丁与表一起删除，改锁「原图直铺」。
// 需求 6 · 亮色规则卡「灰蒙蒙像不可选」
//   可选项不许有整体 Opacity；未开放项 opacity < 0.6 且灰度化。
//
// 每条都尽量"能证伪"：断言的是结构/几何/数值，不是"看着像"。
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/rule_registry.dart';
import 'package:dice_realm/repo/character_repo.dart';
import 'package:dice_realm/repo/settings_repo.dart';
import 'package:dice_realm/theme.dart';
import 'package:dice_realm/ui/art.dart';
import 'package:dice_realm/ui/create/rule_pick_page.dart';
import 'package:dice_realm/ui/roster_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// 每个用例后把全局色板复位（Palette 是全局门面，会跨界污染）
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

/// 首页那张「英灵殿」入口的语义节点（图里烧了字，读屏只能靠它）
Finder _valhallaSemantics() => find.byWidgetPredicate(
  (Widget w) => w is Semantics && w.properties.label == '英灵殿',
);

void main() {
  setUp(_resetPalette);
  tearDown(_resetPalette);

  /* ==========================================================
   * 需求 2 · 名册按入口过滤
   * ========================================================== */
  group('需求 2 · 名册只显示入口对应的那一栏', () {
    testWidgets('scope=saved：有「已保存的角色卡」，没有「英灵殿」（连标题都不建）',
        (tester) async {
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('alive01', '在世的'));
      await repo.save(_card('dead01', '长眠的', dead: true));

      await pumpApp(
        tester,
        repo: repo,
        home: const RosterPage(scope: RosterScope.saved),
      );

      expect(find.text('已保存的角色卡'), findsOneWidget);
      expect(find.text('在世的'), findsOneWidget);
      // ★ 另一块压根不构建：标题 / 列表 / 空态一个都没有
      expect(find.text('英灵殿'), findsNothing);
      expect(find.text('长眠的'), findsNothing);
      expect(find.text('还没有英雄长眠于此'), findsNothing);
      // 顶部 hint 跟着作用域走：只报调查员人数
      expect(find.text('1 位调查员'), findsOneWidget);
      expect(find.textContaining('长眠者'), findsNothing);
    });

    testWidgets('scope=fallen：有「英灵殿」，没有「已保存的角色卡」',
        (tester) async {
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('alive01', '在世的'));
      await repo.save(_card('dead01', '长眠的', dead: true));

      await pumpApp(
        tester,
        repo: repo,
        home: const RosterPage(scope: RosterScope.fallen),
      );

      expect(find.text('英灵殿'), findsOneWidget);
      expect(find.text('长眠的'), findsOneWidget);
      expect(find.text('已保存的角色卡'), findsNothing);
      expect(find.text('在世的'), findsNothing);
      expect(
        find.text('还没有角色卡'),
        findsNothing,
        reason: '已保存那栏的空态也不许建出来',
      );
      expect(find.text('1 位长眠者'), findsOneWidget);
    });

    testWidgets('scope 缺省 = all：两块都在（深链 /roster 的老行为不变）',
        (tester) async {
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('alive01', '在世的'));
      await repo.save(_card('dead01', '长眠的', dead: true));

      await pumpApp(tester, repo: repo, home: const RosterPage());

      expect(find.text('已保存的角色卡'), findsOneWidget);
      expect(find.text('英灵殿'), findsOneWidget);
      expect(
        find.text('已保存 1 位调查员 · 1 位长眠者'),
        findsOneWidget,
        reason: 'all 的 hint 仍是两栏合计',
      );
    });

    testWidgets('首页点「已保存」入口 → 进名册后没有「英灵殿」字样', (tester) async {
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('alive01', '在世的'));
      await repo.save(_card('dead01', '长眠的', dead: true));
      await pumpApp(tester, repo: repo);

      await tapKey(tester, 'home_roster_saved');

      expect(find.byType(RosterPage), findsOneWidget);
      expect(find.text('已保存的角色卡'), findsOneWidget);
      expect(find.text('英灵殿'), findsNothing);
    });

    testWidgets('首页点「英灵殿」入口 → 进名册后没有「已保存的角色卡」字样',
        (tester) async {
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('alive01', '在世的'));
      await repo.save(_card('dead01', '长眠的', dead: true));
      await pumpApp(tester, repo: repo);

      await tapKey(tester, 'home_roster_valhalla');

      expect(find.byType(RosterPage), findsOneWidget);
      expect(find.text('英灵殿'), findsOneWidget);
      expect(find.text('已保存的角色卡'), findsNothing);
    });

    testWidgets('老 Key home_roster_entry 仍挂在第一张卡上，行为等同 saved',
        (tester) async {
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('alive01', '在世的'));
      await pumpApp(tester, repo: repo);

      await tapKey(tester, 'home_roster_entry');
      expect(find.byType(RosterPage), findsOneWidget);
      expect(find.text('已保存的角色卡'), findsOneWidget);
      expect(find.text('英灵殿'), findsNothing);
    });
  });

  /* ==========================================================
   * 需求 4 · 两张入口图走同一套叠字（P11 修订）
   *
   * P10 时英灵殿底图把三段字烧进了图里，App 只好不叠字、只在右下角留个
   * 计数角标。P11 换了素材（不含文字、左侧留白、主体在右），两张卡改成
   * **同一套**：左侧竖金条 + 标题 + 张数副标题，浮动角标删掉。
   * ========================================================== */
  group('需求 4 · 两张入口图同一套叠字', () {
    testWidgets("首页有 Text('英灵殿')，且只有一个可点的语义入口", (tester) async {
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('dead01', '长眠的', dead: true));
      await pumpApp(tester, repo: repo);

      // 图里已经没有字，App 叠的这一层就是唯一可见标题（且只许有一处）
      expect(find.text('英灵殿'), findsOneWidget);
      // 入口"有名有姓"（读屏），且声明可点
      expect(_valhallaSemantics(), findsOneWidget);
      expect(
        tester.widget<Semantics>(_valhallaSemantics()).properties.button,
        isTrue,
      );
      // 两张入口的 Key 与几何都没变（2:1、竖排、等宽）
      expect(find.byKey(const Key('home_roster_saved')), findsOneWidget);
      expect(find.byKey(const Key('home_roster_valhalla')), findsOneWidget);
      final Rect saved = tester.getRect(
        find.byKey(const Key('home_roster_saved')),
      );
      final Rect fallen = tester.getRect(
        find.byKey(const Key('home_roster_valhalla')),
      );
      expect(fallen.width / fallen.height, closeTo(2, 0.02));
      expect(saved.top, lessThan(fallen.top));
    });

    testWidgets('两张卡都是「左侧标题 + 张数副标题」，不再有浮动角标', (tester) async {
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('alive01', '在世的'));
      await repo.save(_card('dead01', '长眠的', dead: true));
      await pumpApp(tester, repo: repo);

      expect(find.text('角色卡'), findsOneWidget);
      expect(find.text('1 位调查员'), findsOneWidget);
      expect(find.text('英灵殿'), findsOneWidget);
      expect(find.text('1 位长眠者'), findsOneWidget);

      // 同一套版式：两个标题、两个副标题的左边界必须对齐（都在图的左侧安全区）
      final Rect savedTitle = tester.getRect(find.text('角色卡'));
      final Rect fallenTitle = tester.getRect(find.text('英灵殿'));
      expect(
        savedTitle.left,
        closeTo(fallenTitle.left, 0.5),
        reason: '两张卡的标题必须从同一个 x 起排（同一套布局）',
      );
      final Rect savedSub = tester.getRect(find.text('1 位调查员'));
      final Rect fallenSub = tester.getRect(find.text('1 位长眠者'));
      expect(savedSub.left, closeTo(fallenSub.left, 0.5));

      // 副标题在标题下方、都在左半边（不再有右下角浮动角标）
      expect(savedSub.top, greaterThan(savedTitle.bottom));
      expect(fallenSub.top, greaterThan(fallenTitle.bottom));
      for (final Rect r in <Rect>[savedTitle, savedSub, fallenTitle, fallenSub]) {
        final Rect banner = tester.getRect(
          find.byKey(
            r == fallenTitle || r == fallenSub
                ? const Key('home_roster_valhalla')
                : const Key('home_roster_saved'),
          ),
        );
        expect(
          r.center.dx,
          lessThan(banner.center.dx),
          reason: '文字全部落在左半边（新素材主体在右，不许压插画）',
        );
      }
    });

    testWidgets('「角色卡」那张图保持原来的左侧叠字（没被一起删掉）', (
      tester,
    ) async {
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('alive01', '在世的'));
      await pumpApp(tester, repo: repo);

      // ★ P19：首页入口图标题改「角色卡」
      expect(find.text('角色卡'), findsOneWidget);
      expect(find.text('1 位调查员'), findsOneWidget);
    });

    testWidgets('最窄一档（320dp）下两张卡都不溢出、仍 2:1', (tester) async {
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('dead01', '长眠的', dead: true));
      await pumpApp(tester, repo: repo);

      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpAndSettle();

      expect(find.text('1 位长眠者'), findsOneWidget);
      final Rect banner = tester.getRect(
        find.byKey(const Key('home_roster_valhalla')),
      );
      final Rect text = tester.getRect(find.text('1 位长眠者'));
      expect(text.left, greaterThanOrEqualTo(banner.left - 0.5));
      expect(text.right, lessThanOrEqualTo(banner.right + 0.5));
      expect(tester.takeException(), isNull, reason: '窄屏上文字挤出了入口卡片');
    });
  });

  /* ==========================================================
   * 需求 6 · 可选项不许套 opacity，未开放项 < 0.6
   * ========================================================== */
  group('需求 6 · 可选 / 未开放 视觉分离', () {
    testWidgets('可选项不被 Opacity 包裹，未开放项 < 0.6 且灰度化', (tester) async {
      await pumpApp(
        tester,
        home: const RulePickPage(next: RulePickTarget.wizard),
      );

      final String open = RuleRegistry.defaultRule.id;
      final RuleMeta closed = RuleRegistry.placeholders.first;

      final Finder openCard = find.byKey(Key('rule_pick_$open'));
      final Finder closedCard = find.byKey(Key('rule_pick_${closed.id}'));
      expect(openCard, findsOneWidget);
      expect(closedCard, findsOneWidget);

      // 可选：卡内不许出现任何 Opacity（"可选"不许用透明度表达）；
      // 祖先链上也不许出现 <1 的（外层页面可能自带 opacity=1 的壳）
      expect(
        find.descendant(of: openCard, matching: find.byType(Opacity)),
        findsNothing,
        reason: '可选卡不许用透明度表达状态',
      );
      final List<double> openOps = tester
          .widgetList<Opacity>(
            find.ancestor(of: openCard, matching: find.byType(Opacity)),
          )
          .map((Opacity o) => o.opacity)
          .toList();
      expect(
        openOps.where((double o) => o < 1).toList(),
        isEmpty,
        reason: '可选卡不许被 <1 的 Opacity 包裹（亮色下就是"灰蒙蒙"）；实测 $openOps',
      );
      // 可选：也不许灰度化
      expect(
        find.descendant(of: openCard, matching: find.byType(ColorFiltered)),
        findsNothing,
      );

      // 未开放：整体（铺满整卡）opacity ≤ 0.6 + 灰度 + 标签
      final Finder closedOps = find.descendant(
        of: closedCard,
        matching: find.byType(Opacity),
      );
      expect(closedOps, findsOneWidget, reason: '未开放必须整体压暗');
      expect(
        tester.widget<Opacity>(closedOps).opacity,
        lessThan(0.6),
        reason: '未开放要明显暗于可选（实现 0.45）',
      );
      // "整体"：这层 Opacity 必须铺满整张卡，不是某个角落的小物件
      final Size opSize = tester.getSize(closedOps);
      final Size cardSize = tester.getSize(closedCard);
      expect(opSize.width, closeTo(cardSize.width, 0.5));
      expect(opSize.height, closeTo(cardSize.height, 0.5));
      expect(
        find.descendant(of: closedCard, matching: find.byType(ColorFiltered)),
        findsOneWidget,
        reason: '未开放必须灰度化，和可选项一眼分开',
      );
      expect(
        find.byKey(Key('rule_unavailable_${closed.id}')),
        findsOneWidget,
      );
    });

    testWidgets('文字可读性靠左→右渐变（只压左侧，右半张露原图）', (tester) async {
      await pumpApp(
        tester,
        home: const RulePickPage(next: RulePickTarget.wizard),
      );

      final Finder card = find.byKey(
        Key('rule_pick_${RuleRegistry.defaultRule.id}'),
      );
      final Finder scrims = find.descendant(
        of: card,
        matching: find.byWidgetPredicate(
          (Widget w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).gradient is LinearGradient,
        ),
      );
      expect(scrims, findsOneWidget, reason: '压层只能有一层，且是渐变');
      final LinearGradient g =
          (tester.widget<DecoratedBox>(scrims).decoration as BoxDecoration)
                  .gradient
              as LinearGradient;
      // 左 → 右：左边最暗，右边透明（旧版是上→下整张压暗）
      expect(g.begin, Alignment.centerLeft);
      expect(g.end, Alignment.centerRight);
      expect(
        g.colors.first.a,
        greaterThan(0.5),
        reason: '左侧要够暗，文字才够对比',
      );
      expect(
        g.colors.last.a,
        lessThan(0.05),
        reason: '右侧必须几乎不压暗（这是"灰蒙蒙"的根因）',
      );
    });
  });

  /* ==========================================================
   * 需求 5 · 不再为「图内金边」打补丁（P11 修订）
   *
   * P10 时暗色 `r1_coc7_2x1.webp` 把金边画成了 3:1 内框，于是在代码里加了
   * `ClipRect + OverflowBox` 把图放大 1.753 倍裁掉那条内框。
   * P11 六张 `g_rules/r1|r2|r3`（2:1） 重出：图内**不再有边框**、主体在右 55%、
   * 左侧 40% 留空 —— 补丁失去意义且会白裁画面，连同 `_innerCrops` 表一起删除。
   * 这里反向锁住：整张卡只允许「原图直铺」一种铺法。
   * ========================================================== */
  group('需求 5 · 规则卡不再放大裁切图内边框', () {
    testWidgets('暗色 COC 卡：底图按 1:1 直铺，没有 OverflowBox / ClipRect 补丁', (
      tester,
    ) async {
      await pumpApp(
        tester,
        home: const RulePickPage(next: RulePickTarget.wizard),
      );

      final Finder card = find.byKey(
        Key('rule_pick_${RuleRegistry.defaultRule.id}'),
      );
      final Rect cardRect = tester.getRect(card);

      expect(
        find.descendant(of: card, matching: find.byType(OverflowBox)),
        findsNothing,
        reason: '新素材图内没有边框，放大裁剪的补丁必须删干净',
      );
      final Size art = tester.getSize(
        find.descendant(of: card, matching: find.byType(ArtImage)).first,
      );
      expect(art.width / cardRect.width, closeTo(1, 0.01));
      expect(art.height / cardRect.height, closeTo(1, 0.01));
      expect(tester.takeException(), isNull);
    });

    testWidgets('亮色 COC 卡：同样是原图整张铺满（两套皮肤一套铺法）', (tester) async {
      // 亮色要走设置仓库（`DiceRealmApp.build` 每帧按 settings 重置 Palette，
      // 直接 Palette.useBrightness 会被下一帧覆盖）。
      final SettingsRepo settings = await newMemorySettings();
      settings.isDarkTheme = false;
      await pumpApp(
        tester,
        settings: settings,
        home: const RulePickPage(next: RulePickTarget.wizard),
      );
      expect(Palette.brightness, Brightness.light);

      final Finder card = find.byKey(
        Key('rule_pick_${RuleRegistry.defaultRule.id}'),
      );
      final Rect cardRect = tester.getRect(card);
      final Size art = tester.getSize(
        find.descendant(of: card, matching: find.byType(ArtImage)).first,
      );
      expect(art.width / cardRect.width, closeTo(1, 0.01));
      expect(art.height / cardRect.height, closeTo(1, 0.01));
      expect(
        find.descendant(of: card, matching: find.byType(OverflowBox)),
        findsNothing,
      );
    });
  });
}
