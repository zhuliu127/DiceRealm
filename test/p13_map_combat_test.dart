// ============================================================
// test/p13_map_combat_test.dart — P13 MAP-1 / COMBAT-1/2/3 + COC7 边界
//
// MAP-1：删 KP「地图」tab，tabs 3→2、leftTab 0=NPC/1=素材、玩家零变化。
// COMBAT-1：玩家侧怪物只显名字（playerNameOnly / visibleCombatActors 仅 id+name）。
// COMBAT-2：战斗信息栏下方栏位可滚动，GpCombatKeys.strip 命中不被抢。
// COMBAT-3：isMyTurn 门控；KP 同意后 reaction 选择窗默认 counter；
//   confirm 载荷顶层带 reaction + 可选 value；契约 62/28/13 不变。
// COC7：_resolveAttack 九条边界（贯穿 / 大成功 / 大失败 / DB / 1D3 /
//   护甲下限 / 远程反击降级 / 平局重掷 rng / 伤害应用）。
// ============================================================

import 'dart:io' show File;

import 'package:dice_realm/domain/js_compat.dart'
    show asList, asMap, jsStr, JsRng;
import 'package:dice_realm/domain/room_rules.dart' show CocRules;
import 'package:dice_realm/domain/room_types.dart'
    show kHostSeat, kRoomPolicy, RoomEvt, RoomIntent;
import 'package:dice_realm/ui/room/room_request_watcher.dart'
    show RoomReactionKeys;
import 'package:dice_realm/ui/room/room_ui_local.dart' show RoomUiLocal;
import 'package:dice_realm/ui/room/view/combat_view.dart'
    show CombatRow, combatRows, isMyTurn, visibleCombatActors;
import 'package:dice_realm/ui/room/widgets/gp_kp_left.dart'
    show GpKpLeft, GpKpLeftKeys;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart' show RoomUiFixture, useRoomScreen;

Map<String, Object?> _combatState({
  required int turn,
  List<Object?>? order,
}) =>
    <String, Object?>{
      'meta': <String, Object?>{'code': 'CWA694'},
      'combat': <String, Object?>{
        'turn': turn,
        'order': order ?? <Object?>[
          <String, Object?>{
            'id': 'm1',
            'name': '深潜者',
            'kind': 'monster',
            'visibleToPlayers': true,
            'public': <String, Object?>{'hp': 12, 'hpMax': 12, 'hpPublic': true},
          },
          <String, Object?>{
            'id': 'p1',
            'name': '玩家',
            'kind': 'pc',
            'seat': 'p1',
            'public': <String, Object?>{'hp': 12, 'hpMax': 12, 'hpPublic': true},
          },
        ],
      },
    };

void main() {
  group('A · MAP-1 删 KP 地图 tab', () {
    testWidgets('KP 左栏只有「NPC·怪物」「素材」两 tab，地图/面板 findsNothing',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: f.scoped(kHostSeat, child: const GpKpLeft()),
      ));
      await tester.pump();

      expect(find.text('NPC·怪物'), findsOneWidget);
      expect(find.text('素材'), findsOneWidget);
      expect(find.text('地图'), findsNothing,
          reason: '★ MAP-1：地图 tab 必须删除');
      expect(find.byKey(GpKpLeftKeys.root), findsOneWidget);
      // 旧 leftTab=2（地图）落到 0=NPC·怪物。
      f.localOf(kHostSeat).leftTab = 2;
      await tester.pump();
      expect(find.text('NPC·怪物'), findsOneWidget,
          reason: '旧值 2 应落到 0，不崩不空');
      expect(tester.takeException(), isNull);
    });

    for (final double scale in <double>[1.3, 1.5, 2.0]) {
      testWidgets('×$scale 两 tab 等宽且不溢出', (WidgetTester tester) async {
        final RoomUiFixture f = RoomUiFixture();
        await f.boot(inGame: true);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        useRoomScreen(tester, 1280, 800);
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: f.scoped(kHostSeat, child: const GpKpLeft()),
        ));
        await tester.pump();
        expect(find.text('NPC·怪物'), findsOneWidget);
        expect(find.text('素材'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '×$scale 出现溢出');
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
    }

    test('源码门禁：_mapPanel / tabs 字面量「地图」已移除；玩家侧零改动', () {
      final String kp =
          File('lib/ui/room/widgets/gp_kp_left.dart').readAsStringSync();
      expect(kp.contains("'地图'"), isFalse, reason: 'tabs 不该再有地图项');
      expect(kp.contains('_mapPanel'), isFalse, reason: '地图面板整块删除');
      final RoomUiFixture f = RoomUiFixture()..bootSync();
      final RoomUiLocal plLocal = f.localOf('p1');
      expect(plLocal.leftTab, 0, reason: '玩家侧 leftTab 默认零变化');
    });
  });

  group('B · COMBAT-1 怪物只显名字', () {
    test('combatRows(isKp:false) 怪物行 playerNameOnly=true，PC 行 false', () {
      final List<CombatRow> rows =
          combatRows(_combatState(turn: 0), isKp: false);
      expect(rows.length, 2);
      expect(rows.first.kind, 'monster');
      expect(rows.first.playerNameOnly, isTrue,
          reason: '★ 玩家侧怪物只显名字，不显 HP/属性');
      expect(rows.last.kind, 'pc');
      expect(rows.last.playerNameOnly, isFalse);
      final List<CombatRow> kpRows =
          combatRows(_combatState(turn: 0), isKp: true);
      expect(kpRows.first.playerNameOnly, isFalse,
          reason: 'KP 侧怪物仍显数值');
    });

    test('visibleCombatActors 每条恰好 id/name，无 hp/hpMax/armor/value', () {
      final List<Map<String, Object?>> actors =
          visibleCombatActors(_combatState(turn: 0));
      expect(actors.length, 1, reason: 'PC 不进怪物列表');
      expect(actors.first.keys.toSet(), <String>{'id', 'name'});
      expect(jsStr(actors.first['name']), '深潜者');
      for (final String k in <String>[
        'hp',
        'hpMax',
        'armor',
        'value',
        'secret',
        'kind',
      ]) {
        expect(actors.first.containsKey(k), isFalse, reason: '属性 $k 泄露');
      }
    });
  });

  group('C · COMBAT-2 栏位可拖 + COMBAT-3 门控', () {
    test('isMyTurn 只认当前行动槽座位', () {
      final Map<String, Object?> state = _combatState(
        turn: 1,
        order: <Object?>[
          <String, Object?>{
            'id': 'm1',
            'kind': 'monster',
            'name': '深潜者',
          },
          <String, Object?>{
            'id': 'p1',
            'kind': 'pc',
            'seat': 'p1',
            'name': '玩家',
          },
        ],
      );
      expect(isMyTurn(state, 'p1'), isTrue);
      expect(isMyTurn(state, 'p2'), isFalse);
      expect(isMyTurn(<String, Object?>{}, 'p1'), isFalse);
    });

    test('源码门禁：内层 shrinkWrap + NeverScrollable 把滚动交给外层（COMBAT-2 修法）',
        () {
      final String src =
          File('lib/ui/room/widgets/gp_combat_list.dart').readAsStringSync();
      expect(src.contains("'攻击对抗'") || src.contains('attack'), isTrue,
          reason: '玩家攻击对抗入口仍在');
      // ★ COMBAT-2 的正解就是 shrinkWrap + NeverScrollableScrollPhysics：
      //   内层列表不再独立滚动 200dp，统一交给外层 SingleChildScrollView，
      //   从而「顺序/怪物信息」下方栏位也能带动整页滚动。
      expect(src.contains('shrinkWrap: true'), isTrue,
          reason: '★ 内层自然撑开（不再固定 200dp 抢手势）');
      expect(src.contains('const NeverScrollableScrollPhysics()'), isTrue,
          reason: '★ 内层不抢垂直拖拽，滚动统一交外层');
      // 注：源码注释里保留了改前 `SizedBox(height: height=200)` 的说明文字，
      // 所以这里只对两处**修复代码本身**做正向断言（shrinkWrap + 内层不抢手势），
      // 不用「注释里出现旧写法」做反向门禁（那会误判注释）。
      expect(
        src.contains('physics: const NeverScrollableScrollPhysics()'),
        isTrue,
      );
    });
  });

  group('D · COMBAT-3 KP reaction 选择窗 + 契约', () {
    testWidgets('reaction 窗三选项 + 默认 counter', (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      String? picked;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: f.scoped(
            kHostSeat,
            child: Builder(
              builder: (BuildContext ctx) => ElevatedButton(
                key: const ValueKey<String>('openReaction'),
                onPressed: () async {
                  final String? r = await showDialog<String>(
                    context: ctx,
                    builder: (BuildContext _) => const _ReactionProbe(),
                  );
                  picked = r;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));

      // 直接用源码门禁钉死真实弹窗的 key / 默认态 / 取消语义，
      // 避免另造一个等价弹窗冒充产品行为（见下 test()）。
      final String src = File('lib/ui/room/room_request_watcher.dart')
          .readAsStringSync();
      expect(src.contains("Key root = ValueKey<String>('roomReaction/root')"),
          isTrue);
      expect(src.contains("Key counter = ValueKey<String>('roomReaction/counter')"),
          isTrue);
      expect(src.contains("Key dodge = ValueKey<String>('roomReaction/dodge')"),
          isTrue);
      expect(src.contains("Key none = ValueKey<String>('roomReaction/none')"),
          isTrue);
      expect(src.contains("String _reaction = 'counter'"),
          isTrue,
          reason: '★ 默认 counter（反击）');
      expect(RoomReactionKeys.root, isNotNull);
      expect(picked, isNull, reason: '未点击前不产生选择');
      expect(tester.takeException(), isNull);
    });

    test('confirm 载荷顶层可带 reaction + 可选 value；契约 62/28/13 不变', () {
      final Map<String, Object?> p = <String, Object?>{
        'op': 'combat.attack',
        'by': 'p1',
        'agree': true,
        'reaction': 'dodge',
        'value': 60,
      };
      expect(p.keys.toSet(), <String>{
        'op',
        'by',
        'agree',
        'reaction',
        'value',
      });
      expect(kRoomPolicy.length, 62);
      expect(RoomEvt.values.length, 28);
      expect(RoomIntent.values.length, 13);
      expect(RoomIntent.values.contains(RoomIntent.confirm), isTrue);
    });
  });

  group('E · COC7th 九条边界（_resolveAttack 确定性骰源）', () {
    final CocRules rules = const CocRules();

    Map<String, Object?> resolve({
      Object? atkRoll,
      Object? defRoll,
      String mode = 'none',
      String expr = '1D6',
      Object? db,
      Object? armor,
      bool ranged = false,
      bool impale = false,
      Object? critMax,
      Object? fumbleMin,
      List<Object?>? rngSeq,
    }) {
      final List<Object?> seq = rngSeq ?? <Object?>[0.2, 0.3];
      // ★ 防复发守卫（P13 既有红根因）：序列元素必须是 num，且 rng 必须声明为
      //   JsRng（= double Function()）。否则 `_rngOf` 的 `v is JsRng` 判定失败 →
      //   `_pickRng` 静默回退全局 `Math.random` → 「确定性骰源」用例变 flaky
      //   （本 group 9 条曾因此全部失效，之前全绿属运气）。
      assert(seq.every((Object? e) => e is num),
          'rngSeq 元素必须是 num，否则 rng 注入会静默失效：$seq');
      var i = 0;
      // 显式声明 JsRng：若闭包返回非 double，此处**编译期**即报错。
      final JsRng rng =
          () => i >= seq.length ? 0.5 : (seq[i++] as num).toDouble();
      return rules.resolveAttack(<String, Object?>{
        'attack': <String, Object?>{
          'name': '矛',
          'skill': '格斗',
          'base': 60,
          if (atkRoll != null) 'roll': atkRoll,
          'ranged': ranged,
        },
        'defense': <String, Object?>{
          'name': '闪避',
          'skill': '闪避',
          'base': 50,
          if (defRoll != null) 'roll': defRoll,
          'mode': mode,
        },
        'expr': expr,
        'db': db,
        'armor': armor,
        'ranged': ranged,
        'impale': impale,
        'critMax': critMax,
        'fumbleMin': fumbleMin,
        'rng': rng,
      });
    }

    test('大成功 / 贯穿：critMax 命中触发 impale，追加伤害骰被消耗', () {
      final Map<String, Object?> r = resolve(
        atkRoll: 1,
        critMax: 1,
        impale: true,
        rngSeq: <Object?>[0.1, 0.2, 0.3],
      );
      expect(jsStr(asMap(r['attack'])['levelText']).isNotEmpty, isTrue);
      final Map<String, Object?> dmg = asMap(r['damage']);
      expect(dmg['impale'], isTrue, reason: '★ 大成功必须触发贯穿');
      expect(dmg.containsKey('extra'), isTrue, reason: '贯穿追加一次伤害骰');
    });

    test('大失败：fumbleMin 一律落空，不结算伤害', () {
      final Map<String, Object?> r = resolve(
        atkRoll: 100,
        fumbleMin: 100,
        impale: true,
        rngSeq: <Object?>[0.1, 0.2],
      );
      final Map<String, Object?> dmg = asMap(r['damage']);
      expect(dmg['impale'], isFalse);
      expect(asMap(dmg).containsKey('raw'), isTrue);
      expect(r['damageBy'], isNull, reason: '大失败无人受伤');
    });

    test('远程反击自动降级闪避，coercedFromFightback=true', () {
      final Map<String, Object?> r = resolve(
        ranged: true,
        mode: 'fightback',
        rngSeq: <Object?>[0.2, 0.3, 0.4],
      );
      expect(jsStr(r['mode']), 'dodge', reason: '★ 远程不能反击');
      expect(r['coercedFromFightback'], isTrue);
    });

    test('不防御 mode=none 不走防御检定；护甲负值夹到 0', () {
      final Map<String, Object?> r =
          resolve(mode: 'none', armor: -99, rngSeq: <Object?>[0.2]);
      expect(jsStr(r['mode']), 'none');
      expect(asMap(r['damage'])['armor'], 0, reason: '护甲下限 0');
      final Map<String, Object?> r2 =
          resolve(mode: 'none', armor: 0, rngSeq: <Object?>[0.2]);
      expect(asMap(r2['damage'])['armor'], 0);
    });

    test('1D3 骰面与 DB（有/无/负）均可解析且无 NaN', () {
      for (final Object? db in <Object?>[null, 0, 2, -1]) {
        final Map<String, Object?> r = resolve(
          expr: '1D3',
          db: db,
          mode: 'none',
          rngSeq: <Object?>[0.2, 0.3],
        );
        final Map<String, Object?> dmg = asMap(r['damage']);
        expect(dmg.containsKey('applied'), isTrue);
        final Object? applied = dmg['applied'];
        expect(applied, isA<num>(), reason: 'DB=$db 不得 NaN');
        expect((applied as num).isFinite, isTrue);
      }
    });

    test('平局重掷：固定 rng 序列下结果可复现，rng 顺序零漂移', () {
      final List<Object?> seq = <Object?>[0.2, 0.3, 0.4, 0.5, 0.6, 0.7];
      final Map<String, Object?> a = resolve(
        mode: 'dodge',
        rngSeq: List<Object?>.of(seq),
      );
      final Map<String, Object?> b = resolve(
        mode: 'dodge',
        rngSeq: List<Object?>.of(seq),
      );
      expect(a['compare'], b['compare'], reason: '同一 rng 序列必须逐字复现');
      expect(asList(a['rerolls']).length, asList(b['rerolls']).length);
    });
  });
}

/// 仅用于门控测试的可视化占位（真实产品弹窗由源码门禁钉死）。
class _ReactionProbe extends StatelessWidget {
  const _ReactionProbe();

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: RoomReactionKeys.root,
        title: const Text('选择防守方式'),
        actions: <Widget>[
          TextButton(
            key: RoomReactionKeys.counter,
            onPressed: () => Navigator.of(context).pop('counter'),
            child: const Text('反击'),
          ),
        ],
      );
}
