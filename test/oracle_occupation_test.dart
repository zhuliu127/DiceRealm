// oracle 等价性测试：职业模型（core/occupation.js）
import 'package:dice_realm/domain/data/skills.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/occupation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/oracle.dart';

Map<String, Object?> _map(Object? v) => Map<String, Object?>.from(v as Map);

void main() {
  OracleFixture.load('occupation.json').run(<String, Object? Function(Object?)>{
    'parseSkillText': (args) => parseSkillText((args as List)[0]),
    'resolveSkillId': (args) => resolveSkillId((args as List)[0]),
    'evalFormula': (args) {
      final a = args as List;
      return evalFormula(a[0], _map(a[1]));
    },
    'getOccupationById': (args) => getOccupationById((args as List)[0]),
    'searchOccupations': (args) =>
        searchOccupations((args as List)[0]).map((o) => o['id']).toList(),
    'getRequirements': (args) =>
        getRequirements(cardOf(args)).map((r) => r).toList(),
    'occupationalSet': (args) => occupationalSet(cardOf(args)),
    'occupationPoints': (args) => occupationPoints(cardOf(args)),
    'interestPoints': (args) => interestPoints(cardOf(args)),
    'pointsFull': (args) => pointsFull(cardOf(args)),
    'validatorsOccupationChoices': (args) =>
        validateOccupationChoices(cardOf(args)),
    'validatorsSkillPoints': (args) => validateSkillPoints(cardOf(args)),
    'validatorsCreditRating': (args) => validateCreditRating(cardOf(args)),
    'validatorsSkillCap': (args) => validateSkillCap(cardOf(args)),
  });

  test('数据表规模与 JS 一致（230 职业 / 54 技能）', () {
    expect(listOccupations().length, 230);
    expect(cocSkills.length, 54);
  });

  test('技能名解析对别名与长名优先的处理与 JS 一致', () {
    expect(resolveSkillId('图书馆使用'), 'library');
    expect(resolveSkillId('魅惑'), 'charm');
    expect(resolveSkillId('取悦'), 'charm');
    expect(resolveSkillId('克苏鲁神话'), 'cthulhu');
    expect(resolveSkillId('心理'), 'psychology');
    expect(resolveSkillId('不存在的技能'), isNull);
  });

  test('parseSkillText 幂等：同一段文本解析两次结果相同', () {
    final text = '一项社交技能（魅惑、话术、恐吓、说服），格斗（斗殴），射击，法律，图书馆，心理学，潜行，追踪。';
    expect(parseSkillText(text), parseSkillText(text));
  });

  test('occupationalSet 不把组技能整组展开（40 项本职的根治点）', () {
    // 厨师这类职业原文写着「技艺」「格斗」但不点名专攻 → 只应算一个专攻
    final card = cardOf(<String, Object?>{
      'card': <String, Object?>{
        'occupationId': 'occ2',
        'occupationPicks': <String, Object?>{},
      },
    });
    final set = occupationalSet(card);
    expect(
      set.keys.where((k) => k.startsWith('art_craft::')).length,
      lessThanOrEqualTo(1),
    );
    expect(
      set.keys.where((k) => k.startsWith('fighting::')).length,
      lessThanOrEqualTo(1),
    );
  });

  test('搜索索引含组技能子类名（搜「斗殴」「步枪」能命中职业）', () {
    expect(searchOccupations('斗殴').isNotEmpty, isTrue);
    expect(searchOccupations('取悦').isNotEmpty, isTrue);
    expect(searchOccupations('绝对不存在的词').isEmpty, isTrue);
  });

  test('空 occupationId 时各统计返回 0 且不抛', () {
    final card = cardOf(<String, Object?>{
      'card': <String, Object?>{'occupationId': ''},
    });
    expect(occupationPoints(card), <String, Object?>{
      'total': 0,
      'used': 0,
      'remain': 0,
    });
    expect(occupationalSet(card), isEmpty);
    expect(getRequirements(card), isEmpty);
    expect(jsNum(interestPoints(card)['total']), 0);
  });
}
