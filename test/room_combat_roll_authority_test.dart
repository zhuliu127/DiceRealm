// ============================================================
// test/room_combat_roll_authority_test.dart — F4（裁决 ①）权威掷骰回归
//
// 缺陷（QA 实测）：`combat.roll` 分发直连 `diceRoll(seat, p)`，而 diceRoll
// 直接吃客户端自报的 `p['result']`（value / levelText / rolls），于是玩家
// 一次 intent 就能把「total:1 / 大成功」写进权威 dice 记录并 PUBLIC 广播。
// 旧版 applyAction(:1702-1862) 对该 op 无分支，是别名补齐带来的新面。
//
// 修法（team-lead 裁决 ①）：
//   · 非 host（seat != kHostSeat）改走 diceDirect 的规则服务复算路径，
//     只透传 expr / label / skill，丢弃 result（以及 secret / reqId /
//     base / bonus / penalty 等会影响广播目标或附带结算的字段）；
//   · KP 保持 diceRoll(seat, p) 原样（权威端可自报）；
//   · POLICY 仍为 ['kp','player']；state.dice 记录结构、to:'*' 广播不变。
//
// 本文件全部 Dart-only，不参与 oracle 比较、不登记白名单。
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_host_intent.dart';
import 'package:dice_realm/domain/room_model_state.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';

/// 客户端自报的「大成功」伪造结果（F4 修复后必须被权威端丢弃）。
const Map<String, Object?> _forged = <String, Object?>{
  'value': 1,
  'level': 5,
  'levelKey': 'CRITICAL',
  'levelText': '大成功',
  'rolls': <Object?>[1],
};

RoomHost _host() {
  final h = RoomHost(roomHostOpts()); // seed=1，结果可钉死
  h.attachPeer(<String, Object?>{'seat': 'p1', 'nickname': '甲', 'at': 1});
  h.attachPeer(<String, Object?>{'seat': 'p2', 'nickname': '乙', 'at': 2});
  return h;
}

Map<String, Object?> _act(String op, [Map<String, Object?> p = const {}]) =>
    <String, Object?>{
      'op': RoomIntent.act,
      'p': <String, Object?>{'op': op, ...p},
    };

/// state 去掉 seq / dice 后的快照（用于「除掷骰记录外零副作用」断言）。
String _stateExceptSeqDice(RoomHost h) => jsonEncode(
      Map<String, Object?>.from(h.state)
        ..remove('seq')
        ..remove('dice'),
    );

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
  group('F4 · 非 host 的 combat.roll 走权威掷骰', () {
    test('① 玩家自报大成功：total / levelText 由权威端复算，记录结构不变', () {
      final h = _host();
      final out = h.intent('p1', _act('combat.roll', <String, Object?>{
        'expr': '1D100',
        'label': '攻击',
        'result': <String, Object?>{..._forged},
      }));
      expect(out, isNotEmpty, reason: 'combat.roll 仍要真实结算，不是空壳');
      final dice = asList(h.state['dice']);
      expect(dice.length, 1);
      final rec = asMap(dice.single);
      // 固定 seed=1：权威端 LCG 首值决定个位为 3，total 落在 3/13/.../93，
      // 必然不等于客户端伪造的 1；等级文本也由规则服务重新判级。
      expect(rec['total'], isNot(1),
          reason: 'total 不得照搬 result.value=1');
      expect(rec['levelText'], isNot('大成功'),
          reason: '等级文本不得照搬客户端');
      expect(rec['seat'], 'p1');
      expect(rec['expr'], '1D100');
      expect(rec['label'], '攻击');
      // 记录键集合完全不变（reduce 的 dice 分支未被改动）。
      expect(rec.keys.toSet(), <String>{
        'seq',
        'seat',
        'nickname',
        'expr',
        'rolls',
        'total',
        'level',
        'levelText',
        'label',
        'at',
      });
      // 广播对象仍是 PUBLIC。
      expect(out.map((p) => p.toJson()['to']).toList().contains('*'), isTrue,
          reason: 'F4 不得改变广播对象，仍 to:*');
    });

    test('② 非 1D100 骰式（rollExpr 路径）同样忽略客户端 result', () {
      final h = _host();
      h.intent('p1', _act('combat.roll', <String, Object?>{
        'expr': '2D6',
        'label': '伤害',
        'result': <String, Object?>{..._forged},
      }));
      final rec = asMap(asList(h.state['dice']).single);
      expect(rec['expr'], '2D6');
      expect(rec['total'], isNot(1), reason: '2D6 的权威掷骰结果不可能是 1');
      expect(rec['levelText'], isNot('大成功'));
      expect(asList(rec['rolls']), isNotEmpty,
          reason: 'rollExpr 会产出真实骰组明细，不是客户端的 [1]');
    });

    test('③ 连续两次玩家 combat.roll：结果不同且都不是伪造值', () {
      final h = _host();
      h.intent('p1', _act('combat.roll', <String, Object?>{
        'expr': '1D100',
        'result': <String, Object?>{..._forged},
      }));
      h.intent('p1', _act('combat.roll', <String, Object?>{
        'expr': '1D100',
        'result': <String, Object?>{..._forged},
      }));
      final dice = asList(h.state['dice']);
      expect(dice.length, 2);
      for (final d in dice) {
        expect(asMap(d)['total'], isNot(1));
        expect(asMap(d)['levelText'], isNot('大成功'));
      }
      expect(asMap(dice[0])['total'], isNot(asMap(dice[1])['total']),
          reason: '权威 rng 被消耗两次，两次结果不应相同（证明真的掷了）');
    });
  });

  group('F4 · KP 行为与权限面不变', () {
    test('④ KP（host）调 combat.roll：保持原样，可自报 result', () {
      final h = _host();
      final out = h.intent(kHostSeat, _act('combat.roll', <String, Object?>{
        'expr': '1D100',
        'label': 'KP 检定',
        'result': <String, Object?>{..._forged},
      }));
      expect(out, isNotEmpty);
      final rec = asMap(asList(h.state['dice']).single);
      expect(rec['total'], 1, reason: 'KP 保持原样：result.value 原样落库');
      expect(rec['levelText'], '大成功');
      expect(rec['level'], 'CRITICAL');
      expect(rec['seat'], kHostSeat);
      expect(out.map((p) => p.toJson()['to']).toList().contains('*'), isTrue);
    });

    test('⑤ POLICY 仍是 [kp, player]；dice.roll 仍 KP-only', () {
      expect(kRoomPolicy['combat.roll']!.roles,
          <String>[RoomRole.kp, RoomRole.player],
          reason: 'F4 不得改动 POLICY');
      expect(kRoomPolicy['combat.roll']!.confirm, isNull);
      expect(needs(RoomRole.player, 'combat.roll').allowed, isTrue);
      expect(needs(RoomRole.kp, 'combat.roll').allowed, isTrue);
      expect(needs(RoomRole.spectator, 'combat.roll').allowed, isFalse);
      expect(needs(RoomRole.player, 'dice.roll').allowed, isFalse,
          reason: 'dice.roll 仍 KP-only，未因 F4 一起放宽');
    });
  });

  group('F4 · 不越权 / 不改广播目标', () {
    test('⑥ 夹带 secret / reqId：仍是 PUBLIC 广播，除 dice 外权威态零变化', () {
      final h = _host();
      final before = _stateExceptSeqDice(h);
      final out = h.intent('p1', _act('combat.roll', <String, Object?>{
        'expr': '1D100',
        'label': '偷改广播',
        'result': <String, Object?>{..._forged},
        'secret': true,
        'reqId': 'c1',
      }));
      expect(asList(h.state['dice']).length, 1);
      expect(out.map((p) => p.toJson()['to']).toList().contains('*'), isTrue,
          reason: 'secret 不得把 PUBLIC 广播改成 SEAT 定向');
      expect(_stateExceptSeqDice(h), before,
          reason: 'reqId 不得触发 settleRequest 等附带结算');
    });

    test('⑦ 夹带 damage / hp / slotId / target：不改 HP / 战斗槽 / 别人的卡', () {
      final h = _host();
      h.applyAction(kHostSeat, <String, Object?>{
        'op': 'combat.set',
        'combat': <String, Object?>{
          'order': <Object?>[
            <String, Object?>{
              'id': 'pc-p1',
              'kind': 'pc',
              'seat': 'p1',
              'public': <String, Object?>{
                'hp': 10,
                'hpMax': 10,
                'hpPublic': true,
              },
            },
          ],
          'turn': 0,
          'round': 1,
        },
      });
      final beforeCombat = jsonEncode(h.state['combat']);
      final beforeSheetP2 = jsonEncode(h.roster.get('p2')!['sheet']);
      h.intent('p1', _act('combat.roll', <String, Object?>{
        'result': <String, Object?>{..._forged},
        'damage': 99,
        'hp': -999,
        'slotId': 'pc-p1',
        'target': 'p2',
      }));
      expect(jsonEncode(h.state['combat']), beforeCombat,
          reason: 'combat.roll 不得改动战斗槽 / HP');
      expect(h.roster.get('p1')!['sheet'], isNull);
      expect(jsonEncode(h.roster.get('p2')!['sheet']), beforeSheetP2,
          reason: '不得写别人的角色卡');
      final rec = asMap(asList(h.state['dice']).single);
      expect(rec['total'], isNot(1), reason: '夹带字段也不能把伪造结果写进去');
    });
  });

  group('F4 · 源码钉子（防止改回去）', () {
    test('⑧ 分流判据与 POLICY 登记都还在', () {
      final dispatch = _codeOf('lib/domain/room_model_actions_combat.dart');
      final types = _codeOf('lib/domain/room_types.dart');
      expect(dispatch.contains('if (seat != kHostSeat)'), isTrue,
          reason: 'host / 非 host 分流必须保留');
      expect(dispatch.contains('return diceDirect('), isTrue,
          reason: '非 host 必须走权威掷骰能力');
      expect(dispatch.contains("case 'dice.roll':"), isTrue);
      expect(
        types.contains(
            "'combat.roll': RoomPolicyEntry(<String>[RoomRole.kp, RoomRole.player], null)"),
        isTrue,
        reason: 'POLICY 的 combat.roll 登记一字未动',
      );
    });
  });
}
