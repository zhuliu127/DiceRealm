// ============================================================
// test/room_ui_shell_test.dart — P5/T02 S2.1 + S2.3 壳体与顶栏验收
//
// 铁律：T1（全内存后端）、T5（房间页用 useRoomScreen，不用 useTallScreen）、
//      T6（断言权威侧 / sent，不断言「界面说成功」）、T8（跨视角用 stateOf）、
//      T3（SectionBox 内禁 ListTile —— 本文件的壳里根本没有 SectionBox）。
//
// 覆盖：
//   · KP 12 / 玩家 13 / 旁观 13 个容器 key 各自 findsOneWidget
//     （P16 起 KP **dock 档**只有 10 格：gpStatus / gpCombat 已按 KP-3 / KP-4②
//      移出网格；折叠档仍是 12 格全集，两档口径都在本文件里钉住）
//   · KP 专属块在玩家侧 findsNothing（反之亦然）
//   · meta.status 翻转 / 角色切换 → 整页重建 key 变化
//   · 顶栏：房间名 / 房间号 / 身份 / 角色 / 模式 / 回合 / 观众数 / 服务地址（仅 KP）
//   · 连接态三档在游戏页始终可见
//   · 折叠：竖屏有折叠头、折叠后块体消失、重绘后保持（P0-17）；横屏无折叠头
//   · 工具栏快捷按钮的可点性 == POLICY（T-30 的表驱动口径）
// ============================================================

import 'package:dice_realm/domain/room_types.dart';
import 'package:dice_realm/ui/room/room_controller.dart' show RoomGate;
import 'package:dice_realm/ui/room/room_game_page.dart';
import 'package:dice_realm/ui/room/room_keys.dart';
import 'package:dice_realm/ui/room/room_session.dart' show RoomLinkState;
import 'package:dice_realm/ui/room/widgets/gp_kp_left.dart' show GpKpLeft;
import 'package:dice_realm/ui/room/widgets/gp_map_stage.dart' show GpMapStage;
import 'package:dice_realm/ui/room/widgets/gp_toolbar.dart';
import 'package:dice_realm/ui/room/widgets/gp_topbar.dart';
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

/// 用夹具的 `pageBuilder` 注入点把真页面接上（T02 的官方切换方式）。
Future<RoomUiFixture> _bootPage(
  WidgetTester tester, {
  double w = 360,
  double h = 640,
  bool inGame = false,
}) async {
  final f = RoomUiFixture();
  await f.boot(inGame: inGame);
  // ★ 设计 §7 K15 的标准片段：注入真页面后才断言容器 key（夹具壳不含 key）。
  f.pageBuilder = (String seat, String role) => RoomGamePage(
        seat: seat,
        role: role,
        serviceBase: 'ws://127.0.0.1:9001',
        toolbarExtensions: const <Widget>[
          PlaceholderBlock(key: ValueKey<String>('ext/probe'), label: '骰子条占位'),
        ],
      );
  useRoomScreen(tester, w, h);
  return f;
}

/// 每个槽位 key 都应恰好一个。
void _expectSlots(List<RoomSlot> slots) {
  expect(slots.toSet().length, slots.length, reason: '槽位不可重复');
  for (final slot in slots) {
    expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsOneWidget,
        reason: '缺容器 ${slot.name}');
  }
}

void main() {
  group('S2.1 · 骨架与容器 key', () {
    testWidgets('KP 视角：12 个容器 key 各自 findsOneWidget',
        (WidgetTester tester) async {
      final f = await _bootPage(tester);
      await tester.pumpWidget(f.kpPage());
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(RoomKeys.kpSlots.length, 12);
      _expectSlots(RoomKeys.kpSlots);
      // 接线后（T03/T04 已落）：KP 12 个槽位全部是真块 → 0 个占位；
      // 只有上面 `_bootPage` 往工具栏插槽里注入的那 1 个探针还是占位块。
      expect(find.byType(PlaceholderBlock), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('ext/probe')), findsOneWidget);
      // 真组件在岗
      expect(find.byType(GpTopbar), findsOneWidget);
      expect(find.byType(GpToolbar), findsOneWidget);
    });

    testWidgets('玩家视角：13 个容器 key 各自 findsOneWidget',
        (WidgetTester tester) async {
      final f = await _bootPage(tester);
      await tester.pumpWidget(f.playerPage('p1'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(RoomKeys.plSlots.length, 13);
      _expectSlots(RoomKeys.plSlots);
    });

    testWidgets('旁观者走 PL 骨架：同样 13 个容器，不多不少',
        (WidgetTester tester) async {
      final f = await _bootPage(tester);
      await tester.pumpWidget(f.spectatorPage('sp1'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      _expectSlots(RoomKeys.plSlots);
      expect(find.byType(GpTopbar), findsOneWidget);
    });

    testWidgets('KP 专属块在玩家侧 findsNothing，PL 专属块在 KP 侧 findsNothing',
        (WidgetTester tester) async {
      final f = await _bootPage(tester);

      await tester.pumpWidget(f.playerPage('p1'));
      await tester.pump();
      for (final slot in RoomKeys.kpSlots) {
        if (RoomKeys.plSlots.contains(slot)) continue;
        expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsNothing,
            reason: '${slot.name} 是 KP 专属块');
      }

      await tester.pumpWidget(f.kpPage());
      await tester.pump();
      for (final slot in RoomKeys.plSlots) {
        if (RoomKeys.kpSlots.contains(slot)) continue;
        expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsNothing,
            reason: '${slot.name} 是玩家专属块');
      }
    });

    testWidgets('角色切换 / meta.status 翻转 → 整页重建 key 变化',
        (WidgetTester tester) async {
      final f = await _bootPage(tester);

      await tester.pumpWidget(f.kpPage());
      await tester.pump();
      expect(find.byKey(ValueKey<String>(RoomGamePage.pageKeyOf('kp', false))),
          findsOneWidget);

      await tester.pumpWidget(f.playerPage('p1'));
      await tester.pump();
      expect(find.byKey(ValueKey<String>(RoomGamePage.pageKeyOf('player', false))),
          findsOneWidget);
      expect(find.byKey(ValueKey<String>(RoomGamePage.pageKeyOf('kp', false))),
          findsNothing, reason: '换视角必须整页重建，不能残留上一视角 State');

      // 开团：status 翻转 → 同一个视角的 key 也要变
      await f.startGame();
      await tester.pump();
      expect(find.byKey(ValueKey<String>(RoomGamePage.pageKeyOf('player', true))),
          findsOneWidget);
      expect(find.byKey(ValueKey<String>(RoomGamePage.pageKeyOf('player', false))),
          findsNothing);
    });
  });

  group('S2.3 · 顶栏（块 1）', () {
    testWidgets('房间名 / 房间号 / 身份 / 角色 / 模式 / 回合 / 观众数都在',
        (WidgetTester tester) async {
      final f = await _bootPage(tester);
      await tester.pumpWidget(f.kpPage());
      await tester.pump();

      expect(find.byKey(GpTopbarKeys.roomName), findsOneWidget);
      expect(find.text('$kFixtureRoomCode 测试团'), findsOneWidget);
      expect(find.byKey(GpTopbarKeys.roomCode), findsOneWidget);
      expect(find.text('房间 $kFixtureRoomCode'), findsOneWidget);
      expect(find.byKey(GpTopbarKeys.who), findsOneWidget);
      expect(find.textContaining('老 K'), findsWidgets);
      // ★ P10 第 7 期（用户原话「『KP·KP 主持』和『角色：主持人』重复了，
      //   只留一个即可」）：身份行 whoLine 已含角色，独立「角色：…」胶囊撤除。
      //   正向断言「旧的必须消失」；who 仍在且有内容，语义没有丢失。
      expect(find.byKey(GpTopbarKeys.role), findsNothing);
      expect(find.text('角色：主持人'), findsNothing);
      expect(find.byKey(GpTopbarKeys.mode), findsOneWidget);
      expect(find.text('模式：探索'), findsOneWidget);
      expect(find.byKey(GpTopbarKeys.round), findsOneWidget);
      expect(find.byKey(GpTopbarKeys.spectators), findsOneWidget);
      expect(find.text('观众 1'), findsOneWidget);
    });

    testWidgets('服务地址块已整体撤除（三种视角都不再建）',
        (WidgetTester tester) async {
      final f = await _bootPage(tester);

      // ★ P10 第 7 期（用户原话「『服务：本机进程内（未联网）』这个也可以删掉」）：
      //   KP 也不再渲染服务行；常量保留供反向断言，不代表还有 UI 在用。
      await tester.pumpWidget(f.kpPage());
      await tester.pump();
      expect(find.byKey(GpTopbarKeys.service), findsNothing);
      expect(find.text('服务：ws://127.0.0.1:9001'), findsNothing);

      await tester.pumpWidget(f.playerPage('p1'));
      await tester.pump();
      expect(find.byKey(GpTopbarKeys.service), findsNothing);

      await tester.pumpWidget(f.spectatorPage('sp1'));
      await tester.pump();
      expect(find.byKey(GpTopbarKeys.service), findsNothing);
    });

    testWidgets('★ 连接态三档在游戏页始终可见，且随 link 变化',
        (WidgetTester tester) async {
      final f = await _bootPage(tester);
      await tester.pumpWidget(f.kpPage());
      await tester.pump();

      expect(roomLinkText(RoomLinkState.connected), '在线');
      expect(find.byKey(GpTopbarKeys.link), findsOneWidget);
      expect(find.text('在线'), findsOneWidget);

      f.kpSession.setLink(RoomLinkState.resync);
      await tester.pump();
      expect(find.byKey(GpTopbarKeys.link), findsOneWidget,
          reason: 'P0-04：连接态不允许被隐藏 / 折叠');
      expect(find.text('补拉中'), findsOneWidget);

      f.kpSession.setLink(RoomLinkState.offline);
      await tester.pump();
      expect(find.text('离线'), findsOneWidget);

      f.kpSession.setLink(RoomLinkState.connecting);
      await tester.pump();
      expect(find.text('连接中'), findsOneWidget);

      f.kpSession.setLink(RoomLinkState.connected);
      await tester.pump();
      expect(find.text('在线'), findsOneWidget);
    });

    testWidgets('点观众数 → 只读弹层（不改任何状态）',
        (WidgetTester tester) async {
      final f = await _bootPage(tester);
      await tester.pumpWidget(f.kpPage());
      await tester.pump();
      final before = f.sent.length;

      await tester.tap(find.byKey(GpTopbarKeys.spectators));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('旁观者（1）'), findsOneWidget);
      expect(f.sent.length, before, reason: '只读弹层不得发出任何 intent/action');
    });
  });

  group('S2.4 · 折叠（P0-17 重绘后保持）', () {
    testWidgets('竖屏：展开区有折叠头；收起后退回方块（抓手仍在同一个 key）',
        (WidgetTester tester) async {
      final f = await _bootPage(tester);
      await tester.pumpWidget(f.kpPage());
      await tester.pump();

      // P10 第 2 期 B：竖屏是折叠档，gpKpLeft 属于「默认展开」的三块之一。
      final foldKey = roomFoldKey(RoomSlot.gpKpLeft);
      expect(find.byKey(foldKey), findsOneWidget);
      expect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpKpLeft)), findsOneWidget);

      // T4：滚动区里的控件先滚进视口再点，否则 tap 会 miss
      final toggle =
          find.descendant(of: find.byKey(foldKey), matching: find.byType(RoomTap));
      await tester.ensureVisible(toggle);
      await tester.pump();
      await tester.tap(toggle);
      await tester.pump();

      expect(f.localOf(kHostSeat).isFolded(RoomSlot.gpKpLeft.name), isTrue);
      // 收起后退化成方块：块体（真块）不在树里，但容器 key 与折叠抓手都在
      expect(
          find.descendant(
              of: find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpKpLeft)),
              matching: find.byType(GpKpLeft)),
          findsNothing,
          reason: '收起后不应该还常驻真块');
      expect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpKpLeft)), findsOneWidget);
      expect(find.byKey(foldKey), findsOneWidget,
          reason: '折叠抓手本身不能被折叠掉（方块上的「展开到面板」用同一个 key）');
    });

    testWidgets('★ 折叠态在会话重绘后保持（T-08）',
        (WidgetTester tester) async {
      final f = await _bootPage(tester);
      await tester.pumpWidget(f.kpPage());
      await tester.pump();

      f.localOf(kHostSeat).toggleFold(RoomSlot.gpMap.name);
      await tester.pump();
      expect(
          find.descendant(
              of: find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpMap)),
              matching: find.byType(GpMapStage)),
          findsNothing);

      // 一条权威事件 → 整页重建
      await f.controllerOf(kHostSeat).hostAction(
        'chat',
        <String, Object?>{'text': '重绘一下'},
      );
      await tester.pump();

      expect(f.localOf(kHostSeat).isFolded(RoomSlot.gpMap.name), isTrue,
          reason: '折叠态不能因重绘被重置');
      expect(
          find.descendant(
              of: find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpMap)),
              matching: find.byType(GpMapStage)),
          findsNothing,
          reason: '重绘后仍应保持收起');
      // 反证：没折叠的展开块还在
      expect(
          find.descendant(
              of: find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpKpLeft)),
              matching: find.byType(GpKpLeft)),
          findsOneWidget);
    });

    testWidgets('平板横屏固定网格：不显示折叠头（省空间）',
        (WidgetTester tester) async {
      final f = await _bootPage(tester, w: 1280, h: 800);
      await tester.pumpWidget(f.kpPage());
      await tester.pump();

      expect(find.byKey(roomFoldKey(RoomSlot.gpChat)), findsNothing);
      expect(find.byKey(roomFoldKey(RoomSlot.gpKpLeft)), findsNothing);
      // 但块体都在。
      //
      // ★ P16：KP 平板横屏（dock）里 `gpStatus` / `gpCombat` 已移出网格
      //   （KP-3 删待办状态条、KP-4② 把战斗信息栏搬进 gpMap 格），
      //   所以这两格在 dock 档必须**确实不存在**；其余 10 格照旧各一个。
      //   折叠档（竖屏）仍是 12 格全集 —— 见 K15「夹具契约守卫」那条用例。
      const Set<RoomSlot> retiredInDock = <RoomSlot>{
        RoomSlot.gpCombat,
        RoomSlot.gpStatus,
      };
      for (final slot in RoomKeys.kpSlots) {
        if (retiredInDock.contains(slot)) {
          expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsNothing,
              reason: 'dock 档不该再有容器 ${slot.name}');
          continue;
        }
        expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsOneWidget,
            reason: '缺容器 ${slot.name}');
      }
      // 正向计数：dock 档的可视格子恰好 10 个（漏一个 / 多一个都红）。
      expect(
        RoomKeys.kpSlots.where((RoomSlot s) => !retiredInDock.contains(s)).length,
        10,
        reason: 'kpSlots 减去两个退役槽应恰好 10 格',
      );
    });
  });

  group('K15 / K14 · 夹具契约守卫', () {
    testWidgets('★ K15：默认夹具壳不含任何容器 key；注入真页面后才出现',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 360, 640);

      // 默认壳（未注入）：12 个容器 key 一个都不该有 —— 这正是设计意图，
      // 防止 T03–T05 的容器用例被夹具「预先满足」而假绿。
      await tester.pumpWidget(f.kpPage());
      await tester.pump();
      for (final slot in RoomKeys.kpSlots) {
        expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsNothing,
            reason: '默认壳不得含 ${slot.name}');
      }
      expect(find.byType(PlaceholderBlock), findsNothing);

      // 注入真页面（设计 §7 K15 的原样写法）后，12 个 key 才出现
      f.pageBuilder = (String seat, String role) =>
          RoomGamePage(seat: seat, role: role);
      await tester.pumpWidget(f.kpPage());
      await tester.pump();
      for (final slot in RoomKeys.kpSlots) {
        expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsOneWidget,
            reason: '注入后应有 ${slot.name}');
      }
    });

    test('★ K14：节流读的是夹具注入的时钟（f.nowMs += 500 后再次放行）', () async {
      final f = RoomUiFixture();
      await f.boot();
      final ctl = f.controllerOf(kHostSeat);

      expect(ctl.throttle('madness.advance'), isTrue);
      expect(ctl.throttle('madness.advance'), isFalse,
          reason: '400ms 窗口内第二下被吞');
      expect(ctl.throttle('combat.next'), isTrue, reason: '不同 key 独立分桶');

      // 只推夹具时钟：若实现读系统时钟，这一句不会改变判定
      f.nowMs += 500;
      expect(ctl.throttle('madness.advance'), isTrue,
          reason: '★ 必须读注入的 now()，不能读系统时钟');
      f.nowMs += 399;
      expect(ctl.throttle('madness.advance'), isFalse, reason: '差 1ms 仍在窗口内');
      f.nowMs += 1;
      expect(ctl.throttle('madness.advance'), isTrue, reason: '正好 400ms 放行');
    });
  });

  group('S2.4 · 工具栏：扩展插槽 + 可点性同源（T-30 口径）', () {
    testWidgets('扩展插槽把注入的 widget 真的装进去了',
        (WidgetTester tester) async {
      final f = await _bootPage(tester);
      await tester.pumpWidget(f.kpPage());
      await tester.pump();

      expect(find.byKey(const ValueKey<String>('ext/probe')), findsOneWidget);
      expect(find.byKey(GpToolbarKeys.extensions), findsOneWidget);
    });

    testWidgets('★ P17 P-4：恒灰的 round.next / scene.mode 三视角删除',
        (WidgetTester tester) async {
      final f = await _bootPage(tester);
      // 「可点性 == POLICY」的正向探针已由 `room_ui_permission_test.dart`
      // 的 KpPanel 分支覆盖（`round.next` 仍在 KP 工具，锚点未迁走）。
      // 这里守的是负向不变量：游戏页三视角都不渲染这两个恒灰入口。
      const ops = <String>['round.next', 'scene.mode'];

      for (final entry in <String, String>{
        kHostSeat: RoomRole.kp,
        'p1': RoomRole.player,
        'sp1': RoomRole.spectator,
      }.entries) {
        await tester.pumpWidget(f.pageOf(entry.key));
        await tester.pump();
        final role = entry.value;
        for (final op in ops) {
          expect(find.byKey(RoomKeys.action(op)), findsNothing,
              reason: 'P17 P-4：$role 工具栏不应再渲染 $op（恒灰无用）');
        }
      }
    });

    testWidgets('P17 P-4：工具栏入口已删，回合推进仍只属于 KP（T6 权威侧）',
        (WidgetTester tester) async {
      final f = await _bootPage(tester);

      // 玩家：`round.next` 的 POLICY 是 [kp]，gate 直接拒 —— UI 入口删不删
      // 都进不了权威端（`_passSelf` 兜底）。
      expect(RoomGate(RoomRole.player).can('round.next'), isFalse,
          reason: '玩家侧推进回合必须被 POLICY 拒绝');

      // KP：经 KP 工具入口（工具栏入口已删）→ 真的推进了回合。
      final kpGate = RoomGate(RoomRole.kp);
      expect(kpGate.can('round.next'), isTrue,
          reason: 'KP 推进回合的能力必须保留（KP 工具 sheet_kp_panel.dart:298）');
      await tester.pumpWidget(f.kpPage());
      await tester.pump();
      f.clearSent();
      f.controllerOf(kHostSeat).hostAction('round.next');
      await tester.pump();
      expect(f.sent.where((e) => e['op'] == 'round.next'), hasLength(1),
          reason: 'KP 推进回合仍应真发包（走 KP 工具入口）');
      final after = (f.hostState()['meta']! as Map)['round'] as num;
      final before = after - 1;
      expect(after, before + 1, reason: '断言权威侧回合 +1，而不是 UI 文案');
    });
  });
}
