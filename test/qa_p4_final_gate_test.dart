// ============================================================
// test/qa_p4_final_gate_test.dart — P4 终验：F3 / F4 / F5 的**独立**复验
//
// 三条都是复核方上一轮提出的缺陷，修完必须重新验，不能沿用「上轮结论」。
//   F3（裁决 A，本期修）：快照窗口打满后的深回退 —— 状态要真退、水位要相等、
//      快照表不能被清空、连续深回退不许崩、adoptSave 之后同样成立、
//      且 Q1 脱敏在「窗口打满 + 无合适快照」时仍然有效。
//   F4（裁决 ①，收口）：玩家 `combat.roll` 的客户端 result 必须被丢弃并由
//      权威端复算；夹带 secret/reqId/damage/... 全部无效；KP 行为不变；
//      POLICY 仍对玩家开放（只是结果不由客户端给）。
//   F5：白名单 9 条路径之外，任何差异（改文案 / 改 seat / 改 seq / 加字段）
//      都必须仍严格报错 —— 白名单不能成为「近似匹配」。
//
// ⚠️ 本文件的断言只依赖「对外可观察行为」，不复用工程师的单测内部断言。
// ============================================================

import 'dart:convert';

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_host_intent.dart';
import 'package:dice_realm/domain/room_model_rollback.dart';
import 'package:dice_realm/domain/room_model_save.dart';
import 'package:dice_realm/domain/room_model_state.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';
import 'support/oracle.dart' show Lcg, oracleNowMs;
import 'support/room_host_script.dart';
import 'support/room_oracle.dart';
import 'support/room_oracle_whitelist.dart';

RoomHost _host({
  int snapshotEvery = 20,
  int snapshotLimit = 20,
  int logCap = 400,
}) =>
    RoomHost(roomHostOpts(
      snapshotEvery: snapshotEvery,
      snapshotLimit: snapshotLimit,
      logCap: logCap,
    ));

void _attachTwo(RoomHost h) {
  h.attachPeer(<String, Object?>{'seat': 'p1', 'nickname': '甲', 'at': 1});
  h.attachPeer(<String, Object?>{'seat': 'p2', 'nickname': '乙', 'at': 2});
}

void _chat(RoomHost h, String text) => h.emit(
      RoomEvt.chat,
      <String, Object?>{'seat': 'p1', 'text': text},
      vis: RoomVis.public,
    );

/// 递归收集字符串值（字节级判泄漏）。
void _collectStrings(Object? v, List<String> out) {
  if (v is Map) {
    for (final e in v.entries) {
      _collectStrings(e.value, out);
    }
    return;
  }
  if (v is List) {
    for (final x in v) {
      _collectStrings(x, out);
    }
    return;
  }
  if (v is String) out.add(v);
}

void main() {
  // ==========================================================
  // F3：快照窗口打满后的深回退
  // ==========================================================
  group('F3 · 深回退（snapshotLimit 打满）', () {
    test('limit=3：rollback(3) 真退到 seq2、水位相等、基线快照保留', () {
      final h = _host(snapshotEvery: 1, snapshotLimit: 3);
      _attachTwo(h);
      for (var i = 0; i < 10; i++) {
        _chat(h, 'x$i');
      }
      final last = h.log.seq; // 12
      // 保留「基线 0 + 最近 2 条」：基线永不淘汰
      expect(h.snapshots.map((s) => s.seq).toList(), <int>[0, last - 1, last],
          reason: 'F3：基线快照(seq0)必须永存，只裁中间的非基线快照');

      final r = h.rollback(3);
      expect(r.seq, 2, reason: 'rollback(3) 的语义是「保留 <3 的事件」→ log.seq=2');
      expect(r.from, 0, reason: '没有任何 seq<=2 的快照 → 必须退化为从建团基线重放');
      // ★ 核心不变式：状态水位 == 日志水位（旧版在这里是 8 vs 2）
      expect(h.state['seq'], h.log.seq,
          reason: 'F3：state.seq 与 log.seq 分叉 → 权威态没跟着退');
      expect(h.state['seq'], 2);
      // 被撤销的事件不得残留
      expect(asList(h.state['chats']), isEmpty,
          reason: 'F3：被撤销的 10 条聊天仍残留在权威态');
      expect(asList(h.state['members']).length, 2,
          reason: '成员表仍应由当前花名册覆盖（回退不该把人抹掉）');
      expect(h.snapshots, isNotEmpty, reason: 'F3：快照表不得被清空');
      expect(h.snapshots.first.seq, 0, reason: 'F3：基线快照必须仍在');
    });

    test('二次 / 连续四次深回退都不崩溃，且每次水位相等', () {
      final h = _host(snapshotEvery: 1, snapshotLimit: 3);
      _attachTwo(h);
      for (var i = 0; i < 10; i++) {
        _chat(h, 'x$i');
      }
      var prevSeq = h.log.seq;
      for (final before in <int>[3, 2, 1, 1]) {
        expect(() => h.rollback(before), returnsNormally,
            reason: 'F3：rollback($before) 崩溃（旧版在第二次深回退抛 StateError）');
        expect(h.state['seq'], h.log.seq,
            reason: 'F3：rollback($before) 之后 state.seq=${h.state['seq']} '
                '≠ log.seq=${h.log.seq}');
        expect(h.log.seq, lessThanOrEqualTo(prevSeq));
        expect(h.snapshots, isNotEmpty);
        expect(h.snapshots.first.seq, 0);
        prevSeq = h.log.seq;
      }
    });

    test('limit=2（最小窗口）：基线 + 1 条，深回退仍正确', () {
      final h = _host(snapshotEvery: 1, snapshotLimit: 2);
      _attachTwo(h);
      for (var i = 0; i < 8; i++) {
        _chat(h, 'y$i');
      }
      final last = h.log.seq;
      expect(h.snapshots.map((s) => s.seq).toList(), <int>[0, last],
          reason: 'limit=2 → 基线 + 最近 1 条');
      h.rollback(4); // target=3，早于 last
      expect(h.state['seq'], 3);
      expect(h.log.seq, 3);
      expect(asList(h.state['chats']).length, 1,
          reason: 'target=3 时只剩 seq3 的那条聊天（两条 attach 在 seq1/2）');
      expect(h.snapshots.first.seq, 0);
    });

    test('adoptSave 之后深回退到存档点之前：不崩溃、水位相等、基线重建', () {
      final h = _host(snapshotEvery: 1);
      _attachTwo(h);
      _chat(h, 'a');
      final save = h.save();
      final restored = RoomHost(roomHostOpts(snapshotEvery: 1))..adoptSave(save);
      final saveSeq = restored.log.seq;
      expect(restored.snapshots.map((s) => s.seq).toList(), <int>[saveSeq],
          reason: 'adoptSave 只留一条 seq=save.seq 的快照');

      expect(() => restored.rollback(1), returnsNormally,
          reason: 'F3：存档点之后深回退崩溃');
      expect(restored.state['seq'], restored.log.seq,
          reason: 'F3：adoptSave + 深回退后水位分叉');
      expect(restored.log.seq, 0);
      expect(restored.snapshots, isNotEmpty, reason: 'F3：快照表被清空');
      expect(restored.snapshots.first.seq, 0, reason: 'F3：应重建 seq0 基线');
      // 再来一次仍然不崩
      expect(() => restored.rollback(1), returnsNormally);
    });

    test('limit=1（极端窗口）：只留基线，深回退仍退得干净', () {
      final h = _host(snapshotEvery: 1, snapshotLimit: 1);
      _attachTwo(h);
      for (var i = 0; i < 6; i++) {
        _chat(h, 'q$i');
      }
      expect(h.snapshots.map((s) => s.seq).toList(), <int>[0],
          reason: 'limit=1 时只剩基线快照');
      h.rollback(4); // target=3 → 只能从基线重放 (0,3]
      expect(h.state['seq'], 3);
      expect(h.log.seq, 3);
      expect(asList(h.state['chats']).length, 1);
      expect(h.snapshots.first.seq, 0);
      expect(() => h.rollback(2), returnsNormally);
      expect(h.state['seq'], h.log.seq);
    });

    test('日志被 logCap 截断后深回退：不崩溃、水位仍相等（内容不可重建属预期）', () {
      final h = _host(snapshotEvery: 5, snapshotLimit: 3, logCap: 3);
      _attachTwo(h);
      for (var i = 0; i < 10; i++) {
        _chat(h, 'w$i');
      }
      expect(h.log.items.first.seq, greaterThan(1),
          reason: 'logCap=3 应已丢掉早期事件');
      expect(() => h.rollback(2), returnsNormally,
          reason: 'F3：日志被截断后深回退崩溃');
      expect(h.state['seq'], h.log.seq,
          reason: 'F3：日志截断场景下水位分叉');
      expect(h.snapshots, isNotEmpty);
    });

    test('roundStarts 随日志一起重建（回退掉回合边界后表里不得残留）', () {
      final h = _host(snapshotEvery: 1, snapshotLimit: 3);
      _attachTwo(h);
      h.emit(RoomEvt.round, <String, Object?>{'round': 1}, vis: RoomVis.public);
      final r1seq = h.log.seq;
      _chat(h, 'a');
      h.emit(RoomEvt.round, <String, Object?>{'round': 2}, vis: RoomVis.public);
      final r2seq = h.log.seq;
      for (var i = 0; i < 6; i++) {
        _chat(h, 'b$i');
      }
      expect(h.roundStarts.length, 2);
      h.rollback(r2seq); // 撤掉 round 2
      expect(h.roundStarts.length, 1, reason: 'F3：被撤销的回合边界仍留在表里');
      expect(asMap(h.roundStarts.single)['round'], 1);
      expect(h.roundStarts.single['seq'], r1seq);
      expect(h.state['seq'], h.log.seq);
    });

    test('Q1 在「窗口打满 + 无合适快照」时仍然脱敏（F3 改动不得带崩 Q1）', () {
      final h = _host(snapshotEvery: 1, snapshotLimit: 2);
      _attachTwo(h);
      h.emit(
        RoomEvt.check,
        <String, Object?>{
          'summary': '秘密检定：骰出 07，极难成功',
          'seat': 'p1',
          'at': 3,
          'kind': 'check',
        },
        vis: RoomVis.seat,
        to: 'p1',
      );
      for (var i = 0; i < 4; i++) {
        _chat(h, 'z$i');
      }
      expect(h.snapshots.map((s) => s.seq).toList(), <int>[0, h.log.seq],
          reason: 'limit=2 时秘密事件所在的中间快照已被裁掉');
      h.rollback(4); // target=3 → 只能从基线 0 重放 (0,3]，区间含秘密 CHECK
      expect(h.state['seq'], h.log.seq);
      final rows = asList(h.state['logs'])
          .map(asMap)
          .where((l) => l['kind'] == 'check')
          .toList();
      expect(rows.length, 1, reason: '重放后应恰有 1 条 check 行');
      expect(rows.single['redacted'], isTrue,
          reason: '★Q1 回归：窗口打满后重放又写出明文行');
      expect(rows.single['text'], 'KP 秘密进行了一次检定');
      expect(rows.single['seat'], '');
      for (final seat in <String>['p1', 'p2', 'ghost']) {
        final strs = <String>[];
        _collectStrings(h.syncFor(seat).toJson(), strs);
        expect(strs.where((s) => s.contains('秘密检定：骰出 07')).toList(), isEmpty,
            reason: '★Q1 回归：syncFor($seat) 泄漏明文');
      }
      final saveStrs = <String>[];
      _collectStrings(h.save(), saveStrs);
      expect(saveStrs.where((s) => s.contains('秘密检定：骰出 07')).toList(), isEmpty,
          reason: '★Q1 回归：save() 泄漏明文');
    });
  });

  // ==========================================================
  // F4：玩家 combat.roll 的客户端 result 必须被丢弃
  // ==========================================================
  group('F4 · 玩家 combat.roll 由权威端复算', () {
    Map<String, Object?> forged([Map<String, Object?> extra = const {}]) =>
        <String, Object?>{
          'op': 'combat.roll',
          'expr': '1D100',
          'label': '攻击',
          'result': <String, Object?>{
            'value': 1,
            'level': 5,
            'levelKey': 'CRITICAL',
            'levelText': '大成功',
            'rolls': <Object?>[1],
            'detail': '1',
          },
          ...extra,
        };

    test('伪造 result 被丢弃：total ≠ 1、levelText ≠ 大成功、expr/label 仍透传', () {
      final h = _host();
      _attachTwo(h);
      final out = h.intent('p1', <String, Object?>{
        'op': RoomIntent.act,
        'p': forged(),
      });
      expect(out, hasLength(1), reason: 'F4：一次玩家掷骰应只产生 1 条计划');
      final msg = out.single.msg.toJson();
      expect(msg['k'], 'evt');
      expect(msg['t'], RoomEvt.dice);
      expect(out.single.to, '*', reason: 'F4：广播对象不变，仍 to:*');
      final dice = asList(h.state['dice']);
      expect(dice, hasLength(1));
      final rec = asMap(dice.single);
      expect(rec['total'], isNot(1),
          reason: 'F4：total 仍照搬客户端 result.value=1（伪造成功）');
      expect(rec['levelText'], isNot('大成功'),
          reason: 'F4：等级文本仍照搬客户端');
      expect(rec['seat'], 'p1');
      expect(rec['expr'], '1D100', reason: 'F4：骰式应照常透传');
      expect(rec['label'], '攻击', reason: 'F4：label 应照常透传');
      // 权威端的复算结果必须自洽：total ∈ 1..100
      expect(jsNum(rec['total']), inInclusiveRange(1, 100));
    });

    test('夹带 secret / reqId / damage / hp / slotId / target：仍 PUBLIC 且零副作用', () {
      final h = _host();
      _attachTwo(h);
      // 先摆一个战斗槽 + 一条待办，用来证伪「夹带字段生效」
      h.applyAction(kHostSeat, <String, Object?>{
        'op': 'combat.set',
        'combat': <String, Object?>{
          'order': <Object?>[
            <String, Object?>{
              'id': 'pc-p1',
              'kind': 'pc',
              'seat': 'p1',
              'public': <String, Object?>{'hp': 10, 'hpMax': 10, 'hpPublic': true},
            },
          ],
          'turn': 0,
          'round': 1,
        },
      });
      h.requestsBySeat['p1'] = <Map<String, Object?>>[
        <String, Object?>{'id': 'r1', 'op': 'check.request', 'payload': <String, Object?>{}},
      ];
      final combatBefore = jsonEncode(h.state['combat']);
      final sheetBefore = jsonEncode(h.roster.get('p1'));
      final reqBefore = jsonEncode(h.requestsBySeat);

      final out = h.intent('p1', <String, Object?>{
        'op': RoomIntent.act,
        'p': forged(<String, Object?>{
          'secret': true,
          'reqId': 'r1',
          'damage': 99,
          'hp': -5,
          'slotId': 'pc-p1',
          'target': 'p2',
        }),
      });
      // ① 仍只有一条 PUBLIC 骰子事件（secret 未被采纳 → 不会变成 SEAT 暗骰）
      expect(out, hasLength(1), reason: 'F4：夹带 secret 产生了额外事件（暗骰分支被触发）');
      expect(out.single.to, '*');
      expect(
        out.where((p) => p.msg.toJson()['k'] == 'evt' &&
                asMap(p.msg.toJson()['p']).containsKey('secret'))
            .toList(),
        isEmpty,
        reason: 'F4：secret 被透传进事件载荷',
      );
      // ② 零副作用：战斗槽 / 角色卡 / 待办队列都没动
      expect(jsonEncode(h.state['combat']), combatBefore,
          reason: 'F4：夹带 slotId/damage 改了战斗槽');
      expect(jsonEncode(h.roster.get('p1')), sheetBefore,
          reason: 'F4：夹带 hp 改了角色卡');
      expect(jsonEncode(h.requestsBySeat), reqBefore,
          reason: 'F4：夹带 reqId 把待办结掉了');
      expect(h.requestsBySeat['p1'], hasLength(1));
      // ③ 没给 p2 发任何东西（target 未生效）
      expect(out.where((p) => p.to == 'p2').toList(), isEmpty);
    });

    test('KP 的 combat.roll 行为不变：客户端 result 仍被权威端直接采用', () {
      final h = _host();
      _attachTwo(h);
      h.intent(kHostSeat, <String, Object?>{
        'op': RoomIntent.act,
        'p': forged(),
      });
      final rec = asMap(asList(h.state['dice']).single);
      expect(rec['total'], 1, reason: 'KP 自己的掷骰结果应照常采用（权威端自己算的）');
      expect(rec['levelText'], '大成功');
    });

    test('POLICY 仍对玩家开放（只是结果不由客户端给）', () {
      expect(needs(RoomRole.player, 'combat.roll').allowed, isTrue);
      expect(needs(RoomRole.player, 'combat.roll').confirm, isNull);
      expect(needs(RoomRole.spectator, 'combat.roll').allowed, isFalse);
    });
  });

  // ==========================================================
  // F5：白名单强度 —— 9 条之外必须仍严格报错
  // ==========================================================
  group('F5 · 白名单外的差异必须仍报错', () {
    final div = kRoomOracleWhitelist.firstWhere((d) => d.caseId == 'S:q1');
    final paths = div.allowedPaths;
    late Map<String, Object?> expectObj;
    late Map<String, Object?> actual;

    /// 只取「白名单涉及的两个子树」，其余键与本组无关。
    Map<String, Object?> sliceOf(Map<String, Object?> full) => <String, Object?>{
          'state': asMap(full['state']),
          'steps': <Object?>[
            for (var i = 0; i < 8; i++) null,
            asMap(asList(full['steps'])[8]),
            asMap(asList(full['steps'])[9]),
          ],
        };

    setUpAll(() {
      // 用**真实**的 S:q1 用例 + 正式 runner 造 actual（不另编数据）
      final fixture = RoomOracleFixture.load('room_sequences.json');
      final c = fixture.cases.firstWhere((x) => x['name'] == 'S:q1#1013');
      final rng = Lcg((c['seed']! as num).toInt());
      setRng(rng.call);
      setClock(() => oracleNowMs);
      actual = sliceOf(runHostScript((c['args'] as Map).cast<String, Object?>()));
      expectObj = sliceOf(asMap(c['expect']));
    });

    test('前置：真实用例在 9 条登记下通过，绕开白名单必须报错', () {
      expect(() => expectJsonMatch(actual, expectObj), throwsA(isA<TestFailure>()),
          reason: 'F5：9 条登记所覆盖的差异竟然不存在 → 白名单又成死登记');
      expect(() => expectJsonMatchExcept(actual, expectObj, paths), returnsNormally);
      expect(paths.length, 9);
    });

    test('改文案（logs[0].text，未登记）必须报错', () {
      final clean = _copy(actual);
      asMap(asList(asMap(clean['state'])['logs'])[0])['text'] = '被改了';
      expect(() => expectJsonMatchExcept(clean, expectObj, paths),
          throwsA(isA<TestFailure>()),
          reason: 'F5：logs[0].text 不在登记里，必须报错');
    });

    test('改 seq（logs[1].seq，未登记）必须报错 —— 登记的是 text/seat/redacted，不含 seq', () {
      final clean = _copy(actual);
      asMap(asList(asMap(clean['state'])['logs'])[1])['seq'] = 999;
      expect(() => expectJsonMatchExcept(clean, expectObj, paths),
          throwsA(isA<TestFailure>()),
          reason: 'F5：seq 被改动却没报错 → 登记范围过宽');
    });

    test('加字段（logs[1].extraFlag，未登记）必须报错', () {
      final clean = _copy(actual);
      asMap(asList(asMap(clean['state'])['logs'])[1])['extraFlag'] = true;
      expect(() => expectJsonMatchExcept(clean, expectObj, paths),
          throwsA(isA<TestFailure>()),
          reason: 'F5：未登记的「多出键」被放过了');
    });

    test('改 steps[8] 的 seq / 新增 steps[10] 都必须报错', () {
      final clean = _copy(actual);
      asMap(asList(clean['steps'])[8])['seq'] = 999;
      expect(() => expectJsonMatchExcept(clean, expectObj, paths),
          throwsA(isA<TestFailure>()));

      final clean2 = _copy(actual);
      asList(clean2['steps']).add(<String, Object?>{'k': 'sync'});
      expect(() => expectJsonMatchExcept(clean2, expectObj, paths),
          throwsA(isA<TestFailure>()),
          reason: 'F5：数组长度变化被放过');
    });

    test('privates 里塞东西必须报错（该路径已从白名单删除）', () {
      final clean = _copy(actual);
      asMap(clean['state'])['privates'] = <Object?>[
        <String, Object?>{'seq': 6, 'text': '线索A'},
      ];
      expect(() => expectJsonMatchExcept(clean, expectObj, paths),
          throwsA(isA<TestFailure>()),
          reason: 'F5：privates 差异被放过（该路径本应已删除）');
    });

    test('登记字段本身被放行（对照组，证明上面不是「全都报错」的假绿）', () {
      final clean = _copy(actual);
      final row = asMap(asList(asMap(clean['state'])['logs'])[1]);
      row['text'] = '任意其它脱敏文案';
      row['seat'] = 'p1';
      expect(() => expectJsonMatchExcept(clean, expectObj, paths), returnsNormally);
    });

    test('coversCase 不会把 S:q10 / S:q1x 误命中', () {
      expect(div.coversCase(<String, Object?>{'name': 'S:q10'}), isFalse);
      expect(div.coversCase(<String, Object?>{'name': 'S:q1x'}), isFalse);
      expect(div.coversCase(<String, Object?>{'name': 'S:q1#1013'}), isTrue);
      expect(div.coversCase(<String, Object?>{'tag': 'S:q1'}), isTrue);
    });
  });
}

/// 深拷贝（只为在断言里就地改，不影响真实 fixture）。
Map<String, Object?> _copy(Object? v) =>
    (jsonDecode(jsonEncode(v)) as Map).cast<String, Object?>();
