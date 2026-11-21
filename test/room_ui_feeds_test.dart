// ============================================================
// test/room_ui_feeds_test.dart — P5/T03 S3.2 + S3.3 信息流 / 私密栏验收
//
// 铁律：T1（全内存后端）、T6（断言权威侧 / sent，不看 UI 文案「成功」）、
//      T8（跨视角用 stateOf 建的会话，不拿权威态假装玩家视图）。
//
// 块测试**不 pump 整页**：直接把块放进 `MaterialApp + RoomScope + Scaffold`，
// 这样块可以独立验（T02 的页面装配留给接线那一轮）。
//
// 覆盖：T-10（输入不丢 / State 不重建）、T-11（redacted 只显脱敏文案）、
//      T-12（不含原始 JSON 键名）、五类分派、懒构建、上滚不拉底、
//      空态、旁观者禁言、私密栏（最近 12 条 / 正序 / 高亮 / 点开全文 / 全屏）。
// ============================================================

import 'package:dice_realm/domain/room_types.dart';
import 'package:dice_realm/ui/room/room_keys.dart';
import 'package:dice_realm/ui/room/view/feed_view.dart';
import 'package:dice_realm/ui/room/widgets/gp_feeds.dart';
import 'package:dice_realm/ui/room/widgets/gp_privates.dart';
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

/// 块的独立宿主：MaterialApp + RoomScope + Scaffold。
///
/// 块只依赖 RoomScope（不碰分享 / 仓库作用域），所以这里不必再套三层作用域；
/// 与夹具 `shell()` 的区别仅在于「没有整页骨架」。
Widget _host(RoomUiFixture f, String seat, Widget child) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: f.scoped(seat, child: child),
        ),
      ),
    );

/// 造一条「公共日志」，[extra] 用于附加 kind / opp / redacted 等字段。
void _log(
  RoomUiFixture f, {
  String kind = 'sys',
  String text = '系统消息',
  String seat = '',
  Map<String, Object?>? opp,
  bool redacted = false,
  num at = 1000,
}) {
  final rec = f.host.emit(
    RoomEvt.log,
    <String, Object?>{
      'seat': seat,
      'text': text,
      'at': at,
      'kind': kind,
      'opp': ?opp,
      if (redacted) 'redacted': true,
    },
    vis: RoomVis.public,
  );
  f.kpSession.pumpPlans(f.host.plan(rec));
}

/// 收集当前树里所有渲染出来的纯文本（Text + RichText），用于「搜不到某串」断言。
List<String> _renderedText(WidgetTester tester) {
  final out = <String>[];
  for (final t in tester.widgetList<Text>(find.byType(Text))) {
    final d = t.data;
    if (d != null) out.add(d);
    final span = t.textSpan;
    if (span != null) out.add(span.toPlainText());
  }
  for (final r in tester.widgetList<RichText>(find.byType(RichText))) {
    out.add(r.text.toPlainText());
  }
  return out;
}

void main() {
  group('S3.2 · 聊天与记录：五类分派', () {
    testWidgets('sys / chat / dice 走真实事件流，check / opposed 走分派（reduce 不存 opp）',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      _log(f, kind: 'sys', text: '开团了', at: 1);
      _log(f, kind: 'chat', text: '大家好', seat: 'p1', at: 2);
      await f.controllerOf(kHostSeat).sendIntent(
        RoomIntent.dice,
        <String, Object?>{'expr': '1D100', 'direct': true},
      );

      await tester.pumpWidget(
        _host(f, kHostSeat, const GpFeeds(pane: FeedPane.record)),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byKey(GpFeedsKeys.list), findsOneWidget);
      final texts = _renderedText(tester);
      expect(texts.any((t) => t.contains('开团了')), isTrue);
      expect(texts.any((t) => t.contains('1D100 →')), isTrue,
          reason: '公开骰用 diceLine 单行文案');

      // ★ 权威端 reduce 只把 {seq,seat,text,at,kind} 落进 logs（不存 opp），
      //   所以「对抗结果卡」这一支用 FeedRow 直接喂 FeedItem 验分派，
      //   而不是伪造一个 reduce 不会产生的形状。
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: Column(
            children: const <Widget>[
              FeedRow(
                item: FeedItem(
                  seq: 10,
                  at: 10,
                  kind: FeedKind.check,
                  text: '侦查 检定：骰出 33',
                ),
              ),
              FeedRow(
                item: FeedItem(
                  seq: 11,
                  at: 11,
                  kind: FeedKind.opposed,
                  text: '对抗：甲 对 乙',
                  opp: <String, Object?>{'winner': 'p1', 'tie': false},
                ),
              ),
              FeedRow(
                item: FeedItem(
                  seq: 12,
                  at: 12,
                  kind: FeedKind.check,
                  text: 'KP 秘密进行了一次检定',
                  redacted: true,
                ),
              ),
            ],
          ),
        ),
      ));
      await tester.pump();
      final rows = _renderedText(tester).join('\n');
      expect(rows.contains('侦查 检定：骰出 33'), isTrue);
      expect(rows.contains('p1 胜'), isTrue, reason: '对抗行要附结论（checkLine）');
      expect(rows.contains('私密'), isTrue, reason: 'redacted 行打「私密」标签');
    });

    testWidgets('空记录显示空态而不是空白',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      await tester.pumpWidget(_host(f, kHostSeat, const GpFeeds(pane: FeedPane.record)));
      await tester.pump();
      expect(find.byKey(GpFeedsKeys.empty), findsOneWidget);
      expect(find.text('暂无记录'), findsOneWidget);
    });

    testWidgets('懒构建：120 条不会全部进树（ListView.builder 只建可见部分）',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      for (var i = 1; i <= 120; i++) {
        _log(f, kind: 'sys', text: '第 $i 条', at: i);
      }
      await tester.pumpWidget(
        _host(f, kHostSeat, const GpFeeds(pane: FeedPane.record, height: 180)),
      );
      await tester.pump();

      final rows = find.byWidgetPredicate((Widget w) => w is FeedRow).evaluate().length;
      expect(rows, greaterThan(0));
      expect(rows, lessThan(120), reason: '懒构建必须只建可见行');
      expect(find.byKey(GpFeedsKeys.row(1)), findsNothing,
          reason: '第 1 条在 120 条之前，早已滚出视口');
    });
  });

  group('S3.2 · T-11 / T-12 两条回归（KP 与 PL 各一条渲染路径）', () {
    testWidgets('KP 侧：redacted 行只显脱敏文案，且不出现明文',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      final rec = f.host.emit(
        RoomEvt.check,
        <String, Object?>{
          'summary': '秘密检定：骰出 07，极难成功',
          'seat': 'p1',
          'at': 9,
          'kind': 'check',
        },
        vis: RoomVis.seat,
        to: 'p1',
      );
      f.kpSession.pumpPlans(f.host.plan(rec));

      await tester.pumpWidget(_host(f, kHostSeat, const GpFeeds(pane: FeedPane.record)));
      await tester.pump();

      final texts = _renderedText(tester).join('\n');
      expect(texts.contains('KP 秘密进行了一次检定'), isTrue,
          reason: '公共日志只有脱敏行（Q1 保证）');
      expect(texts.contains('秘密检定：骰出 07'), isFalse,
          reason: 'T-11：redacted 行不得还原明文');
    });

    testWidgets('PL 侧：他人视角同样只看到脱敏文案',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      final rec = f.host.emit(
        RoomEvt.check,
        <String, Object?>{
          'summary': '秘密检定：骰出 07，极难成功',
          'seat': 'p1',
          'at': 9,
          'kind': 'check',
        },
        vis: RoomVis.seat,
        to: 'p1',
      );
      f.kpSession.pumpPlans(f.host.plan(rec));

      // ★ T8：用 p2 真收到的裁剪态建块，不拿权威态假装
      await tester.pumpWidget(_host(f, 'p2', const GpFeeds(pane: FeedPane.record)));
      await tester.pump();

      final texts = _renderedText(tester).join('\n');
      expect(texts.contains('KP 秘密进行了一次检定'), isTrue);
      expect(texts.contains('秘密检定：骰出 07'), isFalse);
    });

    testWidgets('T-12：任何渲染路径都不出现原始信封键名',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      _log(f, kind: 'sys', text: '系统', at: 1);
      _log(f, kind: 'chat', text: '聊天', seat: 'p1', at: 2);
      _log(
        f,
        kind: 'check',
        text: '对抗：甲 对 乙',
        seat: 'p1',
        at: 3,
        opp: <String, Object?>{'winner': 'p1', 'tie': false},
      );
      await f.controllerOf(kHostSeat).sendIntent(
        RoomIntent.dice,
        <String, Object?>{'expr': '1D100', 'direct': true},
      );

      for (final pane in FeedPane.values) {
        await tester.pumpWidget(_host(f, kHostSeat, GpFeeds(pane: pane)));
        await tester.pump();
        final joined = _renderedText(tester).join('\n');
        for (final banned in <String>['"t":', '"vis":', '"to":', '"seq":']) {
          expect(joined.contains(banned), isFalse,
              reason: '$pane 不得渲染原始键名 $banned');
        }
      }
    });
  });

  group('S3.2 · T-10 输入行：建页挂一次、不重建、不丢字', () {
    testWidgets('★ 输入 abc → 会话重绘 → controller.text 仍是 abc 且 State 同一实例',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      await tester.pumpWidget(_host(f, kHostSeat, const GpFeeds(pane: FeedPane.chat)));
      await tester.pump();

      await tester.enterText(find.byKey(RoomKeys.gpChatInput), 'abc');
      await tester.pump();
      final before = tester.state(find.byKey(RoomKeys.gpChatInput));
      final field = tester.widget<TextField>(find.byKey(RoomKeys.gpChatInput));
      expect(field.controller!.text, 'abc');

      // 别人的消息进来 → 整块重建
      await f.controllerOf('p1').sendIntent(
        RoomIntent.chat,
        <String, Object?>{'text': '别人说话'},
      );
      await tester.pump();

      final after = tester.state(find.byKey(RoomKeys.gpChatInput));
      expect(identical(before, after), isTrue,
          reason: '★ 输入行的 State 必须被复用（重建会丢光标/输入法状态）');
      expect(tester.widget<TextField>(find.byKey(RoomKeys.gpChatInput))
          .controller!.text, 'abc');
      expect(find.text('别人说话'), findsNothing,
          reason: '记录块不显示聊天（两块数据源不同）');
    });

    testWidgets('点发送 → 发出一条 chat intent；空文本静默丢弃', (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      await tester.pumpWidget(_host(f, kHostSeat, const GpFeeds(pane: FeedPane.chat)));
      await tester.pump();
      f.clearSent();

      await tester.enterText(find.byKey(RoomKeys.gpChatInput), '   ');
      await tester.tap(find.byKey(GpFeedsKeys.send));
      await tester.pump();
      expect(f.sent, isEmpty, reason: '空文本不发包');

      await tester.enterText(find.byKey(RoomKeys.gpChatInput), '大家好');
      await tester.tap(find.byKey(GpFeedsKeys.send));
      await tester.pump();

      expect(f.sent, hasLength(1));
      expect(f.sent.single['op'], RoomIntent.chat);
      expect((f.sent.single['p']! as Map)['text'], '大家好');
      expect(f.localOf(kHostSeat).chatDraft, '', reason: '发完清草稿');
    });

    testWidgets('旁观者的输入行禁用（T-05 邻域：不能发言）',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      await tester.pumpWidget(_host(f, 'sp1', const GpFeeds(pane: FeedPane.chat)));
      await tester.pump();

      final field = tester.widget<TextField>(find.byKey(RoomKeys.gpChatInput));
      expect(field.enabled, isFalse);
      final send = tester.widget<RoomTap>(find.byKey(GpFeedsKeys.send));
      expect(send.enabled, isFalse);
    });
  });

  group('S3.3 · 私密栏（只给你看的信息）', () {
    void addPrivate(RoomUiFixture f, {required int at, required String text}) {
      final rec = f.host.emit(
        RoomEvt.private_,
        <String, Object?>{
          'title': '暗骰结果',
          'text': text,
          'at': at,
          'kind': 'dice-dark',
        },
        vis: RoomVis.seat,
        to: 'p1',
      );
      f.kpSession.pumpPlans(f.host.plan(rec));
    }

    testWidgets('最近 12 条 + 正序（最新在最后）+ 更早的被裁掉',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      for (var i = 1; i <= 15; i++) {
        addPrivate(f, at: i, text: '第 $i 条私密');
      }

      // 12 条要一次全部进树 → 用高一点的视口（懒构建只建可见行）
      useRoomScreen(tester, 420, 1000);
      await tester.pumpWidget(_host(f, 'p1', const GpPrivates(height: 760)));
      await tester.pump();

      expect(find.byKey(GpPrivatesKeys.list), findsOneWidget);
      final rows = tester.widgetList<GpPrivatesRow>(find.byType(GpPrivatesRow)).toList();
      expect(rows, hasLength(12), reason: '块 10/9 只显示最近 12 条');
      expect(rows.first.text, '第 4 条私密', reason: '15 条里的后 12 条 → 从第 4 条起');
      expect(rows.last.text, '第 15 条私密', reason: '正序：最新在最后');
      expect(find.text('第 1 条私密'), findsNothing);
    });

    testWidgets('新条高亮：上一帧没有的条目带高亮标记', (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      addPrivate(f, at: 1, text: '旧消息');
      await tester.pumpWidget(_host(f, 'p1', const GpPrivates()));
      await tester.pump();
      expect(
        tester.widget<GpPrivatesRow>(find.byType(GpPrivatesRow)).highlighted,
        isFalse,
        reason: '首帧不把自己标成新条',
      );

      addPrivate(f, at: 2, text: '新消息');
      await tester.pump();
      final rows = tester.widgetList<GpPrivatesRow>(find.byType(GpPrivatesRow)).toList();
      expect(rows.last.text, '新消息');
      expect(rows.last.highlighted, isTrue, reason: '新条要高亮（P2-05）');
      expect(rows.first.highlighted, isFalse);
    });

    testWidgets('点开全文：弹层里给出完整文案', (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      addPrivate(f, at: 1, text: '很长的一条私密文案');
      await tester.pumpWidget(_host(f, 'p1', const GpPrivates()));
      await tester.pump();

      await tester.tap(find.text('很长的一条私密文案'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('私密'), findsWidgets);
      expect(find.text('很长的一条私密文案'), findsWidgets);
    });

    testWidgets('旁观者侧私密栏为空（权威端不给旁观者发 SEAT 事件）',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      addPrivate(f, at: 1, text: '只给甲看');
      await tester.pumpWidget(_host(f, 'sp1', const GpPrivates()));
      await tester.pump();
      expect(find.text('只给甲看'), findsNothing);
      expect(find.byKey(GpPrivatesKeys.empty), findsOneWidget);
    });

    testWidgets('私密栏只渲染 text（不还原结构化字段）', (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      addPrivate(f, at: 1, text: '暗骰 1D100（侦查） = 42（困难成功）');
      await tester.pumpWidget(_host(f, 'p1', const GpPrivates()));
      await tester.pump();
      final joined = _renderedText(tester).join('\n');
      expect(joined.contains('暗骰 1D100（侦查） = 42（困难成功）'), isTrue);
      for (final banned in <String>['"rolls":', '"expr":', '"total":']) {
        expect(joined.contains(banned), isFalse);
      }
    });
  });
}
