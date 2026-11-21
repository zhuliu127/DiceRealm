// ============================================================
// test/qa_p4_whitelist_proof_test.dart — 白名单**非摆设**的常驻自证
//
// 背景（F5）：`S:q1` 曾有 14 条登记，但 fixture 的 rollback 位置写错、重放
// 区间根本不含秘密事件，于是白名单**从未生效**却一直「全绿」。一次性的
// 手工探针跑完就删，挡不住下一次。所以这里落成常驻用例，钉四条：
//
//   ① **绕开白名单必须报错**：对每条登记覆盖的 case，用 `expectJsonMatch`
//      （不带 allowedPaths）比较，必须抛 TestFailure —— 否则该条差异实际为 0，
//      说明白名单是死登记（或对应的源码修复已被破坏）。
//   ② **一条不多**：独立递归算出 actual vs expect 的全部差异路径，
//      必须**恰好等于**登记集合。多出来的登记就是「将来会自动放行新差异」的
//      隐患（本次据此把 S:q1 的 14 条收窄到 9 条）。
//   ③ **一条不少 / 每条都被消费**：逐条摘除后重新比较，必须报错；
//      任何一条摘掉仍然绿 → 该条冗余。
//   ④ **只跳单键、不跳子树**：登记 `$.a.b` 不得放过 `$.a.b.c` 的差异。
//
// ⚠️ 本文件用的是 `test/support/room_host_script.dart`，与正式用例
//    （room_sequences_test.dart）**同一条执行路径**，不是另写一份仿制品。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/oracle.dart' show Lcg, oracleNowMs;
import 'support/room_host_script.dart';
import 'support/room_oracle.dart';
import 'support/room_oracle_whitelist.dart';

/// 取某条登记覆盖的全部 case（跨 fixture）。
List<Map<String, Object?>> _coveredCases(
  KnownDivergence div,
  List<RoomOracleFixture> fixtures,
) {
  final out = <Map<String, Object?>>[];
  for (final f in fixtures) {
    for (final c in f.cases) {
      if (div.coversCase(c)) out.add(c);
    }
  }
  return out;
}

/// 跑一个 case 的 `actual`（与正式用例同种子、同时钟、同 runner）。
Map<String, Object?> _actualOf(Map<String, Object?> c) {
  final rng = Lcg((c['seed']! as num).toInt());
  setRng(rng.call);
  setClock(() => oracleNowMs);
  return runHostScript((c['args'] as Map).cast<String, Object?>());
}

void main() {
  final fixtures = <RoomOracleFixture>[
    RoomOracleFixture.load('room_sequences.json'),
    RoomOracleFixture.load('qa_p4_fresh_oracle.json'),
  ];

  group('白名单非摆设 · 绕开白名单必须报错', () {
    for (final div in kRoomOracleWhitelist) {
      test('${div.caseId}：覆盖的每一例都必须真的有差异', () {
        final cases = _coveredCases(div, fixtures);
        expect(cases, isNotEmpty,
            reason: '${div.caseId} 一条 case 都没覆盖 → 死登记');
        for (final c in cases) {
          final name = c['name'];
          final actual = _actualOf(c);
          expect(
            () => expectJsonMatch(actual, c['expect'], r'$', '${div.caseId}/$name'),
            throwsA(isA<TestFailure>()),
            reason: '${div.caseId}/$name：绕开白名单竟然完全相等 → '
                '这条登记是死登记（或源码修复被回退）',
          );
        }
      });
    }
  });

  group('白名单非摆设 · 被排除用例的理由成立', () {
    test('S:q1#1015 在严格比较下确实相等（排除它是因为零差异，不是图省事）', () {
      final f = RoomOracleFixture.load('room_sequences.json');
      final c = f.cases.firstWhere((x) => x['name'] == 'S:q1#1015');
      final rng = Lcg((c['seed']! as num).toInt());
      setRng(rng.call);
      setClock(() => oracleNowMs);
      final actual = runHostScript((c['args'] as Map).cast<String, Object?>());
      expect(() => expectJsonMatch(actual, c['expect'], r'$'), returnsNormally,
          reason: '#1015 严格比较竟然不等 → 它不该被排除，应该正经登记差异');
    });
  });

  group('白名单非摆设 · 一条不多、一条不少', () {
    for (final div in kRoomOracleWhitelist) {
      test('${div.caseId}：差异路径集合恰好等于登记集合', () {
        final cases = _coveredCases(div, fixtures);
        final union = <String>{};
        for (final c in cases) {
          collectDiffPaths(_actualOf(c), c['expect'], r'$', union);
        }
        final registered = div.allowedPaths.toSet();
        final redundant = registered.difference(union);
        final uncovered = union.difference(registered);
        expect(uncovered, isEmpty,
            reason: '${div.caseId}：出现未登记的差异路径 $uncovered'
                '（严格比较本该报错 → 说明比较器被放宽了）');
        expect(redundant, isEmpty,
            reason: '${div.caseId}：登记的 $redundant 在当前 fixture 下零差异 → '
                '冗余登记，将来可能自动放行新差异，必须删除');
      });

      test('${div.caseId}：逐条摘除都必须报错（每条都真的被消费）', () {
        final cases = _coveredCases(div, fixtures);
        final registered = div.allowedPaths;
        for (final p in registered) {
          final rest = registered.where((x) => x != p).toList();
          var caught = false;
          for (final c in cases) {
            final actual = _actualOf(c);
            try {
              expectJsonMatchExcept(
                actual,
                c['expect'],
                rest,
                r'$',
                '${div.caseId}/${c['name']}',
              );
            } on TestFailure {
              caught = true;
              break;
            }
          }
          expect(caught, isTrue,
              reason: '${div.caseId}：摘掉「$p」后仍然全绿 → 该条零消费，应删除');
        }
      });
    }
  });

  group('比较器语义 · 只跳单键、不跳子树', () {
    test('登记叶子标量路径：只放过它自己', () {
      final actual = <String, Object?>{'a': 1, 'b': <String, Object?>{'c': 2}};
      final expected = <String, Object?>{'a': 9, 'b': <String, Object?>{'c': 2}};
      expect(
        () => expectJsonMatchExcept(actual, expected, <String>[r'$.a']),
        returnsNormally,
      );
    });

    test('登记容器路径不得连带放过它的子键差异', () {
      final actual = <String, Object?>{
        'a': <String, Object?>{
          'b': <String, Object?>{'c': 1, 'd': 2},
        },
      };
      final expected = <String, Object?>{
        'a': <String, Object?>{
          'b': <String, Object?>{'c': 1, 'd': 3},
        },
      };
      expect(
        () => expectJsonMatchExcept(actual, expected, <String>[r'$.a.b']),
        throwsA(isA<TestFailure>()),
        reason: r'登记 $.a.b 却把 $.a.b.d 的差异也放过了 → 一个路径能静默放过整棵子树',
      );
    });

    test('登记容器路径不得连带放过「多出键」', () {
      final actual = <String, Object?>{
        'a': <String, Object?>{
          'b': <String, Object?>{'c': 1, 'x': 9},
        },
      };
      final expected = <String, Object?>{
        'a': <String, Object?>{
          'b': <String, Object?>{'c': 1},
        },
      };
      expect(
        () => expectJsonMatchExcept(actual, expected, <String>[r'$.a.b']),
        throwsA(isA<TestFailure>()),
      );
    });

    test('登记容器里的**单个键**：键集合放行只跳这一个键（F5.5 口径）', () {
      // Dart 脱敏行比旧版多一个 redacted 键 —— 这类「只在一侧存在的叶子键」
      // 必须能被精确登记放行，且不影响同层其他键。
      final actual = <String, Object?>{
        'logs': <Object?>[
          <String, Object?>{'text': 'x', 'redacted': true},
        ],
      };
      final expected = <String, Object?>{
        'logs': <Object?>[
          <String, Object?>{'text': 'x'},
        ],
      };
      expect(
        () => expectJsonMatchExcept(actual, expected, <String>[r'$.logs[0].redacted']),
        returnsNormally,
      );
      // 同层其他键仍严格
      final a2 = <String, Object?>{
        'logs': <Object?>[
          <String, Object?>{'text': 'y', 'redacted': true},
        ],
      };
      expect(
        () => expectJsonMatchExcept(a2, expected, <String>[r'$.logs[0].redacted']),
        throwsA(isA<TestFailure>()),
      );
    });

    test('通配 `.*` 仍可用于「整棵子树」（说明收窄是选择而非能力缺失）', () {
      final actual = <String, Object?>{'a': <String, Object?>{'b': 1, 'c': 2}};
      final expected = <String, Object?>{'a': <String, Object?>{'b': 9, 'c': 8}};
      expect(
        () => expectJsonMatchExcept(actual, expected, <String>[r'$.a.*']),
        returnsNormally,
      );
    });
  });
}
