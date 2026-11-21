// ============================================================
// test/support/room_oracle.dart — P4「JS 当预言机」的测试基础设施
//
// 与 P0 的 OracleFixture 同口径（Lcg + 固定时钟 + 逐字段深比较 + randUsed），
// 另加两件 P4 专属的东西：
//   1) 每个 case 带 `tag`，覆盖矩阵测试据此断言「tag 集合零缺口」；
//   2) **白名单闸门**：只有登记在 room_oracle_whitelist.dart 里的路径允许不同，
//      其余路径一律严格深比较。禁用 contains / 模糊匹配 / 跳过字段（K14）。
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:dice_realm/domain/js_compat.dart';
import 'package:flutter_test/flutter_test.dart';

import 'oracle.dart' show Lcg, oracleNowMs;
import 'room_oracle_whitelist.dart';

/// 一个 P4 fixture 文件。
class RoomOracleFixture {
  RoomOracleFixture._(this.file, this.data, this.cases);

  final String file;
  final Map<String, Object?> data;
  final List<Map<String, Object?>> cases;

  static RoomOracleFixture load(String name) {
    final f = File('test/fixtures/$name');
    if (!f.existsSync()) {
      throw StateError(
        '缺少 fixture: ${f.absolute.path}（先跑 node tool/oracle/dump_p4_room.js）',
      );
    }
    final data = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
    final cases = (data['cases'] as List).cast<Map<String, Object?>>();
    return RoomOracleFixture._(name, data, cases);
  }

  /// fixture 里出现过的全部 tag（覆盖矩阵断言用）
  Set<String> get tags => cases.map((c) => c['tag']! as String).toSet();

  /// 按 `fn` 分组跑；每个 fn 一个 test。
  ///
  /// [handlers] 的 key 必须覆盖 fixture 里出现的所有 `fn`，
  /// 否则末尾的「覆盖完整性」用例会红（避免 handler 漏写却静默通过）。
  void run(
    Map<String, Object? Function(Map<String, Object?> args)> handlers, {
    Set<String>? only,
  }) {
    final byFn = <String, List<Map<String, Object?>>>{};
    final skipped = <String, String>{};
    final unknown = <String>{};

    for (final c in cases) {
      final fn = c['fn']! as String;
      // 分批验收：只跑本批已实现 handler 的子集（其余留给后续任务）
      if (only != null && !only.contains(fn)) continue;
      final err = c['error'];
      if (err != null) {
        skipped['$fn/${c['name']}'] = err as String;
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
          final name = c['name']! as String;
          final rng = Lcg((c['seed']! as num).toInt());
          setRng(rng.call);
          setClock(() => oracleNowMs);

          final args = (c['args'] as Map).cast<String, Object?>();
          final Object? actual;
          try {
            actual = handlers[fn]!(args);
          } catch (e, st) {
            fail('$fn / $name：Dart 侧抛异常 $e\n$st');
          }

          final div = kRoomOracleWhitelist.where((d) => d.coversCase(c)).toList();
          // ★ F5：比较根必须是 `r'$'`，否则 allowedPaths 的 `$.` 语义不成立
          //   （旧实现把 '$fn / $name' 当根 → 14 条 S:q1 路径全部匹配不上，
          //    白名单变成死登记）。用例名改走 [label]，只影响报错可读性。
          if (div.isEmpty) {
            expectJsonMatch(actual, c['expect'], r'$', '$fn / $name');
          } else {
            // 白名单：只放行登记的精确路径，其余仍逐字段深比较
            expectJsonMatchExcept(
              actual,
              c['expect'],
              div.single.allowedPaths,
              r'$',
              '$fn / $name',
            );
          }
          expect(
            rng.used,
            (c['randUsed']! as num).toInt(),
            reason: '$fn / $name：随机数消耗数不一致'
                '（Dart ${rng.used} ≠ JS ${c['randUsed']}）',
          );
          passed++;
        }
        expect(passed, list.length);
      });
    });

    test('fixture 覆盖完整性（$file ${cases.length} 例${only == null ? '' : '，本批 ${only.length} 类 fn'}）', () {
      expect(unknown, isEmpty, reason: '这些 fn 没有对应的 Dart handler: $unknown');
      if (skipped.isNotEmpty) {
        // ignore: avoid_print
        print('⚠️ $file：${skipped.length} 例在原码里会抛异常，已跳过 → $skipped');
      }
    });
  }
}

/// 逐字段深比较 + 路径定位（对外暴露，供不走 [RoomOracleFixture.run] 的用例复用）
///
/// [path] 是**比较根路径**，默认 `r'$'`；`allowedPaths` 里的 `$.a.b[2].c`
/// 一律从它起算。[label] 只作为报错前缀（例如 `'$fn / $name'`），
/// **不参与路径计算**，也不参与 `_isAllowed` 匹配。
void expectJsonMatch(
  Object? actual,
  Object? expected, [
  String path = r'$',
  String? label,
]) =>
    _expectJsonMatch(actual, expected, path, null, label);

/// 与 [expectJsonMatch] 相同，但跳过 [allowedPaths] 里登记的路径。
///
/// 路径语法：`$.a.b[2].c`；结尾 `.*` 表示该节点下的所有后代。
/// [label] 只影响报错前缀，路径仍从 [path]（默认 `r'$'`）起算。
void expectJsonMatchExcept(
  Object? actual,
  Object? expected,
  List<String> allowedPaths, [
  String path = r'$',
  String? label,
]) =>
    _expectJsonMatch(actual, expected, path, allowedPaths, label);

/// 统一报错出口：把用例标签与 JSON 路径拼成可读信息。
///
/// 返回 [Never] 是为了让 `actual is! Map` 之后的流程分析把 `actual` 提升为
/// 非空；`fail()` 本身即 `Never`，函数体无需再补 return/throw。
Never _failAt(String path, String? label, String message) {
  final prefix = (label == null || label.isEmpty) ? path : '$label / $path';
  fail('$prefix：$message');
}

bool _isAllowed(String path, List<String>? allowed) {
  if (allowed == null || allowed.isEmpty) return false;
  for (final a in allowed) {
    if (a == path) return true;
    if (a.endsWith('.*')) {
      final prefix = a.substring(0, a.length - 2);
      if (path == prefix) return true;
      if (path.startsWith('$prefix.') || path.startsWith('$prefix[')) return true;
    }
  }
  return false;
}

void _expectJsonMatch(
  Object? actual,
  Object? expected,
  String path,
  List<String>? allowed,
  String? label,
) {
  // ★ P4-QA 终验（F5 复核项）：登记一条路径，只放行**这个值**本身。
  //   容器（Map / List）必须继续往下递归 —— 否则登记 `$.a.b` 会把
  //   `$.a.b.c` / `$.a.b.d` 的差异整棵子树静默放过（一个路径 = 一张空白支票）。
  //   要放行整棵子树必须显式写 `.*` 通配，让审计一眼看得出来。
  if (_isAllowed(path, allowed) && expected is! Map && expected is! List) {
    return;
  }

  if (expected is Map) {
    if (actual is! Map) {
      _failAt(path, label, '期望对象，实际 ${actual.runtimeType}（$actual）');
    }
    final ek = expected.keys.map((k) => '$k').toSet();
    final ak = actual.keys.map((k) => '$k').toSet();
    // ★ F5.5：allowedPaths 必须同时能放行「只在一侧存在」的单个键。
    //   对象分支原本先做键集合差集、再逐键递归；差集报错发生在递归之前，
    //   导致登记在 `$.xxx.redacted` 这类**叶子路径**上的放行根本来不及生效
    //   （Dart 脱敏行比旧版多一个 redacted 键 → 「多 {redacted}」直接 fail）。
    //   这里按 `'$path.$k'` 构造该键的完整路径，命中 allowed 就从差集里剔除：
    //   只跳过这一个键的缺失/多余报错，不跳过它下面的子树（子树仍由递归
    //   逐字段比较），也不影响同层其他键。数组分支沿用 `'$path[$i]'` 风格，
    //   二者拼出的路径与 allowedPaths 的 `$.a.b[2].c` 文档语法完全一致。
    final missing = ek.difference(ak);
    final extra = ak.difference(ek);
    // 上面两行仍做完整差集（严格比较器未被放宽的静态探针依赖该原文），
    // F5.5 只在**报错判定**这一步按完整路径逐键剔除登记项。
    final missingUnallowed = missing.where(
      (k) => !_isAllowed('$path.$k', allowed),
    ).toSet();
    final extraUnallowed = extra.where(
      (k) => !_isAllowed('$path.$k', allowed),
    ).toSet();
    if (missingUnallowed.isNotEmpty || extraUnallowed.isNotEmpty) {
      _failAt(path, label,
          '键集合不一致。缺 $missingUnallowed，多 $extraUnallowed');
    }
    for (final k in ek) {
      _expectJsonMatch(actual[k], expected[k], '$path.$k', allowed, label);
    }
    return;
  }
  if (expected is List) {
    if (actual is! List) {
      _failAt(path, label, '期望数组，实际 ${actual.runtimeType}（$actual）');
    }
    if (actual.length != expected.length) {
      _failAt(path, label,
          '数组长度 ${actual.length} ≠ 期望 ${expected.length}');
    }
    for (var i = 0; i < expected.length; i++) {
      _expectJsonMatch(actual[i], expected[i], '$path[$i]', allowed, label);
    }
    return;
  }
  if (expected is num) {
    if (actual is! num) {
      _failAt(path, label, '期望数字，实际 ${actual.runtimeType}（$actual）');
    }
    if (actual != expected) {
      _failAt(path, label, '实际 $actual ≠ 期望 $expected');
    }
    return;
  }
  if (actual != expected) {
    _failAt(path, label, '实际「$actual」≠ 期望「$expected」');
  }
}
