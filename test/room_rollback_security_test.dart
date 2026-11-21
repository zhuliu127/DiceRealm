// ============================================================
// test/room_rollback_security_test.dart — Q1 安全回归（T04 · S4.1 核心验收）
//
// 旧版缺陷（room-model.js:3450）：`rollback()` 重放日志时只传 `{t,seq,p}`，
// 丢掉 `vis/to` → :685 把秘密 CHECK 当 PUBLIC 写成明文、:762 的 PRIVATE
// 守卫失效 → 明文与定向私密经 syncFor 广播给**每个**在线玩家。
//
// 本文件是 **Dart-only 断言**（不参与 oracle 比较、不登记白名单，§6.4-3）：
//   ① 构造 VIS.SEAT 秘密 CHECK + 定向 PRIVATE → rollback → 对每个在线 seat
//      调 syncFor，断言载荷字节级不含明文检定结果 / hp / hpMax / secret /
//      kpOnly / attrs / 症状明细；
//   ② 证明 `apply(evt, persist:false)` 重放时 vis/to **确实一起传给了 reduce**
//      （vis:seat → 脱敏；vis:null → 明文，对照成立才说明判据真的读到了 vis）；
//   ③ 静态钉死重放路径：`apply(r.evt, persist:false)` 单口、无补丁分支、
//      全库 reduceRoomState( 调用点 == 2。
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_rollback.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';
import 'support/room_oracle.dart' show expectJsonMatch;

const String _plain = '秘密检定：骰出 07，极难成功';
const String _clue = '线索A：只给 p1 看的密信';
const List<String> _forbidden = <String>[
  'hp',
  'hpMax',
  'secret',
  'kpOnly',
  'attrs',
];

bool _hasKeyDeep(Object? v, String key) {
  if (v is Map) {
    for (final e in v.entries) {
      if ('${e.key}' == key) return true;
      if (_hasKeyDeep(e.value, key)) return true;
    }
    return false;
  }
  if (v is List) {
    for (final x in v) {
      if (_hasKeyDeep(x, key)) return true;
    }
  }
  return false;
}

void _expectClean(Object? payload, String why, {bool forbidClue = true}) {
  for (final k in _forbidden) {
    expect(_hasKeyDeep(payload, k), isFalse, reason: '$why：泄漏了 $k');
  }
  final text = jsonEncode(payload);
  expect(text.contains(_plain), isFalse, reason: '$why：出现明文检定结果');
  if (forbidClue) {
    expect(text.contains(_clue), isFalse, reason: '$why：出现定向私密');
  }
  // 检定明细字段不允许出现在任何玩家载荷里
  expect(_hasKeyDeep(payload, 'summary'), isFalse,
      reason: '$why：出现检定明细 summary');
  expect(_hasKeyDeep(payload, 'detail'), isFalse,
      reason: '$why：出现检定明细 detail');
}

/// Q1 复现输入（设计 §0.1b / 白名单 reproInput 的同一形状）：
///   snapshotEvery=2；p1/p2 在线（直接 open 花名册，避免 attach 的 MEMBERS
///   事件占用 seq，保证 seq 与旧版复现步骤一一对应）
///   seq1 CHAT PUBLIC → seq2 LOG PUBLIC（触发快照 @2）
///   → seq3 CHECK VIS.SEAT to='p1'（明文藏在这里）
///   → seq4 PRIVATE VIS.SEAT to='p1'
///   → seq5 CHAT PUBLIC → rollback(4)（取 @seq2 快照，重放 (2,3] 含秘密 CHECK）
RoomHost _q1Host() {
  final h = RoomHost(roomHostOpts(
    meta: const <String, Object?>{'code': 'abcd'},
    snapshotEvery: 2,
  ));
  h.roster.open(<String, Object?>{'seat': 'p1', 'nickname': '甲', 'at': 1});
  h.roster.open(<String, Object?>{'seat': 'p2', 'nickname': '乙', 'at': 2});
  h.emit(RoomEvt.chat,
      <String, Object?>{'seat': 'host', 'nickname': 'KP', 'text': '开始', 'at': 1},
      vis: RoomVis.public);
  h.emit(RoomEvt.log, <String, Object?>{'text': '场景一', 'at': 2},
      vis: RoomVis.public);
  h.emit(
    RoomEvt.check,
    <String, Object?>{
      'summary': _plain,
      'seat': 'p1',
      'at': 3,
      'kind': 'check',
    },
    vis: RoomVis.seat,
    to: 'p1',
  );
  h.emit(
    RoomEvt.private_,
    <String, Object?>{'text': _clue, 'title': '只给p1', 'at': 4},
    vis: RoomVis.seat,
    to: 'p1',
  );
  h.emit(RoomEvt.chat,
      <String, Object?>{'seat': 'p1', 'text': '然后呢', 'at': 5},
      vis: RoomVis.public);
  return h;
}

void main() {
  test('Q1 复现前置：快照 @seq2，秘密事件落在重放区间 (2,4]', () {
    final h = _q1Host();
    // snapshotEvery=2 → 建团 @0、@seq2、@seq4 三份快照。
    // rollback(4) 取 seq<=3 的最近快照 = @2，重放区间 (2,3] 正好含秘密 CHECK。
    // （若用 rollback(5) 会命中 @4 快照、重放区间为空 → 断言平凡通过，测不到 Q1。）
    expect(h.snapshots.map((s) => s.seq).toList(), <int>[0, 2, 4],
        reason: '建团空快照 + @seq2 + @seq4');
    expect(h.log.items.length, 5);
    final checkRec = h.log.items[2];
    expect(checkRec.evt.t, RoomEvt.check);
    // ★ 内部事件对象必须持久化 vis/to/seq —— 这是 Q1 修正的数据基础
    expect(checkRec.evt.vis, RoomVis.seat);
    expect(checkRec.evt.to, 'p1');
    expect(checkRec.evt.seq, 3);
    expect(checkRec.seq, 3);
  });

  test('★ Q1：rollback 后权威态仍只有脱敏行，定向私密不进 state.privates', () {
    final h = _q1Host();
    final r = h.rollback(4);
    expectJsonMatch(r.toJson(), <String, Object?>{
      'dropped': 2, // seq4 PRIVATE + seq5 CHAT
      'seq': 3,
      'from': 2, // 从 @seq2 快照重放，秘密 CHECK 真的走了 apply(persist:false)
    });

    final logs = h.state['logs']! as List<Object?>;
    expect(logs.length, 2, reason: '场景一 + 脱敏 CHECK 行');
    final checkLine = logs[1]! as Map<String, Object?>;
    expectJsonMatch(checkLine, <String, Object?>{
      'seq': 3,
      'seat': '',
      'text': 'KP 秘密进行了一次检定',
      'at': 3,
      'kind': 'check',
      'opp': null,
      'redacted': true,
    });
    expect(h.state['privates'], isEmpty,
        reason: 'PRIVATE 的 SEAT 守卫在重放后仍须生效');
    expect(jsonEncode(h.state).contains(_plain), isFalse,
        reason: '权威态不得残留明文');
    expect(h.warnings, isEmpty, reason: '正常路径 warnings 必须为空');
  });

  test('★ Q1：对每个在线 seat 的 syncFor 载荷字节级无明文 / 隐藏字段', () {
    final h = _q1Host();
    h.rollback(4);
    for (final seat in <String>['p1', 'p2']) {
      final env = h.syncFor(seat).toJson();
      expect(env['k'], 'sync');
      _expectClean(env, 'syncFor($seat)', forbidClue: seat != 'p1');
      final state = env['state']! as Map<String, Object?>;
      final syncLogs = state['logs']! as List<Object?>;
      expect((syncLogs[1]! as Map)['redacted'], isTrue,
          reason: '$seat 的全量同步里也只能是脱敏行');
      _expectClean(h.combatFor(seat), 'combatFor($seat)');
    }
    // p1 是收件人：他自己的 privates 允许有密信，但 p2 一个字都拿不到
    final p1Privates =
        (h.syncFor('p1').toJson()['state']! as Map)['privates']! as List;
    expect(p1Privates.length, 1);
    expect((p1Privates.single! as Map)['text'], _clue);
    final p2Privates =
        (h.syncFor('p2').toJson()['state']! as Map)['privates']! as List;
    expect(p2Privates, isEmpty);
  });

  test('★ Q1：rollbackPlan 全量重发（无反向事件），且顺序为 sync 在前', () {
    final h = _q1Host();
    final out = h.rollbackPlan(4);
    // 两个在线玩家各 1 条全量 sync，最后 1 条系统日志广播
    expect(out.length, 3, reason: 'p1/p2 全量 sync + 1 条 sys');
    expect(out[0].to, 'p1');
    expect(out[0].msg.k, 'sync');
    expect(out[1].to, 'p2');
    expect(out[1].msg.k, 'sync');
    expect(out[2].msg.k, 'evt');
    expect(out[2].msg.toJson()['t'], RoomEvt.log);
    for (final s in out) {
      _expectClean(s.msg.toJson(), 'rollbackPlan → ${s.to}',
          forbidClue: s.to != 'p1');
    }
  });

  test('★ Q1 机制证明：apply(persist:false) 把 vis/to 一起交给了 reduce', () {
    // 对照 A：vis=seat + to=p1 → 脱敏行、PRIVATE 不进公共私有栏
    final a = RoomHost(roomHostOpts());
    a.apply(
      RoomEvent(
        t: RoomEvt.check,
        p: <String, Object?>{'summary': _plain, 'seat': 'p1', 'at': 1},
        vis: RoomVis.seat,
        to: 'p1',
        seq: 3,
      ),
      persist: false,
    );
    a.apply(
      const RoomEvent(
        t: RoomEvt.private_,
        p: <String, Object?>{'text': _clue, 'at': 2},
        vis: RoomVis.seat,
        to: 'p1',
        seq: 4,
      ),
      persist: false,
    );
    final aLogs = a.state['logs']! as List<Object?>;
    expect((aLogs.single! as Map)['redacted'], isTrue);
    expect(a.state['privates'], isEmpty);
    expect(a.log.items, isEmpty, reason: 'persist:false 不写日志');
    expect(a.log.seq, 0);

    // 对照 B：同一事件但 vis/to 缺失（旧版 :3450 的形状）→ 明文 + 私密混入
    final b = RoomHost(roomHostOpts());
    b.apply(
      RoomEvent(
        t: RoomEvt.check,
        p: <String, Object?>{'summary': _plain, 'seat': 'p1', 'at': 1},
        seq: 3,
      ),
      persist: false,
    );
    b.apply(
      const RoomEvent(
        t: RoomEvt.private_,
        p: <String, Object?>{'text': _clue, 'at': 2},
        seq: 4,
      ),
      persist: false,
    );
    final bLogs = b.state['logs']! as List<Object?>;
    expect((bLogs.single! as Map)['text'], _plain);
    expect((bLogs.single! as Map).containsKey('redacted'), isFalse);
    expect((b.state['privates']! as List).length, 1);
    // A/B 唯一差别就是 vis/to —— 证明 reduce 真的读到了这两个字段。
  });

  test('★ Q1 静态：重放走 apply 单口、无补丁分支、全库 reduce 调用点 == 2', () {
    final src = File('lib/domain/room_model_rollback.dart').readAsStringSync();
    final code = src
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(code.contains('apply(r.evt, persist: false)'), isTrue,
        reason: '重放必须走唯一写口，且沿用日志里的完整事件对象');
    expect(code.contains('reduceRoomState('), isFalse,
        reason: '重放路径不得另起归约口');
    expect(code.contains('{ t: '), isFalse,
        reason: '重放路径不得重建 {t,seq,p} 补丁事件（旧版 :3450 的缺陷形态）');

    var calls = 0;
    final where = <String>[];
    for (final f in Directory('lib/domain').listSync().whereType<File>()) {
      if (!f.path.contains('room_') || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//') || line.contains('///')) continue;
        if (!line.contains('reduceRoomState(')) continue;
        if (line.trimLeft().startsWith('Map<String, Object?> reduceRoomState(')) {
          continue;
        }
        calls++;
        where.add('${f.path}:${i + 1}');
      }
    }
    expect(calls, 2, reason: '实际 $where');
    expect(where.any((w) => w.contains('room_model_host_core.dart')), isTrue);
    expect(where.any((w) => w.contains('room_model_client.dart')), isTrue);
  });

  test('Q1 回归钉子：白名单恰好 2 条（S:q1 + S:trim），且本文件不参与 oracle 比较', () {
    // 本文件所有断言都是 Dart-only；这里只确认 T06 不是靠「开白名单」过关。
    // F3 裁决 A 批准第 2 条 S:trim（快照裁剪后深回退），仍不许出现第 3 条。
    final white = File('test/support/room_oracle_whitelist.dart').readAsStringSync();
    final hits = RegExp(r'^  KnownDivergence\(', multiLine: true).allMatches(white);
    expect(hits.length, 2, reason: '白名单被偷偷加/删条目');
    expect(white.contains("caseId: 'S:q1'"), isTrue);
    expect(white.contains("caseId: 'S:trim'"), isTrue);
    expect(white.contains('M:logScript'), isFalse);
    // Q1 的 vis/to 修正不能受影响：apply(persist:false) 单口仍在。
    expect(white.contains('exactCaseNames'), isTrue,
        reason: 'S:trim 必须靠精确点名命中，不得放宽 coversCase 前缀');
  });
}
