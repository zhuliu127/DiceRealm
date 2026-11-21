// ============================================================
// test/p11_fix_intent_test.dart — P11 修复批（意图层 3 处已确认缺陷）
//
// 全部改动只落在一个文件：`lib/domain/room_model_host_intent.dart`。
// 本文件是这三处修复的验收靶子，老 APP 对应实现：
//   ① consent 同意后状态不落地 —— 老 `room-model.js:1572-1610`；
//   ② confirmPending 缺 120 秒 TTL —— 老 `:1626` / `:1643-1651`（v2.13.6）；
//   ③ stateSyncAck 写错字段 —— 老 `:3967-3970`。
//
// ★ 铁律：全部内存后端（roomHostOpts 的固定时钟 / LCG /
//   InMemoryRoomSaveStore），零 Timer / 真实 I/O。
// ★ 断言口径：只读权威端 state / roster（证据在权威端落地，不看「发了什么包」
//   就下结论）；TTL 两条额外读 SendPlan 的收件人与文案。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_host_intent.dart';
import 'package:dice_realm/domain/room_model_save.dart' show RoomHostSave;
import 'package:dice_realm/domain/room_model_state.dart' show bodyView;
import 'package:dice_realm/domain/room_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';

// ------------------------------------------------------------
// 脚手架
// ------------------------------------------------------------

Map<String, Object?> _sheet({
  num hp = 10,
  num maxHp = 12,
  num san = 50,
  num maxSan = 60,
  num mp = 10,
  num maxMp = 10,
}) =>
    <String, Object?>{
      'name': '甲',
      'status': <String, Object?>{
        'currentHP': hp,
        'maxHP': maxHp,
        'currentSAN': san,
        'maxSAN': maxSan,
        'currentMP': mp,
        'maxMP': maxMp,
        'currentLuck': 50,
        'body': '正常',
        'dying': false,
        'unconscious': false,
      },
      'mental': <Object?>['正常'],
      'madness': <Object?>[],
      'tempStatus': <Object?>[],
      'items': <Object?>[],
      'skills': <Object?>[
        <String, Object?>{'name': '侦查', 'total': 60, 'base': 60},
      ],
    };

RoomHost _host() {
  final h = RoomHost(roomHostOpts(seed: 3));
  h.attachPeer(<String, Object?>{'seat': 'p1', 'nickname': '甲', 'at': 1});
  h.roster.get('p1')!['sheet'] = _sheet();
  return h;
}

Map<String, Object?> _act(String op, Map<String, Object?> p) =>
    <String, Object?>{
      'op': RoomIntent.act,
      'p': <String, Object?>{'op': op, ...p},
    };

/// KP 发一条状态变更请求，返回权威端记下的请求 id。
String _requestChange(RoomHost h, Map<String, Object?> change) {
  h.intent(kHostSeat, _act('state.request', <String, Object?>{
    'seat': 'p1',
    'change': change,
  }));
  final reqs = h.requestsBySeat['p1'];
  expect(reqs, isNotNull, reason: 'KP 请求必须落进 requestsBySeat');
  expect(reqs, hasLength(1));
  return jsStr(reqs!.single['id']);
}

List<SendPlan> _consent(RoomHost h, String id, {required bool agree}) =>
    h.intent('p1', <String, Object?>{
      'op': RoomIntent.consent,
      'p': <String, Object?>{'id': id, 'agree': agree},
    });

Map<String, Object?> _statusOf(RoomHost h) =>
    asMap(asMap(h.roster.get('p1')!['sheet'])['status']);

/// 私信正文（只收发给 seat 的 `private` 事件）。
List<String> _privatesTo(List<SendPlan> plans, String seat) => <String>[
      for (final p in plans)
        if (p.to == seat &&
            p.msg.toJson()['t'] == RoomEvt.private_)
          jsStr(asMap(p.msg.toJson()['p'])['text']),
    ];

bool _hasEnded(List<SendPlan> plans) => plans.any(
      (p) => p.msg.toJson()['t'] == RoomEvt.ended,
    );

void main() {
  // ========================================================
  // 任务 1（P0）· consent 同意后状态必须落地
  // 老：room-model.js:1572-1610（payload {hp,san,mp}
  //     → {status:{currentHP,currentSAN,currentMP}} → stateApply
  //     → applyStatusJudgment → 再写公共日志）
  // ========================================================
  group('T1 · consent 同意 → 状态真的写进角色卡', () {
    test('T1-1 hp:5 同意 → currentHP 5（sheet + runtime 双写），未濒死', () {
      final h = _host();
      final id = _requestChange(h, <String, Object?>{'hp': 5});
      _consent(h, id, agree: true);

      final st = _statusOf(h);
      expect(st['currentHP'], 5, reason: '同意后 HP 必须真的变成 5');
      expect(asMap(h.roster.get('p1')!['runtime'])['hp'], 5,
          reason: 'stateApply 同时写 runtime.hp（与 stateSelf 同一落地路径）');
      expect(jsTruthy(st['dying']), isFalse);
      expect(jsTruthy(st['unconscious']), isFalse);
      expect(h.requestsBySeat['p1'], isEmpty, reason: '待办卡照旧要摘掉');
    });

    test('T1-2 hp:0 同意 → 触发归零分流（昏迷），不是「卡片没了就完事」', () {
      final h = _host();
      // 先把 HP 压到 5，避免 amount ≥ maxHP 直接判「死亡」。
      _consent(h, _requestChange(h, <String, Object?>{'hp': 5}),
          agree: true);
      expect(_statusOf(h)['currentHP'], 5);

      _consent(h, _requestChange(h, <String, Object?>{'hp': 0}),
          agree: true);
      final st = _statusOf(h);
      expect(st['currentHP'], 0);
      expect(jsTruthy(st['unconscious']), isTrue,
          reason: '5→0 且 5*2 < maxHP12 ⇒ 非重伤，按老口径判昏迷');
      expect(bodyView(st), '昏迷');
    });

    test('T1-3 拒绝 → HP 一点不动，只摘卡', () {
      final h = _host();
      final id = _requestChange(h, <String, Object?>{'hp': 5});
      final plans = _consent(h, id, agree: false);

      expect(_statusOf(h)['currentHP'], 10, reason: '拒绝绝不能改状态');
      expect(asMap(h.roster.get('p1')!['runtime'])['hp'], isNull);
      expect(h.requestsBySeat['p1'], isEmpty);
      expect(
        plans.any((p) => asMap(p.msg.toJson()['p'])['text'].toString().contains(
            '拒绝了状态变更请求')),
        isTrue,
      );
    });

    test('T1-4 san/mp 同一条请求一起落地', () {
      final h = _host();
      _consent(h, _requestChange(h, <String, Object?>{
        'san': 45,
        'mp': 3,
      }), agree: true);

      final st = _statusOf(h);
      expect(st['currentSAN'], 45);
      expect(st['currentMP'], 3);
      final rt = asMap(h.roster.get('p1')!['runtime']);
      expect(rt['san'], 45, reason: 'SAN 必须走 stateApply 的 runtime 记账');
      expect(rt['mp'], 3);
    });

    test('T1-5 越界值被上限夹回（证明真的走了 stateApply 而非直写字段）', () {
      final h = _host();
      _consent(h, _requestChange(h, <String, Object?>{'hp': 999}),
          agree: true);
      expect(_statusOf(h)['currentHP'], 12, reason: 'maxHP=12 必须夹住 999');
    });

    test('T1-6 同意后仍然「只发一条」公共日志，不重复', () {
      final h = _host();
      final plans =
          _consent(h, _requestChange(h, <String, Object?>{'hp': 5}),
              agree: true);
      final logs = <String>[
        for (final p in plans)
          if (p.msg.toJson()['t'] == RoomEvt.log)
            jsStr(asMap(p.msg.toJson()['p'])['text']),
      ];
      expect(
          logs.where((t) => t.contains('KP 调整了') && t.contains('的状态')),
          hasLength(1));
    });
  });

  // ========================================================
  // 任务 2（P0）· confirmPending 的 120 秒 TTL
  // 老：room-model.js:1626 CONFIRM_TTL_MS=120000 / :1643-1651
  // ========================================================
  group('T2 · confirmPending 过期闸门（120 秒）', () {
    /// KP 点一次 `room.end`（need=twice ⇒ 入 pending，不立刻执行）。
    void queueEnd(RoomHost h) {
      final plans =
          h.intent(kHostSeat, _act('room.end', <String, Object?>{}));
      expect(_hasEnded(plans), isFalse, reason: '入队阶段绝不能已经结团');
      expect(h.pending, hasLength(1));
    }

    test('T2-1 at 为 3 分钟前 → 不执行、摘掉待办、KP 收到过期私信', () {
      final h = _host();
      queueEnd(h);
      h.pending.single['at'] = h.now() - 180000;

      final plans = h.intent(kHostSeat, <String, Object?>{
        'op': RoomIntent.confirm,
        'p': <String, Object?>{'op': 'room.end', 'by': kHostSeat, 'agree': true},
      });

      expect(_hasEnded(plans), isFalse, reason: '过期确认不得结团');
      expect(jsTruthy(asMap(h.state['meta'])['ended']), isFalse);
      expect(h.pending, isEmpty, reason: '过期项必须从队列里摘掉');
      final priv = _privatesTo(plans, kHostSeat);
      expect(priv.any((t) => t.contains('已过期')), isTrue,
          reason: '必须私信 KP：这条确认已过期');
    });

    test('T2-2 at 为 10 秒前 → 正常执行（结团）', () {
      final h = _host();
      queueEnd(h);
      h.pending.single['at'] = h.now() - 10000;

      final plans = h.intent(kHostSeat, <String, Object?>{
        'op': RoomIntent.confirm,
        'p': <String, Object?>{'op': 'room.end', 'by': kHostSeat, 'agree': true},
      });

      expect(_hasEnded(plans), isTrue, reason: '未过期的确认必须照常执行');
      expect(jsTruthy(asMap(h.state['meta'])['ended']), isTrue);
      expect(_privatesTo(plans, kHostSeat).any((t) => t.contains('已过期')),
          isFalse);
    });

    test('T2-3 边界：119 秒照执行，121 秒作废', () {
      final fresh = _host();
      queueEnd(fresh);
      fresh.pending.single['at'] = fresh.now() - 119000;
      expect(
        _hasEnded(fresh.intent(kHostSeat, <String, Object?>{
          'op': RoomIntent.confirm,
          'p': <String, Object?>{'op': 'room.end', 'by': kHostSeat, 'agree': true},
        })),
        isTrue,
      );

      final stale = _host();
      queueEnd(stale);
      stale.pending.single['at'] = stale.now() - 121000;
      expect(
        _hasEnded(stale.intent(kHostSeat, <String, Object?>{
          'op': RoomIntent.confirm,
          'p': <String, Object?>{'op': 'room.end', 'by': kHostSeat, 'agree': true},
        })),
        isFalse,
      );
    });

    test('T2-4 at 缺失（老存档）→ 按 0 处理，同样视为过期', () {
      final h = _host();
      queueEnd(h);
      h.pending.single.remove('at');

      final plans = h.intent(kHostSeat, <String, Object?>{
        'op': RoomIntent.confirm,
        'p': <String, Object?>{'op': 'room.end', 'by': kHostSeat, 'agree': true},
      });
      expect(_hasEnded(plans), isFalse);
      expect(h.pending, isEmpty);
      expect(_privatesTo(plans, kHostSeat).any((t) => t.contains('已过期')),
          isTrue);
    });
  });

  // ========================================================
  // 任务 3（P1）· stateSyncAck 只记 stateAckSeq，不动 stateSeq
  // 老：room-model.js:3967-3970
  // ========================================================
  group('T3 · stateSyncAck 记账字段', () {
    test('T3-1 seq:7 → 成员 stateAckSeq=7，stateSeq 不变', () {
      final h = _host();
      final before = h.stateSeq;
      final plans = h.intent('p1', <String, Object?>{
        'op': RoomIntent.stateSync,
        'p': <String, Object?>{'seq': 7},
      });

      expect(h.roster.get('p1')!['stateAckSeq'], 7);
      expect(h.stateSeq, before, reason: '回执绝不能推进权威端状态版本号');
      expect(plans, isEmpty, reason: '回执是静默记账，不占公共序号');
    });

    test('T3-2 连发回执：后到覆盖先到，stateSeq 恒定；且进存档', () {
      final h = _host();
      final before = h.stateSeq;
      for (final seq in <int>[7, 9]) {
        h.intent('p1', <String, Object?>{
          'op': RoomIntent.stateSync,
          'p': <String, Object?>{'seq': seq},
        });
        expect(h.stateSeq, before);
      }
      expect(h.roster.get('p1')!['stateAckSeq'], 9);

      final saved = h.save();
      final row = asList(saved['members'])
          .map(asMap)
          .firstWhere((m) => m['seat'] == 'p1');
      expect(row['stateAckSeq'], 9, reason: 'roster.dump() 整表克隆 ⇒ 自动进存档');
      expect(saved['stateSeq'], 0,
          reason: '存档里的 stateSeq 仍是权威端真实版本号');
    });
  });
}
