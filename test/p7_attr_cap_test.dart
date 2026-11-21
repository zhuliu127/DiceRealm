// ============================================================
// p7_attr_cap_test.dart — P7-A 真机反馈：压缩后属性必须「规则合法」
//
// 覆盖：5 倍数网格压缩的 6 条不变式、旧版算法隔离、attrsFromAi 闸门、
//       AI 卡 / 5 张随机卡 / 彩蛋卡三条路径都吃到新上限。
// ============================================================

import 'package:dice_realm/domain/ai_caps.dart';
import 'package:dice_realm/domain/character.dart'
    show Character, uidDeterministic;
import 'package:dice_realm/domain/easter_egg.dart' as egg;
import 'package:dice_realm/domain/js_compat.dart'
    show
        JsClock,
        JsRng,
        jsNum,
        nowClock,
        nowRng,
        setClock,
        setRng;
import 'package:dice_realm/domain/preset_gen.dart' as preset;
import 'package:dice_realm/domain/rules_coc7.dart' show genMax, genMin, genStep;
import 'package:flutter_test/flutter_test.dart';

import 'support/oracle.dart' show Lcg, oracleNowMs;

const List<String> _keys8 = <String>[
  'str',
  'con',
  'siz',
  'dex',
  'app',
  'int',
  'pow',
  'edu',
];
const List<String> _keys9 = <String>[..._keys8, 'luck'];

/// 一组「相对高低明显」的原始属性（9 项，含 >90 的越界值）。
Map<String, Object?> _profile() {
  return <String, Object?>{
    'attributes': <String, Object?>{
      'str': 90,
      'con': 85,
      'siz': 80,
      'dex': 75,
      'app': 70,
      'int': 95,
      'pow': 60,
      'edu': 55,
      'luck': 99,
    },
  };
}

Map<String, Object?> _attrs(Map<String, Object?> p) =>
    (p['attributes'] as Map).cast<String, Object?>();

int _sum(Map<String, Object?> a, {required bool withLuck}) {
  var s = 0;
  for (final k in withLuck ? _keys9 : _keys8) {
    s += jsNum(a[k]);
  }
  return s;
}

void _expectLegal(
  Map<String, Object?> a, {
  required bool withLuck,
  required int cap,
  required String label,
}) {
  final keys = withLuck ? _keys9 : _keys8;
  for (final k in keys) {
    final v = jsNum(a[k]);
    expect(v % genStep, 0, reason: '$label：$k=$v 不是 $genStep 的倍数');
    expect(v, inInclusiveRange(genMin, genMax),
        reason: '$label：$k=$v 超出规则区间 $genMin-$genMax');
  }
  final total = _sum(a, withLuck: withLuck);
  // 物理下界：低于 keys.length * genMin 时，I3（规则区间）优先于 I4。
  final floorSum = keys.length * genMin;
  if (cap >= floorSum) {
    expect(total, lessThanOrEqualTo(cap),
        reason: '$label：总和 $total 反弹超过上限 $cap');
  } else {
    expect(total, floorSum,
        reason: '$label：上限低于物理下界时应压到下界 $floorSum，实际 $total');
  }
}

void _expectOrderKept(
  Map<String, Object?> before,
  Map<String, Object?> after, {
  required bool withLuck,
  required String label,
}) {
  final keys = (withLuck ? _keys9 : _keys8).toList()
    ..sort((x, y) {
      final c = jsNum(before[y]).compareTo(jsNum(before[x]));
      return c != 0 ? c : _keys9.indexOf(x) - _keys9.indexOf(y);
    });
  for (var i = 0; i + 1 < keys.length; i++) {
    expect(
      jsNum(after[keys[i]]),
      greaterThanOrEqualTo(jsNum(after[keys[i + 1]])),
      reason: '$label：${keys[i]}=${after[keys[i]]} 反低于 '
          '${keys[i + 1]}=${after[keys[i + 1]]}，相对高低乱了',
    );
  }
}

void main() {
  late JsRng savedRng;
  late JsClock savedClock;
  late bool savedUid;
  late bool savedLegacy;

  setUp(() {
    savedRng = nowRng;
    savedClock = nowClock;
    savedUid = uidDeterministic;
    savedLegacy = legacyAttrCapForOracle;
    legacyAttrCapForOracle = false; // 生产算法
    setRng(Lcg(20261110).call);
    setClock(() => oracleNowMs);
    uidDeterministic = true;
  });
  tearDown(() {
    setRng(savedRng);
    setClock(savedClock);
    uidDeterministic = savedUid;
    legacyAttrCapForOracle = savedLegacy;
  });

  group('A · 5 倍数网格压缩（生产算法）', () {
    for (final cap in <int>[400, 460, 300, 403]) {
      test('含幸运 cap=$cap → 逐项合法 / 不超限 / 相对高低不乱', () {
        final p = _profile();
        final before = <String, Object?>{..._attrs(p)};
        final moved = applyAttrCap(p, AiCaps(attrCap: cap, withLuck: true));
        expect(moved, isTrue);
        final after = _attrs(p);
        _expectLegal(after, withLuck: true, cap: cap, label: 'cap=$cap');
        _expectOrderKept(before, after, withLuck: true, label: 'cap=$cap');
      });
    }

    test('上限不是 5 的倍数（403）→ 总和仍 ≤ 403，且不因取整反弹', () {
      final p = _profile();
      applyAttrCap(p, const AiCaps(attrCap: 403, withLuck: true));
      final after = _attrs(p);
      expect(_sum(after, withLuck: true), lessThanOrEqualTo(403));
      for (final k in _keys9) {
        expect(jsNum(after[k]) % genStep, 0);
      }
    });

    test('不含幸运（8 项口径）→ luck 原样不动，8 项合法且不超上限', () {
      final p = _profile();
      final before = <String, Object?>{..._attrs(p)};
      final luckBefore = jsNum(before['luck']);
      final moved =
          applyAttrCap(p, const AiCaps(attrCap: 380, withLuck: false));
      expect(moved, isTrue);
      final after = _attrs(p);
      expect(jsNum(after['luck']), luckBefore,
          reason: '不含幸运口径不该改 luck');
      _expectLegal(after, withLuck: false, cap: 380, label: 'noLuck');
      _expectOrderKept(before, after, withLuck: false, label: 'noLuck');
    });

    test('未超限 → 返回 false 且一个字节都不改（旧版语义 I1）', () {
      final p = <String, Object?>{
        'attributes': <String, Object?>{
          'str': 53, // 故意非 5 倍数：未超限也不许动
          'con': 47,
          'siz': 40,
          'dex': 40,
          'app': 40,
          'int': 40,
          'pow': 40,
          'edu': 40,
          'luck': 40,
        },
      };
      final before = <String, Object?>{..._attrs(p)};
      expect(applyAttrCap(p, const AiCaps(attrCap: 460, withLuck: true)),
          isFalse);
      expect(_attrs(p), before);
    });

    test('极小上限（低于物理下界 135）→ 全部压到 15，不产生非法属性', () {
      final p = _profile();
      final moved = applyAttrCap(p, const AiCaps(attrCap: 50, withLuck: true));
      expect(moved, isTrue);
      final after = _attrs(p);
      for (final k in _keys9) {
        expect(jsNum(after[k]), genMin, reason: '$k 应压到规则下界');
      }
      expect(_sum(after, withLuck: true), _keys9.length * genMin);
    });

    test('极小但可行的上限 140 → 总和 ≤ 140 且逐项合法', () {
      final p = _profile();
      applyAttrCap(p, const AiCaps(attrCap: 140, withLuck: true));
      _expectLegal(_attrs(p), withLuck: true, cap: 140, label: 'cap=140');
    });

    test('输入含 95 / 99 越界值 → 压缩输出仍落在 15-90', () {
      final p = _profile();
      applyAttrCap(p, const AiCaps(attrCap: 400, withLuck: true));
      final after = _attrs(p);
      for (final k in _keys9) {
        expect(jsNum(after[k]), inInclusiveRange(genMin, genMax),
            reason: '$k=${after[k]} 越界');
      }
    });
  });

  group('A · 旧版算法隔离（供 P3/P4 预言机）', () {
    test('开关为 true 时逐字走旧算法：输出可以不是 5 的倍数', () {
      legacyAttrCapForOracle = true;
      final p = _profile();
      final moved = applyAttrCap(p, const AiCaps(attrCap: 420, withLuck: true));
      expect(moved, isTrue);
      final after = _attrs(p);
      // 旧版等比压缩的特征：至少有一项不是 5 的倍数。
      expect(
        _keys9.any((k) => jsNum(after[k]) % genStep != 0),
        isTrue,
        reason: '旧算法本该产生非 5 倍数（冻结 fixture 的形态）',
      );
      expect(_sum(after, withLuck: true), lessThanOrEqualTo(420));
    });

    test('applyAttrCapLegacy 与开关路径结果一致', () {
      final a = _profile();
      final b = _profile();
      applyAttrCapLegacy(a, const AiCaps(attrCap: 380, withLuck: false));
      legacyAttrCapForOracle = true;
      applyAttrCap(b, const AiCaps(attrCap: 380, withLuck: false));
      expect(_attrs(a), _attrs(b));
    });
  });

  group('A · attrsFromAi 拒收非 5 倍数', () {
    const legal = <String, Object?>{
      'str': 55,
      'con': 60,
      'siz': 50,
      'dex': 65,
      'app': 70,
      'int': 80,
      'pow': 60,
      'edu': 75,
      'luck': 45,
    };

    test('全 5 倍数且在规则区间 → 收下', () {
      expect(preset.attrsFromAi(legal), isTrue);
      expect(preset.attrsFromAi(<String, Object?>{...legal, 'str': 100}),
          isFalse);
      expect(preset.attrsFromAi(<String, Object?>{...legal, 'con': -1}),
          isFalse);
    });

    test('任一项非 5 倍数 → 整块拒收（走重掷），绝不进卡', () {
      expect(preset.attrsFromAi(<String, Object?>{...legal, 'str': 53}),
          isFalse);
      expect(preset.attrsFromAi(<String, Object?>{...legal, 'luck': 47}),
          isFalse);
    });

    test('缺 luck → 拒收（旧版口径保留）', () {
      expect(
        preset.attrsFromAi(<String, Object?>{
          for (final e in legal.entries)
            if (e.key != 'luck') e.key: e.value,
        }),
        isFalse,
      );
    });
  });

  group('A · 三条生成路径都吃到新上限', () {
    const cap = AiCaps(attrCap: 300, withLuck: true);

    void expectCardLegal(Character c, String label) {
      expect(c.raw['ruleSystemId'], isNotEmpty, reason: '$label 缺规则标记');
      for (final k in _keys9) {
        final v = jsNum(c.attributes[k]);
        expect(v % genStep, 0, reason: '$label：$k=$v 不是 5 的倍数');
        expect(v, inInclusiveRange(genMin, genMax),
            reason: '$label：$k=$v 越界');
      }
      expect(_sum(c.attributes, withLuck: true), lessThanOrEqualTo(cap.attrCap),
          reason: '$label：压缩未生效');
    }

    test('AI 卡：非 5 倍数属性先压缩 → 采纳后仍是合法卡', () {
      final profile = <String, Object?>{
        'fromAI': true,
        'name': '测试调查员',
        'attributes': <String, Object?>{
          'str': 90,
          'con': 85,
          'siz': 80,
          'dex': 75,
          'app': 70,
          'int': 95,
          'pow': 60,
          'edu': 55,
          'luck': 99,
        },
      };
      // 复刻 net/ai_create.dart 的落地链：先压缩，再交给规则引擎。
      final scaled = applyAttrCap(profile, cap);
      expect(scaled, isTrue);
      expect(preset.attrsFromAi(profile['attributes'] as Map), isTrue,
          reason: '压缩后必须过 5 倍数闸门');
      final c = preset.buildFrom(
        profile,
        null,
        preset.PresetOptions(caps: cap, ruleSystemId: 'coc7'),
      );
      expect(c, isNotNull);
      expectCardLegal(c!, 'AI 卡');
    });

    test('AI 卡：非 5 倍数且未超限 → attrsFromAi 拒收 → 规则层重掷出合法卡', () {
      final profile = <String, Object?>{
        'fromAI': true,
        'name': '测试调查员',
        'attributes': <String, Object?>{
          'str': 53,
          'con': 60,
          'siz': 50,
          'dex': 65,
          'app': 70,
          'int': 80,
          'pow': 60,
          'edu': 75,
          'luck': 45,
        },
      };
      expect(preset.attrsFromAi(profile['attributes'] as Map), isFalse);
      final c = preset.buildFrom(
        profile,
        null,
        preset.PresetOptions(caps: const AiCaps()),
      );
      expect(c, isNotNull);
      for (final k in _keys9) {
        final v = jsNum(c!.attributes[k]);
        expect(v % genStep, 0, reason: '$k=$v 不是 5 的倍数');
        expect(v, inInclusiveRange(genMin, genMax));
      }
    });

    test('5 张随机卡：整批共用同一份 caps，每张都合法', () {
      final cards = preset.generate(
        5,
        preset.PresetOptions(caps: cap, ruleSystemId: 'coc7'),
      );
      expect(cards.length, 5);
      for (var i = 0; i < cards.length; i++) {
        expectCardLegal(cards[i], '随机卡#$i');
      }
    });

    test('彩蛋卡：与随机卡同源，压缩后仍合法', () {
      final target = egg.all().first;
      final c = preset.generateOne(
        preset.PresetOptions(
          caps: cap,
          ruleSystemId: 'coc7',
          profile: egg.toProfile(target),
        ),
      );
      expect(c, isNotNull);
      expect(c!.raw['isEasterEgg'], isTrue);
      expectCardLegal(c, '彩蛋卡');
    });
  });
}
