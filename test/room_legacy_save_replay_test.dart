// ============================================================
// test/room_legacy_save_replay_test.dart — CUT-1 旧存档回放（T11）
//
// 输入不是自造的假数据，而是**旧版 JS 预言机真实产出的房间存档**：
//   room_sequences.json 里 6 个 S:legacy 用例的 expect.save（20 键）。
// 门禁内容：
//   ① 逐字段无损：parseSave(JSON) → adoptSave → save() 与旧存档严格深比较
//      （唯一允许的差异是 adoptSave 统一的 online=false 重连语义，比较前
//       在期望副本里同步置位，绝不靠「跳过 members」放水）；
//   ② state 18 键仍含 state.rewind（Q6 休眠项没被删），adoptSave 幂等；
//   ③ 消费 EVT.REWIND 休眠分支：emit → state.rewind 逐字段一致；
//      再走 rollbackAbortIfVoting 的 REWIND 写回路径 → state=FAILED；
//   ④ 消费 rollback.turn 休眠分支：POLICY 未登记（needs 三角色全拒）、
//      但 applyAction 的 case 分支可达且**零副作用**（state/log/rewind 不变）；
//   ⑤ 静态钉死三件休眠项都还在源码里（枚举 / 归约分支 / 动作分支）。
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_host_intent.dart';
import 'package:dice_realm/domain/room_model_rollback.dart';
import 'package:dice_realm/domain/room_model_save.dart';
import 'package:dice_realm/domain/room_model_state.dart' show needs;
import 'package:dice_realm/domain/room_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';
import 'support/room_oracle.dart';

/// 旧版预言机真实产出的 6 份存档（20 键）。
Map<String, Map<String, Object?>> _legacySaves() {
  final seq = RoomOracleFixture.load('room_sequences.json');
  final out = <String, Map<String, Object?>>{};
  for (final c in seq.cases) {
    if (c['tag'] != 'S:legacy') continue;
    final save = asMap(asMap(c['expect'])['save']);
    if (save.isEmpty) continue;
    out[c['name']! as String] = save;
  }
  return out;
}

/// 深拷贝并把 members[].online 统一置 false（adoptSave 的重连语义）。
///
/// 这是「无损导入」唯一被允许的差异：花名册是「谁现在连着」的现实，
/// 读档时不能假装玩家还在线。其余 19 个键一律逐字段严格比较。
Map<String, Object?> _expectedAfterAdopt(Map<String, Object?> save) {
  final copy = jsonDecode(jsonEncode(save)) as Map<String, Object?>;
  final members = (copy['members'] as List)
      .map((m) {
        final mm = (m as Map).cast<String, Object?>();
        mm['online'] = false;
        return mm;
      })
      .toList();
  copy['members'] = members;
  return copy;
}

/// 深拷贝（用于「零副作用」前后逐字段对比）。
Map<String, Object?> _deep(Map<String, Object?> src) =>
    (jsonDecode(jsonEncode(src)) as Map).cast<String, Object?>();

void main() {
  final saves = _legacySaves();

  test('CUT-1 输入：6 份旧版存档，每份恰好 20 键', () {
    expect(saves.length, 6, reason: 'S:legacy 用例应产出 6 份真实旧存档');
    for (final e in saves.entries) {
      expect(e.value.length, 20, reason: '${e.key} 不是 20 键旧存档');
      expect(e.value['v'], 2);
      expect(e.value['savedAt'], 1700000000000);
    }
  });

  test('★ CUT-1：旧版房间 JSON 无损导入 → adoptSave → save() 逐字段一致', () {
    expect(saves.length, 6);
    for (final e in saves.entries) {
      final legacy = e.value;
      final parsed = parseSave(jsonEncode(legacy));
      expect(parsed, isNotNull, reason: '${e.key} parseSave 失败');
      expect(parsed!.length, 20, reason: '${e.key} 解析后键数不对');

      final h = RoomHost(roomHostOpts(meta: asMap(legacy['meta'])))
        ..adoptSave(parsed);

      // 20 键、键序、每个值都严格深比较（键集合双向差集）。
      final expected = _expectedAfterAdopt(legacy);
      expectJsonMatch(h.save(), expected, r'$', '${e.key} / save()');
      expect(h.save().keys.toList(), expected.keys.toList(),
          reason: '${e.key} 键序被改过');

      // 读档后的簿记水位与旧存档一致。
      expect(h.log.seq, (legacy['seq']! as num).toInt());
      expect(h.log.items, isEmpty, reason: '读档不重建历史日志');
      expect(h.stateSeq, (legacy['stateSeq']! as num).toInt());
      expect(h.snapshots.length, 1);
      expect(h.snapshots.single.seq, (legacy['seq']! as num).toInt());
      expect(h.pending, isEmpty);
      expect(h.rewind, isNull);
      for (final m in h.roster.dump()) {
        expect(m['online'], false, reason: '读档后必须等重连');
      }
      // state 仍是 18 键且承载旧存档的 chats/logs/dice/scene 等。
      final st = h.state;
      expect(st.length, 18);
      expectJsonMatch(st['chats'], legacy['chats'], r'$',
          '${e.key} / state.chats');
      expectJsonMatch(st['logs'], legacy['logs'], r'$', '${e.key} / state.logs');
      expectJsonMatch(st['dice'], legacy['dice'], r'$', '${e.key} / state.dice');
      expectJsonMatch(st['scene'], legacy['scene'], r'$',
          '${e.key} / state.scene');
      expectJsonMatch(st['combat'], legacy['combat'], r'$',
          '${e.key} / state.combat');
      expectJsonMatch(st['sceneCheck'], legacy['sceneCheck'], r'$',
          '${e.key} / state.sceneCheck');
    }
  });

  test('★ CUT-1：adoptSave 幂等；state.rewind 休眠字段仍在且为 null', () {
    final legacy = saves['S:legacy#1034']!;
    final h = RoomHost(roomHostOpts(meta: asMap(legacy['meta'])))
      ..adoptSave(parseSave(jsonEncode(legacy))!);
    final once = h.save();
    h.adoptSave(parseSave(jsonEncode(legacy))!);
    expectJsonMatch(h.save(), once, r'$', '幂等 / save()');

    final st = h.state;
    expect(st.containsKey('rewind'), isTrue,
        reason: 'Q6 休眠项 state.rewind 不许从 emptyRoomState 里删掉');
    expect(st['rewind'], isNull);
    expect(st.keys.toList(), <String>[
      'meta', 'members', 'chats', 'logs', 'dice', 'scene', 'combat', 'privates',
      'rewind', 'requests', 'board', 'sceneCheck', 'archive', 'lastState',
      'alert', 'opposed', 'seq', 'version',
    ]);
  });

  test('★ CUT-1：消费 EVT.REWIND 休眠分支（emit → state.rewind 逐字段）', () {
    final legacy = saves['S:legacy#1034']!;
    final h = RoomHost(roomHostOpts(meta: asMap(legacy['meta'])))
      ..adoptSave(parseSave(jsonEncode(legacy))!);

    final r = <String, Object?>{
      'state': RoomRewind.voting,
      'need': <Object?>['p1', 'p2'],
      'by': 'p1',
      'turns': 2,
      'at': 1700000000000,
    };
    final rec = h.emit(RoomEvt.rewind, <String, Object?>{'rewind': r},
        vis: RoomVis.public);
    expect(rec.seq, (legacy['seq']! as num).toInt() + 1);
    expectJsonMatch(h.state['rewind'], r, r'$.state.rewind');
    // REWIND 是事件不是状态归档键，save() 仍是 20 键。
    expect(h.save().length, 20);
    expect(h.save().containsKey('rewind'), isFalse);

    // p['rewind'] 为假值 → 清空（旧版 :310 同一分支）。
    h.emit(RoomEvt.rewind, <String, Object?>{'rewind': null},
        vis: RoomVis.public);
    expect(h.state['rewind'], isNull);

    // 另一条 REWIND 写回路径：表决期间掉线 → state 变 FAILED。
    h.rewind = <String, Object?>{
      'state': RoomRewind.voting,
      'need': <Object?>['p1'],
      'by': 'p1',
    };
    final out = h.rollbackAbortIfVoting('p1');
    expect(out, isNotEmpty);
    final failed = asMap(h.state['rewind']);
    expect(failed['state'], RoomRewind.failed);
    expect(failed['failReason'], '有玩家在表决期间断线');
    expect(failed['need'], <Object?>['p1']);
    expect(failed['by'], 'p1');
  });

  test('★ CUT-1：rollback.turn 休眠（POLICY 摘除但分支可达、零副作用）', () {
    final legacy = saves['S:legacy#1034']!;
    final h = RoomHost(roomHostOpts(meta: asMap(legacy['meta'])))
      ..adoptSave(parseSave(jsonEncode(legacy))!);

    for (final role in RoomRole.values) {
      expect(needs(role, 'rollback.turn').allowed, isFalse,
          reason: '$role 不得放行已摘除的 action');
    }
    expect(needs('kp', 'rollback.turn').confirm, isNull);

    final before = _deep(h.state);
    final logLen = h.log.items.length;
    final out = h.applyAction(kHostSeat, <String, Object?>{
      'op': 'rollback.turn',
      'turns': 2,
    });
    expect(out, isEmpty, reason: 'Q6 休眠分支不产生发送计划');
    expectJsonMatch(h.state, before, r'$', 'rollback.turn / state 零副作用');
    expect(h.log.items.length, logLen);
    expect(h.rewind, isNull);
    expect(h.pending, isEmpty);

    // 从 ACT 意图通道伪造这个 action：needs 闸门必须拒绝，且状态不变。
    final denied = h.intent('p1', <String, Object?>{
      'op': RoomIntent.act,
      'p': <String, Object?>{'op': 'rollback.turn', 'turns': 2},
    });
    expect(denied, isNotEmpty, reason: '伪造休眠 action 要收到定向拒绝提示');
    expect(denied.any((s) => s.to == '*'), isFalse,
        reason: '越权提示绝不广播');
    // 拒绝提示本身是一条 SEAT 定向事件（sysTo），reduce 末尾无条件写
    // state.seq —— 所以唯一允许的变化是水位 +1，其余 17 键逐字段严格不变。
    final afterDenied = _deep(before);
    afterDenied['seq'] = (before['seq']! as num) + 1;
    expectJsonMatch(h.state, afterDenied, r'$',
        'ACT 伪造 / 仅事件水位 +1，其余 17 键零副作用');
    expect(h.rewind, isNull);

    // rollbackVote 无表决时的旧版反馈仍在（休眠但界面要有反应）。
    final vote = h.rollbackVote('p1', true);
    expect(vote.length, 1);
    expect(vote.single.to, 'p1');
    expect(vote.single.msg.k, 'evt');
    expect(h.rewind, isNull);
  });

  test('CUT-1 静态：EVT.REWIND / state.rewind / rollback.turn 三件都保留', () {
    final reduce = File('lib/domain/room_model_reduce.dart').readAsStringSync();
    final state = File('lib/domain/room_model_state.dart').readAsStringSync();
    final types = File('lib/domain/room_types.dart').readAsStringSync();
    final actions =
        File('lib/domain/room_model_actions_room.dart').readAsStringSync();
    final rollback =
        File('lib/domain/room_model_rollback.dart').readAsStringSync();

    expect(types.contains("static const String rewind = 'rewind';"), isTrue);
    expect(RoomEvt.values, contains(RoomEvt.rewind));
    expect(reduce.contains('case RoomEvt.rewind:'), isTrue);
    expect(state.contains("'rewind': null,"), isTrue);
    expect(actions.contains("case 'rollback.turn':"), isTrue);
    expect(rollback.contains('rollbackPropose('), isTrue);
    expect(rollback.contains('rollbackVote('), isTrue);
    expect(rollback.contains('rollbackCommit('), isTrue);
    expect(rollback.contains('rollbackAbortIfVoting('), isTrue);
    // POLICY 里确实没有登记 rollback.turn（入口摘除）。
    expect(types.contains("'rollback.turn': RoomPolicyEntry"), isFalse);
  });
}
