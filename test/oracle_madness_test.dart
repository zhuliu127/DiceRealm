// oracle 等价性测试：疯狂（core/madness.js）
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/madness.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/oracle.dart';

void main() {
  OracleFixture.load('madness.json').run(<String, Object? Function(Object?)>{
    'rollTable': (args) => rollTable(),
    'rollSummary': (args) => rollSummary(),
    'roll': (args) {
      final a = args as List;
      return roll(a[0], a[1] == true);
    },
    'backgroundText': (args) => backgroundText((args as List)[0] as String?),
    'lookup': (args) => lookup((args as List)[0]),
    'lookupPhobia': (args) {
      final a = args as List;
      return lookup(a[0], 'phobia');
    },
    'lookupMania': (args) {
      final a = args as List;
      return lookup(a[0], 'mania');
    },
    'poolSize': (args) => poolSize('phobia'),
    'poolSizeMania': (args) => poolSize('mania'),
    'labelOf': (args) =>
        <String>['phobia', 'mania', 'bout', 'x'].map(labelOf).toList(),
    'size': (args) => size,
    'phobias': (args) => phobias().take(3).toList(),
    'manias': (args) => manias().take(3).toList(),
    'make': (args) {
      final a = args as List;
      return make(
        a[0],
        a[1] == null ? null : Map<String, Object?>.from(a[1] as Map),
        a[2] == true,
        (a[3] as num?)?.toInt(),
      );
    },
    'parseBackground': (args) => parseBackground((args as List)[0]),
    'fromBackground': (args) => fromBackground(cardOf(args)),
    'fromBackgroundIdem': (args) {
      final c = cardOf(args);
      fromBackground(c); // 第一遍：补进数组
      return fromBackground(c); // 第二遍：必须新增 0 条（幂等）
    },
    'advance': (args) {
      final m = args as Map;
      return advance(cardOf(args), m['n']);
    },
    'summary': (args) => summary(cardOf(args)),
    'fading': (args) {
      final m = args as Map;
      return fading(cardOf(args), m['within']);
    },
    'hasName': (args) {
      final m = args as Map;
      return hasName(cardOf(args), m['type'], m['name']);
    },
    'add': (args) {
      final m = args as Map;
      return add(cardOf(args), Map<String, Object?>.from(m['entry'] as Map));
    },
    'remove': (args) {
      final m = args as Map;
      return remove(cardOf(args), m['id']);
    },
    'fromPicked': (args) => fromPicked(cardOf(args), (args as Map)['picked']),
    'clear': (args) {
      final c = cardOf(args);
      clear(c);
      return list(c);
    },
  });

  test('两张疯狂表各 10 条，9/10 条指向 100 条子表', () {
    expect(boutTable.length, 10);
    expect(summaryTable.length, 10);
    expect(boutTable[8]['link'], 'phobia');
    expect(boutTable[9]['link'], 'mania');
    expect(summaryTable[8]['link'], 'phobia');
    expect(summaryTable[9]['link'], 'mania');
    for (var i = 0; i < 8; i++) {
      expect(boutTable[i].containsKey('link'), isFalse);
      expect(summaryTable[i].containsKey('link'), isFalse);
    }
  });

  test('症状池各 100 条，合计 200', () {
    expect(poolSize('phobia'), 100);
    expect(poolSize('mania'), 100);
    expect(size, 200);
  });

  test('永久疯狂不会被 advance 清掉，只能手动删', () {
    final c = cardOf(<String, Object?>{
      'card': <String, Object?>{
        'madness': <Object?>[
          <String, Object?>{
            'id': 'p',
            'type': 'phobia',
            'name': '永久',
            'permanent': true,
            'rounds': 0,
          },
          <String, Object?>{
            'id': 't',
            'type': 'mania',
            'name': '临时',
            'permanent': false,
            'rounds': 2,
          },
        ],
      },
    });
    final faded = advance(c, 5);
    expect(faded.length, 1);
    expect(asMap(faded.first)['id'], 't');
    expect(list(c).length, 1);
  });

  test('advance 的轮数下限为 1（n=0 / 非数字都按 1 算）', () {
    Map<String, Object?> entry() => <String, Object?>{
      'id': 'x',
      'type': 'phobia',
      'name': 'x',
      'permanent': false,
      'rounds': 3,
    };
    for (final n in <Object?>[0, null, 'abc', -5]) {
      final c = cardOf(<String, Object?>{
        'card': <String, Object?>{
          'madness': <Object?>[entry()],
        },
      });
      advance(c, n);
      expect(jsNum(asMap(list(c).first)['rounds']), 2, reason: 'n=$n 应按 1 处理');
    }
  });

  test('summary 格式：【类型】名字（尾注），多条用全角空格分隔', () {
    final c = cardOf(<String, Object?>{
      'card': <String, Object?>{
        'madness': <Object?>[
          <String, Object?>{
            'type': 'phobia',
            'name': '幽闭恐惧症',
            'permanent': true,
            'bg': true,
          },
          <String, Object?>{
            'type': 'mania',
            'name': '纵火狂',
            'permanent': false,
            'rounds': 3,
          },
          <String, Object?>{'type': 'bout', 'name': '失忆', 'permanent': true},
        ],
      },
    });
    expect(summary(c), '【恐惧症】幽闭恐惧症（背景症状）　【狂躁症】纵火狂（3 轮）　【疯狂发作】失忆（永久）');
  });

  test('背景文本解析只认症状表里存在的名字，重复行去重', () {
    final found = parseBackground('【恐惧症】幽闭恐惧症：怕黑\n【恐惧症】幽闭恐惧症：重复\n我瞎写的：不是症状');
    expect(found.length, 1);
    expect(asMap(asMap(found.first)['src'])['name'], '幽闭恐惧症');
  });
}
