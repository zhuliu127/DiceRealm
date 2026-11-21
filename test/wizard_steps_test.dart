// ============================================================
// wizard_steps_test.dart — 步骤注册表 + 「旧索引 → 步骤 id」映射
//
// 钉住的硬约束：
//   · 硬约束 3：「去修复 →」必须跳到正确步骤（映射表逐条断言）
//   · 重构段要求：映射到的步骤 id 必须真实存在（防「跳到不存在的页」）
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/ui/create/wizard_checks.dart';
import 'package:dice_realm/ui/create/wizard_steps.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一张「什么都没填」的卡：让 checkList 的 10 项全部报错，
/// 这样每一行的 label / step 都能被取到
Character _emptyCard() {
  final c = Character(newCharacter());
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

WizardSteps _registry([Character? card]) => WizardSteps(
  draft: card ?? _emptyCard(),
  onChanged: () {},
  onJumpTo: (_) {},
);

void main() {
  group('注册表（唯一事实源）', () {
    test('步骤 id 唯一，顺序与旧版 icon 编号一致', () {
      final r = _registry();
      final ids = r.ids;
      expect(ids.length, ids.toSet().length, reason: 'id 必须唯一（跳转靠它定位）');
      expect(ids, <String>[
        'rules',
        'basics',
        'attrs',
        'assets', // ⚠️ 资产必须在技能之前：信用评级占用职业点
        'skills',
        'combat',
        'gear',
        'background',
        'summary',
      ]);
    });

    test('末步判定与底栏文案从表派生（没有 step == N 字面量）', () {
      final r = _registry();
      expect(r.isLast(0), isFalse);
      expect(r.primaryLabel(0), '下一步');
      expect(r.isLast(r.length - 1), isTrue);
      expect(r.primaryLabel(r.length - 1), '保存角色卡');
    });

    test('indexOf 认得出每个 id，认不出的返回 0', () {
      final r = _registry();
      for (var i = 0; i < r.length; i++) {
        expect(r.indexOf(r.ids[i]), i);
        expect(r.has(r.ids[i]), isTrue);
      }
      expect(r.indexOf('不存在的步骤'), 0);
      expect(r.has('不存在的步骤'), isFalse);
    });
  });

  group('硬约束 3：旧索引 → 步骤 id 映射（逐条）', () {
    test('checkList 的 10 项逐条映射到正确步骤', () {
      final card = _emptyCard();
      final rows = checkList(card);
      expect(rows.length, 10, reason: '规则层的检查项数不能变');

      // 逐条列：label → 期望的步骤 id（不是页序数字）
      const expected = <String, String>{
        '角色姓名已填写': 'basics',
        '玩家名称已填写': 'basics',
        '年龄合法': 'basics',
        '属性合法（15-90 且为 5 的倍数）': 'attrs',
        '已选择职业': 'basics', // 新流程把「职业」并进基本资料
        // D2：这一项只能在技能页勾选（domain 里标的 step=2 与「已选择职业」共用，
        // 所以映射走 (step,label) 二元查表），见 wizard_fix_jump_test.dart 的「点进去真能修」
        '职业限定技能选择完成': 'skills',
        '信用评级在职业范围内': 'assets',
        '职业技能点未超额': 'skills',
        '兴趣技能点未超额': 'skills',
        '技能未超过上限': 'skills',
      };

      for (final row in rows) {
        final label = jsStr(row['label']);
        expect(
          expected.containsKey(label),
          isTrue,
          reason: '出现了未登记的新检查项：$label',
        );
        expect(
          stepIdForCheckRow(row),
          expected[label],
          reason: '「$label」应跳到 ${expected[label]}（实际旧索引 ${row['step']}）',
        );
      }
      // 期望表里每一项都真的被检查到了（防止 checkList 少项时静默通过）
      expect(rows.map((r) => jsStr(r['label'])).toSet(), expected.keys.toSet());
    });

    test('每个出现过的 step 值都映射到一个**真实存在**的步骤 id', () {
      final r = _registry();
      final usedSteps = checkList(_emptyCard())
          .map((r) => jsParseInt(r['step']))
          .toSet();
      expect(usedSteps, <int>{0, 1, 2, 3, 4});
      for (final s in usedSteps) {
        final id = stepIdForCheck(s);
        expect(id, isNotNull, reason: '旧索引 $s 没有映射');
        expect(r.has(id!), isTrue, reason: '旧索引 $s 映射到了不存在的步骤 $id');
      }
    });

    test('wizardChecks 的每一行都指向真实步骤（无处可跳时为 null）', () {
      final card = _emptyCard();
      final r = _registry(card);
      final checks = wizardChecks(card);
      expect(checks.length, 13, reason: '规则层 10 项 + 本层附加 3 项（武器/防具/物品）');
      for (final c in checks) {
        if (c.stepId == null) continue;
        expect(
          r.has(c.stepId!),
          isTrue,
          reason: '「${c.label}」指向了不存在的步骤 ${c.stepId}',
        );
      }
    });

    test('未登记的旧索引 / 非数字 → null（不显示「去修复」）', () {
      expect(stepIdForCheck(9), isNull);
      expect(stepIdForCheck('abc'), isNull);
      expect(stepIdForCheck(null), isNull);
    });
  });

  group('校验函数（从页面搬出来后行为不变）', () {
    test('基本资料：姓名 / 玩家 / 年龄 / 职业 逐项拦截', () {
      final c = Character(newCharacter());
      expect(validateBasics(c), '请填写角色姓名');
      c.raw['characterName'] = '甲';
      expect(validateBasics(c), '请填写玩家名称');
      c.raw['playerName'] = '老王';
      expect(validateBasics(c), contains('年龄'));
      c.basicInfo['age'] = 32;
      expect(validateBasics(c), contains('请选择职业'));
      c.raw['occupationId'] = 'occ67';
      expect(validateBasics(c), isNull);
    });

    test('属性：没填完 / 非法值 / 超总和 各有准确文案', () {
      final c = Character(newCharacter())..raw['attributeMode'] = 'pointbuy';
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
      expect(validateAttrs(c), isNull);

      c.attributes['str'] = 53;
      expect(validateAttrs(c), '力量：必须是 5 的倍数');

      c.attributes['str'] = 90;
      c.attributes['con'] = 90;
      c.attributes['siz'] = 90;
      c.attributes['dex'] = 90;
      c.attributes['app'] = 90;
      c.attributes['int'] = 90;
      c.attributes['pow'] = 90;
      expect(validateAttrs(c), contains('超出上限'));

      c.attributes['str'] = '';
      expect(validateAttrs(c), contains('请先填完 8 项属性'));
    });

    test('非必填步骤永远放行', () {
      final c = Character(newCharacter());
      expect(validateRules(c), isNull);
      expect(validateOptional(c), isNull);
    });
  });
}
