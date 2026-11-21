// ============================================================
// test/room_ui_confirm_flow_test.dart — T-64：confirm=kp 的端到端闭环
//
// P4 只验了 domain 侧「state.edit.self 入 pending 队列」；
// 本文件补 P5 的 UI 侧全链路：
//   玩家提交 → 入队（权威态**不变**）→ KP 在面板点「确认」→ 数值**真生效**
//
// 这是 Q-P5-3 文案「需 KP 同意后生效」的唯一证伪点：
// 文案说「需同意」，若同意后不生效，就又是一次「UI 骗人」（K7）。
// 反过来，若未同意就生效，confirm=kp 形同虚设。
//
// 铁律：全内存后端、零真实 I/O、不用 pumpAndSettle 等节流（弹层动画除外）。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap;
import 'package:dice_realm/domain/room_types.dart' show RoomConfirm, kHostSeat;
import 'package:dice_realm/ui/room/room_request_watcher.dart'
    show RoomPushKeys, RoomRequestWatcher;
import 'package:dice_realm/ui/room/sheets/sheet_kp_panel.dart'
    show KpPanel, KpPanelKeys, showKpPanel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

/// 作用域挂在 Navigator 之上，页面与弹层都能 `RoomScope.of`。
Widget appFor(RoomUiFixture f, String seat, Widget body) {
  return MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    builder: (BuildContext _, Widget? child) =>
        f.scoped(seat, child: child ?? const SizedBox.shrink()),
    home: body,
  );
}

/// 权威态里某座位的当前 HP（读 `sheet.status.currentHP`，与 P4 同口径）。
num hpOf(RoomUiFixture f, String seat) {
  final Map<String, Object?> me = asList(f.host.state['members'])
      .map(asMap)
      .firstWhere((Map<String, Object?> m) => m['seat'] == seat);
  final Map<String, Object?> st = asMap(asMap(me['sheet'])['status']);
  final Object? v = st['currentHP'];
  return v is num ? v : -1;
}

/// 强行打开 KP 工具弹层（不依赖骨架里的入口按钮，才能单独测这一块）。
Future<void> openKpPanelAs(WidgetTester tester, RoomUiFixture f, String seat) async {
  await tester.pumpWidget(appFor(
    f,
    seat,
    Builder(
      builder: (BuildContext ctx) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => showKpPanel(ctx),
            child: const Text('打开KP'),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.tap(find.text('打开KP'));
  await tester.pumpAndSettle();
}

/// 待确认行上的「确认」/「取消」按钮（key = `kpPanel/confirm|cancel/<op>`）。
///
/// ★ P10 第 6 期收尾起这两个 key 已随「待处理」区块一起撤掉，
///   常量保留在测试里用于**反向断言**（弹层里必须 findsNothing）。
Key confirmKey(String op) => ValueKey<String>('kpPanel/confirm/$op');
Key cancelKey(String op) => ValueKey<String>('kpPanel/cancel/$op');

/// 挂上「KP 工具弹层 + 页面级推送监听」的宿主。
///
/// ★ 为什么不再用「点弹层里的确认行」：P10 第 6 期收尾按用户要求
///   「推送消息弹窗后，kp工具箱里面的就不要有了」把弹层里的「待处理」
///   区块整块撤了，确认/取消改由居中弹窗承载。所以本文件改为：
///   先挂 `RoomRequestWatcher`（首帧把已有请求记为已读），
///   再触发新请求 → 弹窗 → 点弹窗里的同意/拒绝。
///   **行为保证一条没削弱**：未同意前权威态不变、同意后真生效、
///   拒绝后不变、待办被消费。只是入口从弹层换成了弹窗。
Future<void> mountKpWithWatcher(
  WidgetTester tester,
  RoomUiFixture f,
  String seat,
) async {
  await tester.pumpWidget(appFor(
    f,
    seat,
    const Scaffold(body: RoomRequestWatcher(child: KpPanel())),
  ));
  await tester.pump();
}

void main() {
  group('T-64 confirm=kp 的端到端闭环（state.edit.self）', () {
    testWidgets('玩家提交 HP=7 → 入队且不生效 → KP 弹窗点「同意」→ 权威态真变 7',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 2200);

      final num before = hpOf(f, 'p1');
      expect(before, isNot(7), reason: '前提：初始 HP 不能已经是 7，否则测不出变化');

      // ③（前置）KP 侧先把「弹层 + 推送监听」挂上 —— 首帧会把已有请求记为
      //   已读，所以必须在提交**之前**挂载，新请求才会弹窗。
      await mountKpWithWatcher(tester, f, kHostSeat);

      // ① 玩家提交（与 sheet_self_state._submitNumbers 同 payload：**不带 seat**，
      //    座位由权威端从发起者身份推导 —— 这正是 UI 与 domain 的契约）。
      f.controllerOf('p1').hostAction('state.edit.self', <String, Object?>{
        'status': <String, Object?>{'currentHP': 7},
      });

      // ② 入队，且此刻权威态**不变**（confirm=kp 的全部意义就在这一步）
      expect(f.host.pending.length, 1, reason: 'confirm=kp 必须入待确认队列');
      expect(asMap(f.host.pending.single)['need'], RoomConfirm.kp,
          reason: 'need 必须是 kp');
      expect(hpOf(f, 'p1'), before, reason: '未同意前不该生效');

      // ③ 新口径：KP 弹层里**不再**有「待处理」区块（用户明确要求撤销）
      expect(find.text('待处理'), findsNothing,
          reason: '推送弹窗后 KP 工具箱里不该再列一遍待处理');
      expect(find.byKey(KpPanelKeys.pendingList), findsNothing);
      expect(find.byKey(confirmKey('state.edit.self')), findsNothing);
      expect(find.byKey(KpPanelKeys.unread), findsNothing);
      // 其余工具区块仍在（没有连带删掉别的东西）
      expect(find.text('工具 · 回合与检定'), findsOneWidget);
      expect(find.text('工具 · 房间管理'), findsOneWidget);

      // ④ 居中弹窗承载确认：标题可读、同意按钮在
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(RoomPushKeys.root), findsOneWidget,
          reason: 'KP 必须收到屏幕正中的推送弹窗（这是唯一确认入口）');
      expect(find.byKey(RoomPushKeys.agree), findsOneWidget);

      // ⑤ 点「同意」
      await tester.tap(find.byKey(RoomPushKeys.agree));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // ⑥ 数值**真生效** + 待办被消费
      expect(hpOf(f, 'p1'), 7,
          reason: 'KP 同意后权威端应真的应用 status —— '
              '文案写着「需 KP 同意后生效」，不同意不生效、同意也不生效就是双重骗人');
      expect(f.host.pending, isEmpty, reason: '待办应被消费，不能残留');
      expect(find.byKey(RoomPushKeys.root), findsNothing,
          reason: '处理后弹窗应关闭');
    });

    testWidgets('KP 弹窗点「拒绝」→ 数值不变，待办同样被消费',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 2200);

      final num before = hpOf(f, 'p2');
      await mountKpWithWatcher(tester, f, kHostSeat);
      f.controllerOf('p2').hostAction('state.edit.self', <String, Object?>{
        'status': <String, Object?>{'currentHP': 3},
      });
      expect(f.host.pending.length, 1);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(RoomPushKeys.root), findsOneWidget);
      // 弹层里已无取消按钮（新口径）；拒绝走弹窗
      expect(find.byKey(cancelKey('state.edit.self')), findsNothing);

      await tester.tap(find.byKey(RoomPushKeys.reject));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(hpOf(f, 'p2'), before, reason: 'KP 拒绝后数值不该变');
      expect(f.host.pending, isEmpty, reason: '拒绝也要消费待办（否则待办越积越多）');
    });

    testWidgets('旁观者打开同一弹层：看不到队列，也消费不了待办',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 2200);

      f.controllerOf('p1').hostAction('state.edit.self', <String, Object?>{
        'status': <String, Object?>{'currentHP': 7},
      });
      expect(f.host.pending.length, 1);

      // 旁观视角强行打开同一个 KP 工具弹层
      await openKpPanelAs(tester, f, 'sp1');

      // ★ 口径更新：旧断言「看不到待确认行」保留，另补「整块都不许有」。
      expect(find.text('待处理'), findsNothing,
          reason: '旁观者打开 KP 工具弹层也不该看到待处理区块');
      expect(find.byKey(KpPanelKeys.pendingList), findsNothing);
      expect(find.byKey(confirmKey('state.edit.self')), findsNothing,
          reason: '旁观者的 hostRead 为 null ⇒ 队列恒空，不该看到确认入口');
      expect(find.byKey(cancelKey('state.edit.self')), findsNothing,
          reason: '旁观者也不该看到「取消」按钮');
      // 点不到 ⇒ 消费不了：权威端的待办仍在，等真正的 KP 处理
      expect(f.host.pending.length, 1,
          reason: '旁观者不该能消费 KP 的待办');
    });
  });
}
