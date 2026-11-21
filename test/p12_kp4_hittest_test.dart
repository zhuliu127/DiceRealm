// ============================================================
// test/p12_kp4_hittest_test.dart — P12 / 第 9 期 · KP-4
//
// 收起玩家信息栏后，场景检定栏「所有按钮可点、可拖动」：
//   · 回调被真实触发（出站计划 +1 / 弹层打开，计数 ≥1）；
//   · hitTest 命中目标是场景检定栏按钮自身，不是收起栏的透明遮罩；
//   · GpSceneCheckKp 仍在树中（不卸载，沿用 P11 RoomStackNode 叠放裁决）；
//   · RoomStackNode Rect / 槽位 rect 前后逐边不变（room_layout.dart 零 diff）。
// ============================================================

import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/ui/room/room_game_page.dart' show RoomGamePage;
import 'package:dice_realm/ui/room/room_keys.dart' show RoomKeys, RoomSlot;
import 'package:dice_realm/ui/room/widgets/gp_kp_players.dart'
    show GpKpPlayersKeys;
import 'package:dice_realm/ui/room/widgets/gp_scene_check_kp.dart'
    show GpSceneCheckKeys, GpSceneCheckKp;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart' show RoomTap;
import 'package:flutter/gestures.dart' show HitTestEntry, HitTestResult;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderBox, RenderObject;
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart' show RoomUiFixture, useRoomScreen;

/// node 是否落在 ancestor 的子树里（含自身）；RenderObject.parent 沿渲染树上溯。
bool _within(RenderObject node, RenderObject ancestor) {
  RenderObject? cur = node;
  while (cur != null) {
    if (identical(cur, ancestor)) return true;
    cur = cur.parent;
  }
  return false;
}

void main() {
  testWidgets('收起后场景检定栏按钮回调计数≥1 + hitTest 命中 + 树保留 + Rect 不变',
      (WidgetTester tester) async {
    final RoomUiFixture f = RoomUiFixture();
    await f.boot(inGame: true);
    f.pageBuilder = (String s, String r) => const RoomGamePage();
    useRoomScreen(tester, 1280, 800);
    await tester.pumpWidget(f.pageOf(kHostSeat));
    await tester.pump();

    final Finder sceneSlot = find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpScene));
    final Finder playersSlot =
        find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlayers));
    expect(sceneSlot, findsOneWidget);
    expect(playersSlot, findsOneWidget);
    final Rect sceneBefore = tester.getRect(sceneSlot);
    final Rect playersBefore = tester.getRect(playersSlot);

    // ① 收起（纯本机态，绝不卸载另一格）。
    final Finder toggle = find.byKey(GpKpPlayersKeys.collapseToggle);
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await tester.pump();
    expect(f.localOf(kHostSeat).playersPanelCollapsed, isTrue);

    // ② GpSceneCheckKp 仍在树中，技能输入框 / 保留按钮都还在。
    expect(find.byType(GpSceneCheckKp), findsOneWidget,
        reason: '★ 收起态绝不卸载场景检定栏');
    expect(find.byKey(GpSceneCheckKeys.root), findsOneWidget);
    expect(find.byKey(GpSceneCheckKeys.modeSkill), findsOneWidget);
    expect(find.byKey(GpSceneCheckKeys.quickPush), findsOneWidget);
    expect(find.byKey(GpSceneCheckKeys.editor), findsOneWidget);

    // ③ 结构性遮挡已移除：收起后 GpKpPlayers 子树不再有不透明 Card 吸收命中。
    expect(
      find.descendant(
        of: find.byKey(GpKpPlayersKeys.root),
        matching: find.byType(Card),
      ),
      findsNothing,
      reason: '★ R4：收起态改用 Align+SizedBox(h:28)，Card 必须消失',
    );
    expect(
      find.descendant(
        of: find.byKey(GpSceneCheckKeys.root),
        matching: find.byType(RoomTap),
      ),
      findsWidgets,
      reason: '场景检定栏按钮仍应可命中',
    );

    // ④ RoomStackNode 叠放 Rect：两格四边逐边相等，收起前后都不变。
    final Rect sceneAfter = tester.getRect(sceneSlot);
    final Rect playersAfter = tester.getRect(playersSlot);
    expect(playersAfter.left, closeTo(sceneAfter.left, 0.6));
    expect(playersAfter.top, closeTo(sceneAfter.top, 0.6));
    expect(playersAfter.right, closeTo(sceneAfter.right, 0.6));
    expect(playersAfter.bottom, closeTo(sceneAfter.bottom, 0.6));
    expect(sceneAfter, sceneBefore, reason: '收起前后场景检定槽 Rect 不变');
    expect(playersAfter, playersBefore, reason: '收起前后玩家信息槽 Rect 不变');

    // ⑤ hitTest：命中路径里必须包含场景检定栏按钮自己的 RenderBox，
    //   而不是收起栏那层透明遮罩（改前 SectionBox 的 Card 会吸收整格 pointer）。
    final Finder btn = find.byKey(GpSceneCheckKeys.quickPush);
    // GpSceneCheckKp 内容包在 SingleChildScrollView 里，右列高度有限；
    // 先滚到按钮，再量 hitTest（否则中心落在裁剪区外会误判为「被遮挡」）。
    await tester.ensureVisible(btn);
    await tester.pump();
    final RenderBox btnBox = tester.renderObject<RenderBox>(btn);
    final RenderBox sceneBox =
        tester.renderObject<RenderBox>(find.byKey(GpSceneCheckKeys.root));
    final RenderBox playersBox =
        tester.renderObject<RenderBox>(find.byKey(GpKpPlayersKeys.root));
    final HitTestResult hit =
        tester.hitTestOnBinding(tester.getCenter(btn));
    expect(hit.path.isNotEmpty, isTrue, reason: '按钮中心必须有命中目标');
    expect(hit.path.length, greaterThanOrEqualTo(2),
        reason: '命中链应是真实可交互控件，而不只是一层背景');
    // 命中路径里至少有一个 target 落在「场景检定栏」子树（或按钮自身子树），
    // 且**不得**是收起后的玩家信息栏 RenderBox（改前 SectionBox 的 Card
    // 会 hitTestSelf==true 吸收整格 pointer）。
    final bool hitSceneSubtree = hit.path.any((HitTestEntry e) {
      final Object? t = e.target;
      if (t is! RenderObject) return false;
      return _within(t, sceneBox) ||
          _within(sceneBox, t) ||
          _within(t, btnBox) ||
          _within(btnBox, t);
    });
    expect(hitSceneSubtree, isTrue,
        reason: '★ 命中目标必须落在场景检定栏子树，不是收起栏的透明遮罩');
    expect(
      hit.path.any((HitTestEntry e) => identical(e.target, playersBox)),
      isFalse,
      reason: '★ 收起后的玩家信息栏 RenderBox 不得吸收该 pointer',
    );

    // ⑥ 回调计数 ≥1：收起态最容易被透明遮罩吞掉的是「点进去打字」。
    //   这里用无条件强断言证明场景检定栏确实收到 pointer 并触发了输入回调。
    final Finder skillField = find.byKey(GpSceneCheckKeys.modeSkill);
    await tester.ensureVisible(skillField);
    await tester.pump();
    // 用坐标级 tapAt（等价于真实用户在屏幕该点按下），避开
    // tester.tap(finder) 对 StatelessWidget 的 finder/renderObject 命中校验
    // 误报；⑤ 已用 hitTestOnBinding 验证该坐标的命中链。
    await tester.tapAt(tester.getCenter(skillField));
    await tester.pump();
    expect(FocusScope.of(tester.element(skillField)).hasFocus, isTrue,
        reason: '★ 收起后场景检定栏输入框必须仍可命中获焦（回调 ≥1）');
    await tester.enterText(skillField, '侦查');
    await tester.pump();
    expect(tester.widget<TextField>(skillField).controller?.text, '侦查',
        reason: '★ 收起后场景检定栏必须仍能接受输入');

    // ⑦ 动作按钮（2.36.0 / Q2 闭环）：坐标级 tapAt 必须让 _push **真触发**。
    //   ★ 原「未结观察项 ⑦」已随 Q2 修复解决：残余根因是 `_slotView` 给
    //     gpPlayers / gpScene 都包了 SingleChildScrollView，`Scrollable` 的
    //     opaque 手势层在 `Positioned.fill` 整格吸收命中。现收起态改走
    //     ClipRect（hitTestSelf==false），非交互区整体穿透。
    //     本条升级为**无条件正向强断言**：出站 scene.check.push 非空。
    //     ⑤ hitTest 链、⑥ 输入框获焦 + enterText 落库的全部核心不变量逐字保留。
    final RoomTap pushTap = tester.widget<RoomTap>(btn);
    expect(pushTap.enabled, isTrue, reason: '「推送检定」按钮应处于可点态');
    expect(pushTap.onTap, isNotNull, reason: '★ 按钮回调必须已接线');
    expect(
      hit.path.any((HitTestEntry e) =>
          e.target.runtimeType.toString() == 'RenderPointerListener'),
      isTrue,
      reason: '★ 按钮中心命中链必须含可接收 pointer 的 listener',
    );
    // 结构性反证：收起态 gpPlayers 槽内不再有整格 opaque Scrollable 手势层。
    expect(
      find.descendant(
        of: find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlayers)),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
      reason: '★ Q2：收起态 gpPlayers 走 ClipRect，不再有整格 opaque 手势层',
    );
    // 命中链必须落到 quickPush 自己的 InkWell 子树；不得含 gpPlayers 槽的
    // Scrollable RenderPointerListener（改前正是它吸收了整格 pointer）。
    final bool hitQuickPushSubtree = hit.path.any((HitTestEntry e) {
      final Object t = e.target;
      return t is RenderObject && _within(t, btnBox);
    });
    expect(hitQuickPushSubtree, isTrue,
        reason: '★ Q2：命中链必须含 quickPush 自身的 InkWell 目标');
    expect(
      hit.path.any((HitTestEntry e) {
        final Object t = e.target;
        return t is RenderObject &&
            t.runtimeType.toString() == 'RenderPointerListener' &&
            _within(t, playersBox);
      }),
      isFalse,
      reason: '★ Q2：命中链不得含 gpPlayers 槽的 Scrollable RenderPointerListener',
    );
    // 坐标级 tapAt（⑥ 已把技能填成「侦查」）：出站计划必须真的出现。
    await tester.ensureVisible(btn);
    await tester.pump();
    f.clearSent();
    await tester.tapAt(tester.getCenter(btn));
    await tester.pump();
    expect(f.lastSent(action: 'scene.check.push'), isNotNull,
        reason: '★ Q2 闭环：收起态坐标级 tapAt 必须让 quickPush 的 onTap 真触发');
    expect(tester.takeException(), isNull, reason: '收起后不该有布局/命中异常');
  });

  testWidgets('收起后展开回来，场景检定栏与卡片都还在（状态机可逆）',
      (WidgetTester tester) async {
    final RoomUiFixture f = RoomUiFixture();
    await f.boot(inGame: true);
    f.pageBuilder = (String s, String r) => const RoomGamePage();
    useRoomScreen(tester, 1280, 800);
    await tester.pumpWidget(f.pageOf(kHostSeat));
    await tester.pump();

    await tester.tap(find.byKey(GpKpPlayersKeys.collapseToggle));
    await tester.pump();
    expect(f.localOf(kHostSeat).playersPanelCollapsed, isTrue);
    expect(find.byType(GpSceneCheckKp), findsOneWidget);

    await tester.tap(find.byKey(GpKpPlayersKeys.collapseToggle));
    await tester.pump();
    expect(f.localOf(kHostSeat).playersPanelCollapsed, isFalse);
    expect(find.byType(GpSceneCheckKp), findsOneWidget);
    expect(find.byKey(GpSceneCheckKeys.root), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
