// ============================================================
// room_feed_flash_wiring_test.dart — P2-05「接线」验收
//
// 纯逻辑测试（room_feed_flash_test.dart）证明不了「tracker 真的被接上了」：
// 一个从没被引用的类照样能全绿。所以这里走真实消息流 + 真实 widget 树。
//
// ★ T1 铁律：全部用 RoomUiFixture 的内存后端（boot() 里 repo/settings/share
//   /saveStore 都是内存实现），零文件 I/O —— fake-async 下真实 I/O 的
//   Future 永不完成。
// ★ 零 Timer / 零 Future.delayed / 零 AnimationController：角标是
//   「本次 build 派生的状态标记」，测试用 pump() 直接驱动与断言。
// ★ 反向验证：注入「恒不闪」的判据（等价于把接线摘掉）后，正例必须变红。
//   —— 防止写出「无论如何都绿」的断言。
//
// ★ Round 2 分工：本文件只管「判据退役后的正常在线行为」。
//   「断线补拉不闪」已改由连接层 syncEpoch 显式信号驱动，那部分真实链路
//   回归（含漏 1~6 事件、两列交错、反向验证）在 room_sync_epoch_test.dart。
//   本机会话没有重连概念，syncEpoch 恒 0，正好用来测「正常在线」。
// ============================================================

import 'package:dice_realm/domain/room_types.dart' show RoomIntent, kHostSeat;
import 'package:dice_realm/ui/room/room_feed_flash.dart' show FeedFlashTracker;
import 'package:dice_realm/ui/room/view/feed_view.dart'
    show collectChats, collectFeeds;
import 'package:dice_realm/ui/room/widgets/gp_feeds.dart'
    show FeedPane, GpFeeds, GpFeedsKeys;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart' show RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

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

/// 用真实 intent 发一条聊天（走权威端 → 客户端裁剪 → 会话通知 → 重绘）。
Future<void> _chat(RoomUiFixture f, String seat, String text) =>
    f.controllerOf(seat).sendIntent(
      RoomIntent.chat,
      <String, Object?>{'text': text},
    );

/// 用真实 intent 掷一枚公开骰（进 record pane 的 dice 分支）。
Future<void> _dice(RoomUiFixture f, String seat) =>
    f.controllerOf(seat).sendIntent(
      RoomIntent.dice,
      <String, Object?>{'expr': '1D100', 'direct': true},
    );

/// 当前该 pane「展示序末条」的 seq —— 与 GpFeeds 选数据时同口径。
int _seqOf(RoomUiFixture f, FeedPane pane) {
  final state = f.stateOf(kHostSeat);
  final items = pane == FeedPane.chat
      ? collectChats(state)
      : collectFeeds(state);
  return items.isEmpty ? 0 : items.last.seq;
}

/// 首屏基线：先造两条真实历史，再 pump —— 首绘只登记基线、不闪。
Future<void> _seedAndPump(
  WidgetTester tester,
  RoomUiFixture f, {
  required Widget child,
  int history = 2,
}) async {
  for (var i = 0; i < history; i++) {
    await _chat(f, 'p1', '历史消息 $i');
  }
  await tester.pumpWidget(_host(f, kHostSeat, child));
  await tester.pump();
  expect(find.byKey(GpFeedsKeys.flash(FeedPane.chat)), findsNothing,
      reason: '前置：首屏（含历史）不许闪');
}

/// 判据替身：恒不闪。用来模拟「把接线摘掉 / 传一个空 tracker」。
class _NeverFlash extends FeedFlashTracker {
  int calls = 0;

  @override
  bool? check({
    required int lastSeq,
    required String lastSeat,
    required String mySeat,
  }) {
    calls += 1;
    return false;
  }
}

void main() {
  group('P2-05 · 接线（真实消息流）', () {
    testWidgets('★ 历史首屏不闪（几十条历史一起进来也不放烟花）',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 900);

      // 一次灌 8 条历史：首绘仍必须一次都不闪（靠「首次只登记基线」）。
      await _seedAndPump(
        tester,
        f,
        child: const GpFeeds(pane: FeedPane.chat),
        history: 8,
      );
      expect(find.byKey(GpFeedsKeys.flash(FeedPane.chat)), findsNothing);
    });

    testWidgets('★ 来一条别人的消息 → 角标出现', (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 900);

      await _seedAndPump(tester, f, child: const GpFeeds(pane: FeedPane.chat));
      final base = _seqOf(f, FeedPane.chat);
      expect(base, greaterThan(0), reason: '前置：基线必须已登记');

      await _chat(f, 'p1', '别人新说的一句话');
      final now = _seqOf(f, FeedPane.chat);
      expect(now, greaterThan(base),
          reason: '前置：新消息必须推进展示序末条 seq；'
              '判据退役后差值多大都该闪，不再有阈值介入');

      await tester.pump();
      expect(find.byKey(GpFeedsKeys.flash(FeedPane.chat)), findsOneWidget,
          reason: '★★ 这一条就是接线本身：tracker 说该闪，屏幕上必须有东西');
      final badge =
          tester.widget<RoomTap>(find.byKey(GpFeedsKeys.flash(FeedPane.chat)));
      expect(badge.label, '新');
      expect(badge.enabled, isTrue);
    });

    testWidgets('★ 来一条自己的消息 → 不闪', (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 900);

      await _seedAndPump(tester, f, child: const GpFeeds(pane: FeedPane.chat));
      // 视角是 KP（kHostSeat），所以「自己发的」= 从 kHostSeat 发。
      await _chat(f, kHostSeat, '我自己说的');
      await tester.pump();

      expect(find.byKey(GpFeedsKeys.flash(FeedPane.chat)), findsNothing,
          reason: '★ 用户知道自己刚发了什么，闪了反而莫名其妙');
    });

    testWidgets('★ 一次涌入 7 条（正常在线、没有补拉信号）→ 仍该闪',
        (WidgetTester tester) async {
      // ★ 如实重写（原用例：「一次涌入 7 条（重连补拉）→ 不闪」）。
      // 旧用例把「差值 > 6」当成补拉的证据，于是断言不闪。Round 2 之后
      // 补拉只能由连接层 syncEpoch 显式告知；本机会话 syncEpoch 恒 0，
      // 所以这批消息就是「正常在线别人连发了 7 条」→ 按判据该闪。
      // 「真补拉不闪」改由 room_sync_epoch_test.dart 用真实 sync 帧回归。
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 900);

      await _seedAndPump(tester, f, child: const GpFeeds(pane: FeedPane.chat));
      final base = _seqOf(f, FeedPane.chat);
      for (var i = 0; i < 7; i++) {
        await _chat(f, 'p1', '连发 $i'); // 故意不 pump：让 7 条落在同一次重绘里
      }
      expect(_seqOf(f, FeedPane.chat) - base, greaterThanOrEqualTo(7),
          reason: '前置：确实一次涌入了 7 条以上，且差值 > 6');
      await tester.pump();

      expect(find.byKey(GpFeedsKeys.flash(FeedPane.chat)), findsOneWidget,
          reason: '★ 差值 > 6 不再等于补拉；没有世代信号时这就是新消息，该闪');
    });

    testWidgets('★ 点一下角标即收起（消退不需要 Timer）',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 900);

      await _seedAndPump(tester, f, child: const GpFeeds(pane: FeedPane.chat));
      await _chat(f, 'p1', '新消息');
      await tester.pump();
      final badge = find.byKey(GpFeedsKeys.flash(FeedPane.chat));
      expect(badge, findsOneWidget);

      await tester.tap(badge);
      await tester.pump();
      expect(badge, findsNothing,
          reason: '★ 用户已读即收起；同步 setState，不依赖任何异步时钟');
    });

    testWidgets('★ 两个 pane 各持一个 tracker（聊天闪不会带闪记录）',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 1100);

      // 两列都先有历史，保证两个 tracker 都登记过基线。
      await _chat(f, 'p1', '聊天历史 1');
      await _chat(f, 'p1', '聊天历史 2');
      await _dice(f, 'p1');
      await _dice(f, 'p1');

      await tester.pumpWidget(_host(
        f,
        kHostSeat,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: const <Widget>[
            GpFeeds(pane: FeedPane.chat, height: 140),
            GpFeeds(pane: FeedPane.record, height: 140),
          ],
        ),
      ));
      await tester.pump();
      expect(find.byKey(GpFeedsKeys.flash(FeedPane.chat)), findsNothing);
      expect(find.byKey(GpFeedsKeys.flash(FeedPane.record)), findsNothing);

      // 只来一条聊天：chat 的 seq 前进，record 的数据源（logs+dice）没动。
      await _chat(f, 'p1', '只进聊天');
      await tester.pump();
      expect(find.byKey(GpFeedsKeys.flash(FeedPane.chat)), findsOneWidget,
          reason: '聊天列该闪');
      expect(find.byKey(GpFeedsKeys.flash(FeedPane.record)), findsNothing,
          reason: '★ 记录列必须不受影响 —— 若共用一个 tracker 就会误闪');
    });

    testWidgets('★ 大差值后点收起，再来 1 条别人消息仍闪（无冷却期）',
        (WidgetTester tester) async {
      // 为什么存在：flood 判据退役后不能引入「闪过一批就沉默」的退化。
      // 这条同时守住「点收起只收当前角标，不影响后续判定」。
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 900);

      await _seedAndPump(tester, f, child: const GpFeeds(pane: FeedPane.chat));
      for (var i = 0; i < 7; i++) {
        await _chat(f, 'p1', '一批 $i');
      }
      await tester.pump();
      final badge = find.byKey(GpFeedsKeys.flash(FeedPane.chat));
      expect(badge, findsOneWidget, reason: '前置：大差值这批应该闪');

      await tester.tap(badge);
      await tester.pump();
      expect(badge, findsNothing, reason: '前置：已收起');

      await _chat(f, 'p1', '收起之后的又一条');
      await tester.pump();
      expect(badge, findsOneWidget,
          reason: '★★ 大差值没有污染后续基线，下一条真新消息仍要闪');
    });

    testWidgets('★ 换房间（session 对象被替换）→ 首屏不闪',
        (WidgetTester tester) async {
      // 为什么存在：Round 2 把 reset 条件扩成「对象替换 **或** 世代变化」，
      // 老的 identical 分支不能被改坏 —— 换房间仍必须重新登记基线。
      final f1 = RoomUiFixture();
      await f1.boot();
      useRoomScreen(tester, 400, 900);

      await _seedAndPump(tester, f1, child: const GpFeeds(pane: FeedPane.chat));
      await _chat(f1, 'p1', '旧房间的新消息');
      await tester.pump();
      expect(find.byKey(GpFeedsKeys.flash(FeedPane.chat)), findsOneWidget,
          reason: '前置：旧房间确实闪了');

      final f2 = RoomUiFixture();
      await f2.boot();
      await _chat(f2, 'p1', '新房间历史 1');
      await _chat(f2, 'p1', '新房间历史 2');
      await tester.pumpWidget(
        _host(f2, kHostSeat, const GpFeeds(pane: FeedPane.chat)),
      );
      await tester.pump();

      expect(find.byKey(GpFeedsKeys.flash(FeedPane.chat)), findsNothing,
          reason: '★ 换了 session 对象，新房间首批历史必须按首屏处理');
    });
  });

  group('P2-05 · 反向验证（防恒绿断言）', () {
    testWidgets('★★ 换成「恒不闪」判据 → 同一场景下角标必须不出现',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 900);
      final never = _NeverFlash();

      await _seedAndPump(
        tester,
        f,
        child: GpFeeds(pane: FeedPane.chat, flashTracker: never),
      );
      await _chat(f, 'p1', '别人新说的一句话');
      await tester.pump();

      expect(never.calls, greaterThan(0),
          reason: '前置：判据确实被调用了（不是压根没接线）');
      expect(find.byKey(GpFeedsKeys.flash(FeedPane.chat)), findsNothing,
          reason: '★★ 判据说不闪，UI 就不许自作主张闪；'
              '若把 GpFeeds 里的角标逻辑写死成恒显示，这条会红');
    });

    testWidgets('★★ 同一棵树里把判据从「恒不闪」换回默认 → 角标重新出现',
        (WidgetTester tester) async {
      // 这条与上面那条成对：证明「闪 / 不闪」只由注入的判据决定，
      // 而不是由消息条数、pump 次数之类恒为真的条件决定。
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 900);
      final never = _NeverFlash();

      await _seedAndPump(
        tester,
        f,
        child: GpFeeds(pane: FeedPane.chat, flashTracker: never),
      );
      await _chat(f, 'p1', '第一条新消息');
      await tester.pump();
      expect(find.byKey(GpFeedsKeys.flash(FeedPane.chat)), findsNothing);

      // 换回默认 tracker：didUpdateWidget 会重建判据并重置基线。
      await tester.pumpWidget(
        _host(f, kHostSeat, const GpFeeds(pane: FeedPane.chat)),
      );
      await tester.pump();
      expect(find.byKey(GpFeedsKeys.flash(FeedPane.chat)), findsNothing,
          reason: '换判据后的首绘仍只登记基线');

      await _chat(f, 'p1', '第二条新消息');
      await tester.pump();
      expect(find.byKey(GpFeedsKeys.flash(FeedPane.chat)), findsOneWidget,
          reason: '★★ 默认判据接管后，同一场景重新变闪 —— 差别只在判据');
    });
  });
}
