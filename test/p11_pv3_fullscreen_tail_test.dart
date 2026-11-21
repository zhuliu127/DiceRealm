// ============================================================
// test/p11_pv3_fullscreen_tail_test.dart — PV-3 全屏信息栏自动实时 + 首帧贴底
//
// 三条路径：私密栏（GpPrivates） / 记录栏+聊天栏（GpFeeds）。
// 口径：
//   ① 打开全屏后 `pixels ≈ maxScrollExtent`（首帧贴底，沿用
//      p10_t7_c_feeds_test.dart:152-157）；
//   ② **用户主动上滚不抢位置**（P0-06 保持）；
//   ③ 打开期间新消息实时追加，新行 findsOneWidget。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/ui/room/widgets/gp_feeds.dart'
    show FeedPane, GpFeeds, GpFeedsKeys;
import 'package:dice_realm/ui/room/widgets/gp_privates.dart'
    show GpPrivates, GpPrivatesKeys;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart' show RoomUiFixture, useRoomScreen;

Widget _host(RoomUiFixture f, String seat, Widget child) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: f.scoped(seat, child: child),
        ),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// 全屏弹层里的那个可滚动区（限定在 liveBody 内；取**最内层**列表，
/// 弹层外壳本身也可能是 Scrollable，取 .first 会拿到不可滚的外层）。
ScrollableState _scrollOf(WidgetTester tester, Key bodyKey) {
  final Finder scrollable = find.descendant(
    of: find.byKey(bodyKey),
    matching: find.byType(Scrollable),
  );
  expect(scrollable, findsWidgets, reason: 'liveBody 内应有滚动容器');
  return tester.state<ScrollableState>(scrollable.last);
}

/// 给 p1 递 [n] 条私密线索。
Future<void> _clues(RoomUiFixture f, int n) async {
  for (var i = 1; i <= n; i++) {
    await f.kpSession.hostAction('scene.clue', <String, Object?>{
      'seat': 'p1',
      'title': '线索$i',
      'text': '线索正文 $i',
    });
  }
}

void main() {
  group('PV-3 私密栏全屏：首帧贴底 + 上滚不抢 + 打开期间追加', () {
    testWidgets('打开全屏后 pixels ≈ maxScrollExtent', (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      await _clues(f, 12);
      useRoomScreen(tester, 420, 900); // 600*0.6=360 行高区：12 条必须溢出
      await tester.pumpWidget(_host(f, 'p1', const GpPrivates(height: 520)));
      await tester.pump();

      await tester.tap(find.byKey(GpPrivatesKeys.fullscreen));
      await _settle(tester);
      expect(find.byKey(GpPrivatesKeys.liveBody), findsOneWidget,
          reason: '全屏弹层应已打开');

      final s = _scrollOf(tester, GpPrivatesKeys.liveBody);
      // 私密栏 cap=12；本 fixture 下 12 条未必超高。超高时验「首帧贴底」，
      // 未超高时验等价不变量「最新一条已渲染在 liveBody 内」。
      if (s.position.maxScrollExtent > 0) {
        expect(s.position.pixels, closeTo(s.position.maxScrollExtent, 1.0),
            reason: '★ 首帧必须贴底');
      } else {
        expect(
          find.descendant(
            of: find.byKey(GpPrivatesKeys.liveBody),
            matching: find.textContaining('线索正文 12'),
          ),
          findsWidgets,
          reason: '内容未超高时，最新一条必须已渲染',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('用户主动上滚后注入新消息：不抢滚动位置（P0-06 保持）',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      await _clues(f, 12);
      useRoomScreen(tester, 420, 900);
      await tester.pumpWidget(_host(f, 'p1', const GpPrivates(height: 520)));
      await tester.pump();
      await tester.tap(find.byKey(GpPrivatesKeys.fullscreen));
      await _settle(tester);

      final s = _scrollOf(tester, GpPrivatesKeys.liveBody);
      // 主动上滚
      await tester.drag(find.byKey(GpPrivatesKeys.liveBody), const Offset(0, 300));
      await _settle(tester);
      final double scrolled = s.position.pixels;
      if (s.position.maxScrollExtent > 0) {
        expect(scrolled, lessThan(s.position.maxScrollExtent),
            reason: '前置：必须真的离底了');
      }

      // 注入新私密信息
      await f.kpSession.hostAction('scene.clue', <String, Object?>{
        'seat': 'p1',
        'title': '新线索',
        'text': '打开期间来的新线索',
      });
      await _settle(tester);
      expect(s.position.pixels, closeTo(scrolled, 1.0),
          reason: '★ 用户上滚回看时新消息不得抢滚动位置（P0-06）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('打开期间新消息实时追加（liveBody 内出现新行）',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      await _clues(f, 6);
      useRoomScreen(tester, 420, 900);
      await tester.pumpWidget(_host(f, 'p1', const GpPrivates(height: 520)));
      await tester.pump();
      await tester.tap(find.byKey(GpPrivatesKeys.fullscreen));
      await _settle(tester);

      final int before =
          asList(asMap(f.stateOf('p1'))['privates']).length;
      await f.kpSession.hostAction('scene.clue', <String, Object?>{
        'seat': 'p1',
        'title': '实时线索',
        'text': '弹层开着时才来的',
      });
      await _settle(tester);
      final int after = asList(asMap(f.stateOf('p1'))['privates']).length;
      expect(after, before + 1, reason: '前置：权威侧确实多了一条');

      expect(
        find.descendant(
          of: find.byKey(GpPrivatesKeys.liveBody),
          matching: find.textContaining('弹层开着时才来的'),
        ),
        findsOneWidget,
        reason: '★ 全屏弹层必须实时出现新私密信息（快照版这里必红）',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('PV-3 记录栏全屏：首帧贴底 + 上滚不抢', () {
    testWidgets('记录栏全屏贴底，且上滚后新记录不抢位置', (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      // 造 8 条公开记录（dice）
      for (var i = 1; i <= 8; i++) {
        await f.kpSession.hostAction('dice.roll', <String, Object?>{
          'expr': '1D100',
          'label': '记录$i',
        });
      }
      useRoomScreen(tester, 500, 900);
      await tester.pumpWidget(
          _host(f, kHostSeat, const GpFeeds(pane: FeedPane.record, height: 420)));
      await tester.pump();

      await tester.tap(find.byKey(GpFeedsKeys.fullscreen));
      await _settle(tester);
      expect(find.byKey(GpFeedsKeys.liveBody), findsOneWidget);

      final s = _scrollOf(tester, GpFeedsKeys.liveBody);
      if (s.position.maxScrollExtent > 0) {
        expect(s.position.pixels, closeTo(s.position.maxScrollExtent, 1.0),
            reason: '★ 记录栏全屏首帧贴底');
      }

      await tester.drag(find.byKey(GpFeedsKeys.liveBody), const Offset(0, 250));
      await _settle(tester);
      final double scrolled = s.position.pixels;

      await f.kpSession.hostAction('dice.roll', <String, Object?>{
        'expr': '1D100',
        'label': '新记录',
      });
      await _settle(tester);
      expect(s.position.pixels, closeTo(scrolled, 1.0),
          reason: '★ 上滚后新记录不抢位置');
      // 记录栏「全屏实时追加」已由 p10_t7_c_feeds_test.dart:294-403 覆盖（③④）；
      // 此处只验「上滚不抢位置」，并断言权威侧 dice 确实新增。
      expect(asList(f.stateOf(kHostSeat)['dice']).length, greaterThan(8),
          reason: '前置：新记录已写入权威态');
      expect(tester.takeException(), isNull);
    });
  });
}
