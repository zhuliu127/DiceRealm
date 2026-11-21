// ============================================================
// room_sync_epoch_test.dart — Round 2：连接层显式补拉信号 + 两条真缺陷回归
//
// 背景（QA 报告 §4，主理人裁决采纳）：第一批把「是不是断线补拉 / 是不是
// 一次涌入太多」交给 FeedFlashTracker 用**全局 evt.seq 差值**去猜，判定为
// 两条功能性 bug，且是同一个错误抽象的两面：
//   · 限制 2：短断线只漏 1~6 个事件，差值够不到阈值 6 → 补拉回来误闪；
//   · 限制 3：正常在线、两条聊天之间夹了 7 条记录 / 骰子，差值被放大到 8
//     → 新聊天被误判成「补拉」而漏闪（QA_PROBE_LIMIT3 jump=8）。
//
// 修法：补拉改由连接层显式信号 RoomSession.syncEpoch 告知，seq 差判据
// 整个退役。本文件用**真实连接层对象**验证这条链路：
//
//   LanClient.deliverForTest(syncEnvelope)
//     → RoomClient.receive() 整体替换 state（全量 sync「应用完成」）
//     → result.kind == 'sync' → LanClient.syncEpoch += 1
//     → 复用 _deliver() 末尾已有的 onChange?.call()
//     → RemoteSession.notifyListeners()
//     → RoomScope（InheritedNotifier）→ GpFeeds.build() 发现世代变化
//     → tracker.reset() + 清 _checkedSeq / _flash，本次重新登记首屏基线
//
// ★ 三条补拉路径（自动重连 / gap 自愈 / RemoteSession.pullSync 显式补拉）
//   最终都由服务端回的**同一份全量 sync 帧**汇入 _deliver()，所以这里用
//   同一个投帧口覆盖它们的共同落点，并单独验证「发补拉请求」本身不算完成。
// ★ 全部内存后端（T1）：不起真 socket、不 connect()、不碰传输帧协议
//   （K3）、零文件 I/O；投帧用的是 RoomHost.syncFor() 产出的**生产级合法
//   全量信封**，不是自造的假 JSON。
// ★ 零 Timer / 零 Future.delayed / 零 AnimationController：投帧与 notify
//   都是同步的，widget 用例用 pump() 直接驱动，FakeAsync 下不会挂起。
// ============================================================

import 'package:dice_realm/domain/room_types.dart'
    show EvtEnvelope, RoomEvt, RoomIntent, SyncEnvelope, kHostSeat;
import 'package:dice_realm/net/lan_client.dart' show LanClient;
import 'package:dice_realm/ui/room/room_scope.dart' show RoomScope;
import 'package:dice_realm/ui/room/room_session_remote.dart' show RemoteSession;
import 'package:dice_realm/ui/room/view/feed_view.dart'
    show collectChats, collectFeeds;
import 'package:dice_realm/ui/room/widgets/gp_feeds.dart'
    show FeedPane, GpFeeds, GpFeedsKeys;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

// ------------------------------------------------------------
// 连接层夹具（纯 Dart 用）：不出网、只投应用层信封
// ------------------------------------------------------------

LanClient _newClient() => LanClient(
      base: 'http://127.0.0.1:1',
      seat: kHostSeat,
      code: 'r2-epoch',
    );

/// 一份**合法的全量 sync 帧**（形状与 SyncEnvelope.toJson() 一致）。
///
/// [mark] 是额外放的诊断键，用来证明 `RoomClient.receive()` 真的把 state
/// 整体替换了，而不是「只把 seq 调大」。meta 必须是 Map（客户端据此
/// emptyRoomState 重建默认态），chats / logs / dice 是信息流的数据源。
Map<String, Object?> _syncFrame(
  int seq, {
  int chatCount = 0,
  int diceCount = 0,
}) {
  final chats = <Map<String, Object?>>[
    for (var i = 0; i < chatCount; i++)
      <String, Object?>{
        'seq': i + 1,
        'at': i + 1,
        'seat': 'p1',
        'nickname': '玩家1',
        'text': '历史聊天 $i',
      },
  ];
  final dice = <Map<String, Object?>>[
    for (var i = 0; i < diceCount; i++)
      <String, Object?>{
        'seq': 100 + i,
        'at': 100 + i,
        'seat': 'p1',
        'nickname': '玩家1',
        'expr': '1D100',
        'rolls': <Object?>[50],
        'levelText': '',
        'label': '',
      },
  ];
  return SyncEnvelope(seq, <String, Object?>{
    'meta': <String, Object?>{'code': 'r2-epoch'},
    'members': <Object?>[],
    'chats': chats,
    'logs': <Object?>[],
    'dice': dice,
    'mark': 'sync-$seq',
  }).toJson();
}

/// 一条**合法的增量 chat 帧**。seq 必须等于客户端 lastSeq + 1 才能过闸门。
Map<String, Object?> _chatEvt(int seq, num at, String text) => EvtEnvelope(
      seq,
      RoomEvt.chat,
      <String, Object?>{
        'seat': 'p1',
        'nickname': '玩家1',
        'text': text,
        'at': at,
      },
    ).toJson();

/// 当前聊天列表里最大的 at —— 增量投帧要排在展示序末尾，不能猜权威端时钟。
num _maxChatAt(Map<String, Object?> state) {
  num max = 0;
  final rows = state['chats'];
  if (rows is List) {
    for (final row in rows) {
      if (row is Map) {
        final at = row['at'];
        if (at is num && at > max) max = at;
      }
    }
  }
  return max;
}

// ------------------------------------------------------------
// widget 夹具：内存后端 + 真 RemoteSession
// ------------------------------------------------------------

/// 两列同屏，各持一个 tracker（按 pane 分 key，互不干扰）。
Widget _twoPanes() => const Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        GpFeeds(pane: FeedPane.chat, height: 140),
        GpFeeds(pane: FeedPane.record, height: 140),
      ],
    );

/// 本机会话宿主（syncEpoch 恒 0，用来测「正常在线」）。
Widget _localHost(RoomUiFixture f, Widget child) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: f.scoped(kHostSeat, child: child),
        ),
      ),
    );

/// 远端会话宿主：RoomScope 的 notifier 就是真 RemoteSession，
/// 这样 LanClient.onChange → notifyListeners() 能直接驱动 GpFeeds 重建。
Widget _remoteHost(RoomUiFixture f, RemoteSession session, Widget child) =>
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: RoomScope(
            session: session,
            local: f.localOf(kHostSeat),
            controller: f.controllerOf(kHostSeat),
            child: child,
          ),
        ),
      ),
    );

Future<void> _chat(RoomUiFixture f, String seat, String text) =>
    f.controllerOf(seat).sendIntent(
      RoomIntent.chat,
      <String, Object?>{'text': text},
    );

Future<void> _dice(RoomUiFixture f, String seat) =>
    f.controllerOf(seat).sendIntent(
      RoomIntent.dice,
      <String, Object?>{'expr': '1D100', 'direct': true},
    );

/// 聊天列「展示序末条」的 seq（与 GpFeeds._deriveFlash 同口径）。
int _chatSeq(RoomUiFixture f) {
  final items = collectChats(f.stateOf(kHostSeat));
  return items.isEmpty ? 0 : items.last.seq;
}

/// 两列都先有真实历史，再 pump —— 首绘只登记基线，两列都不闪。
Future<void> _seedHistoryAndPump(
  WidgetTester tester,
  RoomUiFixture f, {
  required Widget child,
}) async {
  await _chat(f, 'p1', '历史聊天 1');
  await _chat(f, 'p1', '历史聊天 2');
  await _dice(f, 'p1');
  await _dice(f, 'p1');
  await tester.pumpWidget(child);
  await tester.pump();
  expect(find.byKey(GpFeedsKeys.flash(FeedPane.chat)), findsNothing,
      reason: '前置：首屏历史两列都不许闪');
  expect(find.byKey(GpFeedsKeys.flash(FeedPane.record)), findsNothing);
}

void main() {
  // ==========================================================
  // 一、连接层显式信号（纯逻辑，不起 socket）
  // ==========================================================
  group('Round 2 · 连接层 syncEpoch 显式补拉信号', () {
    test('本机会话没有重连概念：RoomSession 默认 syncEpoch 恒 0', () {
      final f = RoomUiFixture()..bootSync();
      expect(f.sessionOf(kHostSeat).syncEpoch, 0,
          reason: '默认实现要兼容 LocalLoopback / Hosting，零改动');
      expect(f.sessionOf('p1').syncEpoch, 0);
    });

    test('★ 首份全量 sync：世代 0→1，state 真的被整体替换，lastSeq 推进', () {
      final lan = _newClient();
      expect(lan.syncEpoch, 0);
      lan.deliverForTest(_syncFrame(10, chatCount: 2));
      expect(lan.syncEpoch, 1);
      expect(lan.client.lastSeq, 10);
      expect(lan.client.state['mark'], 'sync-10',
          reason: '必须是「应用完成」一份全量，而不是只把序号调大');
      expect(collectChats(lan.client.state).length, 2);
    });

    test('★ 连续增量 evt 不推进世代（增量不是补拉，哪怕差值很大）', () {
      final lan = _newClient();
      lan.deliverForTest(_syncFrame(10, chatCount: 1)); // epoch 1
      for (var seq = 11; seq <= 20; seq++) {
        lan.deliverForTest(_chatEvt(seq, seq, '增量 $seq'));
      }
      expect(lan.client.lastSeq, 20);
      expect(collectChats(lan.client.state).length, 11);
      expect(lan.syncEpoch, 1,
          reason: '★ 世代只由全量 sync 推进，与全局 seq 差值彻底解耦');
    });

    test('★ 服务端再回全量 sync（补拉完成）→ 世代累加 1→2→3', () {
      final lan = _newClient();
      lan.deliverForTest(_syncFrame(10)); // 首连
      expect(lan.syncEpoch, 1);
      lan.deliverForTest(_syncFrame(13, chatCount: 3)); // 自动重连补拉
      expect(lan.syncEpoch, 2);
      lan.deliverForTest(_syncFrame(14, chatCount: 4)); // gap 自愈补拉
      expect(lan.syncEpoch, 3);
      expect(lan.client.state['mark'], 'sync-14');
    });

    test('★ RemoteSession.syncEpoch 恒等于 LanClient.syncEpoch（透出）', () {
      final lan = _newClient();
      final rs = RemoteSession(client: lan, roomCode: 'r2-epoch');
      expect(rs.syncEpoch, 0);
      lan.deliverForTest(_syncFrame(10));
      expect(rs.syncEpoch, lan.syncEpoch);
      expect(rs.syncEpoch, 1);
      lan.deliverForTest(_chatEvt(11, 11, '增量'));
      expect(rs.syncEpoch, lan.syncEpoch);
      expect(rs.syncEpoch, 1);
      lan.deliverForTest(_syncFrame(12));
      expect(rs.syncEpoch, lan.syncEpoch);
      expect(rs.syncEpoch, 2);
    });

    test('★ 世代自增发生在 onChange 通知之前（UI 同一次 build 能读到新值）',
        () {
      final lan = _newClient();
      final seen = <int>[];
      lan.onChange = () => seen.add(lan.syncEpoch);
      lan.deliverForTest(_syncFrame(10));
      expect(seen, isNotEmpty, reason: '前置：_deliver 确实通知了');
      expect(seen.every((int e) => e == 1), isTrue,
          reason: '通知回调里读到的必须是已经 +1 的新世代，不能是旧值');
    });

    test('★ 显式 pullSync() 只是发请求；服务端回全量 sync 才算补拉完成',
        () async {
      final lan = _newClient();
      final rs = RemoteSession(client: lan, roomCode: 'r2-epoch');
      lan.deliverForTest(_syncFrame(10)); // 首连 epoch 1
      await rs.pullSync();
      expect(lan.syncEpoch, 1,
          reason: '发出补拉请求 ≠ 数据已应用，不能提前推进世代');
      expect(rs.syncEpoch, 1);
      lan.deliverForTest(_syncFrame(20, chatCount: 2)); // 服务端回全量
      expect(lan.syncEpoch, 2);
      expect(rs.syncEpoch, 2);
    });

    test('★ gap 自愈分支：requestSync 不推进世代，只有回全量 sync 才 +1', () {
      final lan = _newClient();
      lan.deliverForTest(_syncFrame(10)); // 首连 epoch 1
      // 跳号 evt → RoomClient.gate 报 gap → _deliver 走 resync 分支
      lan.deliverForTest(_chatEvt(15, 15, '跳号的那条'));
      expect(lan.client.gapFrom, greaterThan(0),
          reason: '前置：确实检测到序号缺口');
      expect(lan.queued, greaterThan(0),
          reason: '前置：确实把补拉请求排进了发送队列（不发真包）');
      expect(lan.syncEpoch, 1,
          reason: '★ resync→connected 只是连接态，不等于「全量已应用」');
      lan.deliverForTest(_syncFrame(20)); // 服务端回全量 sync
      expect(lan.syncEpoch, 2);
      expect(lan.client.gapFrom, 0, reason: '全量 sync 会清掉缺口标记');
    });
  });

  // ==========================================================
  // 二、QA 限制 2 回归：短断线漏 1~6 事件，补拉后两列都不闪
  // ==========================================================
  group('Round 2 · 限制 2（短断线补拉误闪）', () {
    for (final miss in const <int>[1, 2, 3, 4, 5, 6]) {
      testWidgets('★ 短断线漏 $miss 个事件，重连补拉后聊天列 + 记录列都不闪',
          (WidgetTester tester) async {
        final f = RoomUiFixture();
        await f.boot();
        useRoomScreen(tester, 400, 1100);

        final lan = _newClient();
        final rs = RemoteSession(client: lan, roomCode: 'r2-epoch');

        // ① 首屏历史：2 条聊天 + 2 条公开骰，全部走真实 intent → 权威端。
        await _chat(f, 'p1', '历史聊天 1');
        await _chat(f, 'p1', '历史聊天 2');
        await _dice(f, 'p1');
        await _dice(f, 'p1');

        // ② 首连全量 sync（服务端 host.syncFor 产出的真实信封）→ 世代 0→1。
        lan.deliverForTest(f.host.syncFor(kHostSeat).toJson());
        expect(lan.syncEpoch, 1);

        await tester.pumpWidget(_remoteHost(f, rs, _twoPanes()));
        await tester.pump();
        expect(find.byKey(GpFeedsKeys.flash(FeedPane.chat)), findsNothing,
            reason: '前置：首屏历史不算新消息');
        expect(find.byKey(GpFeedsKeys.flash(FeedPane.record)), findsNothing);

        // ③ 断线：服务端继续产生 miss 个事件，但客户端**没收到任何增量**。
        //    这正是旧实现的死穴：漏得少 → 全局 seq 差值 ≤ 6 → flood 判据
        //    兜不住；漏得多也一样，因为差值根本不该用来判断补拉。
        for (var i = 0; i < miss; i++) {
          await _chat(f, 'p1', '断线期间漏掉的聊天 $i');
        }

        // ④ 重连补拉：服务端回一份新的全量 sync —— 唯一可靠的「补拉已
        //    发生」信号。session 对象不换（重连时座位不变、client 不重建），
        //    只能靠 syncEpoch +1 让 UI reset。
        lan.deliverForTest(f.host.syncFor(kHostSeat).toJson());
        expect(lan.syncEpoch, 2, reason: '补拉必须推进连接层世代');
        expect(rs.syncEpoch, 2, reason: 'RemoteSession 必须透出该世代');
        await tester.pump();

        expect(find.byKey(GpFeedsKeys.flash(FeedPane.chat)), findsNothing,
            reason: '★★ 漏 $miss 个事件（seq 差小，旧阈值兜不住）；'
                '补拉由 syncEpoch 显式告知，两列都不该闪');
        expect(find.byKey(GpFeedsKeys.flash(FeedPane.record)), findsNothing);
      });
    }

    testWidgets('★ 补拉 reset 后本次 build 重新登记基线，再来一条增量仍闪',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 900);

      final lan = _newClient();
      final rs = RemoteSession(client: lan, roomCode: 'r2-epoch');

      await _chat(f, 'p1', '历史聊天 1');
      await _chat(f, 'p1', '历史聊天 2');
      lan.deliverForTest(f.host.syncFor(kHostSeat).toJson()); // 首连 epoch 1
      await tester.pumpWidget(
        _remoteHost(f, rs, const GpFeeds(pane: FeedPane.chat)),
      );
      await tester.pump();
      expect(find.byKey(GpFeedsKeys.flash(FeedPane.chat)), findsNothing);

      await _chat(f, 'p1', '断线漏 1 条');
      lan.deliverForTest(f.host.syncFor(kHostSeat).toJson()); // 补拉 epoch 2
      await tester.pump();
      expect(find.byKey(GpFeedsKeys.flash(FeedPane.chat)), findsNothing,
          reason: '前置：补拉这批不闪');

      // 关键顺序要点：reset 时必须把 _checkedSeq 清掉，让**本次** build
      // 重新走进 _deriveFlash 登记首屏基线；否则这条增量会被当成「首次」
      // 而漏闪（旧实现里短路会跳过登记）。
      final nextSeq = lan.client.lastSeq + 1;
      final at = _maxChatAt(rs.state) + 1;
      lan.deliverForTest(_chatEvt(nextSeq, at, '补拉之后的新消息'));
      expect(lan.syncEpoch, 2, reason: '增量不推进世代');
      await tester.pump();

      expect(find.byKey(GpFeedsKeys.flash(FeedPane.chat)), findsOneWidget,
          reason: '★★ reset 后基线已重新登记，第一条真增量必须正常闪');
    });
  });

  // ==========================================================
  // 三、QA 限制 3 回归：两列交错（正常在线）chat 该闪
  // ==========================================================
  group('Round 2 · 限制 3（全局 seq 错配漏闪）', () {
    testWidgets('★ 2 历史聊天 → 7 公开骰 → 1 别人新聊天，chat 角标出现',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 1100);

      await _seedHistoryAndPump(
        tester,
        f,
        child: _localHost(f, _twoPanes()),
      );
      final base = _chatSeq(f);
      expect(base, greaterThan(0), reason: '前置：chat 基线已登记');

      // 7 枚公开骰只进 record 列的数据源，但它们把**全局事件序号**推高了；
      // 随后 1 条别人新聊天，chat 列末条 seq 相对基线跳跃 > 6（QA jump=8）。
      for (var i = 0; i < 7; i++) {
        await _dice(f, 'p1');
      }
      expect(collectFeeds(f.stateOf(kHostSeat)).length, greaterThan(0),
          reason: '前置：记录列确实收到了公开骰，交错真实发生');
      await _chat(f, 'p1', '别人新聊天');

      final jump = _chatSeq(f) - base;
      expect(jump, greaterThan(6),
          reason: '前置：必须构造出旧 flood 判据会误杀的大跳跃场景');
      await tester.pump();

      expect(find.byKey(GpFeedsKeys.flash(FeedPane.chat)), findsOneWidget,
          reason: '★★ 判据退役后不再看全局 seq 差值；正常在线交错 chat 必须闪');
    });

    testWidgets('★ 只来记录、不来聊天 → chat 不闪（两列各持 tracker）',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 1100);

      await _seedHistoryAndPump(
        tester,
        f,
        child: _localHost(f, _twoPanes()),
      );
      final base = _chatSeq(f);
      for (var i = 0; i < 7; i++) {
        await _dice(f, 'p1');
      }
      expect(_chatSeq(f), base,
          reason: '前置：chat 展示序末条完全没变');
      await tester.pump();

      expect(find.byKey(GpFeedsKeys.flash(FeedPane.chat)), findsNothing,
          reason: '★ 记录列的变动绝不能带闪聊天列 —— 两列独立 tracker');
    });
  });
}
