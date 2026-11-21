// ============================================================
// test/qa_p4_seq_rollback_edges_test.dart — 独立复核：seq 边界与回退边界
//
// 805 例里的 seq 用例集中在「1→1→3→2」这一条正路。本文件专挑边角：
//   · seq = 0 / 负数 / 超大值（2^31-1）/ 重放中途插队；
//   · `filled` 与 `dup` 是否可能同时成立；`lastSeq` 被 sync 拉回退；
//   · `skip` 与 `evt` 是否真的共用同一套闸门判据；
//   · `canFill` 的边界（0 / 负数 / 超出窗口）；
//   · rollback：target == 当前 seq、target 早于所有快照、snapshotEvery=1、
//     IN_GAME 只进不退、members 用当前花名册覆盖、重建回合边界；
//   · ★ 快照被 snapshotLimit 裁掉之后深回退：F3 裁决 A 修复后的回归
//     （基线快照永存 + state.seq/log.seq 恒等 + 二次深回退不崩溃）。
//
// ⚠️ 序号不是从 1 开始：`attachPeer` 自己会发 MEMBERS 事件。所有基准 seq
//    一律用 `h.log.seq` 现取，不写死数字（写死必错）。
// ============================================================

import 'dart:convert';

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_client.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_host_intent.dart';
import 'package:dice_realm/domain/room_model_log.dart';
import 'package:dice_realm/domain/room_model_rollback.dart';
import 'package:dice_realm/domain/room_model_save.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';

/// 断言 receive 返回体的键集合**完全**等于给定集合（多一个 null 也算错）。
void _expectKeys(Map<String, Object?> json, List<String> keys, String label) {
  expect(json.keys.toList(), keys, reason: '$label：返回体键集合/键序不一致');
  expect(json.containsKey('gapFrom'), isFalse,
      reason: '$label：返回体出现了内部字段 gapFrom（§0.3）');
}

Map<String, Object?> _evt(int seq, [String t = 'chat']) =>
    <String, Object?>{'k': 'evt', 'seq': seq, 't': t, 'p': <String, Object?>{}};

Map<String, Object?> _skip(int seq) =>
    <String, Object?>{'k': 'skip', 'seq': seq};

RoomHost _host({
  int snapshotEvery = 20,
  int logCap = 400,
  int snapshotLimit = 20,
}) =>
    RoomHost(roomHostOpts(
      snapshotEvery: snapshotEvery,
      logCap: logCap,
      snapshotLimit: snapshotLimit,
    ));

void _attachTwo(RoomHost h) {
  h.attachPeer(<String, Object?>{'seat': 'p1', 'at': 1});
  h.attachPeer(<String, Object?>{'seat': 'p2', 'at': 2});
}

void _chat(RoomHost h, String text) => h.emit(
      RoomEvt.chat,
      <String, Object?>{'seat': 'p1', 'text': text},
      vis: RoomVis.public,
    );

void main() {
  group('seq 边界 · 客户端闸门', () {
    test('seq=0 与负数一律判重（<= lastSeq），且返回体不带 filled', () {
      final c = RoomClient(seat: 'p1');
      for (final s in <int>[0, -1, -999]) {
        final r = c.receive(_evt(s)).toJson();
        _expectKeys(r, <String>['kind', 'dup', 'gap', 'from', 'got'], 'evt($s)');
        expect(r['dup'], isTrue, reason: 'seq=$s 应判重');
        expect(r['gap'], isFalse);
        expect(r['from'], 0);
        expect(r['got'], s);
      }
      expect(c.lastSeq, 0, reason: '被拒绝的事件不得推进 lastSeq');
      expect(c.rejected, 3);
    });

    test('skip 同样拦 0/负数（共用判据）', () {
      final c = RoomClient(seat: 'p1');
      final r = c.receive(_skip(0)).toJson();
      _expectKeys(r, <String>['kind', 'dup', 'gap', 'from', 'got'], 'skip(0)');
      expect(r['kind'], 'skip');
      expect(r['dup'], isTrue);
    });

    test('超大 seq（2^31-1）判跳号，状态不变', () {
      final c = RoomClient(seat: 'p1');
      final before = jsonEncode(c.state);
      final r = c.receive(_evt(2147483647)).toJson();
      expect(r['gap'], isTrue);
      expect(r['from'], 0);
      expect(r['got'], 2147483647);
      expect(c.lastSeq, 0);
      expect(jsonEncode(c.state), before, reason: '跳号事件不得改状态');
    });

    test('巨量连续推进不溢出：从 1 推到 20000', () {
      final c = RoomClient(seat: 'p1');
      for (var i = 1; i <= 20000; i++) {
        final r = c.receive(_evt(i)).toJson();
        expect(r['kind'], 'evt');
      }
      expect(c.lastSeq, 20000);
      expect(c.gapFrom, 0);
      expect(asList(c.state['chats']).length, 500,
          reason: 'chats 上限 500 应生效（内存不无限涨）');
    });

    test('seq 中途插队（乱序重放）：旧 seq 判重，跳号判缺口，只有 +1 放行', () {
      final c = RoomClient(seat: 'p1');
      expect(c.receive(_evt(1)).toJson()['kind'], 'evt');
      expect(c.receive(_evt(3)).toJson()['gap'], isTrue);
      expect(c.receive(_evt(2)).toJson()['kind'], 'evt');
      expect(c.receive(_evt(2)).toJson()['dup'], isTrue);
      // lastSeq=2 → 4 仍是跳号（3 没来），不能因为「跳过 3」就放行
      expect(c.receive(_evt(4)).toJson()['gap'], isTrue);
      expect(c.lastSeq, 2);
      expect(c.receive(_evt(3)).toJson()['kind'], 'evt');
      expect(c.lastSeq, 3);
    });

    test('filled 与 dup 不可能同时成立（拒绝分支的键集合里没有 filled）', () {
      final c = RoomClient(seat: 'p1');
      c.receive(_evt(1));
      c.receive(_evt(3)); // 缺口：gapFrom = 1
      final dup = c.receive(_evt(1)).toJson(); // 重复
      expect(dup.containsKey('filled'), isFalse,
          reason: '被拒绝的分支不得带 filled（否则「补齐」与「重复」会混）');
      expect(dup['dup'], isTrue);
      expect(dup['gap'], isFalse);
      // 补齐那一刻 filled=true，且此后不再报
      final filled = c.receive(_evt(2)).toJson();
      expect(filled['filled'], isTrue, reason: '补齐瞬间应报 filled=true');
      expect(c.gapFrom, 0);
      expect(c.receive(_evt(3)).toJson()['filled'], isFalse);
    });

    test('lastSeq 被 sync 拉回退后，后续旧事件判重（不重放）', () {
      final c = RoomClient(seat: 'p1');
      c.receive(_evt(1));
      c.receive(<String, Object?>{
        'k': 'sync',
        'seq': 10,
        'state': <String, Object?>{'meta': <String, Object?>{}},
      });
      expect(c.lastSeq, 10);
      final r = c.receive(_evt(3)).toJson();
      expect(r['dup'], isTrue, reason: 'sync 之后 lastSeq=10，seq=3 必须判重');
      expect(r['from'], 10);
    });

    test('gapFrom 以 lastSeq=0 为起点时无法与「无缺口」区分（旧版同源，现状记录）', () {
      final c = RoomClient(seat: 'p1');
      final r = c.receive(_evt(3)).toJson();
      expect(r['gap'], isTrue);
      expect(c.gapFrom, 0, reason: '旧版同样把起点缺口记成 0（哨兵冲突）');
      expect(c.resyncDiag().toJson()['holes'], 0,
          reason: '诊断里看不出有洞 —— 旧版同源的观测性缺陷，非本轮引入');
      // 但补拉起点仍是对的（resyncIntent 用 lastSeq 兜底）
      final intent = c.resyncIntent().toJson();
      expect(asMap(intent['p'])['lastSeq'], 0);
    });
  });

  group('canFill 边界', () {
    RoomLog logWith(int n, {int cap = 400}) {
      final l = RoomLog(cap: cap);
      for (var i = 0; i < n; i++) {
        l.push(RoomEvent(t: RoomEvt.chat, p: <String, Object?>{'text': '$i'}));
      }
      return l;
    }

    test('fromSeq >= seq → true；负数 → false', () {
      final l = logWith(5);
      expect(l.canFill(5), isTrue);
      expect(l.canFill(6), isTrue);
      expect(l.canFill(4), isTrue);
      expect(l.canFill(0), isTrue, reason: 'first.seq=1 <= 0+1');
      expect(l.canFill(-1), isFalse, reason: '负数起点必走全量');
      expect(l.canFill(-100), isFalse);
    });

    test('日志为空时：只有 fromSeq >= seq(0) 才可增量', () {
      final l = RoomLog(cap: 400);
      expect(l.canFill(0), isTrue);
      expect(l.canFill(1), isTrue);
      expect(l.canFill(-1), isFalse);
    });

    test('cap 截断后旧起点一律不可增量（必须全量）', () {
      final l = logWith(6);
      expect(l.canFill(1), isTrue);
      final small = logWith(6, cap: 2);
      expect(small.items.first.seq, 5);
      expect(small.canFill(1), isFalse);
      expect(small.canFill(4), isTrue);
    });
  });

  group('intent(SYNC) · 增量补齐不得叠加全量', () {
    test('canFill=true 时只发增量，且一条 sync 信封都没有', () {
      final h = _host();
      _attachTwo(h);
      for (var i = 0; i < 3; i++) {
        _chat(h, 'x$i');
      }
      final from = h.log.seq - 3;
      final out = h.intent('p2', <String, Object?>{
        'op': RoomIntent.sync,
        'p': <String, Object?>{'lastSeq': from},
      });
      expect(out, isNotEmpty);
      final kinds = out.map((p) => p.msg.toJson()['k']).toList();
      expect(kinds.contains('sync'), isFalse,
          reason: '增量补齐里叠了全量 sync（客户端会整体覆盖一次，白补）');
      expect(kinds.every((k) => k == 'evt'), isTrue);
      expect(out.every((p) => p.to == 'p2'), isTrue, reason: '补拉只发给请求者');
    });

    test('没有任何相关事件时回一条全量（否则客户端永远挂着「正在补齐」）', () {
      final h = _host();
      _attachTwo(h);
      h.emit(RoomEvt.private_, <String, Object?>{'title': 't', 'text': '只给 p1'},
          vis: RoomVis.seat, to: 'p1');
      // 从**当前水位**请求 → since(seq) 为空 → 必须回全量
      final out = h.intent('p2', <String, Object?>{
        'op': RoomIntent.sync,
        'p': <String, Object?>{'lastSeq': h.log.seq},
      });
      expect(out.length, 1, reason: '一条相关事件都没有时必须回 1 条全量');
      expect(out.single.msg.toJson()['k'], 'sync');
      expect(out.single.to, 'p2');
    });

    test('lastSeq=0 → 直接全量；lastSeq 超出窗口 → 直接全量（恰好 1 条）', () {
      final h = RoomHost(roomHostOpts(logCap: 2));
      _attachTwo(h);
      for (var i = 0; i < 8; i++) {
        _chat(h, 'x$i');
      }
      for (final from in <int>[0, 1]) {
        final out = h.intent('p2', <String, Object?>{
          'op': RoomIntent.sync,
          'p': <String, Object?>{'lastSeq': from},
        });
        expect(out.length, 1, reason: 'lastSeq=$from 应恰好 1 条全量 sync');
        expect(out.single.msg.toJson()['k'], 'sync');
      }
    });
  });

  group('rollback 边界', () {
    test('target == 当前 seq（rollback(seq+1)）：撤销 0 条，状态与日志都不动', () {
      final h = _host(snapshotEvery: 1);
      _attachTwo(h);
      _chat(h, 'a');
      _chat(h, 'b');
      final seq = h.log.seq;
      final logsBefore = jsonEncode(h.state['logs']);
      final r = h.rollback(seq + 1).toJson();
      expect(r['dropped'], 0);
      expect(r['seq'], seq);
      expect(jsonEncode(h.state['logs']), logsBefore,
          reason: 'rollback(seq+1) 不该动日志内容');
      expect(h.log.seq, seq);
    });

    test('target 早于所有快照（rollback(1)）：退成建团空态，日志清空', () {
      final h = _host(snapshotEvery: 5);
      _attachTwo(h);
      for (var i = 0; i < 4; i++) {
        _chat(h, 'x$i');
      }
      final total = h.log.seq;
      final r = h.rollback(1).toJson();
      expect(r['dropped'], total, reason: '应撤销全部 $total 条');
      expect(r['seq'], 0);
      expect(r['from'], 0, reason: '应回到 seq 0 的建团快照');
      expect(asList(h.state['logs']), isEmpty);
      expect(h.log.items, isEmpty);
      expect(h.state['seq'], 0);
      expect(h.state.keys.length, 18, reason: '空态应恰好 18 个顶层键');
    });

    test('rollback(0)（非法规格）不崩溃；日志水位落到 -1，下一次 emit 从 0 开始', () {
      final h = _host(snapshotEvery: 1);
      _attachTwo(h);
      _chat(h, 'a');
      final total = h.log.seq;
      final r = h.rollback(0).toJson();
      expect(r['dropped'], total);
      expect(h.log.seq, -1, reason: 'rollbackBefore(0) → seq = -1（旧版同源）');
      expect(h.state['seq'], 0, reason: '快照 seq0 恢复了 state.seq');
      final rec = h.emit(
        RoomEvt.chat,
        <String, Object?>{'seat': 'p1', 'text': 'b'},
        vis: RoomVis.public,
      );
      expect(rec.seq, 0,
          reason: '下一次事件从 0 开始（与已被丢弃的旧 seq 0 重号，但链路不崩）');
      expect(h.state['seq'], 0);
    });

    test('snapshotEvery=1：任意中间点回退都能精确还原', () {
      final h = _host(snapshotEvery: 1);
      _attachTwo(h);
      final base = h.log.seq;
      for (final t in <String>['a', 'b', 'c', 'd', 'e']) {
        _chat(h, t);
      }
      h.rollback(base + 4); // 只留 a/b/c
      // ⚠️ chat 进 state.chats（不是 state.logs）
      expect(asList(h.state['chats']).map(asMap).map((m) => m['text']).toList(),
          <String>['a', 'b', 'c']);
      expect(h.log.seq, base + 3);
      expect(h.state['seq'], base + 3);
      expect(h.snapshots.map((s) => s.seq).toList(),
          <int>[for (var i = 0; i <= base + 3; i++) i],
          reason: 'snapshotEvery=1 应保留每个 seq 的快照（回退后裁到 target）');
    });

    test('IN_GAME 只进不退：回退到开团前的快照仍保持 IN_GAME，且不写 ended', () {
      final h = _host(snapshotEvery: 1);
      _attachTwo(h);
      h.setStatus(RoomStatus.inGame);
      _chat(h, 'a');
      h.rollback(1); // target 0 → 快照是 RECRUITING
      final meta = asMap(h.state['meta']);
      expect(meta['status'], RoomStatus.inGame, reason: '回退把「开团」这个事实撤销了');
      expect(meta.containsKey('ended'), isFalse, reason: 'IN_GAME 回退不得写 meta.ended');
    });

    test('members 用当前花名册覆盖（回退到建团时刻也不会把玩家抹掉）', () {
      final h = _host(snapshotEvery: 10);
      _attachTwo(h);
      _chat(h, 'a');
      h.rollback(1);
      expect(asList(h.state['members']).length, 2,
          reason: '快照里的空成员表覆盖了现实花名册');
      // 离线也要保留（只标 offline，不删）
      h.detachPeer('p2');
      _chat(h, 'b');
      h.rollback(2);
      expect(asList(h.state['members']).length, 2,
          reason: '回退把掉线玩家从名单里删掉了');
    });

    test('rebuildRoundStarts：被裁掉的回合边界不得留在表里', () {
      final h = _host(snapshotEvery: 1);
      _attachTwo(h);
      h.emit(RoomEvt.round, <String, Object?>{'round': 1}, vis: RoomVis.public);
      final r1 = h.log.seq;
      _chat(h, 'a');
      h.emit(RoomEvt.round, <String, Object?>{'round': 2}, vis: RoomVis.public);
      expect(h.roundStarts.length, 2);
      h.rollback(h.log.seq); // 撤掉 round 2（它是最后一条）
      expect(h.roundStarts.length, 1);
      expect(asMap(h.roundStarts.single)['round'], 1);
      expect(h.roundStarts.single['seq'], r1);
    });

    test('回退后每个在线者收全量 sync，且顺序在系统日志之前（rollbackPlan）', () {
      final h = _host(snapshotEvery: 1);
      _attachTwo(h);
      _chat(h, 'a');
      final out = h.rollbackPlan(h.log.seq);
      expect(out.map((p) => p.to).toList(), <String>['p1', 'p2', '*'],
          reason: '顺序：先逐人全量 sync，最后一条系统日志广播');
      expect(out[0].msg.toJson()['k'], 'sync');
      expect(out[1].msg.toJson()['k'], 'sync');
      expect(out.last.msg.toJson()['k'], 'evt');
    });

    test('★ 快照被 snapshotLimit 裁掉后的深回退：F3 修复回归（状态退 + 二次不崩溃）', () {
      // snapshotLimit=3 + snapshotEvery=1 → 打满后保留「基线 + 最近 2 条」。
      final h = _host(snapshotEvery: 1, snapshotLimit: 3);
      _attachTwo(h);
      for (var i = 0; i < 10; i++) {
        _chat(h, 'x$i');
      }
      final last = h.log.seq; // 2（两次 attach）+ 10 = 12
      expect(h.snapshots.map((s) => s.seq).toList(),
          <int>[0, last - 1, last],
          reason: 'F3 修复：建团基线(seq0)永存，只裁中间非基线快照，'
              '与 host_core 的「第 0 条永远是建团时的空状态」注释一致');
      final r = h.rollback(3); // target=2，早于所有非基线留存快照
      expect(r.from, 0,
          reason: '没有任何 seq<=2 的非基线快照 → 退化为从建团基线重放 (0,2]');
      expect(h.log.seq, 2);
      expect(h.state['seq'], 2,
          reason: 'F3 修复：状态水位必须与日志水位恒等（旧版这里留着 seq8）');
      expect(asList(h.state['chats']), isEmpty,
          reason: 'F3 修复：10 条被撤销的聊天不得残留在权威态');
      expect(h.snapshots.map((s) => s.seq).toList(), <int>[0],
          reason: 'F3 修复：快照表不得被清空，基线仍在');
      // 连续第二次深回退：旧版在这里抛 StateError: No element
      expect(() => h.rollback(2), returnsNormally,
          reason: 'F3 修复：二次深回退不得崩溃');
      expect(h.log.seq, 1);
      expect(h.state['seq'], 1);
      expect(h.snapshots.map((s) => s.seq).toList(), <int>[0]);
    });

    test('adoptSave 之后回退到存档点之前：F3 修复回归（同一根因）', () {
      final h = _host(snapshotEvery: 1);
      _attachTwo(h);
      _chat(h, 'a');
      final save = h.save();
      final r = RoomHost(roomHostOpts(snapshotEvery: 1))..adoptSave(save);
      expect(r.snapshots.map((s) => s.seq).toList(), <int>[h.log.seq],
          reason: 'adoptSave 只留一条 seq=save.seq 的快照');
      // rollback(1)：target=0 早于唯一快照 → 从建团空状态重放空集 (0,0]
      r.rollback(1);
      expect(r.log.seq, 0);
      expect(r.state['seq'], 0,
          reason: 'F3 修复：状态水位与日志水位恒等（旧版这里仍是存档时点）');
      expect(r.snapshots.map((s) => s.seq).toList(), <int>[0],
          reason: 'F3 修复：空快照表会重建基线，下一次回退不抛');
      expect(() => r.rollback(1), returnsNormally);
    });
  });
}
