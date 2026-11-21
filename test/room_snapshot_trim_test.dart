// ============================================================
// test/room_snapshot_trim_test.dart — F3（裁决 A）深回退崩溃修复回归
//
// 旧版缺陷链（room-model.js:845 / :1021-1025 / :3437-3439 / :3468）：
//   构造时 snapshots=[{seq:0}]（建团空状态），_maybeSnapshot 打满后用
//   shift() 把首条一起裁掉；rollback 又以 snapshots[0] 无条件兜底，
//   于是快照窗口打满后深回退会拿一条 seq > target 的「未来状态」当基准
//   → 权威态不退、state.seq 与 log.seq 分叉；:3468 的 filter 再把表清空，
//   第二次 rollback 在 snapshots.first 上抛 StateError: No element。
//
// 本期修法（F3 裁决 A）：
//   · _maybeSnapshot / maybeSnapshot：保留 index0 基线 + 最近 N-1 条，
//     超限只 removeAt(1)，基线永不淘汰；
//   · rollback：只在 seq<=target 里挑最近快照，一条都没有就从建团空状态
//     重放 (0,target]；显式对齐 state.seq；快照表空了重建基线。
//
// 本文件钉五类场景 + 幂等/可见性不回退 + 源码钉子，全部 Dart-only，
// 不参与 oracle 比较、不登记白名单。
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_rollback.dart';
import 'package:dice_realm/domain/room_model_save.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';

const String _plain = '秘密检定：骰出 07，极难成功';
const String _clue = '线索A：只给 p1 看的密信';

/// 固定时钟 + 独立 LCG + 确定性规则服务；快照窗口由参数钉死。
RoomHost _host(int snapshotLimit) => RoomHost(roomHostOpts(
      snapshotEvery: 1,
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

List<int> _seqs(RoomHost h) => h.snapshots.map((s) => s.seq).toList();

/// 三者自洽：state.seq == log.seq == target；快照表非空、首条是基线、
/// 单调递增、且不含任何 seq>target 的未来快照；日志里也没有未来事件。
void _assertSelfConsistent(RoomHost h, int target, String why) {
  expect(h.log.seq, target, reason: '$why：log.seq');
  expect(h.state['seq'], target,
      reason: '$why：state.seq 必须与 log.seq 恒等（旧版这里留着未来 seq）');
  final seqs = _seqs(h);
  expect(seqs, isNotEmpty, reason: '$why：快照表不得被清空');
  expect(seqs.first, 0, reason: '$why：建团基线(seq0)必须永存');
  final sorted = <int>[...seqs]..sort();
  expect(seqs, sorted, reason: '$why：快照 seq 必须单调递增');
  for (final s in seqs) {
    expect(s <= target, isTrue,
        reason: '$why：残留了 seq=$s > target 的未来快照');
  }
  for (final r in h.log.items) {
    expect(r.seq <= target, isTrue,
        reason: '$why：日志残留未来事件 seq=${r.seq}');
  }
}

/// 静态判据用：剥掉 `//` 行注释，避免把说明文字里的示例当成代码。
String _codeOf(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .map((line) {
      final i = line.indexOf('//');
      return i < 0 ? line : line.substring(0, i);
    })
    .join('\n');

void main() {
  group('F3 · 快照裁剪后深回退（五类场景）', () {
    test('① 复现路径：snapshotEvery=1 / limit=3 / 10 事件 / rollback(3)', () {
      final h = _host(3);
      _attachTwo(h); // seq1 MEMBERS(p1) + seq2 MEMBERS(p2)
      for (var i = 0; i < 10; i++) {
        _chat(h, 'x$i'); // seq3..seq12
      }
      final last = h.log.seq;
      expect(last, 12, reason: 'attach 占 2 个 seq，10 条 chat 到 seq12');
      expect(_seqs(h), <int>[0, last - 1, last],
          reason: '基线 + 最近 2 条；旧版这里是 [10,11,12]（基线被裁掉）');

      final r = h.rollback(3); // target=2，早于所有非基线留存快照
      expect(r.from, 0, reason: '退化为从建团基线重放 (0,2]');
      expect(r.seq, 2);
      _assertSelfConsistent(h, 2, 'rollback(3)');
      expect(asList(h.state['chats']), isEmpty,
          reason: '10 条被撤销的 chat 不得残留在权威态');
      expect(_seqs(h), <int>[0], reason: '快照表只剩基线，但绝不能空');
    });

    test('② 更小窗口 limit=2：中途重放仍能精确重建状态', () {
      final h = _host(2);
      _attachTwo(h);
      for (var i = 0; i < 10; i++) {
        _chat(h, 'x$i');
      }
      final last = h.log.seq;
      expect(_seqs(h), <int>[0, last]);

      // target=3：从基线重放 seq1/2(MEMBERS) + seq3(chat x0)
      h.rollback(4);
      _assertSelfConsistent(h, 3, 'limit=2 / rollback(4)');
      final chats = asList(h.state['chats']);
      expect(chats.length, 1, reason: '只有 seq3 这条 chat 仍有效');
      expect(asMap(chats.single)['text'], 'x0');
      expect(_seqs(h), <int>[0]);
    });

    test('③ 回退到 baseline 之前的最早 seq（rollback(1)）不崩且幂等', () {
      final h = _host(3);
      _attachTwo(h);
      for (var i = 0; i < 10; i++) {
        _chat(h, 'x$i');
      }
      h.rollback(1); // target=0
      _assertSelfConsistent(h, 0, 'rollback(1)');
      expect(asList(h.state['chats']), isEmpty);
      expect(_seqs(h), <int>[0]);
      // 幂等：同一 target 再退一次不应改变任何水位，也不应抛
      expect(() => h.rollback(1), returnsNormally);
      _assertSelfConsistent(h, 0, 'rollback(1) 二次');
      expect(_seqs(h), <int>[0]);
    });

    test('④ 连续四次深回退：每次都从基线重放，水位单调收敛', () {
      final h = _host(3);
      _attachTwo(h);
      for (var i = 0; i < 10; i++) {
        _chat(h, 'x$i'); // seq3..seq12
      }
      // target=7 → 重放 (0,7]：5 条 chat（x0..x4）
      h.rollback(8);
      _assertSelfConsistent(h, 7, '第 1 次');
      expect(asList(h.state['chats']).length, 5);
      // target=4 → 重放 (0,4]：2 条 chat（x0, x1）
      h.rollback(5);
      _assertSelfConsistent(h, 4, '第 2 次');
      expect(asList(h.state['chats']).length, 2);
      // target=2 → 只剩两条 MEMBERS，chat 清空
      h.rollback(3);
      _assertSelfConsistent(h, 2, '第 3 次');
      expect(asList(h.state['chats']), isEmpty);
      // target=0
      h.rollback(1);
      _assertSelfConsistent(h, 0, '第 4 次');
      expect(_seqs(h), <int>[0]);
    });

    test('⑤ adoptSave 只留一条存档点快照：深回退同样退到空状态', () {
      final h = _host(1);
      _attachTwo(h);
      _chat(h, 'a');
      final save = h.save();
      final r = RoomHost(roomHostOpts(snapshotEvery: 1, snapshotLimit: 3))
        ..adoptSave(save);
      expect(_seqs(r), <int>[h.log.seq],
          reason: 'adoptSave 只留一条 seq=save.seq 的快照');
      r.rollback(1); // target=0 早于唯一快照
      _assertSelfConsistent(r, 0, 'adoptSave 深回退');
      expect(asList(r.state['chats']), isEmpty);
      expect(_seqs(r), <int>[0]);
      expect(() => r.rollback(1), returnsNormally);
    });
  });

  group('F3 · 幂等与可见性不回退', () {
    test('⑥ state.seq / log.seq / snapshotSeqs 三者自洽（多 limit × 多 target 扫描）', () {
      for (final limit in <int>[1, 2, 3, 5]) {
        final h = _host(limit);
        _attachTwo(h);
        for (var i = 0; i < 9; i++) {
          _chat(h, 'x$i'); // seq3..seq11
        }
        expect(_seqs(h).first, 0, reason: 'limit=$limit：基线必须永存');
        for (final before in <int>[11, 8, 5, 3, 1]) {
          h.rollback(before);
          _assertSelfConsistent(h, before - 1,
              'limit=$limit / rollback($before)');
        }
      }
    });

    test('⑦ 深回退到建团点：members 仍用当前花名册覆盖（不抹掉在线玩家）', () {
      final h = _host(3);
      _attachTwo(h);
      for (var i = 0; i < 10; i++) {
        _chat(h, 'x$i');
      }
      h.rollback(1); // target=0
      final members = asList(h.state['members']);
      expect(members.length, 2,
          reason: '回退到建团点也不能把在线玩家从名单抹掉');
      expect(members.map((m) => asMap(m)['seat']).toList(),
          <Object?>['p1', 'p2']);
      _assertSelfConsistent(h, 0, 'members 覆盖');
    });

    test('★ ⑧ Q1 不受影响：窗口打满后深回退，秘密 CHECK 仍是脱敏行', () {
      // 直接 open 花名册，避免 attach 的 MEMBERS 事件占 seq（与 Q1 复现同形）。
      final h = RoomHost(roomHostOpts(
        meta: const <String, Object?>{'code': 'abcd'},
        snapshotEvery: 1,
        snapshotLimit: 2,
      ));
      h.roster.open(<String, Object?>{'seat': 'p1', 'nickname': '甲', 'at': 1});
      h.roster.open(<String, Object?>{'seat': 'p2', 'nickname': '乙', 'at': 2});
      h.emit(RoomEvt.chat,
          <String, Object?>{'seat': 'host', 'text': '开始', 'at': 1},
          vis: RoomVis.public); // seq1
      h.emit(RoomEvt.log, <String, Object?>{'text': '场景一', 'at': 2},
          vis: RoomVis.public); // seq2
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
      ); // seq3：明文藏在 SEAT 定向 CHECK 里
      h.emit(
        RoomEvt.private_,
        <String, Object?>{'text': _clue, 'title': '只给p1', 'at': 4},
        vis: RoomVis.seat,
        to: 'p1',
      ); // seq4
      for (var i = 0; i < 8; i++) {
        h.emit(RoomEvt.chat,
            <String, Object?>{'seat': 'p1', 'text': '续$i', 'at': 5 + i},
            vis: RoomVis.public); // seq5..seq12
      }
      expect(_seqs(h), <int>[0, h.log.seq],
          reason: 'limit=2 打满后只剩基线 + 最后一条；Q1 原用的 @seq2 快照已不存在');

      // rollback(4) → target=3：秘密 CHECK(seq3) 必须走 apply(persist:false)
      // 重放；PRIVATE(seq4) 被裁掉。旧版在这里会拿「未来快照」当基准，
      // Q1 的 vis/to 修正也会被一并绕过。
      final r = h.rollback(4);
      expect(r.from, 0, reason: '没有 seq<=3 的非基线快照 → 从基线重放 (0,3]');
      _assertSelfConsistent(h, 3, 'Q1 + F3 深回退');

      final logs = asList(h.state['logs']);
      expect(logs.length, 2, reason: '场景一 + 脱敏 CHECK 行');
      final line = asMap(logs[1]);
      expect(line['redacted'], isTrue);
      expect(line['text'], 'KP 秘密进行了一次检定');
      expect(line['seat'], '');
      expect(line['opp'], isNull);
      expect(asList(h.state['privates']), isEmpty,
          reason: 'PRIVATE 的 SEAT 守卫在重放后仍须生效');
      expect(jsonEncode(h.state).contains(_plain), isFalse,
          reason: '权威态不得残留明文检定结果');
      expect(jsonEncode(h.state).contains(_clue), isFalse);
    });
  });

  group('F3 · 源码钉子（防止改回去）', () {
    test('⑨ 两处裁剪都用 removeAt(1)，回滚显式对齐 seq，apply 单口未变', () {
      final core = _codeOf('lib/domain/room_model_host_core.dart');
      final rb = _codeOf('lib/domain/room_model_rollback.dart');
      expect(core.contains('snapshots.removeAt(1)'), isTrue,
          reason: '_maybeSnapshot 必须保留基线');
      expect(core.contains('snapshots.removeAt(0)'), isFalse,
          reason: '不许回到无脑裁首条');
      expect(rb.contains('snapshots.removeAt(1)'), isTrue,
          reason: '公开的 maybeSnapshot 必须与 _maybeSnapshot 同规则');
      expect(rb.contains('snapshots.removeAt(0)'), isFalse);
      expect(rb.contains("state['seq'] = target < 0 ? 0 : target;"), isTrue,
          reason: '必须显式对齐状态水位');
      expect(rb.contains('apply(r.evt, persist: false)'), isTrue,
          reason: 'Q1 的重放单口不能被改');
      expect(rb.contains('reduceRoomState('), isFalse,
          reason: 'rollback 不许出现第二处归约口');
      expect(rb.contains('snapshots.isEmpty'), isTrue,
          reason: '快照表空了必须重建基线');
    });
  });
}
