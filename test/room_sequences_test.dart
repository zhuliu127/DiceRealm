// ============================================================
// test/room_sequences_test.dart — F03 `clientScript` 等价性 + S4.1/S4.2 行为断言
//
// A) fixture 驱动：room_sequences.json 的 **121 例全量实跑**
//    · clientScript 27 例：steps / lastSeq / gapFrom / rejected /
//      lastStateSeq / state / sheetState 逐字段深比较 + randUsed 全等。
//      这是 P0-M05「receive 1→1→3→2 返回体与内部快照」的最硬证据：
//      返回体 6 种键集合一个不多一个不少（§0.3 禁止凭空加 gapFrom）。
//    · hostScript 94 例：attach/detach/emit/emitLocal/syncFor/makeSync/
//      intent/rollback/rollbackPlan/setStatus/closeRoom/endSession/kick/
//      nextTurn/applyAction/save 全 op 词表，返回体照搬
//      dump_p4_room.js:943-992（steps/state/logSeq/log/warnings/
//      snapshotSeqs/roundStarts/save/saveKeys），同样严格深比较。
// B) Dart-only：skip 与 evt 共用 gate、canFill 增量补齐不叠全量、
//    P0-M02 真实 `intent('host', CHAT)` 1 条广播、CLOSED/ENDED/SUSPENDED 口径。
//
// ⚠️ T05：已去掉 only，121 例（27 + 94）全部实跑，不留跳过。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_client.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_host_intent.dart';
import 'package:dice_realm/domain/room_model_rollback.dart';
import 'package:dice_realm/domain/room_model_save.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';
import 'support/room_oracle.dart';

/// 把发送计划列表转成旧版 `J(out)` 的同形状 JSON。
List<Map<String, Object?>> _plans(List<SendPlan> out) =>
    out.map((s) => s.toJson()).toList();

/// 构造与 `runHostScript` 里 `new M.Host(args)` 完全一致的权威端。
RoomHost _hostFromArgs(Map<String, Object?> a) => RoomHost(roomHostOpts(
      meta: asMap(a['meta']),
      snapshotEvery: (a['snapshotEvery'] as num?)?.toInt() ?? 20,
      logCap: (a['logCap'] as num?)?.toInt() ?? 400,
    ));

void main() {
  final fixture = RoomOracleFixture.load('room_sequences.json');

  // ==========================================================
  // A) F03 / S4.1~S4.4 全量 fixture：严格逐字段比较 + randUsed
  // ==========================================================
  fixture.run(
    <String, Object? Function(Map<String, Object?> args)>{
      'hostScript': (a) {
        final h = _hostFromArgs(a);
        final steps = <Object?>[];
        Map<String, Object?>? saveOut;
        for (final opRaw in asList(a['ops'])) {
          final op = asMap(opRaw);
          switch (op['op']) {
            case 'attach':
              steps.add(h.attachPeer(asMap(op['m'])).toJson());
              break;
            case 'detach':
              steps.add(_plans(h.detachPeer(jsStr(op['seat']))));
              break;
            case 'emit':
              final rec = h.emit(
                jsStr(op['t']),
                op['p'] == null ? <String, Object?>{} : asMap(op['p']),
                vis: op['vis'] == null ? RoomVis.public : jsStr(op['vis']),
                to: op['to'] == null ? null : jsStr(op['to']),
              );
              steps.add(<String, Object?>{
                'seq': rec.seq,
                'plan': jsTruthy(op['plan']) ? _plans(h.plan(rec)) : null,
              });
              break;
            case 'emitLocal':
              final rec = h.emitLocal(
                jsStr(op['t']),
                op['p'] == null ? <String, Object?>{} : asMap(op['p']),
              );
              steps.add(<String, Object?>{
                'seq': rec.seq,
                'evt': asMap(rec.toWireJson())['evt'],
              });
              break;
            case 'syncFor':
              steps.add(h.syncFor(jsStr(op['seat'])).toJson());
              break;
            case 'makeSync':
              steps.add(h.makeSync(jsStr(op['seat'])).toJson());
              break;
            case 'intent':
              steps.add(_plans(h.intent(jsStr(op['seat']), asMap(op['msg']))));
              break;
            case 'rollback':
              steps.add(h.rollback((op['before'] as num).toInt()).toJson());
              break;
            case 'rollbackPlan':
              steps.add(_plans(h.rollbackPlan((op['before'] as num).toInt())));
              break;
            case 'setStatus':
              steps.add(_plans(h.setStatus(jsStr(op['s']))));
              break;
            case 'closeRoom':
              steps.add(_plans(h.closeRoom()));
              break;
            case 'endSession':
              steps.add(_plans(h.endSession()));
              break;
            case 'kick':
              steps.add(_plans(h.kick(jsStr(op['seat']))));
              break;
            case 'nextTurn':
              steps.add(_plans(h.nextTurn()));
              break;
            case 'applyAction':
              steps.add(_plans(h.applyAction(
                jsStr(op['seat']),
                op['p'] == null ? <String, Object?>{} : asMap(op['p']),
              )));
              break;
            case 'save':
              saveOut = h.save();
              steps.add(null);
              break;
            default:
              throw ArgumentError('未知 host op ${op['op']}');
          }
        }
        return <String, Object?>{
          'steps': steps,
          'state': h.state,
          'logSeq': h.log.seq,
          'log': h.log.items
              .map((r) => <String, Object?>{
                    'seq': r.seq,
                    't': r.evt.t,
                    'vis': r.evt.vis,
                    'to': r.evt.to,
                  })
              .toList(),
          'warnings': h.warnings.map((w) => w.toJson()).toList(),
          'snapshotSeqs': h.snapshots.map((s) => s.seq).toList(),
          'roundStarts': h.roundStarts,
          'save': saveOut,
          'saveKeys': saveOut?.keys.toList(),
        };
      },
      'clientScript': (a) {
        final c = RoomClient(
          seat: a['seat'] == null ? '' : jsStr(a['seat']),
          role: a['role'] == null ? RoomRole.player : jsStr(a['role']),
          // 旧版 `meta: args.meta || {}`：缺失传空 Map（不是 undefined），
          // 否则 emptyState 的 allowSpectate 默认值会不一样。
          meta: asMap(a['meta']),
        );
        final steps = <Object?>[];
        for (final opRaw in asList(a['ops'])) {
          final op = asMap(opRaw);
          switch (op['op']) {
            case 'receive':
              steps.add(c.receive(op['raw']).toJson());
              break;
            case 'intent':
              steps.add(c.intent(jsStr(op['k']), asMap(op['p'])).toJson());
              break;
            case 'resyncIntent':
              steps.add(c.resyncIntent().toJson());
              break;
            case 'resyncDiag':
              steps.add(c.resyncDiag().toJson());
              break;
            case 'applySheetState':
              steps.add(
                c.applySheetState(
                  op['seq'],
                  op['patch'] == null ? null : asMap(op['patch']),
                ).toJson(),
              );
              break;
            case 'member':
              steps.add(c.member(op['seat'] == null ? null : jsStr(op['seat'])));
              break;
            case 'isReady':
              steps.add(c.isReady());
              break;
            default:
              throw ArgumentError('未知 client op ${op['op']}');
          }
        }
        return <String, Object?>{
          'steps': steps,
          'lastSeq': c.lastSeq,
          'gapFrom': c.gapFrom,
          'rejected': c.rejected,
          'lastStateSeq': c.lastStateSeq,
          'state': c.state,
          'sheetState': c.sheetState,
        };
      },
    },
  );

  // ==========================================================
  // B) Dart-only 行为断言
  // ==========================================================

  test('P0-M05：receive 1→1→3→2 返回体与内部快照（§0.3 无 gapFrom 键）', () {
    final c = RoomClient(seat: 'p1');
    final r1 = c
        .receive(<String, Object?>{'k': 'evt', 'seq': 1, 't': 'log', 'p': <String, Object?>{}})
        .toJson();
    final r2 = c
        .receive(<String, Object?>{'k': 'evt', 'seq': 1, 't': 'log', 'p': <String, Object?>{}})
        .toJson();
    final r3 = c
        .receive(<String, Object?>{'k': 'evt', 'seq': 3, 't': 'log', 'p': <String, Object?>{}})
        .toJson();
    final r4 = c
        .receive(<String, Object?>{'k': 'evt', 'seq': 2, 't': 'log', 'p': <String, Object?>{}})
        .toJson();

    expectJsonMatch(r1, <String, Object?>{
      'kind': 'evt', 'changed': true, 'seq': 1, 't': 'log', 'filled': false,
    });
    expectJsonMatch(r2, <String, Object?>{
      'kind': 'evt', 'dup': true, 'gap': false, 'from': 1, 'got': 1,
    });
    expectJsonMatch(r3, <String, Object?>{
      'kind': 'evt', 'dup': false, 'gap': true, 'from': 1, 'got': 3,
    });
    expectJsonMatch(r4, <String, Object?>{
      'kind': 'evt', 'changed': true, 'seq': 2, 't': 'log', 'filled': true,
    });
    // 返回体一律没有 gapFrom 键（内部字段），拒绝分支用的是 from。
    for (final r in <Map<String, Object?>>[r1, r2, r3, r4]) {
      expect(r.containsKey('gapFrom'), isFalse);
    }
    expect(c.lastSeq, 2);
    expect(c.gapFrom, 0, reason: '连续序号收到后必须清缺口标记');
    expect(c.rejected, 1);
  });

  test('P0-M05：skip 与 evt 共用同一套 gate（重复/跳号/补齐 filled）', () {
    final c = RoomClient(seat: 'p1');
    expectJsonMatch(
      c.receive(<String, Object?>{'k': 'skip', 'seq': 1}).toJson(),
      <String, Object?>{
        'kind': 'skip', 'changed': false, 'seq': 1, 'filled': false,
      },
    );
    expect(
      c.receive(<String, Object?>{'k': 'evt', 'seq': 2, 't': 'log', 'p': <String, Object?>{}}).kind,
      'evt',
    );
    // 重复序号：skip 与 evt 判据必须一致
    expectJsonMatch(
      c.receive(<String, Object?>{'k': 'skip', 'seq': 2}).toJson(),
      <String, Object?>{
        'kind': 'skip', 'dup': true, 'gap': false, 'from': 2, 'got': 2,
      },
    );
    // 跳号：skip 也要报缺口，不能悄悄放过
    expectJsonMatch(
      c.receive(<String, Object?>{'k': 'skip', 'seq': 4}).toJson(),
      <String, Object?>{
        'kind': 'skip', 'dup': false, 'gap': true, 'from': 2, 'got': 4,
      },
    );
    expect(c.gapFrom, 2);
    // 补齐的第一条（无论是 evt 还是 skip）都要带 filled:true
    expectJsonMatch(
      c.receive(<String, Object?>{'k': 'evt', 'seq': 3, 't': 'log', 'p': <String, Object?>{}}).toJson(),
      <String, Object?>{
        'kind': 'evt', 'changed': true, 'seq': 3, 't': 'log', 'filled': true,
      },
    );
    expect(c.gapFrom, 0);
  });

  test('P0-M05：sync 重置 lastSeq / gapFrom；intent 与未知 k 一律 ignore', () {
    final c = RoomClient(seat: 'p1');
    c.receive(<String, Object?>{'k': 'evt', 'seq': 1, 't': 'log', 'p': <String, Object?>{}});
    c.receive(<String, Object?>{'k': 'evt', 'seq': 3, 't': 'log', 'p': <String, Object?>{}});
    expect(c.gapFrom, 1);
    final s = c.receive(<String, Object?>{
      'k': 'sync',
      'seq': 9,
      'state': <String, Object?>{'meta': <String, Object?>{}, 'seq': 9},
    });
    expectJsonMatch(s.toJson(), <String, Object?>{
      'kind': 'sync', 'changed': true, 'seq': 9,
    });
    expect(c.lastSeq, 9);
    expect(c.gapFrom, 0);
    expect(c.state['seq'], 9);
    expect(c.receive(<String, Object?>{'k': 'intent', 'op': 'chat'}).toJson(),
        <String, Object?>{'kind': 'ignore'});
    expect(c.receive(<String, Object?>{'k': 'host.gone'}).toJson(),
        <String, Object?>{'kind': 'ignore'});
    expect(c.receive('not json').toJson(), <String, Object?>{'kind': 'ignore'});
  });

  test('P0-M06：applySheetState 幂等（同 seq 只生效一次，seq<=0 不生效）', () {
    final c = RoomClient(seat: 'p1');
    expectJsonMatch(
      c.applySheetState(0, <String, Object?>{'hp': 3}).toJson(),
      <String, Object?>{'applied': false, 'seq': 0},
    );
    expectJsonMatch(
      c.applySheetState(5, <String, Object?>{'hp': 3}).toJson(),
      <String, Object?>{'applied': true, 'seq': 5},
    );
    expectJsonMatch(
      c.applySheetState(5, <String, Object?>{'hp': 99}).toJson(),
      <String, Object?>{'applied': false, 'seq': 5, 'dup': true},
    );
    expect(c.sheetState, <String, Object?>{'hp': 3});
    expect(c.lastStateSeq, 5);
  });

  test('P0-M05 / S4.2：canFill 增量补齐不叠全量；超窗口才发全量 sync', () {
    final h = RoomHost(roomHostOpts());
    for (var i = 1; i <= 3; i++) {
      h.emit(RoomEvt.log, <String, Object?>{'text': 'e$i'},
          vis: RoomVis.public);
    }
    final inc = h.intent('p1', <String, Object?>{
      'op': RoomIntent.sync,
      'p': <String, Object?>{'lastSeq': 1},
    });
    expect(inc.length, 2, reason: 'seq2/seq3 两条增量，不许叠全量 sync');
    for (final s in inc) {
      expect(s.to, 'p1');
      expect(s.msg.k, 'evt', reason: '增量补齐里出现全量 sync 会让后续事件全被判重复');
    }

    final h2 = RoomHost(roomHostOpts(logCap: 2));
    for (var i = 1; i <= 4; i++) {
      h2.emit(RoomEvt.log, <String, Object?>{'text': 'e$i'});
    }
    expect(h2.log.canFill(1), isFalse, reason: '窗口已被裁掉 → 必须全量');
    final full = h2.intent('p1', <String, Object?>{
      'op': RoomIntent.sync,
      'p': <String, Object?>{'lastSeq': 1},
    });
    expect(full.length, 1);
    expect(full.single.msg.k, 'sync');
    expect(full.single.to, 'p1');
  });

  test('P0-M02 真实断言：intent("host", CHAT) 产出 1 条广播（按 seat 认 KP）', () {
    final h = RoomHost(roomHostOpts());
    h.attachPeer(<String, Object?>{'seat': 'p1', 'at': 1});
    expect(h.roster.get(kHostSeat), isNull, reason: '房主恒不在花名册里');
    final out = h.intent(kHostSeat, <String, Object?>{
      'op': RoomIntent.chat,
      'p': <String, Object?>{'text': 'KP 说话'},
    });
    expect(out.length, 1,
        reason: 'KP 发言不能走旁路，也不该被当旁观者拒绝');
    expect(out.single.to, '*');
    expect(out.single.msg.k, 'evt');
    final msg = out.single.msg.toJson();
    expect(msg['k'], 'evt');
    expect(msg['t'], RoomEvt.chat);
    expect(msg['p'], <String, Object?>{
      'seat': kHostSeat,
      'nickname': 'KP',
      'text': 'KP 说话',
      'at': 1700000000000,
      'kind': 'user',
    });
    // 对照：非 host 且查不到成员 → 旁观者，READY 要被拒绝而不是广播
    final outSpec = h.intent('stranger', <String, Object?>{
      'op': RoomIntent.ready,
      'p': <String, Object?>{'ready': true},
    });
    // 定向 PRIVATE 会按 SEAT 规则给收件人发 evt、给其余在线者发 skip 水位，
    // 所以条数 > 1 是**正确**的；关键是没有 `to:'*'` 广播。
    expect(outSpec.any((s) => s.to == '*'), isFalse,
        reason: '越权提示绝不广播');
    expect(
      outSpec.any((s) => s.to == 'stranger' && s.msg.k == 'evt'),
      isTrue,
      reason: '旁观者本人要收到定向拒绝提示',
    );
  });

  test('P0-M03：CLOSED 只置 status 不写 ended；ENDED 才写 ended；SUSPENDED 独立', () {
    final h1 = RoomHost(roomHostOpts());
    h1.closeRoom();
    final m1 = asMap(h1.state['meta']);
    expect(m1['status'], RoomStatus.closed);
    expect(m1.containsKey('ended'), isFalse,
        reason: '旧客户端把 ended 当终止，CLOSED 不许写');

    final h2 = RoomHost(roomHostOpts());
    h2.endSession();
    final m2 = asMap(h2.state['meta']);
    expect(m2['status'], RoomStatus.closed);
    expect(m2['ended'], isTrue);

    final h3 = RoomHost(roomHostOpts());
    h3.setStatus(RoomStatus.suspended);
    final m3 = asMap(h3.state['meta']);
    expect(m3['status'], RoomStatus.suspended);
    expect(m3.containsKey('ended'), isFalse);

    // KICK 置 CLOSED，同样不写 ended
    final h4 = RoomHost(roomHostOpts());
    h4.attachPeer(<String, Object?>{'seat': 'p1', 'at': 1});
    h4.kick('p1');
    final m4 = asMap(h4.state['meta']);
    expect(m4['status'], RoomStatus.closed);
    expect(m4.containsKey('ended'), isFalse);
  });
}
