// ============================================================
// test/support/oracle.dart — 「JS 当预言机」的测试基础设施
//
// 三条约定（缺一不可，否则等价性证明就不成立）：
//   1. 随机源：Dart 侧用与 oracle 完全相同的 LCG（同 seed → 同序列），
//      并在每个用例结束时断言「消耗的随机数个数」也一致 ——
//      消耗数不同说明两边的随机调用顺序已经分叉。
//   2. 时钟：Date.now 固定成 1700000000000（oracle 脚本里 monkey-patch 的值）。
//   3. 比较：逐字段深比较，键集合必须完全一致（多一个 null 键也算不一致）。
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:flutter_test/flutter_test.dart';

/// oracle 脚本里 `Date.now()` 的固定值
const int oracleNowMs = 1700000000000;

/// 与 tool/oracle/load.js 里的 LCG 逐位一致
/// （JS: `seed = (seed * 1664525 + 1013904223) >>> 0`）
class Lcg {
  Lcg(int seed) : _seed = seed & 0xFFFFFFFF;

  int _seed;
  int used = 0;

  double call() {
    used++;
    _seed = (_seed * 1664525 + 1013904223) & 0xFFFFFFFF;
    return _seed / 4294967296;
  }
}

/// 一个 fixture 文件
class OracleFixture {
  OracleFixture._(this.file, this.data, this.cases);

  final String file;
  final Map<String, Object?> data;
  final List<Map<String, Object?>> cases;

  static OracleFixture load(String name) {
    final f = File('test/fixtures/$name');
    if (!f.existsSync()) {
      throw StateError(
        '缺少 fixture: ${f.absolute.path}（先跑 node tool/oracle/dump_fixtures.js）',
      );
    }
    final data = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
    final cases = (data['cases'] as List).cast<Map<String, Object?>>();
    return OracleFixture._(name, data, cases);
  }

  /// 按 `fn` 分组跑。每个 fn 一个 test，内部逐例断言。
  ///
  /// [handlers] 里每个函数把 fixture 的 `args` 映射成对 Dart 实现的调用。
  /// 原码抛异常的用例（`error != null`）会跳过并单独统计 —— 那属于原码缺陷，
  /// 见 _p0_report.txt「原码坑位」一节。
  void run(Map<String, Object? Function(Object? args)> handlers) {
    final byFn = <String, List<Map<String, Object?>>>{};
    final skipped = <String, String>{};
    final unknown = <String>{};

    for (final c in cases) {
      final fn = c['fn'] as String;
      final err = c['error'];
      if (err != null) {
        skipped[fn] = err as String;
        continue;
      }
      if (!handlers.containsKey(fn)) {
        unknown.add(fn);
        continue;
      }
      byFn.putIfAbsent(fn, () => <Map<String, Object?>>[]).add(c);
    }

    byFn.forEach((fn, list) {
      test('$fn（${list.length} 例）', () {
        var passed = 0;
        for (final c in list) {
          final name = c['name'];
          final rng = Lcg((c['seed'] as num).toInt());
          setRng(rng.call);
          setClock(() => oracleNowMs);
          // id 也必须由同一条确定性序列算出来：normalize 的用例逐字比对
          // id，且断言随机数消耗数（uid 占 8 次）。生产环境用 Random.secure()。
          uidDeterministic = true;

          final Object? actual;
          try {
            actual = handlers[fn]!(c['args']);
          } catch (e, st) {
            fail('$fn / $name：Dart 侧抛异常 $e\n$st');
          }

          _expectJsonMatch(actual, c['expect'], '$fn / $name');
          expect(
            rng.used,
            (c['randUsed'] as num).toInt(),
            reason:
                '$fn / $name：随机数消耗数不一致（Dart ${rng.used} ≠ JS ${c['randUsed']}）',
          );
          passed++;
        }
        expect(passed, list.length);
      });
    });

    test('fixture 覆盖完整性（本文件 ${cases.length} 例）', () {
      expect(unknown, isEmpty, reason: '这些 fn 没有对应的 Dart handler: $unknown');
      if (skipped.isNotEmpty) {
        // ignore: avoid_print
        print('⚠️ $file：${skipped.length} 类函数在原码里会抛异常，已跳过 → $skipped');
      }
    });
  }
}

/// 从 `{card: ...}` 参数取出一张卡
Character cardOf(Object? args) {
  final m = args as Map;
  return Character.fromJson(Map<String, Object?>.from(m['card'] as Map));
}

/// 逐字段深比较 + 路径定位（对外暴露一份，供不走 [OracleFixture.run] 的用例复用）
void expectJsonMatch(Object? actual, Object? expected, [String path = r'$']) =>
    _expectJsonMatch(actual, expected, path);

/// 逐字段深比较 + 路径定位
void _expectJsonMatch(Object? actual, Object? expected, String path) {
  if (expected is Map) {
    if (actual is! Map) {
      fail('$path：期望对象，实际 ${actual.runtimeType}（$actual）');
    }
    final ek = expected.keys.map((k) => '$k').toSet();
    final ak = actual.keys.map((k) => '$k').toSet();
    final missing = ek.difference(ak);
    final extra = ak.difference(ek);
    if (missing.isNotEmpty || extra.isNotEmpty) {
      fail('$path：键集合不一致。缺 $missing，多 $extra');
    }
    for (final k in ek) {
      _expectJsonMatch(actual[k], expected[k], '$path.$k');
    }
    return;
  }
  if (expected is List) {
    if (actual is! List) {
      fail('$path：期望数组，实际 ${actual.runtimeType}（$actual）');
    }
    if (actual.length != expected.length) {
      fail('$path：数组长度 ${actual.length} ≠ 期望 ${expected.length}');
    }
    for (var i = 0; i < expected.length; i++) {
      _expectJsonMatch(actual[i], expected[i], '$path[$i]');
    }
    return;
  }
  if (expected is num) {
    if (actual is! num) {
      fail('$path：期望数字，实际 ${actual.runtimeType}（$actual）');
    }
    if (actual != expected) {
      fail('$path：实际 $actual ≠ 期望 $expected');
    }
    return;
  }
  if (actual != expected) {
    fail('$path：实际「$actual」≠ 期望「$expected」');
  }
}
