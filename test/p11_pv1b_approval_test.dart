// ============================================================
// test/p11_pv1b_approval_test.dart — PV-1b 玩家主动对抗
//
// ① 玩家侧独立入口 RoomGamePage.playerOpposedKey 存在且可点；
// ② R1 门控：p1 / sp1 视角下骰子条 KP 裁定入口 `act/check.opposed` 仍 findsNothing；
// ③ 审批通过后 domain `auto:true` 分支（checkOpposed:1775-1777 → _autoOpposedCheck:1708-1768）
//    产出**一条** kind:'check' PUBLIC 记录，技能值取自角色卡 skillBaseOf；
// ④ `auto` 必须是 bool true —— 字符串 'true' 不触发。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/ui/room/room_game_page.dart' show RoomGamePage;
import 'package:dice_realm/ui/room/room_keys.dart' show RoomKeys;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart' show RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart' show RoomUiFixture, useRoomScreen;

Widget _app(RoomUiFixture f, String seat, Widget child) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(body: f.scoped(seat, child: child)),
    );

/// 当前 kind=='check' 记录条数。
int _checkCount(RoomUiFixture f) {
  final logs = asList(f.stateOf(kHostSeat)['logs']);
  return logs.where((e) => jsStr(asMap(e)['kind']) == 'check').length;
}

/// 最近一条含「玩家主动对抗」的 log 文本。
String _lastAutoText(RoomUiFixture f) {
  final logs = asList(f.stateOf(kHostSeat)['logs']);
  for (var i = logs.length - 1; i >= 0; i--) {
    final t = jsStr(asMap(logs[i])['text']);
    if (t.contains('玩家主动对抗')) return t;
  }
  return '';
}

void main() {
  group('PV-1b widget：入口与 R1 门控', () {
    testWidgets('玩家视角有独立「主动对抗」入口且可点', (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(_app(f, 'p1', const RoomGamePage()));
      await tester.pump();
      final Finder entry = find.byKey(RoomGamePage.playerOpposedKey);
      expect(entry, findsOneWidget, reason: '玩家应有独立主动对抗入口');
      expect(tester.widget<RoomTap>(entry).enabled, isTrue, reason: '应可点');
      expect(tester.takeException(), isNull);
    });

    testWidgets('R1 门控：p1 / sp1 视角骰子条 KP 对抗按钮均 findsNothing',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 1280, 800);
      for (final String seat in <String>['p1', 'sp1']) {
        await tester.pumpWidget(_app(f, seat, const RoomGamePage()));
        await tester.pump();
        expect(find.byKey(RoomKeys.action('check.opposed')), findsNothing,
            reason: '$seat 视角不得渲染骰子条 KP 裁定入口（R1 && isKp 门控）');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('KP 视角：骰子条 KP 对抗入口仍渲染（isKp 门控的另一侧）',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(_app(f, kHostSeat, const RoomGamePage()));
      await tester.pump();
      expect(find.byKey(RoomKeys.action('check.opposed')), findsOneWidget,
          reason: 'KP 侧骰子条对抗按钮必须保留');
      expect(find.byKey(RoomGamePage.playerOpposedKey), findsNothing,
          reason: 'KP 不该有玩家主动对抗入口（if (!isKp)）');
      expect(tester.takeException(), isNull);
    });
  });

  group('PV-1b domain：auto:true 自动检定', () {
    test('auto:true → 恰好一条 kind:check PUBLIC 记录，含技能值与掷值', () async {
      final f = RoomUiFixture();
      await f.boot();
      final int before = _checkCount(f);
      await f.kpSession.hostAction('check.opposed', <String, Object?>{
        'auto': true,
        'skill': '侦查',
        'targetSeat': '*',
        'by': 'p1',
      });
      expect(_checkCount(f) - before, 1, reason: '只产出一条结果记录');
      final t = _lastAutoText(f);
      expect(t, isNotEmpty, reason: '应产出「玩家主动对抗」记录');
      expect(t.contains('侦查'), isTrue, reason: '含技能名：$t');
      expect(t.contains('技能值'), isTrue, reason: '含技能值：$t');
      expect(t.contains('掷'), isTrue, reason: '含掷值：$t');
      expect(t.contains('全体'), isTrue, reason: 'targetSeat=* → 全体：$t');
    });

    test('auto 是字符串 "true" → 不触发自动分支（严格 == bool）', () async {
      final f = RoomUiFixture();
      await f.boot();
      final int before = _checkCount(f);
      await f.kpSession.hostAction('check.opposed', <String, Object?>{
        'auto': 'true',
        'skill': '侦查',
        'targetSeat': '*',
        'by': 'p1',
      });
      expect(_lastAutoText(f), isEmpty,
          reason: '字符串 auto 不得触发 _autoOpposedCheck');
      expect(_checkCount(f), before, reason: '不得产出自动检定记录');
    });

    test('auto:true 时技能值由权威端算出，不采信客户端 base', () async {
      final f = RoomUiFixture();
      await f.boot();
      await f.kpSession.hostAction('check.opposed', <String, Object?>{
        'auto': true,
        'skill': '侦查',
        'targetSeat': '*',
        'by': 'p1',
        'base': 1, // 客户端乱传，权威端必须忽略
      });
      final t = _lastAutoText(f);
      expect(t, isNotEmpty);
      expect(t.contains('技能值'), isTrue, reason: '必须播报权威端算出的技能值：$t');
      expect(t.contains('技能值 1，'), isFalse,
          reason: '★ 不得采信客户端回传的 base=1：$t');
    });

    test('auto:true + targetSeat=p1 → 目标名取该玩家昵称', () async {
      final f = RoomUiFixture();
      await f.boot();
      await f.kpSession.hostAction('check.opposed', <String, Object?>{
        'auto': true,
        'skill': '侦查',
        'targetSeat': 'p1',
        'by': 'p2',
      });
      final t = _lastAutoText(f);
      expect(t, isNotEmpty);
      expect(t.contains('全体'), isFalse, reason: '定向目标不该显示全体：$t');
      expect(t.contains('玩家1'), isTrue, reason: '应显示目标昵称：$t');
    });
  });
}
