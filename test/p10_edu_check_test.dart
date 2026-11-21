// ============================================================
// p10_edu_check_test.dart — P10：教育进步检定 + 年龄扣 DEX 对闪避的影响
//                            P11：教育进步检定的**次数**按年龄给（扩充）
//
// 覆盖（对应需求第 9 项）：
//   A. `edu_check.dart#eduCheck` 纯函数边界：等于不增 / 略大就增 / 95+10 封顶 99
//   B. `chargen_logic.dart#runEduCheck`：次数用完即止（幂等）+ 掷骰顺序
//   B-UI. 属性页最下方「教育进步检定」：掷骰 → 生效 EDU 真的涨、按钮变禁用、
//      结果文案带掷出的点数
//   C. 未检定就点「下一步」→ 出现提示（**不拦路**）、「仍要继续」后不再重复弹
//   D. 年龄扣 DEX → 闪避基础值（DEX ~/ 2）跟着降 —— 这条是 bug 回归的钉子
//
// P11 新增：
//   E. `eduCheckAllowance` 逐档断言 / 15–99 岁单调不减 / 与 ageTable 的
//      eduChecks 逐档一致（护栏）
//   F. runEduCheck 按次数上限：20 岁 1 次、60 岁 4 次逐次累加并封顶 99、
//      失败也算用掉一次、改小年龄后剩余夹到 0
//   G. UI：按钮纯文字（无 emoji）、「第 N 次检定」、剩余次数文案
//   H. 未检定提示的判据改成「还有剩余次数」
//
// ⚠️ 断言的「原始值不动、生效值变高」是**既有产品意图**（见 character.dart
//    的 eduProgress 注释、rules_coc7.dart#ageAdjust、engine.dart#dropStaleEduChecks）：
//    购点上限校验只认玩家买来的原始 EDU，年龄修正与教育增益都只作用于生效值。
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/dice.dart' show roll;
import 'package:dice_realm/domain/edu_check.dart'
    show eduCap, eduCheck, eduCheckAllowance;
import 'package:dice_realm/domain/engine.dart' show effAttrs, recalc;
import 'package:dice_realm/domain/js_compat.dart'
    show JsRng, asList, jsNum, nowRng, setRng;
import 'package:dice_realm/domain/rules_coc7.dart' show ageRule;
import 'package:dice_realm/domain/skillmodel.dart' as sm;
import 'package:dice_realm/ui/create/chargen_logic.dart'
    show
        eduCheckAllowanceOf,
        eduCheckText,
        eduChecked,
        eduChecksRemaining,
        eduChecksUsed,
        eduForCheck,
        ensureEduProgress,
        runEduCheck;
import 'package:dice_realm/ui/create/steps/step_attrs.dart' show StepAttrs;
import 'package:flutter/material.dart'
    show
        BuildContext,
        FilledButton,
        Key,
        ListTile,
        MaterialApp,
        Scaffold,
        StatefulBuilder,
        StateSetter,
        Text,
        Widget;
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart' show pumpApp, scrollTo, tapKey, useTallScreen;
import 'support/oracle.dart' show Lcg;

const List<String> _attrKeys = <String>[
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

Character _cardWith({
  int age = 25,
  int attr = 50,
  int edu = 50,
}) {
  final c = Character(newCharacter());
  c.basicInfo['age'] = age;
  c.raw['age'] = age;
  for (final k in _attrKeys) {
    c.attributes[k] = k == 'edu' ? edu : attr;
  }
  recalc(c);
  sm.syncSkills(c);
  return c;
}

/// 找一个满足条件的 1D100 种子。
///
/// ⚠️ LCG 的相邻种子只差 0.0004 左右的概率，所以「取最小种子」往往拿不到
/// 想要的点数 —— 必须扫一段范围（这里扫到 30 万，纯计算、毫秒级）。
int _seedWhere(bool Function(int roll) ok) {
  for (var seed = 1; seed <= 300000; seed++) {
    if (ok(roll(1, 100, Lcg(seed).call))) return seed;
  }
  throw StateError('30 万个种子里找不到满足条件的 1D100');
}

/// 让 widget 用例的检定必定成功的种子（1D100 > 当前 EDU）
int _seedWithRollAbove(int targetEdu) => _seedWhere((int r) => r > targetEdu);

/// 用 StatefulBuilder 模拟 CreateFlowPage 的 onChanged（重建子树）
Widget _host(Character c) => MaterialApp(
  home: Scaffold(
    body: StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) => StepAttrs(
        draft: c,
        onChanged: () => setState(() {}),
      ),
    ),
  ),
);

String _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data ?? '';

/// 按钮（或任意节点）内部所有 Text 拼起来 —— 用来断言「文案不含 emoji」。
/// Key 挂在 FilledButton 上（既有测试要对它取 `widget<FilledButton>`），
/// 所以文本只能从后代里捞。
String _labelOf(WidgetTester tester, String key) => tester
    .widgetList<Text>(
      find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
    )
    .map((Text t) => t.data ?? '')
    .join('|');

/// 永远掷出最大值（1D100 = 100、1D10 = 10）的随机源。
/// 用来把「多次检定每次都成功」写成确定性断言。
double _alwaysMax() => 0.999999;

/// 永远掷出最小值（1D100 = 1）的随机源 → 对任何 EDU ≥ 1 都必然失败。
double _alwaysMin() => 0.0;

/// 从首页走到「属性分配」页（基础资料填好、职业选法官、9 项属性都填 50）
Future<void> _gotoAttrs(
  WidgetTester tester, {
  required String name,
  String age = '32',
}) async {
  await pumpApp(tester);
  await tester.tap(find.byKey(const Key('fab_new_card')));
  await tester.pumpAndSettle();
  await tapKey(tester, 'rule_pick_coc7'); // 规则选择页 → 向导（首步 = 基本资料）

  await tester.enterText(find.byKey(const Key('field_name')), name);
  await tester.enterText(find.byKey(const Key('field_player')), '老王');
  await tester.enterText(find.byKey(const Key('field_age')), age);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('btn_pick_occupation')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('field_occ_search')), '法官');
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, '法官').first);
  await tester.pumpAndSettle();
  await tapKey(tester, 'btn_next'); // 基本资料 → 属性

  for (final k in _attrKeys) {
    await tester.enterText(find.byKey(Key('attr_$k')), '50');
  }
  await tester.pumpAndSettle();
}

/// 取派生值的便捷封装（derivedStats 在 recalc 时写入）
num _derivedOf(Character c, String key) => jsNum(c.derivedStats[key]);

void main() {
  late JsRng savedRng;
  setUp(() {
    savedRng = nowRng;
  });
  tearDown(() {
    setRng(savedRng);
  });

  group('A · eduCheck 纯函数边界', () {
    test('d100 == 当前教育 → 不进步（严格大于才算）', () {
      final r = eduCheck(55, 55, 8);
      expect(r.success, isFalse);
      expect(r.gain, 0);
      expect(r.after, 55, reason: '等于 EDU 不该加，规则书是「大于」');
      expect(r.before, 55);
      expect(r.roll, 55);
    });

    test('d100 == 当前教育 + 1 → 进步，EDU + 1D10', () {
      final r = eduCheck(55, 56, 7);
      expect(r.success, isTrue);
      expect(r.gain, 7);
      expect(r.after, 62);
    });

    test('95 + 1D10=10 → 封顶 99（只加 4）', () {
      final r = eduCheck(95, 96, 10);
      expect(r.success, isTrue);
      expect(r.after, eduCap);
      expect(r.after, 99);
      expect(r.gain, 4, reason: '被封顶吃掉的点数不能算进 gain');
    });

    test('已经是 99：d100=100 仍算进步，但 gain 必须是 0', () {
      final r = eduCheck(99, 100, 10);
      expect(r.success, isTrue);
      expect(r.after, 99);
      expect(r.gain, 0);
    });

    test('失败时 d10 完全不参与（传 10 也不涨）', () {
      expect(eduCheck(70, 12, 10).after, 70);
      expect(eduCheck(70, 70, 10).after, 70);
    });

    test('幂等：同一组入参调 100 次结果逐字相同', () {
      final first = eduCheck(60, 61, 5);
      for (var i = 0; i < 100; i++) {
        final again = eduCheck(60, 61, 5);
        expect(again.after, first.after);
        expect(again.gain, first.gain);
        expect(again.success, first.success);
      }
    });

    test('文案：成功 / 封顶 / 失败三种措辞都带掷出的值', () {
      expect(
        eduCheckText(<String, Object?>{
          'roll': 63,
          'd10': 7,
          'before': 55,
          'gain': 7,
          'after': 62,
        }),
        '掷出 63 > 教育 55 → 教育 +7，现为 62',
      );
      expect(
        eduCheckText(<String, Object?>{
          'roll': 100,
          'd10': 10,
          'before': 95,
          'gain': 4,
          'after': 99,
        }),
        contains('上限 99'),
      );
      expect(
        eduCheckText(<String, Object?>{
          'roll': 12,
          'd10': 0,
          'before': 55,
          'gain': 0,
          'after': 55,
        }),
        '掷出 12 ≤ 教育 55 → 没有进步，教育保持 55',
      );
    });
  });

  group('B · runEduCheck：只做一次，增益落在生效值上', () {
    test('成功一次后：生效 EDU +gain，原始 EDU 不动，再掷返回 null', () {
      final c = _cardWith(age: 25, edu: 20);
      final seed = _seedWithRollAbove(20);
      setRng(Lcg(seed).call);
      final r = runEduCheck(c);
      expect(r, isNotNull);
      final gain = jsNum(r!['gain']);
      expect(gain, greaterThan(0));

      expect(jsNum(c.attributes['edu']), 20,
          reason: '原始 EDU 是买来的点数，不能被改写');
      expect(eduForCheck(c), 20 + gain, reason: '生效教育必须真的涨');
      expect(eduChecked(c), isTrue);
      expect(jsNum(c.eduProgress['bonus']), gain);
      expect(jsNum(c.eduProgress['baseEdu']), 20,
          reason: '要记基准，改教育时旧检定才会作废');

      // 幂等：第二次一个字节都不改
      final before = jsNum(c.eduProgress['bonus']);
      expect(runEduCheck(c), isNull);
      expect(jsNum(c.eduProgress['bonus']), before);
      expect(ensureEduProgress(c)['done'], 1);
    });

    test('掷骰顺序与 rules#eduImproveCheck 一致：先 1D100，进步了才 1D10', () {
      final c = _cardWith(age: 25, edu: 30);
      final d100 = roll(1, 100, Lcg(4242).call);
      final success = d100 > 30;
      final probe = Lcg(4242); // 同一个种子：用它数「消耗了几个随机数」
      setRng(probe.call);
      final r = runEduCheck(c);
      expect(jsNum(r!['roll']), d100, reason: 'd100 必须与同一序列逐字一致');
      expect(r['success'], success);
      expect(jsNum(r['gain']) > 0, success);
      expect(
        probe.used,
        success ? 2 : 1,
        reason: '成功时再掷 1D10（共 2 个随机数）；失败只用掉 1D100 —— 与 rules#eduImproveCheck 一致',
      );
    });
  });

  group('B-UI · 属性页最下方的教育进步检定', () {
    testWidgets('点检定 → 生效 EDU 涨、按钮禁用、文案含掷出的点数', (tester) async {
      useTallScreen(tester);
      final c = _cardWith(age: 25, edu: 20);
      final seed = _seedWithRollAbove(20);
      // 先算出期望值（同一颗种子、同一顺序）
      final probe = Lcg(seed);
      final expD100 = roll(1, 100, probe.call);
      final expD10 = roll(1, 10, probe.call);
      final expAfter = (20 + expD10) > eduCap ? eduCap : 20 + expD10;

      setRng(Lcg(seed).call);
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();

      await scrollTo(tester, 'edu_check_roll');
      expect(_textOf(tester, 'edu_check_result'), contains('尚未检定'));

      await tester.tap(find.byKey(const Key('edu_check_roll')));
      await tester.pumpAndSettle();

      // 卡片数据：生效教育真的涨了
      expect(asList(c.eduProgress['log']).length, 1);
      expect(eduForCheck(c), expAfter);
      expect(jsNum(c.attributes['edu']), 20, reason: '原始值不变（购点校验只认它）');

      // 文案含掷出的点数与新教育值
      final txt = _textOf(tester, 'edu_check_result');
      expect(txt, contains('$expD100'));
      expect(txt, contains('现为 $expAfter'));

      // 按钮变禁用
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('edu_check_roll')))
            .onPressed,
        isNull,
        reason: '做过一次就不能再掷（避免刷点）',
      );

      // 再点也不会累加（按钮已禁用，这里直接调逻辑层再确认一次幂等）
      expect(runEduCheck(c), isNull);
      expect(ensureEduProgress(c)['done'], 1);
      expect(eduForCheck(c), expAfter);
    });

    testWidgets('掷出值 ≤ EDU → 文案说明没进步，按钮同样变禁用', (tester) async {
      useTallScreen(tester);
      // 教育 EDU 很高（90），找一个掷出值 ≤ 90 的种子（必然「没有进步」）
      final seed = _seedWhere((int r) => r <= 90);
      final expD100 = roll(1, 100, Lcg(seed).call);

      final c = _cardWith(age: 25, edu: 90);
      setRng(Lcg(seed).call);
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      await scrollTo(tester, 'edu_check_roll');
      await tester.tap(find.byKey(const Key('edu_check_roll')));
      await tester.pumpAndSettle();

      expect(eduForCheck(c), 90, reason: '没进步就不该涨');
      expect(_textOf(tester, 'edu_check_result'), contains('没有进步'));
      expect(_textOf(tester, 'edu_check_result'), contains('$expD100'));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('edu_check_roll')))
            .onPressed,
        isNull,
        reason: '失败也算「做过了」，不能靠重掷刷出成功',
      );
    });
  });

  group('C · 未检定就点下一步：提示但不拦路，且只提示一次', () {
    testWidgets('第 2 步 → 下一步：出现提示但仍前进；仍要继续后不再重复弹', (tester) async {
      await _gotoAttrs(tester, name: '检定测试');

      await tapKey(tester, 'btn_next'); // 属性 → 资产（未检定）

      // 硬约束：**不拦路** —— 已经到资产页，同时出现提示
      expect(find.byKey(const Key('credit_input')), findsOneWidget,
          reason: '未检定不该把玩家卡在属性页');
      expect(find.byKey(const Key('edu_check_skip_hint')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('edu_check_skip_hint'))).data,
        contains('教育'),
      );

      // 点「仍要继续」→ 提示消失，仍在资产页
      await tester.tap(find.byKey(const Key('edu_check_continue')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edu_check_skip_hint')), findsNothing);
      expect(find.byKey(const Key('credit_input')), findsOneWidget);

      // 回属性页再点一次「下一步」：同一个建卡会话里不再重复弹
      await tapKey(tester, 'step_jump_1'); // 属性页（跳过 rules 后 index=1）
      await tapKey(tester, 'btn_next');
      expect(find.byKey(const Key('edu_check_skip_hint')), findsNothing,
          reason: '提示只弹一次');
      expect(find.byKey(const Key('credit_input')), findsOneWidget);
    });

    testWidgets('做了检定再点下一步：完全不弹提示', (tester) async {
      await _gotoAttrs(tester, name: '已检定');

      setRng(Lcg(_seedWithRollAbove(50)).call);
      await scrollTo(tester, 'edu_check_roll');
      await tester.tap(find.byKey(const Key('edu_check_roll')));
      await tester.pumpAndSettle();

      await tapKey(tester, 'btn_next');
      expect(find.byKey(const Key('credit_input')), findsOneWidget);
      expect(find.byKey(const Key('edu_check_skip_hint')), findsNothing);
    });
  });

  group('D · 年龄扣 DEX 必须影响闪避基础值（DEX ~/ 2）', () {
    test('60 岁扣 6 点 DEX → 闪避基础值 30 降到 27', () {
      final young = _cardWith(age: 25, attr: 60);
      final old = _cardWith(age: 60, attr: 60);

      final youngEffDex = jsNum(effAttrs(young)['dex']);
      final oldEffDex = jsNum(effAttrs(old)['dex']);
      expect(youngEffDex, 60, reason: '25 岁不扣属性');
      expect(oldEffDex, 54, reason: '60 岁力量/体质/敏捷合计 −20，三项轮转分摊 → DEX −6');

      expect(_derivedOf(young, 'dodgeBase'), 30);
      expect(_derivedOf(old, 'dodgeBase'), 27,
          reason: '闪避基础值必须用年龄调整后的 DEX');

      final youngDodge = sm.find(young, 'dodge');
      final oldDodge = sm.find(old, 'dodge');
      expect(youngDodge, isNotNull);
      expect(oldDodge, isNotNull);
      expect(jsNum(youngDodge!['base']), 30);
      expect(jsNum(oldDodge!['base']), 27,
          reason: '技能实例的 base 也必须跟着降（否则年龄调整等于没生效）');
      expect(jsNum(oldDodge['total']), 27, reason: 'total = base（还没投入点数）');

      // 差值就是取整后的 DEX 差：60~/2=30，54~/2=27
      expect(jsNum(youngDodge['base']) - jsNum(oldDodge['base']), 3);
    });

    test('奇数 DEX 也按向下取整跟：49 → 24，43 → 21', () {
      final young = _cardWith(age: 25, attr: 60);
      young.attributes['dex'] = 49;
      recalc(young);
      sm.syncSkills(young);
      expect(jsNum(sm.find(young, 'dodge')!['base']), 24, reason: '49/2 向下取整 = 24');

      final old = _cardWith(age: 60, attr: 60);
      old.attributes['dex'] = 49; // 扣 6 → 43
      recalc(old);
      sm.syncSkills(old);
      expect(jsNum(effAttrs(old)['dex']), 43);
      expect(jsNum(sm.find(old, 'dodge')!['base']), 21, reason: '43/2 向下取整 = 21');
    });

    test('改动 age 后重算一次，闪避基础值立刻跟上（不留旧缓存）', () {
      final c = _cardWith(age: 25, attr: 60);
      expect(jsNum(sm.find(c, 'dodge')!['base']), 30);

      c.basicInfo['age'] = 60;
      c.raw['age'] = 60;
      recalc(c);
      sm.syncSkills(c);
      expect(jsNum(effAttrs(c)['dex']), 54);
      expect(jsNum(sm.find(c, 'dodge')!['base']), 27);
    });
  });

  /* ============================================================
   * P11：教育进步检定的**次数**按年龄给（不再固定 1 次）
   * ============================================================ */

  group('E · eduCheckAllowance：按年龄决定检定次数', () {
    test('逐档断言：15/19→0、20/39→1、40/49→2、50/59→3、60~99→4', () {
      expect(eduCheckAllowance(15), 0);
      expect(eduCheckAllowance(19), 0);
      expect(eduCheckAllowance(20), 1);
      expect(eduCheckAllowance(39), 1);
      expect(eduCheckAllowance(40), 2);
      expect(eduCheckAllowance(49), 2);
      expect(eduCheckAllowance(50), 3);
      expect(eduCheckAllowance(59), 3);
      expect(eduCheckAllowance(60), 4);
      expect(eduCheckAllowance(69), 4);
      expect(eduCheckAllowance(70), 4);
      expect(eduCheckAllowance(79), 4);
      expect(eduCheckAllowance(80), 4);
      expect(eduCheckAllowance(89), 4);
      expect(eduCheckAllowance(90), 4);
      expect(eduCheckAllowance(99), 4);
    });

    test('单调不减：20 岁起每一岁都不比上一岁少（少年档 0 不参与该区间）', () {
      /* ⚠️ 为什么从 20 岁起断言：本项目 15–19 档把教育机会换成了
         「幸运骰 2 次取较高值」，`eduChecks` 记 0（见 ageTable 该档 note，
         以及 engine.json 里 15 岁的 oracle 夹具）。少年档的 0 是**既有设计取舍**，
         不是「次数随年龄递减」，所以单调性只约束 20 岁以上的成长曲线；
         少年档的取值由上面的逐档断言单独钉死。不许为了让断言好看去改数据。 */
      for (var age = 21; age <= 99; age++) {
        expect(
          eduCheckAllowance(age),
          greaterThanOrEqualTo(eduCheckAllowance(age - 1)),
          reason: '$age 岁的次数不能比 ${age - 1} 岁少（年龄越大次数越多）',
        );
      }
      // 低龄段整体不高于高龄段
      expect(eduCheckAllowance(15), lessThanOrEqualTo(eduCheckAllowance(20)));
      expect(eduCheckAllowance(20), lessThan(eduCheckAllowance(40)));
      expect(eduCheckAllowance(40), lessThan(eduCheckAllowance(60)));
      expect(eduCheckAllowance(60), greaterThan(eduCheckAllowance(20)),
          reason: '高龄段必须多于低龄段');
    });

    test('<15 / 0 / 负数等异常值按最低档 0 处理，不抛异常', () {
      expect(eduCheckAllowance(14), 0);
      expect(eduCheckAllowance(0), 0);
      expect(eduCheckAllowance(-5), 0);
    });

    test('护栏：与 ageTable 的 eduChecks 逐档相等（两处不许漂移）', () {
      for (var age = 15; age <= 99; age++) {
        expect(
          eduCheckAllowance(age),
          jsNum(ageRule(age)['eduChecks']),
          reason: '$age 岁：edu_check.dart 与 rules_coc7.dart#ageTable 不一致',
        );
      }
    });

    test('eduCheckAllowanceOf：读卡上的年龄；空 / 非法年龄按引擎默认 25 岁', () {
      expect(eduCheckAllowanceOf(_cardWith(age: 45)), 2);
      expect(eduCheckAllowanceOf(_cardWith(age: 65)), 4);

      final blank = _cardWith(age: 25);
      blank.basicInfo['age'] = '';
      expect(eduCheckAllowanceOf(blank), 1,
          reason: '还没填年龄的半成品卡按 25 岁兜底（与 ageAdjust 一致），别突然一次都不能检定');
    });
  });

  group('F · runEduCheck：按次数上限累加', () {
    test('20 岁只能做 1 次：第 2 次返回 null，且一个字节都不改', () {
      final c = _cardWith(age: 20, edu: 20);
      setRng(_alwaysMax);
      expect(eduChecksRemaining(c), 1);

      final r = runEduCheck(c);
      expect(r, isNotNull);
      expect(eduChecksUsed(c), 1);
      expect(eduChecksRemaining(c), 0);

      final bonus = jsNum(c.eduProgress['bonus']);
      expect(runEduCheck(c), isNull, reason: '20–39 岁只有 1 次');
      expect(eduChecksUsed(c), 1);
      expect(jsNum(c.eduProgress['bonus']), bonus);
    });

    test('60 岁能做 4 次：每次追加一行 log，EDU 逐次累加并封顶 99', () {
      final c = _cardWith(age: 60, edu: 85);
      setRng(_alwaysMax); // 每次都是 1D100=100 > 当前教育，1D10=10
      expect(eduChecksRemaining(c), 4);

      final rows = <Map<String, Object?>>[];
      for (var i = 0; i < 4; i++) {
        final r = runEduCheck(c);
        expect(r, isNotNull, reason: '第 ${i + 1} 次应该还能做');
        rows.add(r!);
        expect(asList(c.eduProgress['log']).length, i + 1,
            reason: '每次都要追加一行 log');
      }

      // 每次都用「当时的教育」判定：85 → 95 → 99（封顶）→ 99 → 99
      expect(rows.map((Map<String, Object?> r) => jsNum(r['before'])).toList(),
          <int>[85, 95, 99, 99]);
      expect(rows.map((Map<String, Object?> r) => jsNum(r['after'])).toList(),
          <int>[95, 99, 99, 99]);
      expect(rows.map((Map<String, Object?> r) => jsNum(r['gain'])).toList(),
          <int>[10, 4, 0, 0], reason: '封顶吃掉的部分不算 gain');
      expect(rows.map((Map<String, Object?> r) => jsNum(r['n'])).toList(),
          <int>[1, 2, 3, 4]);

      expect(jsNum(c.eduProgress['bonus']), 14);
      expect(eduForCheck(c), 99);
      expect(jsNum(c.attributes['edu']), 85, reason: '原始 EDU 是买来的点数，不能被改写');
      expect(eduChecksUsed(c), 4);
      expect(eduChecksRemaining(c), 0);
      expect(eduChecked(c), isTrue);

      // 第 5 次：次数用完 → null
      expect(runEduCheck(c), isNull);
      expect(asList(c.eduProgress['log']).length, 4);
    });

    test('失败也算用掉一次：20 岁掷出 1 ≤ 教育 60 → 剩余直接归零', () {
      final c = _cardWith(age: 20, edu: 60);
      setRng(_alwaysMin); // 1D100 = 1，必然「没有进步」

      final r = runEduCheck(c)!;
      expect(r['success'], isFalse);
      expect(jsNum(r['gain']), 0);
      expect(eduForCheck(c), 60);

      expect(eduChecksUsed(c), 1, reason: '规则是「可以做 N 次检定」，不是「N 次成功」');
      expect(eduChecksRemaining(c), 0);
      expect(eduChecked(c), isTrue);
      expect(runEduCheck(c), isNull, reason: '失败也不能白拿重掷机会');
    });

    test('17 岁（本档 0 次）：一次都掷不了，直接返回 null', () {
      final c = _cardWith(age: 17, edu: 20);
      setRng(_alwaysMax);
      expect(eduChecksRemaining(c), 0);
      expect(runEduCheck(c), isNull);
      expect(asList(c.eduProgress['log']), isEmpty);
      expect(eduForCheck(c), 20);
    });

    test('60 岁做 3 次后把年龄改回 30 岁：剩余夹到 0，不会变成负数', () {
      final c = _cardWith(age: 60, edu: 20);
      setRng(_alwaysMax);
      for (var i = 0; i < 3; i++) {
        expect(runEduCheck(c), isNotNull);
      }
      c.basicInfo['age'] = 30;
      c.raw['age'] = 30;
      recalc(c);
      expect(eduChecksUsed(c), 3);
      expect(eduChecksRemaining(c), 0, reason: '已经做的次数不会退，剩余只能是 0');
      expect(runEduCheck(c), isNull);
    });
  });

  group('G · UI：剩余次数文案与「没有 emoji」的按钮', () {
    testWidgets('60 岁：按钮纯文字、逐次显示剩余次数、第 4 次后禁用', (tester) async {
      useTallScreen(tester);
      final c = _cardWith(age: 60, edu: 20);
      setRng(_alwaysMax);
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      await scrollTo(tester, 'edu_check_roll');

      // 初始：按钮只要文字，不带 emoji / 符号图标
      expect(_labelOf(tester, 'edu_check_roll'), '进行检定（还剩 4 次）');
      // 逐码点确认：没有 emoji（U+1F300–1FAFF）/ 杂项符号（U+2600–27BF）/ 变体选择符
      final String label = _labelOf(tester, 'edu_check_roll');
      final List<int> runs = label.runes.toList();
      expect(
        runs.where((int r) =>
            (r >= 0x1F300 && r <= 0x1FAFF) ||
            (r >= 0x2600 && r <= 0x27BF) ||
            (r >= 0x2B00 && r <= 0x2BFF) ||
            r == 0xFE0F),
        isEmpty,
        reason: '按钮文案必须是纯文字，不能有 emoji / 符号图标：$label',
      );
      expect(_labelOf(tester, 'edu_check_roll'), isNot(contains('🎲')));
      expect(_labelOf(tester, 'edu_check_roll'), isNot(contains('✓')));
      expect(_textOf(tester, 'edu_check_remain'), contains('还可检定 4 次'));

      // 第 1 次
      await tester.tap(find.byKey(const Key('edu_check_roll')));
      await tester.pumpAndSettle();
      expect(_textOf(tester, 'edu_check_result'),
          '第 1 次检定：掷出 100 > 教育 20 → 教育 +10，现为 30');
      expect(_textOf(tester, 'edu_check_remain'), contains('还可检定 3 次'));

      // 第 2 次
      await tester.tap(find.byKey(const Key('edu_check_roll')));
      await tester.pumpAndSettle();
      expect(_textOf(tester, 'edu_check_result'),
          '第 2 次检定：掷出 100 > 教育 30 → 教育 +10，现为 40');
      expect(_textOf(tester, 'edu_check_remain'), contains('还可检定 2 次'));
      expect(_textOf(tester, 'edu_check_edu'), contains('生效 40'));
      expect(_textOf(tester, 'edu_check_raw'), contains('原始教育 20'));

      // 第 3、4 次
      await tester.tap(find.byKey(const Key('edu_check_roll')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edu_check_roll')));
      await tester.pumpAndSettle();
      expect(_textOf(tester, 'edu_check_result'), startsWith('第 4 次检定：'));
      expect(_textOf(tester, 'edu_check_remain'), contains('检定次数已用完（4/4）'));

      // 全部用完 → 禁用，且按钮文案仍无 emoji
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('edu_check_roll')))
            .onPressed,
        isNull,
      );
      expect(_labelOf(tester, 'edu_check_roll'), '已完成（4/4）');
      expect(asList(c.eduProgress['log']).length, 4);
      expect(eduForCheck(c), 60);
    });

    testWidgets('40 岁：第 1 次失败也算用掉一次，剩余 1 次且还能再掷', (tester) async {
      useTallScreen(tester);
      final c = _cardWith(age: 40, edu: 60);
      setRng(_alwaysMin); // 1D100 = 1 → 没有进步
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      await scrollTo(tester, 'edu_check_roll');

      expect(_labelOf(tester, 'edu_check_roll'), '进行检定（还剩 2 次）');
      await tester.tap(find.byKey(const Key('edu_check_roll')));
      await tester.pumpAndSettle();

      expect(_textOf(tester, 'edu_check_result'),
          '第 1 次检定：掷出 1 ≤ 教育 60 → 没有进步，教育保持 60');
      expect(_textOf(tester, 'edu_check_remain'), contains('还可检定 1 次'));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('edu_check_roll')))
            .onPressed,
        isNotNull,
        reason: '40 岁有 2 次，失败一次后还剩 1 次',
      );
      expect(eduForCheck(c), 60);
    });
    testWidgets('17 岁（本档 0 次）：按钮写「本年龄段不做检定」并禁用，文案说明原因', (tester) async {
      useTallScreen(tester);
      final c = _cardWith(age: 17, edu: 20);
      setRng(_alwaysMax);
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      await scrollTo(tester, 'edu_check_roll');

      expect(_labelOf(tester, 'edu_check_roll'), '本年龄段不做检定');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('edu_check_roll')))
            .onPressed,
        isNull,
        reason: '0 次就该禁用，别给一个点不动的「已完成（0/0）」让人困惑',
      );
      expect(_textOf(tester, 'edu_check_remain'), contains('本档不做教育进步检定'));
      expect(_textOf(tester, 'edu_check_result'), contains('本年龄没有教育进步检定次数'));
      expect(runEduCheck(c), isNull);
      expect(asList(c.eduProgress['log']), isEmpty);
    });
  });

  group('H · 未检定提示：还有剩余次数就提醒', () {
    testWidgets('42 岁只做了 1 次 → 仍提示「还有 1 次」，不拦路', (tester) async {
      await _gotoAttrs(tester, name: '四十二岁', age: '42');
      setRng(_alwaysMax);
      await scrollTo(tester, 'edu_check_roll');
      await tester.tap(find.byKey(const Key('edu_check_roll')));
      await tester.pumpAndSettle();
      expect(_textOf(tester, 'edu_check_remain'), contains('还可检定 1 次'));

      await tapKey(tester, 'btn_next');
      expect(find.byKey(const Key('credit_input')), findsOneWidget,
          reason: '只提示、不拦路');
      final hint = tester
          .widget<Text>(find.byKey(const Key('edu_check_skip_hint')))
          .data;
      expect(hint, contains('还有 1 次'));
    });

    testWidgets('42 岁做满 2 次 → 完全不提示', (tester) async {
      await _gotoAttrs(tester, name: '做满两次', age: '42');
      setRng(_alwaysMax);
      await scrollTo(tester, 'edu_check_roll');
      await tester.tap(find.byKey(const Key('edu_check_roll')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edu_check_roll')));
      await tester.pumpAndSettle();
      expect(_textOf(tester, 'edu_check_remain'), contains('检定次数已用完（2/2）'));

      await tapKey(tester, 'btn_next');
      expect(find.byKey(const Key('credit_input')), findsOneWidget);
      expect(find.byKey(const Key('edu_check_skip_hint')), findsNothing,
          reason: '次数用完就不该再念叨');
    });
  });
}
