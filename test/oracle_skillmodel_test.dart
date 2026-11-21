// oracle 等价性测试：技能实例模型（core/skillmodel.js）
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/skillmodel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/oracle.dart';

Map<String, Object?> _map(Object? v) => Map<String, Object?>.from(v as Map);

void main() {
  OracleFixture.load('skillmodel.json').run(<String, Object? Function(Object?)>{
    'baseValue': (args) {
      final a = args as List;
      return baseValue(
        cardOf(<String, Object?>{'card': a[0]}),
        '${a[1]}',
        '${a[2]}',
      );
    },
    'baseValueSub': (args) {
      final a = args as List;
      return baseValue(
        cardOf(<String, Object?>{'card': a[0]}),
        '${a[1]}',
        '${a[2]}',
      );
    },
    'displayName': (args) {
      final a = args as List;
      return displayName('${a[0]}', '${a[1]}');
    },
    'categoryOf': (args) => categoryOf('${(args as List)[0]}'),
    'keyOf': (args) {
      final a = args as List;
      return keyOf('${a[0]}', '${a[1]}');
    },
    'keyOfSub': (args) {
      final a = args as List;
      return keyOf('${a[0]}', '${a[1]}');
    },
    'makeSkill': (args) {
      final a = args as List;
      return makeSkill(cardOf(<String, Object?>{'card': a[0]}), '${a[1]}', '');
    },
    'makeSkillCustom': (args) {
      final a = args as List;
      return makeSkill(
        cardOf(<String, Object?>{'card': a[0]}),
        'custom',
        '',
        _map(a[1]),
      );
    },
    'recompute': (args) => recompute(_map((args as List)[0])),
    'syncSkills': (args) => syncSkills(cardOf(args)),
    'canAdd': (args) {
      final m = args as Map;
      return canAdd(
        cardOf(args),
        _map(m['skill']),
        '${m['field']}',
        (m['delta'] as num).toInt(),
      );
    },
    'applyPoint': (args) {
      final m = args as Map;
      return applyPoint(
        cardOf(args),
        _map(m['skill']),
        '${m['field']}',
        (m['delta'] as num).toInt(),
      );
    },
    'stats': (args) => stats(cardOf(args)),
    'oscSkill': (args) =>
        isOccSkill(cardOf(args), _map((args as Map)['skill'])),
    'capOf': (args) => capOf(cardOf(args), _map((args as Map)['skill'])),
  });

  test('技能实例 key 规则：组技能带 ::专攻，自定义为 custom::<name>', () {
    expect(keyOf('spot_hidden', ''), 'spot_hidden');
    expect(keyOf('fighting', '斗殴'), 'fighting::斗殴');
    expect(keyOf('custom', ''), 'custom');
  });

  test('recompute = base + growth + occ + int', () {
    expect(
      recompute(<String, Object?>{
        'base': 25,
        'growth': 5,
        'occ': 30,
        'int': 10,
      }),
      70,
    );
    expect(recompute(<String, Object?>{}), 0);
  });

  test('克苏鲁神话 / 信用评级 在车卡期不能加点，只能走成长', () {
    final card = cardOf(<String, Object?>{
      'card': <String, Object?>{'skills': <Object?>[]},
    });
    for (final id in <String>['cthulhu', 'credit']) {
      final s = <String, Object?>{
        'key': id,
        'id': id,
        'name': id,
        'base': 0,
        'growth': 0,
        'occ': 0,
        'int': 0,
        'total': 0,
        'custom': false,
        'desc': '',
      };
      expect(jsTruthy(canAdd(card, s, 'occ', 5)['ok']), isFalse);
      expect(jsTruthy(canAdd(card, s, 'growth', 5)['ok']), isTrue);
    }
  });

  test('syncSkills 不丢自定义技能与已有加点', () {
    final card = cardOf(<String, Object?>{
      'card': <String, Object?>{
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
        'skills': <Object?>[
          <String, Object?>{
            'key': 'spot_hidden',
            'id': 'spot_hidden',
            'name': '侦查',
            'sub': '',
            'base': 25,
            'growth': 5,
            'occ': 20,
            'int': 0,
            'total': 50,
            'custom': false,
            'desc': '',
          },
          <String, Object?>{
            'key': 'custom::我的技能',
            'id': 'custom',
            'name': '我的技能',
            'sub': '',
            'base': 10,
            'growth': 0,
            'occ': 0,
            'int': 5,
            'total': 15,
            'custom': true,
            'desc': 'x',
          },
        ],
      },
    });
    final list = syncSkills(card);
    final spot = list.map(asMap).firstWhere((s) => s['key'] == 'spot_hidden');
    expect(spot['occ'], 20);
    expect(spot['growth'], 5);
    expect(list.map(asMap).any((s) => s['key'] == 'custom::我的技能'), isTrue);
  });
}
