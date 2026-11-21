// ============================================================
// p7_ai_caps_ui_test.dart — P7-B / P7-C：AI 车卡页的自定义房规 + 生成前选规则
//
// B：填值→立刻生效→生成用的 caps 变更 / 非法输入不写入 / 三档与自定义互斥 /
//    0=不限 / 随机卡与 AI 卡都吃到新上限。保存走注入的同步 port，
//    widget 里零 await、零 Timer（fake-async 安全）。
// C：未选规则不放「假按钮」/ 生成时把规则传进请求并写进卡 /
//    继续完善跳过规则步且进度分母自洽 / 手动新建仍从规则步开始。
// ============================================================

import 'package:dice_realm/domain/ai_caps.dart' show AiCaps, capsFromSettings;
import 'package:dice_realm/domain/character.dart'
    show Character, newCharacter, uidDeterministic;
import 'package:dice_realm/domain/js_compat.dart'
    show jsNum, nowClock, nowRng, setClock, setRng;
import 'package:dice_realm/domain/preset_gen.dart' as preset;
import 'package:dice_realm/domain/rule_registry.dart' show RuleRegistry;
import 'package:dice_realm/domain/rules_coc7.dart' show genMax, genMin, genStep;
import 'package:dice_realm/net/ai_create.dart' show AiCreateResult;
import 'package:dice_realm/repo/settings_repo.dart' show SettingsRepo;
import 'package:dice_realm/ui/ai_create_page.dart'
    show
        AiCapsSavePort,
        AiCreatePage,
        AiGenerateRequest,
        CapsInputResult,
        parseAiCapInput;
import 'package:dice_realm/ui/create/create_flow_page.dart' show CreateFlowPage;
import 'package:dice_realm/ui/create/steps/step_basics.dart' show StepBasics;
import 'package:dice_realm/ui/create/steps/step_rules.dart' show StepRules;
import 'package:dice_realm/ui/create/wizard_steps.dart'
    show WizardSteps, validateRules;
import 'package:flutter/material.dart'
    show
        ChoiceChip,
        FilledButton,
        Key,
        Offset,
        OutlinedButton,
        Scrollable,
        Text;
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart'
    show newMemorySettings, pumpApp, scrollTo, tapKey;
import 'support/oracle.dart' show Lcg, oracleNowMs;

const List<String> _keys9 = <String>[
  'str',
  'con',
  'siz',
  'dex',
  'app',
  'int',
  'pow',
  'edu',
  'luck',
];

/// 确定性造一张成品卡（走真规则引擎；不联网）。
Character _makeCard() {
  final savedRng = nowRng;
  final savedClock = nowClock;
  final savedUid = uidDeterministic;
  setRng(Lcg(77001).call);
  setClock(() => oracleNowMs);
  uidDeterministic = true;
  final Character c = preset.generateOne()!;
  c.raw['characterName'] = '测试调查员';
  setRng(savedRng);
  setClock(savedClock);
  uidDeterministic = savedUid;
  return c;
}

AiCreateResult _resultOf(Character c, AiCaps caps) => AiCreateResult(
  character: c,
  profile: const <String, Object?>{'fromAI': true},
  raw: const <String, Object?>{},
  caps: caps,
  attrScaled: false,
);

/// 同步保存替身：统计调用次数，绝不发起真实文件 I/O。
class _FakeCapsSavePort implements AiCapsSavePort {
  int saves = 0;

  @override
  void save() => saves++;
}

void _expectChipSelected(WidgetTester tester, String key, bool selected) {
  final ChoiceChip chip = tester.widget<ChoiceChip>(find.byKey(Key(key)));
  expect(chip.selected, selected, reason: '$key 选中态应为 $selected');
}

String _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data ?? '';

void main() {
  group('B · AI 车卡页自定义房规数值', () {
    testWidgets('填值 → 立刻写回设置 / presetSettings 现读生效 / 显示「自定义」',
        (WidgetTester tester) async {
      final SettingsRepo settings = await newMemorySettings();
      final _FakeCapsSavePort port = _FakeCapsSavePort();
      final Character card = _makeCard();
      await pumpApp(
        tester,
        settings: settings,
        home: AiCreatePage(
          capsSavePort: port,
          generate: (AiGenerateRequest req, void Function(String) onStage) async =>
              _resultOf(card, req.caps),
        ),
      );

      await scrollTo(tester, 'ai_cap_attr_input');
      await tester.enterText(
          find.byKey(const Key('ai_cap_attr_input')), '380');
      await tester.pumpAndSettle();

      expect(settings.aiAttrCap, 380, reason: '填完必须同步写回设置');
      expect(preset.presetSettings['aiAttrCap'], 380,
          reason: 'presetSettings 是变量，每次生成现读，改完立刻生效');
      expect(capsFromSettings(settings.settings).attrCap, 380);
      expect(port.saves, greaterThan(0), reason: '保存端口被同步调用');
      expect(_textOf(tester, 'ai_caps_text'), contains('属性总和 ≤ 380（含幸运）'));

      // 自定义值不等于任何一档 → 显示「自定义」且三档都不选中（不冒充「标准」）。
      expect(find.byKey(const Key('ai_cap_custom_state')), findsOneWidget);
      for (final String tier in <String>['不限', '标准', '严格']) {
        _expectChipSelected(tester, 'ai_cap_$tier', false);
      }

      // 另外两个输入框 + 含幸运开关也要真生效。
      await tester.enterText(
          find.byKey(const Key('ai_cap_occ_input')), '80');
      await tester.enterText(
          find.byKey(const Key('ai_cap_int_input')), '60');
      await tester.pumpAndSettle();
      expect(settings.aiOccPtsCap, 80);
      expect(settings.aiIntPtsCap, 60);
      expect(_textOf(tester, 'ai_caps_text'), contains('每项本职技能 ≤ 80'));
      expect(_textOf(tester, 'ai_caps_text'), contains('每项兴趣技能 ≤ 60'));

      await tester.tap(find.byKey(const Key('ai_cap_luck_without')));
      await tester.pumpAndSettle();
      expect(settings.aiAttrCapWithLuck, isFalse);
      expect(capsFromSettings(settings.settings).withLuck, isFalse);
      expect(_textOf(tester, 'ai_caps_text'), contains('不含幸运'));
    });

    testWidgets('三档快捷仍是一键预设，且不会把自定义伪装成标准',
        (WidgetTester tester) async {
      final SettingsRepo settings = await newMemorySettings();
      await pumpApp(
        tester,
        settings: settings,
        home: AiCreatePage(
          capsSavePort: _FakeCapsSavePort(),
          generate: (AiGenerateRequest req, void Function(String) onStage) async =>
              _resultOf(_makeCard(), req.caps),
        ),
      );

      await scrollTo(tester, 'ai_cap_标准');
      await tapKey(tester, 'ai_cap_标准');
      expect(settings.aiAttrCap, 460);
      expect(settings.aiOccPtsCap, 85);
      expect(settings.aiIntPtsCap, 70);
      expect(settings.aiAttrCapWithLuck, isTrue);
      _expectChipSelected(tester, 'ai_cap_标准', true);
      expect(find.byKey(const Key('ai_cap_custom_state')), findsNothing);
      expect(_textOf(tester, 'ai_caps_text'), contains('属性总和 ≤ 460（含幸运）'));

      // 自定义值 → 「标准」立刻取消选中，并显示自定义态。
      await tester.enterText(
          find.byKey(const Key('ai_cap_attr_input')), '999');
      await tester.pumpAndSettle();
      _expectChipSelected(tester, 'ai_cap_标准', false);
      expect(find.byKey(const Key('ai_cap_custom_state')), findsOneWidget);
    });

    testWidgets('0 / 留空 = 不限；「不限」档与自定义互斥',
        (WidgetTester tester) async {
      final SettingsRepo settings = await newMemorySettings();
      await pumpApp(
        tester,
        settings: settings,
        home: AiCreatePage(
          capsSavePort: _FakeCapsSavePort(),
          generate: (AiGenerateRequest req, void Function(String) onStage) async =>
              _resultOf(_makeCard(), req.caps),
        ),
      );

      await scrollTo(tester, 'ai_cap_标准');
      await tapKey(tester, 'ai_cap_标准');
      expect(settings.aiAttrCap, 460);

      await tester.enterText(find.byKey(const Key('ai_cap_attr_input')), '');
      await tester.enterText(find.byKey(const Key('ai_cap_occ_input')), '');
      await tester.enterText(find.byKey(const Key('ai_cap_int_input')), '');
      await tester.pumpAndSettle();
      expect(settings.aiAttrCap, 0);
      expect(settings.aiOccPtsCap, 0);
      expect(settings.aiIntPtsCap, 0);
      expect(capsFromSettings(settings.settings).active, isFalse);
      expect(_textOf(tester, 'ai_caps_text'), contains('暂未设置数值上限'));

      await tapKey(tester, 'ai_cap_不限');
      _expectChipSelected(tester, 'ai_cap_不限', true);
      expect(find.byKey(const Key('ai_cap_custom_state')), findsNothing);
    });

    test('非法输入（负数 / 非数字 / 超范围）一律拒收且有可见提示', () {
      for (final String bad in <String>['-1', 'abc', '3.5', '10000', '1e3']) {
        final CapsInputResult r = parseAiCapInput(bad, '属性总和上限');
        expect(r.ok, isFalse, reason: '$bad 应被拒收');
        expect(r.value, isNull);
        expect(r.error, contains('0-9999'));
        expect(r.error, contains('属性总和上限'));
      }
      for (final String good in <String>['', '  ', '0', '5', '380', '9999']) {
        final CapsInputResult r = parseAiCapInput(good, '属性总和上限');
        expect(r.ok, isTrue, reason: '"$good" 应合法');
        expect(r.value, isNotNull);
        expect(r.error, isEmpty);
      }
      expect(parseAiCapInput('', 'x').value, 0, reason: '留空 = 不限');
      expect(parseAiCapInput(' 380 ', 'x').value, 380);
    });

    testWidgets('UI 前置过滤：非数字灌不进去，设置不被写脏，且不报错',
        (WidgetTester tester) async {
      final SettingsRepo settings = await newMemorySettings();
      await pumpApp(
        tester,
        settings: settings,
        home: AiCreatePage(
          capsSavePort: _FakeCapsSavePort(),
          generate: (AiGenerateRequest req, void Function(String) onStage) async =>
              _resultOf(_makeCard(), req.caps),
        ),
      );
      await scrollTo(tester, 'ai_cap_occ_input');
      await tester.enterText(
          find.byKey(const Key('ai_cap_occ_input')), 'abc-9');
      await tester.pumpAndSettle();
      // digitsOnly 过滤后只剩 '9'；至少不能把 -9 之类的脏值写进去。
      expect(settings.aiOccPtsCap, greaterThanOrEqualTo(0));
      expect(settings.aiOccPtsCap, lessThanOrEqualTo(9999));
      expect(find.byKey(const Key('ai_caps_error')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('★ 随机卡与 AI 卡都吃到刚填的新上限（300，含幸运）',
        (WidgetTester tester) async {
      final SettingsRepo settings = await newMemorySettings();
      final Character card = _makeCard();
      AiGenerateRequest? captured;
      await pumpApp(
        tester,
        settings: settings,
        home: AiCreatePage(
          capsSavePort: _FakeCapsSavePort(),
          generate: (AiGenerateRequest req, void Function(String) onStage) async {
            captured = req;
            return _resultOf(card, req.caps);
          },
        ),
      );

      await scrollTo(tester, 'ai_cap_attr_input');
      await tester.enterText(
          find.byKey(const Key('ai_cap_attr_input')), '300');
      await tester.pumpAndSettle();

      // ① 随机卡：preset.generate 现读 presetSettings，整批共用同一份 caps。
      final List<Character> cards =
          preset.generate(5, preset.PresetOptions());
      expect(cards.length, 5);
      for (var i = 0; i < cards.length; i++) {
        var sum = 0;
        for (final String k in _keys9) {
          final int v = jsNum(cards[i].attributes[k]);
          expect(v % genStep, 0, reason: '随机卡#$i 的 $k=$v 不是 5 倍数');
          expect(v, inInclusiveRange(genMin, genMax));
          sum += v;
        }
        expect(sum, lessThanOrEqualTo(300),
            reason: '随机卡#$i 总和 $sum 没吃到新上限');
      }

      // ② AI 卡：生成请求里带的就是刚填的 caps，卡上带所选规则标记。
      //    先拖回顶部（scrollTo 只会向下滚，回不去）。
      await tester.drag(
          find.byType(Scrollable).first, const Offset(0, 4000));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('ai_desc')), '民国时期的私家侦探');
      await tapKey(tester, 'ai_generate');
      expect(captured, isNotNull);
      expect(captured!.caps.attrCap, 300);
      expect(captured!.caps.withLuck, isTrue);
      expect(captured!.ruleSystemId, RuleRegistry.defaultRule.id);
      expect(card.raw['ruleSystemId'], RuleRegistry.defaultRule.id);
    });
  });

  group('C · 生成前选规则 + 继续完善跳过规则步', () {
    testWidgets('未选规则：所有生成入口停用且有明确引导（K7 不放假按钮）',
        (WidgetTester tester) async {
      var calls = 0;
      await pumpApp(
        tester,
        home: AiCreatePage(
          initialRuleSystemId: '',
          capsSavePort: _FakeCapsSavePort(),
          generate: (AiGenerateRequest req, void Function(String) onStage) async {
            calls++;
            return _resultOf(_makeCard(), req.caps);
          },
        ),
      );

      expect(_textOf(tester, 'ai_rule_current'), contains('未选择'));
      expect(find.byKey(const Key('ai_rule_hint')), findsOneWidget);
      expect(find.byKey(const Key('ai_generate_rule_hint')), findsOneWidget);

      final FilledButton generate = tester
          .widget<FilledButton>(find.byKey(const Key('ai_generate')));
      expect(generate.onPressed, isNull, reason: '未选规则时生成按钮必须停用');
      expect(calls, 0);

      // 未开放项如实展示、不可选（规则卡片在顶部，此时还没滚走）。
      for (final r in RuleRegistry.placeholders) {
        final ChoiceChip chip =
            tester.widget<ChoiceChip>(find.byKey(Key('ai_rule_${r.id}')));
        expect(chip.onSelected, isNull, reason: '${r.id} 未开放，不可选');
      }

      // ★ P8：「一键出卡」从「就地生成随机候选」改成了**页面跳转**
      //   （随机页自带默认规则，跳过去一定出得了卡），所以它不再是"生成动作"，
      //   也不是假按钮 —— 断言改成「入口可用」，停用的判定只保留给真生成动作。
      await scrollTo(tester, 'ai_entry_random');
      final OutlinedButton random = tester
          .widget<OutlinedButton>(find.byKey(const Key('ai_entry_random')));
      expect(random.onPressed, isNotNull, reason: '一键出卡是导航入口，不该停用');

      // 拖回顶部再点规则（scrollTo 只会向下滚，回不去）。
      await tester.drag(
          find.byType(Scrollable).first, const Offset(0, 4000));
      await tester.pumpAndSettle();
      await tapKey(tester, 'ai_rule_${RuleRegistry.defaultRule.id}');
      final FilledButton enabled = tester
          .widget<FilledButton>(find.byKey(const Key('ai_generate')));
      expect(enabled.onPressed, isNotNull);
      expect(find.byKey(const Key('ai_rule_hint')), findsNothing);
      expect(_textOf(tester, 'ai_rule_current'),
          contains(RuleRegistry.defaultRule.shortName));
      expect(calls, 0);
    });

    testWidgets('生成结果带规则标记；「继续完善」首步不是规则且进度 1 / 8',
        (WidgetTester tester) async {
      final Character card = _makeCard();
      await pumpApp(
        tester,
        home: AiCreatePage(
          capsSavePort: _FakeCapsSavePort(),
          generate: (AiGenerateRequest req, void Function(String) onStage) async =>
              _resultOf(card, req.caps),
        ),
      );

      await tester.enterText(
          find.byKey(const Key('ai_desc')), '一个旧书店店员');
      await tapKey(tester, 'ai_generate');
      expect(card.raw['ruleSystemId'], RuleRegistry.defaultRule.id);
      expect(find.byKey(const Key('ai_result_card')), findsOneWidget);

      // ★ P9 需求 6：按钮拆成「就用这张」/「继续完善」，这里走后者。
      await scrollTo(tester, 'result_continue_edit');
      await tapKey(tester, 'result_continue_edit');
      expect(find.byType(CreateFlowPage), findsOneWidget);
      expect(_textOf(tester, 'step_progress'), '1 / 8',
          reason: '跳过 rules 后分母必须同步变 8');
      expect(find.byType(StepRules), findsNothing,
          reason: 'AI 卡不该再让玩家选一次规则');
      expect(find.byType(StepBasics), findsOneWidget,
          reason: '首步应是基本资料');
    });

    testWidgets('手动新建卡仍从规则步开始，进度 1 / 9',
        (WidgetTester tester) async {
      await pumpApp(tester, home: const CreateFlowPage());
      expect(_textOf(tester, 'step_progress'), '1 / 9');
      expect(find.byType(StepRules), findsOneWidget);
      expect(find.text(RuleRegistry.defaultRule.name), findsWidgets);
    });

    test('WizardSteps 跳步后分母 / 编号 / 末步判定全部自洽', () {
      final Character c = Character(newCharacter(RuleRegistry.defaultRule.id));
      final WizardSteps full = WizardSteps(
        draft: c,
        onChanged: () {},
        onJumpTo: (String _) {},
      );
      final WizardSteps skipped = WizardSteps(
        draft: c,
        onChanged: () {},
        onJumpTo: (String _) {},
        skipStepIds: const <String>{'rules'},
      );

      expect(full.length, 9);
      expect(full.ids.first, 'rules');
      expect(full.ids.last, 'summary');
      expect(skipped.length, 8);
      expect(skipped.ids.first, 'basics');
      expect(skipped.ids.last, 'summary');
      expect(skipped.has('rules'), isFalse);
      expect(skipped.indexOf('summary'), 7);
      expect(skipped.isLast(7), isTrue);
      expect(skipped.primaryLabel(7), '保存角色卡');
      expect(skipped.primaryLabel(0), '下一步');
      expect(validateRules(c), isNull,
          reason: '数据层校验仍要通过（卡上已有规则标记）');
    });

    test('规则元信息单一真源：注册表字段与 Coc7 常量一致', () {
      expect(RuleRegistry.defaultRule.id, RuleRegistry.coc7.id);
      expect(RuleRegistry.defaultRule.shortName, 'COC 7th');
      expect(RuleRegistry.defaultRule.name, '克苏鲁的呼唤 第七版');
      expect(RuleRegistry.defaultRule.rulebook, contains('规则书'));
      expect(RuleRegistry.byId(RuleRegistry.defaultRule.id),
          same(RuleRegistry.coc7));
      expect(RuleRegistry.byId('unknown'), isNull);
      expect(RuleRegistry.resolve('unknown'), same(RuleRegistry.defaultRule));
      expect(RuleRegistry.shortNameOf('unknown'), 'COC 7th');
      expect(RuleRegistry.isAvailable('unknown'), isFalse);
      expect(RuleRegistry.effectiveId('unknown'), RuleRegistry.coc7.id);
      for (final r in RuleRegistry.placeholders) {
        expect(r.available, isFalse);
        expect(RuleRegistry.isAvailable(r.id), isFalse);
        expect(RuleRegistry.effectiveId(r.id), RuleRegistry.coc7.id,
            reason: '占位规则绝不能写进卡');
      }
      expect(RuleRegistry.availableRules.length, 1);
    });
  });
}
