// ============================================================
// test/p10_t1_room_exit_save_test.dart — P10 第 1 期 B3 / B4 / C1 / C2
//
// 覆盖：
//   B3 结团 / 解散房间：判定纯函数穷举 + **真实入口页 → 房间 → 点两次 → 回到入口页**
//   B4 踢人：被踢者判定为 kicked（而不是"房主关房"）；座位清理 / 换座可回 / 主动离开可回原座
//   C1 手动保存：把当前游戏中状态写回**同一张**已保存卡（不新建重复卡）
//   C2 回合推进自动保存：同一回合只写一次；非游戏期 / 没绑卡 / 旁观者都不写
//
// 铁律：
//   · 全内存后端（MemoryStorage / InMemoryRoomSaveStore），零真实文件 I/O；
//   · 零 Timer / Future.delayed（只 await 真实 Future 与 tester.pump）；
//   · 房间网络开关关掉（`RoomNetFactory.networkEnabled=false`），否则 fake-async
//     推不动真实 socket。
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart' show recalc;
import 'package:dice_realm/domain/js_compat.dart' show asMap, asList;
import 'package:dice_realm/domain/room_types.dart'
    show RoomRole, RoomStatus, kHostSeat;
import 'package:dice_realm/repo/character_repo.dart';
import 'package:dice_realm/repo/repo_scope.dart';
import 'package:dice_realm/repo/room_notes_store.dart' show MemoryNotesStorage, RoomNotesStore;
import 'package:dice_realm/repo/room_state_writer.dart'
    show CharacterRepoRoomCardSink;
import 'package:dice_realm/theme.dart' show Palette;
import 'package:dice_realm/ui/room/room_boot.dart' show roomSaveSlots;
import 'package:dice_realm/ui/room/room_card_saver.dart'
    show RoomCardSaver, roomCardPatchOf;
import 'package:dice_realm/ui/room/room_controller.dart' show RoomController;
import 'package:dice_realm/ui/room/room_entry_page.dart' show RoomEntryKeys, RoomEntryPage;
import 'package:dice_realm/ui/room/room_exit.dart' show RoomExitKind, roomExitOf;
import 'package:dice_realm/ui/room/room_keys.dart' show RoomKeys;
import 'package:dice_realm/ui/room/room_lobby_page.dart' show RoomLobbyPage;
import 'package:dice_realm/ui/room/room_net_factory.dart' show RoomNetFactory;
import 'package:dice_realm/ui/room/room_scope.dart' show RoomScope;
import 'package:dice_realm/ui/room/room_ui_local.dart' show RoomUiLocal;
import 'package:dice_realm/ui/room/widgets/gp_pl_char_card.dart'
    show GpPlCharCard, GpPlCharCardKeys;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';
import 'support/room_ui_harness.dart';

void _resetPalette() => Palette.useBrightness(Brightness.dark);

/// 造一张带 id 的卡（与 p8 / p10 其它用例同一套最小字段）。
Character _card(String id, String name, {num hp = 12}) {
  final c = Character(newCharacter());
  c.raw['id'] = id;
  c.raw['characterName'] = name;
  c.basicInfo['age'] = 30;
  c.raw['age'] = 30;
  for (final String k in <String>[
    'str',
    'con',
    'siz',
    'dex',
    'app',
    'int',
    'pow',
    'edu',
    'luck',
  ]) {
    c.attributes[k] = 50;
  }
  recalc(c);
  c.status['currentHP'] = hp;
  return c;
}

/// 造一个「带角色卡仓库」的控制器（生产装配同款：cardSink → repo.save）。
RoomController _controllerWithRepo(
  RoomUiFixture f,
  String seat,
  CharacterRepo repo,
) =>
    RoomController(
      session: f.sessionOf(seat),
      local: f.localOf(seat),
      notes: RoomNotesStore(MemoryNotesStorage()),
      cardSink: CharacterRepoRoomCardSink(repo),
    );

/// 从权威态里取某座位的成员行。
Map<String, Object?> _member(RoomUiFixture f, String seat) => asList(
      f.host.state['members'],
    ).map(asMap).firstWhere((Map<String, Object?> m) => m['seat'] == seat);

void main() {
  setUp(_resetPalette);
  tearDown(_resetPalette);

  // ---------------------------------------------------------
  // B3/B4 判定函数：把「该不该离开、为什么离开」穷举
  // ---------------------------------------------------------
  group('B3/B4 roomExitOf 判定', () {
    Map<String, Object?> roomState(String status, {bool ended = false}) =>
        <String, Object?>{
          'meta': <String, Object?>{
            'status': status,
            if (ended) 'ended': true,
          },
          'members': <Object?>[
            <String, Object?>{'seat': 'p1', 'role': RoomRole.player},
            <String, Object?>{'seat': 'p2', 'role': RoomRole.player},
          ],
        };

    test('还在招募 / 游戏中 → 不离开', () {
      expect(
        roomExitOf(
          state: roomState(RoomStatus.recruiting),
          seat: 'p1',
          role: RoomRole.player,
        ).kind,
        RoomExitKind.none,
      );
      expect(
        roomExitOf(
          state: roomState(RoomStatus.inGame),
          seat: 'p1',
          role: RoomRole.player,
        ).kind,
        RoomExitKind.none,
      );
    });

    test('结团（meta.ended）→ ended，且文案说清楚', () {
      final e = roomExitOf(
        state: roomState(RoomStatus.closed, ended: true),
        seat: 'p1',
        role: RoomRole.player,
      );
      expect(e.kind, RoomExitKind.ended);
      expect(e.shouldLeave, isTrue);
      expect(e.message, contains('结团'));
    });

    test('关房：人还在成员表 → closed（不是被踢）', () {
      final e = roomExitOf(
        state: roomState(RoomStatus.closed),
        seat: 'p1',
        role: RoomRole.player,
      );
      expect(e.kind, RoomExitKind.closed);
      expect(e.message, contains('结束房间'));
    });

    test('收到过 KICK（硬信号）→ kicked，即使旧成员表里还留着自己', () {
      // ★ 真实情形：被踢者**收不到**那条 members 广播（plan() 按花名册算收件人
      //   时他已经被移除了），所以他手里的成员表还是旧的、仍含自己。
      //   判据只能是"收到过 kick 信封"。
      final Map<String, Object?> s = roomState(RoomStatus.closed);
      final e = roomExitOf(
        state: s,
        seat: 'p1',
        role: RoomRole.player,
        kickedByHost: true,
      );
      expect(e.kind, RoomExitKind.kicked);
      expect(e.message, contains('移出房间'));
      // 反证：没有 kick 信号时，同样的状态必须判成"房主关房"
      expect(
        roomExitOf(state: s, seat: 'p1', role: RoomRole.player).kind,
        RoomExitKind.closed,
      );
    });

    test('KP 自己关房不能被判成"被踢"（房主恒不在成员表里）', () {
      final e = roomExitOf(
        state: roomState(RoomStatus.closed),
        seat: kHostSeat,
        role: RoomRole.kp,
      );
      expect(e.kind, RoomExitKind.closed);
    });

    test('挂起（SUSPENDED）不算离开：房间还能复活', () {
      expect(
        roomExitOf(
          state: roomState(RoomStatus.suspended),
          seat: 'p1',
          role: RoomRole.player,
        ).kind,
        RoomExitKind.none,
      );
    });

    test('还没收到第一份同步（空态）→ 不离开', () {
      expect(
        roomExitOf(
          state: const <String, Object?>{},
          seat: 'p1',
          role: RoomRole.player,
        ).kind,
        RoomExitKind.none,
      );
    });
  });

  // ---------------------------------------------------------
  // B3 端到端：KP 点两次「结团」→ 本机立刻离开房间
  // ---------------------------------------------------------
  group('B3 结团 / 结束房间后本机离开', () {
    setUp(() {
      roomSaveSlots.clear();
      RoomNetFactoryTestSwitch.off();
    });
    tearDown(RoomNetFactoryTestSwitch.restore);

    Future<void> enterRoom(WidgetTester tester) async {
      await pumpApp(
        tester,
        home: RoomEntryPage(saveStore: roomSaveSlots),
      );
      // 大厅是一长列区块；给一个足够高的视口，让「房间管理」的两个按钮
      // 稳稳落在视口内（否则 tap 会落在视口外 → 点了没反应）。
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pump();
      await tester.tap(find.byKey(RoomEntryKeys.createSubmit));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RoomLobbyPage), findsOneWidget,
          reason: '创建后应进入大厅（招募期）');
      // 两个危险按钮必须真的在视口里（tap 命中测试的前提）
      await tester.ensureVisible(find.byKey(RoomKeys.action('room.end')));
      await tester.pump();
    }

    testWidgets('「结团」连点两次 → 回到入口页，并留下原因说明', (WidgetTester tester) async {
      await enterRoom(tester);

      // ★ K-03：第一次只改文案，不发包
      await tester.tap(find.byKey(RoomKeys.action('room.end')));
      await tester.pump();
      expect(find.text('再点一次确认'), findsOneWidget,
          reason: '第一次点击必须只进入确认态');
      expect(find.byType(RoomLobbyPage), findsOneWidget);

      // 第二次才真发
      await tester.tap(find.byKey(RoomKeys.action('room.end')));
      await tester.pumpAndSettle();

      expect(find.byType(RoomLobbyPage), findsNothing,
          reason: 'B3：结团后本机必须离开房间（旧版原地不动 = 「点了没反应」）');
      expect(find.byType(RoomEntryPage), findsOneWidget);
      expect(find.byKey(RoomEntryKeys.notice), findsOneWidget,
          reason: '回到入口页要说明为什么退出');
      final String notice = tester
              .widget<Text>(find.byKey(RoomEntryKeys.notice))
              .data ??
          '';
      expect(notice, contains('结团'));
    });

    testWidgets('「结束房间」连点两次 → 同样回到入口页', (WidgetTester tester) async {
      await enterRoom(tester);
      await tester.tap(find.byKey(RoomKeys.action('room.close')));
      await tester.pump();
      await tester.tap(find.byKey(RoomKeys.action('room.close')));
      await tester.pumpAndSettle();

      expect(find.byType(RoomLobbyPage), findsNothing);
      expect(find.byType(RoomEntryPage), findsOneWidget);
      expect(find.byKey(RoomEntryKeys.notice), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(RoomEntryKeys.notice)).data ?? '',
        contains('结束房间'),
      );
    });
  });

  // ---------------------------------------------------------
  // B4 踢人之后：座位清干净 → 被踢者能换座回来；主动离开能回原座
  // ---------------------------------------------------------
  group('B4 踢人 / 离开 / 重新加入', () {
    test('踢人：座位从花名册移除、该座永久拒入，但换座可以回来', () async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(players: 2, spectators: 0);

      // KP 踢 p1（真实 action）
      await f.kpSession.hostAction('room.kick', <String, Object?>{'seat': 'p1'});
      final Map<String, Object?> st = f.host.state;
      final List<String> seats = <String>[
        for (final m in asList(st['members'])) asMap(m)['seat'] as String,
      ];
      expect(seats, isNot(contains('p1')), reason: 'B4：踢出后花名册必须清干净');
      expect(f.host.roster.kicked, contains('p1'),
          reason: '被踢的座位要被记住（否则「踢了立刻又回来」）');

      // ① 原座：被拒（这是「踢得掉」的前提）
      expect(
        f.host.attachPeer(<String, Object?>{
          'seat': 'p1',
          'role': RoomRole.player,
          'nickname': '被踢的人',
        }).blocked,
        isTrue,
        reason: 'B4：被踢的座位不能立刻重新占回来',
      );

      // ② 换座：允许（用户要求「不能永久卡死」）
      final added = f.host.attachPeer(<String, Object?>{
        'seat': 'p2',
        'role': RoomRole.player,
        'nickname': '被踢的人',
      });
      expect(added.rejected, isFalse, reason: 'B4：换个座位必须能回到房间');
      expect(added.seat, 'p2');
    });

    test('主动离开 = 只标离线：同一座位能重新加入（原座）', () async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(players: 2, spectators: 0);
      // 主动离开（生产里是 socket 断开 → bye → detachPeer）
      f.host.detachPeer('p1');
      expect(
        _member(f, 'p1')['online'],
        isFalse,
        reason: 'B4：掉线 / 主动离开只标离线，不删成员',
      );
      // 再回来：原座可用，且没有进 kicked
      expect(f.host.roster.kicked, isNot(contains('p1')),
          reason: 'B4：主动离开不该把人拉进黑名单（那才会「再也加不回来」）');
      final added = f.host.attachPeer(<String, Object?>{
        'seat': 'p1',
        'role': RoomRole.player,
        'nickname': '回来了',
      });
      expect(added.rejected, isFalse);
      expect(added.seat, 'p1');
      expect(_member(f, 'p1')['online'], isTrue);
    });

    test('被踢者的房间状态：CLOSED + 不在名单 → 判定 kicked（B4 客户端行动依据）', () async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(players: 2, spectators: 0);
      await f.kpSession.hostAction('room.kick', <String, Object?>{'seat': 'p1'});

      final Map<String, Object?> p1 = f.stateOf('p1');
      expect(
        asMap(p1['meta'])['status'],
        RoomStatus.closed,
        reason: 'KICK 事件在 reduce 里把 status 置 CLOSED（旧客户端把它当终止）',
      );
      expect(f.sessionOf('p1').kickedByHost, isTrue,
          reason: 'B4：被踢者必须收到"只发给他"的 kick 信封（这才是判据）');
      final e = roomExitOf(
        state: p1,
        seat: 'p1',
        role: RoomRole.player,
        kickedByHost: f.sessionOf('p1').kickedByHost,
      );
      expect(e.kind, RoomExitKind.kicked,
          reason: 'B4：被踢者必须自己离开房间（不能停在原地）');
    });
  });

  // ---------------------------------------------------------
  // C1 手动保存：覆盖同一张卡，不新建
  // ---------------------------------------------------------
  group('C1 游戏内手动保存', () {
    test('把当前状态写回同一张卡（不新建重复卡）', () async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true, players: 1, spectators: 0);

      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('c_p1', '沈墨白', hp: 12));

      // 房间里玩家已经掉了 5 点血
      await f.kpSession.hostAction('sheet.damage', <String, Object?>{
        'seat': 'p1',
        'amount': 5,
        'reason': '测试伤害',
      });
      final Map<String, Object?> sheet = asMap(_member(f, 'p1')['sheet']);
      final num inRoom = asMap(sheet['status'])['currentHP'] as num;
      expect(inRoom, lessThan(12), reason: '前提：房间里的 HP 已经掉了');

      final RoomCardSaver saver = RoomCardSaver(
        controller: _controllerWithRepo(f, 'p1', repo),
        session: f.sessionOf('p1'),
      );
      final outcome = await saver.saveNow();
      expect(outcome.ok, isTrue, reason: '保存失败：${outcome.message}');
      expect(saver.manualSaved, 1);

      // ① 覆盖同一张：id 仍是 c_p1，卡数没变
      expect(repo.all.length, 1, reason: 'C1：不许新建重复卡');
      final Character? saved = repo.get('c_p1');
      expect(saved, isNotNull);
      // ② 数值真的落盘了
      expect(saved!.status['currentHP'], inRoom);
      expect(saver.lastError, isEmpty);
    });

    test('没绑定角色卡 → 明确失败（不猜一张卡来写）', () async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true, players: 1, spectators: 0, withSheets: false);
      final CharacterRepo repo = await newMemoryRepo();
      final RoomCardSaver saver = RoomCardSaver(
        controller: _controllerWithRepo(f, 'p1', repo),
        session: f.sessionOf('p1'),
      );
      expect(roomCardPatchOf(f.stateOf('p1'), 'p1'), isNull);
      final outcome = await saver.saveNow();
      expect(outcome.ok, isFalse);
      expect(outcome.message, contains('绑定角色卡'));
      expect(repo.all, isEmpty, reason: 'C1：失败时不许写任何卡');
    });

    testWidgets('角色卡面板里的「保存到已保存」按钮：点了真的落盘', (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true, players: 1, spectators: 0);
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('c_p1', '沈墨白'));

      final RoomController ctl = _controllerWithRepo(f, 'p1', repo);
      final RoomUiLocal local = f.localOf('p1');
      useRoomScreen(tester, 900, 1800);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: RepoScope(
          repo: repo,
          child: Scaffold(
            body: RoomScope(
              session: f.sessionOf('p1'),
              local: local,
              controller: ctl,
              child: const SingleChildScrollView(child: GpPlCharCard()),
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(find.byKey(GpPlCharCardKeys.saveBtn), findsOneWidget,
          reason: 'C1：玩家角色卡面板必须有保存入口');
      await tester.tap(find.byKey(GpPlCharCardKeys.saveBtn));
      await tester.pump();
      await tester.pump();

      expect(find.text('已保存到「已保存的角色卡」'), findsOneWidget,
          reason: 'C1：保存成功要有提示（不弹模态，走 SnackBar）');
      expect(repo.get('c_p1'), isNotNull);
    });

    testWidgets('旁观者不渲染保存入口（结构性不渲染）', (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true, players: 1, spectators: 1);
      useRoomScreen(tester, 900, 1800);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: f.scoped('sp1', child: const SingleChildScrollView(child: GpPlCharCard())),
      ));
      await tester.pump();
      expect(find.byKey(GpPlCharCardKeys.saveBtn), findsNothing,
          reason: 'C1：旁观者没有「我的角色」，不许出现保存按钮');
    });
  });

  // ---------------------------------------------------------
  // C2 回合推进自动保存
  // ---------------------------------------------------------
  group('C2 下一回合自动保存', () {
    test('回合推进后自动写一次；同一回合重复通知不再写', () async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true, players: 1, spectators: 0);
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('c_p1', '沈墨白', hp: 12));

      final RoomCardSaver saver = RoomCardSaver(
        controller: _controllerWithRepo(f, 'p1', repo),
        session: f.sessionOf('p1'),
      );

      // KP 推进到下一回合（真实 action：`round.next`）
      await f.kpSession.hostAction('round.next');
      await saver.onStateChanged();
      expect(saver.autoSaved, 1, reason: 'C2：回合推进后应自动保存一次');

      // 同一回合里再来几次通知（任何 state 变化都会触发）→ 不许重复写盘
      await saver.onStateChanged();
      await saver.onStateChanged();
      expect(saver.autoSaved, 1, reason: 'C2：同一回合只写一次，不能乱循环');
    });

    test('新回合再推进一次 → 再写一次', () async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true, players: 1, spectators: 0);
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('c_p1', '沈墨白'));

      final RoomCardSaver saver = RoomCardSaver(
        controller: _controllerWithRepo(f, 'p1', repo),
        session: f.sessionOf('p1'),
      );

      await f.kpSession.hostAction('round.next');
      await saver.onStateChanged();
      expect(saver.autoSaved, 1);

      await f.kpSession.hostAction('round.next');
      await saver.onStateChanged();
      expect(saver.autoSaved, 2, reason: 'C2：下一个回合应该再存一次');
    });

    test('招募期（还没开团）不写盘', () async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(players: 1, spectators: 0);
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('c_p1', '沈墨白'));
      final RoomCardSaver saver = RoomCardSaver(
        controller: _controllerWithRepo(f, 'p1', repo),
        session: f.sessionOf('p1'),
      );
      await saver.onStateChanged();
      expect(saver.autoSaved, 0, reason: 'C2：招募期没有回合，不该动玩家的卡');
    });

    test('KP / 旁观者不自动保存（没有可写的卡）', () async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true, players: 1, spectators: 1);
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('c_p1', '沈墨白'));

      final RoomCardSaver kpSaver = RoomCardSaver(
        controller: _controllerWithRepo(f, kHostSeat, repo),
        session: f.sessionOf(kHostSeat),
      );
      final RoomCardSaver spSaver = RoomCardSaver(
        controller: _controllerWithRepo(f, 'sp1', repo),
        session: f.sessionOf('sp1'),
      );
      await f.kpSession.hostAction('round.next');
      await kpSaver.onStateChanged();
      await spSaver.onStateChanged();
      expect(kpSaver.autoSaved, 0);
      expect(spSaver.autoSaved, 0);
    });
  });
}

/// 房间网络开关的用例级托管（避免每个用例重复写四行）。
class RoomNetFactoryTestSwitch {
  const RoomNetFactoryTestSwitch._();

  static void off() {
    RoomNetFactory.discoveryEnabled = false;
    RoomNetFactory.networkEnabled = false;
    RoomNetFactory.servicePortOverride = 0;
  }

  static void restore() {
    RoomNetFactory.servicePortOverride = null;
    RoomNetFactory.networkEnabled = true;
    RoomNetFactory.discoveryEnabled = true;
  }
}
