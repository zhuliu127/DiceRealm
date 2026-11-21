// oracle 等价性测试：重算调度与校验（core/engine.js）
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/oracle.dart';

void main() {
  OracleFixture.load('engine.json').run(<String, Object? Function(Object?)>{
    'recalc': (args) => recalc(cardOf(args)).toJson(),
    'attrsReady': (args) => attrsReady(cardOf(args)),
    'attrSum': (args) => attrSum(cardOf(args)),
    'attrSumNoLuck': (args) => attrSum(cardOf(args), includeLuck: false),
    'attrSumEff': (args) => attrSumEff(cardOf(args)),
    'validate': (args) => validate(cardOf(args)),
    'checkList': (args) => checkList(cardOf(args)),
    'effAttrs': (args) => effAttrs(cardOf(args)),
    'ageAdjustOf': (args) => ageAdjustOf(cardOf(args)),
    'clamp': (args) => clamp(cardOf(args).attributes['str'], 0, 99),
  });

  test('clamp 边界：非数字落到下限，超界夹住', () {
    expect(clamp('', 0, 99), 0);
    expect(clamp('abc', 3, 99), 3);
    expect(clamp(-5, 0, 99), 0);
    expect(clamp(500, 0, 99), 99);
    expect(clamp('50', 0, 99), 50);
    expect(clamp(50.9, 0, 99), 50);
  });

  test('recalc 使派生值一致：maxHP=⌊(CON+SIZ)/10⌋、maxMP=⌊POW/5⌋、SAN 上限=POW', () {
    final c = cardOf(<String, Object?>{
      'card': <String, Object?>{
        'basicInfo': <String, Object?>{'age': 30},
        'age': 30,
        'attributes': <String, Object?>{
          'str': 60,
          'con': 65,
          'siz': 70,
          'dex': 55,
          'app': 50,
          'int': 80,
          'pow': 60,
          'edu': 70,
          'luck': 45,
        },
        'status': <String, Object?>{},
      },
    });
    recalc(c);
    expect(jsNum(c.derivedStats['maxHP']), 13); // (65+70)/10 = 13.5 → 13
    expect(jsNum(c.derivedStats['maxMP']), 12); // 60/5
    expect(jsNum(c.derivedStats['maxSAN']), 60);
    expect(jsNum(c.status['maxHP']), 13);
    expect(jsNum(c.status['currentHP']), 13);
    expect(jsNum(c.status['currentSAN']), 60);
    expect(jsNum(c.status['currentLuck']), 45);
  });

  test('recalc 幂等：连跑两次结果不变（缓存指纹不引入漂移）', () {
    final c = cardOf(<String, Object?>{
      'card': <String, Object?>{
        'basicInfo': <String, Object?>{'age': 45},
        'age': 45,
        'attributes': <String, Object?>{
          'str': 70,
          'con': 60,
          'siz': 65,
          'dex': 50,
          'app': 40,
          'int': 75,
          'pow': 55,
          'edu': 80,
          'luck': 35,
        },
        'status': <String, Object?>{},
      },
    });
    recalc(c);
    final first = Map<String, Object?>.from(c.toJson());
    recalc(c);
    expect(c.toJson().toString(), first.toString());
  });

  test('raw EDU 变化后旧的教育进步检定被作废', () {
    final c = cardOf(<String, Object?>{
      'card': <String, Object?>{
        'basicInfo': <String, Object?>{'age': 45},
        'age': 45,
        'attributes': <String, Object?>{
          'str': 50,
          'con': 50,
          'siz': 50,
          'dex': 50,
          'app': 50,
          'int': 50,
          'pow': 50,
          'edu': 50,
          'luck': 50,
        },
        'eduProgress': <String, Object?>{
          'base': 40,
          'baseEdu': 40,
          'done': 1,
          'log': <Object?>[
            <String, Object?>{'before': 40, 'gain': 6},
          ],
          'bonus': 6,
        },
        'status': <String, Object?>{},
      },
    });
    final dropped = dropStaleEduChecks(c);
    expect(dropped, isTrue);
    expect(asList(c.eduProgress['log']), isEmpty);
    expect(jsNum(c.eduProgress['bonus']), 0);
    expect(jsNum(c.eduProgress['baseEdu']), 50);
    expect(jsNum(c.eduProgress['staleFromEdu']), 40);
    expect(jsNum(c.eduProgress['resetAt']), oracleNowMs);
  });

  test('没有基准但首条 before 与当前 EDU 一致 → 只补记基准、不作废', () {
    final c = cardOf(<String, Object?>{
      'card': <String, Object?>{
        'attributes': <String, Object?>{'edu': 50},
        'eduProgress': <String, Object?>{
          'done': 1,
          'log': <Object?>[
            <String, Object?>{'before': 50, 'gain': 6},
          ],
          'bonus': 6,
        },
      },
    });
    expect(dropStaleEduChecks(c), isFalse);
    expect(asList(c.eduProgress['log']).length, 1);
    expect(jsNum(c.eduProgress['baseEdu']), 50);
  });

  test('checkList 十项、step 编号与 JS 一致', () {
    final c = cardOf(<String, Object?>{
      'card': <String, Object?>{
        'characterName': '张三',
        'playerName': '李四',
        'age': 30,
        'basicInfo': <String, Object?>{'age': 30},
        'attributes': <String, Object?>{
          'str': 60,
          'con': 60,
          'siz': 60,
          'dex': 60,
          'app': 60,
          'int': 60,
          'pow': 60,
          'edu': 60,
          'luck': 60,
        },
      },
    });
    final list = checkList(c);
    expect(list.length, 10);
    expect(list.map((e) => e['label']).toList(), <String>[
      '角色姓名已填写',
      '玩家名称已填写',
      '年龄合法',
      '属性合法（15-90 且为 5 的倍数）',
      '已选择职业',
      '职业限定技能选择完成',
      '信用评级在职业范围内',
      '职业技能点未超额',
      '兴趣技能点未超额',
      '技能未超过上限',
    ]);
    expect(list.map((e) => e['step']).toList(), <int>[
      0,
      0,
      0,
      1,
      2,
      2,
      3,
      4,
      4,
      4,
    ]);
  });
}
