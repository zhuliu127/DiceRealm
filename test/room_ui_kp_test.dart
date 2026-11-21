// ============================================================
// test/room_ui_kp_test.dart — P5/T04 KP 专属块与 KP 侧弹层验收
//
// 铁律：T1（全内存后端）、T5（房间页用 useRoomScreen）、T6（断言 sent）、
//      T7（KP 本地态走本机只读面）、T8（跨视角用 stateOf）。
//
// ★ 全部用例**独立 pump Scaffold**，不依赖游戏页：本轮不碰
//   `room_game_page.dart`，接线由后续批次单独派。作用域用
//   `MaterialApp.builder` 把房间作用域挂在 Navigator 之上，
//   于是 `showRoomSheet` 推出的弹层也能取到同一份作用域。
//
// 覆盖（对应派工 7 条验收）：
//   ① 角标公式逐项（三种 pending 各一条 + 组合一条）
//   ② 弹层入口可点性 == gate.can；`room.close`/`session.end` 点两次
//   ③ 定向 9 项目标过滤（后续批次）
//   ④ 未读角标（本批次）
//   ⑤ `scene.check.step` 载荷逐字段（后续批次）
//   ⑥ 机械门禁零命中（后续批次扩展到全部 T04 文件）
//   ⑦ 全量 0 红 + analyze 零 issue
// ============================================================

import 'dart:io' show File;

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/room_types.dart'
    show RoomConfirm, RoomIntent, kHostSeat;
import 'package:dice_realm/ui/room/room_keys.dart';
import 'package:dice_realm/ui/room/room_request_watcher.dart'
    show RoomPushKeys, RoomRequestWatcher;
import 'package:dice_realm/ui/room/room_theme.dart' show kDrawColors;
import 'package:dice_realm/ui/room/sheets/room_sheet.dart' show showRoomSheet;
import 'package:dice_realm/ui/room/sheets/sheet_char_view.dart'
    show CharViewKeys, CharViewSheet;
import 'package:dice_realm/ui/room/sheets/sheet_add_actor.dart'
    show AddActorSheetKeys;
import 'package:dice_realm/ui/room/sheets/sheet_combat.dart'
    show CombatSheet, CombatSheetKeys;
import 'package:dice_realm/ui/room/sheets/sheet_dice_tools.dart'
    show DiceToolsKeys, DiceToolsSheet;
import 'package:dice_realm/ui/room/sheets/sheet_kp_directives.dart'
    show
        KpDirective,
        KpDirectivesSheet,
        kKpConsentOps,
        kKpDirectives,
        kKpExtraDirectives,
        kKpMadBoutExtraOps,
        kpDirectiveBlocksMadBout,
        kpDirectiveNeedsConsent,
        kpDirectivePayload,
        kpDirectiveTargets,
        kpMadBout;
import 'package:dice_realm/ui/room/sheets/sheet_kp_panel.dart';
import 'package:dice_realm/ui/room/sheets/sheet_opposed.dart'
    show OpposedSheet, OpposedSheetKeys;
import 'package:dice_realm/ui/room/sheets/sheet_san_check.dart'
    show SanCheckSheet, SanCheckSheetKeys;
import 'package:dice_realm/ui/room/sheets/sheet_scene.dart'
    show SceneSheet, SceneSheetKeys;
import 'package:dice_realm/ui/room/view/scene_view.dart' show NormPoint;
import 'package:dice_realm/ui/room/widgets/gp_kp_left.dart'
    show GpKpLeft, GpKpLeftKeys;
import 'package:dice_realm/ui/room/widgets/gp_kp_players.dart'
    show GpKpPlayers, GpKpPlayersKeys, kpBoardStrokeCount;
import 'package:dice_realm/ui/room/widgets/gp_kp_tools.dart';
import 'package:dice_realm/ui/room/widgets/gp_scene_check_kp.dart'
    show
        GpSceneCheckKeys,
        GpSceneCheckKp,
        kKpSceneModes,
        sceneCheckStepPayload;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart'
    show MapStageController, RoomSheet, RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

/// 造一个开团中的房间（真实 action 开团，不手改权威态）。
Future<RoomUiFixture> _boot(WidgetTester tester,
    {double w = 800, double h = 900}) async {
  final f = RoomUiFixture();
  await f.boot(inGame: true);
  useRoomScreen(tester, w, h);
  return f;
}

/// 独立宿主：`MaterialApp.builder` 把作用域挂在 Navigator 之上，
/// 弹层（showModalBottomSheet）因此也能 `RoomScope.of`。
Widget _hostApp(
  RoomUiFixture f,
  Widget body, {
  String seat = kHostSeat,
  Key? appKey,
}) {
  return MaterialApp(
    key: appKey,
    theme: ThemeData.dark(useMaterial3: true),
    builder: (BuildContext _, Widget? child) => f.scoped(
      seat,
      child: child ?? const SizedBox.shrink(),
    ),
    home: Scaffold(
      body: SingleChildScrollView(child: body),
    ),
  );
}

/// 滚动到可见再点（块较多时按钮可能落在首屏之外）。
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

/// 舞台控制面替身：只记录调用，不画东西。
class _FakeStage implements MapStageController {
  final List<String> calls = <String>[];

  @override
  void beginStroke({required String color, required double width}) =>
      calls.add('stroke:$color:$width');

  @override
  void beginErase() => calls.add('erase');

  @override
  void beginMark({
    required String kind,
    required String label,
    bool revealed = true,
  }) => calls.add('mark:$kind:$label');

  @override
  void beginPlace({String? actorName, String? playerSeat}) =>
      calls.add('place:${actorName ?? ''}:${playerSeat ?? ''}');

  @override
  void cancel() => calls.add('cancel');

  @override
  bool get awaitingTap => false;
}

Map<String, Object?> _q(String need) => <String, Object?>{
      'by': 'p1',
      'op': 'madness.cure',
      'p': <String, Object?>{},
      'need': need,
      'at': 1,
    };

/// 造一个成员（可精确控制「已撕卡 / 疯狂发作中 / 他人视图」）。
Map<String, Object?> _mem(
  String seat,
  String nick, {
  String body = '正常',
  List<Object?> mental = const <Object?>[],
  int madnessCount = 0,
  bool withMaxSan = true,
}) {
  return <String, Object?>{
    'seat': seat,
    'nickname': nick,
    'role': 'player',
    'sheet': <String, Object?>{
      'status': <String, Object?>{
        'body': body,
        'currentHP': 10,
        'maxHP': 10,
        'currentMP': 5,
        'maxMP': 5,
        'currentSAN': 40,
        if (withMaxSan) 'maxSAN': 60,
        'dying': false,
        'unconscious': false,
      },
      'mental': mental,
      'madnessCount': madnessCount,
      'madness': <Object?>[],
      'attrs': <String, Object?>{},
      'skills': <Object?>[],
      'items': <Object?>[],
      'weapons': <Object?>[],
      'tempStatus': <Object?>[],
    },
  };
}

/// 一份含「已撕卡 / 正常 / 疯狂发作中」三种目标的裁剪态。
Map<String, Object?> _croppedState() => <String, Object?>{
      'members': <Object?>[
        _mem('p0', '撕卡者', body: '死亡'),
        _mem('p1', '正常玩家'),
        _mem('p2', '发作中',
            mental: const <Object?>['不定疯狂'], madnessCount: 2),
      ],
    };

void main() {
  // ----------------------------------------------------------
  // S4.2 · 未读角标公式（验收 ④）
  // ----------------------------------------------------------
  group('S4.2 · 未读角标 = pending(need∈{twice,kp}) + requests + await_kp',
      () {
    test('空房间 → 0', () {
      expect(
        kpUnreadCount(
          pending: const <Map<String, Object?>>[],
          requestsBySeat: const <String, List<Map<String, Object?>>>{},
          state: const <String, Object?>{},
        ),
        0,
      );
    });

    test('三种 pending 各一条：twice / kp 各计 1，owner 计 0', () {
      expect(
        kpUnreadCount(
          pending: <Map<String, Object?>>[_q(RoomConfirm.twice)],
          requestsBySeat: const <String, List<Map<String, Object?>>>{},
          state: const <String, Object?>{},
        ),
        1,
      );
      expect(
        kpUnreadCount(
          pending: <Map<String, Object?>>[_q(RoomConfirm.kp)],
          requestsBySeat: const <String, List<Map<String, Object?>>>{},
          state: const <String, Object?>{},
        ),
        1,
      );
      expect(
        kpUnreadCount(
          pending: <Map<String, Object?>>[_q(RoomConfirm.owner)],
          requestsBySeat: const <String, List<Map<String, Object?>>>{},
          state: const <String, Object?>{},
        ),
        0,
      );
      expect(
        kpUnreadCount(
          pending: <Map<String, Object?>>[
            <String, Object?>{'by': 'p1', 'op': 'state.apply'},
          ],
          requestsBySeat: const <String, List<Map<String, Object?>>>{},
          state: const <String, Object?>{},
        ),
        0,
        reason: '没有 need 键的改状态待办不计入角标',
      );
    });

    test('requests 逐 seat 累加', () {
      expect(
        kpRequestCount(<String, List<Map<String, Object?>>>{
          'p1': <Map<String, Object?>>[
            <String, Object?>{'id': 'r1'},
          ],
          'p2': <Map<String, Object?>>[
            <String, Object?>{'id': 'r2'},
            <String, Object?>{'id': 'r3'},
          ],
        }),
        3,
      );
      expect(
        kpUnreadCount(
          pending: const <Map<String, Object?>>[],
          requestsBySeat: <String, List<Map<String, Object?>>>{
            'p1': <Map<String, Object?>>[<String, Object?>{'id': 'r1'}],
          },
          state: const <String, Object?>{},
        ),
        1,
      );
    });

    test('opposed.phase：仅 await_kp 计 1', () {
      expect(
        kpOpposedAwaitingKp(<String, Object?>{
          'opposed': <String, Object?>{'phase': 'await_kp'},
        }),
        isTrue,
      );
      expect(
        kpOpposedAwaitingKp(<String, Object?>{
          'opposed': <String, Object?>{'phase': 'await_target'},
        }),
        isFalse,
      );
      expect(
        kpUnreadCount(
          pending: const <Map<String, Object?>>[],
          requestsBySeat: const <String, List<Map<String, Object?>>>{},
          state: <String, Object?>{
            'opposed': <String, Object?>{'phase': 'await_kp'},
          },
        ),
        1,
      );
    });

    test('组合：2 条 pending + 3 条 requests + 1 条 await_kp = 6', () {
      expect(
        kpUnreadCount(
          pending: <Map<String, Object?>>[
            _q(RoomConfirm.twice),
            _q(RoomConfirm.kp),
            _q(RoomConfirm.owner),
            <String, Object?>{'by': 'p1', 'op': 'state.apply'},
          ],
          requestsBySeat: <String, List<Map<String, Object?>>>{
            'p1': <Map<String, Object?>>[
              <String, Object?>{'id': 'r1'},
              <String, Object?>{'id': 'r2'},
            ],
            'p2': <Map<String, Object?>>[
              <String, Object?>{'id': 'r3'},
            ],
          },
          state: <String, Object?>{
            'opposed': <String, Object?>{'phase': 'await_kp'},
          },
        ),
        6,
      );
    });
  });

  // ----------------------------------------------------------
  // S4.2 · 面板与二次确认（验收 ②）
  // ----------------------------------------------------------
  group('S4.2 · KP 面板入口与二次确认', () {
    testWidgets('弹层入口可点性恰好等于 gate.can(op)（Q6 两动作已迁入工具栏专用 key）',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, const KpPanel()));
      await tester.pump();
      final gate = f.controllerOf(kHostSeat).gate;
      // ★ 2.36.0 / Q6：「下一回合」round.next 与「战斗准备」combat.start 已从
      //   本弹层两个 SectionBox 扁平迁入工具栏主组（独立 ValueKey），不再挂
      //   `act/<op>` 锚点。既有核心不变量**逐字保留**：下面 5 个 op 仍逐个
      //   `findsOneWidget` + `enabled == gate.can(op)`；迁移出去的两个 op
      //   另由 `room_ui_permission_test.dart` / `qa_236_regression_test.dart`
      //   的「专用 key 运行时等价探针」三视角 + tap 真触发把覆盖平移回来。
      for (final op in <String>[
        'check.request',
        'room.rules',
        'check.opposed',
        'scene.check.push',
        'sheet.damage',
      ]) {
        final finder = find.byKey(RoomKeys.action(op));
        expect(finder, findsOneWidget, reason: '缺入口 $op');
        expect(
          tester.widget<RoomTap>(finder).enabled,
          gate.can(op),
          reason: '$op 的可点性必须与闸门同源',
        );
      }
      expect(find.byKey(RoomKeys.action('round.next')), findsNothing,
          reason: '★ Q6：弹层内不再重复渲染「下一回合」');
      expect(find.byKey(RoomKeys.action('combat.start')), findsNothing,
          reason: '★ Q6：弹层内不再重复渲染「战斗准备」');
      expect(tester.takeException(), isNull);
    });

    testWidgets('room.close / session.end 必须点两次才发 intent',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, const KpPanel()));
      await tester.pump();
      f.clearSent();

      for (final op in <String>['room.close', 'session.end']) {
        final finder = find.byKey(RoomKeys.action(op));
        await _tap(tester, finder);
        expect(f.lastSent(action: op), isNull,
            reason: '$op 第一次点击不该发包');
        await _tap(tester, finder);
        expect(f.lastSent(action: op), isNotNull,
            reason: '$op 第二次点击才发 action');
        expect(f.lastSent(action: op)!['kind'], 'action');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('玩家视角没有 KP 本机只读面：角标 0、危险按钮禁用',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      expect(kpUnreadCountOf(f.sessionOf('p1')), 0);
      await tester.pumpWidget(
          _hostApp(f, const KpPanel(), seat: 'p1'));
      await tester.pump();
      final gate = f.controllerOf('p1').gate;
      expect(gate.can('room.close'), isFalse);
      expect(
        tester
            .widget<RoomTap>(find.byKey(RoomKeys.action('room.close')))
            .enabled,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });

    // ★ P10 第 6 期收尾口径更新（用户原话「推送消息弹窗后，kp工具箱里面
    //   的就不要有了」）：旧的「待确认队列逐条确认 / 取消走 confirm 意图」
    //   断言的是「KP 弹层里有一行，点它的确认按钮」——那是**旧入口**。
    //   新口径：弹层不再渲染「待处理」区块，确认改由页面级居中弹窗承载；
    //   但 confirm 的**载荷契约**（{op, by, agree}）必须逐字段继续钉住，
    //   只是入口从「弹层里的行」换成「弹窗里的同意按钮」。
    testWidgets('弹层不再有待处理区块；确认仍由居中弹窗走同一 confirm 载荷',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      // 弹窗宿主先挂上（首帧把已有请求记为已读），之后新请求才会弹。
      await tester.pumpWidget(_hostApp(
        f,
        const RoomRequestWatcher(child: KpPanel()),
      ));
      await tester.pump();

      // ① 新口径正向断言：弹层里不再有「待处理」标题 / 未读角标 / 确认行
      expect(find.text('待处理'), findsNothing,
          reason: '推送已由居中弹窗承载，KP 工具弹层不许再列一遍');
      expect(find.byKey(KpPanelKeys.unread), findsNothing,
          reason: '未读角标随「待处理」区块一起撤掉');
      expect(find.byKey(KpPanelKeys.pendingList), findsNothing);
      expect(find.byKey(KpPanelKeys.requestList), findsNothing);
      expect(find.byKey(KpPanelKeys.opposedCard), findsNothing);

      // ② 反向守卫：其余三组工具一个不少（没有连带删掉别的东西）
      for (final title in <String>[
        '工具 · 回合与检定',
        '工具 · 战斗与场景',
        '工具 · 房间管理',
      ]) {
        expect(find.text(title), findsOneWidget, reason: '缺工具区块：$title');
      }

      // ③ 载荷契约仍钉死：真实请求到达 → 居中弹窗 → 点同意 → CONFIRM 载荷
      f.controllerOf('p1').hostAction('state.edit.self', <String, Object?>{
        'status': <String, Object?>{'currentHP': 7},
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(RoomPushKeys.root), findsOneWidget,
          reason: '新请求必须弹屏幕正中（弹层不再有入口，弹窗是唯一入口）');

      f.clearSent();
      await tester.tap(find.byKey(RoomPushKeys.agree));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final sent = f.lastSent(op: RoomIntent.confirm);
      expect(sent, isNotNull, reason: '点同意必须真的发出 confirm 意图');
      expect(sent!['kind'], 'intent');
      final p = asMap(sent['p']);
      expect(p['op'], 'state.edit.self');
      expect(p['by'], 'p1');
      expect(p['agree'], true);
      expect(tester.takeException(), isNull);
    });

    testWidgets('showKpPanel 推出的弹层能取到同一份作用域',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_hostApp(
        f,
        Builder(
          builder: (BuildContext context) => RoomTap(
            label: '打开',
            onTap: () => showKpPanel<void>(context),
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('打开'));
      await tester.pump();
      expect(find.byKey(KpPanelKeys.root), findsOneWidget);
      // ★ 口径更新：旧断言是 `unread` findsOneWidget；现在角标已随
      //   「待处理」区块撤掉，改为「不再渲染」+「三组工具仍在」。
      expect(find.byKey(KpPanelKeys.unread), findsNothing);
      expect(find.text('待处理'), findsNothing);
      expect(find.text('工具 · 回合与检定'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('showRoomSheet 的 body 在作用域内可读本机只读面',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      f.host.pending.add(_q(RoomConfirm.twice));
      await tester.pumpWidget(_hostApp(
        f,
        Builder(
          builder: (BuildContext context) => RoomTap(
            label: '打开',
            onTap: () => showRoomSheet<void>(
              context: context,
              title: '探针',
              body: (BuildContext _) =>
                  Text('${kpUnreadCountOf(f.sessionOf(kHostSeat))}',
                      key: const ValueKey<String>('probe/unread')),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('打开'));
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey<String>('probe/unread')))
            .data,
        '1',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  // ----------------------------------------------------------
  // S4.1 · 工具窄栏（验收 P1-01 / P1-02 / P1-03）
  // ----------------------------------------------------------
  group('S4.1 · 工具窄栏：本地加怪 / 5 色 / 橡皮一次提交', () {
    testWidgets('加怪走左栏弹层：只改本地候选，不发任何包',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      // ★ P16 KP-7 / KP-10：加怪唯一入口已搬到左窄栏（弹层六字段）。
      f.localOf(kHostSeat).setTab('left', 0);
      await tester.pumpWidget(_hostApp(f, const GpKpLeft()));
      await tester.pump();
      f.clearSent();

      // 正向反证：工具窄栏确实不再有加怪入口（KP-10）。
      expect(find.byKey(GpKpToolsKeys.addActor), findsNothing,
          reason: 'KP-10：工具窄栏不再有加怪按钮');

      await _tap(tester, find.byKey(GpKpLeftKeys.addActor));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(AddActorSheetKeys.root), findsOneWidget,
          reason: 'KP-7：点加怪必须先弹六字段弹层');
      await tester.enterText(find.byKey(AddActorSheetKeys.name), '哥布林');
      await tester.pump();
      await _tap(tester, find.byKey(AddActorSheetKeys.confirm));
      await tester.pump(const Duration(milliseconds: 400));

      final local = f.localOf(kHostSeat);
      expect(local.pendingActors.length, 1);
      expect(local.pendingActors.first['name'], '哥布林');
      expect(local.pendingActors.first['id'], 'la1');
      // KP-8：弹层默认护甲 0 也要落进候选记录。
      expect(local.pendingActors.first['armor'], 0,
          reason: 'KP-8：默认护甲 0');
      expect(
        f.sent.where((Map<String, Object?> e) => <String>[
          'combat.actor',
          'combat.pool.set',
          'combat.start',
          'map.mark',
        ].contains(jsStr(e['op']))),
        isEmpty,
        reason: '本地候选不进事件流',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('6 色切换写本地色号，并让舞台进入画笔模式',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      final stage = _FakeStage();
      await tester.pumpWidget(_hostApp(f, GpKpTools(stage: stage)));
      await tester.pump();
      // ★ KP-2：第 6 色 #e67e22 追加在末尾；前 5 色索引即协议、顺序未动。
      expect(kDrawColors.length, 6);
      await _tap(tester, find.byKey(GpKpToolsKeys.color(3)));
      expect(f.localOf(kHostSeat).toolColorIndex, 3);
      expect(stage.calls.last, 'stroke:#3498db:3.0');
      // 正向：新增的第 6 色可选，色号与绘制色都对。
      await _tap(tester, find.byKey(GpKpToolsKeys.color(5)));
      expect(f.localOf(kHostSeat).toolColorIndex, 5);
      expect(stage.calls.last, 'stroke:#e67e22:3.0');
      expect(tester.takeException(), isNull);
    });

    testWidgets('橡皮：段级删除 + 手势末尾恰好一次 map.strokes.set',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      final ctl = f.controllerOf(kHostSeat);
      final eraser = KpEraser(
        commit: (List<Map<String, Object?>> strokes) => ctl.hostAction(
          'map.strokes.set',
          <String, Object?>{'strokes': strokes},
        ),
      );
      final stage = _FakeStage();
      // 往权威快照里塞一条 5 点的笔迹（UI 侧不写权威态，这里只造测试数据）。
      final scene = <String, Object?>{...asMap(f.hostState()['scene'])};
      scene['strokes'] = <Object?>[
        <String, Object?>{
          'id': 's1',
          'color': '#e74c3c',
          'width': 3,
          'pts': <Object?>[
            for (var i = 0; i < 6; i++)
              <String, Object?>{'x': 0.1 * i, 'y': 0.5},
          ],
        },
      ];
      f.hostState()['scene'] = scene;
      await tester.pumpWidget(
          _hostApp(f, GpKpTools(stage: stage, eraser: eraser)));
      await tester.pump();
      f.clearSent();

      await _tap(tester, find.byKey(GpKpToolsKeys.erase));
      expect(stage.calls, contains('erase'));
      expect(eraser.active, isTrue);
      // 手势期间逐点演算：只改本地，不发包。
      for (var i = 0; i < 3; i++) {
        eraser.move(NormPoint(0.2 + 0.1 * i, 0.5));
      }
      expect(f.sent, isEmpty, reason: '手势期间零发送');
      await eraser.finish();

      final commits = f.sent
          .where((Map<String, Object?> e) =>
              jsStr(e['op']) == 'map.strokes.set')
          .toList();
      expect(commits.length, 1, reason: '手势末尾只提交一次');
      expect(eraser.commits, 1);
      final payload = asMap(commits.single['p']);
      final strokes = (payload['strokes']! as List).cast<Map<String, Object?>>();
      expect(strokes.length, 2, reason: '中间 3 点被擦掉 → 两段');
      expect(tester.takeException(), isNull);
    });

    // ★ P12 KP-2c / R1：「清除笔迹」→「清除标记」，范围扩到
    //   笔迹 + 标点 + 单位标记三类（strokesOnly:false）。
    //   按「更强或等价」改写：二次确认核心不变量逐字保留，
    //   strokesOnly 期望值随产品真变等价更新，并**新增**文案/范围正向断言。
    testWidgets('清除标记必须连点两次（KP-2c：三类全清、素材不动）',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      f.hostState()['scene'] = <String, Object?>{
        'assets': <Object?>[
          <String, Object?>{
            'id': 'a1', 'kind': 'map', 'name': '底图',
            'data': '', 'revealed': true, 'at': 1,
          },
        ],
        'strokes': <Object?>[<String, Object?>{
          'color': '#ff0000', 'width': 2,
          'pts': <Object?>[<String, Object?>{'x': 0.1, 'y': 0.1}],
        }],
        'marks': <Object?>[<String, Object?>{
          'x': 0.5, 'y': 0.5, 'kind': 'dot',
          'label': '标点', 'revealed': true,
        }],
      };
      await tester.pumpWidget(_hostApp(f, const GpKpTools()));
      await tester.pump();
      // ★ 新增正向断言：新文案恰好一个、旧文案与冗余入口消失。
      expect(find.text('清除标记'), findsOneWidget,
          reason: 'R1：工具窄栏新文案恰好一个');
      expect(find.text('清除笔迹'), findsNothing);
      expect(find.text('清除笔迹与标记'), findsNothing);
      expect(find.text('放玩家'), findsNothing, reason: 'KP-2a：冗余按钮已删');

      f.clearSent();
      final clear = find.byKey(GpKpToolsKeys.clear);
      await _tap(tester, clear);
      expect(f.lastSent(action: 'map.clear'), isNull,
          reason: '核心不变量：第一下只点亮二次确认，不发包');
      await _tap(tester, clear);
      final sent = f.lastSent(action: 'map.clear');
      expect(sent, isNotNull,
          reason: '核心不变量：第二下才真正下发');
      expect(asMap(sent!['p'])['strokesOnly'], false,
          reason: '产品真变：三类全清，等价于旧 true 的「更强」口径');
      // ★ 新增：三类清零、公开素材集合长度不变。
      final scene = asMap(f.hostState()['scene']);
      expect(asList(scene['strokes']), isEmpty, reason: '笔迹集合清零');
      expect(asList(scene['marks']), isEmpty, reason: '标点/单位标记集合清零');
      expect(asList(scene['assets']).length, 1, reason: '公开素材不动');
      expect(tester.takeException(), isNull);
    });

    testWidgets('KP-5：玩家卡片按钮「全屏」→「手绘板」（精确匹配口径）',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, const GpKpPlayers()));
      await tester.pump();
      final Finder board = find.byKey(GpKpPlayersKeys.board('p1'));
      expect(board, findsOneWidget);
      expect(find.descendant(of: board, matching: find.text('手绘板')),
          findsOneWidget, reason: '★ KP-5 新文案');
      expect(find.descendant(of: board, matching: find.text('全屏')),
          findsNothing, reason: '★ KP-5 旧文案已删');
      // 同卡片还有「手绘板：N 笔」统计文本，find.text 是精确匹配不会误伤。
      expect(find.textContaining('手绘板：'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('素材上传只在左窄栏素材 tab 发 asset.add；公开·删除同栏',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      f.host.localAssets.add(<String, Object?>{
        'id': 'seedAsset',
        'kind': 'map',
        'name': '旧地图',
        'data': '',
        'revealed': false,
        'at': 1,
      });
      // ★ P16 KP-10：上传按钮已从工具窄栏移走（唯一入口在左窄栏素材 tab）。
      await tester.pumpWidget(_hostApp(f, const GpKpTools()));
      await tester.pump();
      expect(find.byKey(GpKpToolsKeys.upload), findsNothing,
          reason: 'KP-10：工具窄栏不再有上传素材按钮');
      expect(f.picker.calls, 0, reason: '工具窄栏没有上传入口 → 不该触发选图');

      // ① 上传：左窄栏「素材」tab（P16 起唯一入口）。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      f.localOf(kHostSeat).setTab('left', 1);
      await tester.pumpWidget(_hostApp(f, const GpKpLeft()));
      await tester.pump();
      f.clearSent();
      await _tap(tester, find.byKey(GpKpLeftKeys.upload));
      expect(f.picker.calls, 1);
      final add = f.lastSent(action: 'asset.add');
      expect(add, isNotNull, reason: '左窄栏上传必须发 asset.add');
      expect(asMap(asMap(add!['p'])['asset'])['kind'], 'map');

      // ② 公开 / 删除：与上传同栏（左窄栏「素材」tab），不再两处重复。
      await _tap(tester, find.byKey(GpKpLeftKeys.reveal('seedAsset')).first);
      final reveal = f.lastSent(action: 'asset.reveal');
      expect(reveal, isNotNull);
      expect(asMap(reveal!['p'])['id'], 'seedAsset');
      expect(asMap(reveal['p'])['revealed'], true);

      await _tap(tester, find.byKey(GpKpLeftKeys.delete('seedAsset')).first);
      final del = f.lastSent(action: 'asset.del');
      expect(del, isNotNull);
      expect(asMap(del!['p'])['id'], 'seedAsset');
      expect(tester.takeException(), isNull);
    });
  });

  // ----------------------------------------------------------
  // S4.1 · 左窄栏两 tab（P13 MAP-1：地图 tab 已删）
  // ----------------------------------------------------------
  group('S4.1 · 左窄栏两 tab', () {
    testWidgets('切 tab 写本地态，两块内容各自可达（地图面板已删）',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, const GpKpLeft()));
      await tester.pump();
      final local = f.localOf(kHostSeat);
      // ★ P13 MAP-1 索引重映射：0=NPC·怪物，1=素材（旧 2=素材）。
      expect(local.leftTab, 0);
      expect(find.byKey(const ValueKey<String>('gpKpLeft/mapSummary')),
          findsNothing,
          reason: '★ 地图面板整块删除（Q8 明确不补回）');
      expect(find.text('地图'), findsNothing);

      await _tap(tester, find.text('NPC·怪物'));
      expect(local.leftTab, 0);
      expect(find.byKey(GpKpLeftKeys.addActor), findsOneWidget);

      // ★ P16 KP-7：内联表单已删 → 点入口先弹层，填名 + 确定才进候选池。
      await _tap(tester, find.byKey(GpKpLeftKeys.addActor));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(AddActorSheetKeys.root), findsOneWidget,
          reason: 'KP-7：点加怪必须先弹出六字段弹层');
      await tester.enterText(find.byKey(AddActorSheetKeys.name), '食尸鬼');
      await tester.pump();
      await _tap(tester, find.byKey(AddActorSheetKeys.confirm));
      await tester.pump(const Duration(milliseconds: 400));
      expect(local.pendingActors.length, 1);
      expect(local.pendingActors.first['name'], '食尸鬼');

      await _tap(tester, find.text('素材'));
      expect(local.leftTab, 1, reason: '★ P13 MAP-1：素材 tab 索引 2→1');
      expect(find.byKey(GpKpLeftKeys.upload), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ----------------------------------------------------------
  // S4.3 · 场景检定 6 档（K-04 / 验收 ⑤）
  // ----------------------------------------------------------
  group('S4.3 · 场景检定 6 档载荷逐字段', () {
    test('6 档常量已删：载荷纯函数三键口径不回归', () {
      // ★ W-A 已删除 `kSceneCheckLevels` / `kKpSceneLevels` / `GpSceneCheckKeys.level(int)`；
      //   domain 侧 `sceneCheckStepPayload` 的三键口径是核心不变量，逐字保留。
      final p = sceneCheckStepPayload(
        stepId: 'st1',
        seat: 'p1',
        level: 5,
      );
      expect(p.length, 3, reason: '恰好三个键');
      expect(p.keys.toSet(), <String>{'stepId', 'seat', 'level'});
      expect(p['stepId'], 'st1');
      expect(p['seat'], 'p1');
      expect(p['level'], 5);
    });

    testWidgets('删 6 档后：6 个 level key 全无、保留 quickPush/editor、四档检定方式仍在',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, const GpSceneCheckKp()));
      await tester.pump();

      // ① 6 个档位按钮全部 findsNothing（硬编码字面量，避免引用已删工厂）。
      for (final int lv in <int>[5, 4, 3, 2, 0, -1]) {
        expect(find.byKey(ValueKey<String>('gpSceneCheckKp/level/$lv')),
            findsNothing,
            reason: '删 6 档后第 $lv 档按钮不得再渲染');
      }
      // ② 保留的两个动作按钮仍在且可点。
      for (final Key k in <Key>[
        GpSceneCheckKeys.quickPush,
        GpSceneCheckKeys.editor,
      ]) {
        expect(find.byKey(k), findsOneWidget);
        expect(tester.widget<RoomTap>(find.byKey(k)).enabled, isTrue);
      }
      // ③ 网格不塌陷 / 无空白占位：root 尺寸有效，两按钮四边不越框。
      final Rect grid = tester.getRect(find.byKey(GpSceneCheckKeys.root));
      expect(grid.width, greaterThan(0));
      expect(grid.height, greaterThan(0));
      for (final Key k in <Key>[
        GpSceneCheckKeys.quickPush,
        GpSceneCheckKeys.editor,
      ]) {
        final Rect r = tester.getRect(find.byKey(k));
        expect(r.left, greaterThanOrEqualTo(grid.left - 0.5));
        expect(r.right, lessThanOrEqualTo(grid.right + 0.5));
        expect(r.top, greaterThanOrEqualTo(grid.top - 0.5));
        expect(r.bottom, lessThanOrEqualTo(grid.bottom + 0.5));
      }
      // ④ 四档「检定方式」正向断言（难度档不是 6 档裁定按钮，仍必须完整）。
      for (final m in kKpSceneModes) {
        expect(find.byKey(GpSceneCheckKeys.mode(m.value)), findsOneWidget,
            reason: '检定方式第 ${m.value} 档不该丢');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('快速推送走 scene.check.push 且带一步',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, const GpSceneCheckKp()));
      await tester.pump();
      f.clearSent();
      await _tap(tester, find.byKey(GpSceneCheckKeys.quickPush));
      final sent = f.lastSent(action: 'scene.check.push');
      expect(sent, isNotNull);
      final p = asMap(sent!['p']);
      expect((p['steps']! as List).length, 1);
      expect(tester.takeException(), isNull);
    });
  });

  // ----------------------------------------------------------
  // S4.5 · 定向 9 项目标过滤（K-02 / 验收 ③）
  // ----------------------------------------------------------
  group('S4.5 · 定向 9 项目标过滤（R2a）', () {
    test('9 项清单与 5 项需同意名单', () {
      // ★ P17 KP-6：删「暗骰」（工具栏已有）→ kKpDirectives 9→8；
      //   删「请求修改状态」（玩家请求直接弹窗）→ kKpExtraDirectives 2→1。
      //   强口径：不仅数条数，还断言删掉的确实不在、留下的都在。
      expect(kKpDirectives.length, 8);
      expect(kKpDirectives.map((d) => d.op), isNot(contains('dice.dark')),
          reason: 'KP-6：暗骰入口已删（工具栏与骰子条已有）');
      expect(kKpDirectives.map((d) => d.op),
          containsAllInOrder(<String>[
            'sheet.damage',
            'sheet.tempstatus',
            'sheet.item',
            'sheet.sancheck',
            'aid.apply',
          ]),
          reason: 'KP-6：其余指令全部保留');
      expect(kKpConsentOps.length, 5);
      expect(kKpMadBoutExtraOps.length, 2);
      expect(kKpExtraDirectives.length, 1);
      expect(kKpExtraDirectives.map((d) => d.op),
          isNot(contains('state.request')),
          reason: 'KP-6：「请求修改状态」已删（玩家请求直接弹窗）');
      expect(kKpExtraDirectives.map((d) => d.op), contains('aid.psycho'),
          reason: 'KP-6：精神分析指令保留');
      for (final d in kKpDirectives) {
        expect(d.op.isNotEmpty, isTrue);
        expect(RoomKeys.action(d.op), isA<Key>());
      }
      for (final op in kKpConsentOps) {
        expect(kpDirectiveNeedsConsent(op), isTrue);
        expect(kpDirectiveBlocksMadBout(op), isTrue);
      }
    });

    test('已撕卡座位在 9 项里全部被过滤', () {
      final members = <Map<String, Object?>>[
        _mem('p0', '撕卡者', body: '死亡'),
        _mem('p1', '正常玩家'),
      ];
      for (final d in kKpDirectives) {
        final rows = kpDirectiveTargets(members, op: d.op);
        expect(rows.length, 1, reason: '${d.op} 漏过滤已撕卡');
        expect(rows.first['seat'], 'p1');
      }
    });

    test('疯狂发作中：需同意 5 项被过滤，其余 4 项保留', () {
      final members = <Map<String, Object?>>[
        _mem('p1', '正常玩家'),
        _mem('p2', '发作中',
            mental: const <Object?>['不定疯狂'], madnessCount: 2),
      ];
      expect(kpMadBout(members[1]), isTrue);
      for (final op in kKpConsentOps) {
        final rows = kpDirectiveTargets(members, op: op);
        expect(rows.length, 1, reason: '$op 应过滤疯狂发作中的座位');
        expect(rows.first['seat'], 'p1');
      }
      // 权威端另有同款拒绝分支的 2 项，按 K6 一并对齐。
      for (final op in kKpMadBoutExtraOps) {
        expect(kpDirectiveTargets(members, op: op).length, 1,
            reason: '$op 与权威端拒绝分支对齐');
      }
      for (final op in <String>[
        'sheet.damage',
        'sheet.tempstatus',
        'sheet.item',
        'dice.dark',
      ]) {
        expect(kpDirectiveNeedsConsent(op), isFalse);
        expect(kpDirectiveTargets(members, op: op).length, 2,
            reason: '$op 是「直接生效」，不应过滤发作中目标');
      }
    });

    test('指令载荷逐项带 seat', () {
      for (final d in <String>[
        ...kKpDirectives.map((KpDirective e) => e.op),
        ...kKpExtraDirectives.map((KpDirective e) => e.op),
      ]) {
        final p = kpDirectivePayload(d, 'p1');
        expect(p['seat'], 'p1', reason: d);
      }
    });

    testWidgets('弹层里点指令 → 目标列表过滤 → 执行发 action',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(
          _hostApp(f, KpDirectivesSheet(stateOverride: _croppedState())));
      await tester.pump();
      f.clearSent();

      // 「造成伤害」：已撕卡过滤，发作中保留。
      await _tap(tester, find.byKey(RoomKeys.action('sheet.damage')));
      expect(find.textContaining('撕卡者'), findsNothing);
      expect(find.textContaining('发作中'), findsOneWidget);

      // 「治愈不定疯狂」：需同意，发作中也过滤。
      await _tap(tester, find.byKey(RoomKeys.action('madness.cure')));
      expect(find.textContaining('撕卡者'), findsNothing);
      expect(find.textContaining('发作中'), findsNothing);
      expect(find.textContaining('正常玩家'), findsOneWidget);

      await _tap(tester, find.byKey(const ValueKey<String>(
          'kpDirective/target/madness.cure/p1')));
      final sent = f.lastSent(action: 'madness.cure');
      expect(sent, isNotNull);
      expect(asMap(sent!['p'])['seat'], 'p1');
      expect(tester.takeException(), isNull);
    });
  });

  // ----------------------------------------------------------
  // S4.4 · 玩家信息：无 maxSAN / madnessCount / 笔数
  // ----------------------------------------------------------
  group('S4.4 · KP 玩家信息三条口径', () {
    test('笔数来源：本机只读面优先，裁剪态回退', () {
      expect(
        kpBoardStrokeCount(const <String, Object?>{}, 'p1',
            board: <String, Object?>{
              'strokes': <Object?>[1, 2, 3],
            }),
        3,
      );
      expect(
        kpBoardStrokeCount(const <String, Object?>{}, 'p1'),
        0,
      );
    });

    testWidgets('裁剪态里他人无 maxSAN → SAN 只显当前值、疯狂只显计数',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      final state = _croppedState();
      // 他人视图：maxSAN 键存在但为 null、疯狂明细整块删。
      for (final raw in (state['members']! as List)) {
        final m = raw as Map<String, Object?>;
        final sheet = m['sheet'] as Map<String, Object?>;
        final st = sheet['status'] as Map<String, Object?>;
        st['maxSAN'] = null;
        sheet.remove('madness');
      }
      await tester.pumpWidget(
          _hostApp(f, GpKpPlayers(stateOverride: state)));
      await tester.pump();
      expect(find.byKey(GpKpPlayersKeys.root), findsOneWidget);

      final stats = tester.widget<Text>(find.byKey(
          const ValueKey<String>('gpKpPlayers/stats/p2')));
      expect(stats.data, contains('SAN 40'));
      expect(stats.data, isNot(contains('SAN 40 /')),
          reason: '他人视图绝不能显示 / 60');
      final madness = tester.widget<Text>(find.byKey(
          const ValueKey<String>('gpKpPlayers/madness/p2')));
      expect(madness.data, '疯狂：不定疯狂 ×2');
      final board = tester.widget<Text>(find.byKey(
          const ValueKey<String>('gpKpPlayers/boardCount/p2')));
      expect(board.data, contains('笔'));
      expect(tester.takeException(), isNull);
    });
  });

  // ----------------------------------------------------------
  // S4.5 · 全部 KP 弹层入口与分派（验收 ②）
  // ----------------------------------------------------------
  group('S4.5 · KP 弹层分派与入口可点性', () {
    testWidgets('8 个分派 id 都能打开弹层且不抛异常',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      expect(kKpSheetIds.length, 8);
      for (final id in kKpSheetIds) {
        // 每轮换一个 MaterialApp key：旧的底部弹层 route 连同 barrier
        // 一起销毁，否则下一轮的点击会被上一层弹层吃掉。
        await tester.pumpWidget(_hostApp(
          f,
          Builder(
            builder: (BuildContext context) => RoomTap(
              label: '打开$id',
              onTap: () => openKpSheet(context, id),
            ),
          ),
          appKey: ValueKey<String>('app/$id'),
        ));
        await tester.pump();
        await tester.tap(find.text('打开$id'));
        await tester.pump();
        expect(find.byType(RoomSheet), findsOneWidget,
            reason: '$id 没有打开弹层');
        expect(tester.takeException(), isNull, reason: id);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('对抗弹层：ACT 入口 enabled==gate.can，意图入口按 K6 判',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      // 直接把弹层体泵进 Scaffold：独立可测，不受底部弹层入场动画影响。
      await tester.pumpWidget(_hostApp(f, const OpposedSheet()));
      await tester.pump();
      expect(find.byKey(OpposedSheetKeys.root), findsOneWidget);
      final gate = f.controllerOf(kHostSeat).gate;
      expect(
        tester
            .widget<RoomTap>(find.byKey(RoomKeys.action('check.opposed')))
            .enabled,
        gate.can('check.opposed'),
      );
      f.clearSent();
      await _tap(tester, find.byKey(RoomKeys.action('check.opposed')));
      // ★ P17 KP-3：弹层改成「先选甲乙双方才发包」—— 空表单只出本地提示，
      //   绝不空发 `check.opposed`（对齐 `p10_t6:399-410`「不许发空包」门禁）。
      //   这是比旧口径更强的断言：旧版点按钮就发包，现在必须表单齐。
      expect(f.lastSent(action: 'check.opposed'), isNull,
          reason: 'KP-3：空表单不空发（旧版点按钮直接发包，已收紧）');
      expect(f.localOf(kHostSeat).notice, contains('请先选择'),
          reason: 'KP-3：空表单给明确提示，不是「点了没反应」');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    // ★ 2.37.0 / Q4 等价迁移：DiceToolsSheet 删掉 SAN Check 块（key 常量全保留），
    //   SAN 行为改由专用弹层承担。核心不变量「走 sancheck 意图通道」逐字保留，
    //   并新增「DiceToolsSheet 不含 sanCheck」的正向断言（比旧口径更强）。
    testWidgets('SAN Check 走 sancheck 意图通道（2.37.0 迁至专用弹层）',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      // ① 骰子工具弹层不再提供该入口（常量仍在，用于这个负向断言）。
      await tester.pumpWidget(_hostApp(f, const DiceToolsSheet()));
      await tester.pump();
      expect(find.byKey(DiceToolsKeys.sanCheck), findsNothing,
          reason: '★ 2.37.0/Q4：骰子工具弹层不再含 SAN Check 入口');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // ② 专用弹层：填合法表达式 → 确定 → 发 sancheck 意图（原核心不变量）。
      await tester.pumpWidget(_hostApp(f, const SanCheckSheet()));
      await tester.pump();
      await tester.enterText(find.byKey(SanCheckSheetKeys.field), '2/1');
      await tester.pump();
      f.clearSent();
      await _tap(tester, find.byKey(SanCheckSheetKeys.submit));
      final sent = f.lastSent(op: 'sancheck');
      expect(sent, isNotNull,
          reason: 'SAN Check 仍必须走 sancheck 意图通道（行为不变量未变）');
      expect(sent!['kind'], 'intent');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('场景弹层：推送 scene.check.push 带多步',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, const SceneSheet()));
      await tester.pump();
      f.clearSent();
      await _tap(tester, find.byKey(SceneSheetKeys.addStep));
      await _tap(tester, find.byKey(RoomKeys.action('scene.check.push')));
      final sent = f.lastSent(action: 'scene.check.push');
      expect(sent, isNotNull);
      final p = asMap(sent!['p']);
      expect((p['steps']! as List).length, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('战斗弹层：combat.start 带 pcSeats / actors',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      f.localOf(kHostSeat).pendingActors.add(<String, Object?>{
        'id': 'la1',
        'name': '哥布林',
        'kind': 'monster',
        'hp': 10,
        'hpMax': 10,
        'dex': 50,
        'actionsPerRound': 1,
      });
      await tester.pumpWidget(_hostApp(f, const CombatSheet()));
      await tester.pump();
      expect(find.byKey(CombatSheetKeys.root), findsOneWidget);
      f.clearSent();
      // ★ P10 第 7 期 C 批 B 口径更新：怪物改成「默认全不选」+「至少 1 怪」
      //   门禁，所以必须先勾 la1 再点部署。旧断言「直接点按钮」不再成立。
      await _tap(tester, find.byKey(CombatSheetKeys.monsterToggle('la1')));
      await _tap(tester, find.byKey(RoomKeys.action('combat.start')));
      final sent = f.lastSent(action: 'combat.start');
      expect(sent, isNotNull);
      final p = asMap(sent!['p']);
      // ---- 核心不变量逐字保留 ----
      expect((p['pcSeats']! as List).isNotEmpty, isTrue);
      expect((p['actors']! as List).isNotEmpty, isTrue);
      // ---- 新增更强正向断言（口径更新 = 加严，不是放宽）----
      // 旧断言 `actors.length == 1` 只允许 1 条候选怪；新的正确载荷必须
      // 同时含「勾选的怪物」与「显式构造的 PC 记录」（domain 不会自动带 PC），
      // 所以这里改为逐字段钉死，覆盖 actorIds / pcSeats / PC 字段 / 计数。
      expect((p['actorIds']! as List).map(jsStr).toList(), <String>['la1'],
          reason: 'actorIds 恰为勾选的那一只怪');
      expect((p['pcSeats']! as List).map(jsStr).toList(), f.playerSeats,
          reason: 'pcSeats 恰为默认全选的全部座位');
      final actors = (p['actors']! as List).map(asMap).toList();
      final pcs = actors.where((a) => jsStr(a['kind']) == 'pc').toList();
      expect(pcs.length, f.playerSeats.length,
          reason: 'actors 必须含每个勾选玩家的 PC 记录（带 seat）');
      for (final pc in pcs) {
        expect(jsStr(pc['seat']).isNotEmpty, isTrue,
            reason: 'PC 记录必须带 seat');
        expect(jsStr(pc['id']).startsWith('p-'), isTrue);
        expect(pc.containsKey('dex'), isTrue);
        expect(pc.containsKey('hp'), isTrue);
        expect(pc.containsKey('hpMax'), isTrue);
      }
      expect(actors.where((a) => jsStr(a['kind']) != 'pc').length, 1,
          reason: 'actors 里恰好 1 条勾选的怪物记录');
      final count =
          tester.widget<Text>(find.byKey(CombatSheetKeys.deployCount));
      expect(count.data, contains('怪物 1'));
      expect(count.data, contains('玩家 ${f.playerSeats.length}'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('战斗弹层：不勾怪物直接部署 → 不发 combat.start + 明确提示',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      f.localOf(kHostSeat).pendingActors.add(<String, Object?>{
        'id': 'la1',
        'name': '哥布林',
        'kind': 'monster',
        'hp': 10,
        'hpMax': 10,
        'dex': 50,
        'actionsPerRound': 1,
      });
      await tester.pumpWidget(_hostApp(f, const CombatSheet()));
      await tester.pump();
      f.clearSent();
      await _tap(tester, find.byKey(RoomKeys.action('combat.start')));
      expect(f.lastSent(action: 'combat.start'), isNull,
          reason: '空手点部署不能发 combat.start');
      expect(f.localOf(kHostSeat).notice, contains('至少选择 1 个怪物/NPC'),
          reason: '必须给一次性提示（K7），不能静默 return');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('人物卡弹层只读，无写回按钮',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(
          _hostApp(f, const CharViewSheet(seat: 'p1')));
      await tester.pump();
      expect(find.byKey(CharViewKeys.root), findsOneWidget);
      expect(find.byKey(CharViewKeys.vitals), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  // ----------------------------------------------------------
  // 机械门禁（验收 ⑥：全部 11 个 T04 文件）
  // ----------------------------------------------------------
  group('门禁 · 全部 T04 文件零命中', () {
    test('11 个文件纯净', () {
      const files = <String>[
        'sheets/sheet_kp_panel.dart',
        'sheets/sheet_kp_directives.dart',
        'sheets/sheet_opposed.dart',
        'sheets/sheet_combat.dart',
        'sheets/sheet_scene.dart',
        'sheets/sheet_char_view.dart',
        'sheets/sheet_dice_tools.dart',
        'widgets/gp_kp_left.dart',
        'widgets/gp_kp_tools.dart',
        'widgets/gp_scene_check_kp.dart',
        'widgets/gp_kp_players.dart',
      ];
      const banned = <String>[
        'RoomHost',
        'rules?.check(',
        'rollExpr(',
        'opposedFull(',
        'plBottomBar',
        'plFeeds',
        'kpChat',
        'kpGameLog',
      ];
      expect(files.length, 11, reason: 'T04 应恰好 11 个新增文件');
      for (final rel in files) {
        final src = File('lib/ui/room/$rel').readAsStringSync();
        for (final word in banned) {
          expect(src.contains(word), isFalse,
              reason: '$rel 命中门禁字面量 $word');
        }
        expect(src.contains('PlaceholderBlock'), isFalse,
            reason: '$rel 仍残留占位块');
        for (final line in src.split('\n')) {
          if (!line.trimLeft().startsWith('//')) continue;
          for (final word in <String>[
            'package:flutter',
            'dart:io',
            'dart:ui',
          ]) {
            expect(line.contains(word), isFalse,
                reason: '$rel 注释命中 $word');
          }
        }
        // 权威快照赋值（形如 `state[...] =`）在本层零出现。
        expect(RegExp(r'state\s*\[[^\]]+\]\s*=').hasMatch(src), isFalse,
            reason: '$rel 出现权威快照赋值');
      }
    });
  });
}
