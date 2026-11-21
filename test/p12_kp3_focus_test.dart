// ============================================================
// test/p12_kp3_focus_test.dart — P12 / 第 9 期 · KP-3
//
// 点输入框以外任意位置 → 聊天输入框失焦、输入法收起，连续 tap 不复焦。
// 两处输入框各测：
//   ① sheets/sheet_chat_composer.dart 的全屏编辑器 ChatComposerPage
//      （TextField.onTapOutside + Scaffold body 的 GestureDetector 兜底）；
//   ② widgets/gp_feeds.dart 的 ChatInputRow（TextField.onTapOutside）。
//
// ★ 多位置 tap 参数化 × 连续 tap × textScaler 1.3 / 1.5 / 2.0。
// ★ 不回退 P11 KP-6a 的 `resizeToAvoidBottomInset: false` 抗抖动口径
//   （本文件用源码门禁钉住游戏页；全屏编辑器自己的 :168 true 也不动）。
// ============================================================

import 'dart:io' show File;

import 'package:dice_realm/ui/room/room_keys.dart' show RoomKeys;
import 'package:dice_realm/ui/room/sheets/sheet_chat_composer.dart'
    show ChatComposerKeys, ChatComposerPage;
import 'package:dice_realm/ui/room/widgets/gp_feeds.dart' show ChatInputRow;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart' show RoomUiFixture, useRoomScreen;

/// 全屏编辑器（独立 Scaffold，自带 autofocus + GestureDetector 兜底）。
Widget _composerApp() => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: ChatComposerPage(
        initialText: '草稿',
        onChanged: (String _) {},
        onSend: (String _) {},
      ),
    );

/// 主页聊天输入行：上下各放一块明确可命中的「外部点击区」。
Widget _inputRowApp(RoomUiFixture f) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: f.scoped(
          'p1',
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('外部点击区A'),
              ChatInputRow(),
              Text('外部点击区B'),
            ],
          ),
        ),
      ),
    );

/// 焦点是否还落在输入框所在的 FocusScope 内。
bool _hasFocus(WidgetTester tester, Finder field) =>
    FocusScope.of(tester.element(field)).hasFocus;

/// viewInsets.bottom（widget test 无真实 IME，由测试夹具提供，默认 0）。
double _bottomInset(WidgetTester tester, Finder field) =>
    MediaQuery.of(tester.element(field)).viewInsets.bottom;

void main() {
  group('A · ChatComposerPage（sheet_chat_composer.dart）', () {
    for (final double scale in <double>[1.0, 1.3, 1.5, 2.0]) {
      testWidgets('×$scale 多位置 tap → hasFocus=false / viewInsets.bottom=0 / 不复焦',
          (WidgetTester tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        useRoomScreen(tester, 1280, 800);
        await tester.pumpWidget(_composerApp());
        await tester.pump();

        final Finder field = find.byKey(ChatComposerKeys.field);
        expect(field, findsOneWidget, reason: '全屏编辑器应有输入框');
        expect(_hasFocus(tester, field), isTrue,
            reason: 'autofocus 应让输入框初始获焦');
        expect(_bottomInset(tester, field), 0,
            reason: '未弹真实 IME 时 viewInsets.bottom 必须为 0');

        // 两个明确位于输入框之外的可命中位置（AppBar 上）。
        final List<Offset> outside = <Offset>[
          tester.getCenter(find.byType(AppBar)),
          tester.getCenter(find.text('编辑发言')),
        ];
        for (final Offset p in outside) {
          // 每轮先重新聚焦，再点外部，独立验证「点一下就失焦」。
          await tester.showKeyboard(field);
          await tester.pump();
          expect(_hasFocus(tester, field), isTrue,
              reason: '重新聚焦失败，位置 $p');
          await tester.tapAt(p);
          await tester.pump();
          expect(_hasFocus(tester, field), isFalse,
              reason: '×$scale 点位置 $p 后必须失焦');
          expect(tester.testTextInput.isVisible, isFalse,
              reason: '×$scale 输入法必须收起');
          expect(_bottomInset(tester, field), 0,
              reason: '×$scale viewInsets.bottom 必须为 0');
        }

        // 连续多次 tap 外部，不得复焦。
        await tester.showKeyboard(field);
        await tester.pump();
        for (int i = 0; i < 3; i++) {
          await tester.tapAt(outside.first);
          await tester.pump();
          expect(_hasFocus(tester, field), isFalse,
              reason: '第 ${i + 1} 次连续 tap 后不该复焦');
        }
        expect(tester.takeException(), isNull,
            reason: '×$scale 大字号下不该有布局异常');
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
    }
  });

  group('B · ChatInputRow（gp_feeds.dart，主页聊天下方输入行）', () {
    for (final double scale in <double>[1.0, 1.3, 1.5, 2.0]) {
      testWidgets('×$scale 两处外部点击区都让输入行失焦、连续 tap 不复焦',
          (WidgetTester tester) async {
        final RoomUiFixture f = RoomUiFixture();
        await f.boot(inGame: true);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        useRoomScreen(tester, 1280, 800);
        await tester.pumpWidget(_inputRowApp(f));
        await tester.pump();

        final Finder field = find.byKey(RoomKeys.gpChatInput);
        expect(field, findsOneWidget, reason: '主页输入行应存在');
        // showKeyboard 只请求焦点，不触发 TextField.onTap（否则会弹全屏编辑器）。
        await tester.showKeyboard(field);
        await tester.pump();
        expect(_hasFocus(tester, field), isTrue, reason: '输入行应能获焦');

        for (final String label in <String>['外部点击区A', '外部点击区B']) {
          await tester.showKeyboard(field);
          await tester.pump();
          expect(_hasFocus(tester, field), isTrue);
          await tester.tap(find.text(label));
          await tester.pump();
          expect(_hasFocus(tester, field), isFalse,
              reason: '×$scale 点「$label」后必须失焦');
          expect(tester.testTextInput.isVisible, isFalse,
              reason: '×$scale 输入法必须收起');
          expect(_bottomInset(tester, field), 0);
        }

        // 连续 tap 不复焦，且输入行本身仍在树中（不卸载、不改高度）。
        await tester.showKeyboard(field);
        await tester.pump();
        for (int i = 0; i < 3; i++) {
          await tester.tap(find.text('外部点击区A'));
          await tester.pump();
          expect(_hasFocus(tester, field), isFalse);
        }
        expect(find.byKey(RoomKeys.gpChatInput), findsOneWidget);
        expect(tester.takeException(), isNull);
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
    }
  });

  group('C · 源码门禁：不回退 KP-6a / 不删本期失焦修法', () {
    test('两处 onTapOutside 与全屏编辑器 GestureDetector 兜底都在', () {
      final String composer =
          File('lib/ui/room/sheets/sheet_chat_composer.dart').readAsStringSync();
      final String feeds =
          File('lib/ui/room/widgets/gp_feeds.dart').readAsStringSync();
      expect(composer.contains('onTapOutside:'), isTrue,
          reason: '全屏编辑器必须保留 onTapOutside');
      expect(composer.contains('GestureDetector('), isTrue,
          reason: 'body 外层 GestureDetector 兜底不能删');
      expect(composer.contains('resizeToAvoidBottomInset: true'), isTrue,
          reason: '全屏编辑器自身的 :168 true 不得改动');
      expect(feeds.contains('onTapOutside:'), isTrue,
          reason: '主页输入行必须补 onTapOutside');
      expect(
        File('lib/ui/room/room_game_page.dart')
            .readAsStringSync()
            .contains('resizeToAvoidBottomInset: false'),
        isTrue,
        reason: 'P11 KP-6a 抗抖动口径不得回退',
      );
    });
  });
}
