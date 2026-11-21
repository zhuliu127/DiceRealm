// ============================================================
// test/qa_p4_b1_visibility_test.dart — B1 补丁复验（二）：可见性三闸 / POLICY 面 / BOARD
//
// B1 新增了四个「玩家可触发」的入口，最容易出的事故是：
//   · 绕过 emit 直接写 state（可见性三闸失效）；
//   · 为了接上分支顺手往 kRoomPolicy 里加 op（权限面 61→65，打穿门禁）；
//   · 手绘板这类「只有本人该看」的载荷被广播。
// 本文件逐条钉住，并且**用运行期断言**证明「四个 op 不在 POLICY 里」而
// 「intent 仍然结算」——这个不对称是旧版 `Host.intent` 的既有语义
// （只有 INTENT.ACT 走权限链），不是 B1 新增的后门。
// ============================================================

import 'dart:io';

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_host_intent.dart';
import 'package:dice_realm/domain/room_model_state.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';

RoomHost _host() {
  final h = RoomHost(roomHostOpts());
  h.attachPeer(<String, Object?>{'seat': 'p1', 'nickname': '甲', 'at': 1});
  h.attachPeer(<String, Object?>{'seat': 'p2', 'nickname': '乙', 'at': 2});
  return h;
}

/// 去注释后的源码（静态判据用）。
String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .map((line) {
      final i = line.indexOf('//');
      return i < 0 ? line : line.substring(0, i);
    })
    .join('\n');

void main() {
  // ==========================================================
  // 4) BOARD：落笔进权威态，但只有本人收 evt
  // ==========================================================
  group('B1-4 BOARD：手绘板只回本人', () {
    test('落笔写进 boardBySeat / state.board / scene.boards，只有本人收 evt', () {
      final h = _host();
      final out = h.intent('p1', <String, Object?>{
        'op': RoomIntent.board,
        'p': <String, Object?>{
          'strokes': <Object?>[
            <String, Object?>{'x': 1, 'y': 2},
          ],
          'thumb': 'data:png',
        },
      });
      // 权威态三处都写到了
      final bySeat = asMap(h.boardBySeat['p1']);
      expect(asList(bySeat['strokes']), hasLength(1));
      expect(asMap(h.state['board'])['strokes'], hasLength(1));
      final sceneBoards = asMap(asMap(h.state['scene'])['boards']);
      expect(sceneBoards.containsKey('p1'), isTrue);
      expect(asMap(sceneBoards['p1'])['count'], 1);
      // 广播面：只有本人收 evt，其他人收 skip
      final evts = out
          .map((p) => p.toJson())
          .where((j) => asMap(j['msg'])['k'] == 'evt')
          .toList();
      expect(evts, hasLength(1), reason: 'B1：手绘板 evt 被发给了多人');
      expect(evts.single['to'], 'p1');
      final kP2 = asMap(out.firstWhere((p) => p.to == 'p2').msg.toJson());
      expect(kP2['k'], 'skip', reason: 'B1：其他人应只收水位标记');
      expect(out.where((p) => p.to == '*').toList(), isEmpty,
          reason: 'B1：手绘板被广播给全房间');
    });

    test('别人的全量同步看不到我的笔迹（board 为 null），本人能看到', () {
      final h = _host();
      h.intent('p1', <String, Object?>{
        'op': RoomIntent.board,
        'p': <String, Object?>{
          'strokes': <Object?>[
            <String, Object?>{'x': 9},
          ],
        },
      });
      final mine = asMap(h.syncFor('p1').toJson()['state']);
      expect(asMap(mine['board'])['strokes'], hasLength(1),
          reason: 'B1：本人同步里看不到自己的笔迹');
      final other = asMap(h.syncFor('p2').toJson()['state']);
      expect(other['board'], isNull, reason: 'B1：别人的笔迹泄漏进我的同步');
      // 场景里的 boards 只放摘要（count/thumb），不放笔画
      final boards = asMap(asMap(other['scene'])['boards']);
      expect(boards.containsKey('p1'), isTrue);
      expect(asMap(boards['p1']).containsKey('strokes'), isFalse,
          reason: 'B1：scene.boards 里带了完整笔画');
    });

    test('笔迹上限 4000（防一条消息撑爆存档）', () {
      final h = _host();
      h.intent('p1', <String, Object?>{
        'op': RoomIntent.board,
        'p': <String, Object?>{
          'strokes': <Object?>[
            for (var i = 0; i < 5000; i++) <String, Object?>{'x': i},
          ],
        },
      });
      expect(asList(asMap(h.boardBySeat['p1'])['strokes']), hasLength(4000));
      expect(asList(asMap(h.state['board'])['strokes']), hasLength(4000));
      expect(asMap(asMap(asMap(h.state['scene'])['boards'])['p1'])['count'], 4000);
    });
  });

  // ==========================================================
  // 5) 可见性三闸：B1 的四个入口都走 emit，闸门逻辑没被绕开
  // ==========================================================
  group('B1-5 可见性三闸未被破坏', () {
    test('VIS.KP：plan() 恒为空（根本不出门），但权威态仍归约', () {
      final h = _host();
      final rec = h.emit(
        RoomEvt.log,
        <String, Object?>{'text': 'KP 内部备注', 'at': 1},
        vis: RoomVis.kp,
      );
      expect(h.plan(rec), isEmpty);
      expect(asList(h.state['logs']), hasLength(1),
          reason: 'VIS.KP 的事件应仍进权威态');
    });

    test('VIS.SEAT：只有 to 收 evt，其余在线者收 skip（不多不少）', () {
      final h = _host();
      final rec = h.emit(
        RoomEvt.private_,
        <String, Object?>{'title': 't', 'text': '只给 p1', 'at': 1},
        vis: RoomVis.seat,
        to: 'p1',
      );
      final plans = h.plan(rec).map((p) => p.toJson()).toList();
      final evts = plans.where((j) => asMap(j['msg'])['k'] == 'evt').toList();
      final skips = plans.where((j) => asMap(j['msg'])['k'] == 'skip').toList();
      expect(evts, hasLength(1));
      expect(evts.single['to'], 'p1');
      expect(skips.map((j) => j['to']).toList(), <String>['p2']);
    });

    test('PUBLIC 带 secret：被 scrub 且恰好记 1 条 warning', () {
      final h = _host();
      final before = h.warnings.length;
      final rec = h.emit(
        RoomEvt.asset,
        <String, Object?>{
          'assets': <Object?>[
            <String, Object?>{'id': 'a1', 'kpOnly': {'真名': 'x'}, 'hp': 9},
          ],
        },
        vis: RoomVis.public,
      );
      expect(h.warnings.length, before + 1);
      final json = rec.evt.p.toString();
      expect(json.contains('kpOnly'), isFalse, reason: 'PUBLIC 载荷里的 kpOnly 未被剥离');
      final plans = h.plan(rec).map((p) => p.toJson()).toList();
      expect(plans.every((j) => !asMap(j['msg']).toString().contains('kpOnly')), isTrue);
    });

    test('四个 B1 入口都是经 emit 进状态（静态：不出现直写 state[...] =）', () {
      final src = _code('lib/domain/room_model_host_intent.dart');
      // 取出四个 case 的片段，确认它们只是「汇总结算函数的返回」
      for (final call in <String>[
        'diceDirect(seat, mem, role, p)',
        'playerSanCheck(seat, mem, p)',
        'opposed(seat, mem, role, p)',
        'boardSelf(seat, p)',
      ]) {
        expect(src.contains(call), isTrue, reason: 'B1：缺少接线 $call');
      }
      // intent 里不得直接写权威态（唯一例外是 stateSeqAck 的计数）
      final writes = RegExp(r'^\s*state\[[^\]]+\]\s*=', multiLine: true)
          .allMatches(src)
          .length;
      expect(writes, 0, reason: 'B1：intent 层直接写了 state[...]（绕开 apply/emit）');
    });
  });

  // ==========================================================
  // 6) POLICY 面：四个 op 不在表里，但 intent 仍结算
  // ==========================================================
  group('B1-6 POLICY 面与四个入口不入表', () {
    test('kRoomPolicy 恰好 62 条（★ P19：save.share 是唯一新增，其余不变）', () {
      expect(kRoomPolicy.length, 62,
          reason: 'B1 不得把 dice/sancheck/opposed/board 加进权限表；'
              'P19 只新增 save.share（[kp]，存档分发）');
      expect(kRoomPolicy.containsKey('save.share'), isTrue,
          reason: 'P19：save.share 必须显式登记（[kp]）');
    });

    test('四个 INTENT op 名不在表里；ACT 通道的同名别名仍在表里', () {
      for (final op in <String>['dice', 'sancheck', 'opposed', 'board']) {
        expect(kRoomPolicy.containsKey(op), isFalse,
            reason: 'B1：$op 被登记进 POLICY（权限面会打穿门禁与白名单）');
        expect(needs(RoomRole.player, op).allowed, isFalse);
      }
      // 这些是 ACT 通道的既有别名，本来就在表里 —— 不要误判成 B1 违规
      for (final alias in <String>[
        'board.self',
        'dice.request',
        'check.opposed',
        'sheet.sancheck',
      ]) {
        expect(kRoomPolicy.containsKey(alias), isTrue,
            reason: '既有 ACT 别名 $alias 不该被删');
      }
    });

    test('不对称是旧版既有语义：op 不在表里，intent 仍结算', () {
      final h = _host();
      // 未登记 → ACT 通道必拒
      expect(needs(RoomRole.player, 'board').allowed, isFalse);
      // 但 INTENT.BOARD 直接结算（旧版 Host.intent 只有 INTENT.ACT 走 needs）
      final out = h.intent('p1', <String, Object?>{
        'op': RoomIntent.board,
        'p': <String, Object?>{'strokes': <Object?>[]},
      });
      expect(out, isNotEmpty, reason: 'INTENT.BOARD 应仍然结算');
      // ACT 通道拿 'board' 当 op 会被拒（不进结算）
      final denied = h.intent('p1', <String, Object?>{
        'op': RoomIntent.act,
        'p': <String, Object?>{'op': 'board'},
      });
      expect(
        denied.where((p) => asMap(p.toJson()['msg'])['k'] == 'evt').length,
        1,
        reason: 'ACT(board) 应只回一条越权提示',
      );
    });
  });
}
