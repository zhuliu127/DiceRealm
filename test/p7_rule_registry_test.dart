// ============================================================
// p7_rule_registry_test.dart — P7-D：人物卡规则标记（单一真源 + 可查找注册表）
//
// 覆盖：三条生成路径 + 手动新建都带标记（值来自所选规则，不硬编码）、
//      注册表查找与占位回退、老卡 normalize 补齐、三处徽标显示、
//      导出 / 全量存档 / 导入往返不丢标记。
// ============================================================

import 'package:dice_realm/domain/character.dart'
    show Character, newCharacter, uidDeterministic;
import 'package:dice_realm/domain/easter_egg.dart' as egg;
import 'package:dice_realm/domain/js_compat.dart'
    show JsClock, JsRng, jsStr, nowClock, nowRng, setClock, setRng;
import 'package:dice_realm/domain/normalize.dart' show normalize;
import 'package:dice_realm/domain/preset_gen.dart' as preset;
import 'package:dice_realm/domain/rule_registry.dart' show RuleRegistry;
import 'package:dice_realm/repo/card_transfer.dart'
    show
        CardImportResult,
        exportBundleJson,
        exportCardJson,
        importIntoRepo,
        parseCardImport;
import 'package:dice_realm/ui/card_detail_page.dart' show CardDetailPage;
import 'package:dice_realm/ui/summary_card.dart' show SummaryCard;
import 'package:flutter/material.dart' show Key, MaterialApp, Scaffold, Text;
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart' show newMemoryRepo, pumpApp, tapKey;
import 'support/oracle.dart' show Lcg, oracleNowMs;

/// 确定性造一张成品卡（走真规则引擎；不联网）。
Character _makeCard() {
  final JsRng savedRng = nowRng;
  final JsClock savedClock = nowClock;
  final bool savedUid = uidDeterministic;
  setRng(Lcg(88001).call);
  setClock(() => oracleNowMs);
  uidDeterministic = true;
  final Character c = preset.generateOne()!;
  c.raw['characterName'] = '规则标记测试卡';
  setRng(savedRng);
  setClock(savedClock);
  uidDeterministic = savedUid;
  return c;
}

void _expectTagged(Character c, String label) {
  expect(c.ruleSystemId, RuleRegistry.defaultRule.id,
      reason: '$label 的 ruleSystemId 应来自所选规则');
  expect(jsStr(preset.summaryOf(c)['ruleSystemId']),
      RuleRegistry.defaultRule.id,
      reason: '$label 的候选卡摘要也要带标记');
}

void main() {
  group('D · 注册表是规则元信息的单一真源', () {
    test('all / placeholders / availableRules 与 Coc7 常量一致', () {
      expect(RuleRegistry.all.length, 3);
      expect(RuleRegistry.placeholders.length, 2);
      expect(RuleRegistry.availableRules.length, 1);
      expect(RuleRegistry.defaultRule.id, 'coc7');
      expect(RuleRegistry.defaultRule.name, '克苏鲁的呼唤 第七版');
      expect(RuleRegistry.defaultRule.shortName, 'COC 7th');
      expect(RuleRegistry.defaultRule.rulebook, '克苏鲁的呼唤 第七版规则书');
      expect(RuleRegistry.defaultRule.available, isTrue);
      expect(RuleRegistry.defaultRule.isPlaceholder, isFalse);
      for (final r in RuleRegistry.placeholders) {
        expect(r.isPlaceholder, isTrue);
        expect(r.available, isFalse);
      }
    });

    test('byId 精确查找（未知返回 null，不悄悄回退）；resolve / effectiveId 兜底',
        () {
      expect(RuleRegistry.byId(null), isNull);
      expect(RuleRegistry.byId(''), isNull);
      expect(RuleRegistry.byId('nope'), isNull);
      expect(RuleRegistry.byId(RuleRegistry.coc7.id), same(RuleRegistry.coc7));
      expect(RuleRegistry.resolve('nope'), same(RuleRegistry.defaultRule));
      expect(RuleRegistry.shortNameOf('nope'), 'COC 7th');
      expect(RuleRegistry.effectiveId(null), RuleRegistry.coc7.id);
      expect(RuleRegistry.effectiveId('nope'), RuleRegistry.coc7.id);
      expect(RuleRegistry.effectiveId(RuleRegistry.dnd5e.id),
          RuleRegistry.coc7.id,
          reason: '未开放占位规则绝不能写进卡');
      expect(RuleRegistry.isAvailable(RuleRegistry.dnd5e.id), isFalse);
    });

    test('ruleSystemIdOf：未传 / 占位 / 未知一律回退已开放的默认规则', () {
      expect(preset.ruleSystemIdOf(), RuleRegistry.defaultRule.id);
      expect(preset.ruleSystemIdOf(preset.PresetOptions()),
          RuleRegistry.defaultRule.id);
      expect(
        preset.ruleSystemIdOf(
          preset.PresetOptions(ruleSystemId: RuleRegistry.dnd5e.id),
        ),
        RuleRegistry.defaultRule.id,
      );
      expect(
        preset.ruleSystemIdOf(preset.PresetOptions(ruleSystemId: 'unknown')),
        RuleRegistry.defaultRule.id,
      );
      expect(
        preset.ruleSystemIdOf(
          preset.PresetOptions(ruleSystemId: RuleRegistry.coc7.id),
        ),
        RuleRegistry.coc7.id,
      );
    });
  });

  group('D · 四条生成路径都带规则标记', () {
    test('5 张随机卡：整批同一规则；彩蛋卡同源；AI 卡 buildFrom 也带', () {
      final List<Character> cards = preset.generate(
        5,
        preset.PresetOptions(ruleSystemId: RuleRegistry.defaultRule.id),
      );
      expect(cards.length, 5);
      for (var i = 0; i < cards.length; i++) {
        _expectTagged(cards[i], '随机卡#$i');
      }

      final target = egg.all().first;
      final Character? easter = preset.generateOne(
        preset.PresetOptions(
          ruleSystemId: RuleRegistry.defaultRule.id,
          profile: egg.toProfile(target),
        ),
      );
      expect(easter, isNotNull);
      expect(easter!.raw['isEasterEgg'], isTrue);
      _expectTagged(easter, '彩蛋卡');

      final Character? ai = preset.buildFrom(
        <String, Object?>{'fromAI': true, 'name': 'AI 测试调查员'},
        null,
        preset.PresetOptions(ruleSystemId: RuleRegistry.defaultRule.id),
      );
      expect(ai, isNotNull);
      _expectTagged(ai!, 'AI 卡');
    });

    test('手动新建：规则 id 来自注册表（UI 入口显式传，不硬编码字面量）', () {
      final Character manual =
          Character(newCharacter(RuleRegistry.defaultRule.id));
      expect(manual.ruleSystemId, RuleRegistry.defaultRule.id);
      expect(manual.ruleSystemId, isNot(''), reason: '不许是空标记');
    });
  });

  group('D · 老卡 normalize / 导出 / 存档 / 导入往返', () {
    test('★ 老卡缺 ruleSystemId → normalize 补默认值；不伪造来源标记', () {
      final Map<String, Object?> raw = newCharacter();
      raw.remove('ruleSystemId');
      final Character c = Character(raw);
      expect(c.raw.containsKey('ruleSystemId'), isFalse,
          reason: '读进来时确实没有标记（不伪造「原本就带标记」）');

      final Character n = normalize(c);
      expect(n.ruleSystemId, RuleRegistry.defaultRule.id);
      expect(raw['ruleSystemId'], RuleRegistry.defaultRule.id);
      // 只补 id 本身，不额外造「原本就带标记」的出处字段。
      expect(c.raw.containsKey('ruleTagged'), isFalse);
      expect(c.raw.containsKey('ruleMarkedFromStart'), isFalse);

      // 幂等：第二遍不再改动。
      normalize(n);
      expect(n.ruleSystemId, RuleRegistry.defaultRule.id);
    });

    test('单卡导出 / 全量存档 / 导入往返都不丢标记', () async {
      final c = _makeCard();
      c.raw['ruleSystemId'] = RuleRegistry.defaultRule.id;
      c.raw['characterName'] = '往返测试卡';

      final String single = exportCardJson(c);
      final CardImportResult parsed = parseCardImport(single);
      expect(parsed.count, 1);
      expect(parsed.cards.single['ruleSystemId'], RuleRegistry.defaultRule.id);

      final String bundle = exportBundleJson(<Character>[c, _makeCard()]);
      final CardImportResult parsedBundle = parseCardImport(bundle);
      expect(parsedBundle.bundle, isTrue);
      expect(parsedBundle.count, 2);
      for (final Map<String, Object?> rawCard in parsedBundle.cards) {
        expect(rawCard['ruleSystemId'], RuleRegistry.defaultRule.id);
      }

      final repo = await newMemoryRepo();
      final List<Character> imported = await importIntoRepo(repo, single);
      expect(imported.length, 1);
      expect(imported.single.ruleSystemId, RuleRegistry.defaultRule.id);
      expect(repo.all.single.ruleSystemId, RuleRegistry.defaultRule.id,
          reason: '存档落库后仍保留标记');
    });

    test('已有非默认标记不被导出 / 导入强制改写成默认', () async {
      final c = _makeCard();
      c.raw['characterName'] = '未来规则卡';
      c.raw['ruleSystemId'] = 'future-rule';
      final repo = await newMemoryRepo();
      final List<Character> imported =
          await importIntoRepo(repo, exportCardJson(c));
      expect(imported.single.ruleSystemId, 'future-rule');
      expect(jsStr(parseCardImport(exportCardJson(c)).cards.single['ruleSystemId']),
          'future-rule');
    });
  });

  group('D · 卡面 / 卡列表 / 详情都能看到规则徽标', () {
    testWidgets('候选卡卡面：summary_rule_badge 显示规则简称',
        (WidgetTester tester) async {
      final c = _makeCard();
      c.raw['ruleSystemId'] = RuleRegistry.defaultRule.id;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SummaryCard(summary: preset.summaryOf(c), index: 0),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('summary_rule_badge')), findsOneWidget);
      final Text badge = tester.widget<Text>(find.descendant(
        of: find.byKey(const Key('summary_rule_badge')),
        matching: find.byType(Text),
      ));
      expect(badge.data, RuleRegistry.defaultRule.shortName);
    });

    testWidgets('卡列表：每张卡都有 card_rule_badge_<id> 且显示简称',
        (WidgetTester tester) async {
      final c = _makeCard();
      c.raw['ruleSystemId'] = RuleRegistry.defaultRule.id;
      final repo = await newMemoryRepo();
      await repo.save(c);
      await pumpApp(tester, repo: repo);
      // ★ P8：卡列表从首页搬到二级页「角色档案」，徽标 Key 依旧逐卡保留
      await tapKey(tester, 'home_roster_entry');

      expect(find.byKey(Key('card_rule_badge_${c.id}')), findsOneWidget);
      final Text badge = tester.widget<Text>(find.descendant(
        of: find.byKey(Key('card_rule_badge_${c.id}')),
        matching: find.byType(Text),
      ));
      expect(badge.data, RuleRegistry.defaultRule.shortName);
    });

    testWidgets('详情页「概要」里有规则行（简称 + 全名）',
        (WidgetTester tester) async {
      final c = _makeCard();
      c.raw['ruleSystemId'] = RuleRegistry.defaultRule.id;
      final repo = await newMemoryRepo();
      await repo.save(c);
      await pumpApp(tester, repo: repo, home: CardDetailPage(cardId: c.id));

      expect(find.text('规则'), findsOneWidget);
      expect(
        find.text(
          '${RuleRegistry.defaultRule.shortName} · '
          '${RuleRegistry.defaultRule.name}',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
