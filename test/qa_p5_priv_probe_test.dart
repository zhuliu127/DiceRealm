// ============================================================
// test/qa_p5_priv_probe_test.dart — P5 独立探针 ①：越权 / 结构隐藏
//
// 与既有 T-30（`room_ui_permission_test.dart`）**互补而非重复**：
//   T-30 只扫 `RoomKeys.action(op)` 的 `act/` 锚点（29 个 op）；
//   本文件专攻「走专用 key、T-30 射程外」的那批 KP 专属动作，逐个问：
//     玩家 / 旁观视角下它们**在不在树里**？在的话**可不可点**？点下去**发不发包**？
//
// 判据（比 T-30 更严）：
//   · KP 专属块对玩家 / 旁观 → `findsNothing`（结构性不渲染，不是禁用）；
//   · 若确实渲染了 → `RoomTap.enabled` 必须为 false **且** 点下去零发包；
//   · 反向守卫：同一 key 在 KP 视角必须找得到，否则「找不到」是因为页面没画，
//     而不是因为权限正确。
//
// 铁律与既有用例一致：全内存后端、零真实 I/O、不用 pumpAndSettle 等节流。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap;
import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/ui/room/room_game_page.dart' show RoomGamePage;
import 'package:dice_realm/ui/room/room_keys.dart' show RoomKeys, RoomSlot;
import 'package:dice_realm/ui/room/room_lobby_page.dart'
    show RoomLobbyKeys, RoomLobbyPage;
import 'package:dice_realm/ui/room/sheets/sheet_combat.dart' show CombatSheet;
import 'package:dice_realm/ui/room/sheets/sheet_self_state.dart'
    show GpSelfStateKeys, openSelfStateSheet;
import 'package:dice_realm/ui/room/widgets/gp_kp_left.dart' show GpKpLeftKeys;
import 'package:dice_realm/ui/room/widgets/gp_kp_tools.dart' show GpKpToolsKeys;
import 'package:dice_realm/ui/room/widgets/gp_pl_char_card.dart'
    show GpPlCharCardKeys;
import 'package:dice_realm/ui/room/widgets/gp_pl_sketch.dart' show GpPlSketchKeys;
import 'package:dice_realm/ui/room/widgets/gp_scene_check_kp.dart'
    show GpSceneCheckKeys;
import 'package:dice_realm/ui/room/widgets/gp_scene_check_pl.dart'
    show GpSceneCheckPlKeys;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart' show RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

/// 作用域挂在 Navigator **之上**：页面与弹层都能 `RoomScope.of`。
Widget appFor(RoomUiFixture f, String seat, Widget body) {
  return MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    builder: (BuildContext _, Widget? child) =>
        f.scoped(seat, child: child ?? const SizedBox.shrink()),
    home: body,
  );
}

/// 读某个 key 的 `RoomTap.enabled`；不存在或不是 RoomTap 返回 null。
bool? enabledOf(WidgetTester tester, Key key) {
  final Finder finder = find.byKey(key);
  if (finder.evaluate().isEmpty) return null;
  final Widget w = tester.widget(finder);
  if (w is! RoomTap) return null;
  return w.enabled;
}

/// 造一条**已公开**素材（走真实 action，不手改权威态）。
///
/// 返回素材 id。这样玩家侧 `assetsOf/publicAssets` 里真有这一行 ——
/// 「行渲染了、按钮不该有」才是有效断言（行都不存在时 findsNothing 没信息量）。
String seedRevealedAsset(RoomUiFixture f) {
  f.controllerOf(kHostSeat).hostAction('asset.add', <String, Object?>{
    'asset': <String, Object?>{'kind': 'map', 'name': '洋馆一层'},
  });
  final List<Object?> rows =
      asList(asMap(f.hostState()['scene'])['assets']); // 公开后才进 state
  final List<Object?> priv = asList(f.host.localAssets);
  expect(priv, isNotEmpty, reason: '前提：asset.add 应落进 KP 私有库');
  final String id = '${asMap(priv.last)['id']}';
  f.controllerOf(kHostSeat).hostAction('asset.reveal', <String, Object?>{
    'id': id,
    'revealed': true,
  });
  final List<Object?> after = asList(asMap(f.hostState()['scene'])['assets']);
  expect(after.length, greaterThan(rows.length),
      reason: '前提：asset.reveal 后公开画面里应多出这一条');
  return id;
}

void main() {
  // ==========================================================
  // 攻击面 A：14 类「专用 key」的 KP 专属入口
  // ==========================================================

  group('A-1 招募期大厅：asset.* / scene.set 入口已归位到游戏期', () {
    testWidgets('★ 招募期大厅：探索 / 素材 / 场景入口全部 findsNothing（附游戏期守卫）',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: false);
      useRoomScreen(tester, 900, 2200);
      final String id = seedRevealedAsset(f);

      // ★ P7：探索面板与素材行是游戏期能力，招募期大厅按 isInGame 门控
      //   后零渲染（KP / 玩家 / 旁观三种视角一致）。
      for (final String seat in <String>[kHostSeat, 'p1', 'sp1']) {
        await tester.pumpWidget(appFor(f, seat, const RoomLobbyPage()));
        await tester.pump();
        for (final Key k in <Key>[
          RoomLobbyKeys.explore,
          RoomLobbyKeys.addAsset,
          RoomLobbyKeys.sceneEdit,
          RoomLobbyKeys.assetRow(id),
          RoomLobbyKeys.assetReveal(id),
          RoomLobbyKeys.assetDel(id),
        ]) {
          expect(find.byKey(k), findsNothing,
              reason: '$seat 招募期大厅不该渲染游戏期探索/素材块 $k');
        }
        if (seat != kHostSeat) {
          expect(find.byKey(RoomKeys.kpStartGame), findsNothing,
              reason: '$seat 视角不该渲染「开始游戏」（room.start 只放 KP）');
        }
      }

      // ★ 正向守卫：这些能力没被删，游戏期由 RoomGamePage 的 slot 网格
      //   承载（A-2 group 逐键验证 map.* / asset.* 的第二入口）。
      await tester.pumpWidget(appFor(f, kHostSeat, const RoomGamePage()));
      await tester.pump();
      expect(find.byType(RoomGamePage), findsOneWidget);
    });

    testWidgets('即使把玩家硬塞进 KP 专属块，闸门也必须为 false（双保险）',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: false);
      useRoomScreen(tester, 900, 2200);

      for (final String op in <String>[
        'asset.add',
        'asset.cover',
        'asset.reveal',
        'asset.del',
        'scene.set',
        'room.start',
        'room.kick',
      ]) {
        expect(f.controllerOf('p1').gate.can(op), isFalse,
            reason: '玩家不该有 $op 权限');
        expect(f.controllerOf('sp1').gate.can(op), isFalse,
            reason: '旁观不该有 $op 权限');
      }
    });
  });

  group('A-2 游戏页：块 3 工具窄栏（map.* / asset.* 的第二入口）', () {
    testWidgets('整块 + 全部按钮对玩家 / 旁观 findsNothing', (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 1280, 800); // P10-2B：平板横屏档才会摊出全部槽位

      // ---- 反向守卫：KP 视角块在、按钮在、可点性恒等闸门
      await tester.pumpWidget(appFor(f, kHostSeat, const RoomGamePage()));
      await tester.pump();
      expect(find.byKey(GpKpToolsKeys.root), findsOneWidget,
          reason: 'KP 视角应渲染工具窄栏');
      // ★ P16 KP-10：`upload` 已从工具窄栏移走（唯一入口在左窄栏素材 tab），
      //   故探针表只剩 map.* 三件；asset.add 的探针改到左栏那一条。
      final Map<Key, String> toolOps = <Key, String>{
        GpKpToolsKeys.mark: 'map.mark',
        GpKpToolsKeys.draw: 'map.stroke',
        GpKpToolsKeys.erase: 'map.strokes.set',
      };
      toolOps.forEach((Key key, String op) {
        expect(enabledOf(tester, key), f.controllerOf(kHostSeat).gate.can(op),
            reason: 'KP 视角 $op 的可点性应恒等闸门');
      });
      // 正向反证：工具窄栏确实不再渲染 upload（探针表删掉它不是遗漏）。
      expect(find.byKey(GpKpToolsKeys.upload), findsNothing,
          reason: 'KP-10：工具窄栏不再有上传素材按钮');
      // asset.add 的第二入口：左窄栏素材 tab（切 tab 后才渲染）。
      f.localOf(kHostSeat).setTab('left', 2);
      await tester.pump();
      expect(find.byKey(GpKpLeftKeys.upload), findsOneWidget,
          reason: 'asset.add 的唯一入口在左窄栏素材 tab');
      expect(enabledOf(tester, GpKpLeftKeys.upload),
          f.controllerOf(kHostSeat).gate.can('asset.add'),
          reason: '左窄栏上传可点性应恒等闸门（T-30 原口径迁移）');
      expect(enabledOf(tester, GpKpToolsKeys.clear), isNull,
          reason: '`clear` 是 ConfirmTwice（key 挂在 ConfirmTwice 上），'
              '不是 RoomTap；存在性单独断言');
      expect(find.byKey(GpKpToolsKeys.clear), findsOneWidget,
          reason: 'KP 视角应能清除笔迹（map.clear 只放 KP）');

      // ---- 玩家 / 旁观
      for (final String seat in <String>['p1', 'sp1']) {
        await tester.pumpWidget(appFor(f, seat, const RoomGamePage()));
        await tester.pump();

        expect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpKpTools)), findsNothing,
            reason: '$seat 骨架里没有块 3（plSlots 不含 gpKpTools）');
        expect(find.byKey(GpKpToolsKeys.root), findsNothing,
            reason: '$seat 视角不该渲染工具窄栏');
        for (final Key key in <Key>[
          GpKpToolsKeys.mark,
          GpKpToolsKeys.draw,
          GpKpToolsKeys.erase,
          GpKpToolsKeys.placeActor,
          GpKpToolsKeys.placePlayer,
          GpKpToolsKeys.clear,
          GpKpToolsKeys.upload,
        ]) {
          expect(find.byKey(key), findsNothing,
              reason: '$seat 视角不该渲染 map.*/asset.* 入口');
        }
        // 玩家的素材舞台必须是只读的（readOnly=true → 手势回调为 null）
        expect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlMap)), findsOneWidget,
            reason: '$seat 视角应有素材舞台（只读）');
      }
    });
  });

  group('A-3 游戏页：scene.check.step（专用 key）', () {
    testWidgets('KP 有 6 档；玩家/旁观走的是另一块（KP 块 findsNothing）',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 1280, 800); // P10-2B：平板横屏档才会摊出全部槽位

      await tester.pumpWidget(appFor(f, kHostSeat, const RoomGamePage()));
      await tester.pump();
      expect(find.byKey(GpSceneCheckKeys.root), findsOneWidget,
          reason: 'KP 视角应渲染场景检定块');
      // ★ W-A 删 6 档：档位按钮已不存在（硬编码字面量；`enabledOf` 对不存在的 key 会抛异常＝假红）。
      for (final int lv in <int>[5, 4, 3, 2, 0, -1]) {
        expect(find.byKey(ValueKey<String>('gpSceneCheckKp/level/$lv')),
            findsNothing,
            reason: '删 6 档后第 $lv 档按钮不得再渲染');
      }
      // 正向：保留的两个动作按钮仍在。
      expect(find.byKey(GpSceneCheckKeys.quickPush), findsOneWidget);
      expect(find.byKey(GpSceneCheckKeys.editor), findsOneWidget);

      for (final String seat in <String>['p1', 'sp1']) {
        await tester.pumpWidget(appFor(f, seat, const RoomGamePage()));
        await tester.pump();
        expect(find.byKey(GpSceneCheckKeys.root), findsNothing,
            reason: '$seat 视角不该渲染 KP 的场景检定块');
        for (final int lv in <int>[5, 4, 3, 2, 0, -1]) {
          expect(find.byKey(ValueKey<String>('gpSceneCheckKp/level/$lv')),
              findsNothing,
              reason: '$seat 视角不该有第 $lv 档裁定按钮（scene.check.step 只放 KP）');
        }
        expect(find.byKey(GpSceneCheckPlKeys.root), findsOneWidget,
            reason: '$seat 视角应有玩家侧检定块（只读进度）');
      }
    });
  });

  group('A-4 游戏页：state.edit.self / state.self（专用 key）', () {
    testWidgets('玩家：状态管理入口在、弹层可开、提交真的发包', (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 1280, 800); // P10-2B：平板横屏档才会摊出全部槽位

      await tester.pumpWidget(appFor(f, 'p1', const RoomGamePage()));
      await tester.pump();
      expect(find.byKey(GpPlCharCardKeys.stateBtn), findsOneWidget,
          reason: '玩家应能自行管理状态（state.self 放 player）');

      await tester.tap(find.byKey(GpPlCharCardKeys.stateBtn));
      await tester.pumpAndSettle();
      expect(find.byKey(GpSelfStateKeys.root), findsOneWidget,
          reason: '状态管理弹层应能打开');
      expect(find.byKey(GpSelfStateKeys.submitNumbers), findsOneWidget,
          reason: '弹层里应有「提交数值」（state.edit.self 放 player）');

      f.clearSent();
      await tester.tap(find.byKey(GpSelfStateKeys.body('轻伤')));
      await tester.pumpAndSettle();
      expect(f.sent.where((Map<String, Object?> e) => e['op'] == 'state.self'),
          hasLength(1),
          reason: '玩家点「轻伤」应发出一条 state.self');
    });

    testWidgets('旁观：不该能发出 state.self / state.edit.self（点了零发包）',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 1280, 800); // P10-2B：平板横屏档才会摊出全部槽位

      await tester.pumpWidget(appFor(f, 'sp1', const RoomGamePage()));
      await tester.pump();

      // 旁观者没有「我的角色卡」语义：入口存在就是缺陷（先记录，再验发包）
      final Finder stateBtn = find.byKey(GpPlCharCardKeys.stateBtn);
      if (stateBtn.evaluate().isNotEmpty) {
        await tester.tap(stateBtn);
        await tester.pumpAndSettle();
        final Finder body = find.byKey(GpSelfStateKeys.body('轻伤'));
        if (body.evaluate().isNotEmpty) {
          f.clearSent();
          await tester.tap(body);
          await tester.pumpAndSettle();
        }
      }

      expect(f.sent.where((Map<String, Object?> e) => e['op'] == 'state.self'),
          isEmpty,
          reason: '旁观者点「轻伤」不该发出 state.self（POLICY 不含 spectator）');
      expect(
          f.sent.where((Map<String, Object?> e) => e['op'] == 'state.edit.self'),
          isEmpty,
          reason: '旁观者不该发出 state.edit.self');
    });

    testWidgets('旁观：入口结构性不渲染，零发包，权威态不变',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 1280, 800); // P10-2B：平板横屏档才会摊出全部槽位

      await tester.pumpWidget(appFor(f, 'sp1', const RoomGamePage()));
      await tester.pump();

      // ★ 已修复：旁观者没有「我的角色」语义（POLICY 的 `state.self` 只放
      //   player / kp）⇒ 入口**结构性不渲染**，与 T-20「撕卡后不渲染」同一口径。
      expect(find.byKey(GpPlCharCardKeys.stateBtn), findsNothing,
          reason: '旁观者不该渲染「状态管理」入口');
      expect(find.byKey(GpSelfStateKeys.root), findsNothing,
          reason: '旁观者页面上不该出现状态管理弹层');

      final Map<String, Object?> before = f.stateOf('sp1');
      f.clearSent();
      // 点遍页面上所有「可点」控件（含任何漏网的入口）
      final List<RoomTap> taps = tester
          .widgetList<RoomTap>(find.byType(RoomTap))
          .where((RoomTap t) => t.enabled)
          .toList();
      for (final RoomTap t in taps) {
        final Finder finder = find.byWidget(t);
        if (finder.evaluate().isEmpty) continue;
        await tester.tap(finder, warnIfMissed: false);
        await tester.pump();
      }
      expect(f.sent.where((Map<String, Object?> e) => e['op'] == 'state.self'),
          isEmpty, reason: '旁观者点遍页面不该发出 state.self：${f.sent}');
      expect(
          f.sent.where((Map<String, Object?> e) => e['op'] == 'state.edit.self'),
          isEmpty, reason: '旁观者不该发出 state.edit.self：${f.sent}');

      final Map<String, Object?> after = f.stateOf('sp1');
      expect(after['members'], before['members'],
          reason: '旁观者的权威态不该被改动');
    });

    testWidgets('双保险：强行打开弹层后点「轻伤」→ 仍零发包、不宣称「已更新」',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 2200);

      // 绕过入口门控，直接用 BuildContext 打开弹层 —— 验证**内层**门控。
      await tester.pumpWidget(appFor(
        f,
        'sp1',
        Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => openSelfStateSheet(ctx),
                child: const Text('强行打开'),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('强行打开'));
      await tester.pumpAndSettle();
      expect(find.byKey(GpSelfStateKeys.root), findsOneWidget,
          reason: '前提：弹层确实被打开了（否则下面的断言没有信息量）');

      final Map<String, Object?> before = f.stateOf('sp1');
      f.clearSent();
      await tester.tap(find.byKey(GpSelfStateKeys.body('轻伤')));
      await tester.pumpAndSettle();

      // ① 内层门控必须拦住发包
      expect(f.sent.where((Map<String, Object?> e) => e['op'] == 'state.self'),
          isEmpty, reason: '内层门控应拦住旁观者的 state.self：${f.sent}');

      // ② 权威态不变
      final Map<String, Object?> after = f.stateOf('sp1');
      expect(after['members'], before['members'],
          reason: '权威态不该被改动');

      // ③ UI 侧不得宣称成功（K7：不乐观提示成功）
      final String? notice = f.localOf('sp1').notice;
      // ignore: avoid_print
      print('[A-4] 旁观者强行点「轻伤」后的 local.notice = $notice');
      expect(notice, isNot(contains('已更新')),
          reason: '无权时却提示「$notice」—— 乐观提示成功，与 K7 口径冲突');
    });
  });

  // ==========================================================
  // 攻击面 B：combat.damage 的「纯闸门」两段式
  // ==========================================================

  group('B 战斗结算：有权限的玩家能否点到 combat.damage', () {
    testWidgets('玩家视角：enabled=false 且点了零发包（POLICY 只放 KP）',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 2200);

      await tester.pumpWidget(appFor(f, 'p1', const CombatSheet()));
      await tester.pump();

      expect(f.controllerOf('p1').gate.can('combat.damage'), isFalse,
          reason: '前提：POLICY 里 combat.damage 只放 KP');
      final Finder btn = find.byKey(RoomKeys.action('combat.damage'));
      expect(btn, findsOneWidget, reason: '弹层恒渲染结算按钮（可点性由闸门定）');
      expect(tester.widget<RoomTap>(btn).enabled, isFalse,
          reason: '玩家视角结算按钮必须禁用（enabled 恒等 gate.can）');

      f.clearSent();
      await tester.tap(btn, warnIfMissed: false);
      await tester.pump();
      expect(f.sent, isEmpty,
          reason: '玩家点禁用的结算按钮不该发包：${f.sent}');
    });

    testWidgets('旁观视角：同样禁用且零发包', (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 2200);

      await tester.pumpWidget(appFor(f, 'sp1', const CombatSheet()));
      await tester.pump();
      final Finder btn = find.byKey(RoomKeys.action('combat.damage'));
      expect(tester.widget<RoomTap>(btn).enabled, isFalse);
      f.clearSent();
      await tester.tap(btn, warnIfMissed: false);
      await tester.pump();
      expect(f.sent, isEmpty);
    });
  });

  // ==========================================================
  // T-20：撕卡后只能聊天
  // ==========================================================

  group('T-20 撕卡后只剩聊天', () {
    testWidgets('p1 被打到 HP 0 → 动作入口结构性隐藏，聊天输入仍在',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      // P10-2B：角色卡 / 手绘板 / 聊天在竖屏折叠档会收成方块，本用例要
      // 「三块同屏」，所以用平板横屏档（全部槽位都摊成真块）。
      useRoomScreen(tester, 1280, 800);

      // 走真实 action：KP 对 p1 施加致死伤害
      f.controllerOf(kHostSeat).hostAction('sheet.damage', <String, Object?>{
        'seat': 'p1',
        'amount': 99,
        'kind': '测试',
      });
      final Map<String, Object?> me = asMap(
        asList(f.stateOf('p1')['members'])
            .map(asMap)
            .firstWhere((Map<String, Object?> m) => m['seat'] == 'p1'),
      );
      // 前提确认：真的撕卡了（HP 0 / dying 或 body 死亡）
      final Map<String, Object?> st = asMap(asMap(me['sheet'])['status']);
      expect(
          (st['currentHP'] == 0) ||
              (st['dying'] == true) ||
              (st['body'] == '死亡'),
          isTrue,
          reason: '前提：p1 应已被打到濒死/死亡，实际 status=$st');

      await tester.pumpWidget(appFor(f, 'p1', const RoomGamePage()));
      await tester.pump();

      expect(find.byKey(GpPlCharCardKeys.locked), findsOneWidget,
          reason: '撕卡后应显示「只能聊天」提示');
      expect(find.byKey(GpPlCharCardKeys.stateBtn), findsNothing,
          reason: '撕卡后不该渲染「状态管理」入口');
      expect(find.byKey(RoomKeys.action('aid.apply')), findsNothing,
          reason: '撕卡后不该渲染「急救」');
      // ★ P20 需求 3②：手绘板不再常驻 dock（收进场景格里的全屏按钮），
      //   所以 canvas 的断言从「dock 里必在」改成「全屏里必在」——
      //   先证明按钮还在（看得到），再点开证明 canvas 在但不可落笔（更强）。
      expect(find.byKey(GpPlSketchKeys.canvas), findsNothing,
          reason: 'P20 需求3②：手绘板不再常驻 dock');
      expect(find.byKey(RoomGamePage.plSketchKey), findsOneWidget,
          reason: '撕卡后仍能打开手绘板查看');
      await tester.tap(find.byKey(RoomGamePage.plSketchKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(GpPlSketchKeys.canvas), findsOneWidget,
          reason: '全屏里手绘板容器仍在（只是不可画）');
      expect(find.byKey(GpPlSketchKeys.draw), findsNothing,
          reason: '撕卡后手绘板不可落笔');
      // ★ P20 需求 3②：全屏壳已从 `showRoomSheet`（底部弹层，点 (4,4) 打在
      //   modal barrier 上即关）改成 `showFullscreenReader`（**真路由** +
      //   AppBar）。真路由的返回键热区实测是 `LTRB(4.5, 4, 52.5, 52)`，
      //   老坐标 `(4,4)` 落在它左边缘**之外**（x=4 < 4.5）⇒ 点空、路由不关，
      //   于是下面「撕卡后仍能聊天」拿不到页面里的输入框。
      //   改成点弹层自带的关闭按钮（`FullscreenReader` 的 AppBar action），
      //   **不是**放宽断言：关不掉照样红。
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // ★ 转场（M3 默认页面转场）反向播完前路由不会被移出树，
      //   固定 400ms 不够 —— 必须 pumpAndSettle 才能稳定判定「已关闭」。
      await tester.pumpAndSettle();
      expect(find.byKey(GpPlSketchKeys.canvas), findsNothing,
          reason: '全屏手绘板必须真的关闭（关不掉就证明点击没落到关闭按钮）');
      expect(find.byKey(RoomKeys.gpChatInput), findsOneWidget,
          reason: '撕卡后仍能聊天');
    });
  });

  // ==========================================================
  // T-63：手绘板隔离
  // ==========================================================

  group('T-63 手绘板隔离', () {
    test('p1 落笔后 p2 / 旁观 / 权威 public 都看不到笔迹', () {
      final RoomUiFixture f = RoomUiFixture()..bootSync(inGame: true);

      f.controllerOf('p1').sendIntent('board', <String, Object?>{
        'strokes': <Object?>[
          <String, Object?>{'x': 0.1, 'y': 0.2},
          <String, Object?>{'x': 0.3, 'y': 0.4},
        ],
      });

      final List<Object?> mine =
          asList(asMap(f.stateOf('p1')['board'])['strokes']);
      expect(mine, hasLength(2), reason: '本人应收到自己的 2 个点');

      for (final String other in <String>['p2', 'sp1']) {
        final Map<String, Object?> board = asMap(f.stateOf(other)['board']);
        expect(asList(board['strokes']), isEmpty,
            reason: '$other 不该收到 p1 的笔迹：$board');
      }

      // KP 侧只经本机权威副本看到（不是经事件流广播）
      final Map<String, Object?>? boardOfP1 = f.host.boardBySeat['p1'];
      expect(asList(boardOfP1?['strokes']), hasLength(2),
          reason: 'KP 应通过 boardBySeat 拿到本机权威副本');
    });
  });

  // ==========================================================
  // 旁观者：全程零发包（T-06 的强化版：真实页面 + 真点）
  // ==========================================================

  group('T-06 旁观者零发包（游戏页真实点击）', () {
    testWidgets('点遍旁观页上所有可点控件 → sent 仍为 0',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 1280, 800); // P10-2B：平板横屏档才会摊出全部槽位
      await tester.pumpWidget(appFor(f, 'sp1', const RoomGamePage()));
      await tester.pump();

      f.clearSent();
      final List<RoomTap> taps = tester
          .widgetList<RoomTap>(find.byType(RoomTap))
          .where((RoomTap t) => t.enabled)
          .toList();
      // 旁观者的可点控件只应是「本地态」类（缩放 / 折叠 / 全屏 / 查看）
      for (final RoomTap t in taps) {
        final Finder finder = find.byWidget(t);
        if (finder.evaluate().isEmpty) continue;
        await tester.tap(finder, warnIfMissed: false);
        await tester.pump();
      }
      expect(f.sent, isEmpty,
          reason: '旁观者点遍页面不该发出任何 intent/action：${f.sent}');
    });
  });
}
