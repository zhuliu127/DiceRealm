// ============================================================
// test/qa_p4_alias_actions_test.dart — 独立复核：5 个别名 action 的裁决依据
//
// 工程师遗留问题 #1：`room.close` / `room.end` / `combat.roll` / `check.push`
// / `state.edit.self` 在旧版 `applyAction`(:1702-1862) **没有分支**（直调返回空），
// 而本工程的规则层按「61 action 全量实现」补齐了真实结算，因此 fixture 只比了
// needs 权限、没有结算等价比较。本文件补三件事：
//   ① 权限面：玩家绝不能触发 KP-only 的三个（room.close / room.end / check.push），
//      且被拒时**权威态一字不改**（不能只看返回了提示）；
//   ② ★ 结算面：`combat.roll` 原本对玩家开放且会让客户端自带的 result
//      **原样**成为权威公开掷骰记录（可伪造数值）。team-lead 裁决 ① 已修：
//      非 host 改走权威掷骰、忽略 result；本文件据此改为修复后断言；
//   ③ 存档回放面：存档走 `apply(evt) → reduceRoomState`，**不经过** applyAction，
//      故别名补齐不影响旧存档回放（实证 + 静态双证）。
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_host_intent.dart';
import 'package:dice_realm/domain/room_model_save.dart';
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

Map<String, Object?> _act(String op, [Map<String, Object?> p = const {}]) =>
    <String, Object?>{
      'op': RoomIntent.act,
      'p': <String, Object?>{'op': op, ...p},
    };

/// 发给某座位的 evt 信封（SEAT 事件会顺带给其他在线者发 skip，
/// 所以不能拿 out.length 数——那会把水位标记也算进去）。
List<Map<String, Object?>> _evtsTo(List<SendPlan> out, String seat) => out
    .map((p) => p.toJson())
    .where((j) => j['to'] == seat && asMap(j['msg'])['k'] == 'evt')
    .toList();

/// 读源码并去掉 `//` 行注释（静态判据不能把说明文字里的示例当代码）。
String _codeOf(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .map((line) {
      final i = line.indexOf('//');
      return i < 0 ? line : line.substring(0, i);
    })
    .join('\n');

void main() {
  group('别名 action · 权限面（玩家不得触发 KP-only）', () {
    const kpOnlyAliases = <String>['room.close', 'room.end', 'check.push'];

    test('needs()：三个 KP-only 别名对 player/spectator 一律拒绝', () {
      for (final op in kpOnlyAliases) {
        expect(needs(RoomRole.kp, op).allowed, isTrue, reason: '$op 应允许 KP');
        expect(needs(RoomRole.player, op).allowed, isFalse,
            reason: '$op 被玩家拿到（越权）');
        expect(needs(RoomRole.spectator, op).allowed, isFalse);
      }
      expect(needs(RoomRole.player, 'state.edit.self').allowed, isTrue);
      expect(needs(RoomRole.player, 'state.edit.self').confirm, RoomConfirm.kp,
          reason: 'state.edit.self 必须走 KP 二次确认');
      expect(needs(RoomRole.player, 'combat.roll').allowed, isTrue,
          reason: 'combat.roll 在旧版 POLICY 里就对玩家开放（照搬）');
    });

    test('玩家 intent(act) 触发三个 KP-only 别名：只回一条定向提示，权威态零变化', () {
      for (final op in kpOnlyAliases) {
        final h = _host();
        // 注意：拒绝提示本身是一条 SEAT 事件，会推进 state.seq 与日志水位，
        // 所以「零变化」= 除 seq 外的所有状态键不变 + 日志只多这一条。
        final before = jsonEncode(Map<String, Object?>.from(h.state)..remove('seq'));
        final beforeSeq = h.log.seq;
        final out = h.intent('p1', _act(op));
        final toMe = _evtsTo(out, 'p1');
        expect(toMe.length, 1, reason: '$op：越权应只回 1 条定向提示');
        expect(asMap(toMe.single['msg'])['t'], RoomEvt.private_,
            reason: '$op：越权提示应定向（不进公共流）');
        // 其余计划只能是水位标记（skip），不得是 evt
        final otherEvts = out
            .map((p) => p.toJson())
            .where((j) => asMap(j['msg'])['k'] == 'evt' && j['to'] != 'p1')
            .toList();
        expect(otherEvts, isEmpty, reason: '$op：越权提示被广播给了别人');
        final after =
            jsonEncode(Map<String, Object?>.from(h.state)..remove('seq'));
        expect(after, before, reason: '$op：越权调用改动了权威态（除 seq）');
        expect(h.log.seq, beforeSeq + 1,
            reason: '$op：越权调用除提示外还产生了别的事件');
        expect(asMap(h.state['meta'])['status'], RoomStatus.recruiting,
            reason: '$op：越权调用改了房间生命周期状态');
        expect(h.pending, isEmpty, reason: '$op：越权不应入待确认队列');
      }
    });

    test('KP 的 room.close 要过 twice 二次确认，确认后只置 CLOSED 不写 ended', () {
      final h = _host();
      final out = h.intent(kHostSeat, _act('room.close'));
      expect(_evtsTo(out, kHostSeat).length, 1,
          reason: 'KP 应收到 1 条「已提交，等待确认」定向提示');
      expect(h.pending.length, 1, reason: 'twice 类操作必须先入待确认队列');
      expect(asMap(h.state['meta'])['status'], RoomStatus.recruiting,
          reason: '入队阶段不得改状态');
      // KP 自己确认
      h.intent(kHostSeat, <String, Object?>{
        'op': RoomIntent.confirm,
        'p': <String, Object?>{'op': 'room.close', 'by': kHostSeat, 'agree': true},
      });
      expect(asMap(h.state['meta'])['status'], RoomStatus.closed);
      expect(asMap(h.state['meta']).containsKey('ended'), isFalse,
          reason: 'CLOSED 不得写 meta.ended（旧客户端会当终止）');
    });

    test('KP 的 room.end 走 same 通道，但写 ended=true', () {
      final h = _host();
      h.intent(kHostSeat, _act('room.end'));
      h.intent(kHostSeat, <String, Object?>{
        'op': RoomIntent.confirm,
        'p': <String, Object?>{'op': 'room.end', 'by': kHostSeat, 'agree': true},
      });
      expect(asMap(h.state['meta'])['status'], RoomStatus.closed);
      expect(asMap(h.state['meta'])['ended'], isTrue,
          reason: 'ENDED 必须写 meta.ended=true');
    });

    test('玩家 state.edit.self 进 pending（不能直接改自己的重伤/濒死）', () {
      final h = _host();
      final out = h.intent('p1', _act('state.edit.self', <String, Object?>{
        'seat': 'p1',
        'status': <String, Object?>{'currentHP': 3},
      }));
      expect(_evtsTo(out, 'p1').length, 1);
      expect(h.pending.length, 1);
      expect(asMap(h.pending.single)['need'], RoomConfirm.kp);
      // 重复提交同一份 payload → 去重，不产生第二条 pending
      h.intent('p1', _act('state.edit.self', <String, Object?>{
        'seat': 'p1',
        'status': <String, Object?>{'currentHP': 3},
      }));
      expect(h.pending.length, 1, reason: 'pending 去重失效（会刷屏待办）');
    });

    test('伪造 ACT（未登记 op / rollback.turn）一律拒绝且不改状态', () {
      for (final op in <String>['__forged__', 'rollback.turn', '']) {
        final h = _host();
        final before = jsonEncode(Map<String, Object?>.from(h.state)..remove('seq'));
        final out = h.intent('p1', _act(op));
        expect(_evtsTo(out, 'p1').length, 1, reason: '$op：伪造 ACT 未被拒绝');
        final after =
            jsonEncode(Map<String, Object?>.from(h.state)..remove('seq'));
        expect(after, before, reason: '$op：伪造 ACT 改动了权威态（除 seq）');
        expect(asList(h.state['chats']), isEmpty);
      }
    });
  });

  group('别名 action · 结算面', () {
    test('★ combat.roll（玩家）：F4 修复后客户端 result 被忽略，权威端复算', () {
      final h = _host();
      final out = h.intent('p1', _act('combat.roll', <String, Object?>{
        'expr': '1D100',
        'label': '攻击',
        // 玩家自报「大成功」——F4 修复后必须由权威端丢弃并复算
        'result': <String, Object?>{
          'value': 1,
          'level': 5,
          'levelKey': 'CRITICAL',
          'levelText': '大成功',
          'rolls': <Object?>[1],
        },
      }));
      expect(out, isNotEmpty, reason: 'combat.roll 在 Dart 里有真实结算（不是空壳）');
      final dice = asList(h.state['dice']);
      expect(dice.length, 1, reason: '一次 act 仍只写一条权威 dice 记录（结构不变）');
      final rec = asMap(dice.single);
      // 固定 seed=1：权威端 LCG 首值决定个位为 3，total 落在 3/13/.../93，
      // 必然不等于客户端伪造的 1。
      expect(rec['total'], isNot(1),
          reason: 'F4：total 必须来自权威端复算，不得照搬 result.value=1');
      expect(rec['levelText'], isNot('大成功'),
          reason: 'F4：等级文本必须由权威端算，不得照搬客户端');
      expect(rec['seat'], 'p1');
      expect(rec['expr'], '1D100');
      expect(rec['label'], '攻击');
      // 整条事件仍是 PUBLIC 广播（记录结构与广播对象都不变）
      final kinds = out.map((p) => p.toJson()['to']).toList();
      expect(kinds.contains('*'), isTrue, reason: 'F4 不得改变广播对象，仍 to:*');
      // 不越出 dice 记录：不改 HP/角色卡/模式（伤害入口仍 KP-only）
      expect(asMap(h.state['meta'])['mode'], RoomMode.exploration);
    });

    test('combat.roll 不越权：不能借它改 HP / 战斗槽 / 别人的卡', () {
      final h = _host();
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
      final beforeCombat = jsonEncode(h.state['combat']);
      h.intent('p1', _act('combat.roll', <String, Object?>{
        'result': <String, Object?>{'value': 1, 'rolls': <Object?>[1]},
        // 企图夹带伤害字段
        'damage': 99,
        'slotId': 'pc-p1',
      }));
      expect(jsonEncode(h.state['combat']), beforeCombat,
          reason: 'combat.roll 越权改了战斗槽');
      expect(h.roster.get('p1')!['sheet'], isNull,
          reason: 'combat.roll 不应写角色卡');
    });

    test('check.push（KP）产生 SEAT 定向 REQUEST，不广播给其他玩家', () {
      final h = _host();
      final out = h.intent(kHostSeat, _act('check.push', <String, Object?>{
        'seat': 'p1',
        'skill': '侦查',
        'desc': '找线索',
      }));
      final seatEvts = out
          .where((p) => p.msg.toJson()['k'] == 'evt')
          .map((p) => p.toJson())
          .where((j) => j['to'] == 'p1')
          .toList();
      expect(seatEvts, isNotEmpty, reason: 'check.push 应给目标发定向 REQUEST');
      final reqs = h.requestsBySeat['p1'];
      expect(reqs, isNotNull);
      expect(reqs!.length, 1);
      expect(asMap(reqs.single)['op'], 'check.request');
      // 其他玩家不应收到这条 payload
      final leaked = out
          .map((p) => p.toJson())
          .where((j) => j['to'] == 'p2')
          .where((j) => asMap(asMap(j['msg'])['p']).containsKey('skill'))
          .toList();
      expect(leaked, isEmpty, reason: '检定请求泄漏给了非目标玩家');
    });
  });

  group('别名 action · 不影响旧存档回放', () {
    test('静态：重放路径不出现 applyAction（只有 apply+reduce）', () {
      for (final f in <String>[
        'lib/domain/room_model_rollback.dart',
        'lib/domain/room_model_host_core.dart',
        'lib/domain/room_model_reduce.dart',
        'lib/domain/room_model_save.dart',
      ]) {
        final code = _codeOf(f);
        expect(code.contains('applyAction('), isFalse,
            reason: '$f 在回放/存档路径上引用了 applyAction（会把别名结算卷进重放）');
      }
    });

    test('实证：save → restoreHost 幂等，状态逐字节一致（与 applyAction 无关）', () {
      final h = _host();
      h.emit(RoomEvt.chat, <String, Object?>{'seat': 'p1', 'text': 'a'},
          vis: RoomVis.public);
      h.applyAction(kHostSeat, <String, Object?>{
        'op': 'room.close',
      });
      // 别名结算可能与 applyAction 直调不同（这里直接调，绕过 twice）
      final save = h.save();
      final restored = restoreHost(jsonEncode(save))!;
      expect(jsonEncode(restored.state), jsonEncode(h.state),
          reason: '存档往返丢了状态（别名事件与非别名事件不一致）');
      expect(restored.save().keys.toList(), save.keys.toList(),
          reason: '往返后 20 键的键序发生变化');
    });

    test('实证：旧存档只回放日志事件 → 完全没有 applyAction 参与的空间', () {
      final h = _host();
      h.emit(RoomEvt.round, <String, Object?>{'round': 1}, vis: RoomVis.public);
      h.emit(RoomEvt.chat, <String, Object?>{'seat': 'p1', 'text': 'a'},
          vis: RoomVis.public);
      h.emit(RoomEvt.chat, <String, Object?>{'seat': 'p2', 'text': 'b'},
          vis: RoomVis.public);
      final expected = jsonEncode(h.state);

      // 用「同一批事件」从空房间重建（等价于旧存档回放）
      final replay = _host();
      replay.log.items.clear();
      replay.log.seq = 0;
      replay.state = <String, Object?>{
        ...asMap(replay.state),
        'chats': <Object?>[],
        'logs': <Object?>[],
        'seq': 0,
      };
      for (final rec in h.log.items) {
        replay.apply(rec.evt);
      }
      expect(asList(replay.state['chats']).length,
          asList(h.state['chats']).length);
      expect(replay.state['seq'], h.state['seq']);
      expect(jsonEncode(replay.state), expected,
          reason: '同一批事件重放结果与原始状态不一致（可重放性被破坏）');
    });
  });
}
