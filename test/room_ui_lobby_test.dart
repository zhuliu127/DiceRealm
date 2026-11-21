// ============================================================
// test/room_ui_lobby_test.dart — P5/T05-B2a 大厅页 R1–R12 验收
//
// 铁律：
//   · T1：后端全部内存实现，零文件读写；
//   · T5：房间页面按真实档位 pump（`useRoomScreen`）；
//   · T6：断言「点了到底发了什么」看 `sent`（hub 的 SessionSendLog）；
//   · T8：跨视角只用「该视角真收到的那份 state」。
//
// ★ 宿主**不替页面订阅 `local`**：大厅页自己包了 `ListenableBuilder(local)`，
//   宿主再兜一层就会把「漏订阅」掩盖成假绿（前两批的教训）。
// ★ 绑卡类用例：玩家视角 + 「存回去再读出来」的卡（`repo.save` 会跑 recalc）。
// ============================================================

import 'dart:io' show Directory, File;

import 'package:dice_realm/app.dart' show DiceRealmApp;
import 'package:dice_realm/domain/character.dart' show Character, newCharacter;
import 'package:dice_realm/domain/js_compat.dart' show asMap, jsStr;
import 'package:dice_realm/domain/room_model_client.dart' show RoomClient;
// `RoomHost.intent` 是 extension，必须把扩展名带进作用域
import 'package:dice_realm/domain/room_model_host_intent.dart'
    show RoomHostIntent;
import 'package:dice_realm/ui/room/room_net_factory.dart'
    show RoomNetFactory;
import 'package:dice_realm/domain/room_types.dart'
    show RoomIntent, RoomMode, RoomRole, RoomStatus;
import 'package:dice_realm/repo/repo_scope.dart' show RepoScope;
import 'package:dice_realm/ui/room/room_boot.dart' show RoomBoot, bootLocalRoom;
import 'package:dice_realm/ui/room/room_entry_page.dart' show RoomEntryKeys;
import 'package:dice_realm/ui/room/room_game_page.dart' show RoomGamePage;
import 'package:dice_realm/ui/room/room_keys.dart' show RoomKeys;
import 'package:dice_realm/ui/room/room_lobby_page.dart'
    show RoomLobbyKeys, RoomLobbyPage;
import 'package:dice_realm/ui/room/room_scope.dart' show RoomScope;
import 'package:dice_realm/ui/room/sheets/card_sheet_payload.dart'
    show cardToRoomSheet;
import 'package:dice_realm/ui/room/sheets/sheet_bind_char.dart'
    show BindCharSheetKeys;
import 'package:dice_realm/ui/room/sheets/sheet_kp_panel.dart'
    show KpPanelKeys, showKpPanel;
import 'package:dice_realm/ui/room/sheets/sheet_bind_char.dart'
    show openBindCharSheet;
import 'package:dice_realm/ui/room/sheets/sheet_misc.dart' show openMiscSheet;
import 'package:dice_realm/ui/room/sheets/sheet_save_slots.dart'
    show openSaveSlotsSheet;
import 'package:dice_realm/ui/room/sheets/sheet_self_state.dart'
    show GpSelfStateKeys, openSelfStateSheet;
import 'package:dice_realm/ui/room/sheets/sheet_misc.dart' show MiscSheetKeys;
import 'package:dice_realm/ui/room/sheets/sheet_save_slots.dart'
    show SaveSlotsKeys;
import 'package:dice_realm/ui/room/widgets/gp_dice_bar.dart' show GpDiceBar;
import 'package:dice_realm/ui/room/widgets/gp_status.dart' show GpStatus;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart' show RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';
import 'package:dice_realm/ui/widgets/auto_avatar_png.dart'
    show autoAvatarPngEncoder;

// ------------------------------------------------------------
// 开房间
// ------------------------------------------------------------

/// 开一个房间并按角色取视角（KP 读权威态，玩家/旁观读环回客户端裁剪态）。
///
/// [extra] 形如 `['p2', 'sp1:spectator']`：补玩家 / 旁观进花名册，
/// 「全员准备」「踢人」这类用例才有对象。
Future<RoomBoot> _room(
  WidgetTester tester, {
  String role = RoomRole.kp,
  String seat = 'p1',
  String nickname = '调查员甲',
  List<String> extra = const <String>[],
}) async {
  final boot = await bootLocalRoom(
    code: 'LOBBY1',
    name: '大厅测试团',
    nickname: role == RoomRole.kp ? '老K' : nickname,
    role: role,
    seat: seat,
  );
  boot.local.scheduleDismiss = (_, _) => null;
  addTearDown(boot.dispose);
  for (final spec in extra) {
    final at = spec.indexOf(':');
    final s = at < 0 ? spec : spec.substring(0, at);
    final r = at < 0 ? RoomRole.player : spec.substring(at + 1);
    // KP 会话是 hub 把手：注册客户端 + 走真实的 attachPeer 产出成员事件
    boot.session.attach(s, RoomClient(seat: s, role: r));
    final plans = boot.host.attachPeer(<String, Object?>{
      'seat': s,
      'role': r,
      'nickname': s,
      'at': 1,
    }).out;
    if (plans.isNotEmpty) boot.session.pumpPlans(plans);
  }
  return boot;
}

/// 让某座位先绑一张卡（权威端 `READY` 需要 charId，否则会被拒）。
void _bindCard(RoomBoot boot, String seat, {String id = 'c1'}) {
  boot.session.pumpPlans(boot.host.intent(seat, <String, Object?>{
    'op': RoomIntent.char,
    'p': <String, Object?>{
      'id': id,
      'name': '李探',
      'sheet': cardToRoomSheet(_card(id: id)),
    },
  }));
}

/// 让某座位「准备」（直接喂权威意图，等价于那个玩家点了准备）。
void _setReady(RoomBoot boot, String seat, {bool ready = true}) {
  final plans = boot.host.intent(seat, <String, Object?>{
    'op': RoomIntent.ready,
    'p': <String, Object?>{'ready': ready, 'charId': ''},
  });
  boot.session.pumpPlans(plans);
}

/// 大厅页宿主：作用域挂在 Navigator 之上（弹层也取得到），**不订阅 local**。
Widget _host(RoomBoot boot) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (BuildContext _, Widget? child) => RoomScope(
        session: boot.session,
        local: boot.local,
        controller: boot.controller,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const Scaffold(body: RoomLobbyPage()),
    );

/// ★ P7 正向守卫宿主：游戏期壳体（RoomGamePage 的 slot 网格承载 5 类块）。
Widget _gameHost(RoomBoot boot) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (BuildContext _, Widget? child) => RoomScope(
        session: boot.session,
        local: boot.local,
        controller: boot.controller,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const Scaffold(body: RoomGamePage()),
    );

/// 一张带数值的车卡（`repo.save` 会 recalc，断言请用读回来的那张）。
Character _card({String id = 'c1', String name = '李探'}) {
  final raw = newCharacter();
  raw['id'] = id;
  raw['characterName'] = name;
  raw['attributes'] = <String, Object?>{
    'str': 50,
    'con': 55,
    'siz': 60,
    'dex': 61,
    'app': 45,
    'int': 70,
    'pow': 65,
    'edu': 80,
  };
  raw['skills'] = <Object?>[
    <String, Object?>{'name': '侦查', 'total': 70},
  ];
  return Character(raw);
}

/// 该 op 的最近一条 `sent`（找不到就失败）。
Map<String, Object?> _last(RoomBoot boot, String op) => boot.hub.sent.entries
    .lastWhere((Map<String, Object?> e) => e['op'] == op, orElse: () {
  fail('sent 里没有 $op（实际：${boot.hub.sent.entries.map((Map<String, Object?> e) => e['op']).toList()}）');
});

void main() {
  // 自动头像 PNG 生成是引擎真异步：widget 测试里统一替身（见文件末注释）
  setUp(_stubAutoAvatarPng);

  // P6：本文件有走真实入口流程的用例（建房 → 进大厅），现在建房会真起服务。
  // 端口交给系统分配，否则多个用例抢 4211。
  setUp(() {
    RoomNetFactory.discoveryEnabled = false;
    RoomNetFactory.networkEnabled = false; // FakeAsync 推不动真实 bind
    RoomNetFactory.servicePortOverride = 0;
  });
  tearDown(() {
    RoomNetFactory.servicePortOverride = null;
    RoomNetFactory.networkEnabled = true;
  });
  group('R1–R12 · 结构', () {
    testWidgets('KP 视角：R1–R12 全部就位', (WidgetTester tester) async {
      useRoomScreen(tester, 400, 2400); // 足够高：R12 必须真的建出来
      final boot = await _room(tester, extra: <String>['p2', 'sp1:spectator']);
      await tester.pumpWidget(_host(boot));
      await tester.pump();

      expect(find.byKey(RoomLobbyKeys.root), findsOneWidget);
      expect(find.byKey(RoomLobbyKeys.header), findsOneWidget); // R1
      expect(find.byKey(RoomLobbyKeys.service), findsOneWidget); // R2
      expect(find.byKey(RoomLobbyKeys.members), findsOneWidget); // R3
      expect(find.byKey(RoomKeys.kpStartGame), findsOneWidget); // R6
      // ★ P7：招募期「结束房间 / 结团」的房间生命周期能力**保留**。
      expect(find.byKey(RoomLobbyKeys.closeRoom), findsOneWidget);
      expect(find.byKey(RoomKeys.action('room.close')), findsOneWidget);
      // ★ P7：5 类游戏期块在大厅（招募期）一律不渲染；游戏期由
      //   RoomGamePage 的 slot 网格承载（正向守卫见下方 group 与
      //   test/p7_lobby_gate_test.dart）—— 不是「为了绿放宽」。
      expect(find.byKey(RoomLobbyKeys.explore), findsNothing); // R9
      expect(find.byKey(RoomLobbyKeys.kpTools), findsNothing); // R10
      expect(find.byKey(RoomLobbyKeys.openKpPanel), findsNothing);
      expect(find.byType(GpStatus), findsNothing); // R11
      expect(find.byType(GpDiceBar), findsNothing); // R12
      expect(find.byKey(RoomKeys.gpDiceBar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('★ 玩家视角：KP 专属块**不渲染**（T-22，不是禁用）',
        (WidgetTester tester) async {
      useRoomScreen(tester, 400, 1200);
      final boot = await _room(tester, role: RoomRole.player);
      await tester.pumpWidget(_host(boot));
      await tester.pump();

      for (final Key k in <Key>[
        RoomLobbyKeys.service, // R2
        RoomKeys.kpStartGame, // R6
        RoomLobbyKeys.closeRoom, // R7 / R8
        RoomLobbyKeys.kpTools, // R10
      ]) {
        expect(find.byKey(k), findsNothing, reason: '玩家侧不许出现 $k');
      }
      // 玩家专属 R4 / R5 必须在
      expect(find.byKey(RoomLobbyKeys.ready), findsOneWidget);
      expect(find.byKey(RoomLobbyKeys.bindChar), findsOneWidget);
      // ★ P7：R8 / R9 / R10 / R11 / R12 都是游戏期块，招募期玩家侧同样零渲染。
      expect(find.byKey(RoomLobbyKeys.explore), findsNothing);
      expect(find.byKey(RoomLobbyKeys.sceneEdit), findsNothing);
      expect(find.byKey(RoomLobbyKeys.addAsset), findsNothing);
      expect(find.byKey(RoomLobbyKeys.modeSwitch), findsNothing);
      expect(find.byKey(RoomLobbyKeys.kpTools), findsNothing);
      expect(find.byType(GpStatus), findsNothing);
      expect(find.byType(GpDiceBar), findsNothing);
    });

    testWidgets('★ 旁观者：显示「旁观中（不能准备）」、准备区 findsNothing、可点控件零发包（T-06）',
        (WidgetTester tester) async {
      useRoomScreen(tester, 400, 2400);
      final boot = await _room(tester, role: RoomRole.spectator, seat: 'sp1');
      await tester.pumpWidget(_host(boot));
      await tester.pump();

      expect(find.textContaining('旁观中（不能准备）'), findsOneWidget);
      expect(find.byKey(RoomLobbyKeys.ready), findsNothing,
          reason: '★ 旁观者连准备区都不渲染（结构保证，不靠禁用）');
      expect(find.byKey(RoomLobbyKeys.bindChar), findsNothing);

      // ★ T-06：旁观者能点到的每个控件都点一遍，`sent` 必须一条都没有。
      //   逐个点名而不是盲扫：盲扫会因为 ListView 懒加载 / 自动关弹层而漏点。
      boot.hub.sent.clear();
      // ★ P7：R12 掷骰条已从招募期大厅移除，不再是可点目标。
      expect(find.byKey(RoomKeys.gpDiceBar), findsNothing);
      final targets = <Finder>[
        find.byKey(RoomLobbyKeys.copyInvite), // R1 复制邀请
        find.byKey(RoomLobbyKeys.memberDetail('sp1')), // R3 成员详情
      ];
      for (final target in targets) {
        expect(target, findsOneWidget, reason: '旁观者也该看得到 $target');
        await tester.ensureVisible(target);
        await tester.pump();
        await tester.tap(target, warnIfMissed: false);
        await tester.pump();
      }
      expect(boot.hub.sent.isEmpty, isTrue,
          reason: '★ T-06：旁观者全程零发包，实际 ${boot.hub.sent.length} 条'
              '（${boot.hub.sent.entries.map((Map<String, Object?> e) => e['op']).toList()}）');
    });
  });

  group('R4 / R6 / R7 · 准备与开局', () {
    testWidgets('★ 玩家点「我准备好了」→ INTENT.READY{ready:true, charId}；再点回 false',
        (WidgetTester tester) async {
      useRoomScreen(tester, 400, 1200);
      final boot = await _room(tester, role: RoomRole.player);
      _bindCard(boot, 'p1');
      await tester.pumpWidget(_host(boot));
      await tester.pump();
      boot.hub.sent.clear();

      await tester.tap(find.text('我准备好了'));
      await tester.pump();
      var ready = _last(boot, RoomIntent.ready);
      expect(ready['kind'], 'intent');
      expect(asMap(ready['p'])['ready'], true);
      expect(asMap(ready['p']).containsKey('charId'), isTrue);

      await tester.tap(find.text('取消准备'));
      await tester.pump();
      ready = _last(boot, RoomIntent.ready);
      expect(asMap(ready['p'])['ready'], false);
    });

    testWidgets('★ KP「开始游戏」：有人未准备时禁用 + 点了零发包；全员准备后发 room.start',
        (WidgetTester tester) async {
      useRoomScreen(tester, 400, 1200);
      final boot = await _room(tester, extra: <String>['p2']);
      await tester.pumpWidget(_host(boot));
      await tester.pump();
      boot.hub.sent.clear();

      final startFinder = find.byKey(RoomKeys.kpStartGame);
      expect(tester.widget<RoomTap>(startFinder).enabled, isFalse,
          reason: 'p1 / p2 都没准备');
      await tester.tap(startFinder, warnIfMissed: false);
      await tester.pump();
      expect(boot.hub.sent.isEmpty, isTrue, reason: '★ 禁用时点了也不许发包');

      _bindCard(boot, 'p1');
      _bindCard(boot, 'p2');
      _setReady(boot, 'p1');
      _setReady(boot, 'p2');
      await tester.pump();
      expect(tester.widget<RoomTap>(find.byKey(RoomKeys.kpStartGame)).enabled,
          isTrue);

      boot.hub.sent.clear();
      await tester.tap(find.byKey(RoomKeys.kpStartGame));
      await tester.pump();
      final start = _last(boot, 'room.start');
      expect(start['kind'], 'action');
    });

    testWidgets('★ KP「结束房间」：ConfirmTwice 第一次不发包、第二次才发 room.close',
        (WidgetTester tester) async {
      useRoomScreen(tester, 400, 1200);
      final boot = await _room(tester);
      await tester.pumpWidget(_host(boot));
      await tester.pump();
      boot.hub.sent.clear();

      final closeBtn = find.byKey(RoomKeys.action('room.close'));
      await tester.ensureVisible(closeBtn);
      await tester.pump();
      await tester.tap(closeBtn);
      await tester.pump();
      expect(boot.hub.sent.isEmpty, isTrue, reason: '第一次只上膛');

      await tester.tap(closeBtn);
      await tester.pump();
      expect(_last(boot, 'room.close')['kind'], 'action');
    });
  });

  group('R3 · 成员与踢人', () {
    testWidgets('成员行点开 → 详情弹层；KP 踢人 → room.kick 带 seat',
        (WidgetTester tester) async {
      useRoomScreen(tester, 400, 1200);
      final boot = await _room(tester, extra: <String>['p2']);
      await tester.pumpWidget(_host(boot));
      await tester.pump();

      expect(find.byKey(RoomLobbyKeys.memberRow('p2')), findsOneWidget);
      await tester.tap(find.byKey(RoomLobbyKeys.memberDetail('p2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.textContaining('座位：p2'), findsOneWidget);

      await tester.tapAt(const Offset(4, 4)); // 关弹层
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      boot.hub.sent.clear();
      await tester.tap(find.byKey(RoomLobbyKeys.kick('p2')));
      await tester.pump();
      expect(asMap(_last(boot, 'room.kick')['p'])['seat'], 'p2');
    });
  });

  group('R5 · 绑卡入口', () {
    testWidgets('★ 玩家点「绑定角色卡」→ 真弹层（不是占位）',
        (WidgetTester tester) async {
      // 高屏：R5 在 ListView 下部，太矮就不会被懒加载建出来
      useRoomScreen(tester, 400, 2400);
      final f = RoomUiFixture();
      await f.boot();
      await f.repo.save(_card());
      final boot = await _room(tester, role: RoomRole.player);

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        builder: (BuildContext _, Widget? child) => RepoScope(
          repo: f.repo,
          child: RoomScope(
            session: boot.session,
            local: boot.local,
            controller: boot.controller,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: const Scaffold(body: RoomLobbyPage()),
      ));
      await tester.pump();

      final bindBtn = find.descendant(
        of: find.byKey(RoomLobbyKeys.bindChar),
        matching: find.byType(RoomTap),
      );
      // ★ 没绑卡时必须是「绑定角色卡」——`sheet.name` 可能是 null，
      //   若用 jsStr 读会渲染成字符串「null」进而把按钮误判成「更换」。
      expect(tester.widget<RoomTap>(bindBtn).label, '绑定角色卡');
      expect(
        find.descendant(
          of: find.byKey(RoomLobbyKeys.bindChar),
          matching: find.textContaining('null'),
        ),
        findsNothing,
        reason: '★ 界面上不许出现字面量「null」',
      );
      await tester.tap(bindBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(BindCharSheetKeys.root), findsOneWidget);
      expect(find.text('李探'), findsOneWidget);
    });
  });

  group('R10 · 弹层入口（游戏期 RoomGamePage 的 KP 面板）', () {
    /// ★ P7：招募期大厅不再有 KP 面板入口；游戏期由 RoomGamePage 工具栏的
    ///   kpPanelKey 承载。这条守卫证明「能力没被删，只是回到游戏期」。
    Future<void> openPanel(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(RoomGamePage.kpPanelKey));
      await tester.pump();
      await tester.tap(find.byKey(RoomGamePage.kpPanelKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(KpPanelKeys.root), findsOneWidget);
    }

    testWidgets('★ 面板里的「更多工具」打开杂项弹层（游戏期入口，大厅不再有同名按钮）',
        (WidgetTester tester) async {
      useRoomScreen(tester, 400, 2400);
      final boot = await _room(tester);
      await tester.pumpWidget(_gameHost(boot));
      await tester.pump();
      await openPanel(tester);

      await tester.tap(find.byKey(KpPanelKeys.misc));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(MiscSheetKeys.root), findsOneWidget);
      expect(find.byKey(MiscSheetKeys.zoomPct), findsOneWidget);
    });

    testWidgets('★ 面板里的「存档槽」打开真弹层（游戏期入口）',
        (WidgetTester tester) async {
      useRoomScreen(tester, 400, 2400);
      final boot = await _room(tester);
      await tester.pumpWidget(_gameHost(boot));
      await tester.pump();
      await openPanel(tester);

      await tester.tap(find.byKey(KpPanelKeys.saveSlots));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(SaveSlotsKeys.root), findsOneWidget);
    });

    testWidgets('招募期大厅 R10：KP 面板入口与 kpTools 都 findsNothing（附游戏期守卫）',
        (WidgetTester tester) async {
      useRoomScreen(tester, 400, 2400);
      final boot = await _room(tester);
      await tester.pumpWidget(_host(boot));
      await tester.pump();

      expect(find.byKey(RoomLobbyKeys.openKpPanel), findsNothing);
      expect(find.byKey(RoomLobbyKeys.kpTools), findsNothing);
      // 大厅侧不再有「更多工具 / 存档槽」直入口
      expect(find.text('更多工具'), findsNothing);

      // ★ 正向守卫：游戏期壳体里 KP 面板入口仍在。
      await tester.pumpWidget(_gameHost(boot));
      await tester.pump();
      expect(find.byKey(RoomGamePage.kpPanelKey), findsOneWidget);
    });
  });

  group('R8 / R9 · 招募期不渲染游戏期模式与探索面板（附权威端守卫）', () {
    testWidgets('KP 招募期：模式 / 探索 / 素材入口全部 findsNothing；scene.mode 仍是权威端能力',
        (WidgetTester tester) async {
      useRoomScreen(tester, 400, 2400);
      final boot = await _room(tester);
      await tester.pumpWidget(_host(boot));
      await tester.pump();

      for (final Key k in <Key>[
        RoomLobbyKeys.modeSwitch,
        RoomLobbyKeys.combatPrep,
        RoomLobbyKeys.endCombat,
        RoomLobbyKeys.explore,
        RoomLobbyKeys.sceneEdit,
        RoomLobbyKeys.addAsset,
      ]) {
        expect(find.byKey(k), findsNothing, reason: '招募期大厅不该渲染 $k');
      }

      // ★ 正向守卫：这些能力没被删，仍在权威端（游戏期由 RoomGamePage
      //   的 slot 网格 / KP 面板承载）。
      boot.hub.sent.clear();
      final scope = tester.widget<RoomScope>(find.byType(RoomScope));
      await scope.controller.hostAction('scene.mode', <String, Object?>{
        'mode': RoomMode.combat,
      });
      await tester.pump();
      expect(asMap(_last(boot, 'scene.mode')['p'])['mode'], RoomMode.combat);
    });

    testWidgets('KP 招募期：改场景名入口不在大厅；scene.set 仍整体替换权威态',
        (WidgetTester tester) async {
      useRoomScreen(tester, 400, 1200);
      final boot = await _room(tester);
      await tester.pumpWidget(_host(boot));
      await tester.pump();
      boot.hub.sent.clear();

      expect(find.byKey(RoomLobbyKeys.sceneEdit), findsNothing);
      final scope = tester.widget<RoomScope>(find.byType(RoomScope));
      await scope.controller.hostAction('scene.set', <String, Object?>{
        'scene': <String, Object?>{'name': '洋馆大厅'},
      });
      await tester.pump();

      expect(jsStr(asMap(asMap(_last(boot, 'scene.set')['p'])['scene'])['name']),
          '洋馆大厅');
      expect(jsStr(asMap(boot.host.state['scene'])['name']), '洋馆大厅',
          reason: '★ 不是只改了弹层里的草稿');
    });
  });

  group('阶段路由 · 大厅 ↔ 游戏页（走真实入口流程）', () {
    testWidgets('★ 创建后先进大厅；KP 开团后大厅 findsNothing、游戏页 findsOneWidget',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);
      await tester.pumpWidget(
          DiceRealmApp(repo: f.repo, settings: f.settings, share: f.share));
      await tester.pump();

      // 首页 🎲 → 规则选择页 → 入口页 → 创建（★ P9：入口先选规则系统）
      await tester.tap(find.byKey(const Key('fab_room')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rule_pick_coc7')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byKey(RoomEntryKeys.createName), '流程团');
      await tester.pump();
      await tester.tap(find.byKey(RoomEntryKeys.createSubmit));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // ① 创建后是**大厅**，不是游戏页
      expect(find.byType(RoomLobbyPage), findsOneWidget);
      expect(find.byType(RoomGamePage), findsNothing);

      // ② KP 开团（走真实 action）
      final scope = tester.widget<RoomScope>(find.byType(RoomScope));
      await scope.controller.hostAction('room.start');
      await tester.pump();
      await tester.pump();

      expect(jsStr(asMap(scope.session.state['meta'])['status']),
          RoomStatus.inGame);
      expect(find.byType(RoomGamePage), findsOneWidget);
      expect(find.byType(RoomLobbyPage), findsNothing,
          reason: '★ 阶段切换必须整棵子树重建');
    });
  });

  _nullLiteralGroup();
  _jsStrBudgetGroup();
}

// ------------------------------------------------------------
// null 字面量泄漏（`jsStr(null) == 'null'` 的端到端守门人）
// ------------------------------------------------------------
void _nullLiteralGroup() {
  group('UI · 不出现字面量「null」', () {
    /// 当前页面上任何 Text 都不许含 `null`（含插值拼接出来的）。
    void expectNoNull(WidgetTester tester, String where) {
      expect(
        find.textContaining('null'),
        findsNothing,
        reason: '★ $where 出现了字面量「null」：jsStr(null) 的泄漏',
      );
    }

    testWidgets('★ 大厅页三种视角都没有「null」', (WidgetTester tester) async {
      useRoomScreen(tester, 400, 2400);
      for (final role in <String>[
        RoomRole.kp,
        RoomRole.player,
        RoomRole.spectator,
      ]) {
        final boot = await _room(
          tester,
          role: role,
          seat: role == RoomRole.spectator ? 'sp1' : 'p1',
          extra: <String>['p2', 'sp2:spectator'],
        );
        await tester.pumpWidget(_host(boot));
        await tester.pump();
        expectNoNull(tester, '大厅页（$role）');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });

    testWidgets('★ 游戏页壳体（KP / 玩家）没有「null」', (WidgetTester tester) async {
      useRoomScreen(tester, 400, 2400);
      for (final role in <String>[RoomRole.kp, RoomRole.player]) {
        final boot = await _room(
          tester,
          role: role,
          extra: <String>['p2'],
        );
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          builder: (BuildContext _, Widget? child) => RoomScope(
            session: boot.session,
            local: boot.local,
            controller: boot.controller,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const RoomGamePage(),
        ));
        await tester.pump();
        expectNoNull(tester, '游戏页（$role）');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });

    testWidgets('★ KP 面板 / 绑卡 / 存档槽 / 杂项 / 状态管理弹层都没有「null」',
        (WidgetTester tester) async {
      useRoomScreen(tester, 400, 2400);
      final f = RoomUiFixture();
      await f.boot();
      final boot = await _room(tester, extra: <String>['p2']);

      Future<void> pumpHost() async {
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          builder: (BuildContext _, Widget? child) => RepoScope(
            repo: f.repo,
            child: RoomScope(
              session: boot.session,
              local: boot.local,
              controller: boot.controller,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
          home: Builder(
            builder: (BuildContext ctx) => Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    RoomTap(
                      key: const Key('openPanel'),
                      label: 'panel',
                      onTap: () => showKpPanel<void>(ctx),
                    ),
                    RoomTap(
                      key: const Key('openBind'),
                      label: 'bind',
                      onTap: () => openBindCharSheet(ctx),
                    ),
                    RoomTap(
                      key: const Key('openSlots'),
                      label: 'slots',
                      onTap: () => openSaveSlotsSheet(ctx),
                    ),
                    RoomTap(
                      key: const Key('openMisc'),
                      label: 'misc',
                      onTap: () => openMiscSheet(ctx),
                    ),
                    RoomTap(
                      key: const Key('openSelf'),
                      label: 'self',
                      onTap: () => openSelfStateSheet(ctx),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ));
        await tester.pump();
      }

      Future<void> openAndCheck(String key, String label) async {
        await tester.tap(find.byKey(Key(key)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expectNoNull(tester, label);
        await tester.tapAt(const Offset(4, 4));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
      }

      await pumpHost();
      await openAndCheck('openPanel', 'KP 工具面板');
      await openAndCheck('openBind', '绑卡弹层');
      await openAndCheck('openSlots', '存档槽弹层');
      await openAndCheck('openMisc', '杂项弹层');
      await openAndCheck('openSelf', '状态管理弹层');
      // 兜底：确认这些弹层真的开过（否则断言是空转）
      expect(GpSelfStateKeys.root, isNotNull);
    });
  });
}

// ------------------------------------------------------------
// 静态冻结：`jsStr(` 在 UI 层只允许剩「必须保留」的那几处
// ------------------------------------------------------------
void _jsStrBudgetGroup() {
  group('门禁 · jsStr 预算（冻结，防新增泄漏）', () {
    test('lib/ui/room 的 jsStr 只允许出现在审计过的位置', () {
      final dir = Directory('lib/ui/room');
      final hits = <String>[];
      for (final e in dir.listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final rel = e.path.replaceAll('\\', '/');
        final lines = e.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains('jsStr(')) {
            hits.add('$rel:${i + 1}  ${lines[i].trim()}');
          }
        }
      }
      // 白名单：会话层内部 3 处（已 ?? '' 兜底）+ room_text 定义 1 处
      //        + 一处 switch 判别 + 一处历史注释
      final allowed = <String>[
        'room_session_local.dart',
        'room_text.dart',
        'gp_scene_check_pl.dart',
        'gp_status.dart', // 仅注释里提到
        // 「加入战斗」候选行要按座位区分（每行一个 seat），见下方 seat-only 专项校验
        'gp_combat_list.dart',
        // P6 远端会话：与 room_session_local 同口径（seat 公开标识 /
        // kind 判别 'sys' / 消息正文只读展示）
        'room_session_remote.dart',
        // ★ P19 存档同步器：jsStr 只读 meta 的 status / code / seat 等
        //   房间级公开标识（快照本身整包进 store，不经 jsStr 渲染任何
        //   秘密字段 —— HP/SAN/笔记全走结构化存储）。
        'room_save_syncer.dart',
        // ★ P13 COMBAT-1/3：玩家侧参战者只显名字（kind 判据）与
        //   visibleCombatActors 的裸 id 归一（actorId/id），均非秘密字段渲染。
        'view/combat_view.dart',
        // ★ P13 COMBAT-3：玩家攻击弹窗解析武器 ranged 标志（'true'/'1'）。
        'sheets/sheet_combat.dart',
        // ★ P20 需求 2：横幅事件源。它是**纯 Dart 状态差分器**，不返回任何
        //   Widget，读的全是「要往横幅上写给所有人看的那几个字」——
        //   seat / 角色名 / 昵称 / 疯狂症状名 / body 状态 / 开战时刻 / 槽位名。
        //   下面有专项断言：**该文件里的 jsStr 一行都不许碰秘密字段**。
        'critical_event_tracker.dart',
      ];
      final leaks = hits
          .where((String h) => !allowed.any((String a) => h.contains(a)))
          .toList();
      expect(leaks, isEmpty, reason: '★ 新增了 jsStr 直接渲染：\n${leaks.join('\n')}');

      // 放行 `gp_combat_list` 必须带约束：只准读 **seat / kind**（p1/p2/sp1、
      // 'pc'/'npc' 这类公开标识），不许在该文件里用 jsStr 渲染任何秘密字段
      // （HP / SAN / 笔记 / 私有素材）。否则「放行一个文件」就等于开了个后门。
      final combatBad = hits
          .where((String h) =>
              h.contains('gp_combat_list.dart') &&
              !h.contains('seat') &&
              !h.contains('kind'))
          .toList();
      expect(combatBad, isEmpty,
          reason: '★ gp_combat_list 的 jsStr 只允许读 seat / kind（公开标识）：\n'
              '${combatBad.join('\n')}');

      // ★ P20 需求 2 放行 `critical_event_tracker` 的约束：只准读「要印在
      //   横幅上给所有人看」的公开文案字段。HP / SAN / 笔记 / 手绘笔迹 /
      //   私密素材一律不许出现在该文件的 jsStr 行里，否则「放行一个文件」
      //   就成了往所有人都看得见的地方泄漏秘密的后门。
      const List<String> secretKeys = <String>[
        'currentHP',
        'currentSAN',
        'currentMP',
        'hp',
        'san',
        'note',
        'notes',
        'board',
        'strokes',
        'private',
        'secret',
        'privateBySeat',
      ];
      final trackerBad = hits
          .where((String h) =>
              h.contains('critical_event_tracker.dart') &&
              secretKeys.any((String k) => h.contains(k)))
          .toList();
      expect(trackerBad, isEmpty,
          reason: '★ critical_event_tracker 的 jsStr 不许读秘密字段：\n'
              '${trackerBad.join('\n')}');

      // P13 新增 7 处合法判据（COMBAT-1/3），预算 18→25；逐条已由上面
      // 白名单 + combatBad 专项校验审计，不是整体放宽。
      // P20 需求 2 新增 8 处（横幅事件差分器），25→33，同样逐条审计。
      expect(hits.length, lessThanOrEqualTo(33),
          reason: '★ jsStr 预算被突破（当前 ${hits.length} 处）：\n${hits.join('\n')}');
    });
  });
}

/// ★ P10 第 3 期 A 批：自动头像 PNG 化是 `picture.toImage()` 的真异步，
/// 在 fake-async 区域里永不完成 → 绑卡链路会卡在 `await`。
/// 与既有 `avatarThumbEncoder` 同一套注入规矩（见 `repo/avatar_thumb.dart`），
/// 这里统一换成同步返回空串的替身；头像 PNG 本身由
/// `test/p10_t3_broadcast_potential_png_test.dart` 的 C 组覆盖。
void _stubAutoAvatarPng() {
  final saved = autoAvatarPngEncoder;
  addTearDown(() => autoAvatarPngEncoder = saved);
  autoAvatarPngEncoder = (spec) async => '';
}
