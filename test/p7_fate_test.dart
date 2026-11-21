// ============================================================
// p7_fate_test.dart — P7-E：手动车卡「天命 N 选一」对齐旧版
//
// 覆盖：N 边界 1/2/10/11、两个快捷按钮、掷出后不可重掷、选组写回、
//      fate 纯数据持久化、硬拦截文案、属性只来自 genRandom()、
//      fate 不误套购点总上限、切换模式后状态不串。
// ============================================================

import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:dice_realm/domain/character.dart' show Character, newCharacter;
import 'package:dice_realm/domain/js_compat.dart'
    show JsClock, JsRng, jsNum, nowClock, nowRng, setClock, setRng;
import 'package:dice_realm/domain/rules_coc7.dart'
    show genMax, genMin, genRandom, genStep;
import 'package:dice_realm/ui/attr_meta.dart' show allAttrKeys;
import 'package:dice_realm/ui/create/chargen_logic.dart'
    show
        checkAttributes,
        ensureFate,
        fateDefaultN,
        fateN,
        fateOptionSum,
        fateOptions,
        fatePicked,
        fateRolled,
        isValidFateN,
        pickFate,
        rollFate;
import 'package:dice_realm/ui/create/steps/step_attrs.dart' show StepAttrs;
import 'package:dice_realm/ui/create/wizard_steps.dart' show validateAttrs;
import 'package:flutter/material.dart'
    show
        BuildContext,
        FilledButton,
        Key,
        MaterialApp,
        OutlinedButton,
        Scaffold,
        SegmentedButton,
        StatefulBuilder,
        StateSetter,
        Text,
        TextField,
        Widget;
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart' show scrollTo, useTallScreen;
import 'support/oracle.dart' show Lcg, oracleNowMs;

/// 每组天命都必须逐项合法（5 的倍数 + 落在规则区间），且两种合计口径自洽。
void _expectLegalOption(Map<String, Object?> o) {
  for (final String k in allAttrKeys) {
    final int v = jsNum(o[k]);
    expect(v % genStep, 0, reason: '$k=$v 不是 $genStep 的倍数');
    expect(v, inInclusiveRange(genMin, genMax), reason: '$k=$v 越界');
  }
  expect(
    fateOptionSum(o, withLuck: true),
    fateOptionSum(o, withLuck: false) + jsNum(o['luck']),
    reason: '含幸运合计 = 不含幸运合计 + 幸运',
  );
}

/// 用 StatefulBuilder 模拟 CreateFlowPage 的 onChanged（重建子树）。
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

void main() {
  late JsRng savedRng;
  late JsClock savedClock;
  setUp(() {
    savedRng = nowRng;
    savedClock = nowClock;
    setRng(Lcg(20261110).call);
    setClock(() => oracleNowMs);
  });
  tearDown(() {
    setRng(savedRng);
    setClock(savedClock);
  });

  group('E · 纯逻辑：N 边界 / 掷出 / 选组 / 持久化', () {
    test('N 只认 2-10；1 / 11 / 0 一律拒掷且一个字节不改', () {
      expect(isValidFateN(1), isFalse);
      expect(isValidFateN(2), isTrue);
      expect(isValidFateN(10), isTrue);
      expect(isValidFateN(11), isFalse);
      expect(isValidFateN(0), isFalse);

      final Character c = Character(newCharacter());
      expect(rollFate(c, 1), isFalse);
      expect(rollFate(c, 11), isFalse);
      expect(fateRolled(c), isFalse);
      expect(fateOptions(c), isEmpty);
      expect(fateN(c), fateDefaultN);
      expect(fatePicked(c), -1);
    });

    test('掷出 N 组：每组 9 项都来自 genRandom() 且合法', () {
      final Character c = Character(newCharacter());
      setRng(Lcg(555).call);
      final List<Map<String, int>> expected = List<Map<String, int>>.generate(
        4,
        (int _) => genRandom(),
      );
      setRng(Lcg(555).call);
      expect(rollFate(c, 4), isTrue);

      final List<Map<String, Object?>> opts = fateOptions(c);
      expect(opts.length, 4);
      for (var i = 0; i < 4; i++) {
        _expectLegalOption(opts[i]);
        for (final String k in allAttrKeys) {
          expect(jsNum(opts[i][k]), expected[i][k],
              reason: '第 $i 组的 $k 必须与 genRandom() 逐字一致（不另造公式）');
        }
      }
      expect(fateRolled(c), isTrue);
      expect(fateN(c), 4);
      expect(fatePicked(c), -1);
      expect(c.raw['attributeMode'], 'fate');
      expect(jsNum(c.fate['rolledAt']), greaterThan(0));
    });

    test('★ 掷出后锁定：不可重掷、N 不变、选项一个字节都不改', () {
      final Character c = Character(newCharacter());
      expect(rollFate(c, 5), isTrue);
      final List<Map<String, Object?>> before = fateOptions(c);
      final List<List<int>> snapshot = before
          .map((Map<String, Object?> o) =>
              allAttrKeys.map((String k) => jsNum(o[k])).toList())
          .toList();

      expect(rollFate(c, 10), isFalse);
      expect(fateN(c), 5, reason: '重掷不许改 N');
      final List<Map<String, Object?>> after = fateOptions(c);
      expect(after.length, 5);
      for (var i = 0; i < 5; i++) {
        expect(
          allAttrKeys.map((String k) => jsNum(after[i][k])).toList(),
          snapshot[i],
          reason: '第 $i 组不该被重掷覆盖',
        );
      }
    });

    test('选组：写回 9 项属性 + picked + 模式；越界 / 未掷出都拒收', () {
      final Character c = Character(newCharacter());
      expect(pickFate(c, 0), isFalse, reason: '没掷出不许选');
      expect(rollFate(c, 5), isTrue);
      expect(pickFate(c, -1), isFalse);
      expect(pickFate(c, 5), isFalse);
      expect(pickFate(c, 2), isTrue);

      final Map<String, Object?> chosen = fateOptions(c)[2];
      for (final String k in allAttrKeys) {
        expect(jsNum(c.attributes[k]), jsNum(chosen[k]),
            reason: '$k 没写回卡上');
      }
      expect(fatePicked(c), 2);
      expect(c.raw['attributeMode'], 'fate');
      expect(validateAttrs(c), isNull, reason: '选完组就该放行');
    });

    test('fate 是纯数据：JSON 往返 / 重进向导都不丢', () {
      final Character c = Character(newCharacter());
      expect(rollFate(c, 3), isTrue);
      expect(pickFate(c, 1), isTrue);

      final Object? decoded = jsonDecode(jsonEncode(c.raw));
      final Character reloaded =
          Character(Map<String, Object?>.from(decoded as Map));
      expect(fateRolled(reloaded), isTrue);
      expect(fateN(reloaded), 3);
      expect(fatePicked(reloaded), 1);
      expect(fateOptions(reloaded).length, 3);
      for (var i = 0; i < 3; i++) {
        expect(fateOptionSum(fateOptions(reloaded)[i], withLuck: true),
            fateOptionSum(fateOptions(c)[i], withLuck: true));
      }
      expect(reloaded.raw['attributeMode'], 'fate');
    });

    test('ensureFate 幂等规整：脏 N / 空选项 / 越界 picked 都归位', () {
      final Character c = Character(newCharacter());
      final Map<String, Object?> f = ensureFate(c);
      expect(f['n'], fateDefaultN);
      expect(f['rolled'], isFalse);
      expect(f['picked'], -1);

      f['n'] = 99;
      f['rolled'] = true;
      f['picked'] = 42;
      f['options'] = <Object?>[];
      final Map<String, Object?> fixed = ensureFate(c);
      expect(fixed['n'], fateDefaultN, reason: '非法 N 回退 5');
      expect(fixed['rolled'], isFalse, reason: '没选项不算掷出');
      expect(fixed['picked'], -1);
    });

    test('切换模式后状态不串：fate 数据仍挂在卡上', () {
      final Character c = Character(newCharacter());
      expect(rollFate(c, 5), isTrue);
      c.raw['attributeMode'] = 'random';
      expect(fateRolled(c), isTrue);
      expect(fateOptions(c).length, 5);
      c.raw['attributeMode'] = 'fate';
      expect(fateOptions(c).length, 5);
      expect(fateN(c), 5);
    });
  });

  group('E · 硬拦截与购点上限口径', () {
    test('没掷出 / 没选一组都不准进下一步（文案对齐旧版）', () {
      final Character c = Character(newCharacter());
      c.raw['attributeMode'] = 'fate';
      expect(validateAttrs(c), '天命还没掷出：先点「掷出天命」');

      expect(rollFate(c, 5), isTrue);
      expect(validateAttrs(c), '请先从 5 组天命里选一组');

      expect(pickFate(c, 0), isTrue);
      expect(validateAttrs(c), isNull);
    });

    test('★ fate 不误套购点总上限；pointbuy 才会拦', () {
      final Character c = Character(newCharacter());
      c.raw['attributeMode'] = 'fate';
      for (final String k in allAttrKeys) {
        c.attributes[k] = genMax; // 8 项合计 720 > 购点上限 540
      }
      final Map<String, Object?> f = ensureFate(c);
      f['options'] = <Object?>[
        <String, Object?>{for (final String k in allAttrKeys) k: genMax},
      ];
      f['rolled'] = true;
      f['picked'] = 0;

      final check = checkAttributes(c, pointBuy: false, includeLuck: true);
      expect(check.enforceCap, isFalse);
      expect(check.over, isFalse);
      expect(check.sum, 8 * genMax);
      expect(validateAttrs(c), isNull,
          reason: 'fate 模式不该被 540 的购点总上限卡住');

      // 反向守卫：同一张卡切成 pointbuy，购点上限确实会生效 —— 证明
      // 上面的「放行」不是因为断言恒绿。
      c.raw['attributeMode'] = 'pointbuy';
      expect(checkAttributes(c, pointBuy: true, includeLuck: true).over, isTrue);
      expect(validateAttrs(c), isNotNull);
    });
  });

  group('E · UI：第三档 / 快捷按钮 / 锁定 / 选组', () {
    testWidgets('SegmentedButton 有三档，切到「天命 N 选一」才出天命块',
        (WidgetTester tester) async {
      useTallScreen(tester);
      final Character c = Character(newCharacter());
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();

      final SegmentedButton<String> seg = tester
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));
      expect(seg.segments.length, 3);
      expect(
        seg.segments.map((s) => s.value).toList(),
        <String>['pointbuy', 'random', 'fate'],
      );
      expect(find.byKey(const Key('attr_fate_n')), findsNothing,
          reason: '未切模式时不该出现天命控件');

      await tester.tap(find.text('天命 N 选一'));
      await tester.pumpAndSettle();
      expect(c.raw['attributeMode'], 'fate');
      expect(find.byKey(const Key('attr_fate_n')), findsOneWidget);
      expect(find.byKey(const Key('attr_fate_quick_5')), findsOneWidget);
      expect(find.byKey(const Key('attr_fate_quick_10')), findsOneWidget);
      expect(_textOf(tester, 'attr_fate_state'), '未掷出');
    });

    testWidgets('★ 5 选 1 / 10 选 1 快捷按钮 + N 边界 1 / 2 / 10 / 11',
        (WidgetTester tester) async {
      useTallScreen(tester);
      final Character c = Character(newCharacter());
      c.raw['attributeMode'] = 'fate';
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('attr_fate_quick_5')));
      await tester.pumpAndSettle();
      expect(fateN(c), 5);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('attr_fate_n')))
            .controller
            ?.text,
        '5',
      );

      await tester.tap(find.byKey(const Key('attr_fate_quick_10')));
      await tester.pumpAndSettle();
      expect(fateN(c), 10);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('attr_fate_n')))
            .controller
            ?.text,
        '10',
      );

      await scrollTo(tester, 'attr_fate_roll');
      for (final String bad in <String>['1', '11']) {
        await tester.enterText(find.byKey(const Key('attr_fate_n')), bad);
        await tester.tap(find.byKey(const Key('attr_fate_roll')));
        await tester.pumpAndSettle();
        expect(fateRolled(c), isFalse, reason: 'N=$bad 不许掷出');
        expect(_textOf(tester, 'attr_fate_error'),
            contains('2 - 10 之间的整数'));
      }

      await tester.enterText(find.byKey(const Key('attr_fate_n')), '2');
      await tester.tap(find.byKey(const Key('attr_fate_roll')));
      await tester.pumpAndSettle();
      expect(fateRolled(c), isTrue);
      expect(fateN(c), 2);
      expect(fateOptions(c).length, 2);
      for (final Map<String, Object?> o in fateOptions(c)) {
        _expectLegalOption(o);
      }
    });

    testWidgets('★ 掷出后锁定 N 与重掷；选组写回卡；切模式再切回数据仍在',
        (WidgetTester tester) async {
      useTallScreen(tester);
      final Character c = Character(newCharacter());
      c.raw['attributeMode'] = 'fate';
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();

      await scrollTo(tester, 'attr_fate_roll');
      await tester.tap(find.byKey(const Key('attr_fate_roll')));
      await tester.pumpAndSettle();
      expect(fateRolled(c), isTrue);
      expect(fateOptions(c).length, fateDefaultN);

      expect(_textOf(tester, 'attr_fate_state'), '已掷出 · 不可重掷');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('attr_fate_roll')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('attr_fate_n')))
            .readOnly,
        isTrue,
      );
      for (final String k in <String>['attr_fate_quick_5', 'attr_fate_quick_10']) {
        expect(
          tester.widget<OutlinedButton>(find.byKey(Key(k))).onPressed,
          isNull,
          reason: '$k 掷出后必须停用',
        );
      }

      final Map<String, Object?> chosen = fateOptions(c)[1];
      await scrollTo(tester, 'attr_fate_pick_1');
      await tester.tap(find.byKey(const Key('attr_fate_pick_1')));
      await tester.pumpAndSettle();
      expect(fatePicked(c), 1);
      expect(validateAttrs(c), isNull);
      for (final String k in allAttrKeys) {
        expect(jsNum(c.attributes[k]), jsNum(chosen[k]));
      }

      // 切到随机再切回：fate 是卡上的纯数据，不随 widget state 丢。
      await tester.tap(find.text('随机掷骰'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('attr_fate_n')), findsNothing);
      expect(c.raw['attributeMode'], 'random');
      await tester.tap(find.text('天命 N 选一'));
      await tester.pumpAndSettle();
      expect(fateRolled(c), isTrue);
      expect(fateOptions(c).length, fateDefaultN);
      expect(fatePicked(c), 1);
    });
  });
}
