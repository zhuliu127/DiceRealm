// ============================================================
// test/p12_kp6_push_details_test.dart — P12 / 第 9 期 · KP-6
//
// 检定推送详情（room_request_watcher.dart，纯 Dart 派生）逐行验收：
//   · details 里没有「来自」开头的行；
//   · 含 `发起人：<角色名>`（不是裸 seat）；
//   · 含 `座位：<seat>`（该行逐字保留）；
//   · `pushInitiatorOf` 回退链 charName → nickname → seat，空 seat 不出行；
//   · `RoomPushRequest.payload` 仍是 `{op, by}` 契约，原始 p 袋另存 source。
//
// ★ 用真实 `RoomHost.pending` 造待办，再调 `collectRoomPushRequests(kpSession)`
//   读真实派生结果 —— 不构造 RoomPushRequest 自证自话。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap;
import 'package:dice_realm/domain/room_types.dart' show RoomIntent, kHostSeat;
import 'package:dice_realm/ui/room/room_request_watcher.dart'
    show RoomPushReply, RoomPushRequest, collectRoomPushRequests, pushInitiatorOf;
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart' show RoomUiFixture;

/// 给权威态的某个 seat 补上 charName / nickname（角色名单一真源 members[].charName）。
void _setMember(
  RoomUiFixture f,
  String seat, {
  String? charName,
  String? nickname,
}) {
  final List<Object?> members = asList(f.hostState()['members']);
  for (final Object? raw in members) {
    final Map<String, Object?> m = asMap(raw);
    if (m['seat']?.toString() != seat) continue;
    if (charName != null) m['charName'] = charName;
    if (nickname != null) m['nickname'] = nickname;
  }
}

/// 往权威端 pending 队列塞一条「玩家主动对抗」待办（字段与 act() 入队一致）。
void _addPending(
  RoomUiFixture f, {
  required String by,
  String op = 'check.opposed',
  Map<String, Object?>? p,
}) {
  f.host.pending.add(<String, Object?>{
    'by': by,
    'op': op,
    'p': p ??
        <String, Object?>{
          'op': op,
          'auto': true,
          'skill': '侦查',
          'seat': by,
          'by': by,
          'defender': <String, Object?>{
            'side': 'monster',
            'actorId': 'm1',
          },
        },
    'need': 'kp',
    'at': 1000,
  });
}

void main() {
  group('A · pushInitiatorOf 回退链（纯函数）', () {
    test('优先 charName；其次 nickname；最后 seat', () {
      final Map<String, Object?> state = <String, Object?>{
        'members': <Object?>[
          <String, Object?>{
            'seat': 'p1',
            'charName': '阿比盖尔',
            'nickname': '玩家1',
          },
          <String, Object?>{
            'seat': 'p2',
            'nickname': '二号调查员',
          },
          <String, Object?>{
            'seat': 'p3',
          },
        ],
      };
      expect(pushInitiatorOf(state, 'p1'), '阿比盖尔');
      expect(pushInitiatorOf(state, 'p2'), '二号调查员');
      expect(pushInitiatorOf(state, 'p3'), 'p3');
      expect(pushInitiatorOf(state, 'p9'), 'p9', reason: '查不到成员回退裸 seat');
    });

    test('空 seat 返回空串（调用方据此不出「发起人」空行）', () {
      expect(pushInitiatorOf(<String, Object?>{}, ''), '');
    });

    test('charName / nickname 为空串时继续回退，不产生空名字', () {
      final Map<String, Object?> state = <String, Object?>{
        'members': <Object?>[
          <String, Object?>{
            'seat': 'p1',
            'charName': '',
            'nickname': '',
          },
        ],
      };
      expect(pushInitiatorOf(state, 'p1'), 'p1');
      expect(pushInitiatorOf(state, 'p1').isNotEmpty, isTrue);
    });

    test('不修改入参（纯函数）', () {
      final Map<String, Object?> state = <String, Object?>{
        'members': <Object?>[
          <String, Object?>{'seat': 'p1', 'charName': '阿比盖尔'},
        ],
      };
      final Map<String, Object?> before = asMap(asList(state['members']).first);
      pushInitiatorOf(state, 'p1');
      expect(asMap(asList(state['members']).first), before);
    });
  });

  group('B · collectRoomPushRequests 逐行详情', () {
    test('无「来自」开头行、含「发起人：角色名」、含「座位：p1」', () {
      final RoomUiFixture f = RoomUiFixture()..bootSync();
      _setMember(f, 'p1', charName: '阿比盖尔·费尔柴尔德', nickname: '玩家1');
      _addPending(f, by: 'p1');

      final List<RoomPushRequest> reqs =
          collectRoomPushRequests(f.sessionOf(kHostSeat));
      expect(reqs, isNotEmpty, reason: 'KP 应产出一条待确认推送');
      final RoomPushRequest r = reqs.firstWhere(
        (RoomPushRequest x) => x.reply == RoomPushReply.confirm,
      );
      // ① 删「来自」整行（PRD §5.5 / KP-6）。
      expect(r.details.any((String l) => l.startsWith('来自')), isFalse,
          reason: 'details 不该再有「来自」行，实测 ${r.details}');
      // ② 发起人取角色名，不是座位号。
      expect(r.details, contains('发起人：阿比盖尔·费尔柴尔德'),
          reason: '实测 details=${r.details}');
      expect(r.details.any((String l) => l == '发起人：p1'), isFalse,
          reason: '发起人不得再显示裸 seat');
      // ③ 「座位」行逐字保留。
      expect(r.details, contains('座位：p1'), reason: '实测 details=${r.details}');
      // ④ 技能行仍来自 p 袋，未因改详情而丢。
      expect(r.details, contains('技能：侦查'), reason: '实测 details=${r.details}');
    });

    test('角色名缺失 → 回退昵称，仍无「来自」行、座位行仍在', () {
      final RoomUiFixture f = RoomUiFixture()..bootSync();
      _setMember(f, 'p1', charName: '', nickname: '老玩家甲');
      _addPending(f, by: 'p1');
      final List<RoomPushRequest> reqs =
          collectRoomPushRequests(f.sessionOf(kHostSeat));
      final RoomPushRequest r = reqs.firstWhere(
        (RoomPushRequest x) => x.reply == RoomPushReply.confirm,
      );
      expect(r.details, contains('发起人：老玩家甲'));
      expect(r.details, contains('座位：p1'));
      expect(r.details.any((String l) => l.startsWith('来自')), isFalse);
    });

    test('payload 严格 {op, by}；原始 p 袋另存 source（PL-1c 判据不污染出站）', () {
      final RoomUiFixture f = RoomUiFixture()..bootSync();
      _setMember(f, 'p1', charName: '阿比盖尔');
      _addPending(f, by: 'p1');
      final RoomPushRequest r = collectRoomPushRequests(f.sessionOf(kHostSeat))
          .firstWhere((RoomPushRequest x) => x.reply == RoomPushReply.confirm);
      expect(r.payload.keys.toSet(), <String>{'op', 'by'},
          reason: 'confirmPending 靠 op+by 定位，载荷不许加字段：${r.payload}');
      expect(r.payload['op'], 'check.opposed');
      expect(r.payload['by'], 'p1');
      expect(asMap(r.source)['auto'], true,
          reason: 'source 应保留原始 p 袋供同意回调判 monster+auto');
      expect(asMap(asMap(r.source)['defender'])['side'], 'monster');
    });

    test('两条不同 pending 各有唯一 id，且都无「来自」行', () {
      final RoomUiFixture f = RoomUiFixture()..bootSync();
      _setMember(f, 'p1', charName: '甲');
      _setMember(f, 'p2', charName: '乙');
      _addPending(f, by: 'p1');
      _addPending(f, by: 'p2');
      final List<RoomPushRequest> reqs =
          collectRoomPushRequests(f.sessionOf(kHostSeat));
      expect(reqs.length, greaterThanOrEqualTo(2));
      expect(<String>{for (final RoomPushRequest r in reqs) r.id}.length,
          reqs.length,
          reason: '去重键必须唯一');
      for (final RoomPushRequest r in reqs) {
        expect(r.details.any((String l) => l.startsWith('来自')), isFalse);
      }
    });
  });

  group('C · 意图契约未因 KP-6 漂移', () {
    test('RoomIntent.sanCheck / act / confirm 仍存在，13 项不变', () {
      expect(RoomIntent.sanCheck, 'sancheck');
      expect(RoomIntent.values.length, 13);
      expect(RoomIntent.values.contains(RoomIntent.confirm), isTrue);
      expect(RoomIntent.values.contains(RoomIntent.act), isTrue);
    });
  });
}
