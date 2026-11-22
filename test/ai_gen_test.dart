// ============================================================
// ai_gen_test.dart — AI 车卡「纯函数」与旧版 ai.js 的等价性
//
// fixture：test/fixtures/ai_gen.json（node tool/oracle/dump_ai_fixtures.js）
//
// 三条不变式：
//   1. 同一描述 + 同样的上限 → **同一个提示词字符串**（逐字节）；
//   2. 同一份模型 JSON → **同一个 profile**（逐字段）；
//   3. parseJson 的失败方式稳定 —— 上层靠「截断 vs 格式错」决定要不要重试。
// ============================================================

import 'package:dice_realm/domain/ai_caps.dart';
import 'package:dice_realm/domain/ai_gen.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/oracle.dart';

/// v2.45.0（含）及之前 buildPrompt 里 name 字段的旧说明（旧版 ai.js 口径）。
/// v2.46.0 起改为「玩家指定姓名优先 + 模型自拟多样」的新口径（见下方 ★ 测试）；
/// fixture（逐字节 oracle）的 buildPrompt 比对会把新行换回这行旧值后照常进行 ——
/// 除姓名策略行外，提示词其余部分仍必须与旧版逐字节一致。
const String kLegacyAiNameLine =
    '  "name": "符合该设定文化的完整人名。每次都必须生成与示例不同的人名，不得重复使用同一姓名；'
    '下面只是格式示范，禁止照抄：林砚秋 / 陆知微 / 顾长庚 / 温静姝 / 裴允行",';

/// 从提示词里抠出 name 字段那一行（用于新旧口径拼接比对）
String nameLineOf(String prompt) => prompt
    .split('\n')
    .firstWhere((l) => l.startsWith('  "name": '));

void main() {
  final fixture = OracleFixture.load('ai_gen.json');

  group('ai.js → ai_gen.dart 等价性', () {
    fixture.run(<String, Object? Function(Object? args)>{
      'buildPrompt': (args) {
        final a = (args as Map).cast<String, Object?>();
        final caps = a['caps'] is Map ? AiCaps.fromMap(a['caps'] as Map) : null;
        final p = buildPrompt(jsStr(a['desc']), caps: caps);
        // v2.46.0 有意偏离旧版 ai.js：name 字段说明重写为「玩家指定优先」。
        // 比对前把新行换回旧行 —— 除姓名策略这一行外，仍要求与旧版逐字节一致。
        return p
            .split('\n')
            .map((l) => l.startsWith('  "name": ') ? kLegacyAiNameLine : l)
            .join('\n');
      },
      'toProfile': (args) {
        final a = (args as Map).cast<String, Object?>();
        return toProfile(a['raw']);
      },
      'parseJson': (args) {
        final a = (args as Map).cast<String, Object?>();
        return parseJson(a['text']);
      },
    });
  });

  group('parseJson 的失败方式必须稳定（可读 + 分类明确）', () {
    test('fixture 里所有「原码会抛异常」的样例，Dart 也抛且同属一类', () {
      final bad = fixture.cases.where((c) => c['error'] != null).toList();
      expect(bad, isNotEmpty, reason: 'fixture 里应该有失败样例');

      for (final c in bad) {
        final jsMsg = c['error'] as String;
        final text = jsStr((c['args'] as Map)['text']);
        // 前 10 个字足以区分三类（格式错 / 不完整 / 不是 JSON）
        final prefix = jsMsg.length > 10 ? jsMsg.substring(0, 10) : jsMsg;

        Object? thrown;
        try {
          parseJson(text);
        } catch (e) {
          thrown = e;
        }
        expect(
          thrown,
          isA<AiGenException>(),
          reason: '${c['name']}：应该抛 AiGenException',
        );
        final msg = (thrown as AiGenException).message;
        expect(msg, startsWith(prefix), reason: '${c['name']}：消息类别应与旧版一致');
      }
    });

    test('尾随逗号能救回来（旧版的第三条抢救路径）', () {
      final v = parseJson('{"a":1,}');
      expect(v, isA<Map>());
      expect((v as Map)['a'], 1);
    });

    test('```json 围栏 + 前后废话都能救', () {
      expect((parseJson('```json\n{"a":1}\n```') as Map)['a'], 1);
      expect((parseJson('好的：\n{"a":1}\n希望你喜欢') as Map)['a'], 1);
    });

    test('截断（不闭合）→ 明确说是「不完整」，不是「格式有误」', () {
      expect(
        () => parseJson('{"a":1'),
        throwsA(
          isA<AiGenException>().having(
            (e) => e.message,
            'message',
            contains('不完整'),
          ),
        ),
      );
    });

    test('返回数组 / null / 标量时不抛，原样返回（由 toProfile 兜底）', () {
      expect(parseJson('[1,2,3]'), isA<List<Object?>>());
      expect(parseJson('null'), isNull);
      expect(parseJson('42'), 42);
    });

    test('字符串里的花括号不会被当成结构（配平必须跳过字符串）', () {
      final v = parseJson('前言 {"s":"a}b{c"} 尾巴');
      expect((v as Map)['s'], 'a}b{c');
    });
  });

  group('buildPrompt 的可读性要求（用户能看到的都在这段提示词里）', () {
    test('包含玩家原话、世界设定清单、职业清单、数值区间要求', () {
      final p = buildPrompt('民国时期的私家侦探');
      expect(p, contains('民国时期的私家侦探'));
      expect(p, contains('【第一步】'));
      expect(p, contains('【第二步】'));
      expect(p, contains('【第三步】'));
      expect(p, contains('中国 · 当代')); // 世界设定清单里的一个标签
      expect(p, contains('医生')); // 职业清单里的一个名字
      expect(p, contains('str/con/siz/dex/app/int/pow 取值 20-90'));
    });

    test('没设上限时不含「硬性上限」段；设了就逐条写进去', () {
      const noCap = AiCaps();
      expect(buildPrompt('x', caps: noCap), isNot(contains('本次的硬性上限')));

      const cap = AiCaps(attrCap: 420, withLuck: false, occCap: 70, intCap: 60);
      final p = buildPrompt('x', caps: cap);
      expect(p, contains('本次的硬性上限'));
      expect(p, contains('八项（不含幸运）相加不得超过 420'));
      expect(p, contains('每项本职技能的最终值不得超过 70 点'));
      expect(p, contains('每项非本职（兴趣）技能的最终值不得超过 60 点'));
    });

    test('提示词里必须明确「不许人人写一条疯狂症状」（v2.11.4 的产品决定）', () {
      expect(buildPrompt('x'), contains('不要人人都写一条'));
    });

    // ★ v2.46.0 产品行为真变：姓名策略从「本地池纠偏」改回「由模型生成」，
    //   并把「玩家指定优先」写成最高优先级条款。fixture 的逐字节比对（上面
    //   第一道网）把 name 行换回旧值后照常运行，保证除该行外零漂移；这里钉
    //   住的是新口径的三层语义：指定优先（显式最高优先级 + 原样使用）、
    //   多样性（每次不同）、样例禁抄。旧口径里的「不得重复」并入第 2 层，
    //   必须排在「玩家指定优先」之后 —— 顺序颠倒说明优先级又压错了。
    test('★ 姓名约束（玩家指定优先 > 模型自拟多样 / 样例禁抄）', () {
      final String p = buildPrompt('x');
      // 第一层：玩家指定姓名 → 显式最高优先级 + 原样使用
      expect(p, contains('★（最高优先）'),
          reason: '★ 「玩家指定优先」必须带显式优先级标记');
      expect(p, contains('如果玩家的描述里明确指定了角色姓名'),
          reason: '★ 必须显式说明「玩家描述里指定了姓名」的情形');
      expect(p, contains('必须原样使用玩家指定的姓名'),
          reason: '★ 玩家指定的姓名必须原样使用（不得被本地改掉）');
      expect(p, contains('不得改写、不得谐音、不得另起新名字'),
          reason: '★ 必须禁止改写 / 谐音 / 另起名');
      // 第二层：未指定时自行起名 → 多样性约束（保留旧口径的用词，但已并入
      // 「仅当玩家没有指定姓名时」的从句，不再压过指定优先）
      expect(p, contains('仅当玩家没有指定姓名时，才自行起一个符合该设定文化的完整人名'),
          reason: '★ 多样性约束必须明确限定在「未指定姓名」的情形');
      expect(p, contains('每次都必须生成与示例不同的人名'),
          reason: '★ 「每次不同」必须是对模型的显式要求');
      expect(p, contains('不得重复使用同一姓名'),
          reason: '★ 「不得重复」必须逐字出现');
      // 优先级顺序：指定优先必须出现在多样性约束之前
      expect(p.indexOf('★（最高优先）'),
          lessThan(p.indexOf('不得重复使用同一姓名')),
          reason: '★ 「玩家指定优先」必须排在「不得重复」之前，否则会被它压过');
      // 样例：5 个格式示范 + 禁止照抄
      expect(p, contains('下面只是格式示范，禁止照抄'),
          reason: '★ 样例必须标明禁抄，否则模型会直接抄样例名');
      for (final String sample in <String>[
        '林砚秋',
        '陆知微',
        '顾长庚',
        '温静姝',
        '裴允行',
      ]) {
        expect(p, contains(sample), reason: '★ 名字池样例「$sample」缺失');
      }
    });

    test('★ 玩家指定姓名的描述（QA 案例：华强买瓜的刘华强）也带同样的约束', () {
      final String p = buildPrompt('车一个华强买瓜里面的刘华强');
      expect(p, contains('车一个华强买瓜里面的刘华强'));
      expect(p, contains('★（最高优先）'),
          reason: '★ 玩家指定了姓名时，优先级标记必须在提示词里');
      expect(p, contains('必须原样使用玩家指定的姓名'),
          reason: '★ 模型必须把「刘华强」原样当作角色姓名，不得另起「岳振山」');
    });

    test('★ JSON schema 的字段名一个都不能少（模型是照着抄结构的）', () {
      final String p = buildPrompt('x');
      for (final String key in <String>[
        '"setting"',
        '"name"',
        '"gender"',
        '"age"',
        '"residence"',
        '"birthplace"',
        '"occupationName"',
        '"occupationSkills"',
        '"attributes"',
        '"str": 0',
        '"edu": 0',
        '"luck": 0',
        '"background"',
        '"description"',
        '"ideology"',
        '"significantPeople"',
        '"meaningfulPlaces"',
        '"treasuredPossessions"',
        '"traits"',
        '"wounds"',
        '"phobias"',
        '"history"',
      ]) {
        expect(p, contains(key), reason: '★ schema 字段 $key 必须逐字出现');
      }
    });
  });

  // ============================================================
  // 姓名兜底（v2.46.0）：本地姓名池只用于「AI 结果落地时名字为空」的兜底；
  // 对模型给的非空姓名不再做任何纠偏（ensureFreshInvestigatorName 已删除，
  // 相应的纠偏用例随被删除行为一起移除）。多样性改由提示词约束。
  // ============================================================
  group('姓名兜底（本地池，仅空名时使用）', () {
    final RegExp cjk24 = RegExp(r'^[\u4e00-\u9fa5]{2,4}$');

    test('★ randomInvestigatorName：连续 10 次 distinct ≥ 8 / 全 2-4 汉字', () {
      final List<String> names = <String>[
        for (int i = 0; i < 10; i++) randomInvestigatorName(),
      ];
      expect(names.toSet().length, greaterThanOrEqualTo(8),
          reason: '同一轮内名字袋不许重复取用：$names');
      for (final String n in names) {
        expect(cjk24.hasMatch(n), isTrue, reason: '「$n」必须是 2-4 个汉字');
        // 历史回归钉子：v2.39.0 之前模型口头禅「沈砚清」泛滥，
        // 池子里也不存在这个组合 —— 万一出现说明池子被改坏了。
        expect(n, isNot('沈砚清'), reason: '★ 已知的模型口头禅名字绝不允许再出现');
      }
    });
  });

  group('toProfile 的清洗原则：能给空就给空，绝不给错值', () {
    test('属性只保留能解析成整数的项；一项都不剩就整块丢弃', () {
      final p = toProfile(<String, Object?>{
        'attributes': <String, Object?>{'str': '55', 'dex': 'abc'},
      });
      expect(p['attributes'], <String, Object?>{'str': 55});

      final none = toProfile(<String, Object?>{
        'attributes': <String, Object?>{'str': 'x'},
      });
      expect(none['attributes'], isNull);
    });

    test('非法输入（null / 字符串 / 数组）→ 空 profile，不抛', () {
      for (final raw in <Object?>[
        null,
        'oops',
        42,
        <Object?>[1, 2],
      ]) {
        final p = toProfile(raw);
        expect(p['name'], '');
        expect(p['occupationName'], '');
        expect(p['attributes'], isNull);
        expect(p['background'], isNull);
        expect(p['fromAI'], isTrue);
      }
    });

    test('年龄越界归 0（表示「交给随机」）；字符串数字能救', () {
      expect(toProfile(<String, Object?>{'age': 200})['age'], 0);
      expect(toProfile(<String, Object?>{'age': 14})['age'], 0);
      expect(toProfile(<String, Object?>{'age': '33'})['age'], 33);
      expect(toProfile(<String, Object?>{'age': 75})['age'], 75);
    });

    test('背景文本单行化 + 240 字截断', () {
      final long = toProfile(<String, Object?>{
        'background': <String, Object?>{
          'description': '第一行\n\n\n第二行',
          'ideology': '字' * 400,
        },
      });
      final bg = long['background'] as Map;
      expect(bg['description'], '第一行 第二行');
      expect((bg['ideology'] as String).length, 240);
    });

    test('occupationSkills 去空、去重前截断到 8 项；非数组整块丢弃', () {
      final p = toProfile(<String, Object?>{
        'occupationSkills': <Object?>['侦查', '  ', '聆听', '侦查'],
      });
      expect(p['occupationSkills'], <Object?>['侦查', '聆听', '侦查']);

      expect(
        toProfile(<String, Object?>{
          'occupationSkills': 'x',
        })['occupationSkills'],
        isNull,
      );
    });

    test('fromAI 恒为 true（规则层据此走宽松属性口径 + 跳过背景疯狂掷骰）', () {
      expect(toProfile(<String, Object?>{})['fromAI'], isTrue);
      expect(toProfile(null)['fromAI'], isTrue);
    });
  });
}
