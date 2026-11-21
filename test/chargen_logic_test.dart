// ============================================================
// chargen_logic_test.dart — 车卡纯逻辑（属性闸门 / 自动配点 / 勾选上限）
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/occupation.dart';
// skillmodel 里有个 find(skill) 会与 flutter_test 的 find(finder) 撞名，这里隐藏掉；
// 需要按 key 查技能时用 chargen_logic 的 findSkill。
import 'package:dice_realm/domain/skillmodel.dart' hide find;
import 'package:dice_realm/ui/create/chargen_logic.dart';
import 'package:flutter_test/flutter_test.dart';

Character _card({
  String occupationId = 'occ67',
  int attrValue = 60,
  int age = 30,
}) {
  final c = Character(newCharacter());
  c.raw['id'] = 'logic01';
  c.raw['occupationId'] = occupationId;
  c.basicInfo['age'] = age;
  c.raw['age'] = age;
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
    c.attributes[k] = attrValue;
  }
  recalc(c);
  return c;
}

void main() {
  group('属性输入闸门（挡住原码 ATT_MAP 异常）', () {
    test('空 / 非数字 / 越界 / 非 5 倍数 全部拦下', () {
      expect(attrFieldError(''), '未填写');
      expect(attrFieldError('   '), '未填写');
      expect(attrFieldError('abc'), '必须是整数');
      expect(attrFieldError('50.5'), '必须是整数');
      expect(attrFieldError('14'), '必须在 15-90 之间');
      expect(attrFieldError('91'), '必须在 15-90 之间');
      expect(attrFieldError('53'), '必须是 5 的倍数');
      expect(attrFieldError('95'), '必须在 15-90 之间');
    });

    test('合法值放行', () {
      for (final v in <String>['15', '50', '90']) {
        expect(attrFieldError(v), isNull, reason: v);
      }
    });
  });

  group('属性体检', () {
    test('点数分配：8 项 × 60 = 480 超过 460 上限', () {
      final c = _card(attrValue: 60);
      final r = checkAttributes(c, pointBuy: true, includeLuck: false);
      expect(r.over, isTrue);
      expect(r.sum, 480);
      expect(r.cap, 460);
      expect(r.errors.containsKey('__sum'), isTrue);
    });

    test('点数分配：8 项 × 55 = 440 合法', () {
      final c = _card(attrValue: 55);
      final r = checkAttributes(c, pointBuy: true, includeLuck: false);
      expect(r.ok, isTrue);
      expect(r.remain, 20);
      expect(r.allCoreFilled, isTrue);
    });

    test('含幸运时上限变 540，且幸运纳入合计', () {
      final c = _card(attrValue: 55); // 9 × 55 = 495
      final r = checkAttributes(c, pointBuy: true, includeLuck: true);
      expect(r.cap, 540);
      expect(r.sum, 495);
      expect(r.ok, isTrue);
    });

    test('随机模式只要求 8 项合法，不校验总和', () {
      final c = _card(attrValue: 90); // 8 × 90 = 720
      final r = checkAttributes(c, pointBuy: false, includeLuck: true);
      expect(r.ok, isTrue);
      expect(r.sum, 720);
    });

    test('缺项时报未填', () {
      final c = _card();
      c.attributes['pow'] = '';
      final r = checkAttributes(c, pointBuy: true, includeLuck: false);
      expect(r.allCoreFilled, isFalse);
      expect(r.errors['pow'], '未填写');
    });
  });

  group('职业点 / 兴趣点', () {
    test('一键分配能把两池都花完（法官：教育×4，INT×2）', () {
      final c = _card();
      syncSkills(c);
      final left = autoSpendPoints(c);

      expect(left[0], 0, reason: '职业技能点应当分配完');
      expect(left[1], 0, reason: '兴趣技能点应当分配完');
      expect(
        jsNum(occupationPoints(c)['used']),
        jsNum(occupationPoints(c)['total']),
      );
      expect(
        jsNum(interestPoints(c)['used']),
        jsNum(interestPoints(c)['total']),
      );
      // 分配后的每项都不得超上限
      for (final s in c.skills.map(asMap)) {
        expect(
          jsNum(s['total']),
          lessThanOrEqualTo(capOf(c, s)),
          reason: jsStr(s['name']),
        );
      }
    });

    test('一键分配不会给「克苏鲁神话 / 信用评级」加车卡点', () {
      final c = _card();
      syncSkills(c);
      autoSpendPoints(c);
      for (final id in <String>['cthulhu', 'credit']) {
        final s = findSkill(c, id);
        if (s != null) {
          expect(jsNum(s['occ']), 0, reason: id);
          expect(jsNum(s['int']), 0, reason: id);
        }
      }
    });

    test('点数用完后 canAbsorbMore 为 false', () {
      final c = _card();
      syncSkills(c);
      autoSpendPoints(c);
      expect(canAbsorbMore(c, 'occ'), isFalse);
      expect(canAbsorbMore(c, 'int'), isFalse);
    });
  });

  group('职业限定技能勾选', () {
    test('超过上限时拒绝并保持原样', () {
      final c = _card();
      final req = <String, Object?>{
        'id': 'r9',
        'type': 'free',
        'count': 1,
        'label': '任选 1 项',
      };
      final a = <String, Object?>{
        'skill': 'spot_hidden',
        'sub': null,
        'name': '侦查',
      };
      final b = <String, Object?>{'skill': 'listen', 'sub': null, 'name': '聆听'};

      expect(togglePick(c, req, a, max: 1), isTrue);
      expect(togglePick(c, req, b, max: 1), isFalse);
      expect(picksOf(c, 'r9').length, 1);

      // 再点一次已选项 = 取消
      expect(togglePick(c, req, a, max: 1), isTrue);
      expect(picksOf(c, 'r9'), isEmpty);
    });

    test('组技能按「id::专攻」区分', () {
      final c = _card();
      final req = <String, Object?>{
        'id': 'r10',
        'type': 'free',
        'count': 2,
        'label': '任选 2 项',
      };
      final a = <String, Object?>{
        'skill': 'fighting',
        'sub': '斗殴',
        'name': '格斗（斗殴）',
      };
      final b = <String, Object?>{
        'skill': 'fighting',
        'sub': '剑',
        'name': '格斗（剑）',
      };
      expect(togglePick(c, req, a, max: 2), isTrue);
      expect(togglePick(c, req, b, max: 2), isTrue);
      expect(picksOf(c, 'r10').length, 2);
      expect(isPicked(picksOf(c, 'r10'), 'fighting', '斗殴'), isTrue);
      expect(isPicked(picksOf(c, 'r10'), 'fighting', '剑'), isTrue);
    });
  });

  test('年龄写回同时更新顶层 age 与 basicInfo.age', () {
    final c = Character(newCharacter());
    setAge(c, 47);
    expect(jsNum(c.raw['age']), 47);
    expect(jsNum(c.basicInfo['age']), 47);
    setAge(c, '');
    expect(jsStr(c.raw['age']), '');
    expect(ageOf(c), 0);
  });
}
