// ============================================================
// p17_skill_editor_test.dart — P17 技能编辑四项需求的正式验收
//
// 本轮源码改动（仅两个文件，哈希已核验）：
//   · lib/ui/card_edit/skills_editor.dart
//   · lib/ui/create/steps/step_skills.dart
//
// 钉住四条需求：
//   A. 修改已保存角色 → 「全部技能」弹层加搜索（命中计数 / 空态 / 清除 / 顺序不变）
//   B. 修改已保存角色 → 克苏鲁神话等「仅成长」技能出现「成长点」；车卡流程不出现
//   C. 修改已保存角色 → 克苏鲁神话回到主列表；信用评级仍排除；车卡页无成长点控件
//   D. 点数可直接输入（目标值 → 复用 applyPoint 校验链；超上限报错、空串回退）
//   另加 domain 层回归（growth 绕过点数池但保留上限）与 360dp × textScaler 溢出硬约束。
//
// 约束：不改 lib/**；不许 skip / 放宽断言。
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/occupation.dart';
import 'package:dice_realm/domain/skillmodel.dart' hide find;
import 'package:dice_realm/ui/attr_meta.dart' show allAttrKeys;
import 'package:dice_realm/ui/card_edit/skills_editor.dart';
import 'package:dice_realm/ui/create/chargen_logic.dart';
import 'package:dice_realm/ui/create/steps/step_skills.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ------------------------------------------------------------
// 夹具
// ------------------------------------------------------------

/// 一张属性齐备、职业已选、技能已同步的卡（默认会计师 occ2：教育×4 = 240 职业点）
Character _card({String occ = 'occ2', int attr = 60}) {
  final c = Character(newCharacter());
  c.raw['id'] = 'p17skill01';
  c.raw['characterName'] = '技能编辑测试';
  c.raw['playerName'] = 'QA';
  c.basicInfo['age'] = 32;
  c.raw['age'] = 32;
  c.raw['occupationId'] = occ;
  for (final k in allAttrKeys) {
    c.attributes[k] = attr;
  }
  recalc(c);
  syncSkills(c);
  materializeOccupationalSkills(c);
  return c;
}

Map<String, Object?> _skill(Character c, String id) =>
    c.skills.map(asMap).firstWhere((s) => jsStr(s['id']) == id);

/// 复刻 `SkillsEditor.build` 里的排序（本职优先 → 最终值降序）。
/// 只用于断言「加了搜索之后未搜索态顺序没变」。
List<Map<String, Object?>> _orderedRows(Character card) {
  final occSet = occupationalSet(card);
  return card.skills.map(asMap).toList()
    ..sort((a, b) {
      final ao = occSet.containsKey(jsStr(a['key'])) ||
          occSet.containsKey(jsStr(a['id']));
      final bo = occSet.containsKey(jsStr(b['key'])) ||
          occSet.containsKey(jsStr(b['id']));
      if (ao != bo) return ao ? -1 : 1;
      return jsNum(b['total']).compareTo(jsNum(a['total']));
    });
}

// ------------------------------------------------------------
// 宿主 / pump 工具
// ------------------------------------------------------------

Widget _editorApp(Character card) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SkillsEditor(card: card, onChanged: () {}),
        ),
      ),
    );

Widget _sheetApp(Widget sheet) => MaterialApp(home: Scaffold(body: sheet));

Future<void> _pumpEditor(
  WidgetTester tester,
  Character card, {
  Size size = const Size(1200, 16000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_editorApp(card));
  await tester.pumpAndSettle();
}

Future<void> _pumpSheet(
  WidgetTester tester,
  Widget sheet, {
  Size size = const Size(400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_sheetApp(sheet));
  await tester.pumpAndSettle();
}

/// 「全部技能」弹层里技能行的顺序（按树序）。弹层行都在 ListView.builder 里，
/// 主编辑区不是 ListView，因此限定 descendant 可避开弹层背后那份列表。
List<String> _sheetRowKeys(WidgetTester tester) {
  final finder = find.descendant(
    of: find.byType(ListView),
    matching: find.byWidgetPredicate(
      (w) =>
          w is InkWell &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('edit_skill_'),
    ),
  );
  return tester
      .widgetList<InkWell>(finder)
      .map((w) => (w.key as ValueKey<String>).value)
      .toList();
}

String _textOf(WidgetTester tester, String key) {
  final f = find.byKey(Key(key));
  expect(f, findsOneWidget, reason: '$key 不在树里');
  return tester.widget<Text>(f).data ?? '';
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  // ==========================================================
  // A. 「全部技能」弹层搜索
  // ==========================================================
  group('A · 修改角色「全部技能」弹层搜索', () {
    testWidgets('未搜索：计数 = 列表长度，顺序与改动前（rows 原序）一致',
        (WidgetTester tester) async {
      final card = _card();
      await _pumpEditor(tester, card);
      await _tapKey(tester, 'btn_show_all_skills');

      final rows = _orderedRows(card);
      expect(find.byKey(const Key('edit_all_skills_search')), findsOneWidget);
      // 计数文案：未搜索是「N 项」
      expect(find.text('${rows.length} 项'), findsOneWidget);
      // 顺序：与 rows 原序逐项一致（搜索逻辑不得重排未搜索态）
      expect(
        _sheetRowKeys(tester),
        rows.map((s) => 'edit_skill_${jsStr(s['key'])}').toList(),
        reason: '未搜索时应保持 rows 原序（本职优先 → 最终值降序）',
      );
    });

    testWidgets('搜「克苏鲁」→ 只剩克苏鲁神话；搜 zzzz → 空态；清除 → 恢复全量',
        (WidgetTester tester) async {
      final card = _card();
      await _pumpEditor(tester, card);
      await _tapKey(tester, 'btn_show_all_skills');
      final all = _orderedRows(card);

      await tester.enterText(
          find.byKey(const Key('edit_all_skills_search')), '克苏鲁');
      await tester.pumpAndSettle();
      expect(find.text('命中 1 项'), findsOneWidget);
      expect(_sheetRowKeys(tester), <String>['edit_skill_cthulhu'],
          reason: '「克苏鲁」应只命中克苏鲁神话一项');

      await tester.enterText(
          find.byKey(const Key('edit_all_skills_search')), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edit_all_skills_empty')), findsOneWidget);
      expect(find.text('没有匹配的技能'), findsOneWidget);
      expect(_sheetRowKeys(tester), isEmpty);

      await _tapKey(tester, 'edit_all_skills_search_clear');
      expect(find.text('${all.length} 项'), findsOneWidget);
      expect(
        _sheetRowKeys(tester),
        all.map((s) => 'edit_skill_${jsStr(s['key'])}').toList(),
        reason: '清除搜索后应恢复全量与原有顺序',
      );
    });
  });

  // ==========================================================
  // B. 成长点（仅修改已保存角色）
  // ==========================================================
  group('B · 成长点开关', () {
    testWidgets('allowGrowth: true → 有成长步进器、显示「不限制」，无 occ/int 步进器',
        (WidgetTester tester) async {
      final card = _card();
      final cth = _skill(card, 'cthulhu');
      await _pumpSheet(
        tester,
        SkillPointSheet(card: card, skill: cth, allowGrowth: true),
      );

      expect(find.byKey(const Key('growth_plus')), findsOneWidget);
      expect(find.byKey(const Key('growth_minus')), findsOneWidget);
      expect(find.byKey(const Key('occ_plus')), findsNothing,
          reason: '仅成长技能在修改态也不该出现职业点步进器');
      expect(find.byKey(const Key('int_plus')), findsNothing,
          reason: '仅成长技能在修改态也不该出现兴趣点步进器');
      expect(find.text('不限制'), findsOneWidget,
          reason: '成长点不来自点数池，remain=null 应显示「不限制」');
      expect(find.text('这项技能只能通过成长点提升。'), findsOneWidget);
    });

    testWidgets('allowGrowth: false（车卡）→ 保留车卡原文，且无 growth 控件',
        (WidgetTester tester) async {
      final card = _card();
      final cth = _skill(card, 'cthulhu');
      await _pumpSheet(
        tester,
        SkillPointSheet(card: card, skill: cth), // 故意不传 → 默认 false
      );

      expect(
        find.text('按规则书，这项技能在车卡时不能用职业点 / 兴趣点加点，只能通过「成长」获得。'),
        findsOneWidget,
        reason: '车卡文案必须一字不改',
      );
      expect(find.byKey(const Key('growth_plus')), findsNothing);
      expect(find.byKey(const Key('growth_minus')), findsNothing);
      expect(find.text('不限制'), findsNothing);
    });
  });

  // ==========================================================
  // C. 克苏鲁神话回到主列表（仅修改角色）
  // ==========================================================
  group('C · 主列表可见性', () {
    testWidgets('修改角色主列表：显示克苏鲁神话，不含信用评级',
        (WidgetTester tester) async {
      final card = _card();
      await _pumpEditor(tester, card);

      expect(find.byKey(const Key('edit_skill_cthulhu')), findsOneWidget,
          reason: '克苏鲁神话 total=0 但属于仅成长技能，必须常驻主列表');
      expect(find.byKey(const Key('edit_skill_credit')), findsNothing,
          reason: '信用评级归「资产与信用评级」步骤，此处排除');
    });

    testWidgets('加了成长点后主列表副标题显示「成长 +N」', (WidgetTester tester) async {
      final card = _card();
      final cth = _skill(card, 'cthulhu');
      expect(applyPoint(card, cth, 'growth', 5)['ok'], true);

      await _pumpEditor(tester, card);
      expect(find.byKey(const Key('edit_skill_cthulhu')), findsOneWidget);
      expect(find.text('成长 +5'), findsOneWidget,
          reason: '副标题应在 growth>0 时出现「成长 +N」');
    });

    testWidgets('车卡页（StepSkills）打开克苏鲁神话弹层：无成长点控件',
        (WidgetTester tester) async {
      final card = _card();
      tester.view.physicalSize = const Size(1200, 16000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StepSkills(draft: card, onChanged: () {}),
        ),
      ));
      await tester.pumpAndSettle();

      // 车卡页默认只列有加点的技能；搜索后 _filtering=true 才会出现克苏鲁神话
      await tester.enterText(find.byKey(const Key('skill_search')), '克苏鲁');
      await tester.pumpAndSettle();
      await _tapKey(tester, 'skill_row_cthulhu');

      expect(
        find.text('按规则书，这项技能在车卡时不能用职业点 / 兴趣点加点，只能通过「成长」获得。'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('growth_plus')), findsNothing,
          reason: '车卡流程不允许出现成长点入口');
    });
  });

  // ==========================================================
  // D. 点数直接输入
  // ==========================================================
  group('D · 点数直接输入', () {
    testWidgets('点 occ_value 输入 37 → 值变 37，domain 同步落账',
        (WidgetTester tester) async {
      final card = _card();
      final acc = _skill(card, 'accounting');
      await _pumpSheet(tester, SkillPointSheet(card: card, skill: acc));

      // 既有 occ 步进器 key 必须保留
      expect(find.byKey(const Key('occ_minus')), findsOneWidget);
      expect(find.byKey(const Key('occ_plus')), findsOneWidget);
      expect(_textOf(tester, 'occ_value_text'), '0');

      await _tapKey(tester, 'occ_value');
      expect(find.byKey(const Key('occ_value_input')), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('occ_value_input')), '37');
      await _tapKey(tester, 'occ_value_ok');

      expect(_textOf(tester, 'occ_value_text'), '37');
      expect(jsNum(acc['occ']), 37, reason: '目标值应经 applyPoint 落到技能实例');
      expect(find.byKey(const Key('point_error')), findsNothing);
    });

    testWidgets('输入超上限 200 → 出现 point_error 且值未变',
        (WidgetTester tester) async {
      final card = _card();
      final acc = _skill(card, 'accounting');
      await _pumpSheet(tester, SkillPointSheet(card: card, skill: acc));

      await _tapKey(tester, 'occ_value');
      await tester.enterText(
          find.byKey(const Key('occ_value_input')), '200');
      await _tapKey(tester, 'occ_value_ok');

      expect(find.byKey(const Key('point_error')), findsOneWidget,
          reason: '超出上限必须由 applyPoint 拒绝并通过 point_error 展示');
      expect(_textOf(tester, 'occ_value_text'), '0', reason: '被拒后原值不变');
      expect(jsNum(acc['occ']), 0);
    });

    testWidgets('输入空串 → 回退原值，不报错', (WidgetTester tester) async {
      final card = _card();
      final acc = _skill(card, 'accounting');
      await _pumpSheet(tester, SkillPointSheet(card: card, skill: acc));

      await _tapKey(tester, 'occ_value');
      await tester.enterText(find.byKey(const Key('occ_value_input')), '');
      await _tapKey(tester, 'occ_value_ok');

      expect(_textOf(tester, 'occ_value_text'), '0');
      expect(find.byKey(const Key('point_error')), findsNothing,
          reason: '空串 = 取消输入，应静默回退而非报错');
    });
  });

  // ==========================================================
  // 领域层回归（不受 UI 影响）
  // ==========================================================
  group('domain · 成长点规则回归', () {
    test('applyPoint(cthulhu, growth, +5) ok，最终值 +5', () {
      final card = _card();
      final cth = _skill(card, 'cthulhu');
      final before = jsNum(cth['total']);
      final r = applyPoint(card, cth, 'growth', 5);
      expect(r['ok'], true);
      expect(jsNum(cth['total']), before + 5);
    });

    test('applyPoint(cthulhu, occ/int, +5) 拒绝，提示「只能通过成长」', () {
      final card = _card();
      final cth = _skill(card, 'cthulhu');
      for (final field in <String>['occ', 'int']) {
        final r = applyPoint(card, cth, field, 5);
        final text = '${r['reason'] ?? ''}${r['detail'] ?? ''}';
        expect(r['ok'], false, reason: '$field 不该能加到克苏鲁神话上');
        expect(text, contains('只能通过'), reason: '$field 拒绝原因应指引走成长');
      }
    });

    test('普通技能 growth 加点：兴趣池为 0 时仍然 ok（不受池限制）', () {
      final card = _card(attr: 0); // INT=0 → 兴趣池 0
      final acc = _skill(card, 'accounting');
      expect(jsNum(interestPoints(card)['total']), 0);
      expect(jsNum(occupationPoints(card)['total']), 0);

      final r = applyPoint(card, acc, 'growth', 3);
      expect(r['ok'], true, reason: 'growth 不占职业/兴趣池，池为 0 也应放行');
      expect(jsNum(acc['growth']), 3);
      expect(jsNum(acc['total']), jsNum(acc['base']) + 3);
    });

    test('growth 仍受最终值上限约束：total 到 cap 后再加被拒', () {
      final card = _card();
      final cth = _skill(card, 'cthulhu');
      cth['growth'] = 99; // cap = 99
      recompute(cth);
      final r = applyPoint(card, cth, 'growth', 1);
      expect(r['ok'], false, reason: '成长点也不能突破 99% 上限');
      expect('${r['reason'] ?? ''}', contains('最多到'));
    });
  });

  // ==========================================================
  // 硬约束：360dp × textScaler 1.0/1.3/1.5/2.0 无溢出
  // ==========================================================
  const List<double> _scales = <double>[1.0, 1.3, 1.5, 2.0];

  // ==========================================================
  // E · 普通技能也有成长点（2.47.1 真机报障回归）
  //
  // 2.47.0 把「成长点」写死在 `growthOnly` 分支里，普通技能（如会计/侦查）
  // 在「修改已保存角色」只看到职业点 + 兴趣点 —— 用户真机实测报障。
  // 下列 N1/N2 钉死「普通技能也要有、车卡不许有」，N3~N5 钉死 domain 语义
  // 在 UI 层同样成立（不受池限制、仍受上限），N6 防止修反把仅成长技能改坏。
  // ==========================================================
  group('E · 普通技能成长点', () {
    testWidgets('N1 普通技能 + allowGrowth: true → occ/int/growth 三行同时出现',
        (WidgetTester tester) async {
      final card = _card();
      final acc = _skill(card, 'accounting');
      await _pumpSheet(
        tester,
        SkillPointSheet(card: card, skill: acc, allowGrowth: true),
      );

      expect(find.byKey(const Key('occ_plus')), findsOneWidget,
          reason: '普通技能应保留职业点步进器');
      expect(find.byKey(const Key('int_plus')), findsOneWidget,
          reason: '普通技能应保留兴趣点步进器');
      expect(find.byKey(const Key('growth_plus')), findsOneWidget,
          reason: '2.47.0 回归点：普通技能在修改态必须有成长点步进器');
      expect(find.byKey(const Key('growth_minus')), findsOneWidget);

      expect(find.text('不限制'), findsOneWidget,
          reason: '成长点不来自点数池，remain=null 应显示「不限制」');
      expect(find.text('这项技能只能通过成长点提升。'), findsNothing,
          reason: '普通技能不是仅成长技能，不该出现该提示');
      expect(_textOf(tester, 'growth_value_text'), '0');
    });

    testWidgets('N2 普通技能 + allowGrowth: false（车卡）→ 只有 occ/int',
        (WidgetTester tester) async {
      final card = _card();
      final acc = _skill(card, 'accounting');
      await _pumpSheet(tester, SkillPointSheet(card: card, skill: acc));

      expect(find.byKey(const Key('occ_plus')), findsOneWidget);
      expect(find.byKey(const Key('int_plus')), findsOneWidget);
      expect(find.byKey(const Key('growth_plus')), findsNothing,
          reason: '车卡流程不允许出现成长点入口');
      expect(find.byKey(const Key('growth_minus')), findsNothing);
      expect(find.text('成长点'), findsNothing);
    });

    testWidgets('N3 成长点加减落账：+5 落 growth 与 total，-5 回 0',
        (WidgetTester tester) async {
      final card = _card();
      final acc = _skill(card, 'accounting');
      final base = jsNum(acc['base']);
      await _pumpSheet(
        tester,
        SkillPointSheet(card: card, skill: acc, allowGrowth: true),
      );

      expect(jsNum(acc['growth']), 0);
      await _tapKey(tester, 'growth_plus');
      expect(jsNum(acc['growth']), 5, reason: '步长应为 genStep=5');
      expect(jsNum(acc['total']), base + 5,
          reason: 'growth 必须反映到最终值');
      expect(_textOf(tester, 'growth_value_text'), '5');
      expect(find.byKey(const Key('point_error')), findsNothing);

      await _tapKey(tester, 'growth_minus');
      expect(jsNum(acc['growth']), 0);
      expect(jsNum(acc['total']), base);
      expect(_textOf(tester, 'growth_value_text'), '0');
    });

    testWidgets('N4 点数池 remain=0 时成长点仍可加，不查池',
        (WidgetTester tester) async {
      final card = _card(attr: 0); // 属性全 0 → 职业池 / 兴趣池总量都是 0
      final acc = _skill(card, 'accounting');
      expect(jsNum(occupationPoints(card)['remain']), 0);
      expect(jsNum(interestPoints(card)['remain']), 0);

      await _pumpSheet(
        tester,
        SkillPointSheet(card: card, skill: acc, allowGrowth: true),
      );
      expect(find.text('可用 0'), findsNWidgets(2),
          reason: '职业点、兴趣点两行都应显示「可用 0」');

      await _tapKey(tester, 'growth_plus');
      expect(find.byKey(const Key('point_error')), findsNothing,
          reason: '成长点不来自点数池，池为 0 也不该被拒');
      expect(jsNum(acc['growth']), 5);
      expect(jsNum(acc['total']), jsNum(acc['base']) + 5);
    });

    testWidgets('N5 成长点仍受技能上限：total 到 cap 后再加报 point_error',
        (WidgetTester tester) async {
      final card = _card();
      final acc = _skill(card, 'accounting');
      final cap = capOf(card, acc);
      acc['growth'] = cap - jsNum(acc['base']);
      recompute(acc);
      expect(jsNum(acc['total']), cap, reason: '夹具应把 total 顶到 cap');

      await _pumpSheet(
        tester,
        SkillPointSheet(card: card, skill: acc, allowGrowth: true),
      );
      await _tapKey(tester, 'growth_plus');

      expect(find.byKey(const Key('point_error')), findsOneWidget,
          reason: '成长点也不能突破上限');
      expect(_textOf(tester, 'point_error'), contains('最多到'));
      expect(jsNum(acc['growth']), cap - jsNum(acc['base']),
          reason: '被拒后成长值不变');
      expect(jsNum(acc['total']), cap);
    });

    testWidgets('N6 growthOnly 回归钉死：true 只有 growth / false 只有车卡原文',
        (WidgetTester tester) async {
      final card = _card();
      final cth = _skill(card, 'cthulhu');

      await _pumpSheet(
        tester,
        SkillPointSheet(card: card, skill: cth, allowGrowth: true),
      );
      expect(find.byKey(const Key('growth_plus')), findsOneWidget);
      expect(find.byKey(const Key('occ_plus')), findsNothing);
      expect(find.byKey(const Key('int_plus')), findsNothing);
      expect(find.text('这项技能只能通过成长点提升。'), findsOneWidget);

      await _pumpSheet(tester, SkillPointSheet(card: card, skill: cth));
      expect(
        find.text('按规则书，这项技能在车卡时不能用职业点 / 兴趣点加点，只能通过「成长」获得。'),
        findsOneWidget,
        reason: '车卡文案必须一字不改',
      );
      expect(find.byKey(const Key('growth_plus')), findsNothing);
      expect(find.byKey(const Key('occ_plus')), findsNothing);
      expect(find.text('不限制'), findsNothing);
    });

    testWidgets('N7 三行弹层 360dp × 四档 textScaler 无溢出',
        (WidgetTester tester) async {
      final card = _card();
      final acc = _skill(card, 'accounting');
      addTearDown(
          () => tester.platformDispatcher.clearTextScaleFactorTestValue());
      for (final scale in _scales) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await _pumpSheet(
          tester,
          SkillPointSheet(card: card, skill: acc, allowGrowth: true),
          size: const Size(360, 640),
        );
        expect(find.byKey(const Key('growth_plus')), findsOneWidget,
            reason: 'textScaler $scale 下成长行未渲染，溢出断言会变成空转');
        expect(tester.takeException(), isNull,
            reason: '普通技能三行弹层（occ/int/growth）在 textScaler $scale 下溢出');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  });

  group('textScaler 溢出硬约束', () {
    testWidgets('SkillsEditor 主区', (WidgetTester tester) async {
      final card = _card();
      tester.platformDispatcher.textScaleFactorTestValue = 1.0;
      addTearDown(
          () => tester.platformDispatcher.clearTextScaleFactorTestValue());
      for (final scale in _scales) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await _pumpEditor(tester, card, size: const Size(360, 640));
        expect(tester.takeException(), isNull,
            reason: 'SkillsEditor 在 textScaler $scale 下溢出');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });

    testWidgets('全部技能弹层', (WidgetTester tester) async {
      final card = _card();
      addTearDown(
          () => tester.platformDispatcher.clearTextScaleFactorTestValue());
      for (final scale in _scales) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await _pumpEditor(tester, card, size: const Size(360, 640));
        // 360dp 宽下按钮在滚动区之外，先滚到可见，否则 tap 打空气、弹层不会打开。
        await tester.ensureVisible(
            find.byKey(const Key('btn_show_all_skills')));
        await tester.pumpAndSettle();
        await _tapKey(tester, 'btn_show_all_skills');
        expect(find.byKey(const Key('edit_all_skills_search')), findsOneWidget,
            reason: 'textScaler $scale 下弹层未打开，溢出断言会变成空转');
        expect(tester.takeException(), isNull,
            reason: '全部技能弹层在 textScaler $scale 下溢出');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });

    testWidgets('普通技能加点弹层（含数字直输控件）', (WidgetTester tester) async {
      final card = _card();
      final acc = _skill(card, 'accounting');
      addTearDown(
          () => tester.platformDispatcher.clearTextScaleFactorTestValue());
      for (final scale in _scales) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await _pumpSheet(
          tester,
          SkillPointSheet(card: card, skill: acc),
          size: const Size(360, 640),
        );
        expect(tester.takeException(), isNull,
            reason: '普通技能加点弹层在 textScaler $scale 下溢出');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });

    testWidgets('成长点弹层', (WidgetTester tester) async {
      final card = _card();
      final cth = _skill(card, 'cthulhu');
      addTearDown(
          () => tester.platformDispatcher.clearTextScaleFactorTestValue());
      for (final scale in _scales) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await _pumpSheet(
          tester,
          SkillPointSheet(card: card, skill: cth, allowGrowth: true),
          size: const Size(360, 640),
        );
        expect(tester.takeException(), isNull,
            reason: '成长点弹层在 textScaler $scale 下溢出');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  });
}
