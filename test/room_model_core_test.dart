// ============================================================
// test/room_model_core_test.dart — D10/D11/D12/D13 等价性 + 骨架不变式（T03）
//
// 分两块：
//   A) fixture 驱动（room_model.json 的 M-state / M-log / M-reduce / M-envelope 子集）
//      —— 逐字段深比较 + randUsed 全等；
//   B) Dart-only 不变式（不进 fixture，防「等价但结构错了」）：
//      · emptyState 18 键且键序固定
//      · EVT.TEMP_COMMIT 刻意无分支（只写 seq）
//      · needs() 对未登记 action 一律拒绝（Q6：rollback.turn 已摘除）
//      · apply 是唯一写口（静态扫描 + persist:false 必须带 seq）
//
// ⚠️ 本文件只覆盖到 D13；plan/crop/sync 的可见性断言在 room_visibility_test.dart。
// ============================================================

import 'dart:io';

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_envelope.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_log.dart';
import 'package:dice_realm/domain/room_model_reduce.dart';
import 'package:dice_realm/domain/room_model_state.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_oracle.dart';

Map<String, Object?> _m(Object? v) => asMap(v);

/// 旧版 `Log.push` / `Log.since` 的记录形状由 [LogRecord.toWireJson] 收口：
/// `{seq, evt:{t[,vis,to],p}}`（evt **不带** seq，键集合 = push 入参键集合）。
///
/// 不能手写 4 键 `evt`：fixture 里直接 `new M.Log().push({t,p})` 的入参根本
/// 没有 vis/to，硬补会触发「键集合不一致，多 {vis,to}」。
Map<String, Object?> recJson(LogRecord rec) => rec.toWireJson();

/// 旧版 EVT 的 JS 成员名 → 值（只有 3 个缩写需要特判）
String _evtOf(String key) {
  switch (key) {
    case 'TEMP_COMMIT':
      return RoomEvt.tempCommit;
    case 'SAVE_SYNC':
      return RoomEvt.saveSync;
    case 'TURN_ALERT':
      return RoomEvt.turnAlert;
    case 'SCENE_CHECK':
      return RoomEvt.sceneCheck;
    default:
      return key.toLowerCase();
  }
}

/// 旧版 INTENT 的 JS 成员名 → 值
String _intentOf(String key) {
  switch (key) {
    case 'STATE_SYNC':
      return RoomIntent.stateSync;
    case 'SAN_CHECK':
      return RoomIntent.sanCheck;
    default:
      return key.toLowerCase();
  }
}

Object? _constOf(String name) {
  switch (name) {
    case 'ROLE':
      return <String, Object?>{
        'KP': RoomRole.kp,
        'PLAYER': RoomRole.player,
        'SPECTATOR': RoomRole.spectator,
      };
    case 'STATUS':
      return <String, Object?>{
        'RECRUITING': RoomStatus.recruiting,
        'IN_GAME': RoomStatus.inGame,
        'CLOSED': RoomStatus.closed,
        'SUSPENDED': RoomStatus.suspended,
      };
    case 'STATUS_TEXT':
      return RoomStatus.text;
    case 'MODE':
      return <String, Object?>{
        'EXPLORATION': RoomMode.exploration,
        'COMBAT': RoomMode.combat,
      };
    case 'REWIND':
      return <String, Object?>{
        'IDLE': RoomRewind.idle,
        'VOTING': RoomRewind.voting,
        'DONE': RoomRewind.done,
        'FAILED': RoomRewind.failed,
      };
    case 'CONFIRM':
      return <String, Object?>{
        'NONE': null,
        'TWICE': RoomConfirm.twice,
        'KP': RoomConfirm.kp,
        'OWNER': RoomConfirm.owner,
        'ALL': RoomConfirm.all,
      };
    case 'VIS':
      return <String, Object?>{
        'PUBLIC': RoomVis.public,
        'KP': RoomVis.kp,
        'SEAT': RoomVis.seat,
      };
    case 'SECRET_KEYS':
      return kSecretKeys;
    case 'HOST_SEAT':
      return kHostSeat;
    default:
      throw ArgumentError('未知常量组 $name');
  }
}

void main() {
  final fixture = RoomOracleFixture.load('room_model.json');

  /// 本批（D10~D13）已实现的 handler 集合。
  final batch = <String>{
    'Mconst',
    'MconstMember',
    'needs',
    'allowed',
    'reduce',
    'hasSecret',
    'scrub',
    'ruleOptsOf',
    'bodyView',
    'bodyForHp',
    'migrateBodyStatus',
    'validCode',
    'cleanText',
    'inviteLink',
    'readInvite',
    'emptyState',
    'clone',
    'syncMsg',
    'evtMsg',
    'skipMsg',
    'intentMsg',
    'parse',
    'logScript',
    'rosterScript',
  };

  final handlers = <String, Object? Function(Map<String, Object?> args)>{
    'Mconst': (a) => _constOf(a['name']! as String),
    'MconstMember': (a) {
      final key = a['key']! as String;
      switch (a['group']) {
        case 'EVT':
          return _evtOf(key);
        case 'INTENT':
          return _intentOf(key);
        case 'POLICY':
          return kRoomPolicy[key]!.toJson();
        default:
          throw ArgumentError('未知常量组 ${a['group']}');
      }
    },
    'needs': (a) =>
        needs(jsStr(a['role']), jsStr(a['action'])).toJson(),
    'allowed': (a) => allowed(jsStr(a['role']), jsStr(a['action'])),

    'reduce': (a) {
      final st = emptyRoomState(_m(a['meta']));
      final pre = _m(a['state']);
      pre.forEach((k, v) {
        st[k] = roomClone(v);
      });
      final e = _m(a['evt']);
      return reduceRoomState(
        st,
        RoomEvent(
          t: jsStr(e['t']),
          p: _m(e['p']),
          vis: e['vis'] == null ? null : jsStr(e['vis']),
          to: e['to'] == null ? null : jsStr(e['to']),
          seq: jsNum(e['seq']),
        ),
      );
    },

    'hasSecret': (a) => hasSecret(a['p']),
    'scrub': (a) => scrub(a['p']),
    'ruleOptsOf': (a) => ruleOptsOf(_m(a['meta'])),
    'bodyView': (a) => bodyView(a['status'] == null ? null : _m(a['status'])),
    'bodyForHp': (a) => bodyForHp(a['hp'], a['maxHP']),
    'migrateBodyStatus': (a) {
      final status = a['status'];
      if (status == null) return null;
      final st = _m(roomClone(status));
      migrateBodyStatus(st);
      return st;
    },
    'validCode': (a) => validCode(a['c']),
    'cleanText': (a) => cleanText(
          a['s'],
          a['max'] == null ? null : jsNum(a['max']),
        ),
    'inviteLink': (a) => inviteLink(
          jsStr(a['pageUrl']),
          jsStr(a['code']),
          a['serverBase'] == null ? null : jsStr(a['serverBase']),
        ),
    'readInvite': (a) => readInvite(a['s']),
    'emptyState': (a) =>
        emptyRoomState(a['meta'] == null ? null : _m(a['meta'])),
    'clone': (a) => roomClone(a['x']),

    'syncMsg': (a) => syncMsg(jsNum(a['seq']), _m(a['state'])).toJson(),
    'evtMsg': (a) {
      final r = _m(a['rec']);
      final e = _m(r['evt']);
      return evtMsg(LogRecord(
        jsNum(r['seq']),
        RoomEvent(
          t: jsStr(e['t']),
          p: _m(e['p']),
          vis: e['vis'] == null ? null : jsStr(e['vis']),
          to: e['to'] == null ? null : jsStr(e['to']),
        ),
      )).toJson();
    },
    'skipMsg': (a) => skipMsg(jsNum(a['seq'])).toJson(),
    'intentMsg': (a) => intentMsg(jsStr(a['op']), _m(a['p'])).toJson(),
    'parse': (a) => parseRoomRaw(a['raw']),

    'logScript': (a) {
      final spec = _m(a['ops']);
      final log = RoomLog(cap: jsNum(spec['cap']));
      final out = <Object?>[];
      for (final opRaw in asList(spec['ops'])) {
        final op = _m(opRaw);
        switch (op['op']) {
          case 'push':
            final e = _m(op['evt']);
            // 旧版 Log.push 原样保存入参对象：入参没有 vis/to，记录里也没有。
            // 把入参形状作为 wire 交给日志，push 返回值与 since() 结果都由
            // LogRecord.toWireJson() 统一收口（domain 层，不在测试里拼键）。
            final rec = log.push(
              RoomEvent(
                t: jsStr(e['t']),
                p: _m(e['p']),
                vis: e['vis'] == null ? null : jsStr(e['vis']),
                to: e['to'] == null ? null : jsStr(e['to']),
              ),
              wire: <String, Object?>{...e},
            );
            out.add(rec.toWireJson());
            break;
          case 'since':
            out.add(log.since(jsNum(op['fromSeq'])).map(recJson).toList());
            break;
          case 'canFill':
            out.add(log.canFill(jsNum(op['fromSeq'])));
            break;
          case 'rollbackBefore':
            out.add(log.rollbackBefore(jsNum(op['beforeSeq'])));
            break;
          default:
            throw ArgumentError('未知 log op ${op['op']}');
        }
      }
      return <String, Object?>{
        'out': out,
        'seq': log.seq,
        'truncated': log.truncated,
        'items': log.items.map((r) => r.seq).toList(),
      };
    },

    'rosterScript': (a) {
      final r = RoomRoster();
      final out = <Object?>[];
      List<Map<String, Object?>> dumpAll(List<Map<String, Object?>> xs) =>
          xs.map((m) => _m(roomClone(m))).toList();
      for (final opRaw in asList(a['ops'])) {
        final op = _m(opRaw);
        switch (op['op']) {
          case 'open':
            out.add(r.open(op['m'] == null ? null : _m(op['m'])));
            break;
          case 'markOffline':
            out.add(r.markOffline(jsStr(op['seat'])));
            break;
          case 'remove':
            out.add(r.remove(jsStr(op['seat'])));
            break;
          case 'get':
            out.add(r.get(jsStr(op['seat'])));
            break;
          case 'list':
            out.add(dumpAll(r.list()));
            break;
          case 'players':
            out.add(dumpAll(r.players()));
            break;
          case 'spectators':
            out.add(dumpAll(r.spectators()));
            break;
          case 'onlinePlayers':
            out.add(dumpAll(r.onlinePlayers()));
            break;
          case 'allReady':
            out.add(r.allReady());
            break;
          case 'dump':
            out.add(dumpAll(r.dump()));
            break;
          default:
            throw ArgumentError('未知 roster op ${op['op']}');
        }
      }
      final bySeat = <String, Object?>{};
      r.bySeat.forEach((k, v) => bySeat[k] = roomClone(v));
      return <String, Object?>{
        'out': out,
        'order': r.order,
        'kicked': r.kicked.toList(),
        'bySeat': bySeat,
      };
    },
  };

  fixture.run(handlers, only: batch);

  // ==========================================================
  // B) Dart-only 不变式
  // ==========================================================

  test('emptyState 恰好 18 个顶层键，且键序与旧版一致', () {
    final keys = emptyRoomState().keys.toList();
    expect(keys, <String>[
      'meta', 'members', 'chats', 'logs', 'dice', 'scene', 'combat', 'privates',
      'rewind', 'requests', 'board', 'sceneCheck', 'archive', 'lastState',
      'alert', 'opposed', 'seq', 'version',
    ]);
    expect(keys.length, 18);
    final metaKeys = asMap(emptyRoomState()['meta']).keys.toList();
    expect(metaKeys, <String>[
      'code', 'name', 'rules', 'kpName', 'maxPlayers', 'allowSpectate',
      'status', 'mode', 'round', 'critThreshold', 'fumbleThreshold',
      'hpWeek', 'psychoRound',
    ]);
  });

  test('EVT.TEMP_COMMIT 刻意无 reduce 分支：只写 seq，其余全等', () {
    final before = emptyRoomState(<String, Object?>{'code': 'abcd'});
    final snapshot = _m(roomClone(before));
    reduceRoomState(
      before,
      const RoomEvent(t: RoomEvt.tempCommit, p: <String, Object?>{}, seq: 7),
    );
    expect(before['seq'], 7);
    snapshot['seq'] = 7;
    expectJsonMatch(before, snapshot);
  });

  test('ruleOptsOf 只下发 [1,99] 的自定义阈值（旧版未导出，Dart-only）', () {
    expect(ruleOptsOf(<String, Object?>{}), <String, Object?>{});
    expect(ruleOptsOf(<String, Object?>{'critThreshold': 5}),
        <String, Object?>{'critMax': 5});
    expect(ruleOptsOf(<String, Object?>{'fumbleThreshold': 95}),
        <String, Object?>{'fumbleMin': 95});
    // 100 = 「未自定义」→ 不下发；0 / 越界 / 非数字同样不下发
    expect(ruleOptsOf(<String, Object?>{'critThreshold': 0}), isEmpty);
    expect(ruleOptsOf(<String, Object?>{'critThreshold': 100}), isEmpty);
    expect(ruleOptsOf(<String, Object?>{'fumbleThreshold': 0}), isEmpty);
    expect(ruleOptsOf(<String, Object?>{'critThreshold': 'x'}), isEmpty);
    expect(
      ruleOptsOf(<String, Object?>{
        'critThreshold': 5,
        'fumbleThreshold': 99,
      }),
      <String, Object?>{'critMax': 5, 'fumbleMin': 99},
    );
  });

  test('needs() 对未登记 action 一律拒绝（Q6：rollback.turn 已摘除）', () {
    expect(kRoomPolicy.containsKey('rollback.turn'), isFalse);
    expect(kRoomPolicy.containsKey('rollback.commit'), isTrue);
    for (final role in RoomRole.values) {
      final n = needs(role, 'rollback.turn');
      expect(n.allowed, isFalse, reason: '伪造 ACT 必须被拒绝（$role）');
      expect(n.confirm, isNull);
      expect(needs(role, '__unknown__').allowed, isFalse);
    }
  });

  test('apply 是唯一写口：room_model_host_core.dart 内 reduceRoomState( 只 1 处', () {
    final src = File('lib/domain/room_model_host_core.dart').readAsStringSync();
    final hits = src
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//') && l.contains('reduceRoomState('))
        .toList();
    expect(hits.length, 1, reason: '唯一写口被破了：$hits');
    expect(hits.single.trim(), startsWith('reduceRoomState(state, rec.evt)'));
  });

  test('apply(persist:false) 必须带 seq；persist 不参与归约判定', () {
    final host = RoomHost(RoomHostOptions(meta: const <String, Object?>{}));
    expect(
      () => host.apply(
        const RoomEvent(t: RoomEvt.log, p: <String, Object?>{}),
        persist: false,
      ),
      throwsA(isA<StateError>()),
    );
    // 两条路径喂给 reduce 的事件同构 → 状态必须一致
    final a = RoomHost(RoomHostOptions(meta: const <String, Object?>{}));
    final b = RoomHost(RoomHostOptions(meta: const <String, Object?>{}));
    final rec = a.emit(RoomEvt.log, <String, Object?>{'text': 'x', 'at': 1});
    b.apply(rec.evt, persist: false);
    expectJsonMatch(b.state, a.state);
    // 不持久化的路径不写日志
    expect(b.log.items, isEmpty);
    expect(b.log.seq, 0);
  });

  test('Log/Roster 基础语义（不依赖 fixture 也钉一遍）', () {
    final log = RoomLog(cap: 2);
    log.push(const RoomEvent(t: RoomEvt.log, p: <String, Object?>{}));
    final r2 = log.push(const RoomEvent(t: RoomEvt.log, p: <String, Object?>{}));
    expect(r2.seq, 2);
    expect(r2.evt.seq, 2, reason: '日志项必须挂带 seq 的完整事件对象');
    log.push(const RoomEvent(t: RoomEvt.log, p: <String, Object?>{}));
    expect(log.truncated, 1);
    expect(log.canFill(0), isFalse, reason: '窗口已被裁掉 → 必须走全量同步');
    expect(log.canFill(2), isTrue);

    final roster = RoomRoster();
    roster.open(<String, Object?>{'seat': 'p1', 'at': 1});
    expect(roster.get(kHostSeat), isNull, reason: '房主不在花名册里');
    roster.remove('p1');
    expect(roster.kicked, contains('p1'));
  });
}
