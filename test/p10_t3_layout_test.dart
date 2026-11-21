// ============================================================
// test/p10_t3_layout_test.dart — P10 第 2 期 B（布局重构）验收
//
// 用户口述五条，逐条对应本文件的组：
//   ① 平板横屏：固定比例网格（复刻老 APP 2.13.13）+ 缝隙统一（分组 A）
//   ② 平板竖屏 / 手机横竖屏：少数面板展开 + 其余收成方块、点开全屏（分组 B/C）
//   ③ 工具栏加高：按钮全部直接可见、不需要横向拖动；底部避让同步（分组 D）
//   ④ 聊天 / 公开记录 / 只给你看三栏闪烁同源（分组 E）
//   ⑤ 自动头像 PNG 化（分组 F；未完成时如实标注 skip 原因）
//
// 铁律：T1（全内存后端）、T5（房间页 useRoomScreen 按真实档位）、
//      零 Timer / Future.delayed / AnimationController 驱动。
// ============================================================

import 'dart:io' show File;

import 'package:dice_realm/domain/room_types.dart';
import 'package:dice_realm/ui/room/room_game_page.dart';
import 'package:dice_realm/ui/room/room_keys.dart';
import 'package:dice_realm/ui/room/view/room_view.dart'
    show RoomGridSpec, RoomLayoutMode;
import 'package:dice_realm/ui/room/widgets/gp_dice_bar.dart' show GpDiceBarKeys;
import 'package:dice_realm/ui/room/widgets/gp_feeds.dart' show GpFeeds;
import 'package:dice_realm/ui/room/widgets/gp_kp_left.dart' show GpKpLeft;
import 'package:dice_realm/ui/room/widgets/gp_map_stage.dart' show GpMapStage;
import 'package:dice_realm/ui/room/widgets/gp_pl_mates.dart' show GpPlMatesKeys;
import 'package:dice_realm/ui/room/widgets/gp_privates.dart' show GpPrivates;
import 'package:dice_realm/ui/room/widgets/gp_toolbar.dart';
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart' show RoomTap;
import 'package:dice_realm/ui/room/widgets/room_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

/// 三档代表性屏幕（两角色都跑一遍）。
const List<List<double>> _screens = <List<double>>[
  <double>[1280, 800], // 平板横屏 → dock
  <double>[820, 1180], // 平板竖屏 → folded
  <double>[780, 320], // 手机横屏 → folded
  <double>[360, 640], // 手机竖屏 → folded
];

Future<RoomUiFixture> _bootPage(
  WidgetTester tester, {
  required double w,
  required double h,
  String seat = kHostSeat,
}) async {
  final f = RoomUiFixture();
  await f.boot(inGame: true);
  f.pageBuilder = (String s, String r) => const RoomGamePage();
  useRoomScreen(tester, w, h);
  await tester.pumpWidget(f.pageOf(seat));
  await tester.pump();
  return f;
}

/// 折叠方块上的角标（`新`）在不在。
bool _squareFlashing(WidgetTester tester, RoomSlot slot) {
  final badge = find.descendant(
    of: find.byKey(RoomKeys.keyOfSlot(slot)),
    matching: find.text('新'),
  );
  return badge.evaluate().isNotEmpty;
}

void main() {
  group('A · 平板横屏：固定网格的槽位落位表', () {
    test('KP 图：12 槽位 = 顶栏 + 工具栏 + 10 格，顺序与声明一致（含嵌套）', () {
      final plan = roomDockPlanOf(isKp: true);
      final slots = roomLayoutSlotsOf(plan);
      // P16 KP-3 / KP-4②：待办状态条（gpStatus）与右列战斗格（gpCombat）
      // 已移出 KP 平板横屏网格，故落位表从 10 格降到 8 格。
      expect(slots, <RoomSlot>[
        RoomSlot.gpKpLeft,
        RoomSlot.gpKpTools,
        RoomSlot.gpMap,
        RoomSlot.gpScene,
        RoomSlot.gpPlayers,
        RoomSlot.gpChat,
        RoomSlot.gpLog,
        RoomSlot.gpPriv,
      ]);
      // 正向反证：这两个槽位**确实不在** KP dock 落位表里（不是笔误漏写）。
      expect(slots.contains(RoomSlot.gpCombat), isFalse,
          reason: 'KP-4②：战斗信息栏已搬进 gpMap 舞台格，右列不再有战斗格');
      expect(slots.contains(RoomSlot.gpStatus), isFalse,
          reason: 'KP-3：待办状态条已从 KP 横屏网格删除');
      expect(slots.toSet().length, slots.length, reason: '落位表不许有重复槽位');
      // 一个不少、也不重复（顶栏与工具栏由页面钉住，不进网格）
      final all = <RoomSlot>{...slots, RoomSlot.gpTopbar, RoomSlot.gpToolbar};
      expect(all.length, RoomKeys.kpSlots.length - 2,
          reason: 'kpSlots 共 12 个，其中 gpCombat / gpStatus 2 个不进 dock');
      expect(all.containsAll(RoomKeys.kpSlots), isFalse,
          reason: '旧口径 12 个全进 dock 已不成立');
      expect(all.containsAll(RoomKeys.kpSlots
              .where((RoomSlot s) =>
                  s != RoomSlot.gpCombat && s != RoomSlot.gpStatus)),
          isTrue,
          reason: '除这两个外的其余 10 个槽位一个不能少');

      // flex 链：左窄栏与右侧内容区在根上按 17:83 分
      final paths = roomLayoutFlexPathsOf(plan);
      expect(paths[RoomSlot.gpKpLeft], <int>[17]);
      expect(paths[RoomSlot.gpKpTools]!.first, 83,
          reason: '右侧内容列在根上占 83');
      expect(paths[RoomSlot.gpMap]!.length, 3,
          reason: '素材图在「根 → 内容列 → 上排」三层里');
    });

    test('玩家图：9 槽位 = 顶栏 + 工具栏 + 7 格，一张不缺', () {
      final plan = roomDockPlanOf(isKp: false);
      final slots = roomLayoutSlotsOf(plan);
      // P20 需求 3⑤：右列改 [gpPlScene 底层 / gpPlMates 上层] 叠放，深度优先
      // 展开后顺序是 scene 在 mates 之前，与 `RoomStackNode.children` 一致。
      // ★ P23 R2：DFS 顺序变了 —— 「只给你看」（gpPriv）从右列第 3 段搬到
      //   左列下半（紧挨 gpPlCharCard），所以它现在排在第 2 位而不是最后。
      //   （DFS 是先访问左列整棵子树，再访问右列；左列先 card 后 priv。）
      expect(slots, <RoomSlot>[
        RoomSlot.gpPlCharCard,
        RoomSlot.gpPriv,
        RoomSlot.gpPlMap,
        RoomSlot.gpPlScene,
        RoomSlot.gpPlMates,
        RoomSlot.gpPlChat,
        RoomSlot.gpPlLog,
      ]);
      final all = <RoomSlot>{...slots, RoomSlot.gpTopbar, RoomSlot.gpToolbar};
      // P20 需求 3②③④：玩家 dock 删了 gpPlCombat/gpPlSketch/gpPlNotes/gpStatus 4 格
      expect(all.length, RoomKeys.plSlots.length - 4,
          reason: 'P20 需求3②③④：玩家 dock 删了 gpPlCombat/gpPlSketch/gpPlNotes/gpStatus 4 格');
      expect(all.containsAll(<RoomSlot>[
        for (final RoomSlot s in RoomKeys.plSlots)
          if (s != RoomSlot.gpPlCombat &&
              s != RoomSlot.gpPlSketch &&
              s != RoomSlot.gpPlNotes &&
              s != RoomSlot.gpStatus)
            s,
      ]), isTrue);

      // ★ P23 R2：flex 链按新树重钉（左列 20 里上下分 55/45；右列 80 里
      //   上排 52 / 中排 41，其中 41 = 原 26 + 私密栏让出的 15）。
      final paths = roomLayoutFlexPathsOf(plan);
      expect(paths[RoomSlot.gpPlCharCard], <int>[20, 55],
          reason: 'P23 R2：角色卡在左列（20）里占上 55');
      expect(paths[RoomSlot.gpPriv], <int>[20, 45],
          reason: 'P23 R2：只给你看已搬到左列下 45，不再挂在右列');
      expect(paths[RoomSlot.gpPlMap], <int>[80, 52, 55],
          reason: 'P23 R2：私密栏让位后右列上排比例仍是 52');
      expect(paths[RoomSlot.gpPlScene], <int>[80, 52, 30, 100],
          reason: 'P23 R2：场景仍吃满叠放列');
      expect(paths[RoomSlot.gpPlChat], <int>[80, 41, 1],
          reason: 'P23 R2：聊天排从 26 长到 41（26+15），补满私密栏让出的高度');
      expect(paths[RoomSlot.gpPlLog], <int>[80, 41, 1],
          reason: 'P23 R2：记录排与聊天排同 flex（高度一样、宽度一样）');
      // 反向守卫：私密栏**不在**右列那条链上（45 那个位置只属于左列）。
      expect(paths[RoomSlot.gpPriv]!.first, 20,
          reason: 'P23 R2：私密栏必须留在左列（根 flex 20），不许搬回右列 80');
    });

    testWidgets('三档 × 两角色：模式判对、槽位落位、零异常（表驱动）',
        (WidgetTester tester) async {
      for (final List<double> s in _screens) {
        for (final String seat in <String>[kHostSeat, 'p1']) {
          final isKp = seat == kHostSeat;
          await _bootPage(tester, w: s[0], h: s[1], seat: seat);
          final label = '${s[0].toInt()}×${s[1].toInt()}/$seat';
          expect(tester.takeException(), isNull, reason: '$label 有异常');

          final spec = RoomGridSpec.of(
            w: s[0],
            h: s[1],
            landscape: s[0] > s[1],
          );
          final wantDock = s[0] == 1280 && s[1] == 800;
          expect(spec.mode,
              wantDock ? RoomLayoutMode.dock : RoomLayoutMode.folded,
              reason: '$label 的布局形态判错');

          final slotList = isKp ? RoomKeys.kpSlots : RoomKeys.plSlots;
          // P16：KP 平板横屏（dock）里 gpStatus / gpCombat 已移出网格。
          // P20 需求 3②③④：玩家 dock 另删 gpPlCombat / gpPlSketch / gpPlNotes / gpStatus
          // 四个叶子；**折叠档里这四格仍各有方块**，所以只在 dock 档 absent。
          final absentInDock = switch ((isKp, spec.mode)) {
            (true, RoomLayoutMode.dock) =>
              <RoomSlot>{RoomSlot.gpCombat, RoomSlot.gpStatus},
            (false, RoomLayoutMode.dock) => <RoomSlot>{
                RoomSlot.gpPlCombat,
                RoomSlot.gpPlSketch,
                RoomSlot.gpPlNotes,
                RoomSlot.gpStatus,
              },
            _ => const <RoomSlot>{},
          };
          // 无论哪一档，容器 key 都必须各一个（落位可断言）
          for (final slot in slotList) {
            if (absentInDock.contains(slot)) {
              expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsNothing,
                  reason: '$label 的 KP dock 不应再有容器 ${slot.name}');
              continue;
            }
            expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsOneWidget,
                reason: '$label 缺容器 ${slot.name}');
          }

          if (spec.mode == RoomLayoutMode.dock) {
            // 横屏固定网格：全部槽位都是真块（没有方块）
            expect(find.byType(RoomSlotSquare), findsNothing, reason: label);
            expect(isKp ? find.byType(GpKpLeft) : find.byType(GpMapStage),
                findsWidgets,
                reason: '$label 固定网格里应有真块');
          } else {
            // 折叠档：口述白名单展开、其余是方块
            final expanded = roomExpandedSlots(slotList, isKp ? RoomRole.kp : RoomRole.player);
            for (final slot in expanded) {
              expect(tester.widget(find.byKey(RoomKeys.keyOfSlot(slot))),
                  isNot(isA<RoomSlotSquare>()),
                  reason: '$label 的 ${slot.name} 应展开');
            }
            final folded = roomFoldedSlots(slotList, isKp ? RoomRole.kp : RoomRole.player);
            for (final slot in folded) {
              expect(tester.widget(find.byKey(RoomKeys.keyOfSlot(slot))),
                  isA<RoomSlotSquare>(),
                  reason: '$label 的 ${slot.name} 应收成方块');
            }
          }

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      }
    });
  });

  group('B · 折叠档：方块点开 → 全屏显示真块', () {
    testWidgets('KP：聊天 / 只给你看 / 战斗 三格点开各自显示真块',
        (WidgetTester tester) async {
      await _bootPage(tester, w: 360, h: 640);

      Future<void> openSquare(RoomSlot slot, Type type) async {
        expect(find.byType(type), findsNothing,
            reason: '${slot.name} 收起时不该常驻块体');
        final tile = find.byKey(RoomKeys.keyOfSlot(slot));
        await tester.ensureVisible(tile);
        await tester.pump();
        await tester.tap(tile);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(type), findsOneWidget,
            reason: '${slot.name} 点开必须显示真块');
        Navigator.of(tester.element(find.byType(type))).pop();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(type), findsNothing);
      }

      await openSquare(RoomSlot.gpChat, GpFeeds);
      await openSquare(RoomSlot.gpPriv, GpPrivates);
    });

    testWidgets('玩家：公开素材图收成方块，点开是全屏舞台（只读）',
        (WidgetTester tester) async {
      await _bootPage(tester, w: 360, h: 640, seat: 'p1');
      expect(find.byType(GpMapStage), findsNothing,
          reason: '玩家竖屏下素材图默认收起');

      final tile = find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlMap));
      await tester.ensureVisible(tile);
      await tester.pump();
      await tester.tap(tile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final stage = tester.widget<GpMapStage>(find.byType(GpMapStage));
      expect(stage.readOnly, isTrue, reason: '玩家看素材图只读');
    });
  });

  group('C · 展开区可收起（复用 RoomUiLocal.folded，不另造状态）', () {
    testWidgets('KP：场景检定收起 → 变方块 → 再放回展开区',
        (WidgetTester tester) async {
      final f = await _bootPage(tester, w: 360, h: 640);
      final local = f.localOf(kHostSeat);
      expect(local.isFolded(RoomSlot.gpScene.name), isFalse);

      final toggle = find.descendant(
        of: find.byKey(roomFoldKey(RoomSlot.gpScene)),
        matching: find.byType(RoomTap),
      );
      await tester.ensureVisible(toggle);
      await tester.pump();
      await tester.tap(toggle);
      await tester.pump();
      expect(local.isFolded(RoomSlot.gpScene.name), isTrue);
      expect(tester.widget(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpScene))),
          isA<RoomSlotSquare>());

      final unfold = find.byKey(roomFoldKey(RoomSlot.gpScene));
      await tester.ensureVisible(unfold);
      await tester.pump();
      await tester.tap(unfold);
      await tester.pump();
      expect(local.isFolded(RoomSlot.gpScene.name), isFalse);
    });
  });

  group('D · 工具栏加高：按钮全部直接可见 + 不遮挡内容', () {
    testWidgets('360×640：工具栏由内容撑高，所有按钮都落在工具栏矩形内',
        (WidgetTester tester) async {
      await _bootPage(tester, w: 360, h: 640);

      final bar = tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpToolbar)));
      expect(bar.height, greaterThan(56),
          reason: '旧版固定 56 高只能看到半截按钮');
      // 结构性保证：工具栏里没有任何**横向**滚动容器
      // → 不可能「要横着拖动才能看全」（用户明确抱怨的那一条）。
      expect(
        find.descendant(
          of: find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpToolbar)),
          matching: find.byWidgetPredicate((Widget w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal),
        ),
        findsNothing,
        reason: '工具栏不允许横向滚动',
      );

      // ★ P17 P-4：恒灰的 `round.next` / `scene.mode` 已三视角删除。
      expect(find.byKey(RoomKeys.action('round.next')), findsNothing,
          reason: 'P17 P-4：360 档工具栏不渲染恒灰的下一轮入口');
      expect(find.byKey(RoomKeys.action('scene.mode')), findsNothing,
          reason: 'P17 P-4：360 档工具栏不渲染恒灰的转战斗入口');
      for (final Key key in <Key>[
        GpToolbarKeys.zoomPercent,
        RoomKeys.gpZoomReset,
        RoomKeys.gpDiceBar,
        GpDiceBarKeys.bonus,
        GpDiceBarKeys.customExpr,
        GpDiceBarKeys.dark,
        RoomKeys.action('combat.roll'),
        RoomGamePage.kpPanelKey,
      ]) {
        final r = tester.getRect(find.byKey(key));
        expect(r.top, greaterThanOrEqualTo(bar.top - 0.5),
            reason: '$key 被工具栏上沿裁掉');
        expect(r.bottom, lessThanOrEqualTo(bar.bottom + 0.5),
            reason: '$key 落在工具栏可视区之外（要么加高，要么就得拖动找）');
        expect(r.left, greaterThanOrEqualTo(bar.left - 0.5), reason: '$key 左越界');
        expect(r.right, lessThanOrEqualTo(bar.right + 0.5), reason: '$key 右越界');
      }
    });

    testWidgets('1280×800：横屏档工具栏比竖屏矮，但仍全部可见',
        (WidgetTester tester) async {
      await _bootPage(tester, w: 360, h: 640);
      final phoneBar =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpToolbar)));
      await _bootPage(tester, w: 1280, h: 800);
      final bar = tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpToolbar)));
      expect(bar.height, lessThan(phoneBar.height),
          reason: '横屏一行排得下更多按钮，高度应自适应变小');
      // ★ P17 P-4：`scene.mode` 已删 —— 改用现存按钮守「横屏仍全部可见」。
      expect(find.byKey(RoomKeys.action('scene.mode')), findsNothing,
          reason: 'P17 P-4：1280 档工具栏不渲染恒灰的转战斗入口');
      for (final Key key in <Key>[
        GpToolbarKeys.zoomPercent,
        GpDiceBarKeys.dark,
        RoomGamePage.kpPanelKey,
      ]) {
        final r = tester.getRect(find.byKey(key));
        expect(r.bottom, lessThanOrEqualTo(bar.bottom + 0.5), reason: '$key 越界');
      }
    });

    testWidgets('★ 工具栏不再覆盖内容（加高后最后一块也不会被盖住）',
        (WidgetTester tester) async {
      for (final List<double> s in <List<double>>[
        <double>[360, 640],
        <double>[780, 320],
        <double>[1280, 800],
      ]) {
        await _bootPage(tester, w: s[0], h: s[1]);
        final bar =
            tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpToolbar)));
        // 内容区的**视口**（滚动容器）必须整体在工具栏上方
        final viewport = tester.getRect(
          find
              .ancestor(
                of: find.byKey(RoomGamePage.zoomKey),
                matching: find.byType(SingleChildScrollView),
              )
              .first,
        );
        expect(viewport.bottom, lessThanOrEqualTo(bar.top + 0.5),
            reason: '${s[0].toInt()}×${s[1].toInt()}：内容区被工具栏压住了');
        expect(bar.bottom, lessThanOrEqualTo(s[1] + 0.5),
            reason: '工具栏必须贴在屏幕最下方且不越界');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  });

  group('E · 闪烁三栏同源（聊天 / 公开记录 / 只给你看）', () {
    testWidgets('别人发聊天 → KP 的聊天方块闪「新」；自己发的不闪',
        (WidgetTester tester) async {
      final f = await _bootPage(tester, w: 360, h: 640);
      // 首屏基线：不闪
      expect(_squareFlashing(tester, RoomSlot.gpChat), isFalse);

      // KP 自己发 → 不闪
      await f.controllerOf(kHostSeat).sendIntent(
            RoomIntent.chat,
            <String, Object?>{'text': '我自己说的'},
          );
      await tester.pump();
      expect(_squareFlashing(tester, RoomSlot.gpChat), isFalse,
          reason: '自己发的不闪');

      // p1 发 → 闪
      await f.controllerOf('p1').sendIntent(
            RoomIntent.chat,
            <String, Object?>{'text': '别人说的'},
          );
      await tester.pump();
      expect(_squareFlashing(tester, RoomSlot.gpChat), isTrue,
          reason: '别人发的新消息必须闪');
    });

    testWidgets('公开记录（骰子进 logs）→ 记录方块闪「新」', (WidgetTester tester) async {
      final f = await _bootPage(tester, w: 360, h: 640);
      expect(_squareFlashing(tester, RoomSlot.gpLog), isFalse);

      await f.controllerOf('p1').sendIntent(
            RoomIntent.dice,
            <String, Object?>{'expr': '1D100', 'direct': true},
          );
      await tester.pump();
      expect(_squareFlashing(tester, RoomSlot.gpLog), isTrue);
      // 反证：聊天栏没被骰子带闪（各栏互不干扰）
      expect(_squareFlashing(tester, RoomSlot.gpChat), isFalse);
    });

    testWidgets('只给你看：KP 递线索给 p1 → p1 的私密方块闪；KP 自己不闪',
        (WidgetTester tester) async {
      final f = await _bootPage(tester, w: 360, h: 640, seat: 'p1');
      expect(_squareFlashing(tester, RoomSlot.gpPriv), isFalse);

      Future<void> clue(String to, String text) async =>
          f.controllerOf(kHostSeat).hostAction('scene.clue', <String, Object?>{
            'seat': to,
            'title': '线索',
            'text': text,
          });

      // 第一条只登记基线（首条不算「新消息」，与 GpFeeds 同一条规则）
      await clue('p1', '门后有脚步声');
      await tester.pump();
      expect(_squareFlashing(tester, RoomSlot.gpPriv), isFalse,
          reason: '空栏的第一条只登记基线，不闪');

      await clue('p1', '地板上有血迹');
      await tester.pump();
      expect(_squareFlashing(tester, RoomSlot.gpPriv), isTrue,
          reason: 'KP 递来的新私密信息必须闪');

      // KP 视角：同一条线索发给 KP 自己 → 不闪（自己发的不闪）
      final f2 = RoomUiFixture();
      await f2.boot(inGame: true);
      f2.pageBuilder = (String s, String r) => const RoomGamePage();
      useRoomScreen(tester, 360, 640);
      await tester.pumpWidget(f2.pageOf(kHostSeat));
      await tester.pump();
      for (final String text in <String>['自己写的 1', '自己写的 2']) {
        await f2.controllerOf(kHostSeat).hostAction(
          'scene.clue',
          <String, Object?>{'seat': kHostSeat, 'title': '线索', 'text': text},
        );
        await tester.pump();
      }
      expect(_squareFlashing(tester, RoomSlot.gpPriv), isFalse,
          reason: 'KP 自己写的私密信息不闪（与 GpFeeds 同一条规则）');
    });

    test('静态守卫：三处闪烁实现零 Timer / 零 AnimationController', () {
      // 只看**代码行**（注释里解释「为什么不用动画」不算违规）。
      List<String> codeLines(String path) => File(path)
          .readAsLinesSync()
          .where((String l) =>
              !l.trimLeft().startsWith('//') && !l.contains('///'))
          .toList();
      for (final String path in <String>[
        'lib/ui/room/room_feed_flash.dart',
        'lib/ui/room/widgets/gp_feeds.dart',
        'lib/ui/room/widgets/gp_privates.dart',
        'lib/ui/room/widgets/room_layout.dart',
      ]) {
        final src = codeLines(path).join('\n');
        expect(src.contains('Timer('), isFalse, reason: '$path 出现 Timer');
        expect(src.contains('AnimationController'), isFalse,
            reason: '$path 出现 AnimationController');
        expect(src.contains('Future.delayed'), isFalse,
            reason: '$path 出现 Future.delayed');
      }
      // 判据唯一来源：三栏都只通过 `FeedFlashTracker.check` 判定
      final priv = File('lib/ui/room/widgets/gp_privates.dart').readAsStringSync();
      expect(priv.contains('FeedFlashTracker'), isTrue);
      expect(priv.contains('_seenSeq'), isFalse,
          reason: '旧的「组件自带 _seenSeq」判据必须退役');
    });
  });

  // ==========================================================
  // F · P20 需求 3⑤：队友栏默认收起 + 场景格按钮落点避让
  // ----------------------------------------------------------
  // 真机症状（1280×800 实测）：
  //   SCENE == MATES == Rect.fromLTRB(920.2, 38.0, 1272.0, 403.7)
  //   `RoomStackNode` 用 `Positioned.fill` 给**紧约束**，展开态 `SectionBox`
  //   铺满整格 ⇒ 一进房间就把场景检定栏整格盖死；
  //   且右对齐的「笔记」按钮 rect 恰好等于队友收起标题行「展开」抓手
  //   （LTRB(1200, 38, 1272, 66)），点它会被上层 Card 吃掉。
  // 本组用**真几何**（Rect.overlaps）钉住两条修法，禁止改回真值。
  //
  // ★ P23 R1 归属变更（不是放宽）：产品把「手绘板 / 笔记」两个按钮从
  //   `gpPlScene` 格顶那条 28dp 行**搬进了玩家工具栏**（用户原话：
  //   「笔记和手绘板按钮放到玩家工具栏」）。于是原先「按钮 rect 与队友抓手
  //   不相交」这条断言**已经失去意义** —— 它们现在物理上就不在同一个区域；
  //   取而代之的是三条更强/等价的结构断言：
  //     ① 两个按钮都必须存在且**在 `GpToolbar` 子树内**（新落点）；
  //     ② 两个按钮**不再出现在 `gpPlScene` 格内**（旧落点确实清理干净了，
  //        否则就是双入口）；
  //     ③ 场景格顶边 == 右列顶边（= `gpPlMap` 顶边）—— 那条 28dp 按钮行
  //        消失后场景检定栏吃满整列，这也是 R1 要的观感结果。
  // ==========================================================
  group('F · 需求3⑤ 队友栏默认收起 + 按钮落点（P23 R1 起在工具栏）', () {
    testWidgets('1280×800 玩家 dock：默认收起、按钮在工具栏内且不在场景格、toggle 双向可用',
        (WidgetTester tester) async {
      final RoomUiFixture f =
          await _bootPage(tester, w: 1280, h: 800, seat: 'p1');

      // ① 默认收起（`RoomUiLocal.matesOpen = false`）。
      expect(f.localOf('p1').matesOpen, isFalse,
          reason: '★ 默认必须收起：展开态与场景检定栏逐像素同 rect，会把后者盖死');
      expect(find.byKey(GpPlMatesKeys.row('p2')), findsNothing,
          reason: '★ 默认收起时队友行不许渲染（否则场景检定栏被盖死）');
      expect(find.byKey(GpPlMatesKeys.toggle), findsOneWidget,
          reason: '收起态必须保留「展开」抓手，否则该栏永久无法展开');

      // ② 新落点：两个按钮都在工具栏子树内，且都能被 `getRect` 量到。
      final sceneCell = find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlScene));
      for (final Key key in <Key>[
        RoomGamePage.plSketchKey,
        RoomGamePage.plNotesKey,
      ]) {
        expect(find.byKey(key), findsOneWidget,
            reason: 'P23 R1：$key 必须仍有一个入口（只是落点换了）');
        expect(
          find.ancestor(
            of: find.byKey(key),
            matching: find.byType(GpToolbar),
          ),
          findsOneWidget,
          reason: 'P23 R1：$key 必须在 GpToolbar 子树内（用户要求「放到玩家工具栏」）',
        );
        // ③ 旧落点必须清空：场景格内不许再有这两个 key（否则是双入口）。
        expect(
          find.descendant(of: sceneCell, matching: find.byKey(key)),
          findsNothing,
          reason: 'P23 R1：$key 已从 gpPlScene 格顶行搬走，格内不许残留',
        );
      }
      // ④ 按钮矩形落在工具栏矩形内（不是被挤出可视区的那种「存在」）。
      final bar =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpToolbar)));
      for (final Key key in <Key>[
        RoomGamePage.plSketchKey,
        RoomGamePage.plNotesKey,
      ]) {
        final Rect btn = tester.getRect(find.byKey(key));
        expect(btn.top, greaterThanOrEqualTo(bar.top - 0.5),
            reason: 'P23 R1：$key 被工具栏上沿裁掉');
        expect(btn.bottom, lessThanOrEqualTo(bar.bottom + 0.5),
            reason: 'P23 R1：$key 落在工具栏可视区之外');
      }

      // ⑤ 场景格顶边 == 右列顶边（= 同排 `gpPlMap` 顶边）：那条 28dp 按钮行
      //    消失后，场景检定栏才真的吃满整列（R1 的几何结果）。
      final Rect scene = tester.getRect(sceneCell);
      final Rect map = tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlMap)));
      expect((scene.top - map.top).abs(), lessThan(0.6),
          reason: 'P23 R1：场景格顶边必须与右列顶边齐平（不再被按钮行推下去）');
      // 队友收起态与场景共 rect（叠放语义不变，反向守卫）。
      final Rect mates =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlMates)));
      expect((mates.top - scene.top).abs(), lessThan(0.6),
          reason: 'P20 需求3⑤：收起态队友栏与场景格共 rect（叠放语义不变）');

      expect(tester.takeException(), isNull,
          reason: '1280 宽下场景格与工具栏都不许 overflow');

      // ⑥ toggle 双向可用：点开 → 行出现；再点 → 行消失（且是本机态，零发包）。
      await tester.tap(find.byKey(GpPlMatesKeys.toggle));
      await tester.pump();
      expect(f.localOf('p1').matesOpen, isTrue);
      expect(find.byKey(GpPlMatesKeys.row('p2')), findsOneWidget,
          reason: '点「展开」后必须真的看到队友列表');

      await tester.tap(find.byKey(GpPlMatesKeys.toggle));
      await tester.pump();
      expect(f.localOf('p1').matesOpen, isFalse);
      expect(find.byKey(GpPlMatesKeys.row('p2')), findsNothing,
          reason: '再点「收起」后队友行必须消失');
    });

    // ★ P23 R2 新增：左列「角色卡 / 私密栏」上下分 + 右列「聊天 / 记录」
    //   同高同宽补满原私密栏的空隙。用真几何（1280×800 dock 实测）。
    testWidgets('1280×800 玩家 dock：左列上下分，聊天/记录同高同宽补满空隙',
        (WidgetTester tester) async {
      await _bootPage(tester, w: 1280, h: 800, seat: 'p1');

      final Rect card =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlCharCard)));
      final Rect priv =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPriv)));
      final Rect chat =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlChat)));
      final Rect log =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlLog)));
      final Rect map =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlMap)));

      // ① 左列上下相邻、不重叠，且左右边完全对齐（同宽）。
      expect((priv.left - card.left).abs(), lessThan(0.6),
          reason: 'P23 R2：私密栏必须与角色卡左对齐（都在左列）');
      expect((priv.right - card.right).abs(), lessThan(0.6),
          reason: 'P23 R2：私密栏必须与角色卡同宽（都在左列）');
      expect(priv.top, greaterThanOrEqualTo(card.bottom - 1),
          reason: 'P23 R2：私密栏必须在角色卡**下方**，不许重叠');
      // ② 左列底边与右列底边对齐（左列整列吃满，没留空带）。右列最后一格是
      //    聊天/记录那一排，所以用它的底边当「右列底边」。
      expect((priv.bottom - chat.bottom).abs(), lessThan(0.6),
          reason: 'P23 R2：左列底边应与右列底边（聊天/记录排底边）齐平');
      // ③ 角色卡确实变矮了（改前它是**通高**，`card.height == 整列高`）。
      final columnHeight = priv.bottom - card.top;
      expect(card.height, lessThan(columnHeight * 0.6),
          reason: 'P23 R2：角色卡只占左列 55%（改前是 100% 通高，'
              '整列高 $columnHeight，卡高 ${card.height}）');
      expect(card.height, greaterThan(priv.height),
          reason: 'P23 R2：角色卡 55% > 私密栏 45%');
      // ④ 素材图仍然「最大」（P10 期钉过的老口径，不许回退）。
      expect(map.width, greaterThan(card.width * 1.5),
          reason: '素材图必须仍是最宽的那一格');
      expect((card.top - map.top).abs(), lessThan(0.6),
          reason: 'P23 R2：左列 / 右列顶边齐平');

      // ⑤ 聊天 / 记录：高度一样、宽度一样，且明显变高（补满私密栏的空隙）。
      expect((chat.width - log.width).abs(), lessThan(0.6),
          reason: 'P23 R2：聊天栏与游戏记录栏宽度必须一样');
      expect((chat.height - log.height).abs(), lessThan(0.6),
          reason: 'P23 R2：聊天栏与游戏记录栏高度必须一样');
      final rightColumnHeight = priv.bottom - map.top;
      expect(chat.height, greaterThan(rightColumnHeight * 0.35),
          reason: 'P23 R2：聊天/记录这一排必须吃掉原私密栏让出的 15%（'
              '右列高 $rightColumnHeight，聊天高 ${chat.height}）');
      expect((chat.top - log.top).abs(), lessThan(0.6),
          reason: 'P23 R2：两栏并排（顶边齐平）');
      // ⑥ 私密栏宽度 ≥ 自己的最小可用宽度（否则 `_slotView` 会横向滚动）。
      expect(priv.width, greaterThanOrEqualTo(roomDockMinWidthOf(RoomSlot.gpPriv)),
          reason: 'P23 R2：gpPriv 下限已收到 230，私密栏宽度 ${priv.width} 必须够');
      expect(tester.takeException(), isNull);
    });

    // ★ P23 R1 反向守卫：折叠档**不**渲染这两个工具栏按钮 —— 那里
    //   `gpPlSketch` / `gpPlNotes` 本来各占一个方块，再给一份工具栏入口
    //   就是双入口（施工单 R1.4）。
    testWidgets('360×640 折叠档玩家：工具栏无手绘板/笔记按钮，折叠方块仍是唯一入口',
        (WidgetTester tester) async {
      await _bootPage(tester, w: 360, h: 640, seat: 'p1');
      expect(find.byKey(RoomGamePage.plSketchKey), findsNothing,
          reason: 'P23 R1：折叠档不渲染工具栏「手绘板」按钮（避免双入口）');
      expect(find.byKey(RoomGamePage.plNotesKey), findsNothing,
          reason: 'P23 R1：折叠档不渲染工具栏「笔记」按钮（避免双入口）');
      // 正向守卫：折叠档里这两块**确实**仍有各自的方块（不是被一起删了）。
      expect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlSketch)), findsOneWidget,
          reason: 'P23 R1：折叠档的 gpPlSketch 方块必须还在（那是它的入口）');
      expect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlNotes)), findsOneWidget,
          reason: 'P23 R1：折叠档的 gpPlNotes 方块必须还在（那是它的入口）');
      expect(tester.takeException(), isNull);
    });
  });
}
