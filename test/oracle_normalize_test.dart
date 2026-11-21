// oracle 等价性测试：老存档迁移（core/store.js#normalize）
import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/normalize.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/oracle.dart';

void main() {
  final fx = OracleFixture.load('normalize.json');

  fx.run(<String, Object? Function(Object?)>{
    'normalize': (args) => normalize(cardOf(args)).toJson(),
  });

  // ---- 幂等性（审计 §D.6 的硬要求）：normalize(normalize(x)) == normalize(x) ----
  test('normalize 幂等：25 张老卡第二遍跑不产生任何变化', () {
    for (final c in fx.cases) {
      final rng1 = Lcg((c['seed'] as num).toInt());
      setRng(rng1.call);
      setClock(() => oracleNowMs);
      final card = cardOf(c['args']);
      normalize(card);
      final once = _snapshot(card);

      // 第二遍：换一个 seed（normalize 里 newCharacter 会消耗随机数），
      // 结果必须完全一致 —— 否则说明有字段被反复「迁移」。
      final rng2 = Lcg((c['seed'] as num).toInt() + 7);
      setRng(rng2.call);
      normalize(card);
      final twice = _snapshot(card);
      expect(twice, once, reason: '${c['name']} 第二遍 normalize 产生了变化');
    }
  });

  group('逐项迁移规则', () {
    test('旧 skillCap 拆成本职 / 兴趣两类', () {
      final c = cardOf(<String, Object?>{
        'card': <String, Object?>{'skillCap': 80},
      });
      normalize(c);
      expect(jsNum(c.raw['skillCapOcc']), 80);
      expect(jsNum(c.raw['skillCapInterest']), 80);
    });

    test('已有分项上限时不覆盖', () {
      final c = cardOf(<String, Object?>{
        'card': <String, Object?>{
          'skillCap': 80,
          'skillCapOcc': 90,
          'skillCapInterest': 70,
        },
      });
      normalize(c);
      expect(jsNum(c.raw['skillCapOcc']), 90);
      expect(jsNum(c.raw['skillCapInterest']), 70);
    });

    test('购点上限缺失补 480', () {
      final c = cardOf(<String, Object?>{
        'card': <String, Object?>{'pbCap': null},
      });
      normalize(c);
      expect(jsNum(c.raw['pbCap']), 480);
    });

    test('教育进步只有 log 时 bonus = Σgain、done = log.length', () {
      final c = cardOf(<String, Object?>{
        'card': <String, Object?>{
          'eduProgress': <String, Object?>{
            'log': <Object?>[
              <String, Object?>{'before': 50, 'gain': 6},
              <String, Object?>{'before': 56, 'gain': 3},
            ],
          },
        },
      });
      normalize(c);
      expect(jsNum(c.eduProgress['bonus']), 9);
      expect(jsNum(c.eduProgress['done']), 2);
    });

    test('天命 n 夹到 2-10，picked 越界归 -1，rolled 需有 options', () {
      final c = cardOf(<String, Object?>{
        'card': <String, Object?>{
          'fate': <String, Object?>{
            'n': 99,
            'rolled': true,
            'options': <Object?>[],
            'picked': 3,
          },
        },
      });
      normalize(c);
      expect(jsNum(c.fate['n']), 5);
      expect(jsNum(c.fate['picked']), -1);
      expect(c.fate['rolled'], isFalse);
    });

    test('mental 字符串 → 数组；空 → [正常]', () {
      final a = cardOf(<String, Object?>{
        'card': <String, Object?>{
          'status': <String, Object?>{'mental': '临时疯狂'},
        },
      });
      normalize(a);
      expect(a.status['mental'], <Object?>['临时疯狂']);

      final b = cardOf(<String, Object?>{
        'card': <String, Object?>{
          'status': <String, Object?>{'mental': ''},
        },
      });
      normalize(b);
      expect(b.status['mental'], <Object?>['正常']);
    });

    test('mental 含「永久疯狂」时互斥只留它一项', () {
      final c = cardOf(<String, Object?>{
        'card': <String, Object?>{
          'status': <String, Object?>{
            'mental': <Object?>['正常', '永久疯狂', '临时疯狂'],
          },
        },
      });
      normalize(c);
      expect(c.status['mental'], <Object?>['永久疯狂']);
    });

    test('body=濒死 → body=重伤 + dying=true', () {
      final c = cardOf(<String, Object?>{
        'card': <String, Object?>{
          'status': <String, Object?>{
            'body': '濒死',
            'currentHP': 0,
            'maxHP': 12,
          },
        },
      });
      normalize(c);
      expect(c.status['body'], '重伤');
      expect(c.status['dying'], isTrue);
    });

    test('body=昏迷 → unconscious=true + body 按 HP 归位', () {
      Map<String, Object?> run(int hp, int max) {
        final c = cardOf(<String, Object?>{
          'card': <String, Object?>{
            'status': <String, Object?>{
              'body': '昏迷',
              'currentHP': hp,
              'maxHP': max,
            },
          },
        });
        normalize(c);
        return <String, Object?>{
          'body': c.status['body'],
          'un': c.status['unconscious'],
        };
      }

      expect(run(12, 12), <String, Object?>{'body': '正常', 'un': true});
      expect(run(6, 12), <String, Object?>{'body': '重伤', 'un': true});
      expect(run(5, 12), <String, Object?>{'body': '轻伤', 'un': true});
      expect(run(0, 0), <String, Object?>{'body': '轻伤', 'un': true});
    });

    test('dying / unconscious 收敛为布尔', () {
      final c = cardOf(<String, Object?>{
        'card': <String, Object?>{
          'status': <String, Object?>{'dying': 'yes', 'unconscious': 1},
        },
      });
      normalize(c);
      expect(c.status['dying'], isTrue);
      expect(c.status['unconscious'], isTrue);
    });

    test('背景症状文本补进 madness（bg=true、永久）', () {
      final c = cardOf(<String, Object?>{
        'card': <String, Object?>{
          'background': <String, Object?>{'phobias': '【恐惧症】幽闭恐惧症：怕黑'},
        },
      });
      normalize(c);
      final list = asList(c.raw['madness']).map(asMap).toList();
      expect(list.length, 1);
      expect(list.first['type'], 'phobia');
      expect(list.first['name'], '幽闭恐惧症');
      expect(list.first['bg'], isTrue);
      expect(list.first['permanent'], isTrue);
    });

    test('持有背景 / 永久症状时「疯狂症状」与「正常」互斥', () {
      final c = cardOf(<String, Object?>{
        'card': <String, Object?>{
          'status': <String, Object?>{
            'mental': <Object?>['正常'],
          },
          'madness': <Object?>[
            <String, Object?>{
              'id': 'm',
              'type': 'mania',
              'name': 'y',
              'permanent': true,
              'rounds': 0,
              'at': 1,
            },
          ],
        },
      });
      normalize(c);
      expect(asList(c.status['mental']).contains('正常'), isFalse);
      expect(asList(c.status['mental']).contains('疯狂症状'), isTrue);
    });

    test('缺字段一律用 newCharacter 补齐（老卡不崩）', () {
      final c = cardOf(<String, Object?>{
        'card': <String, Object?>{'characterName': '老卡'},
      });
      normalize(c);
      for (final k in <String>[
        'id',
        'userId',
        'ruleSystemId',
        'basicInfo',
        'attributes',
        'status',
        'assets',
        'background',
        'mythos',
        'skills',
        'weapons',
        'armors',
        'vehicles',
        'items',
        'history',
        'companions',
        'changeLog',
        'madness',
        'occupationPicks',
      ]) {
        expect(c.raw.containsKey(k), isTrue, reason: '缺字段 $k');
        expect(c.raw[k], isNotNull, reason: '$k 不应为 null');
      }
      expect(c.raw['version'], 'v1.0');
      expect(jsNum(c.raw['sanLoss']), 0);
    });

    test('数组字段被写成非数组时归位为 []', () {
      final c = cardOf(<String, Object?>{
        'card': <String, Object?>{
          'skills': 'oops',
          'weapons': null,
          'items': 3,
        },
      });
      normalize(c);
      expect(c.raw['skills'], isEmpty);
      expect(c.raw['weapons'], isEmpty);
      expect(c.raw['items'], isEmpty);
    });
  });
}

/// 只保留结构（用于幂等比较；忽略 normalize 每次生成的随机 id 之外的一切）
String _snapshot(Character c) => c.toJson().toString();
