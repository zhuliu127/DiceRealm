import 'dart:async' show Timer;

// ============================================================
// room_notice_overlay_test.dart — 提示浮层
//
// 这个文件存在的理由：`local.notice` 曾经**从来没有被渲染过**。
// 十多个用例断言它的值，逻辑全对，但用户一个字也看不到 ——
// 其中「旧存档含历史明文记录，已自动脱敏 N 条」是 K4 的安全告知。
//
// 所以这里特意分两层：
//   · 组件级：浮层本身怎么显示、怎么消失、会不会吃掉点击；
//   · **集成级：走真实入口建房进大厅 → 点复制 → 提示真的出现在屏幕上**。
//     只有这一条能证明「挂载对了」——组件级测试无法发现「忘了挂」。
//
// ★ 反向验证（做完测试后手工确认过一次）：把 `_RoomShell` 里的
//   `RoomNoticeOverlay()` 从 Stack 摘掉，集成那条必须变红，
//   组件级仍然绿 —— 说明两条测试各自守的是不同的事。
// ============================================================

import 'package:dice_realm/app.dart' show DiceRealmApp;
import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/repo/repo_scope.dart' show AppRoutes;
import 'package:dice_realm/ui/room/room_entry_page.dart' show RoomEntryKeys;
import 'package:dice_realm/ui/room/room_lobby_page.dart' show RoomLobbyKeys;
import 'package:dice_realm/ui/room/room_net_factory.dart' show RoomNetFactory;
import 'package:dice_realm/ui/room/widgets/room_notice_overlay.dart'
    show RoomNoticeKeys, RoomNoticeOverlay;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

/// 组件级宿主：RoomScope + 一个 button（用于验「浮层不吃点击」）。
Widget _host(RoomUiFixture f, {required Widget child}) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  builder: (BuildContext _, Widget? c) =>
      f.scoped(kHostSeat, child: c ?? const SizedBox.shrink()),
  home: Scaffold(body: child),
);

Future<void> _pushNamed(WidgetTester tester, String name) async {
  final ctx = tester.element(find.byType(Scaffold).first);
  Navigator.of(ctx).pushNamed(name);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('提示浮层（组件级）', () {
    testWidgets('★ 没有提示时整块不渲染（不占位、不挡东西）', (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      await tester.pumpWidget(_host(f, child: const RoomNoticeOverlay()));
      await tester.pump();

      expect(find.byKey(RoomNoticeKeys.root), findsNothing);
      expect(find.byKey(RoomNoticeKeys.text), findsNothing);
    });

    testWidgets('★ showNotice → 文本真的上屏（这是之前缺的那一环）', (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      await tester.pumpWidget(_host(f, child: const RoomNoticeOverlay()));
      await tester.pump();

      f.localOf(kHostSeat).showNotice('操作失败：端口被占用');
      await tester.pump();

      expect(find.byKey(RoomNoticeKeys.text), findsOneWidget,
          reason: '★ 这一条就是当年缺的：值写进去了，但没人画出来');
      expect(find.text('操作失败：端口被占用'), findsOneWidget);
    });

    testWidgets('★ ttl 到了自动消失（默认 2 秒，PRD 的「居中 2 秒」）',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      // ★ harness 的 boot() 把 scheduleDismiss 换成了 `(_, _) => null`
      //   （测试不想被定时器干扰），所以「2 秒自消」这条生产行为
      //   在别的用例里从来没被验过。这里显式换回真 Timer。
      f.localOf(kHostSeat).scheduleDismiss = (Duration d, void Function() fn) =>
          Timer(d, fn);

      await tester.pumpWidget(_host(f, child: const RoomNoticeOverlay()));
      await tester.pump();

      f.localOf(kHostSeat).showNotice('已复制加入信息');
      await tester.pump();
      expect(find.byKey(RoomNoticeKeys.text), findsOneWidget);

      // 2 秒内还在
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.byKey(RoomNoticeKeys.text), findsOneWidget,
          reason: '没到 2 秒不该提前消失');

      // 超过 2 秒自动消失
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.byKey(RoomNoticeKeys.text), findsNothing,
          reason: '★ 提示不消失会一直盖在屏幕中央');
    });

    testWidgets('★ 浮层不吃点击（IgnorePointer）—— 否则页面按钮全废',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      var taps = 0;
      await tester.pumpWidget(
        _host(
          f,
          child: Stack(
            children: <Widget>[
              Center(
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('下面的按钮'),
                ),
              ),
              const RoomNoticeOverlay(),
            ],
          ),
        ),
      );
      await tester.pump();

      // 提示正好盖在按钮上方（居中）
      f.localOf(kHostSeat).showNotice('一条很长的提示，正正地压在按钮上面');
      await tester.pump();
      expect(find.byKey(RoomNoticeKeys.text), findsOneWidget);

      await tester.tap(find.text('下面的按钮'), warnIfMissed: false);
      await tester.pump();
      expect(taps, 1, reason: '★ 浮层必须让点击穿透，否则等于半屏禁用');
    });

    testWidgets('新提示覆盖旧提示（不堆叠、不残留）', (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      await tester.pumpWidget(_host(f, child: const RoomNoticeOverlay()));
      await tester.pump();

      f.localOf(kHostSeat).showNotice('第一条');
      await tester.pump();
      expect(find.text('第一条'), findsOneWidget);

      f.localOf(kHostSeat).showNotice('第二条');
      await tester.pump();
      expect(find.text('第二条'), findsOneWidget);
      expect(find.text('第一条'), findsNothing,
          reason: '同时只显示一条（旧版 optoast 的堆叠是同屏多条，我们这里不做）');
    });

    testWidgets('超长文本最多 3 行并省略（不该吃掉半屏）', (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      await tester.pumpWidget(_host(f, child: const RoomNoticeOverlay()));
      await tester.pump();

      f.localOf(kHostSeat).showNotice('很长的提示' * 60);
      await tester.pump();

      final t = tester.widget<Text>(find.byKey(RoomNoticeKeys.text));
      expect(t.maxLines, 3);
      expect(t.overflow, TextOverflow.ellipsis);
    });
  });

  group('提示浮层（集成级 · 走真实入口）', () {
    setUp(() {
      // 与 entry_test 同一套隔离：测试里不能真起网络/真扫 UDP。
      RoomNetFactory.discoveryEnabled = false;
      RoomNetFactory.networkEnabled = false;
      RoomNetFactory.servicePortOverride = 0;
    });

    tearDown(() {
      RoomNetFactory.servicePortOverride = null;
      RoomNetFactory.networkEnabled = true;
      RoomNetFactory.discoveryEnabled = true;
    });

    testWidgets('★★ 建房进大厅 → 点「复制加入信息」→ 提示真的出现在屏幕上',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 1400);

      await tester.pumpWidget(
        DiceRealmApp(repo: f.repo, settings: f.settings, share: f.share),
      );
      await tester.pump();
      await _pushNamed(tester, AppRoutes.room);

      // 建房（进大厅）
      await tester.enterText(find.byKey(RoomEntryKeys.createName), '提示测试团');
      await tester.enterText(find.byKey(RoomEntryKeys.createNick), '老K');
      await tester.pump();
      await tester.tap(find.byKey(RoomEntryKeys.createSubmit));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 前提：已经在大厅里（否则下面找按钮会失败得莫名其妙）
      expect(find.byKey(RoomLobbyKeys.copyJoin), findsOneWidget,
          reason: '前提：建房后应进大厅');

      await tester.ensureVisible(find.byKey(RoomLobbyKeys.copyJoin));
      await tester.pump();
      await tester.tap(find.byKey(RoomLobbyKeys.copyJoin));
      await tester.pump();

      // ★ 这一条才是真正守住缺陷的：值写进去 + 真的画在屏幕上
      expect(find.byKey(RoomNoticeKeys.text), findsOneWidget,
          reason: '★★ 浮层必须挂在 _RoomShell 里 —— 只断言 local.notice 有值'
              '是发现不了「忘了挂」的（缺陷就是这么藏了很久）');
      expect(find.text('已复制加入信息'), findsOneWidget);
    });
  });
}
