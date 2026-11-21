// ============================================================
// p9_rule_pick_test.dart — 规则系统选择前置（P9 需求 5 / 6 / 8）+ 头图统一
//
// 用户原话：
//   5. 首页「AI车卡」「一键出卡」「跑团房间」也改成先选择规则系统，
//      四个入口逻辑一样，都是先到选择规则系统再进后续流程。
//   6. 结果页那个「√ 就用这张，继续完善」拆成「就用这张」和「继续完善」：
//      「就用这张」= 存进已保存角色卡 + 回首页；「继续完善」= 进修改，不保存。
//   8. 无论哪种车卡方式，保存角色卡之后都自动跳到首页。
//
// 每条都做成**能证伪**的断言，不是「点完没崩」：
//   · 入口断言「先出现 RulePickPage，且此时目标页**还不存在**」——
//     只断言「点完能到目标页」的话，直连入口的实现也会绿，证明不了前置。
//   · 未开放规则断言 **InkWell.onTap == null**（真的没有回调），
//     再补一次「点下去页面不变」。
//   · 「就用这张」同时断言 repo 多一张 + AI/随机页**已从栈里消失**
//     + HomePage 是顶层（`find` 默认跳过 offstage，所以「在下面一直存在」
//     这件事骗不过断言）。
//   · 「继续完善」除了进向导，还必须断言 repo 仍然为空 ——
//     只断言前者会把「顺手帮你存了」这种 bug 放过去。
//   · 规则列表断言「渲染数量 == 注册表长度」，并额外塞一条注册表里没有的
//     假规则渲染出来，证明页面是遍历渲染而不是写死三条。
//
// ⚠️ 本文件是磁盘事故后的重建版，与首版的三处差异（都是源码演进而非放宽）：
//   1. 头图 maxHeight 由 120 改为 **160**（手机 412dp 上 3:1 自然高 137，
//      钳到 120 会显得扁）；
//   2. 首页英灵殿入口图的三段字已由素材**烧进底图**（P10），App 不再叠标题，
//      所以不再断言 `find.text('英灵殿')`（那条口径属于 `qa_probe_test`），
//      改为断言张数角标 `1 位长眠者`；
//   3. 首页两个入口各自带**作用域**进名册（`RosterScope.saved` / `.fallen`），
//      断言从「点进去是 RosterPage」加强为「点进去只看到该作用域的卡」。
// ============================================================

import 'package:dice_realm/domain/ai_caps.dart';
import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/js_compat.dart' show setClock, setRng;
import 'package:dice_realm/domain/preset_gen.dart' as preset;
import 'package:dice_realm/domain/rule_registry.dart';
import 'package:dice_realm/net/ai_create.dart';
import 'package:dice_realm/repo/settings_repo.dart';
import 'package:dice_realm/ui/ai_create_page.dart';
import 'package:dice_realm/ui/create/create_flow_page.dart';
import 'package:dice_realm/ui/create/rule_pick_page.dart';
import 'package:dice_realm/ui/create/steps/step_rules.dart';
import 'package:dice_realm/ui/home_page.dart';
import 'package:dice_realm/ui/random_create_page.dart';
import 'package:dice_realm/ui/roster_page.dart';
import 'package:dice_realm/ui/room/room_entry_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';
import 'support/oracle.dart';

/// 造一张走真规则引擎的确定性卡（不联网）
Character _makeCard({String name = '规则测试员'}) {
  setRng(Lcg(20260908).call);
  setClock(() => oracleNowMs);
  uidDeterministic = true;
  final c = preset.generateOne()!;
  c.raw['characterName'] = name;
  return c;
}

/// 已配置 AI 的设置仓库（否则 AI 页只显示配置引导，没有描述输入框）
Future<SettingsRepo> _configuredSettings() async {
  final s = await newMemorySettings();
  s
    ..aiBase = 'https://api.example.com/v1'
    ..aiModel = 'm'
    ..aiKey = 'sk-abcdefghijklmnop';
  await s.save();
  return s;
}

AiCreateResult _resultOf(Character c) => AiCreateResult(
  character: c,
  profile: const <String, Object?>{'fromAI': true},
  raw: const <String, Object?>{},
  caps: const AiCaps(),
  attrScaled: false,
);

/// 把某页**压到首页之上**（模拟真实入口栈：首页 → 目标页），
/// 这样「保存后回首页」才可验证 —— 回的是首页，不是同一页。
Future<void> _pushOverHome(WidgetTester tester, Widget page) async {
  final BuildContext ctx = tester.element(find.byType(HomePage));
  Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => page));
  await tester.pumpAndSettle();
}

/// 规则卡上的 InkWell（用来证伪「未开放也能点」）
InkWell _cardInk(WidgetTester tester, String ruleId) => tester.widget<InkWell>(
  find.descendant(
    of: find.byKey(Key('rule_pick_$ruleId')),
    matching: find.byType(InkWell),
  ),
);

/// 一个可点进去的「未来规则」（注册表里没有，只用来验证渲染是遍历式的）
const RuleMeta _fakeRule = RuleMeta(
  id: 'fake9',
  name: '未来规则（假）',
  shortName: 'FUTURE',
  rulebook: '假规则书',
  available: true,
  description: '仅测试：证明列表遍历注册表而不是写死三条。',
);

void main() {
  /* ==========================================================
   * 需求 5：四个入口都先到「选择规则系统」
   * ========================================================== */
  group('需求 5 · 四个入口统一先选规则', () {
    testWidgets('跑团房间：先 RulePickPage，选 COC 后才进房间入口页', (tester) async {
      await pumpApp(tester);
      await tapKey(tester, 'fab_room');

      expect(find.byType(RulePickPage), findsOneWidget, reason: '入口必须先到选规则页');
      expect(find.byType(RoomEntryPage), findsNothing, reason: '选规则之前不该已经进房间');

      await tapKey(tester, 'rule_pick_coc7');
      expect(find.byType(RoomEntryPage), findsOneWidget);
    });

    testWidgets('AI 车卡：先 RulePickPage，选 COC 后才进 AI 页；AI 页不再出规则芯片', (
      tester,
    ) async {
      await pumpApp(tester, settings: await _configuredSettings());
      await tapKey(tester, 'fab_ai_create');

      expect(find.byType(RulePickPage), findsOneWidget);
      expect(find.byType(AiCreatePage), findsNothing);

      await tapKey(tester, 'rule_pick_coc7');
      expect(find.byType(AiCreatePage), findsOneWidget);

      // ★ 规则已在上一页选定：本页只显示一条只读说明，不再有可选芯片。
      //   （不能用 `find.byType(ChoiceChip) findsNothing` —— AI 页的房规上限
      //     档位也是 ChoiceChip，这里只针对**规则**芯片。）
      expect(
        find.byKey(Key('ai_rule_${RuleRegistry.defaultRule.id}')),
        findsNothing,
        reason: '规则已前移到选择页，AI 页不许再让玩家选第二次',
      );
      final Text current = tester.widget<Text>(
        find.byKey(const Key('ai_rule_current')),
      );
      expect(current.data, contains(RuleRegistry.defaultRule.shortName));
      expect(current.data, contains(RuleRegistry.defaultRule.rulebook));
    });

    testWidgets('一键出卡：先 RulePickPage，选 COC 后才进随机页；随机页无规则芯片', (tester) async {
      await pumpApp(tester);
      await tapKey(tester, 'entry_random');

      expect(find.byType(RulePickPage), findsOneWidget);
      expect(find.byType(RandomCreatePage), findsNothing);

      await tapKey(tester, 'rule_pick_coc7');
      expect(find.byType(RandomCreatePage), findsOneWidget);

      expect(find.byType(ChoiceChip), findsNothing, reason: '随机页不该再放规则选择');
      final Text line = tester.widget<Text>(
        find.byKey(const Key('random_rule_current')),
      );
      expect(line.data, contains(RuleRegistry.defaultRule.shortName));
    });

    testWidgets('按流程车卡：选完规则直接进 8 步向导（规则步已被选择页取代）', (tester) async {
      await pumpApp(tester);
      await tapKey(tester, 'fab_new_card');

      expect(find.byType(RulePickPage), findsOneWidget);
      expect(find.byType(CreateFlowPage), findsNothing);

      await tapKey(tester, 'rule_pick_coc7');
      expect(find.byType(CreateFlowPage), findsOneWidget);
      expect(find.byType(StepRules), findsNothing, reason: '不该让玩家再选一次规则');
      final Text progress = tester.widget<Text>(
        find.byKey(const Key('step_progress')),
      );
      expect(progress.data, '1 / 8', reason: '跳过 rules 步后分母必须是 8');
    });
  });

  /* ==========================================================
   * 未开放规则：如实灰掉、真的不可点
   * ========================================================== */
  group('未开放规则不可点', () {
    testWidgets('未开放卡片 onTap 为 null，且点下去页面不变', (tester) async {
      await pumpApp(tester);
      await tapKey(tester, 'entry_random');

      final RuleMeta closed = RuleRegistry.placeholders.first;
      expect(find.byKey(Key('rule_pick_${closed.id}')), findsOneWidget);
      expect(
        find.byKey(Key('rule_unavailable_${closed.id}')),
        findsOneWidget,
        reason: '未开放必须如实标注',
      );
      expect(_cardInk(tester, closed.id).onTap, isNull, reason: '未开放不许有回调');

      // 真点一次：页面必须原样停在这里
      await tester.tap(find.byKey(Key('rule_pick_${closed.id}')));
      await tester.pumpAndSettle();
      expect(find.byType(RulePickPage), findsOneWidget);
      expect(find.byType(RandomCreatePage), findsNothing);

      // 对照：已开放的卡片确实有回调（不是「全都不能点」）
      expect(_cardInk(tester, RuleRegistry.defaultRule.id).onTap, isNotNull);
    });
  });

  /* ==========================================================
   * 列表来源：遍历注册表，不是写死三条
   * ========================================================== */
  group('规则列表来自注册表', () {
    testWidgets('渲染数量 == RuleRegistry.all 长度', (tester) async {
      await pumpApp(tester);
      await tapKey(tester, 'fab_room');

      final int cards = find
          .byWidgetPredicate((Widget w) {
            final Key? k = w.key;
            if (k is! ValueKey<String>) return false;
            return k.value.startsWith('rule_pick_');
          })
          .evaluate()
          .length;
      expect(
        cards,
        RuleRegistry.all.length,
        reason: '卡片数量必须等于注册表长度（写死三条时，加规则后这条会立刻红）',
      );
      for (final RuleMeta r in RuleRegistry.all) {
        expect(find.byKey(Key('rule_pick_${r.id}')), findsOneWidget);
      }
    });

    testWidgets('注册表里没有的规则也能渲染出来（加一条就多一张卡）', (tester) async {
      // 4 张 2:1 卡在 800×600 里会有一张落在折叠线以下（ListView 懒构建）
      useTallScreen(tester);
      await tester.pumpWidget(
        await wrapWithScopes(
          MaterialApp(
            home: RulePickPage(
              next: RulePickTarget.ai,
              rules: <RuleMeta>[...RuleRegistry.all, _fakeRule],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(Key('rule_pick_${_fakeRule.id}')),
        findsOneWidget,
        reason: '页面必须按传入/注册的规则遍历渲染',
      );
      expect(find.text(_fakeRule.name), findsOneWidget);
      // 假规则标了 available:true → 真的可点（不是画上去的假卡）
      expect(_cardInk(tester, _fakeRule.id).onTap, isNotNull);
    });
  });

  /* ==========================================================
   * 需求 6 / 8：结果页两个按钮 + 保存后回首页
   * ========================================================== */
  group('AI 结果：就用这张 / 继续完善', () {
    testWidgets('「就用这张」→ 落库 + 回首页', (tester) async {
      final repo = await pumpApp(tester, settings: await _configuredSettings());
      final card = _makeCard(name: '一键入库');
      await _pushOverHome(
        tester,
        AiCreatePage(
          initialRuleId: RuleRegistry.defaultRule.id,
          generate: (
            AiGenerateRequest req,
            void Function(String) onStage,
          ) async => _resultOf(card),
        ),
      );
      expect(find.byType(AiCreatePage), findsOneWidget);

      await tester.enterText(find.byKey(const Key('ai_desc')), '一个守夜人');
      await tapKey(tester, 'ai_generate');
      expect(find.byKey(const Key('ai_result_card')), findsOneWidget);

      await scrollTo(tester, 'result_use_this');
      await tapKey(tester, 'result_use_this');

      expect(repo.all.length, 1, reason: '「就用这张」必须真的落库');
      expect(repo.alive.single.characterName, '一键入库');
      expect(
        repo.alive.single.raw['ruleSystemId'],
        RuleRegistry.defaultRule.id,
        reason: '卡上必须带所选规则',
      );
      expect(find.byType(AiCreatePage), findsNothing, reason: '保存后必须离开 AI 页');
      expect(find.byType(HomePage), findsOneWidget, reason: '保存后必须回首页');
      expect(find.byKey(const Key('fab_room')), findsOneWidget);
    });

    testWidgets('「继续完善」→ 进向导且**未落库**', (tester) async {
      final repo = await pumpApp(tester, settings: await _configuredSettings());
      await _pushOverHome(
        tester,
        AiCreatePage(
          initialRuleId: RuleRegistry.defaultRule.id,
          generate: (
            AiGenerateRequest req,
            void Function(String) onStage,
          ) async => _resultOf(_makeCard(name: '待完善')),
        ),
      );

      await tester.enterText(find.byKey(const Key('ai_desc')), '一个法医');
      await tapKey(tester, 'ai_generate');
      await scrollTo(tester, 'result_continue_edit');
      await tapKey(tester, 'result_continue_edit');

      expect(find.byType(CreateFlowPage), findsOneWidget);
      expect(find.byType(StepRules), findsNothing, reason: '规则已选过，不再重复');
      expect(repo.all, isEmpty, reason: '「继续完善」不许偷偷落库');
    });
  });

  group('一键出卡结果：就用这张 / 继续完善', () {
    testWidgets('「就用这张」→ 落库 + 回首页（第 1 张）', (tester) async {
      final repo = await pumpApp(tester);
      await _pushOverHome(tester, const RandomCreatePage());

      expect(find.byType(RandomCreatePage), findsOneWidget);
      await scrollTo(tester, 'result_use_this_0');
      await tapKey(tester, 'result_use_this_0');

      expect(repo.all.length, 1, reason: '只保存点中的那一张');
      expect(find.byType(RandomCreatePage), findsNothing);
      expect(find.byType(HomePage), findsOneWidget, reason: '保存后必须回首页');
    });

    testWidgets('「继续完善」→ 进向导且未落库', (tester) async {
      final repo = await pumpApp(tester);
      await _pushOverHome(tester, const RandomCreatePage());

      await scrollTo(tester, 'result_continue_edit_0');
      await tapKey(tester, 'result_continue_edit_0');

      expect(find.byType(CreateFlowPage), findsOneWidget);
      expect(repo.all, isEmpty, reason: '进向导还不是保存，仓库必须为空');
    });
  });

  /* ==========================================================
   * 头图尺寸统一（向导页 / 一键出卡页同一套 BannerSlot；AI 页固定 64）
   * ========================================================== */
  group('头图', () {
    testWidgets('向导页与一键出卡页头图等高（同一个 Art + 同一组 BannerSlot 参数）', (tester) async {
      useTallScreen(tester);

      await tester.pumpWidget(
        await wrapWithScopes(const MaterialApp(home: CreateFlowPage())),
      );
      await tester.pumpAndSettle();
      final double wizardH = tester
          .getSize(find.byKey(const Key('wizard_header')))
          .height;

      await tester.pumpWidget(
        await wrapWithScopes(const MaterialApp(home: RandomCreatePage())),
      );
      await tester.pumpAndSettle();
      final double randomH = tester
          .getSize(find.byKey(const Key('random_header')))
          .height;

      expect(
        wizardH,
        randomH,
        reason: '两页头图必须一样高（以前一页固定 68px、一页裸 3:1，看起来一扁一厚）',
      );
      expect(
        wizardH,
        160,
        reason:
            '1200dp 宽下必须被 maxHeight 钳到 160（3:1 自然高会是 273，'
            '会把首屏内容挤走）',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('AI 车卡页头图固定 64px（不用 AspectRatio，宽屏也不膨胀）', (tester) async {
      await pumpApp(
        tester,
        settings: await _configuredSettings(),
        home: AiCreatePage(
          generate: (
            AiGenerateRequest req,
            void Function(String) onStage,
          ) async => _resultOf(_makeCard()),
        ),
      );

      final Size s = tester.getSize(find.byKey(const Key('ai_header')));
      expect(s.height, 64, reason: 'AI 页头图高度写死 64px');
      expect(s.width, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  });

  /* ==========================================================
   * 首页「角色档案」= 两张 2:1 入口图（已保存 / 英灵殿）
   *
   * ★ P10：英灵殿那张的三段字曾**烧进底图**，App 当时不叠标题。
   * ★ P11：素材换成「不含文字、左侧留白」的新版，两张卡改成同一套叠字，
   *   所以这里同时断言文本 + 语义 + Key + 点击落点。
   * ========================================================== */
  group('首页角色档案入口图', () {
    testWidgets('两张竖排 2:1 图、Key 齐全，各自进名册且作用域正确', (tester) async {
      // 英灵殿入口的三段字烧在底图里，读屏只能靠 Semantics 标签 ——
      // 要断言它就必须先打开语义树。注意 handle 必须在本体内 dispose：
      // `addTearDown` 会排在「测试结束校验」之后，那时已经报「handle 未释放」。
      final SemanticsHandle semantics = tester.ensureSemantics();
      try {
        final repo = await newMemoryRepo();
        final alive = _makeCard(name: '在世调查员');
        alive.raw['id'] = 'alive01';
        await repo.save(alive);

        final dead = _makeCard(name: '长眠调查员');
        dead.raw['id'] = 'dead0001';
        dead.status['body'] = '死亡';
        await repo.save(dead);

        await pumpApp(tester, repo: repo);

        // 老用例按名依赖的入口 Key 仍在（挂在第一张外面）
        expect(find.byKey(const Key('home_roster_entry')), findsOneWidget);
        expect(find.byKey(const Key('home_roster_saved')), findsOneWidget);
        expect(find.byKey(const Key('home_roster_valhalla')), findsOneWidget);

        final Rect saved = tester.getRect(
          find.byKey(const Key('home_roster_saved')),
        );
        final Rect fallen = tester.getRect(
          find.byKey(const Key('home_roster_valhalla')),
        );

        expect(
          saved.width / saved.height,
          closeTo(2, 0.02),
          reason: '已保存入口图必须 2:1',
        );
        expect(
          fallen.width / fallen.height,
          closeTo(2, 0.02),
          reason: '英灵殿入口图必须 2:1',
        );
        expect(saved.width, closeTo(fallen.width, 0.5), reason: '两张必须等宽');
        expect(saved.top, lessThan(fallen.top), reason: '两张必须竖排');

        // 文案画在图上（不烧进图）：标题 + 张数
        // ★ P19：标题改「角色卡」（用户要求去掉「已保存的」前缀）
        expect(find.text('角色卡'), findsOneWidget);
        expect(find.text('1 位调查员'), findsOneWidget);
        expect(find.text('1 位长眠者'), findsOneWidget, reason: '英灵殿角标显示长眠张数');

        /* ★ P10 需求 4：英灵殿那张的「英灵殿」字样烧在底图里，首页**没有**这个
         Text（旧断言 `find.text('英灵殿')` 已不成立）。图里的字读屏读不到，
         所以真正的可访问性契约是「有且只有一个名为英灵殿的按钮」——
         这里按语义树断言，强度不低于原来的文本断言。 */
        // 标签会被合并（`container: true` 把角标文字也并进同一个节点），
        // 所以用正则匹配而不是精确相等。
        expect(
          find.bySemanticsLabel(RegExp('英灵殿')),
          findsOneWidget,
          reason: '烧在图里的标题必须由 Semantics 补上，且只能有一个',
        );
        final SemanticsNode valhallaNode = tester.getSemantics(
          find.byKey(const Key('home_roster_valhalla')),
        );
        expect(valhallaNode.label, contains('英灵殿'));
        expect(
          valhallaNode.flagsCollection.isButton,
          isTrue,
          reason: '入口是可点的，读屏要能听出「按钮」',
        );
        /* ★ P11 变更：新素材不再把字烧进图里，英灵殿那张和「已保存」走同一套
           叠字，所以首页**有且只有一个** Text('英灵殿') —— 这正是「两张卡弄成
           一样」的落地结果（旧断言是 findsNothing，因为当时图上自带标题）。 */
        expect(
          find.text('英灵殿'),
          findsOneWidget,
          reason: '图里已经没字了，App 叠的这层就是唯一可见的标题',
        );

        // 第一张 → 名册（已保存作用域：只有活着的卡）
        await tapKey(tester, 'home_roster_entry');
        expect(find.byType(RosterPage), findsOneWidget);
        expect(find.text('在世调查员'), findsOneWidget);
        expect(find.text('长眠调查员'), findsNothing, reason: '已保存入口不该混进英灵殿的卡');

        // 回首页点第二张 → 名册（英灵殿作用域）
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tapKey(tester, 'home_roster_valhalla');
        expect(find.byType(RosterPage), findsOneWidget);
        expect(find.text('长眠调查员'), findsOneWidget);
        expect(find.text('在世调查员'), findsNothing, reason: '英灵殿入口不该混进已保存的卡');
      } finally {
        semantics.dispose();
      }
    });
  });

  /* ==========================================================
   * 需求 8 的另一头：未开放规则的 id 不会被写进卡
   * ========================================================== */
  test('占位规则的 id 一律回退到已开放规则（写卡前的最后一道闸门）', () {
    for (final RuleMeta ph in RuleRegistry.placeholders) {
      expect(RuleRegistry.effectiveId(ph.id), RuleRegistry.defaultRule.id);
      expect(RuleRegistry.isAvailable(ph.id), isFalse);
    }
    expect(RuleRegistry.effectiveId('不存在'), RuleRegistry.defaultRule.id);
    expect(RuleRegistry.effectiveId(null), RuleRegistry.defaultRule.id);
  });
}
