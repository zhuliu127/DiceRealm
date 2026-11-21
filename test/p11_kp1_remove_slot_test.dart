// ============================================================
// test/p11_kp1_remove_slot_test.dart — KP-1「移出战斗」= 真删槽
//
// 被测：lib/ui/room/widgets/gp_combat_list.dart
//   · `combatBaseId(String)` 顶层纯函数（剥 `#n`）
//   · `removeCombatUnit(RoomScope, String baseId)` 顶层函数（发包 combat.set）
// 口径（源码注释 :347-364）：
//   · 不是 down/dead 标记，而是删除 order 元素；同 base id 的多行动槽一并删；
//   · turn 是索引：i<turn → turn-1、i>turn → 不变、i==turn → clamp(0,len-1)；round 不变；
//   · 载荷带齐 order/turn/round 三键；复用既有 combat.set，不新增 action。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/ui/room/room_scope.dart' show RoomScope;
import 'package:dice_realm/ui/room/widgets/gp_combat_list.dart'
    show combatBaseId, removeCombatUnit;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart' show RoomUiFixture;

Map<String, Object?> _slot(String id) => <String, Object?>{
      'id': id,
      'name': id,
      'kind': 'monster',
      'public': <String, Object?>{'hp': 5, 'hpMax': 5},
    };

RoomScope _scopeOf(RoomUiFixture f) => RoomScope(
      session: f.sessionOf(kHostSeat),
      local: f.localOf(kHostSeat),
      controller: f.controllerOf(kHostSeat),
      child: const SizedBox.shrink(),
    );

/// 建一个含 order/turn/round 的战斗态并返回 fixture。
RoomUiFixture _combat(List<Object?> order, {required int turn, int round = 1}) {
  final f = RoomUiFixture()..bootSync();
  f.hostState()['combat'] = <String, Object?>{
    'order': order,
    'turn': turn,
    'round': round,
  };
  return f;
}

List<String> _ids(RoomUiFixture f) => asList(asMap(f.hostState()['combat'])['order'])
    .map((e) => jsStr(asMap(e)['id']))
    .toList();

void main() {
  group('KP-1 combatBaseId 纯函数', () {
    test('剥掉 #n；无 # 原样返回；多个 # 只认第一个', () {
      expect(combatBaseId('m1'), 'm1');
      expect(combatBaseId('m1#2'), 'm1');
      expect(combatBaseId('a#b#c'), 'a');
      expect(combatBaseId(''), '');
    });
  });

  group('KP-1 removeCombatUnit 真删槽', () {
    test('同 base id 的多行动 #n 槽一并删，round 不变', () {
      final f = _combat(<Object?>[
        _slot('a'),
        _slot('m1'),
        _slot('m1#2'),
        _slot('b'),
      ], turn: 0, round: 3);
      removeCombatUnit(_scopeOf(f), 'm1');
      expect(_ids(f), <String>['a', 'b'], reason: 'm1 与 m1#2 一并删');
      expect(asList(asMap(f.hostState()['combat'])['order']).length, 2);
      expect('${asMap(f.hostState()['combat'])['round']}', '3',
          reason: 'round 不变');
    });

    test('turn 分支 i<turn：删前一个 → turn-1', () {
      final f = _combat(<Object?>[_slot('a'), _slot('b'), _slot('c')], turn: 2);
      removeCombatUnit(_scopeOf(f), 'a');
      expect(_ids(f), <String>['b', 'c']);
      expect('${asMap(f.hostState()['combat'])['turn']}', '1',
          reason: 'index 0 < turn 2 → turn 1');
    });

    test('turn 分支 i>turn：删后面 → turn 不变', () {
      final f = _combat(<Object?>[_slot('a'), _slot('b'), _slot('c')], turn: 0);
      removeCombatUnit(_scopeOf(f), 'c');
      expect(_ids(f), <String>['a', 'b']);
      expect('${asMap(f.hostState()['combat'])['turn']}', '0',
          reason: 'index 2 > turn 0 → 不变');
    });

    test('turn 分支 i==turn：删「末位 + 当前行动」→ clamp 不越界', () {
      final f = _combat(<Object?>[_slot('a'), _slot('b')], turn: 1);
      removeCombatUnit(_scopeOf(f), 'b');
      final c = asMap(f.hostState()['combat']);
      expect(asList(c['order']).length, 1);
      expect('${c['turn']}', '0', reason: 'clamp(0, len-1=0) = 0，不越界');
    });

    test('非末位 i==turn：删当前行动 → turn 不变（后续单位顶上）', () {
      final f = _combat(<Object?>[_slot('a'), _slot('b'), _slot('c')], turn: 1);
      removeCombatUnit(_scopeOf(f), 'b');
      final c = asMap(f.hostState()['combat']);
      expect(_ids(f), <String>['a', 'c']);
      expect('${c['turn']}', '1', reason: '删除索引 1 后新 order[1] 即原 c');
    });

    test('不存在的 base id：order 原样不动（幂等）', () {
      final f = _combat(<Object?>[_slot('a'), _slot('b')], turn: 0);
      removeCombatUnit(_scopeOf(f), 'zzz');
      expect(_ids(f), <String>['a', 'b']);
    });
  });
}
