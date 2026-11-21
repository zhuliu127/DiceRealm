// ============================================================
// p6_lan_sheets_test.dart — 「局域网自检」与「附近的房间」两个弹层
//
// 两个弹层打开时都会发起真 I/O（HTTP 探测 / UDP 扫描），
// 在 widget 测试的 FakeAsync 下会永远等不到结果 —— 所以都必须注入桩。
//
// ★ 不用 `pumpAndSettle()`：弹层里的 `CircularProgressIndicator` 是无限
//   动画，`pumpAndSettle` 会直接超时。改用定量 `pump(Duration)`。
// ============================================================

import 'dart:async' show Completer;

import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/net/lan_diagnose.dart';
import 'package:dice_realm/net/lan_discovery.dart' show RoomAnnounce;
import 'package:dice_realm/ui/room/sheets/sheet_lan_check.dart'
    show LanCheckKeys, LanCheckSheet, openLanCheckSheet;
import 'package:dice_realm/ui/room/sheets/sheet_nearby_rooms.dart'
    show NearbyKeys, showNearbyRoomsSheet;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

RoomAnnounce _room(
  String code, {
  String name = '',
  int players = 0,
  int maxPlayers = 4,
  String status = 'RECRUITING',
  String kpName = '',
}) => RoomAnnounce(
  code: code,
  base: 'http://192.168.1.7:4211',
  name: name,
  players: players,
  maxPlayers: maxPlayers,
  status: status,
  kpName: kpName,
);

/// 自检弹层要 `RoomScope`（读 `session.lanBase`），所以套着 harness 的宿主。
Widget _scopedApp(RoomUiFixture f, Widget body) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  builder: (BuildContext _, Widget? child) =>
      f.scoped(kHostSeat, child: child ?? const SizedBox.shrink()),
  home: Scaffold(body: SingleChildScrollView(child: body)),
);

/// 让 postFrameCallback + 桩的 Future 都跑完，但**不**等无限动画。
///
/// ★ 必须把 bottom sheet 的进入动画（约 250ms）走完：动画中途按钮还没到
///   最终位置，`tap` 的坐标会落到遮罩上 —— 表现为「静默 miss」
///   （只有一条 `warnIfMissed` 提示，断言却是另一回事，很难查）。
Future<void> _settleIo(WidgetTester tester) async {
  await tester.pump(); // 首帧：触发 postFrameCallback
  await tester.pump(const Duration(milliseconds: 50)); // 桩的 Future 完成
  await tester.pump(const Duration(milliseconds: 400)); // 弹层进入/退出动画
  await tester.pump(); // setState 后重建
}

void main() {
  group('局域网自检弹层', () {
    testWidgets('★ 探测中先显示「正在探测…」，不直接甩一个空结论', (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);

      // 桩故意不完成，卡在探测中。
      final pend = Completer<LanDiagResult>();
      await tester.pumpWidget(
        _scopedApp(f, LanCheckSheet(diagnose: (String _) => pend.future)),
      );
      await tester.pump();

      expect(find.byKey(LanCheckKeys.loading), findsOneWidget);
      expect(find.byKey(LanCheckKeys.verdict), findsNothing,
          reason: '还没结果时不该有结论块');

      // 收尾，避免 pending Future 泄漏到下一个用例。
      pend.complete(
        const LanDiagResult(verdict: LanVerdict.lanDown, steps: <LanDiagStep>[]),
      );
      await tester.pump();
    });

    testWidgets('★ 局域网正常 → 结论、步骤、网卡、建议四块齐全', (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);

      await tester.pumpWidget(
        _scopedApp(
          f,
          LanCheckSheet(
            diagnose: (String base) async => const LanDiagResult(
              verdict: LanVerdict.lanOk,
              base: 'http://192.168.1.7:4211',
              loopBase: 'http://127.0.0.1:4211',
              steps: <LanDiagStep>[
                LanDiagStep(name: '局域网服务', ok: true, text: 'http://192.168.1.7:4211'),
                LanDiagStep(name: '局域网地址', ok: true, text: '正常 · 3ms · 房号 AB12CD'),
                LanDiagStep(name: '回环地址', ok: true, text: '正常 · 1ms'),
              ],
              ifaces: <LanIface>[
                LanIface(name: 'wlan0', address: '192.168.1.7', score: 100, chosen: true),
                LanIface(name: 'tun0', address: '198.18.0.1', score: 0, chosen: false),
              ],
            ),
          ),
        ),
      );
      await _settleIo(tester);

      expect(find.byKey(LanCheckKeys.loading), findsNothing);
      expect(find.byKey(LanCheckKeys.verdict), findsOneWidget);
      expect(find.textContaining('局域网正常'), findsOneWidget);
      expect(find.byKey(LanCheckKeys.step(0)), findsOneWidget);
      expect(find.byKey(LanCheckKeys.ifaces), findsOneWidget);
      expect(find.byKey(LanCheckKeys.advice), findsOneWidget);
    });

    testWidgets('★ 网卡清单要标出「VPN 虚拟网卡不可用」——这是最难自查的问题',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);

      await tester.pumpWidget(
        _scopedApp(
          f,
          LanCheckSheet(
            diagnose: (String _) async => const LanDiagResult(
              verdict: LanVerdict.lanBlocked,
              steps: <LanDiagStep>[
                LanDiagStep(name: '局域网地址', ok: false, text: '连接超时'),
                LanDiagStep(name: '回环地址', ok: true, text: '正常 · 1ms'),
              ],
              ifaces: <LanIface>[
                LanIface(name: 'wlan0', address: '192.168.1.7', score: 100, chosen: false),
                LanIface(name: 'tun0', address: '198.18.0.1', score: 0, chosen: true),
              ],
            ),
          ),
        ),
      );
      await _settleIo(tester);

      expect(find.byKey(LanCheckKeys.iface('198.18.0.1')), findsOneWidget);
      expect(find.textContaining('VPN 虚拟网卡'), findsWidgets,
          reason: '选中了 TUN 网卡必须明说，否则用户永远查不出来');
      // 结论要指向「AP 隔离 / 防火墙 / 网卡」这类可行动方向
      expect(find.textContaining('AP 隔离'), findsWidgets);
    });

    testWidgets('★ 没起服务 → 直接告诉用户「去建房」，不是「连接失败」',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);

      await tester.pumpWidget(
        _scopedApp(
          f,
          LanCheckSheet(
            diagnose: (String _) async => const LanDiagResult(
              verdict: LanVerdict.lanDown,
              steps: <LanDiagStep>[
                LanDiagStep(name: '局域网服务', ok: false, text: '未启动'),
              ],
            ),
          ),
        ),
      );
      await _settleIo(tester);

      expect(find.textContaining('还没开局域网服务'), findsOneWidget);
      expect(find.textContaining('建房'), findsWidgets,
          reason: '处置必须能指导下一步动作');
    });

    testWidgets('★ 「重新探测」会再跑一次（改完网络设置后能复检）',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);

      var calls = 0;
      await tester.pumpWidget(
        _scopedApp(
          f,
          LanCheckSheet(
            diagnose: (String _) async {
              calls++;
              return const LanDiagResult(
                verdict: LanVerdict.lanOk,
                steps: <LanDiagStep>[
                  LanDiagStep(name: '局域网服务', ok: true, text: 'ok'),
                ],
              );
            },
          ),
        ),
      );
      await _settleIo(tester);
      expect(calls, 1);

      await tester.ensureVisible(find.byKey(LanCheckKeys.rerun));
      await tester.pump();
      await tester.tap(find.byKey(LanCheckKeys.rerun));
      await _settleIo(tester);
      expect(calls, 2, reason: '点重跑必须真的再探一次');
    });

    testWidgets('诊断函数抛异常也不能把弹层打崩', (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);

      await tester.pumpWidget(
        _scopedApp(
          f,
          LanCheckSheet(diagnose: (String _) async => throw StateError('boom')),
        ),
      );
      await _settleIo(tester);

      // 崩了也要给出结论块（降级成一条失败步骤），而不是白屏
      expect(find.byKey(LanCheckKeys.verdict), findsOneWidget);
      expect(find.textContaining('自检异常'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('从头（真实入口）打开也能拿到作用域 —— 弹层套在 Navigator 之上',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);

      // 与生产一致：`openLanCheckSheet` 走 showRoomSheet，
      // 而 showRoomSheet 依赖 `RoomScope` 已在树上（room_sheet 会把 scope 重新提供）。
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          builder: (BuildContext _, Widget? child) =>
              f.scoped(kHostSeat, child: child ?? const SizedBox.shrink()),
          home: Scaffold(
            body: Builder(
              builder: (BuildContext ctx) => TextButton(
                onPressed: () => openLanCheckSheet(
                  ctx,
                  diagnose: (String _) async => const LanDiagResult(
                    verdict: LanVerdict.lanDown,
                    steps: <LanDiagStep>[
                      LanDiagStep(name: '局域网服务', ok: false, text: '未启动'),
                    ],
                  ),
                ),
                child: const Text('打开自检'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开自检'));
      await _settleIo(tester);

      expect(find.byKey(LanCheckKeys.root), findsOneWidget,
          reason: '★ 弹层取不到 RoomScope 会直接抛异常（T04 踩过）');
      expect(tester.takeException(), isNull);
    });
  });

  group('附近的房间弹层', () {
    testWidgets('★ 扫到房间 → 列出房号、房名、人数；点「加入」返回该房',
        (WidgetTester tester) async {
      // ★ 必须放大视口：默认 800×600 下 bottom sheet 里的按钮会落到屏幕外，
      //   tap 会「miss」（只有 warnIfMissed 警告，断言却莫名失败）。
      useRoomScreen(tester, 900, 1600);
      RoomAnnounce? picked;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: Builder(
              builder: (BuildContext ctx) => TextButton(
                onPressed: () async {
                  picked = await showNearbyRoomsSheet(
                    ctx,
                    scan: (Duration _) async => <RoomAnnounce>[
                      _room('AB12CD',
                          name: '洋馆惊魂', players: 2, kpName: '老张'),
                      _room('ZZ99YY',
                          name: '雪山密室', players: 1, status: 'IN_GAME'),
                    ],
                  );
                },
                child: const Text('打开附近'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开附近'));
      await _settleIo(tester);

      expect(find.byKey(NearbyKeys.root), findsOneWidget);
      expect(find.byKey(NearbyKeys.row('AB12CD')), findsOneWidget);
      expect(find.byKey(NearbyKeys.row('ZZ99YY')), findsOneWidget);
      expect(find.text('洋馆惊魂'), findsOneWidget);
      expect(find.textContaining('招募中'), findsOneWidget);
      expect(find.textContaining('进行中'), findsOneWidget,
          reason: '进行中的房也要如实标状态，别让用户以为能从头开始');
      expect(find.textContaining('玩家 2/4'), findsOneWidget);

      await tester.ensureVisible(find.byKey(NearbyKeys.join('ZZ99YY')));
      await tester.pump();
      await tester.tap(find.byKey(NearbyKeys.join('ZZ99YY')));
      await _settleIo(tester);

      expect(picked?.code, 'ZZ99YY', reason: '点哪行的加入就该返回哪间房');
      expect(picked?.base, 'http://192.168.1.7:4211');
    });

    testWidgets('★ 一个都没扫到 → 给排查清单，不是干巴巴「无结果」',
        (WidgetTester tester) async {
      useRoomScreen(tester, 900, 1600);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: Builder(
              builder: (BuildContext ctx) => TextButton(
                onPressed: () => showNearbyRoomsSheet(
                  ctx,
                  scan: (Duration _) async => const <RoomAnnounce>[],
                ),
                child: const Text('打开附近'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开附近'));
      await _settleIo(tester);

      expect(find.byKey(NearbyKeys.empty), findsOneWidget);
      // 空态要能指导动作：三个常见原因 + 手输兜底
      expect(find.textContaining('同一个 WiFi'), findsOneWidget);
      expect(find.textContaining('AP 隔离'), findsOneWidget);
      expect(find.textContaining('手输'), findsOneWidget);
    });

    testWidgets('扫描抛异常 → 退化成空态，不崩', (WidgetTester tester) async {
      useRoomScreen(tester, 900, 1600);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: Builder(
              builder: (BuildContext ctx) => TextButton(
                onPressed: () => showNearbyRoomsSheet(
                  ctx,
                  scan: (Duration _) async => throw StateError('udp boom'),
                ),
                child: const Text('打开附近'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开附近'));
      await _settleIo(tester);

      expect(find.byKey(NearbyKeys.empty), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('「重新搜寻」会再扫一次', (WidgetTester tester) async {
      useRoomScreen(tester, 900, 1600);
      var scans = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: Builder(
              builder: (BuildContext ctx) => TextButton(
                onPressed: () => showNearbyRoomsSheet(
                  ctx,
                  scan: (Duration _) async {
                    scans++;
                    return <RoomAnnounce>[_room('AB12CD')];
                  },
                ),
                child: const Text('打开附近'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开附近'));
      await _settleIo(tester);
      expect(scans, 1);

      await tester.ensureVisible(find.byKey(NearbyKeys.rerun));
      await tester.pump();
      await tester.tap(find.byKey(NearbyKeys.rerun));
      await _settleIo(tester);
      expect(scans, 2);
    });
  });
}
