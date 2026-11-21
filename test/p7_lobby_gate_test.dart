// ============================================================
// p7_lobby_gate_test.dart — P7-F 大厅阶段门控的**正向守卫**
//
// ★ 只把 findsOneWidget 改成 findsNothing 是「为了绿放宽」—— 本文件的
//   存在就是为了证伪它：证明 5 类游戏期块在游戏期 RoomGamePage 里**仍在**，
//   并证明招募期大厅仍保留「关闭房间 / 踢人 / 复制邀请」三项必要能力。
// ============================================================

import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/ui/room/room_game_page.dart' show RoomGamePage;
import 'package:dice_realm/ui/room/room_keys.dart' show RoomKeys, RoomSlot;
import 'package:dice_realm/ui/room/room_lobby_page.dart'
    show RoomLobbyKeys, RoomLobbyPage;
import 'package:dice_realm/ui/room/room_net_factory.dart'
    show RoomNetFactory;
import 'package:dice_realm/ui/room/widgets/gp_dice_bar.dart' show GpDiceBar;
import 'package:dice_realm/ui/room/widgets/gp_kp_tools.dart' show GpKpTools;
import 'package:dice_realm/ui/room/widgets/gp_map_stage.dart' show GpMapStage;
import 'package:dice_realm/ui/room/widgets/gp_status.dart'
    show GpStatus, GpStatusKeys;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart' show RoomUiFixture, useRoomScreen;

/// 作用域挂在 Navigator 之上：页面与弹层都能 `RoomScope.of`。
Widget _app(RoomUiFixture f, String seat, Widget body) {
  return MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    builder: (BuildContext _, Widget? child) =>
        f.scoped(seat, child: child ?? const SizedBox.shrink()),
    home: body,
  );
}

void main() {
  setUp(() {
    RoomNetFactory.discoveryEnabled = false;
    RoomNetFactory.networkEnabled = false;
    RoomNetFactory.servicePortOverride = 0;
  });
  tearDown(() {
    RoomNetFactory.servicePortOverride = null;
    RoomNetFactory.networkEnabled = true;
  });

  group('F · 正向守卫：游戏期 RoomGamePage 仍承载游戏期块', () {
    testWidgets('★ IN_GAME 且 KP 视角：GpDiceBar / KP 工具 / 探索舞台 / '
        'KP 面板入口全部 findsOneWidget；待办状态条已按 P16 KP-3 移出 KP 网格',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      // P10-2B：改成「平板横屏」档 —— 只有这一档会把 12 个槽位全部摊成
      // 真块（竖屏 / 手机档按用户口述收成方块），语义仍是「全都在」。
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(
        _app(f, kHostSeat, const Scaffold(body: RoomGamePage())),
      );
      await tester.pump();

      // ★ P16 KP-3（规格 _p16_w2_page_report.md）：KP 图的 dock 树删掉了
      //   最底那条「待办」状态条（gpStatus）。所以这里不是「放宽成
      //   findsNothing」而是**口径变更**：KP 网格里必须确实没有它 ——
      //   组件、槽位容器、内部根 key 三层都没有（不是「容器在、内容空」）。
      //   「能力没被删」由下一条玩家视角用例正向证伪（玩家档照旧有）。
      expect(find.byType(GpStatus), findsNothing,
          reason: 'P16 KP-3：KP dock 已把待办状态条移出网格');
      expect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpStatus)), findsNothing,
          reason: '槽位容器也必须不存在，而不是留个空壳');
      expect(find.byKey(GpStatusKeys.root), findsNothing);

      expect(find.byType(GpDiceBar), findsOneWidget,
          reason: 'R12 掷骰条应在游戏期工具栏里');
      expect(find.byKey(RoomKeys.gpDiceBar), findsOneWidget);
      expect(find.byKey(RoomGamePage.kpPanelKey), findsOneWidget,
          reason: 'R10 KP 工具面板入口应在游戏期工具栏里');
      expect(find.byType(GpKpTools), findsOneWidget,
          reason: 'R10 KP 工具窄栏应在 slot 网格里');
      expect(find.byType(GpMapStage), findsOneWidget,
          reason: 'R9 探索舞台应在 slot 网格里');
      expect(tester.takeException(), isNull);
    });

    testWidgets('★ IN_GAME 且玩家视角：待办状态条已按 P20 需求3④ 移出 dock 图，'
        '且 KP 专属块零渲染',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(
        _app(f, 'p1', const Scaffold(body: RoomGamePage())),
      );
      await tester.pump();

      // ★ P20 需求 3④（施工单 D6）：玩家「需我同意」状态条改弹窗后，dock 图里
      //   的 `gpStatus` 叶子删除 —— 与 P16 KP-3 删 KP 侧 `gpStatus` 同一口径。
      //   断言从「必须还在」反转为「dock 里不许再渲染」，并补两条正向反证：
      //   ① 枚举 / `plSlots` 常量本身**没被删小**（不是全局删除）；
      //   ② 竖屏折叠档玩家**仍能看到**待办状态条（方块区里补齐）。
      expect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpStatus)), findsNothing,
          reason: 'P20 需求3④：玩家 dock 不该再有独立状态条格');
      expect(find.byType(GpStatus), findsNothing,
          reason: 'P20 需求3④：玩家 dock 不该渲染状态条组件');
      expect(RoomKeys.plSlots.contains(RoomSlot.gpStatus), isTrue,
          reason: '只删声明节点，`plSlots` 常量不许跟着删小');
      expect(find.byType(GpDiceBar), findsOneWidget,
          reason: 'R12 掷骰条玩家侧同样在');
      // 另一侧边界：KP 专属块不得串进玩家视角。
      expect(find.byType(GpKpTools), findsNothing,
          reason: '玩家视角不该渲染 KP 工具窄栏');
      expect(find.byKey(RoomGamePage.kpPanelKey), findsNothing,
          reason: '玩家视角不该有 KP 面板入口');
      // 地图舞台两侧都有，但玩家侧必须是只读（readOnly = !isKp）。
      expect(tester.widget<GpMapStage>(find.byType(GpMapStage)).readOnly,
          isTrue,
          reason: '玩家侧舞台只读，不能拿到 KP 的落子能力');
      expect(tester.takeException(), isNull);

      // ② 折叠档反证：360×640 竖屏玩家仍能在方块区看到待办状态条。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      useRoomScreen(tester, 360, 640);
      await tester.pumpWidget(
        _app(f, 'p1', const Scaffold(body: RoomGamePage())),
      );
      await tester.pump();
      expect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpStatus)), findsOneWidget,
          reason: '★ 折叠档玩家必须仍有状态条容器：删的是 dock 叶子，不是功能');
    });
  });

  group('F · 招募期大厅门控 + 必要能力保留', () {
    testWidgets('★ RECRUITING：5 类游戏期块零渲染；closeRoom / kick / '
        'copyInvite 仍可用', (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: false);
      useRoomScreen(tester, 900, 2200);
      await tester.pumpWidget(
        _app(f, kHostSeat, const Scaffold(body: RoomLobbyPage())),
      );
      await tester.pump();

      // 5 类游戏期块：房间管理（模式/战斗）、探索面板、KP 工具、待办、掷骰。
      for (final Key k in <Key>[
        RoomLobbyKeys.modeSwitch,
        RoomLobbyKeys.combatPrep,
        RoomLobbyKeys.endCombat,
        RoomLobbyKeys.explore,
        RoomLobbyKeys.sceneEdit,
        RoomLobbyKeys.addAsset,
        RoomLobbyKeys.kpTools,
        RoomLobbyKeys.openKpPanel,
      ]) {
        expect(find.byKey(k), findsNothing,
            reason: '招募期大厅不该渲染游戏期块 $k');
      }
      expect(find.byType(GpStatus), findsNothing);
      expect(find.byType(GpDiceBar), findsNothing);
      expect(find.byKey(RoomKeys.gpDiceBar), findsNothing);

      // ★ 保留能力（F 的取舍）：关闭房间、踢人、复制邀请。
      expect(find.byKey(RoomLobbyKeys.closeRoom), findsOneWidget,
          reason: '招募期 KP 仍必须能关闭房间');
      expect(find.byKey(RoomKeys.action('room.close')), findsOneWidget);
      expect(find.byKey(RoomLobbyKeys.copyInvite), findsOneWidget,
          reason: '招募期仍必须能复制邀请');
      expect(find.byKey(RoomLobbyKeys.kick('p1')), findsOneWidget,
          reason: '招募期 KP 仍必须能踢人');
      expect(find.byKey(RoomKeys.kpStartGame), findsOneWidget,
          reason: 'R6 开始游戏仍在');
      expect(tester.takeException(), isNull);
    });

    testWidgets('玩家视角：游戏期块零渲染，但准备 / 绑卡仍在',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: false);
      useRoomScreen(tester, 900, 2200);
      await tester.pumpWidget(
        _app(f, 'p1', const Scaffold(body: RoomLobbyPage())),
      );
      await tester.pump();

      expect(find.byKey(RoomLobbyKeys.ready), findsOneWidget);
      expect(find.byKey(RoomLobbyKeys.bindChar), findsOneWidget);
      expect(find.byKey(RoomLobbyKeys.closeRoom), findsNothing);
      expect(find.byKey(RoomLobbyKeys.explore), findsNothing);
      expect(find.byKey(RoomLobbyKeys.kpTools), findsNothing);
      expect(find.byType(GpStatus), findsNothing);
      expect(find.byType(GpDiceBar), findsNothing);
    });
  });
}
