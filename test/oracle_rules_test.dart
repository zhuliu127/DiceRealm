// oracle 等价性测试：COC 7th 规则（core/rules-coc7.js）
import 'package:dice_realm/domain/data/skills.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/rules_coc7.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/oracle.dart';

Map<String, Object?> _map(Object? v) => Map<String, Object?>.from(v as Map);

void main() {
  OracleFixture.load('rules.json').run(<String, Object? Function(Object?)>{
    'ageAdjust': (args) => ageAdjust(_map((args as List)[0])),
    'ageRule': (args) => ageRule((args as List)[0]),
    'ageProgressChecks': (args) => ageProgressChecks((args as List)[0]),
    'spreadLoss': (args) {
      final a = args as List;
      return spreadLoss(
        (a[0] as num).toInt(),
        (a[1] as List).map((x) => '$x').toList(),
        (a[2] as Map).map((k, v) => MapEntry('$k', (v as num).toInt())),
      );
    },
    'derived': (args) => derived(_map((args as List)[0])),
    'dbBuild': (args) => dbBuild((args as List)[0] as num),
    'maxSan': (args) => maxSan((args as List)[0]),
    'skillCapOf': (args) {
      final a = args as List;
      final occSetRaw = a[2];
      return skillCapOf(
        cardOf(<String, Object?>{'card': a[0]}),
        _map(a[1]),
        occSetRaw == null
            ? null
            : (occSetRaw as Map).map((k, v) => MapEntry('$k', v == true)),
      );
    },
    'capExempt': (args) => capExempt((args as List)[0]),
    'isGrowthOnly': (args) => isGrowthOnly((args as List)[0]),
    'eduImproveCheck': (args) => eduImproveCheck((args as List)[0]),
    'genRandom': (args) => genRandom(),
    'genRandomOne': (args) => genRandomOne('${(args as List)[0]}'),
    'validatePointBuy': (args) {
      final a = args as List;
      return validatePointBuy(_map(a[0]), a[1], a[2] == true);
    },
    'radar': (args) => radar((args as List)[0] as List?, cocSkills),
    'attrByName': (args) => attrByName((args as List)[0]),
    'validatorsAttributes': (args) => validateAttributes(cardOf(args)),
    'validatorsBasicInfo': (args) => validateBasicInfo(cardOf(args)),
    'validatorsOccupationSelected': (args) =>
        validateOccupationSelected(cardOf(args)),
  });

  test('规则常量与 JS 一致', () {
    expect(physFloor, 15);
    expect(genMin, 15);
    expect(genMax, 90);
    expect(genStep, 5);
    expect(defaultOccSkillCap, 99);
    expect(mentalNormal, '正常');
    expect(mentalSymptom, '疯狂症状');
    expect(mentalPermanent, '永久疯狂');
    expect(bodyStatus, <String>['正常', '轻伤', '重伤', '濒死', '昏迷', '死亡']);
    /* P8（用户需求 6/7）有意偏离旧版 JS 常量：
       · 「昏迷」是身体状态（status.dying / unconscious），不是精神状态 → 删掉；
       · 新增「潜在疯狂」（不定疯狂的症状消退后的状态）。
       其余项与旧版一致。 */
    expect(mentalStatus, <String>[
      '正常',
      '临时疯狂',
      '不定疯狂',
      '潜在疯狂',
      '疯狂症状',
      '永久疯狂',
      '其他',
    ]);
  });

  test('属性定义表 9 项，幸运标记 optional', () {
    expect(attributes.length, 9);
    expect(jsTruthy(attributes.last['optional']), isTrue);
    expect(attributes.map((a) => a['key']).toList(), <String>[
      'str',
      'con',
      'siz',
      'dex',
      'app',
      'int',
      'pow',
      'edu',
      'luck',
    ]);
  });
}
