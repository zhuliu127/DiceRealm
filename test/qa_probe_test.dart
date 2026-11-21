// ============================================================
// qa_probe_test.dart — QA 独立复核探针（不依赖工程师既有的测试）
//
// 每条探针都尽量从「反面 / 边界」去撞实现，而不是复述实现里的分支：
//   H1 空输入 ≠ 0        H2 改 HP 不触发疯狂
//   H3 撕卡口径          H4 濒死不被 recalc 治活
//   H5 导入导出          H6 卡片契约（键树，见 tool/qa/legacy_probe.js 对照）
//   S1..S6 结构性风险
//
// 这个文件是**复核产物**：断言写的是「按 PRD / 旧版契约应当如何」，
// 不是「实现现在如何」。红的就是缺陷。
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/data/skills.dart';
import 'package:dice_realm/domain/data/spells.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/normalize.dart';
import 'package:dice_realm/domain/occupation.dart';
import 'package:dice_realm/domain/rules_coc7.dart';
import 'package:dice_realm/domain/skillmodel.dart' hide find;
import 'package:dice_realm/repo/card_transfer.dart';
import 'package:dice_realm/repo/character_repo.dart';
import 'package:dice_realm/ui/card_edit/assets_logic.dart';
import 'package:dice_realm/ui/card_edit/background_logic.dart';
import 'package:dice_realm/ui/card_edit/combat_logic.dart';
import 'package:dice_realm/ui/card_edit/madness_table_sheet.dart';
import 'package:dice_realm/ui/card_view.dart';
import 'package:dice_realm/ui/create/chargen_logic.dart';
import 'package:dice_realm/ui/create/wizard_checks.dart';
import 'package:dice_realm/ui/create/wizard_steps.dart';
import 'package:dice_realm/ui/status_ops.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// 一张属性齐备、已 recalc 的卡（HP=10 / MP=10 / SAN=50 左右）
Character probeCard({int hp = 7, int san = 40}) {
  final c = Character(newCharacter());
  c.raw['id'] = 'probe001';
  c.raw['characterName'] = '探针';
  c.raw['playerName'] = 'QA';
  c.basicInfo['age'] = 30;
  c.raw['age'] = 30;
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
  c.status['currentHP'] = hp;
  c.status['currentSAN'] = san;
  c.status['_inited'] = true;
  return c;
}

Map<String, Object?> deepCopy(Map<String, Object?> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, Object?>;

void main() {
  // ==========================================================
  // H1 空输入 ≠ 0
  // ==========================================================
  group('H1 空输入 ≠ 0（状态数字通道）', () {
    const fields = <String>[
      'currentHP',
      'currentMP',
      'currentSAN',
      'currentLuck',
    ];
    // 「1.5e3」不列入：jsParseInt 取数字前缀 = 1，与 JS parseInt 一致；
    // 且输入框有 FilteringTextInputFormatter.digitsOnly，'.' / 'e' 根本打不进去。
    const badInputs = <String>['', '   ', '\t\n', 'abc', '-', '--', '全角１２'];

    test('空串 / 纯空白 / 非数字 / 单个减号 → 一律不写模型（值不变）', () {
      for (final f in fields) {
        for (final raw in badInputs) {
          final c = probeCard();
          final before = c.status[f];
          final wrote = commitStatusNumber(c, f, raw);
          expect(wrote, isFalse, reason: '$f 输入 ${jsonEncode(raw)} 不该写入');
          expect(c.status[f], before, reason: '$f 输入 ${jsonEncode(raw)} 后值被改了');
          expect(
            c.status[statusTouchedKeys[f]!],
            isNull,
            reason: '$f 输入 ${jsonEncode(raw)} 不该打「用户改过」标记',
          );
        }
      }
    });

    test('反面：真输入 0 → 必须写入，并且打标记（否则规则被「修没了」）', () {
      for (final f in fields) {
        final c = probeCard();
        final wrote = commitStatusNumber(c, f, '0');
        expect(wrote, isTrue, reason: '$f 输入 "0" 必须写入');
        expect(jsNum(c.status[f]), 0, reason: '$f 输入 "0" 后应为 0');
        expect(
          c.status[statusTouchedKeys[f]!],
          isTrue,
          reason: '$f 输入 "0" 必须打标记',
        );
      }
    });

    test('输入 0 之后 recalc 不得把值补回去（H4 的姊妹面）', () {
      final c = probeCard(hp: 8);
      commitStatusNumber(c, 'currentHP', '0');
      recalc(c);
      recalc(c);
      expect(jsNum(c.status['currentHP']), 0);
    });

    testWidgets('UI 全选删除 HP 输入框后直接点保存（不失焦）→ HP 不变、不弹撕卡框', (tester) async {
      final card = probeCard(hp: 7);
      final repo = await pumpCardDetail(tester, card: card);
      await tapKey(tester, 'btn_edit');

      final hpField = find.byKey(const Key('status_hp'));
      await scrollTo(tester, 'status_hp');
      expect(hpField, findsOneWidget);
      await tester.enterText(hpField, '');
      await tester.pump();

      // 不失焦，直接点保存
      await tester.tap(find.byKey(const Key('btn_save')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('confirm_rip')),
        findsNothing,
        reason: '清空输入框不等于 0，不该触发撕卡确认',
      );
      final saved = repo.get(card.id)!;
      expect(jsNum(saved.status['currentHP']), 7, reason: '保存后 HP 必须仍是 7');
      expect(isRippedCard(saved), isFalse);
    });
  });

  // ==========================================================
  // H2 改 HP 不触发疯狂
  // ==========================================================
  group('H2 改 HP 不触发疯狂', () {
    test('只改 HP（不动 SAN）→ madness / mental 都不新增', () {
      final c = probeCard(hp: 10, san: 40);
      recalc(c);
      final madBefore = (c.raw['madness'] as List).length;
      final mentalBefore = jsonEncode(c.status['mental']);

      commitStatusNumber(c, 'currentHP', '0');
      prepareStatusSave(c);

      expect(
        (c.raw['madness'] as List).length,
        madBefore,
        reason: '改 HP 不该新增疯狂条目',
      );
      expect(
        jsonEncode(c.status['mental']),
        mentalBefore,
        reason: '改 HP 不该改精神状态',
      );
    });

    test('连续多次保存（模拟反复点保存）→ 疯狂条目数不增长', () {
      final c = probeCard(hp: 10, san: 40);
      recalc(c);
      for (var i = 0; i < 5; i++) {
        prepareStatusSave(c);
        normalize(c);
      }
      expect((c.raw['madness'] as List), isEmpty);
    });

    test('反面：真掉 SAN 到 0 → 永久疯狂逻辑仍然生效', () {
      final c = probeCard(hp: 10, san: 40);
      recalc(c);
      commitStatusNumber(c, 'currentSAN', '0');
      final pending = prepareStatusSave(c);
      expect(pending.sanDown, isTrue);
      applyRip(c, pending);
      expect(mentalList(c), contains(mentalPermanent));
      expect(jsStr(c.status['body']), isNot('死亡'), reason: 'SAN 归零是永久疯狂，不是死亡');
    });

    test('疯狂表没有「默认选中项」（v2.1.8 的真实根因不得复现）', () {
      // 疯狂表是 10 行「点格子」式界面：没有持久化的 selection state。
      // 这里用「重复 applySymptomToBackground 同一条」来证明不会越点越多。
      final c = probeCard();
      normalize(c);
      final first = applySymptomToBackground(c, '恐惧症', '深渊恐惧', '怕黑');
      final again = applySymptomToBackground(c, '恐惧症', '深渊恐惧', '怕黑');
      expect(first, greaterThan(0));
      expect(again, 0, reason: '同一条症状重复应用不得重复入数组');
      expect((c.raw['madness'] as List).length, 1);
    });
  });

  // ==========================================================
  // H3 撕卡口径
  // ==========================================================
  group('H3 撕卡口径', () {
    test('HP 归零 → hpDown 且 applyRip 后 body=死亡', () {
      final c = probeCard(hp: 10);
      recalc(c);
      commitStatusNumber(c, 'currentHP', '0');
      final p = prepareStatusSave(c);
      expect(p.hit, isTrue);
      expect(p.hpDown, isTrue);
      expect(p.reasons.join(), contains('死亡'));
      applyRip(c, p);
      expect(jsStr(c.status['body']), '死亡');
      expect(isRippedCard(c), isTrue);
    });

    test('SAN 归零 → 永久疯狂（不进死亡分支）', () {
      final c = probeCard(san: 40);
      recalc(c);
      commitStatusNumber(c, 'currentSAN', '0');
      final p = prepareStatusSave(c);
      expect(p.sanDown, isTrue);
      expect(p.hpDown, isFalse);
      applyRip(c, p);
      expect(mentalList(c), <String>[mentalPermanent]);
      expect(jsStr(c.status['body']), isNot('死亡'));
    });

    test('两种撕卡都进英灵殿（alive / fallen 分区）', () async {
      final repo = CharacterRepo(storage: MemoryStorage());
      await repo.load();
      final dead = probeCard(hp: 1);
      dead.raw['id'] = 'dead001';
      commitStatusNumber(dead, 'currentHP', '0');
      applyRip(dead, prepareStatusSave(dead));

      final mad = probeCard(san: 1);
      mad.raw['id'] = 'mad0001';
      commitStatusNumber(mad, 'currentSAN', '0');
      applyRip(mad, prepareStatusSave(mad));

      await repo.save(dead);
      await repo.save(mad);

      expect(repo.fallen.map((c) => c.id).toSet(), <String>{
        'dead001',
        'mad0001',
      });
      expect(repo.alive.map((c) => c.id), isNot(contains('dead001')));
      expect(repo.alive.map((c) => c.id), isNot(contains('mad0001')));
    });

    testWidgets('HP 归零 → 保存弹二次确认 → 点「取消」→ 盘上什么都没写', (tester) async {
      final card = probeCard(hp: 7);
      final repo = await pumpCardDetail(tester, card: card);
      await tapKey(tester, 'btn_edit');
      await scrollTo(tester, 'status_hp');
      await tester.enterText(find.byKey(const Key('status_hp')), '0');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_save')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('confirm_rip')),
        findsOneWidget,
        reason: 'HP 归零必须二次确认',
      );

      await tester.tap(find.byKey(const Key('cancel_rip')));
      await tester.pumpAndSettle();

      final stored = repo.get(card.id)!;
      expect(jsNum(stored.status['currentHP']), 7, reason: '取消后不得写入 HP=0');
      expect(jsStr(stored.status['body']), isNot('死亡'));
      expect(isRippedCard(stored), isFalse);
    });

    testWidgets('HP 归零 → 确认撕卡 → 卡进英灵殿', (tester) async {
      final card = probeCard(hp: 7);
      final repo = await pumpCardDetail(tester, card: card);
      await tapKey(tester, 'btn_edit');
      await scrollTo(tester, 'status_hp');
      await tester.enterText(find.byKey(const Key('status_hp')), '0');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_rip')));
      await tester.pumpAndSettle();

      final stored = repo.get(card.id)!;
      expect(
        jsNum(stored.status['currentHP']),
        0,
        reason: '确认后 HP 必须留在 0（不得被治活）',
      );
      expect(jsStr(stored.status['body']), '死亡');
      expect(repo.fallen.map((c) => c.id), contains(card.id));
    });

    testWidgets('英灵殿里的卡点得开（不抛异常、能看到英灵殿横幅）', (tester) async {
      final dead = probeCard(hp: 1);
      dead.raw['characterName'] = '已阵亡者';
      commitStatusNumber(dead, 'currentHP', '0');
      applyRip(dead, prepareStatusSave(dead));

      final repo = await newMemoryRepo();
      await repo.save(dead);
      await pumpApp(tester, repo: repo);
      /* ★ P10 需求 4：英灵殿入口图里曾烧进「英灵殿 / 英灵长眠于此 /
         致敬每一位调查员」，App 当时不许再叠标题。
         ★ P11：新素材不再烧字（左侧留白），两张入口变成同一套叠字，
         所以首页重新有**且只有一个** Text('英灵殿')；同时保留语义入口断言
         （唯一一个语义名为「英灵殿」且声明 button 的节点）。 */
      expect(find.text('英灵殿'), findsOneWidget, reason: '图里没字了，App 叠这层');
      final Finder valhallaEntry = find.byWidgetPredicate(
        (Widget w) => w is Semantics && w.properties.label == '英灵殿',
      );
      expect(valhallaEntry, findsOneWidget);
      expect(
        tester.widget<Semantics>(valhallaEntry).properties.button,
        isTrue,
      );

      // ★ P8：卡片收进二级页「角色档案」，先点首页入口再点卡名。
      //   断言本身（点开不崩、只读、不能编辑）一个字都没放宽。
      // ★ P10 需求 2：撕卡只出现在「英灵殿」那一栏，入口也要走英灵殿那张图。
      await tester.tap(find.byKey(const Key('home_roster_valhalla')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('已阵亡者').first);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '英灵殿的卡详情页不该崩');
      expect(find.textContaining('英灵殿'), findsWidgets);
      // 撕卡后不可编辑 + 不能进编辑态
      expect(find.byKey(const Key('btn_edit')), findsNothing);
    });
  });

  // ==========================================================
  // H4 濒死不得被 recalc 治活
  // ==========================================================
  group('H4 濒死不得被 recalc 治活', () {
    test('导入一张 HP=0 的卡 → recalc 两次仍然 HP=0', () async {
      // 老存档形状：属性齐备、HP 被打到 0、SAN 还有（模拟跑团受伤后导出的卡）
      final src = probeCard(hp: 10, san: 40);
      recalc(src);
      src.raw['id'] = 'dying001';
      src.status['currentHP'] = 0;
      src.status.remove('_hpTouched');
      final json = exportCardJson(src);

      final repo = CharacterRepo(storage: MemoryStorage());
      await repo.load();
      final imported = await importIntoRepo(repo, json);
      final c = imported.first;

      expect(
        jsNum(c.status['currentHP']),
        0,
        reason: '导入的濒死卡被 recalc 补满了 —— 等价于「被治活」',
      );
      // 再跑两遍，确认不是「碰巧第一遍没补」
      recalc(c);
      recalc(c);
      expect(jsNum(c.status['currentHP']), 0, reason: 'recalc 连跑后 HP 仍应为 0');
    });

    test('反向对照：导入一张 SAN=0 的永久疯狂卡 → 不得把 SAN 补回去', () async {
      final src = probeCard(hp: 10, san: 40);
      recalc(src);
      src.raw['id'] = 'perm001';
      src.status['currentSAN'] = 0;
      src.status['mental'] = <Object?>['永久疯狂'];
      src.status.remove('_sanTouched');
      final json = exportCardJson(src);

      final repo = CharacterRepo(storage: MemoryStorage());
      await repo.load();
      final c = (await importIntoRepo(repo, json)).first;
      expect(
        jsNum(c.status['currentSAN']),
        0,
        reason: '永久疯狂卡的 SAN 被补回 —— 同一处 guard 的另一面',
      );
    });

    test('反面：不打 _hpTouched 时确实会补满（证明守卫真的在起作用）', () {
      final c = probeCard(hp: 10);
      recalc(c);
      c.status['currentHP'] = 0;
      c.status.remove('_hpTouched');
      recalc(c);
      expect(
        jsNum(c.status['currentHP']),
        greaterThan(0),
        reason: '没有守卫时应当补满 —— 若这条不成立，说明守卫没了，另一条也就没意义',
      );
    });

    test('经 status_ops 写 0（用户手动）→ recalc 不得补回', () {
      final c = probeCard(hp: 10);
      recalc(c);
      setStatusNumber(c, 'currentHP', 0);
      recalc(c);
      recalc(c);
      expect(jsNum(c.status['currentHP']), 0);
    });
  });

  // ==========================================================
  // H5 导入导出
  // ==========================================================
  group('H5 导入导出', () {
    test('单卡导出与旧版 JSON.stringify 逐字节一致（键序 / 2 空格 / 中文不转义）', () {
      var legacy = File('test/fixtures/qa_legacy_export.json')
          .readAsStringSync();
      // fixture 是 console.log 落的，尾部多一个换行；JSON.stringify 本身不带
      if (legacy.endsWith('\n')) legacy = legacy.substring(0, legacy.length - 1);
      final obj = jsonDecode(legacy) as Map<String, Object?>;
      final data = Map<String, Object?>.from(obj['data'] as Map);
      final dart = exportCardJson(Character(data));
      expect(dart.length, legacy.length, reason: '字节长度不同');
      expect(dart, legacy, reason: '与旧版 exportCharacter 输出不一致');
    });

    test('导出 → 导入 → 逐字段深比较（除 id）', () async {
      final c = probeCard(hp: 9, san: 33);
      normalize(c);
      recalc(c);
      final json = exportCardJson(c);
      final repo = CharacterRepo(storage: MemoryStorage());
      await repo.load();
      final back = (await importIntoRepo(repo, json)).first;

      final a = deepCopy(c.raw)..remove('id');
      final b = deepCopy(back.raw)..remove('id');
      // updatedAt 由 repo.save 更新，属正常差异；其余必须全等
      a.remove('updatedAt');
      b.remove('updatedAt');
      expect(b, a, reason: '导出→导入后卡片字段发生了漂移');
    });

    for (final f in <String>[
      'legacy_card_export.json',
      'legacy_bundle_export.json',
      'legacy_card_blocks_export.json',
    ]) {
      test('导入旧版真实 fixture：$f（逐字段 + 不崩）', () async {
        final text = File('test/fixtures/$f').readAsStringSync();
        final repo = CharacterRepo(storage: MemoryStorage());
        await repo.load();
        final cards = await importIntoRepo(repo, text);
        expect(cards, isNotEmpty);
        for (final c in cards) {
          // normalize 是幂等的：再跑一遍必须零变化
          final snapshot = deepCopy(c.raw);
          normalize(c);
          expect(
            jsonEncode(c.raw),
            jsonEncode(snapshot),
            reason: '$f 导入后 normalize 不幂等',
          );
          // 关键字段必须还在
          expect(c.raw.containsKey('characterName'), isTrue);
          expect(c.raw.containsKey('status'), isTrue);
        }
      });
    }
  });

  // ==========================================================
  // S1 步骤映射（checkList 每条 → 真正能修它的那一页）
  // ==========================================================
  group('S1 步骤映射', () {
    test('checkList 每条 label 都映射到「真能修它」的步骤', () {
      final c = probeCard();
      normalize(c);
      recalc(c);
      final rows = checkList(c);
      // 语义期望表（与实现无关，按「这个问题在哪一页能改」定）
      const expected = <String, String>{
        '角色姓名已填写': 'basics',
        '玩家名称已填写': 'basics',
        '年龄合法': 'basics',
        '属性合法（15-90 且为 5 的倍数）': 'attrs',
        '已选择职业': 'basics',
        '职业限定技能选择完成': 'skills',
        '信用评级在职业范围内': 'assets',
        '职业技能点未超额': 'skills',
        '兴趣技能点未超额': 'skills',
        '技能未超过上限': 'skills',
      };
      for (final r in rows) {
        final label = jsStr(r['label']);
        final want = expected[label];
        expect(want, isNotNull, reason: '出现未登记的新检查项：$label');
        // ⚠️ 必须带上 label：`step=2` 被「已选择职业」与「职业限定技能选择完成」
        // 两个语义不同的检查项共用（下方期望表本身就对同一个 step 要两个答案），
        // 只给 step 数字的版本无法区分 —— 二元查表是 D2 的修法，期望表一字未动。
        final got = stepIdForCheck(r['step'], jsStr(r['label']));
        expect(
          got,
          want,
          reason: '「$label」应跳到 $want，实际跳到 $got（step=${r['step']}）',
        );
      }
    });

    test('映射出来的 stepId 在向导注册表里真实存在', () {
      final c = probeCard();
      final steps = WizardSteps(draft: c, onChanged: () {}, onJumpTo: (_) {});
      for (final r in checkList(c)) {
        final id = stepIdForCheck(r['step']);
        expect(id, isNotNull, reason: 'step=${r['step']} 没有映射');
        expect(steps.has(id!), isTrue, reason: '映射出的 $id 不在向导里');
      }
    });

    testWidgets('概要页点「职业限定技能选择完成」的去修复 → 应落在技能页', (tester) async {
      final c = probeCard();
      normalize(c);
      // occ2 = 会计师：credit 30-70，skillText 含「任意其他两项」→ 有未满足的限定技能
      c.raw['occupationId'] = 'occ2';
      recalc(c);
      syncSkills(c);
      materializeOccupationalSkills(c);
      final checks = wizardChecks(c);
      final row = checks.firstWhere((x) => x.label == '职业限定技能选择完成');
      expect(row.ok, isFalse, reason: '构造前提失败：该项应当报红');
      expect(
        row.stepId,
        'skills',
        reason: '「职业限定技能选择完成」只能在技能页修复，跳到 ${row.stepId} 是错的',
      );
    });
  });

  // ==========================================================
  // S2 信用评级占用职业点 + 步骤顺序
  // ==========================================================
  group('S2 信用评级占用职业点', () {
    test('assets 步骤排在 skills 之前', () {
      final c = probeCard();
      final steps = WizardSteps(draft: c, onChanged: () {}, onJumpTo: (_) {});
      final ids = steps.debugIds;
      expect(ids.indexOf('assets'), greaterThanOrEqualTo(0));
      expect(
        ids.indexOf('assets'),
        lessThan(ids.indexOf('skills')),
        reason: '资产（信用评级）必须排在技能之前，否则职业点算错：$ids',
      );
    });

    test('改信用评级后 occupationPoints.used 同步变化', () {
      final c = probeCard();
      c.raw['occupationId'] = 'occ2'; // 会计师，credit 30-70
      normalize(c);
      syncSkills(c);
      materializeOccupationalSkills(c);
      final before = jsNum(occupationPoints(c)['used']);

      const target = 50;
      final r = commitCreditRating(c, '$target');
      expect(r.written, isTrue, reason: '合法信用评级应写入（${r.error ?? ''}）');
      final after = jsNum(occupationPoints(c)['used']);
      expect(
        after - before,
        target,
        reason: '信用评级 $target 点必须计入职业点（before=$before after=$after）',
      );
    });

    test('信用评级调低会把多占的职业点还回去', () {
      final c = probeCard();
      c.raw['occupationId'] = 'occ2'; // 会计师 credit 30-70
      normalize(c);
      syncSkills(c);
      materializeOccupationalSkills(c);
      commitCreditRating(c, '60');
      final high = jsNum(occupationPoints(c)['used']);
      final r = commitCreditRating(c, '30'); // 仍在区间内
      expect(r.written, isTrue);
      final low = jsNum(occupationPoints(c)['used']);
      expect(high - low, 30);
    });
  });

  // ==========================================================
  // S3 武器使用技能清单
  // ==========================================================
  group('S3 武器使用技能清单', () {
    test('清单外技能（心理学）不可选', () {
      expect(isValidWeaponSkill('心理学'), isFalse);
      expect(
        weaponSkillOptions(probeCard()).map((o) => o.value),
        isNot(contains('心理学')),
      );
    });

    test('清单正好是 7 格斗 + 5 射击 + 投掷/炮术/爆破 = 15 项', () {
      final names = combatSkillNames();
      expect(names.length, 15, reason: '实际清单：$names');
      for (final x in <String>['投掷', '炮术', '爆破']) {
        expect(names, contains(x));
      }
      // 7 格斗
      final fighting = cocSkills.firstWhere((d) => d['id'] == 'fighting');
      for (final sub in asList(fighting['subskills'])) {
        expect(names, contains(jsStr(asMap(sub)['name'])));
      }
      // 5 射击
      final firearms = cocSkills.firstWhere((d) => d['id'] == 'firearms');
      for (final sub in asList(firearms['subskills'])) {
        expect(names, contains(jsStr(asMap(sub)['name'])));
      }
    });
  });

  // ==========================================================
  // S4 法术深拷贝
  // ==========================================================
  group('S4 法术深拷贝', () {
    test('加一条法术并改 name / variants，cocSpells 源表一字不变', () {
      final before = jsonEncode(cocSpells);
      final src = cocSpells.firstWhere(
        (s) => asList(s['variants']).isNotEmpty,
        orElse: () => cocSpells.first,
      );
      final c = probeCard();
      final copy = copySpell(src);
      c.mythos['spells'] = <Object?>[copy];

      copy['name'] = '被我改过的名字';
      final variants = asList(copy['variants']);
      if (variants.isNotEmpty) {
        asMap(variants.first)['name'] = '被我改过的变体';
        asMap(variants.first)['cost'] = '被我改过的消耗';
      }

      expect(jsonEncode(cocSpells), before, reason: '静态法术表被卡片污染（浅拷贝）');
      expect(jsonEncode(copy), isNot(jsonEncode(src)), reason: '改动没落到副本上？');
    });

    test('两次 copySpell 互不共享引用（含嵌套 variants）', () {
      final src = cocSpells.firstWhere(
        (s) => asList(s['variants']).isNotEmpty,
        orElse: () => cocSpells.first,
      );
      final a = copySpell(src);
      final b = copySpell(src);
      expect(jsonEncode(a), jsonEncode(b), reason: '同一源两次拷贝结果应相同');
      a['name'] = 'A';
      final av = asList(a['variants']);
      if (av.isNotEmpty) asMap(av.first)['name'] = 'A-variant';
      expect(jsonEncode(a), isNot(jsonEncode(b)), reason: 'a 与 b 共享了引用');
      // 源表依旧不变
      expect(jsonEncode(cocSpells), isNot(contains('A-variant')));
    });
  });

  // ==========================================================
  // S5 类型不漂移：history[].sanChange 保持字符串
  // ==========================================================
  group('S5 类型不漂移', () {
    test('导入 → 保存 → 读回，sanChange 仍是字符串且值不变', () async {
      // legacy_card_blocks_export.json 是三个 fixture 里唯一带 history 的
      final text = File('test/fixtures/legacy_card_blocks_export.json')
          .readAsStringSync();
      final repo = CharacterRepo(storage: MemoryStorage());
      await repo.load();
      final c = (await importIntoRepo(repo, text)).first;

      final history = asList(c.raw['history']);
      expect(history, isNotEmpty, reason: 'fixture 里应当有历史记录');
      final before = history.map((h) => asMap(h)['sanChange']).toList();
      expect(
        before.every((v) => v is String || v == null),
        isTrue,
        reason: '导入后 sanChange 已被转成非字符串：$before',
      );

      await repo.save(c); // 再落一次盘（normalize + recalc）
      final back = repo.get(c.id)!;
      final after = asList(back.raw['history'])
          .map((h) => asMap(h)['sanChange'])
          .toList();
      expect(after, before, reason: '保存后类型 / 值漂移了');
      for (final v in after) {
        if (v != null) expect(v, isA<String>());
      }
    });

    test('"-1D6" / "-5" 两种写法都原样保留', () async {
      final c = probeCard();
      c.raw['history'] = <Object?>[
        <String, Object?>{'id': 'h1', 'title': 'A', 'sanChange': '-1D6'},
        <String, Object?>{'id': 'h2', 'title': 'B', 'sanChange': '-5'},
      ];
      final repo = CharacterRepo(storage: MemoryStorage());
      await repo.load();
      await repo.save(c);
      final back = repo.get(c.id)!;
      final arr = asList(back.raw['history']).map(asMap).toList();
      expect(arr[0]['sanChange'], '-1D6');
      expect(arr[1]['sanChange'], '-5');
    });
  });

  // ==========================================================
  // S6 持久化闭环（真实文件后端）
  // ==========================================================
  group('S6 持久化闭环', () {
    test('真实文件后端：写盘 → 新 repo 实例读回 → 逐字段相等', () async {
      final dir = await Directory.systemTemp.createTemp('dice_realm_qa_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final repo1 = CharacterRepo(directory: dir);
      await repo1.load();
      final card = probeCard(hp: 6, san: 21);
      normalize(card);
      recalc(card);
      await repo1.save(card);
      final written = deepCopy(card.raw);

      final repo2 = CharacterRepo(directory: dir);
      await repo2.load();
      final readBack = repo2.get(card.id);
      expect(readBack, isNotNull, reason: '新实例读不回这张卡');
      final got = deepCopy(readBack!.raw);

      // updatedAt 在 save 时被刷新，写入值以 repo1 内存里的为准
      expect(got, written, reason: '真实文件后端往返后字段不一致');

      // 数值类型也不能漂移（int 不能变 double / 字符串）
      expect(got['pbCap'], isA<int>());
      expect(asMap(got['status'])['currentHP'], isA<int>());
      expect(asMap(got['attributes'])['str'], isA<int>());
    });
  });
}
