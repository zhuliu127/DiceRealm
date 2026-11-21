// ============================================================
// wizard_fix_jump_test.dart — 「去修复 →」跳过去之后，那一页真的能修吗？
//
// QA 的 D2：`职业限定技能选择完成` 被映射到 basics（基本资料页），
// 但那一页根本没有勾选本职技能的地方 —— 玩家点「去修复」会到错页干瞪眼。
//
// 所以这里**不用「跳到的 id 和映射表一致」**来自证（那是用实现验证实现），
// 而是：真的点「去修复 →」，然后断言**目标页上出现了能修这个问题的控件**。
//
// 两张卡分工（没有任何一张卡能同时让 13 项全红，因为「已选择职业」与
// 「职业限定技能选择完成」互斥）：
//   cardA —— 什么都没填：基本信息 3 项 + 属性 + 未选职业 + 装备 3 项
//   cardB —— 填好基本信息、选了「会计师」但限定技能没勾、信用评级越界、技能点超额
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/normalize.dart';
import 'package:dice_realm/domain/occupation.dart';
import 'package:dice_realm/domain/skillmodel.dart' hide find;
import 'package:dice_realm/ui/create/chargen_logic.dart';
import 'package:dice_realm/ui/create/wizard_checks.dart';
import 'package:dice_realm/ui/create/wizard_steps.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// 迷你向导：一开始停在「概要」，点「去修复」就切到目标步（等价于真实向导的 _jumpTo）
class _MiniWizard extends StatefulWidget {
  const _MiniWizard({super.key, required this.card});

  final Character card;

  @override
  State<_MiniWizard> createState() => _MiniWizardState();
}

class _MiniWizardState extends State<_MiniWizard> {
  late final WizardSteps _steps;
  late int _index;

  @override
  void initState() {
    super.initState();
    _steps = WizardSteps(
      draft: widget.card,
      onChanged: () => setState(() {}),
      onJumpTo: (id) => setState(() => _index = _steps.indexOf(id)),
    );
    _index = _steps.length - 1; // 概要页
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: IndexedStack(
          index: _index,
          children: <Widget>[for (final s in _steps.steps) s.builder()],
        ),
        bottomNavigationBar: Text(
          'index=$_index',
          key: const Key('wizard_index'),
        ),
      ),
    );
  }
}

/// 什么都没填的卡（信息 / 属性 / 职业 / 装备全空）
Character _cardA() {
  final c = Character(newCharacter());
  c.raw['id'] = 'fixA0001';
  for (final k in <String>[
    'str',
    'con',
    'siz',
    'dex',
    'app',
    'int',
    'pow',
    'edu',
  ]) {
    c.attributes[k] = '';
  }
  recalc(c);
  return c;
}

/// 基本资料齐备、但本职技能没勾 / 信用评级越界 / 技能点超额的卡
Character _cardB() {
  final c = Character(newCharacter());
  c.raw['id'] = 'fixB0001';
  c.raw['characterName'] = '甲';
  c.raw['playerName'] = '老王';
  c.basicInfo['age'] = 32;
  c.raw['age'] = 32;
  c.raw['occupationId'] = 'occ2'; // 会计师：credit 30-70，有限定技能要勾
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
  c.assets['creditRating'] = 99; // 越界
  recalc(c);
  syncSkills(c);
  materializeOccupationalSkills(c);
  // 造一个点数 / 上限都超的职业技能
  asList(c.raw['skills']).add(<String, Object?>{
    'key': 'dodge',
    'id': 'dodge',
    'name': '闪避',
    'sub': '',
    'base': 25,
    'growth': 0,
    'occ': 300,
    'int': 200,
    'total': 525,
    'custom': false,
    'desc': '',
  });
  normalize(c);
  return c;
}

/// 点某条「去修复 →」，然后断言目标页上真的出现了能修它的控件
Future<void> _jumpAndExpectControl(
  WidgetTester tester,
  Character card,
  String label,
  String controlKey,
) async {
  // 每次都用新的 key：pumpWidget 复用同类型 State 时 initState 不会再跑，
  // 上一条用例跳走之后概要不在了（这样每条「去修复」都是独立的一次点击）
  // 概要页的 StepSummary 内嵌 SharePanel（P3-B），裸 MaterialApp 宿主缺
  // ShareScope 会命中断言；这里补上与 DiceRealmApp 同构的三个 Scope（仅夹具）。
  final host = await wrapWithScopes(_MiniWizard(key: UniqueKey(), card: card));
  await tester.pumpWidget(host);
  await tester.pumpAndSettle();

  final fix = find.byKey(Key('fix_$label'));
  expect(fix, findsOneWidget, reason: '概要页没有「$label」的去修复按钮（前提不成立）');
  await tester.ensureVisible(fix);
  await tester.pumpAndSettle();
  await tester.tap(fix);
  await tester.pumpAndSettle();

  // 跳过去了，而且那一页有能修它的控件
  final control = find.byKey(Key(controlKey));
  if (control.evaluate().isEmpty) {
    // 目标页是懒构建列表，控件可能在屏幕外 —— 滚过去再断言
    await tester.dragUntilVisible(
      control,
      find.byType(Scrollable).last,
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();
  }
  expect(control, findsWidgets, reason: '「$label」→ 目标页上没有可操作的「$controlKey」');
}

void main() {
  setUp(() {});

  group('D2：每一行「去修复」都跳到真能修它的那一页', () {
    testWidgets('cardA：姓名 / 玩家 / 年龄 → 基本资料页的对应输入框', (tester) async {
      useTallScreen(tester);
      final card = _cardA();
      await _jumpAndExpectControl(tester, card, '角色姓名已填写', 'field_name');
      await _jumpAndExpectControl(tester, card, '玩家名称已填写', 'field_player');
      await _jumpAndExpectControl(tester, card, '年龄合法', 'field_age');
    });

    testWidgets('cardA：属性非法 → 属性页的属性输入框', (tester) async {
      useTallScreen(tester);
      await _jumpAndExpectControl(
        tester,
        _cardA(),
        '属性合法（15-90 且为 5 的倍数）',
        'attr_str',
      );
    });

    testWidgets('cardA：未选职业 → 基本资料页的职业选择器', (tester) async {
      useTallScreen(tester);
      await _jumpAndExpectControl(
        tester,
        _cardA(),
        '已选择职业',
        'btn_pick_occupation',
      );
    });

    testWidgets('cardA：装备三项 → 战斗 / 物品页的添加入口', (tester) async {
      useTallScreen(tester);
      final card = _cardA();
      await _jumpAndExpectControl(tester, card, '已添加武器', 'btn_pick_weapon');
      await _jumpAndExpectControl(tester, card, '已装备防具', 'btn_pick_armor');
      await _jumpAndExpectControl(tester, card, '随身物品已填写', 'btn_add_item');
    });

    testWidgets('cardB：职业限定技能选择完成 → **技能页**的勾选块（D2 的正主）', (tester) async {
      useTallScreen(tester);
      final card = _cardB();
      final reqs = getRequirements(card);
      expect(reqs, isNotEmpty, reason: '会计师必须有职业限定技能，否则前提不成立');
      final reqId = jsStr(reqs.first['id']);

      await _jumpAndExpectControl(tester, card, '职业限定技能选择完成', 'req_$reqId');
    });

    testWidgets('cardB：信用评级越界 → 资产页的信用评级输入框', (tester) async {
      useTallScreen(tester);
      await _jumpAndExpectControl(
        tester,
        _cardB(),
        '信用评级在职业范围内',
        'credit_input',
      );
    });

    testWidgets('cardB：职业点 / 兴趣点超额 → 技能页的点数与加点入口', (tester) async {
      useTallScreen(tester);
      final card = _cardB();
      await _jumpAndExpectControl(tester, card, '职业技能点未超额', 'btn_auto_spend');
      await _jumpAndExpectControl(tester, card, '兴趣技能点未超额', 'btn_auto_spend');
      await _jumpAndExpectControl(
        tester,
        card,
        '技能未超过上限',
        'btn_toggle_all_skills',
      );
    });
  });

  group('D2：映射本身的语义（二元查表）', () {
    test('同一个 step=2 的两个检查项，按 label 分出不同页', () {
      expect(stepIdForCheck(2, '已选择职业'), 'basics');
      expect(stepIdForCheck(2, '职业限定技能选择完成'), 'skills');
      // 只给 step 时退回旧行为（basics），既有调用点不碎
      expect(stepIdForCheck(2), 'basics');
    });

    test('每个 label 的映射都与「该问题在哪一页能修」一致（逐条）', () {
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
      expected.forEach((label, id) {
        final row = <String, Object?>{
          'step': _stepOfLabel(label),
          'label': label,
        };
        expect(stepIdForCheckRow(row), id, reason: '「$label」应跳到 $id');
      });
    });
  });
}

/// 从 domain 的 checkList 里取某个 label 对应的旧 step（不硬编码数字）
int _stepOfLabel(String label) {
  final rows = checkList(_cardA());
  for (final r in rows) {
    if (jsStr(r['label']) == label) return jsNum(r['step']);
  }
  final rowsB = checkList(_cardB());
  for (final r in rowsB) {
    if (jsStr(r['label']) == label) return jsNum(r['step']);
  }
  throw StateError('checkList 里找不到 label=$label');
}
