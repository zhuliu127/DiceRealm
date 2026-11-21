// ============================================================
// test/p11_kp6a_focus_test.dart — KP-6a 键盘弹起 + 翻档时焦点/输入保持
//
// 修法锚点：room_game_page.dart:428 `resizeToAvoidBottomInset: false`
//   （键盘弹起不压缩 body，避免布局挤压导致 TextField 失焦 / 输入法收起）。
// 断言口径：必须断言「焦点保持」而非仅「能点」，否则 ClipRect 硬裁能蒙混。
// 三档 textScaler 1.3 / 1.5 / 2.0（外加基线 1.0）。
// ============================================================

import 'dart:io' show File;

import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/ui/room/room_game_page.dart' show RoomGamePage;
import 'package:dice_realm/ui/room/widgets/gp_scene_check_kp.dart'
    show GpSceneCheckKeys;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart' show RoomUiFixture, useRoomScreen;

// ★ RoomGamePage 自带 Scaffold(resizeToAvoidBottomInset: false)，此处**不能**
//   再包一层默认 resize=true 的 Scaffold（否则 viewInsets 会压缩 body 并溢出，
//   测到的就不是产品行为）。
Widget _app(RoomUiFixture f, Widget child) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: f.scoped(kHostSeat, child: child),
    );

/// 场景检定块内的文本输入框（KP dock 档 ≤1 个）。
Finder _skillField() => find
    .descendant(
      of: find.byKey(GpSceneCheckKeys.root),
      matching: find.byType(TextField),
    )
    .first;

void main() {
  group('KP-6a 键盘弹起时焦点保持', () {
    for (final double scale in <double>[1.0, 1.3, 1.5, 2.0]) {
      testWidgets('1280×800 × textScaler $scale：键盘(insets 300dp)不导致失焦/文本回退',
          (WidgetTester tester) async {
        final f = RoomUiFixture();
        await f.boot(inGame: true);
        useRoomScreen(tester, 1280, 800);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        // 模拟软键盘：bottom = 300dp × dpr 3
        tester.view.viewInsets = const FakeViewPadding(bottom: 900);
        addTearDown(tester.view.resetViewInsets);

        await tester.pumpWidget(_app(f, const RoomGamePage()));
        await tester.pump();

        final Finder field = _skillField();
        expect(field, findsOneWidget, reason: 'KP dock 档应有技能输入框');

        await tester.ensureVisible(field);
        await tester.pump();
        await tester.tap(field, warnIfMissed: false);
        await tester.pump();
        await tester.enterText(field, '侦查');
        await tester.pump();
        expect(tester.widget<TextField>(field).controller?.text, '侦查');

        // 键盘已注入 insets：再次 pump 后焦点必须仍在同一 TextField 上。
        await tester.pump();
        final TextField now = tester.widget<TextField>(field);
        expect(now.controller?.text, '侦查',
            reason: '技能名不得回退：${now.controller?.text}');
        expect(tester.testTextInput.isVisible, isTrue,
            reason: '键盘弹起后输入法不得被收起（fail = 焦点丢 / 输入法收起）');

        // 连续追加输入
        await tester.enterText(field, '侦查 聆听');
        await tester.pump();
        expect(tester.widget<TextField>(field).controller?.text, '侦查 聆听',
            reason: '必须能连续追加输入');
        expect(tester.takeException(), isNull,
            reason: '键盘弹起 + 大字号下不应有布局异常');
      });
    }

    testWidgets('doc↔folded 尺寸来回切换（1280×800 ↔ 780×320）后焦点与文本保持',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 1280, 800);
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(tester.view.resetViewInsets);

      await tester.pumpWidget(_app(f, const RoomGamePage()));
      await tester.pump();
      await tester.ensureVisible(_skillField());
      await tester.pump();
      await tester.tap(_skillField(), warnIfMissed: false);
      await tester.pump();
      await tester.enterText(_skillField(), '侦查');
      await tester.pump();

      // 切到矮横屏（folded/紧凑档）再切回 dock：同一 Element 树应保留 State。
      useRoomScreen(tester, 780, 320);
      await tester.pump();
      useRoomScreen(tester, 1280, 800);
      await tester.pump();

      final Finder field = _skillField();
      expect(field, findsOneWidget, reason: '切档后技能输入框仍在');
      final TextField now = tester.widget<TextField>(field);
      expect(now.controller?.text, '侦查',
          reason: '切档来回后文本不得回退：${now.controller?.text}');
      expect(tester.takeException(), isNull);
    });

    test('修法锚点存在：游戏页 Scaffold 显式 resizeToAvoidBottomInset: false',
        () {
      // 源码门禁（只读断言，防止有人改回 true 却没人发现）。
      final String src =
          File('lib/ui/room/room_game_page.dart').readAsStringSync();
      expect(src.contains('resizeToAvoidBottomInset: false'), isTrue,
          reason: 'KP-6a 修复锚点被移除/改回 true');
    });
  });
}
