// ============================================================
// test/room_equivalence_test.dart — T05 三 fixture 1102 例全量等价门禁
//
// 「全绿」有两种骗法：只跑子集（only）和悄悄放宽比较器。本文件把这两条
// 都钉死，并给出可复核的注册表级证据：
//   ① 三个基线 fixture 精确 525 / 455 / 122 = 1102 例；第 4 个独立
//      fixture（S4.3 动作分发）256 例；四者零 error、零缺 expect/seed/randUsed；
//   ② 四个 fixture 的**每个 fn 都能在 test/room_*_test.dart 里找到 handler**；
//      room_model.json 的两处 only（core 的 batch + save 的 6 类）并集恰好
//      等于它的 30 类 fn，其余三个宿主测试不许出现 only；
//   ③ room_sequences.json 的 hostScript 95 / clientScript 27 例全部有
//      handler 且无 only —— 122 例全实跑；
//   ④ 比较器仍是「键集合双向差集 + randUsed 严格相等」的严格版；
//      白名单恰好 2 条：S:q1 收窄到 9 条 allowedPaths（终验核销 5 条冗余），
//      F3 裁决 A 新增 S:trim 的 1 条精确路径；
//   ⑤ 运行时正反例证明 expectJsonMatch 不是 no-op（多键/错值必须 fail）。
//
// 1102 例的**实际执行**由四个宿主测试完成：
//   room_rules_oracle_test.dart（455）、room_model_core_test.dart（492）+
//   room_save_test.dart（25）、room_sequences_test.dart（122）。
// 本文件不重复实现 handler，只做「没人能偷偷少跑一例」的门禁。
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/room_oracle.dart';
import 'support/room_oracle_whitelist.dart';

/// 四个 fixture 的精确条数（三个基线累计 1105）。
const Map<String, int> kFixtureSizes = <String, int>{
  'room_rules.json': 455,
  'room_model.json': 525,
  'room_sequences.json': 122,
  'room_actions.json': 259,
};

Map<String, Object?> _raw(String name) => jsonDecode(
      File('test/fixtures/$name').readAsStringSync(),
    ) as Map<String, Object?>;

List<Map<String, Object?>> _cases(String name) =>
    (_raw(name)['cases'] as List).cast<Map<String, Object?>>();

String _src(String rel) => File(rel).readAsStringSync();

/// 剥离 `//` 行注释：注释里的示例语法不算真实代码。
String _codeOnly(String src) => src
    .split('\n')
    .map((line) {
      final i = line.indexOf('//');
      return i < 0 ? line : line.substring(0, i);
    })
    .join('\n');

Set<String> _quoted(String block) => RegExp(r"'([^']+)'")
    .allMatches(block)
    .map((m) => m.group(1)!)
    .toSet();

/// 源码里 `only: <String>{...}` 的字面量集合（可能有多处）。
Set<String> _onlyLiterals(String src) {
  final out = <String>{};
  for (final m in RegExp(r'only:\s*<String>\{([\s\S]*?)\}').allMatches(src)) {
    out.addAll(_quoted(m.group(1)!));
  }
  return out;
}

/// `final batch = <String>{...};` 的字面量集合（room_model_core_test.dart）。
Set<String> _batchLiterals(String src) {
  final m = RegExp(r'final batch = <String>\{([\s\S]*?)\};').firstMatch(src);
  return m == null ? <String>{} : _quoted(m.group(1)!);
}

/// 所有 `test/room_*_test.dart` 里出现过的 handler 键。
///
/// 两种写法都要认：`'fn': (a) => ...` 与 `'fn': _helper,`（后者是
/// room_save_test.dart 的 applyStateToCard）。
Set<String> _handlerKeys() {
  final out = <String>{};
  final re = RegExp(
    r"^\s*'([^']+)':\s*(?:\(|[A-Za-z_][A-Za-z0-9_]*\s*,)",
    multiLine: true,
  );
  for (final f in Directory('test').listSync().whereType<File>()) {
    if (!f.path.contains('room_') || !f.path.endsWith('_test.dart')) continue;
    for (final m in re.allMatches(f.readAsStringSync())) {
      out.add(m.group(1)!);
    }
  }
  return out;
}

void main() {
  test('四 fixture 精确 1361 例（三基线 1102），零 error / 零缺字段', () {
    for (final e in kFixtureSizes.entries) {
      final d = _raw(e.key);
      final expectedKeys = e.key == 'room_actions.json'
          ? <String>{'generatedAt', 'total', 'tags', 'cases', 'meta'}
          : <String>{'generatedAt', 'total', 'tags', 'cases'};
      expect(
        d.keys.toSet(),
        expectedKeys,
        reason: '${e.key} 顶层形状被改过',
      );
      expect(d['total'], e.value, reason: '${e.key}.total 与条数不符');
      // 三个基线用「tag → 例数」对象，第 4 个动作 fixture 用 tag 数组；
      // 两者都合法，只要不是 null / 标量。
      expect(d['tags'] is Map || d['tags'] is List, isTrue,
          reason: '${e.key}.tags 必须是覆盖矩阵容器');
      final cases = _cases(e.key);
      expect(cases.length, e.value, reason: '${e.key} 条数被改过');
      for (final c in cases) {
        expect(c['name'], isA<String>(), reason: '${e.key} 有用例缺 name');
        expect(c['fn'], isA<String>(), reason: '${e.key} 有用例缺 fn');
        expect(c['seed'], isA<num>(), reason: '${e.key} 有用例缺 seed');
        expect(c['randUsed'], isA<num>(), reason: '${e.key} 有用例缺 randUsed');
        // expect: null 是**合法期望值**（旧版函数真的返回 null），
        // 只要求键存在；缺键才说明 fixture 被裁过。
        expect(c.containsKey('expect'), isTrue,
            reason: '${e.key} 有用例没有 expect 键');
        expect(c['error'], isNull,
            reason: '${e.key}/${c['name']} 带 error，会被 run 静默跳过');
      }
    }
    expect(
      kFixtureSizes['room_rules.json']! +
          kFixtureSizes['room_model.json']! +
          kFixtureSizes['room_sequences.json']!,
      1102,
      reason: '三个基线 fixture 必须仍是 1102 例',
    );
  });

  test('四个 fixture 的每个 fn 都有 handler；room_model 的 only 并集零漏跑', () {
    final handlers = _handlerKeys();
    for (final name in kFixtureSizes.keys) {
      final fns = _cases(name).map((c) => c['fn']! as String).toSet();
      final missing = fns.difference(handlers);
      expect(missing, isEmpty, reason: '$name 有 fn 没有 handler：$missing');
    }

    final core = _src('test/room_model_core_test.dart');
    final save = _src('test/room_save_test.dart');
    final batch = _batchLiterals(core);
    final saveOnly = _onlyLiterals(save);
    final modelFns = _cases('room_model.json').map((c) => c['fn']! as String).toSet();
    expect(batch.length, 24, reason: 'D10~D13 的 24 类 handler');
    expect(saveOnly.length, 6, reason: 'D21 的 6 类 handler');
    // 两处 only 的并集必须覆盖 room_model.json 的每一类 fn（零漏跑）。
    // 并集比 fixture 多出的 ruleOptsOf 是 Dart-only handler：旧版没导出，
    // fixture 里没有这类用例，多一个不会跳过任何一例。
    final union = batch.union(saveOnly);
    expect(modelFns.difference(union), isEmpty,
        reason: 'room_model.json 的 525 例被两处 only 切成两块，并集必须全覆盖');
    expect(union.difference(modelFns), <String>{'ruleOptsOf'},
        reason: '额外的 handler 只能是 Dart-only 的 ruleOptsOf');

    // 其余三个宿主测试不许再出现 only（含注释里写 only 也不影响，只认语法）。
    for (final f in <String>[
      'room_rules_oracle_test.dart',
      'room_sequences_test.dart',
      'room_actions_test.dart',
    ]) {
      expect(
        RegExp(r'\bonly\s*:').hasMatch(_codeOnly(_src('test/$f'))),
        isFalse,
        reason: '$f 出现 only，会导致部分用例从未执行',
      );
    }
  });

  test('room_sequences.json 122 例全实跑：hostScript 95 / clientScript 27', () {
    final seqs = _cases('room_sequences.json');
    expect(seqs.length, 122);
    final host = seqs.where((c) => c['fn'] == 'hostScript').length;
    final client = seqs.where((c) => c['fn'] == 'clientScript').length;
    expect(host, 95, reason: '95 例 hostScript 曾因 only 被跳过，T05 必须全跑');
    expect(client, 27);
    expect(host + client, 122);
    final src = _src('test/room_sequences_test.dart');
    expect(src.contains("'hostScript':"), isTrue);
    expect(src.contains("'clientScript':"), isTrue);
    expect(RegExp(r'\bonly\s*:').hasMatch(_codeOnly(src)), isFalse);
  });

  test('严格比较器未被放宽；白名单恰好 2 条，S:q1 9 条 allowedPaths', () {
    // F3 裁决 A：新增 S:trim（1 条精确路径）；P4-QA 终验把 S:q1 的 14 条
    // 收窄到 9 条（5 条零消费的冗余放行已删，核销依据见
    // qa_p4_whitelist_proof_test.dart 的「一条不多」核算）。
    expect(kRoomOracleWhitelist.length, 2);
    final d = kRoomOracleWhitelist.firstWhere((e) => e.caseId == 'S:q1');
    expect(d.caseId, 'S:q1');
    expect(d.allowedPaths.length, 9);
    expect(d.allowedPaths.toSet().length, 9);
    final trim = kRoomOracleWhitelist.firstWhere((e) => e.caseId == 'S:trim');
    expect(trim.allowedPaths, <String>[kTrimAllowedPath]);
    for (final p in trim.allowedPaths) {
      expect(p.contains('*'), isFalse);
    }
    final cmp = _src('test/support/room_oracle.dart');
    expect(cmp.contains('final missing = ek.difference(ak);'), isTrue);
    expect(cmp.contains('final extra = ak.difference(ek);'), isTrue);
    expect(cmp.contains('键集合不一致'), isTrue);
    expect(cmp.contains("(c['randUsed']! as num).toInt()"), isTrue,
        reason: 'randUsed 必须严格相等，不能只看结果');
    expect(cmp.contains('expectJsonMatchExcept'), isTrue);
  });

  test('比较器正反例：多键 / 少键 / 错值 / 长度不符一律 fail（不是 no-op）', () {
    expectJsonMatch(<String, Object?>{'a': 1}, <String, Object?>{'a': 1});
    expectJsonMatch(<Object?>[1, 2], <Object?>[1, 2]);

    void mustFail(Object? actual, Object? expected, String why) {
      Object? caught;
      try {
        expectJsonMatch(actual, expected, r'$', 'probe');
      } catch (e) {
        caught = e;
      }
      expect(caught, isNotNull, reason: '$why：比较器竟然放过了差异');
    }

    mustFail(<String, Object?>{'a': 1}, <String, Object?>{'a': 1, 'b': 2},
        '多一个键');
    mustFail(<String, Object?>{'a': 1, 'b': 2}, <String, Object?>{'a': 1},
        '少一个键');
    mustFail(<String, Object?>{'a': 2}, <String, Object?>{'a': 1}, '值不同');
    mustFail(<Object?>[1], <Object?>[1, 2], '数组长度不同');
    mustFail(<String, Object?>{'a': 1}, <Object?>[1], '类型不同');
  });
}
