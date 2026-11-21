// ============================================================
// test/room_actions_test.dart — S4.3 动作分发（5488 行）正式验收
//
// 由三个 _s43_probe*_test.dart 临时探针转正而来：探针只 dump 不比较，
// 本文件改成「旧版 JS 当预言机」的严格逐字段深比较 + randUsed 全等。
//
// 数据来源：tool/oracle/dump_p4_actions.js → test/fixtures/room_actions.json
//   （第 4 个独立 fixture，259 例；三个基线 fixture 1100 例）
//
// 覆盖范围：
//   A) actionScript   42 例 —— 主干动作结算结果与旧版 applyAction/intent
//                     逐字段等价（steps/state/logSeq/warnings/roundStarts/
//                     snapshotSeqs）+ randUsed 严格相等；
//   B) behaviorScript 217 例 —— 61 POLICY action × 3 角色 needs 矩阵、
//                     4 个未登记 action × 3 角色默认拒绝、pending 去重、
//                     伪造 ACT 被拒、locked 全局操作锁白名单；
//   C) Dart-only      —— 61 action 分支零缺口静态扫描、逐 action 的
//                     allowed/denied 双侧断言、U4 全量别名结算、
//                     nextTurn / advanceRound / dyingRoundCheck 行为断言、
//                     Q6 休眠项保留检查。
//
// ⚠️ 旧版 applyAction(:1702-1862) 对 room.close / room.end / combat.roll /
//    check.push / state.edit.self 没有分支（只有 POLICY 登记），直调返回空。
//    按 U4 全量裁决，Dart 补齐了这些别名分支，故不做「直调旧版」的等价比较
//    （那等于拿旧版未实现的入口当基准），改由 C 组的 Dart-only 断言验证
//    「分支存在 + 真实结算非空」。char.share / locked:char 依赖 S4.4 的
//    sanitizeSheet（D21），批次 2 落地后已补回等价用例（42/214 例）。
//
// ⚠️ 禁用 contains / 模糊匹配 / 跳过字段：等价性一律走
//    RoomOracleFixture.run 的 expectJsonMatch（键集合双向差集）。
// ============================================================

import 'dart:io';

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_host_intent.dart';
import 'package:dice_realm/domain/room_model_rollback.dart';
import 'package:dice_realm/domain/room_model_state.dart' show needs;
import 'package:dice_realm/domain/room_rules.dart' show CocRules;
import 'package:dice_realm/domain/room_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/oracle.dart' show Lcg, oracleNowMs;
import 'support/room_fakes.dart';
import 'support/room_oracle.dart';

/// 把发送计划转成旧版 `J(out)` 的同形状 JSON。
List<Map<String, Object?>> _plans(List<SendPlan> out) =>
    out.map((s) => s.toJson()).toList();

/// 构造与旧版 `newHost(args)` 完全一致的权威端。
///
/// · meta / snapshotEvery / logCap 从 fixture args 读（缺省与旧版一致）；
/// · 时钟固定 oracleNowMs，与 oracle sandbox 的 Date.now 一致；
/// · **不传 rng**：RoomHostOptions 构造时捕获 `nowRng`，即本 case 的 Lcg，
///   与旧版 `Math.random` 被 patch 成同一条 LCG 序列（randUsed 才严格相等）；
/// · rules 用确定性替身（同 seed 同序列，但不额外消耗全局 Lcg）；
/// · 两名在线玩家 p1/乙、p2/甲 的 nickname 与 at 必须与旧版逐字节一致。
RoomHost _newHost(Map<String, Object?> args) {
  final opts = RoomHostOptions(
    meta: asMap(args['meta']),
    snapshotEvery: (args['snapshotEvery'] as num?)?.toInt() ?? 20,
    logCap: (args['logCap'] as num?)?.toInt() ?? 400,
    now: () => oracleNowMs,
    rules: DeterministicRoomRules(seed: 1),
    madness: const DeterministicRoomMadness(),
    saveStore: InMemoryRoomSaveStore(),
  );
  final h = RoomHost(opts);
  h.attachPeer(<String, Object?>{
    'seat': 'p1',
    'nickname': '甲',
    'at': 1,
  });
  h.attachPeer(<String, Object?>{
    'seat': 'p2',
    'nickname': '乙',
    'at': 2,
  });
  return h;
}

/// 三个 dispatch extension 里出现的 `case 'op':` 词表（静态扫描）。
Set<String> _actionCases() {
  final out = <String>{};
  final re = RegExp(r"case\s+'([^']+)'\s*:");
  for (final name in <String>[
    'room_model_actions_room.dart',
    'room_model_actions_combat.dart',
    'room_model_actions_sheet.dart',
  ]) {
    final f = File('lib/domain/$name');
    for (final m in re.allMatches(f.readAsStringSync())) {
      out.add(m.group(1)!);
    }
  }
  return out;
}

/// fixture 里出现过的 tag 集合（覆盖矩阵零缺口的证据）。
Set<String> _fixtureTags(RoomOracleFixture fixture) => fixture.tags;

void main() {
  final fixture = RoomOracleFixture.load('room_actions.json');
  final cases = _actionCases();
  final tags = _fixtureTags(fixture);
  const roles = <String>['kp', 'player', 'spectator'];

  // ==========================================================
  // A + B) 旧版预言机：261 例严格逐字段深比较 + randUsed
  // ==========================================================
  group('S4.3 动作分发 · 旧版逐字段等价（256 例）', () {
    fixture.run(<String, Object? Function(Map<String, Object?> args)>{
      'actionScript': (a) {
        final h = _newHost(a);
        final List<SendPlan> out;
        if (a['entry'] == 'intent') {
          out = h.intent(jsStr(a['seat']), asMap(a['msg']));
        } else {
          out = h.applyAction(jsStr(a['seat']), asMap(a['p']));
        }
        return <String, Object?>{
          'steps': _plans(out),
          'state': h.state,
          'logSeq': h.log.seq,
          'warnings': h.warnings.map((w) => w.toJson()).toList(),
          'roundStarts': h.roundStarts,
          'snapshotSeqs': h.snapshots.map((s) => s.seq).toList(),
        };
      },
      'behaviorScript': (a) {
        switch (a['kind']) {
          case 'needs':
            return needs(jsStr(a['role']), jsStr(a['action'])).toJson();

          case 'pending':
            final h = _newHost(a);
            final mem = h.roster.get('p1');
            final p = <String, Object?>{
              'op': jsStr(a['actOp']),
              'seat': 'p1',
            };
            final first = h.act('p1', mem, RoomRole.player, p);
            final n1 = h.pending.length;
            final second = h.act('p1', mem, RoomRole.player, p);
            final n2 = h.pending.length;
            return <String, Object?>{
              'first': _plans(first),
              'second': _plans(second),
              'pendingAfterFirst': n1,
              'pendingAfterSecond': n2,
            };

          case 'forged':
            final h = _newHost(a);
            return <String, Object?>{
              'steps': _plans(h.intent('p1', <String, Object?>{
                'op': RoomIntent.act,
                'p': asMap(a['p']),
              })),
            };

          case 'locked':
            final hb = _newHost(a);
            final mem = hb.roster.get('p1');
            // 与旧版 newHost 的锁定构造逐字段一致：body=死亡 触发撕卡锁，
            // madness:[] 必须给（旧版 advanceMadness 直接读该键）。
            mem?['sheet'] = <String, Object?>{
              'status': <String, Object?>{'body': '死亡'},
              'mental': <Object?>[],
              'madness': <Object?>[],
            };
            final blocked = hb.intent('p1', asMap(a['msg']));
            final hf = _newHost(a);
            final free = hf.intent('p1', asMap(a['msg']));
            return <String, Object?>{
              'blocked': _plans(blocked),
              'free': _plans(free),
            };

          default:
            throw ArgumentError('未知 behavior kind: ${a['kind']}');
        }
      },
    });
  });

  // ==========================================================
  // C) 61 个 POLICY action 的覆盖矩阵（逐 action 一个用例）
  // ==========================================================
  group('62 个 POLICY action · 覆盖矩阵零缺口', () {
    test('POLICY 恰好 62 项、且三角色 needs 用例各 62 条', () {
      expect(kRoomPolicy.length, 62);
      for (final role in roles) {
        final n = tags
            .where((t) =>
                t.startsWith('A:needs:') && t.endsWith(':$role'))
            .length;
        expect(n, 62,
            reason: '角色 $role 的 needs 覆盖用例应恰好 62 条，实际 $n');
      }
      final unregistered = tags
          .where((t) => t.startsWith('A:needs-unregistered:'))
          .length;
      expect(unregistered, 12,
          reason: '4 个未登记 action × 3 角色 = 12 条');
    });

    test('三组 dispatch 分支零缺口（61 action 全部有 case）', () {
      final missing = kRoomPolicy.keys.where((a) => !cases.contains(a)).toList();
      expect(missing, isEmpty,
          reason: '以下 POLICY action 在三个 dispatch 文件里没有分支: $missing');
      // 额外的 6 个非 POLICY 分支（含 Q6 休眠的 rollback.turn）也必须保留。
      for (final extra in <String>[
        'combat.turnState',
        'dice.direct',
        'sancheck',
        'opposed',
        'state.apply',
        'rollback.turn',
      ]) {
        expect(cases.contains(extra), isTrue,
            reason: '额外分支 $extra 不许删（Q6 休眠保留）');
      }
    });

    // 逐 action 一个 test：用例名直接就是 allowed/denied 侧的证据。
    for (final action in kRoomPolicy.keys) {
      test('POLICY「$action」allowed/denied 双侧 + 分支存在', () {
        final entry = kRoomPolicy[action]!;
        final allowedRoles = roles
            .where((r) => needs(r, action).allowed)
            .toList();
        final deniedRoles = roles
            .where((r) => !needs(r, action).allowed)
            .toList();

        // allowed 侧：登记在 POLICY.roles 里的角色全部通过，且 confirm 一致。
        expect(allowedRoles, isNotEmpty,
            reason: '$action 至少有一个角色被允许');
        for (final r in allowedRoles) {
          expect(entry.roles.contains(r), isTrue,
              reason: '$action 对 $r 返回 allowed，但 POLICY.roles 未登记');
          expect(needs(r, action).confirm, entry.confirm,
              reason: '$action 对 $r 的 confirm 必须与 POLICY 一致');
        }
        // denied 侧：未登记角色一律拒绝，且 confirm 为 null。
        expect(deniedRoles, isNotEmpty,
            reason: '$action 至少有一个角色被拒绝（双侧覆盖）');
        for (final r in deniedRoles) {
          expect(needs(r, action).allowed, isFalse);
          expect(needs(r, action).confirm, isNull);
          expect(entry.roles.contains(r), isFalse,
              reason: '$action 对 $r 返回 denied，但 POLICY.roles 却登记了');
        }
        // spectator 恒被拒（POLICY 里没有任何 roles 含 spectator）。
        expect(needs('spectator', action).allowed, isFalse);
        // fixture 里该 action 的三角色 needs 用例必须齐全。
        for (final r in roles) {
          expect(tags.contains('A:needs:$action:$r'), isTrue,
              reason: 'fixture 缺 A:needs:$action:$r');
        }
        // 实现里必须有分支。
        expect(cases.contains(action), isTrue,
            reason: '$action 在三个 dispatch 文件里没有 case 分支');
      });
    }

    test('未登记 action 一律拒绝（Q6：rollback.turn 已摘除但分支保留）', () {
      for (final action in <String>[
        'rollback.turn',
        '__unknown__',
        'fake.action',
        '',
      ]) {
        expect(kRoomPolicy.containsKey(action), isFalse,
            reason: '$action 不许登记进 POLICY');
        for (final r in roles) {
          expect(needs(r, action).allowed, isFalse);
          expect(needs(r, action).confirm, isNull);
        }
        for (final r in roles) {
          expect(tags.contains('A:needs-unregistered:$action:$r'), isTrue,
              reason: 'fixture 缺 A:needs-unregistered:$action:$r');
        }
      }
      expect(cases.contains('rollback.turn'), isTrue,
          reason: 'applyAction 的 rollback.turn 分支按 Q6 休眠保留');
    });

    test('pending 去重 / 伪造 ACT / locked 白名单用例齐全', () {
      for (final op in <String>[
        'madness.cure',
        'sheet.healwound',
        'aid.apply',
      ]) {
        expect(tags.contains('A:pending:$op'), isTrue);
      }
      expect(tags.where((t) => t.startsWith('A:forged:')).length, 5);
      expect(tags.where((t) => t.startsWith('A:locked:')).length, 11);
    });

    test('U4 全量：旧版 applyAction 无分支的 5 个别名在 Dart 里仍真实结算', () {
      // 这 5 个 op 在旧版 room-model.js:1702-1862 里没有 applyAction 分支，
      // 只有 POLICY 登记（真实入口是传输层直调 / INTENT 链路）。Dart 按 U4
      // 「动作分发全量、不预先降级」补齐了分支，这里证明不是空壳。
      const probes = <String, Map<String, Object?>>{
        'room.close': <String, Object?>{'op': 'room.close'},
        'room.end': <String, Object?>{'op': 'room.end'},
        'combat.roll': <String, Object?>{
          'op': 'combat.roll',
          'expr': '1D100',
          'label': '攻击',
          'result': <String, Object?>{
            'value': 42,
            'level': 2,
            'levelKey': 'REGULAR',
            'levelText': '成功',
            'rolls': <Object?>[42],
          },
        },
        'check.push': <String, Object?>{
          'op': 'check.push',
          'skill': '侦查',
          'desc': '找线索',
        },
        'state.edit.self': <String, Object?>{
          'op': 'state.edit.self',
          'seat': 'p1',
          'status': <String, Object?>{'currentHP': 8},
        },
      };
      for (final entry in probes.entries) {
        final op = entry.key;
        expect(cases.contains(op), isTrue,
            reason: '$op 必须在三个 dispatch 文件里有真实分支');
        expect(kRoomPolicy.containsKey(op), isTrue,
            reason: '$op 必须在 POLICY 里登记（needs 覆盖）');
        final h = RoomHost(roomHostOpts());
        h.attachPeer(<String, Object?>{'seat': 'p1', 'at': 1});
        final out = h.applyAction(kHostSeat, entry.value);
        expect(out.isNotEmpty, isTrue,
            reason: '$op 在 Dart 里必须产生真实结算计划，不许是空壳分支');
      }
    });
  });

  // ==========================================================
  // D) nextTurn / advanceRound / dyingRoundCheck 行为断言
  // ==========================================================
  group('回合引擎 · nextTurn / advanceRound / dyingRoundCheck', () {
    RoomHost combatHost() {
      final h = RoomHost(roomHostOpts());
      h.applyAction(kHostSeat, <String, Object?>{
        'op': 'combat.set',
        'combat': <String, Object?>{
          'order': <Object?>[
            <String, Object?>{
              'actorId': 'a1',
              'name': '甲',
              'slot': 1,
              'totalSlots': 1,
            },
            <String, Object?>{
              'actorId': 'a2',
              'name': '乙',
              'slot': 1,
              'totalSlots': 1,
            },
          ],
          'turn': 0,
          'round': 1,
        },
      });
      // TURNSTATE 属战斗类事件，plan() 只发给在线成员；没有花名册时
      // 会被整条裁掉（这正是无战斗房间收不到回合事件的原因）。
      h.attachPeer(<String, Object?>{'seat': 'p1', 'at': 1});
      h.attachPeer(<String, Object?>{'seat': 'p2', 'at': 2});
      return h;
    }

    /// 从发送计划里取事件类型（RoomEnvelope 是 sealed 基类，只有 k/toJson）。
    String evtType(SendPlan s) =>
        jsStr(asMap(s.msg.toJson())['t']);
    Map<String, Object?> evtPayload(SendPlan s) =>
        asMap(asMap(s.msg.toJson())['p']);

    test('nextTurn：无战斗时回定向提示、有战斗时推进 turn 并发 TURNSTATE', () {
      final empty = RoomHost(roomHostOpts());
      final noCombat = empty.nextTurn();
      expect(noCombat.length, 1);
      expect(evtType(noCombat.single), RoomEvt.log);
      expect(evtPayload(noCombat.single)['text'],
          '当前没有战斗，无法推进行动轮');

      final h = combatHost();
      final stepped = h.nextTurn();
      final ts = stepped
          .where((s) => evtType(s) == RoomEvt.turnstate)
          .toList();
      expect(ts.length, 2, reason: '推进一轮必须按在线成员逐人发 TURNSTATE');
      // 逐人裁剪的载荷形状一致，两个收件人都要是同一份 turn/round。
      for (final s in ts) {
        expect(evtPayload(s)['turn'], 1);
        expect(evtPayload(s)['round'], 1);
      }
      final alerts = stepped
          .where((s) => evtType(s) == RoomEvt.turnAlert)
          .toList();
      expect(alerts.length, 1);
      expect(evtPayload(alerts.single)['roundChanged'], isFalse);
    });

    test('nextTurn：跨轮边界自动调 advanceRoundInto（ROUND + TEMP_COMMIT）', () {
      final h = combatHost();
      final all = <SendPlan>[...h.nextTurn(), ...h.nextTurn()];
      final rounds =
          all.where((s) => evtType(s) == RoomEvt.round).toList();
      final commits =
          all.where((s) => evtType(s) == RoomEvt.tempCommit).toList();
      expect(rounds.length, 1,
          reason: '第二次 nextTurn 由 slot1 回到 slot0，必须跨轮');
      expect(commits.length, 1,
          reason: '跨轮必须发 TEMP_COMMIT（临时状态结算）');
      expect(evtPayload(rounds.single)['round'], 2);
      expect(evtPayload(commits.single)['round'], 2);
    });

    test('advanceRound：统一出口发 ROUND 与 TEMP_COMMIT，且每条计划都记账', () {
      final h = RoomHost(roomHostOpts());
      final before = h.log.seq;
      final out = h.advanceRound(3);
      expect(
          out.where((s) => evtType(s) == RoomEvt.round).length, 1);
      expect(
          out.where((s) => evtType(s) == RoomEvt.tempCommit).length, 1);
      expect(h.log.seq, before + out.length,
          reason: '每条发送计划都必须经 apply 单口记账');
    });

    test('dyingRoundCheck：返回体 4 键、stable 与 dead 严格互斥', () {
      const rules = CocRules();
      final rng = Lcg(1);
      final r = rules.dyingRoundCheck(50, rng.call);
      expect(r.keys.toSet(),
          <String>{'check', 'stable', 'dead', 'summary'});
      expect(r['stable'], isA<bool>());
      expect(r['dead'], isA<bool>());
      expect(r['dead'], isNot(r['stable']),
          reason: '濒死判定 stable / dead 必须互斥');
      expect(r['check'], isA<Map>());
      expect(asMap(r['check']).containsKey('value'), isTrue);
      expect(rng.used, greaterThan(0), reason: '濒死 CON 检定必须真掷一次骰');
    });
  });
}
