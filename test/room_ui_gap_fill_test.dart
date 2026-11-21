// ============================================================
// test/room_ui_gap_fill_test.dart — P5/T05-B2c · 补齐 3 条 PRD 要求的入口
//
// 背景：`qa_p5_ui.js` + T-30 探针盘出 POLICY 61 个动作里有 7 条在 UI 上
// 没有入口。逐条回溯 PRD 后确认其中 **3 条是 PRD 明确要求、本期漏做**，
// 不是「未排期」：
//
//   ① `madness.advance` — `_p5_prd.md:356`（块 2 规格「⏩推进1轮」，
//      注明「**不受操作锁限制**」）+ `:508`（[player,kp]）+ `:687` S7
//      「整体操作锁只放行 madness.advance 等自助动作」→ **P0**
//   ② `combat.enqueue` — `_p5_prd.md:305`（块 6「＋加入 → combat.enqueue {seat}」）
//      + `:513`（[kp]）→ **P0**
//   ③ `item.del` — `_p5_prd.md:430` + `:522`（[kp,player]）+ `:760` P2-02
//
// 三条都断言 `host.state`（不是 `sent`）：点得动不算数，权威态真变了才算数。
// 铁律：T1 全内存后端；T5 `useRoomScreen`；T6 负向断言才看 `sent`。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/ui/room/room_keys.dart' show RoomKeys;
import 'package:dice_realm/ui/room/sheets/sheet_misc.dart'
    show MiscSheet, MiscSheetKeys;
import 'package:dice_realm/ui/room/widgets/gp_combat_list.dart'
    show GpCombatKeys, GpCombatList;
import 'package:dice_realm/ui/room/widgets/gp_pl_char_card.dart'
    show GpPlCharCard, GpPlCharCardKeys;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart' show RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

// ------------------------------------------------------------
// 夹具
// ------------------------------------------------------------

Future<RoomUiFixture> _boot(WidgetTester tester) async {
  final RoomUiFixture f = RoomUiFixture();
  await f.boot(inGame: true);
  useRoomScreen(tester, 900, 1600);
  return f;
}

Widget _hostApp(RoomUiFixture f, String seat, Widget body) {
  return MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    builder: (BuildContext _, Widget? child) => f.scoped(
      seat,
      child: child ?? const SizedBox.shrink(),
    ),
    home: Scaffold(body: SingleChildScrollView(child: body)),
  );
}

/// 权威端某座位的花名册记录（真源；不是裁剪视图）。
Map<String, Object?> _rosterOf(RoomUiFixture f, String seat) {
  final Map<String, Object?>? m = f.host.roster.get(seat);
  expect(m, isNotNull, reason: '花名册里没有 $seat');
  return m!;
}

Map<String, Object?> _sheetOf(RoomUiFixture f, String seat) =>
    asMap(_rosterOf(f, seat)['sheet']);

/// 改权威端前置状态并推给所有客户端（照既有用例的 `_patchMember` 手法）。
Future<void> _patchMember(
  RoomUiFixture f,
  String seat,
  void Function(Map<String, Object?> member) edit,
) async {
  edit(_rosterOf(f, seat));
  for (final String s in f.clientSeats) {
    await f.kpSession.pullSync(s);
  }
}

void main() {
  // ----------------------------------------------------------
  // ① madness.advance（P0，块 2 / S7）
  // ----------------------------------------------------------
  group('madness.advance · 操作锁期间唯一可点的自助动作', () {
    testWidgets('昏迷 + 临时疯狂发作中：按钮仍渲染且可点，点后权威态疯狂轮次推进',
        (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      await _patchMember(f, 'p1', (Map<String, Object?> m) {
        final Map<String, Object?> st = asMap(asMap(m['sheet'])['status']);
        st['unconscious'] = true;
        final Map<String, Object?> sheet = asMap(m['sheet']);
        sheet['mental'] = <Object?>['临时疯狂'];
        sheet['madness'] = <Object?>[
          <String, Object?>{
            'name': '临时疯狂：恐惧症',
            'from': '临时疯狂',
            'rounds': 2,
          },
        ];
      });

      await tester.pumpWidget(_hostApp(f, 'p1', GpPlCharCard()));
      await tester.pump();

      // 前置自检：确实进了操作锁
      expect(find.byKey(GpPlCharCardKeys.locked), findsOneWidget,
          reason: '前置：昏迷应触发操作锁横幅');

      final Finder advance = find.byKey(RoomKeys.action('madness.advance'));
      expect(advance, findsOneWidget,
          reason: '★ S7：锁定期间「推进 1 轮」必须**渲染**（它是唯一的自助动作）');
      expect(tester.widget<RoomTap>(advance).enabled, isTrue,
          reason: '锁定期间仍必须可点（PRD :356「不受操作锁限制」）');
      expect(tester.widget<RoomTap>(advance).enabled,
          f.controllerOf('p1').gate.can('madness.advance'),
          reason: '可点性应恒等闸门（闸门不看操作锁，锁的放行在权威端 _passSelf）');

      // 对照：其余入口在锁定期间仍结构性隐藏
      for (final Key k in <Key>[
        GpPlCharCardKeys.stateBtn,
        GpPlCharCardKeys.itemsBtn,
        GpPlCharCardKeys.aiBtn,
      ]) {
        expect(find.byKey(k), findsNothing,
            reason: '锁定期间 $k 必须不渲染');
      }

      // 点 → 权威态疯狂轮次真的 -1
      final List<Object?> before = asList(_sheetOf(f, 'p1')['madness']);
      expect(asMap(before.first)['rounds'], 2, reason: '前置：轮次应为 2');

      await tester.tap(advance);
      await tester.pump();

      final List<Object?> after = asList(_sheetOf(f, 'p1')['madness']);
      expect(after, isNotEmpty, reason: '轮次 2 → 1 后记录不该消失');
      expect(asMap(after.first)['rounds'], 1,
          reason: '点「推进 1 轮」后权威态 rounds 应 2 → 1，实际 ${asMap(after.first)['rounds']}');
    });

    testWidgets('描卡（永久疯狂）时不渲染：只剩聊天（T-20 口径不被 S7 打穿）',
        (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      await _patchMember(f, 'p1', (Map<String, Object?> m) {
        asMap(m['sheet'])['mental'] = <Object?>['永久疯狂'];
      });

      await tester.pumpWidget(_hostApp(f, 'p1', GpPlCharCard()));
      await tester.pump();

      expect(find.byKey(GpPlCharCardKeys.locked), findsOneWidget);
      expect(find.text('已撕卡 / 无法行动：只能聊天'), findsOneWidget,
          reason: '撕卡文案不能被 S7 改掉');
      expect(find.byKey(RoomKeys.action('madness.advance')), findsNothing,
          reason: '撕卡后连「推进 1 轮」也不给（死亡/永久疯狂 = 只能聊天）');
    });

    testWidgets('未锁定时也渲染（块 2 常规按钮）', (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, 'p1', GpPlCharCard()));
      await tester.pump();
      expect(find.byKey(GpPlCharCardKeys.locked), findsNothing);
      final Finder advance = find.byKey(RoomKeys.action('madness.advance'));
      expect(advance, findsOneWidget);
      expect(tester.widget<RoomTap>(advance).enabled, isTrue);
    });
  });

  // ----------------------------------------------------------
  // ② combat.enqueue（P0，块 6）
  // ----------------------------------------------------------
  group('combat.enqueue · KP 把未参战玩家追加入场', () {
    testWidgets('选未参战玩家 → 权威态 combat.order 多出该座位的槽位',
        (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      // 先用真实 action 进战斗态（`combat.start` 空池）
      await f.controllerOf(kHostSeat)
          .hostAction('combat.start', <String, Object?>{
        'actorIds': <Object?>[],
        'actors': <Object?>[],
        'pcSeats': <Object?>[],
      });
      await tester.pump();

      await tester.pumpWidget(_hostApp(f, kHostSeat, const GpCombatList()));
      await tester.pump();

      final Finder open = find.byKey(GpCombatKeys.enqueue);
      expect(open, findsOneWidget, reason: 'KP 战斗列表应有「＋加入」入口');
      expect(tester.widget<RoomTap>(open).enabled,
          f.controllerOf(kHostSeat).gate.can('combat.enqueue'),
          reason: '可点性应恒等闸门');

      await tester.tap(open);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 候选里应能看到 p1 / p2（都还没参战）
      final Finder pick = find.byKey(GpCombatKeys.enqueueRow('p1'));
      expect(pick, findsOneWidget, reason: '候选列表应列出未参战的 p1');
      await tester.tap(pick);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final List<Object?> order =
          asList(asMap(f.hostState()['combat'])['order']);
      expect(order, isNotEmpty, reason: '追加入场后 combat.order 不该还是空的');
      final Iterable<Object?> p1slots = order.where(
          (Object? x) => jsStr(asMap(x)['seat']) == 'p1');
      expect(p1slots.length, 1,
          reason: 'p1 应恰好有一个参战槽位，实际 order=$order');
      expect(jsStr(asMap(p1slots.first)['kind']), 'pc');
    });

    testWidgets('玩家 / 旁观视角：没有「＋加入」（结构上不渲染）',
        (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      for (final String seat in <String>['p1', 'sp1']) {
        await tester.pumpWidget(_hostApp(f, seat, const GpCombatList()));
        await tester.pump();
        expect(find.byKey(GpCombatKeys.enqueue), findsNothing,
            reason: '$seat 视角不该渲染「＋加入」（POLICY 只放 KP）');
      }
    });
  });

  // ----------------------------------------------------------
  // ③ item.del（P2-02）
  // ----------------------------------------------------------
  group('item.del · 从房卡物品里删除', () {
    testWidgets('点删除 → 该物品从权威态 items 里消失（其余物品不受影响）',
        (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      await _patchMember(f, 'p1', (Map<String, Object?> m) {
        asMap(m['sheet'])['items'] = <Object?>[
          <String, Object?>{'id': 'it_a', 'name': '手电筒', 'qty': 1},
          <String, Object?>{'id': 'it_b', 'name': '绳索', 'qty': 2},
        ];
      });

      await tester.pumpWidget(_hostApp(f, 'p1', const MiscSheet()));
      await tester.pump();

      final Finder del = find.byKey(MiscSheetKeys.itemDel('it_a'));
      expect(del, findsOneWidget, reason: '每行物品应有删除入口');
      expect(asList(_sheetOf(f, 'p1')['items']).length, 2, reason: '前置：两件物品');

      // 删不可逆 → ConfirmTwice：第一下上膛，第二下才真删
      await tester.tap(del);
      await tester.pump();
      expect(asList(_sheetOf(f, 'p1')['items']).length, 2,
          reason: '第一下不该真删（要二次确认）');

      await tester.tap(del);
      await tester.pump();

      final List<Object?> left = asList(_sheetOf(f, 'p1')['items']);
      expect(left.length, 1, reason: '第二下应真删，剩 1 件，实际 $left');
      expect(jsStr(asMap(left.first)['id']), 'it_b',
          reason: '删错物品了：应只剩 it_b');
    });

    testWidgets('旁观者视角：没有删除入口（POLICY [kp,player]）',
        (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      await _patchMember(f, 'sp1', (Map<String, Object?> m) {
        asMap(m['sheet'])['items'] = <Object?>[
          <String, Object?>{'id': 'it_x', 'name': '不该能删', 'qty': 1},
        ];
      });
      await tester.pumpWidget(_hostApp(f, 'sp1', const MiscSheet()));
      await tester.pump();
      expect(find.byKey(MiscSheetKeys.itemDel('it_x')), findsNothing,
          reason: '旁观者不该有删除入口');
    });
  });
}
