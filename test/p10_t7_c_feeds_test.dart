// ============================================================
// test/p10_t7_c_feeds_test.dart — P10 第 7 期 C 批 A 验收
//
// 用户原话：
//   5. 「聊天框，文字输入框，改为点击文字输入框（焦点在输入框），
//       输入框变为全屏，好让玩家可以方便检查自己写了什么。」
//   6. 「公开信息栏，现在显示不出来最新的 4 条消息。全屏公开信息栏之后，
//       不实时更新最新消息。」
//
// 铁律：
//   · T1：全内存后端（RoomUiFixture），零真实 I/O；
//   · 不放宽既有断言、不 skip、不降级 findsOneWidget；
//   · 几何一律用 tester.getRect 实测，行高不写死（字体/主题会变）；
//   · 反向证伪口径见报告 _p10_transport10_ca.md：
//       快照版 body → 用例③必红；去掉首帧贴底 → 用例①必红。
//
// ★ 每条 flutter test 命令前 unset 代理 + NO_PROXY=127.0.0.1,localhost，
//   命令后立刻恢复 pubspec.lock（镜像会污染 lock）。
// ============================================================

import 'package:dice_realm/domain/room_types.dart' show RoomIntent, kHostSeat;
import 'package:dice_realm/ui/room/room_keys.dart' show RoomKeys;
import 'package:dice_realm/ui/room/room_theme.dart' show RoomTheme;
import 'package:dice_realm/ui/room/view/feed_view.dart'
    show FeedItem, FeedKind, collectChats;
import 'package:dice_realm/ui/room/widgets/gp_feeds.dart'
    show FeedList, FeedPane, FeedRow, GpFeeds, GpFeedsKeys;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart' show RoomUiFixture, useRoomScreen;

/// 块的独立宿主：MaterialApp + RoomScope + Scaffold（与既有 feeds 用例同口径）。
Widget _host(RoomUiFixture f, String seat, Widget child) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: f.scoped(seat, child: child),
        ),
      ),
    );

/// 直接喂 [FeedList] 的宿主（用于构造「同长度、不同末条 seq」的可控场景）。
Widget _listHost(List<FeedItem> items, double height) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SizedBox(
          width: 480,
          height: height,
          child: FeedList(items: items, pane: FeedPane.chat, scrollable: true),
        ),
      ),
    );

/// 造一条真实聊天（走权威端 → 客户端裁剪 → 会话通知 → 重绘）。
Future<void> _chat(RoomUiFixture f, String text, {String seat = 'p1'}) =>
    f.controllerOf(seat).sendIntent(
      RoomIntent.chat,
      <String, Object?>{'text': text},
    );

/// 普通 pump 若干帧（首帧贴底 / 跟随的 postFrameCallback 需要额外帧）。
Future<void> _pumps(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump();
  }
}

/// 弹层 / 路由转场：一帧建树 + 400ms 跑完动画 + 一帧收尾。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  // 路由退场动画跑完才算真的关掉（与既有 `room_ui_wiring_test` 同口径）。
  await tester.pumpAndSettle();
}

/// 量一条**短**聊天行的真实高度。视口高度按它算，换字体/主题也不假绿。
Future<double> _shortRowHeight(WidgetTester tester) async {
  const FeedItem probe = FeedItem(
    seq: 990001,
    at: 1,
    kind: FeedKind.chat,
    seat: 'p1',
    nickname: '甲',
    text: '短消息',
  );
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            FeedRow(
              key: GpFeedsKeys.row(probe.seq),
              item: probe,
              pane: FeedPane.chat,
            ),
          ],
        ),
      ),
    ),
  ));
  await tester.pump();
  return tester.getRect(find.byKey(GpFeedsKeys.row(probe.seq))).height;
}

/// 取主栏列表的 ScrollableState（只在没有弹层时用，避免两个 list 撞 key）。
ScrollableState _scrollable(WidgetTester tester) =>
    tester.state<ScrollableState>(find.descendant(
      of: find.byKey(GpFeedsKeys.list),
      matching: find.byType(Scrollable),
    ));

/// 一条矩形是否完整落在视口内（留 1dp 浮点容差）。
bool _fullyInside(Rect row, Rect viewport) =>
    row.top >= viewport.top - 1.0 && row.bottom <= viewport.bottom + 1.0;

void main() {
  group('P10 T7 C-A · 问题 6：最新 4 条 + 首帧贴底', () {
    testWidgets(
      '① 造 8 条 → 首帧滚到底：最后 4 条完整可见，更早 4 条在视口上方',
      (WidgetTester tester) async {
        final RoomUiFixture f = RoomUiFixture()..bootSync();
        useRoomScreen(tester, 500, 900);
        for (var i = 1; i <= 8; i++) {
          await _chat(f, '第 $i 条消息');
        }
        final List<FeedItem> items = collectChats(f.stateOf(kHostSeat));
        expect(items, hasLength(8), reason: '前置：夹具里恰好 8 条聊天');

        final double h = await _shortRowHeight(tester);
        expect(h, greaterThan(0));
        // 视口恰好 4 行：贴底后正好是最后 4 条，倒数第 5 条刚好在视口上缘之外。
        await tester.pumpWidget(_host(
          f,
          kHostSeat,
          GpFeeds(pane: FeedPane.chat, height: h * 4),
        ));
        await _pumps(tester, 5);

        // ★ GL-2a：误导文案「最新 4 条」与其 key 已随 W-C 一并删除。
        //   `GpFeedsKeys.latestHint` 常量已删（引用它会编译失败），故用硬编码字面量。
        expect(find.byKey(const ValueKey<String>('gpFeeds/latestHint')), findsNothing,
            reason: 'GL-2a：误导文案与其 key 必须一并消失');
        expect(find.text('最新 4 条'), findsNothing);
        // 既有三个抓手逐字保留（不许靠删主列表/角标换绿）。
        expect(find.byKey(GpFeedsKeys.fullscreen), findsOneWidget);
        expect(find.byKey(GpFeedsKeys.list), findsOneWidget);
        expect(find.byKey(RoomKeys.gpChatInput), findsOneWidget);
        // 取数上限未被「最新4条」反向收窄（与 room_view_test:701-702 同源常量）。
        expect(RoomTheme.feedCap, 120);
        expect(RoomTheme.chatCap, 60);
        // 正向：删文案 ≠ 删数据。本用例是 chat pane（造了 8 条聊天），
        // 取数走 collectChats；仍 >4 条且不超过 chatCap=60。
        final List<FeedItem> chats = collectChats(f.stateOf(kHostSeat));
        expect(chats.length, greaterThan(4),
            reason: '删提示文案不许把数据源截成 4 条');
        expect(chats.length, lessThanOrEqualTo(60));

        final ScrollableState scroll = _scrollable(tester);
        expect(scroll.position.maxScrollExtent, greaterThan(0),
            reason: '前置：8 行确实需要滚动');
        expect(scroll.position.pixels,
            closeTo(scroll.position.maxScrollExtent, 1.0),
            reason: '★ 首帧必须贴底（去掉首帧贴底这里就红）');

        final Rect viewport = tester.getRect(find.byKey(GpFeedsKeys.list));
        for (var i = 4; i < 8; i++) {
          final int seq = items[i].seq;
          final Finder row = find.byKey(GpFeedsKeys.row(seq));
          expect(row, findsOneWidget, reason: '第 ${i + 1} 条必须已构建');
          final Rect r = tester.getRect(row);
          expect(_fullyInside(r, viewport), isTrue,
              reason: '最新 4 条里的第 ${i + 1} 条必须完整可见：'
                  'row=$r viewport=$viewport');
        }
        for (var i = 0; i < 4; i++) {
          final Finder row = find.byKey(GpFeedsKeys.row(items[i].seq));
          if (row.evaluate().isEmpty) continue; // 懒构建未进树 = 更不可见
          final Rect r = tester.getRect(row);
          expect(r.bottom <= viewport.top + 1.0, isTrue,
              reason: '更早的第 ${i + 1} 条必须在视口上方：'
                  'row=$r viewport=$viewport');
        }
      },
    );

    testWidgets(
      '② 条数已达上限（长度不变、末条 seq 变化）→ 仍跟随到新的底',
      (WidgetTester tester) async {
        useRoomScreen(tester, 500, 900);
        // cap 打满的等价构造：始终 8 条，末条 seq 从 8 推进到 9，
        // 首条被顶掉；新末条故意是多行长文本 → 内容变高，必须再跳一次底。
        List<FeedItem> make(int tailSeq, {bool tallTail = false}) =>
            List<FeedItem>.generate(
          8,
          (int i) => FeedItem(
            seq: tailSeq - 7 + i,
            at: tailSeq - 7 + i,
            kind: FeedKind.chat,
            seat: 'p1',
            nickname: '甲',
            text: (tallTail && i == 7) ? ('这是一段较长的发言' * 8) : '短 $i',
          ),
        );

        final double h = await _shortRowHeight(tester);
        await tester.pumpWidget(_listHost(make(8), h * 4));
        await _pumps(tester, 5);
        final double p0 = _scrollable(tester).position.pixels;
        final double max0 = _scrollable(tester).position.maxScrollExtent;
        expect(max0, greaterThan(0), reason: '前置：确实存在可滚动区域');
        expect(p0, closeTo(max0, 1.0), reason: '前置：首帧已贴底');

        // 同长度（模拟 cap=8 已满）、末条 seq 变化 → 旧 length 判据不会跟随。
        await tester.pumpWidget(_listHost(make(9, tallTail: true), h * 4));
        await _pumps(tester, 5);

        final ScrollableState after = _scrollable(tester);
        expect(after.position.maxScrollExtent, greaterThan(max0 + 1.0),
            reason: '前置：新末条更高，底部位置确实前移了');
        expect(after.position.pixels,
            closeTo(after.position.maxScrollExtent, 1.0),
            reason: '★★ cap 打满、长度不变也必须跟随到最新一条'
                '（旧的 length 判据在这里会红）');
        final Rect viewport = tester.getRect(find.byKey(GpFeedsKeys.list));
        final Finder newTail = find.byKey(GpFeedsKeys.row(9));
        expect(newTail, findsOneWidget);
        expect(_fullyInside(tester.getRect(newTail), viewport), isTrue,
            reason: '新末条必须完整可见');
        expect(find.byKey(GpFeedsKeys.row(1)).evaluate().length,
            lessThanOrEqualTo(1),
            reason: '被顶掉的首条至多还在缓存里，不许重复渲染');
      },
    );

    testWidgets(
      '②b 真实 cap 边界：GpFeeds(limit: 8) 打满后追加一条 → 主栏仍显示新末条',
      (WidgetTester tester) async {
        final RoomUiFixture f = RoomUiFixture()..bootSync();
        useRoomScreen(tester, 500, 900);
        for (var i = 1; i <= 8; i++) {
          await _chat(f, '短 $i');
        }
        final double h = await _shortRowHeight(tester);
        await tester.pumpWidget(_host(
          f,
          kHostSeat,
          GpFeeds(pane: FeedPane.chat, limit: 8, height: h * 4),
        ));
        await _pumps(tester, 5);
        final List<FeedItem> before = collectChats(f.stateOf(kHostSeat), limit: 8);
        expect(before, hasLength(8));
        final int oldTail = before.last.seq;

        // 第 9 条进来：collectChats(limit: 8) 仍是 8 条，但末条 seq 变了。
        await _chat(f, '打满 cap 之后的新消息');
        await _pumps(tester, 5);
        final List<FeedItem> after = collectChats(f.stateOf(kHostSeat), limit: 8);
        expect(after, hasLength(8), reason: '前置：长度没变（cap 已打满）');
        expect(after.last.seq, isNot(oldTail), reason: '前置：末条 seq 前进了');
        expect(find.byKey(GpFeedsKeys.row(after.last.seq)), findsOneWidget,
            reason: '★ 新末条必须进树并贴底可见');
        final ScrollableState scroll = _scrollable(tester);
        expect(scroll.position.pixels,
            closeTo(scroll.position.maxScrollExtent, 1.0),
            reason: '★ 长度不变也跟随');
      },
    );

    testWidgets(
      '⑦ P0-06 口径不动：用户上滚回看时新消息不抢滚动位置',
      (WidgetTester tester) async {
        final RoomUiFixture f = RoomUiFixture()..bootSync();
        useRoomScreen(tester, 500, 900);
        for (var i = 1; i <= 8; i++) {
          await _chat(f, '消息 $i');
        }
        final double h = await _shortRowHeight(tester);
        await tester.pumpWidget(_host(
          f,
          kHostSeat,
          GpFeeds(pane: FeedPane.chat, height: h * 4),
        ));
        await _pumps(tester, 5);
        expect(_scrollable(tester).position.pixels,
            closeTo(_scrollable(tester).position.maxScrollExtent, 1.0));

        // 模拟用户上滚回看（回到顶部）。
        _scrollable(tester).position.jumpTo(0);
        await tester.pump();
        expect(_scrollable(tester).position.pixels, 0);

        await _chat(f, '回看时来的新消息');
        await _pumps(tester, 5);
        expect(_scrollable(tester).position.pixels, 0,
            reason: '★ 未贴底时不许自动拉回底部（P0-06 逐字保留）');
      },
    );
  });

  group('P10 T7 C-A · 问题 6：全屏信息栏实时', () {
    testWidgets(
      '③ ★ 全屏弹层打开状态下注入新消息 → 弹层内实时出现该行',
      (WidgetTester tester) async {
        final RoomUiFixture f = RoomUiFixture()..bootSync();
        useRoomScreen(tester, 500, 900);
        for (var i = 1; i <= 4; i++) {
          await _chat(f, '历史 $i');
        }
        await tester.pumpWidget(
            _host(f, kHostSeat, const GpFeeds(pane: FeedPane.chat)));
        await _pumps(tester, 3);

        await tester.tap(find.byKey(GpFeedsKeys.fullscreen));
        await _settle(tester);
        expect(find.byKey(GpFeedsKeys.liveBody), findsOneWidget,
            reason: '前置：全屏弹层已经打开');
        final int before = collectChats(f.stateOf(kHostSeat)).length;

        // ★ 硬验收时序：弹层**开着**的时候再灌一条，pump 让会话通知走完。
        await _chat(f, '弹层打开后才来的新消息');
        await _settle(tester);
        await _pumps(tester, 3);

        final List<FeedItem> items = collectChats(f.stateOf(kHostSeat));
        expect(items.length, before + 1, reason: '前置：权威侧确实多了一条');
        final int newSeq = items.last.seq;
        expect(
          find.descendant(
            of: find.byKey(GpFeedsKeys.liveBody),
            matching: find.byKey(GpFeedsKeys.row(newSeq)),
          ),
          findsOneWidget,
          reason: '★★ 全屏弹层必须实时出现刚注入的新行'
              '（把 body 换回 FeedList(items: items) 快照这里必红）',
        );
        expect(
          find.descendant(
            of: find.byKey(GpFeedsKeys.liveBody),
            matching: find.byType(FeedRow),
          ).evaluate().length,
          before + 1,
          reason: '弹层里行数同步 +1（不截断、不缓存旧批次）',
        );
      },
    );

    testWidgets(
      '④ 全屏内无重复 / 陈旧行；关闭弹层后主栏仍正常',
      (WidgetTester tester) async {
        final RoomUiFixture f = RoomUiFixture()..bootSync();
        useRoomScreen(tester, 500, 900);
        for (var i = 1; i <= 6; i++) {
          await _chat(f, '消息 $i');
        }
        await tester.pumpWidget(
            _host(f, kHostSeat, const GpFeeds(pane: FeedPane.chat)));
        await _pumps(tester, 3);

        await tester.tap(find.byKey(GpFeedsKeys.fullscreen));
        await _settle(tester);

        final List<FeedItem> items = collectChats(f.stateOf(kHostSeat));
        for (final FeedItem it in items) {
          expect(
            find.descendant(
              of: find.byKey(GpFeedsKeys.liveBody),
              matching: find.byKey(GpFeedsKeys.row(it.seq)),
            ).evaluate().length,
            lessThanOrEqualTo(1),
            reason: 'seq=${it.seq} 在全屏里至多一份（不许重复）',
          );
        }

        // 弹层开着再注入一条：新行只出现一次，旧行不重排、不残留陈旧快照。
        await _chat(f, '弹层开着又来一条');
        await _settle(tester);
        await _pumps(tester, 2);
        final List<FeedItem> now = collectChats(f.stateOf(kHostSeat));
        expect(
          find.descendant(
            of: find.byKey(GpFeedsKeys.liveBody),
            matching: find.byKey(GpFeedsKeys.row(now.last.seq)),
          ),
          findsOneWidget,
        );
        for (final FeedItem it in now) {
          expect(
            find.descendant(
              of: find.byKey(GpFeedsKeys.liveBody),
              matching: find.byKey(GpFeedsKeys.row(it.seq)),
            ).evaluate().length,
            lessThanOrEqualTo(1),
            reason: '刷新后 seq=${it.seq} 仍不许重复',
          );
        }

        // 关闭全屏。
        // ★ P20 需求 3⑥b：全屏壳已从 `showRoomSheet`（底部弹层，点 (4,4) 打在
        //   modal barrier 上即关）改成 `showFullscreenReader`（**真路由** +
        //   AppBar + 关闭按钮）。真路由的返回键热区实测 `LTRB(4.5, 4, 52.5, 52)`，
        //   老坐标 `(4,4)` 落在它左边缘之外（x=4 < 4.5）⇒ 点空、路由不关。
        //   改为点弹层自带的关闭按钮（`FullscreenReader` 的 AppBar action，
        //   `Icons.close`）；`_settle` 里的 `pumpAndSettle` 负责把退场动画跑完。
        //   这不是放宽断言：关不掉，下面两条 findsNothing / findsOneWidget 照样红。
        await tester.tap(find.byIcon(Icons.close));
        await _settle(tester);
        expect(find.byKey(GpFeedsKeys.liveBody), findsNothing,
            reason: '弹层已关闭');
        expect(find.byKey(GpFeedsKeys.list), findsOneWidget,
            reason: '主栏列表仍在');
        expect(find.byKey(GpFeedsKeys.fullscreen), findsOneWidget);
        expect(find.byKey(RoomKeys.gpChatInput), findsOneWidget,
            reason: '主栏聊天输入行仍在');
      },
    );
  });

  group('P10 T7 C-A · 问题 5：聊天输入框全屏编辑', () {
    testWidgets(
      '⑤ tap 聊天输入框 → 全屏编辑页；长文本「完成」写回原输入框 + 草稿同步',
      (WidgetTester tester) async {
        final RoomUiFixture f = RoomUiFixture()..bootSync();
        useRoomScreen(tester, 500, 900);
        await tester.pumpWidget(
            _host(f, kHostSeat, const GpFeeds(pane: FeedPane.chat)));
        await _pumps(tester, 3);
        f.clearSent();

        expect(find.byKey(GpFeedsKeys.chatFullscreen), findsOneWidget,
            reason: '独立「全屏编辑」入口存在');
        expect(find.byKey(GpFeedsKeys.chatComposer), findsNothing,
            reason: '前置：还没打开全屏页');

        await tester.tap(find.byKey(RoomKeys.gpChatInput));
        await _settle(tester);
        expect(find.byKey(GpFeedsKeys.chatComposer), findsOneWidget,
            reason: '★ 点击输入框必须变成全屏编辑页');
        expect(find.byKey(GpFeedsKeys.chatComposerField), findsOneWidget);
        expect(find.byKey(GpFeedsKeys.chatComposerDone), findsOneWidget);
        expect(find.byKey(GpFeedsKeys.chatComposerSend), findsOneWidget);
        expect(find.text('编辑发言'), findsOneWidget);

        final String longText = ('这是一段需要放大才能检查的长发言，'
                '里面有细节、还有第二句和第三句，'
                '单行输入框根本看不全。') *
            3;
        await tester.enterText(
            find.byKey(GpFeedsKeys.chatComposerField), longText);
        await _pumps(tester, 2);
        expect(f.localOf(kHostSeat).chatDraft, longText,
            reason: 'onChanged 逐字同步 RoomUiLocal.chatDraft');

        await tester.tap(find.byKey(GpFeedsKeys.chatComposerDone));
        await _settle(tester);
        expect(find.byKey(GpFeedsKeys.chatComposer), findsNothing,
            reason: '「完成」后全屏页关闭');
        final TextField field =
            tester.widget<TextField>(find.byKey(RoomKeys.gpChatInput));
        expect(field.controller!.text, longText,
            reason: '★ 原 RoomKeys.gpChatInput 的文本 == 输入内容');
        expect(field.controller!.selection.baseOffset, longText.length,
            reason: '光标移到末尾');
        expect(f.localOf(kHostSeat).chatDraft, longText,
            reason: 'local.chatDraft 同步');
        expect(f.sent.where((Map<String, Object?> e) => e['op'] == RoomIntent.chat),
            isEmpty,
            reason: '「完成」只回填、不发送（AI RP 同口径）');
      },
    );

    testWidgets(
      '⑥ 全屏「发送」→ RoomIntent.chat 发出、草稿清空、全屏页关闭',
      (WidgetTester tester) async {
        final RoomUiFixture f = RoomUiFixture()..bootSync();
        useRoomScreen(tester, 500, 900);
        await tester.pumpWidget(
            _host(f, kHostSeat, const GpFeeds(pane: FeedPane.chat)));
        await _pumps(tester, 3);
        f.clearSent();

        await tester.tap(find.byKey(GpFeedsKeys.chatFullscreen));
        await _settle(tester);
        expect(find.byKey(GpFeedsKeys.chatComposer), findsOneWidget,
            reason: '独立入口同样能开全屏');

        await tester.enterText(
            find.byKey(GpFeedsKeys.chatComposerField), '  从全屏发出  ');
        await _pumps(tester, 2);
        await tester.tap(find.byKey(GpFeedsKeys.chatComposerSend));
        await _settle(tester);
        await _pumps(tester, 2);

        final List<Map<String, Object?>> chats = f.sent
            .where((Map<String, Object?> e) => e['op'] == RoomIntent.chat)
            .toList();
        expect(chats, hasLength(1), reason: '★ 发出且只发出一条 chat intent');
        expect((chats.single['p']! as Map)['text'], '从全屏发出',
            reason: '复用原 _send() 的 trim 语义');
        expect(f.localOf(kHostSeat).chatDraft, '', reason: '★ 发完清草稿');
        expect(find.byKey(GpFeedsKeys.chatComposer), findsNothing,
            reason: '★ 发送后全屏页关闭');
        expect(
          tester
              .widget<TextField>(find.byKey(RoomKeys.gpChatInput))
              .controller!
              .text,
          '',
          reason: '原输入框同步清空',
        );
      },
    );

    testWidgets(
      '⑥b 旁观者：不渲染全屏入口、点输入框也不弹全屏',
      (WidgetTester tester) async {
        final RoomUiFixture f = RoomUiFixture()..bootSync();
        useRoomScreen(tester, 500, 900);
        await tester.pumpWidget(
            _host(f, 'sp1', const GpFeeds(pane: FeedPane.chat)));
        await _pumps(tester, 3);

        expect(find.byKey(GpFeedsKeys.chatFullscreen), findsNothing,
            reason: '★ 旁观者不渲染全屏编辑入口');
        final TextField field =
            tester.widget<TextField>(find.byKey(RoomKeys.gpChatInput));
        expect(field.enabled, isFalse, reason: '既有断言：旁观者输入行禁用');
        expect(field.onTap, isNull, reason: '旁观者输入框不挂全屏 onTap');
        await tester.tap(find.byKey(RoomKeys.gpChatInput), warnIfMissed: false);
        await _settle(tester);
        expect(find.byKey(GpFeedsKeys.chatComposer), findsNothing,
            reason: '★ 旁观者点输入框不弹全屏');
      },
    );

    testWidgets(
      '⑧ 回归口径：enterText 不弹全屏、AI RP 与发送键都还在',
      (WidgetTester tester) async {
        final RoomUiFixture f = RoomUiFixture()..bootSync();
        useRoomScreen(tester, 500, 900);
        await tester.pumpWidget(
            _host(f, kHostSeat, const GpFeeds(pane: FeedPane.chat)));
        await _pumps(tester, 3);
        f.clearSent();

        // 既有用例的写法：enterText（不是 tap）绝不能被 onTap 拦截。
        await tester.enterText(find.byKey(RoomKeys.gpChatInput), 'abc');
        await _pumps(tester, 2);
        expect(find.byKey(GpFeedsKeys.chatComposer), findsNothing,
            reason: '★ enterText 只聚焦，不弹全屏（不能回归既有输入用例）');
        expect(
          tester
              .widget<TextField>(find.byKey(RoomKeys.gpChatInput))
              .controller!
              .text,
          'abc',
        );
        expect(f.localOf(kHostSeat).chatDraft, 'abc');
        expect(find.byKey(GpFeedsKeys.aiRp), findsOneWidget,
            reason: 'AI RP 入口保持不变');
        expect(find.byKey(GpFeedsKeys.send), findsOneWidget);

        await tester.tap(find.byKey(GpFeedsKeys.send));
        await _pumps(tester, 2);
        final List<Map<String, Object?>> chats = f.sent
            .where((Map<String, Object?> e) => e['op'] == RoomIntent.chat)
            .toList();
        expect(chats, hasLength(1));
        expect((chats.single['p']! as Map)['text'], 'abc');
      },
    );
  });
}
