// ============================================================
// test/p12_game_e2e_test.dart — 带卡开团后的 UI / 按钮 / 二级菜单巡检
//
// 用户要求（2026-11-11）：「用随机生成人物卡进跑团房间开始游戏再继续测试
// 一下，看看 UI 布局、各个功能按钮、二级菜单有没有异常」。
//
// 双模拟器上已跑通「建房 → 第二台加入 → 两端同步」（见 _p12_ui_polish_report.md
// 与 _p12_final_a_joined.png / _p12_final_b_joined.png），但继续压测时模拟器
// 反复 OOM 退出，游戏期这一段改用可重复的集成测试补齐：
//
//   · boot(inGame: true) 用**真实 action** 开团（room.start + scene.mode），
//     withSheets 默认为 true → 两个玩家各带一张完整卡（等价于随机卡进房）；
//   · 4 档屏幕 × KP / 玩家 两视角 = 8 组，逐组查布局异常（RenderFlex
//     overflow 会以 FlutterError 冒到 takeException）；
//   · 所有 RoomTap 都必须有 RoomButtonSkin 底色；
//   · 逐个点按钮，查「点了会不会崩」；
//   · 打开二级菜单（面板 tab / 弹层），查渲染是否完整。
// ============================================================

import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/ui/room/room_game_page.dart' show RoomGamePage;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart'
    show RoomButtonSkin, RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

Widget _app(RoomUiFixture f, String seat) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: f.scoped(seat, child: const RoomGamePage()),
    );

/// 四档屏幕：窄手机 / 横屏小窗 / 竖屏平板 / 横屏平板。
/// 覆盖 `lib/ui/responsive.dart` 的 compact / medium / expanded 三档。
const List<(String, double, double)> kScreens = <(String, double, double)>[
  ('手机竖 360×640', 360, 640),
  ('横屏小窗 780×320', 780, 320),
  ('平板竖 820×1180', 820, 1180),
  ('平板横 1280×800', 1280, 800),
];

Future<RoomUiFixture> _bootGame(
  WidgetTester tester, {
  required String seat,
  required double w,
  required double h,
}) async {
  final f = RoomUiFixture();
  await f.boot(inGame: true); // 真实 action 开团 + 玩家带卡
  useRoomScreen(tester, w, h);
  await tester.pumpWidget(_app(f, seat));
  await tester.pump();
  return f;
}

void main() {
  // ----------------------------------------------------------
  // A · 布局：8 组（4 档屏幕 × KP / 玩家）零异常
  // ----------------------------------------------------------
  for (final (String name, double w, double h) in kScreens) {
    for (final String seat in <String>[kHostSeat, 'p1']) {
      final String who = seat == kHostSeat ? 'KP' : '玩家';
      testWidgets('A · $name / $who：开团后整页无溢出、无异常',
          (WidgetTester tester) async {
        await _bootGame(tester, seat: seat, w: w, h: h);

        expect(tester.takeException(), isNull,
            reason: '$name / $who 渲染时抛异常（布局溢出会在这里冒出来）');
        expect(find.byType(RoomGamePage), findsOneWidget);
        expect(find.byType(RoomTap), findsWidgets,
            reason: '$name / $who 一个功能按钮都没渲染出来');
      });
    }
  }

  // ----------------------------------------------------------
  // B · 功能按钮：每个可点件都有底色，且点了不崩
  // ----------------------------------------------------------
  testWidgets('B · 游戏页每个 RoomTap 都带按钮底色', (WidgetTester tester) async {
    await _bootGame(tester, seat: kHostSeat, w: 360, h: 900);

    final int taps = find.byType(RoomTap).evaluate().length;
    final int skins = find.byType(RoomButtonSkin).evaluate().length;
    expect(taps, greaterThan(5), reason: '游戏页可点件太少，八成没渲染完整');
    expect(skins, greaterThanOrEqualTo(taps),
        reason: '有 $taps 个按钮却只有 $skins 个按钮皮肤 —— 有文字按钮漏补底色');
    expect(tester.takeException(), isNull);
  });

  testWidgets('B · 逐个点击工具栏按钮，无一个抛异常',
      (WidgetTester tester) async {
    await _bootGame(tester, seat: kHostSeat, w: 360, h: 900);

    // 先快照 widget 列表：点击可能改变状态、让后续 finder 失效。
    final List<RoomTap> buttons = find
        .byType(RoomTap)
        .evaluate()
        .map((Element e) => e.widget as RoomTap)
        .toList();
    expect(buttons.length, greaterThan(5));

    var clicked = 0;
    for (final RoomTap b in buttons) {
      final Finder f = find.byWidget(b);
      if (f.evaluate().isEmpty) continue; // 被前一次点击带走了，跳过
      await tester.scrollUntilVisible(f, 60,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(f, warnIfMissed: false);
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: '点「${b.label.isEmpty ? b.hint ?? '图标按钮' : b.label}」抛异常');
      clicked += 1;
    }
    expect(clicked, greaterThan(3), reason: '没点到几个按钮，用例没意义');
  });

  // ----------------------------------------------------------
  // C · 二级菜单：面板 tab 切换 + 弹层能开、内容不空
  // ----------------------------------------------------------
  testWidgets('C · 面板 tab 可切换，切换后无异常', (WidgetTester tester) async {
    await _bootGame(tester, seat: kHostSeat, w: 360, h: 900);

    final Finder chips = find.byType(ActionChip);
    expect(chips, findsWidgets, reason: '游戏页面板 tab 没渲染');
    final List<ActionChip> snapshot = chips
        .evaluate()
        .map((Element e) => e.widget as ActionChip)
        .toList();

    for (final ActionChip chip in snapshot.take(4)) {
      final Finder f = find.byWidget(chip);
      if (f.evaluate().isEmpty) continue;
      await tester.tap(f, warnIfMissed: false);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '切 tab 抛异常');
    }
  });

  testWidgets('C · 二级菜单：逐个点开弹层，内容渲染且可关闭',
      (WidgetTester tester) async {
    await _bootGame(tester, seat: kHostSeat, w: 360, h: 900);

    // 不能用「找 hint 含详情的按钮」——找不到就跳过会变成假绿。
    // 改成遍历全部按钮，凡是弹出 BottomSheet / Dialog 的都算一个二级菜单。
    final List<RoomTap> buttons = find
        .byType(RoomTap)
        .evaluate()
        .map((Element e) => e.widget as RoomTap)
        .toList();

    var opened = 0;
    for (final RoomTap b in buttons) {
      final Finder f = find.byWidget(b);
      if (f.evaluate().isEmpty) continue;
      await tester.tap(f, warnIfMissed: false);
      await tester.pumpAndSettle();

      final bool hasSheet = find.byType(BottomSheet).evaluate().isNotEmpty;
      final bool hasDialog = find.byType(Dialog).evaluate().isNotEmpty;
      if (hasSheet || hasDialog) {
        opened += 1;
        expect(tester.takeException(), isNull,
            reason: '打开「${b.label.isEmpty ? b.hint ?? '图标' : b.label}」'
                '的二级菜单后渲染抛异常');
        // 关掉，避免遮住后面的按钮。弹层里没有 BackButton，
        // 所以不能用 tester.pageBack()（它会去找返回按钮并直接失败）。
        final Finder overlay = hasSheet
            ? find.byType(BottomSheet).first
            : find.byType(Dialog).first;
        Navigator.of(tester.element(overlay)).pop();
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull, reason: '点按钮后抛异常');
    }
    expect(opened, greaterThan(0),
        reason: '一个二级菜单都没点开 —— 说明用例没覆盖到，不能算通过');
  });

  // ----------------------------------------------------------
  // D · 带卡的玩家：数值照实显示，不再出现假 0 / 未绑卡
  // ----------------------------------------------------------
  testWidgets('D · 玩家带了卡：状态区显示真实数值', (WidgetTester tester) async {
    await _bootGame(tester, seat: 'p1', w: 360, h: 900);
    expect(tester.takeException(), isNull);
    expect(find.text('未绑卡'), findsNothing,
        reason: '已经带卡进房，不该还显示未绑卡');
    expect(find.text('还没有绑定角色卡'), findsNothing);
  });
}
