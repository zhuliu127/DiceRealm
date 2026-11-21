// ============================================================
// p8_home_ui_test.dart — P8 首页 / 名册 / 一键出卡 / 分享按钮（widget 级）
//
// 这一批的 UI 缺陷，每条都用「能证伪」的方式守：
//   ① 横幅被裁：几何断言（宽高比 + 对齐方式），不是"看着像"
//   ② 分类头长度不一致：两个分类头的 Rect.left / Rect.right 必须相等
//   ③ HP/SAN 溢出：名册页每行一张卡，且 `takeException()` 必须为 null
//   ④ 角色卡收进二级页：首页不再出现卡名，名册页逐卡带规则徽标
//   ⑤ 切亮色不切换：真的点设置页的「亮色」，回来断言叶子 Text 颜色
//   ⑥ AI 页只做 AI：候选卡 UI 不在本页，「一键出卡」入口能跳
//   ⑦ 一键出卡：右下角常驻「重新随机」，点了内容真的换
//   ⑧ 卡详情快捷分享：顶部 bar 有按钮，点了真的滚到云分享区
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/net/ai_client.dart';
import 'package:dice_realm/net/ai_create.dart';
import 'package:dice_realm/theme.dart';
import 'package:dice_realm/ui/ai_create_page.dart';
import 'package:dice_realm/ui/create/rule_pick_page.dart';
import 'package:dice_realm/ui/art.dart';
import 'package:dice_realm/ui/random_create_page.dart';
import 'package:dice_realm/ui/roster_page.dart';
import 'package:dice_realm/ui/summary_card.dart';
import 'package:dice_realm/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// 每个用例前后把全局色板复位（Palette 是全局门面，会跨界污染）
void _resetPalette() => Palette.useBrightness(Brightness.dark);

/// 造一张可落库的卡
Character _card(String id, String name, {bool dead = false}) {
  final c = Character(newCharacter());
  c.raw['id'] = id;
  c.raw['characterName'] = name;
  c.basicInfo['age'] = 31;
  c.raw['age'] = 31;
  for (final k in <String>[
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

/// 取某个 Text 的实际渲染颜色
Color? _textColor(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  setUp(_resetPalette);
  tearDown(_resetPalette);

  // ---------------------------------------------------------
  // ② 分类头长度一致 + ① 横幅几何
  // ---------------------------------------------------------
  group('首页版式', () {
    testWidgets('「开始冒险」与「角色档案」两个分类头左右边界完全相等', (tester) async {
      await pumpApp(tester);

      final banners = find.byType(SectionBanner);
      expect(banners, findsNWidgets(2), reason: '首页应只有两个分类头');

      final Rect adventure = tester.getRect(banners.at(0));
      final Rect archive = tester.getRect(banners.at(1));

      expect(
        adventure.left,
        archive.left,
        reason: '左边不齐（曾因 SliverPadding+内边距双重缩进）',
      );
      expect(adventure.right, archive.right, reason: '右边不齐');
      expect(adventure.width, archive.width);
    });

    testWidgets('入口横幅宽高比 2.45（四边金边都在框内）且居中裁切', (tester) async {
      await pumpApp(tester);

      for (final String k in <String>[
        'fab_room',
        'fab_ai_create',
        'entry_random',
        'fab_new_card',
      ]) {
        final Rect r = tester.getRect(find.byKey(Key(k)));
        final double ratio = r.width / r.height;

        // 源图 1536×620 = 2.477:1，金边内缩 13px（0.85%）。
        // 2.45 时左右各裁 (1−2.45/2.477)/2 = 0.55% = 8.5px < 13px →
        // 左边框与右边框都还剩 4px 以上余量；上下不裁。
        expect(
          ratio,
          inInclusiveRange(2.3, 2.5),
          reason: '$k 宽高比 $ratio 超出安全区（2.0 会把上下金边裁掉）',
        );
        expect(
          ratio,
          greaterThanOrEqualTo(2.44),
          reason:
              '$k 宽高比 $ratio 太小，左右会裁掉 13px 的金边'
              '（2.44 时左右各裁 11.6px，仍在金边内缩 13px 以内）',
        );

        // 对齐必须是居中：centerLeft 会把裁切全压到右侧，右边框直接消失
        final ArtImage img = tester.widget<ArtImage>(
          find.descendant(
            of: find.byKey(Key(k)),
            matching: find.byType(ArtImage),
          ),
        );
        expect(img.fit, BoxFit.cover);
        expect(img.alignment, Alignment.center);
      }
    });

    testWidgets('首页不再铺角色卡：卡名不在首页，只在名册页', (tester) async {
      final repo = await newMemoryRepo();
      await repo.save(_card('c1', '首页不该出现的名字'));
      await pumpApp(tester, repo: repo);

      expect(find.text('首页不该出现的名字'), findsNothing);
      // 但计数还在（用户要一眼看到有几张）。
      // ★ P9 追加：计数从「单独一个数字」改成入口图上的副标题「1 位调查员」
      //   （用户要求两张 2:1 入口图、文案画在图上），断言改成等价的整句，
      //   仍然是「首页必须显示张数」，没有放宽。
      expect(find.text('1 位调查员'), findsOneWidget);

      await tapKey(tester, 'home_roster_entry');
      expect(find.byType(RosterPage), findsOneWidget);
      expect(find.text('首页不该出现的名字'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------
  // ⑤ 切亮色：叶子节点颜色必须真的变（const 复用的坑）
  // ---------------------------------------------------------
  testWidgets('切亮色后「开始冒险」区块的文字颜色真的变成亮色金', (tester) async {
    final settings = await newMemorySettings();
    await pumpApp(tester, settings: settings);

    expect(
      _textColor(tester, '开始冒险'),
      AppPalette.dark.goldStr,
      reason: '默认应是暗色皮肤',
    );

    // 真机路径：右上角菜单 → 设置 → 点「亮色」
    await tester.tap(find.byKey(const Key('home_menu')));
    await tester.pumpAndSettle();
    await tapKey(tester, 'menu_settings');
    await tester.tap(find.byKey(const Key('settings_theme_light')));
    await tester.pumpAndSettle();
    expect(settings.isDarkTheme, isFalse);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(
      _textColor(tester, '开始冒险'),
      AppPalette.light.goldStr,
      reason: '切换后仍是暗色金 → const 实例被复用、Element 跳过了 rebuild',
    );
    // 四个入口的图也要跟着换（亮色版横幅）
    final ArtImage room = tester.widget<ArtImage>(
      find.descendant(
        of: find.byKey(const Key('fab_room')),
        matching: find.byType(ArtImage),
      ),
    );
    expect(room.path, Art.bannerRoomLight);
  });

  // ---------------------------------------------------------
  // ③④ 名册页：一行一张、徽标齐、不溢出
  // ---------------------------------------------------------
  testWidgets('名册页逐卡带规则徽标，数值不溢出边框', (tester) async {
    final repo = await newMemoryRepo();
    await repo.save(_card('alive01', '在世调查员'));
    await repo.save(_card('dead01', '长眠调查员', dead: true));
    await pumpApp(tester, repo: repo);

    // ★ P10 需求 2：名册按入口分栏（点「已保存」只显示已保存、点「英灵殿」
    //   只显示长眠）。两个入口分别进一次，各自断言「只有自己这一栏」——
    //   比以前"两栏混在一页"更严，不是放宽。
    await tapKey(tester, 'home_roster_entry');

    expect(find.byType(RosterPage), findsOneWidget);
    // ★ P7-D 口径：每张卡都有 card_rule_badge_<id>
    expect(find.byKey(const Key('card_rule_badge_alive01')), findsOneWidget);
    expect(find.byKey(const Key('card_rule_badge_dead01')), findsNothing);
    // 只有「已保存」这一栏
    expect(find.text('已保存的角色卡'), findsOneWidget);
    expect(find.text('英灵殿'), findsNothing);

    // 数值 chip 都在（溢出会抛 RenderFlex overflow，被 takeException 抓到）
    expect(find.text('HP'), findsOneWidget);
    expect(find.text('SAN'), findsOneWidget);
    expect(find.text('MP'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '卡片里的数值溢出了边框');

    // 回首页，从「英灵殿」入口进：只该有长眠的那张
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapKey(tester, 'home_roster_valhalla');

    expect(find.byType(RosterPage), findsOneWidget);
    expect(find.byKey(const Key('card_rule_badge_dead01')), findsOneWidget);
    expect(find.byKey(const Key('card_rule_badge_alive01')), findsNothing);
    expect(find.text('英灵殿'), findsOneWidget);
    expect(find.text('已保存的角色卡'), findsNothing);
    expect(find.text('☠ 已撕卡'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '撕卡徽标把行挤出了边框');
  });

  // ---------------------------------------------------------
  // ⑥ 一键出卡：入口 + 常驻悬浮按钮
  // ---------------------------------------------------------
  testWidgets('首页「一键出卡」先进规则选择页，再进随机页；「重新随机」真的换一批',
      (tester) async {
    await pumpApp(tester);
    await tapKey(tester, 'entry_random');
    // ★ P9 需求 5：四个入口统一先选规则系统
    expect(find.byType(RulePickPage), findsOneWidget);
    expect(find.byType(RandomCreatePage), findsNothing);
    await tapKey(tester, 'rule_pick_coc7');

    expect(find.byType(RandomCreatePage), findsOneWidget);
    expect(
      find.byType(SummaryCard, skipOffstage: false),
      findsNWidgets(5),
      reason: '一次必须出 5 张',
    );
    expect(find.byKey(const Key('random_reroll')), findsOneWidget);

    final String firstBatch = tester
        .widget<Text>(find.byKey(const Key('random_batch_label')))
        .data!;
    expect(firstBatch, contains('第 1 批'));

    await tester.tap(find.byKey(const Key('random_reroll')));
    await tester.pumpAndSettle();

    final String secondBatch = tester
        .widget<Text>(find.byKey(const Key('random_batch_label')))
        .data!;
    expect(secondBatch, contains('第 2 批'), reason: '点一次必须重出一批');
    expect(
      find.byType(SummaryCard, skipOffstage: false),
      findsNWidgets(5),
      reason: '重随机后仍然是 5 张',
    );
  });

  testWidgets('重新随机换的是内容，不只是换了个计数器', (tester) async {
    var round = 0;
    await tester.pumpWidget(
      await wrapWithScopes(
        MaterialApp(
          home: RandomCreatePage(
            generate: () {
              round++;
              return <Character>[
                for (var i = 0; i < 5; i++)
                  _card('r$round-$i', '第$round批第${i + 1}人'),
              ];
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('第1批第1人'), findsOneWidget);

    await tester.tap(find.byKey(const Key('random_reroll')));
    await tester.pumpAndSettle();

    expect(find.text('第1批第1人'), findsNothing, reason: '旧一批必须整体换掉');
    expect(find.text('第2批第1人'), findsOneWidget);
  });

  // ---------------------------------------------------------
  // ⑥ AI 页只做 AI
  // ---------------------------------------------------------
  testWidgets('AI 页没有随机候选卡 UI，但有「一键出卡」入口且能跳', (tester) async {
    await pumpApp(
      tester,
      settings: await newMemorySettings(),
      home: const AiCreatePage(generate: _neverCalled),
    );

    expect(
      find.byKey(const Key('preset_candidate_0'), skipOffstage: false),
      findsNothing,
      reason: '随机候选卡已搬到 /random，AI 页不许再出',
    );

    await scrollTo(tester, 'ai_entry_random');
    expect(find.text('不想用 AI？'), findsOneWidget);
    await tapKey(tester, 'ai_entry_random');
    expect(find.byType(RandomCreatePage), findsOneWidget);
  });

  // ---------------------------------------------------------
  // ⑧ 卡详情快捷分享
  // ---------------------------------------------------------
  testWidgets('卡详情顶部「修改」右边有快捷分享，点了真的滚到云分享区', (tester) async {
    await pumpCardDetail(tester, card: _card('s1', '分享测试员'));

    expect(find.byKey(const Key('card_quick_share')), findsOneWidget);

    // 把视口压到手机尺寸：详情页内容远长于一屏，分享区一开始在视口外
    tester.view.physicalSize = const Size(400, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    expect(
      _onScreen(tester, const Key('share_unconfigured')),
      isFalse,
      reason: '详情页一进来不应该已经停在分享区',
    );

    await tester.tap(find.byKey(const Key('card_quick_share')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      _onScreen(tester, const Key('share_unconfigured')),
      isTrue,
      reason: '点分享后应当停在云分享区（测试里分享服务未配置）',
    );
  });

  // ---------------------------------------------------------
  // ③ 卡片数值不溢出（窄屏也不溢）
  // ---------------------------------------------------------
  testWidgets('320px 窄屏下名册卡片的数值不溢出', (tester) async {
    final repo = await newMemoryRepo();
    await repo.save(_card('narrow1', '窄屏调查员'));
    await pumpApp(tester, repo: repo);

    // 把视口压到小屏（真实手机里最窄的一档）
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    await tapKey(tester, 'home_roster_entry');
    expect(find.byKey(const Key('card_rule_badge_narrow1')), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '窄屏上数值溢出了边框');
  });
}

/// 目标控件是否真的落在当前视口内（找不到 = 不在，算不可见）
bool _onScreen(WidgetTester tester, Key key) {
  final Finder f = find.byKey(key);
  if (f.evaluate().isEmpty) return false;
  final Rect r = tester.getRect(f);
  final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  return r.bottom > 0 && r.top < screen.height;
}

Future<AiCreateResult> _neverCalled(
  AiGenerateRequest req,
  void Function(String) onStage,
) => Future<AiCreateResult>.error(
  AiException(AiErrorKind.notConfigured, '测试不该走到这里'),
);
