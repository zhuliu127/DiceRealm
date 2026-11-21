// ============================================================
// test/qa_p4_whitelist_strength_test.dart — 独立复核：白名单强度
//
// 白名单是「唯一允许偏离 oracle」的闸门，写松一点整层等价性就废了。
// 本文件钉五件事：
//   ① **恰好 2 条** KnownDivergence（F3 裁决 A 批准新增 S:trim）：
//      **S:q1 的 9 条**、S:trim 的 1 条路径都**逐条冻结**（终验把 14 收窄到 9，
//      核销依据见 qa_p4_whitelist_proof_test.dart 的「一条不多」核算）；
//      任何人偷偷加第 3 条 / 加路径 / 加 `.*` 通配 → 这里先红；
//   ② coversCase 的匹配范围**恰好**覆盖 S:q1 家族里**真有差异的 2 例**
//      （#1015 零差异，被 excludeCaseNames 精确排除、回到严格比较），
//      且不会被 `S:q10` / `S:q1-other` 这类无关命名蹭到（前缀过宽）；
//      S:trim 只靠 exactCaseNames 精确点名 F:4#900001，不得放宽前缀；
//   ③ 比较器强度：白名单外的差异必须**报错**，白名单内的差异才放行；
//   ④ forbiddenKeys 仍是 Q1 那 5 个（不许借「顺手多放几个键」放水）；
//   ⑤ 容器路径不得成为「空白支票」（只跳单键、不跳子树）。
// ============================================================

import 'package:flutter_test/flutter_test.dart';

import 'support/room_oracle.dart';
import 'support/room_oracle_whitelist.dart';

/// 逐条冻结的 **9** 条路径（改任何一条都要走设计裁决，不能顺手改）。
///
/// 终验收窄（14 → 9）：删掉 3× `.opp`（旧版脱敏行同样带 `opp:null`，两侧同值）、
/// `$.state.privates` 与 `$.steps[8].state.privates`（两侧同为 `[]`）。
/// 这 5 条在原 fixture 下**零消费**，属于「登记了却从不生效」的冗余放行。
const List<String> kFrozenAllowedPaths = <String>[
  r'$.state.logs[1].text',
  r'$.state.logs[1].seat',
  r'$.state.logs[1].redacted',
  r'$.steps[8].state.logs[1].text',
  r'$.steps[8].state.logs[1].seat',
  r'$.steps[8].state.logs[1].redacted',
  r'$.steps[9].state.logs[1].text',
  r'$.steps[9].state.logs[1].seat',
  r'$.steps[9].state.logs[1].redacted',
];

/// F3 裁决 A 新增的第 2 条：只允许这一条精确路径，禁止通配。
/// 运行期完整路径口径见 `room_oracle_whitelist.dart#kTrimAllowedPath`。
const List<String> kFrozenTrimAllowedPaths = <String>[
  kTrimAllowedPath,
];

/// 按 caseId 取登记项（白名单变 2 条后不能再写 `.single`）。
KnownDivergence byId(String id) =>
    kRoomOracleWhitelist.firstWhere((d) => d.caseId == id);

void main() {
  group('白名单登记面', () {
    test('恰好 2 条已知差异，且就是 S:q1 + S:trim', () {
      expect(kRoomOracleWhitelist.length, 2,
          reason: 'F3 裁决 A 批准 S:trim，但绝不许出现第 3 条');
      expect(kRoomOracleWhitelist.map((d) => d.caseId).toList(),
          <String>['S:q1', 'S:trim']);
    });

    test('S:q1 的 allowedPaths 恰好 9 条且逐条冻结', () {
      final paths = byId('S:q1').allowedPaths;
      expect(paths.length, 9);
      expect(paths, kFrozenAllowedPaths,
          reason: 'S:q1 路径集合被改动（加路径 / 换顺序 / 用通配取代精确路径）');
    });

    test('S:trim 的 allowedPaths 恰好 1 条且冻结（F3 新增项）', () {
      final trim = byId('S:trim');
      expect(trim.allowedPaths, kFrozenTrimAllowedPaths);
      expect(trim.allowedPaths.length, 1);
      expect(trim.legacyRef, contains('room-model.js'));
      expect(trim.reproInput, contains('rollback'));
      expect(trim.legacyBehavior, contains('StateError'));
      expect(trim.dartBehavior, isNotEmpty);
      // 精确点名，不放宽 coversCase 的前缀匹配（遵守 P4-QA 的 F1 修复）。
      expect(trim.exactCaseNames, <String>{'F:4#900001'});
    });

    test('两条登记的 allowedPaths 都不得出现 `.*` 通配（会整棵子树放过）', () {
      for (final d in kRoomOracleWhitelist) {
        for (final p in d.allowedPaths) {
          expect(p.endsWith('.*'), isFalse, reason: '通配路径 $p 会放过整个子树');
          expect(p.contains('*'), isFalse, reason: '路径 $p 含通配符');
        }
      }
    });

    test('两条登记的 forbiddenKeys 仍是 Q1 的 5 个，不得增删', () {
      for (final d in kRoomOracleWhitelist) {
        expect(
          d.forbiddenKeys,
          <String>['hp', 'hpMax', 'secret', 'kpOnly', 'attrs'],
          reason: '${d.caseId} 的 forbiddenKeys 被放水',
        );
      }
    });
  });

  group('coversCase 匹配范围', () {
    final fixture = RoomOracleFixture.load('room_sequences.json');

    test('只覆盖 S:q1 家族里真有差异的 2 例（#1015 被精确排除）', () {
      final matched = fixture.cases
          .where((c) =>
              kRoomOracleWhitelist.any((d) => d.coversCase(c)))
          .toList();
      expect(matched.length, 2,
          reason: '白名单命中 ${matched.length} 例（期望 2）→ 匹配范围失控');
      for (final c in matched) {
        expect('${c['name']}'.startsWith('S:q1#'), isTrue,
            reason: '命中了非 S:q1 家族用例：${c['name']}');
      }
      // #1015 的重放区间为空、两侧逐字段相等 → 必须回到严格比较
      final c1015 = fixture.cases
          .firstWhere((c) => c['name'] == 'S:q1#1015');
      expect(byId('S:q1').coversCase(c1015), isFalse,
          reason: '#1015 零差异却仍被白名单覆盖 → 将来这 9 条路径上的回归会被静默放过');
      expect(byId('S:q1').excludeCaseNames, <String>{'S:q1#1015'});
      // S:trim 只登记 QA 现造 oracle 的 F:4#900001，不该波及既有 121 例。
      expect(fixture.cases.where((c) => byId('S:trim').coversCase(c)).length, 0,
          reason: 'S:trim 在 room_sequences.json 蹭到了用例');
    });

    test('S:trim 精确点名：只认 F:4#900001，不得顺带放过同 tag 其他例', () {
      final trim = byId('S:trim');
      expect(trim.coversCase(<String, Object?>{'name': 'F:4#900001'}), isTrue);
      expect(trim.coversCase(<String, Object?>{'name': 'F:4#900002'}), isFalse);
      expect(trim.coversCase(<String, Object?>{'name': 'F:0#11'}), isFalse);
      expect(trim.coversCase(<String, Object?>{'name': 'S:trim0'}), isFalse,
          reason: '前缀过宽会重新放开整层等价性');
      expect(trim.coversCase(<String, Object?>{'name': 'S:trim#1'}), isTrue,
          reason: 'caseId#序号 是 fixture 的标准命名法，仍应命中');
      expect(trim.coversCase(<String, Object?>{'tag': 'S:trim'}), isTrue);
    });

    test('前缀过宽回归：S:q10 / S:q1-other 不得被白名单蹭到', () {
      final wl = byId('S:q1');
      // tag 精确匹配仍然是唯一「同名」路径
      expect(wl.coversCase(<String, Object?>{'tag': 'S:q1', 'name': 'x'}), isTrue);
      expect(wl.coversCase(<String, Object?>{'tag': 'S:q1', 'name': 'S:q10'}), isTrue,
          reason: 'tag 精确同名必须命中（tag 是 fixture 的权威标识）');
      // 仅靠 name 时，只认 caseId 本身与 caseId#序号
      expect(wl.coversCase(<String, Object?>{'name': 'S:q1'}), isTrue);
      expect(wl.coversCase(<String, Object?>{'name': 'S:q1#1013'}), isTrue);
      expect(wl.coversCase(<String, Object?>{'name': 'S:q10'}), isFalse,
          reason: 'S:q10 被白名单蹭到（前缀过宽，回到 startsWith 的老问题）');
      expect(wl.coversCase(<String, Object?>{'name': 'S:q1-other'}), isFalse,
          reason: 'S:q1-other 被白名单蹭到（前缀过宽）');
      expect(wl.coversCase(<String, Object?>{'name': 'S:q'}), isFalse);
      expect(wl.coversCase(<String, Object?>{'name': 'S:q2'}), isFalse);
      expect(wl.coversCase(<String, Object?>{}), isFalse);
      expect(wl.coversCase(<String, Object?>{'tag': 42, 'name': null}), isFalse);
    });
  });

  group('比较器强度（白名单外的差异必须报错）', () {
    final paths = byId('S:q1').allowedPaths;

    Map<String, Object?> actualWith(String logText, int privatesLen) =>
        <String, Object?>{
          'state': <String, Object?>{
            'logs': <Object?>[
              <String, Object?>{'seq': 1, 'text': 'a'},
              <String, Object?>{
                'seq': 2,
                'seat': 'p1',
                'text': logText,
                'redacted': true,
                'opp': null,
              },
            ],
            'privates': <Object?>[
              for (var i = 0; i < privatesLen; i++) <String, Object?>{'seq': i},
            ],
          },
        };

    Map<String, Object?> expected() => <String, Object?>{
          'state': <String, Object?>{
            'logs': <Object?>[
              <String, Object?>{'seq': 1, 'text': 'a'},
              <String, Object?>{
                'seq': 2,
                'seat': '',
                'text': 'KP 秘密进行了一次检定',
                'redacted': true,
                'opp': null,
              },
            ],
            'privates': <Object?>[],
          },
        };

    test('白名单内的路径（logs[1].text / seat）允许不同', () {
      final a = actualWith('明文检定', 0);
      asMapLocal(asListLocal(a, 'logs')[1])['seat'] = 'p1';
      expect(
        () => expectJsonMatchExcept(a, expected(), paths),
        returnsNormally,
      );
    });

    test('未登记的 privates 差异必须报错（收窄后不再是「随便改」）', () {
      expect(
        () => expectJsonMatchExcept(actualWith('明文检定', 1), expected(), paths),
        throwsA(isA<TestFailure>()),
        reason: 'privates 已从白名单删除 → 两侧不同必须报错',
      );
    });

    test('白名单外的差异（logs[0].text）必须报错', () {
      final a = actualWith('明文检定', 0);
      asListLocal(a, 'logs')[0] = <String, Object?>{'seq': 1, 'text': '被别人改了'};
      expect(
        () => expectJsonMatchExcept(a, expected(), paths),
        throwsA(isA<TestFailure>()),
        reason: '白名单之外的差异被放过了 → 等价性失效',
      );
    });

    test('白名单外的差异（多出键）必须报错', () {
      final a = actualWith('明文检定', 0);
      asMapLocal(asListLocal(a, 'logs')[1])['extra'] = 1;
      expect(
        () => expectJsonMatchExcept(a, expected(), paths),
        throwsA(isA<TestFailure>()),
      );
    });

    test('白名单内的下标不是「整段 logs 放过」：logs[2] 仍严格比较', () {
      final e = expected();
      final a = actualWith('明文检定', 0);
      asListLocal(e, 'logs').add(<String, Object?>{'seq': 3, 'text': 'x'});
      asListLocal(a, 'logs').add(<String, Object?>{'seq': 3, 'text': 'y'});
      expect(
        () => expectJsonMatchExcept(a, e, paths),
        throwsA(isA<TestFailure>()),
        reason: 'logs[2] 与白名单无关，必须严格比较',
      );
    });
  });
}

/// 宽松取子数组（保持 Object? 形态，供探针就地改）。
List<Object?> asListLocal(Map<String, Object?> root, String key) =>
    (root['state']! as Map)['logs']! as List<Object?>;

Map<String, Object?> asMapLocal(Object? v) => v! as Map<String, Object?>;
