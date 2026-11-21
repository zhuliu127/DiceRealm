// ============================================================
// test/room_ui_layout_test.dart — 布局 / 缩放验收
//
// 历史：P5/T02 S2.2 + S2.4（Wrap 两列 + 单列折叠头）。
// P10 第 2 期 B 按用户口述整体改版为**两档**布局：
//   · 平板横屏 → 固定比例网格（复刻老 APP 2.13.13），声明在
//     `roomDockPlanOf`，行列共用同一个 gap；
//   · 平板竖屏 / 手机横屏 / 手机竖屏 → 少数面板展开 + 其余收成方块。
// 本文件随之改写：**旧断言换成新期望 + 补正向守卫**（不是删断言）。
//
// 铁律：T5（房间页必须用 useRoomScreen 按真实档位测，不能用 useTallScreen）。
//
// 覆盖：
//   · 网格唯一真相源：RoomGridSpec 五档阈值 + 新档位 `mode`（纯 Dart 断言）
//   · 折叠档：展开白名单 / 方块落位 / 收起后可放回 / 12·13 容器一个不少
//   · 平板横屏：固定网格的行列对齐（同一 gap）+ 大素材图占最大面积
//   · compact 收紧方块间距（几何反证）
//   · 缩放：Transform.scale 数值随档位变化（60/70/80/90/100）+ 重置
//   · ★ 结构断言：gpToolbar 与 gpTopbar 都不在任何 Transform 子树里
// ============================================================

import 'package:dice_realm/domain/room_types.dart';
import 'package:dice_realm/ui/room/room_game_page.dart';
import 'package:dice_realm/ui/room/room_keys.dart';
import 'package:dice_realm/ui/room/room_theme.dart';
import 'package:dice_realm/ui/room/view/room_view.dart'
    show RoomGridSpec, RoomLayoutMode;
import 'package:dice_realm/ui/room/widgets/gp_feeds.dart' show GpFeeds;
import 'package:dice_realm/ui/room/widgets/gp_map_stage.dart' show GpMapStage;
import 'package:dice_realm/ui/room/widgets/gp_toolbar.dart';
import 'package:dice_realm/ui/room/widgets/room_layout.dart' show RoomSlotSquare;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

/// 用夹具的 `pageBuilder` 注入点接上真页面。
Future<RoomUiFixture> _bootPage(
  WidgetTester tester, {
  required double w,
  required double h,
  bool inGame = false,
  String seat = kHostSeat,
}) async {
  final f = RoomUiFixture();
  await f.boot(inGame: inGame);
  f.pageBuilder = (String s, String r) => const RoomGamePage(
        toolbarExtensions: <Widget>[
          PlaceholderBlock(key: ValueKey<String>('ext/probe'), label: '骰子条'),
        ],
      );
  useRoomScreen(tester, w, h);
  await tester.pumpWidget(f.pageOf(seat));
  await tester.pump();
  return f;
}

/// 读缩放容器当前的 scale。
double _zoomOf(WidgetTester tester) {
  final t = tester.widget<Transform>(find.byKey(RoomGamePage.zoomKey));
  return t.transform.entry(0, 0);
}

/// 某个槽位块是否被 Transform 包着（反查祖先链）。
bool _hasTransformAncestor(WidgetTester tester, Key slotKey) {
  final el = tester.element(find.byKey(slotKey));
  var found = false;
  el.visitAncestorElements((Element a) {
    if (a.widget is Transform) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

void main() {
  group('S2.2 · 网格唯一真相源（纯 Dart）', () {
    test('五档阈值：宽屏 / 窄带 / 极矮 / compact 各自判对', () {
      // 360×640 竖屏手机 → 单列、不 compact
      final phone = RoomGridSpec.of(w: 360, h: 640, landscape: false);
      expect(phone.grid, isFalse);
      expect(phone.compact, isFalse);

      // 780×320 横屏平板 → 多列 + compact（h ≤ 360）
      final pad = RoomGridSpec.of(w: 780, h: 320, landscape: true);
      expect(pad.grid, isTrue);
      expect(pad.compact, isTrue);

      // 780×400 横屏 → 多列、不 compact
      final padTall = RoomGridSpec.of(w: 780, h: 400, landscape: true);
      expect(padTall.grid, isTrue);
      expect(padTall.compact, isFalse);

      // 520–599 窄带 → 即使高度够也单列（旧版把这一档误判成 compact 的坑）
      for (final w in <double>[520, 560, 599]) {
        final narrow = RoomGridSpec.of(w: w, h: 800, landscape: true);
        expect(narrow.grid, isFalse, reason: '窄带 w=$w 必须单列');
        expect(narrow.compact, isFalse, reason: '单列永远不是 compact');
      }

      // 极矮（h < 290）→ 单列
      final flat = RoomGridSpec.of(w: 900, h: 280, landscape: true);
      expect(flat.grid, isFalse);
      expect(flat.compact, isFalse);

      // 阈值常量只在这一处出现（引用即可，不另造数字）
      expect(RoomGridSpec.wide, 820);
      expect(RoomGridSpec.narrowLo, 520);
      expect(RoomGridSpec.narrowHi, 599);
      expect(RoomGridSpec.minH, 290);
      expect(RoomGridSpec.compactH, 360);
      expect(RoomGridSpec.dockShortSide, 560);
    });

    test('★ 布局形态：只有「平板横屏」走固定网格，其余一律折叠档', () {
      // 平板横屏（短边 ≥ 560）→ dock
      for (final List<double> s in <List<double>>[
        <double>[1280, 800],
        <double>[1180, 820],
        <double>[1024, 768],
      ]) {
        final spec = RoomGridSpec.of(w: s[0], h: s[1], landscape: true);
        expect(spec.mode, RoomLayoutMode.dock,
            reason: '${s[0].toInt()}×${s[1].toInt()} 是平板横屏，应走固定网格');
        expect(spec.dock, isTrue);
      }

      // 手机横屏（短边 320–430）→ folded（用户口述 ② 含手机横屏）
      for (final List<double> s in <List<double>>[
        <double>[780, 320],
        <double>[900, 420],
      ]) {
        final spec = RoomGridSpec.of(w: s[0], h: s[1], landscape: true);
        expect(spec.mode, RoomLayoutMode.folded,
            reason: '${s[0].toInt()}×${s[1].toInt()} 是手机横屏，应走折叠档');
      }

      // 平板竖屏 / 手机竖屏 → folded
      for (final List<double> s in <List<double>>[
        <double>[820, 1180],
        <double>[360, 640],
      ]) {
        final spec = RoomGridSpec.of(w: s[0], h: s[1], landscape: false);
        expect(spec.mode, RoomLayoutMode.folded);
      }

      // 反证：`dock` 恒含于 `grid`（不会出现「不是多列却走固定网格」）
      final narrow = RoomGridSpec.of(w: 560, h: 800, landscape: true);
      expect(narrow.grid, isFalse);
      expect(narrow.dock, isFalse);
    });

    test('折叠档：展开白名单按口述（KP 三块 / 玩家两块），方块表补齐其余',
        () {
      expect(roomExpandedSlots(RoomKeys.kpSlots, RoomRole.kp),
          <RoomSlot>[
            RoomSlot.gpKpLeft,
            RoomSlot.gpKpTools,
            RoomSlot.gpMap,
            RoomSlot.gpScene
          ]);
      expect(roomExpandedSlots(RoomKeys.plSlots, RoomRole.player),
          <RoomSlot>[RoomSlot.gpPlCharCard, RoomSlot.gpPlScene]);

      final kpFolded = roomFoldedSlots(RoomKeys.kpSlots, RoomRole.kp);
      // 12 个槽位 = 顶栏 + 工具栏 + 4 展开（含 gpKpTools）+ 6 方块
      expect(kpFolded.length, 6);
      expect(kpFolded, isNot(contains(RoomSlot.gpTopbar)));
      expect(kpFolded, isNot(contains(RoomSlot.gpToolbar)));
      expect(kpFolded, contains(RoomSlot.gpChat));
      expect(kpFolded, contains(RoomSlot.gpLog));
      expect(kpFolded, contains(RoomSlot.gpPriv));

      final plFolded = roomFoldedSlots(RoomKeys.plSlots, RoomRole.player);
      // 13 个槽位 = 顶栏 + 工具栏 + 2 展开 + 9 方块
      expect(plFolded.length, 9);

      // 一个不少：展开 ∪ 方块 ∪ {顶栏, 工具栏} == 全部槽位（无重复、无丢失）
      for (final MapEntry<List<RoomSlot>, String> e
          in <MapEntry<List<RoomSlot>, String>>[
        MapEntry<List<RoomSlot>, String>(RoomKeys.kpSlots, RoomRole.kp),
        MapEntry<List<RoomSlot>, String>(RoomKeys.plSlots, RoomRole.player),
      ]) {
        final all = <RoomSlot>{
          ...roomExpandedSlots(e.key, e.value),
          ...roomFoldedSlots(e.key, e.value),
          RoomSlot.gpTopbar,
          RoomSlot.gpToolbar,
        };
        expect(all.length, e.key.length,
            reason: '${e.value} 侧槽位在展开区/方块区之间不能重复或丢失');
      }
    });

    test('单列档私密栏提到内容区第一位；多列档保持原序', () {
      final single = RoomGridSpec.of(w: 360, h: 640, landscape: false);
      final ordered = roomOrderedContentSlots(RoomKeys.kpSlots, single);
      expect(ordered.first, RoomSlot.gpPriv);
      expect(ordered.contains(RoomSlot.gpTopbar), isFalse,
          reason: '顶栏钉在顶部，不参与滚动内容');
      expect(ordered.contains(RoomSlot.gpToolbar), isFalse,
          reason: '工具栏钉在底部，不参与滚动内容');
      expect(ordered.length, 10);

      final grid = RoomGridSpec.of(w: 780, h: 400, landscape: true);
      final orderedGrid = roomOrderedContentSlots(RoomKeys.kpSlots, grid);
      expect(orderedGrid.first, RoomSlot.gpKpLeft, reason: '多列档不打乱顺序');
      expect(orderedGrid.contains(RoomSlot.gpPriv), isTrue);

      // 玩家骨架同样适用（13 → 11 个内容块）
      final plOrdered = roomOrderedContentSlots(RoomKeys.plSlots, single);
      expect(plOrdered.length, 11);
      expect(plOrdered.first, RoomSlot.gpPriv);
    });

    test('compact 收紧间距（纯函数，不量像素也能锁死）', () {
      final compact = RoomGridSpec.of(w: 780, h: 320, landscape: true);
      final normal = RoomGridSpec.of(w: 780, h: 400, landscape: true);
      expect(roomBlockGap(compact), 4.0);
      expect(roomBlockGap(normal), RoomTheme.panelGap);
      expect(roomBlockGap(compact), lessThan(roomBlockGap(normal)));
    });

    test('槽位标题与折叠头 key 稳定（不随渲染变化）', () {
      expect(roomSlotTitle(RoomSlot.gpChat), '聊天');
      expect(roomSlotTitle(RoomSlot.gpPriv), '私密栏');
      expect(roomSlotTitle(RoomSlot.gpPlSketch), '手绘板');
      expect(roomFoldKey(RoomSlot.gpChat),
          const ValueKey<String>('gpFold/gpChat'));
    });
  });

  group('S2.2 · 折叠档（平板竖屏 / 手机横竖屏）', () {
    testWidgets('360×640 竖屏 KP：展开三块是真块，其余是方块，零异常',
        (WidgetTester tester) async {
      final f = await _bootPage(tester, w: 360, h: 640);
      expect(tester.takeException(), isNull);

      final spec = RoomGridSpec.of(w: 360, h: 640, landscape: false);
      expect(spec.mode, RoomLayoutMode.folded);

      // 展开区：地图 / 素材栏 / 场景检定 都是真块（正向守卫）
      expect(
          find.descendant(
              of: find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpMap)),
              matching: find.byType(GpMapStage)),
          findsOneWidget,
          reason: '公开素材图片栏必须展开且是真块');
      expect(find.byKey(roomFoldKey(RoomSlot.gpKpLeft)), findsOneWidget,
          reason: '展开区带头部（可收起）');
      expect(find.byKey(roomFoldKey(RoomSlot.gpMap)), findsOneWidget);
      expect(find.byKey(roomFoldKey(RoomSlot.gpScene)), findsOneWidget);

      // 方块区：聊天是方块（标题 + 摘要），块体不在树里
      final chatSquare = find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpChat));
      expect(chatSquare, findsOneWidget);
      expect(tester.widget(chatSquare), isA<RoomSlotSquare>());
      expect(find.byType(GpFeeds), findsNothing,
          reason: '收成方块后块体不应常驻（点开才全屏显示）');
      expect(find.textContaining('聊天 ·'), findsOneWidget,
          reason: '方块必须显示一行摘要');

      // 12 个容器一个不少（非懒构建）
      for (final slot in RoomKeys.kpSlots) {
        expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsOneWidget,
            reason: '缺容器 ${slot.name}');
      }
      expect(f.booted, isTrue);
    });

    testWidgets('360×640 竖屏玩家：角色卡与场景检定展开，素材图收成方块',
        (WidgetTester tester) async {
      await _bootPage(tester, w: 360, h: 640, seat: 'p1');
      expect(tester.takeException(), isNull);

      expect(find.byKey(roomFoldKey(RoomSlot.gpPlCharCard)), findsOneWidget);
      expect(find.byKey(roomFoldKey(RoomSlot.gpPlScene)), findsOneWidget);
      // 口述口径：玩家侧只有「角色信息面板 + 场景检定」常驻
      final mapSquare = find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlMap));
      expect(tester.widget(mapSquare), isA<RoomSlotSquare>());
      for (final slot in RoomKeys.plSlots) {
        expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsOneWidget,
            reason: '缺容器 ${slot.name}');
      }
    });

    testWidgets('780×320 手机横屏：折叠档、12 个容器全在、零异常',
        (WidgetTester tester) async {
      await _bootPage(tester, w: 780, h: 320);
      expect(tester.takeException(), isNull);
      final spec = RoomGridSpec.of(w: 780, h: 320, landscape: true);
      expect(spec.mode, RoomLayoutMode.folded,
          reason: '手机横屏按口述属于折叠档，不是平板横屏的固定网格');
      for (final slot in RoomKeys.kpSlots) {
        expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsOneWidget,
            reason: '缺容器 ${slot.name}');
      }
    });

    testWidgets('展开区可收起：收起后退回方块区，仍是同一个槽位容器',
        (WidgetTester tester) async {
      final f = await _bootPage(tester, w: 360, h: 640);
      final local = f.localOf(kHostSeat);
      expect(local.isFolded(RoomSlot.gpMap.name), isFalse);

      // 点展开区头部的「收起」（先滚进视口，内容区在折叠档是要滚的）
      final header = find.byKey(roomFoldKey(RoomSlot.gpMap));
      final toggle =
          find.descendant(of: header, matching: find.byType(RoomTap));
      await tester.ensureVisible(toggle);
      await tester.pump();
      await tester.tap(toggle);
      await tester.pump();

      expect(local.isFolded(RoomSlot.gpMap.name), isTrue);
      expect(tester.widget(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpMap))),
          isA<RoomSlotSquare>(),
          reason: '收起后应退化成方块（复用 RoomUiLocal.folded，不另造一套）');

      // 方块右上角的「展开到面板」把它放回展开区
      final unfold = find.byKey(roomFoldKey(RoomSlot.gpMap));
      await tester.ensureVisible(unfold);
      await tester.pump();
      await tester.tap(unfold);
      await tester.pump();
      expect(local.isFolded(RoomSlot.gpMap.name), isFalse);
      expect(
          find.descendant(
              of: find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpMap)),
              matching: find.byType(GpMapStage)),
          findsOneWidget);
    });

    testWidgets('compact 收紧方块间距（几何反证，不是常量自证）',
        (WidgetTester tester) async {
      // 常规档：780×400（grid=true、不 compact → 折叠档）
      await _bootPage(tester, w: 780, h: 400);
      final normalSpec = RoomGridSpec.of(w: 780, h: 400, landscape: true);
      expect(normalSpec.compact, isFalse);
      final nA =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpCombat)));
      final nB =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlayers)));
      expect(nB.top, nA.top, reason: '同一排方块（780 宽排得下 7 个 104dp 方块）');
      final normalGap = nB.left - nA.right;

      // compact 档：780×320
      await _bootPage(tester, w: 780, h: 320);
      final compactSpec = RoomGridSpec.of(w: 780, h: 320, landscape: true);
      expect(compactSpec.compact, isTrue);
      final cA =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpCombat)));
      final cB =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlayers)));
      final compactGap = cB.left - cA.right;

      expect(compactGap, lessThan(normalGap),
          reason: 'compact 档间距必须更紧（$compactGap vs $normalGap）');
      expect(normalGap, moreOrLessEquals(RoomTheme.panelGap, epsilon: 0.6));
      expect(compactGap, moreOrLessEquals(4.0, epsilon: 0.6));
    });
  });

  group('S2.2 · 平板横屏：固定比例网格（复刻老 APP）', () {
    testWidgets('1280×800 KP：左窄栏与工具窄栏同一行、列间距与行间距同源',
        (WidgetTester tester) async {
      await _bootPage(tester, w: 1280, h: 800);
      expect(tester.takeException(), isNull);

      final spec = RoomGridSpec.of(w: 1280, h: 800, landscape: true);
      expect(spec.mode, RoomLayoutMode.dock);
      final gap = roomBlockGap(spec);

      final kpLeft =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpKpLeft)));
      final kpTools =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpKpTools)));
      final map = tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpMap)));
      final scene =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpScene)));
      final chat = tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpChat)));
      final log = tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpLog)));

      // 同一行：左窄栏 / 工具窄栏 / 素材图的顶边一致（对齐）
      expect(kpTools.top, kpLeft.top);
      expect(map.top, kpLeft.top);

      // 列间距 = 行间距 = 同一个 gap（用户抱怨的「栏位没对齐」）
      expect(kpTools.left - kpLeft.right, moreOrLessEquals(gap, epsilon: 0.6));
      expect(map.left - kpTools.right, moreOrLessEquals(gap, epsilon: 0.6));
      expect(chat.top - map.bottom, moreOrLessEquals(gap, epsilon: 0.6),
          reason: '行间距必须与列间距同一个 gap');
      expect(log.left - chat.right, moreOrLessEquals(gap, epsilon: 0.6));

      // 大块占主要面积：素材图比任何一条竖窄条都宽得多
      expect(map.width, greaterThan(kpLeft.width * 1.5));
      expect(map.width, greaterThan(scene.width * 1.5));

      // 素材图在整页里是最大的那一块（面积比较，不看文案）
      final mapArea = map.width * map.height;
      // ★ P16 KP-4②：gpCombat 已搬进素材舞台格、不再是独立槽位，
      //   故面积比较的对手里去掉它（其余槽位一个不减）。
      for (final slot in <RoomSlot>[
        RoomSlot.gpKpLeft,
        RoomSlot.gpKpTools,
        RoomSlot.gpScene,
        RoomSlot.gpPlayers,
        RoomSlot.gpChat,
        RoomSlot.gpPriv,
      ]) {
        final r = tester.getRect(find.byKey(RoomKeys.keyOfSlot(slot)));
        expect(mapArea, greaterThan(r.width * r.height),
            reason: '${slot.name} 不该比素材图还大');
      }

      // 12 个容器里除去 P16 移出网格的 gpCombat / gpStatus，其余一个不少
      const Set<RoomSlot> retired = <RoomSlot>{
        RoomSlot.gpCombat,
        RoomSlot.gpStatus,
      };
      for (final slot in RoomKeys.kpSlots) {
        if (retired.contains(slot)) {
          expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsNothing,
              reason: 'P16：${slot.name} 已移出 KP 平板横屏网格，不该再渲染');
          continue;
        }
        expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsOneWidget,
            reason: '缺容器 ${slot.name}');
      }
      // 固定网格里没有折叠头（用户给的红块图没有折叠条）
      expect(find.byKey(roomFoldKey(RoomSlot.gpChat)), findsNothing);
    });

    testWidgets('1280×800 玩家：左列角色卡 + 私密栏上下分、素材图最大、13 个容器全在',
        (WidgetTester tester) async {
      await _bootPage(tester, w: 1280, h: 800, seat: 'p1');
      expect(tester.takeException(), isNull);

      final spec = RoomGridSpec.of(w: 1280, h: 800, landscape: true);
      expect(spec.mode, RoomLayoutMode.dock);
      final gap = roomBlockGap(spec);

      final card = tester
          .getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlCharCard)));
      final map =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlMap)));
      // ★ P20 需求 3②：`gpPlSketch` 叶子已删（手绘板改为按钮入口）。
      expect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlSketch)), findsNothing,
          reason: 'P20 需求3②：玩家 dock 已删 gpPlSketch');

      // ★ P23 R2：角色卡**不再通高**（用户：「『我的角色卡』栏位可以拉短
      //   一些高度」），「只给你看」搬进左列下半。所以本题的标题与断言从
      //   「角色卡通高」改成「左列上下分」—— 换成**更强**的结构断言：
      //   同宽、上下相邻、左列底边与右列底边对齐、卡比私密栏高。
      final priv =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPriv)));
      final chat =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlChat)));
      final log =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlLog)));

      // ① 私密栏与角色卡**同宽、同一条左边**（都在左列）。
      expect(priv.left, moreOrLessEquals(card.left, epsilon: 0.6));
      expect(priv.right, moreOrLessEquals(card.right, epsilon: 0.6));
      // ② 上下相邻、不重叠（角色卡在上）。
      expect(priv.top, greaterThanOrEqualTo(card.bottom - 1),
          reason: 'P23 R2：私密栏必须在角色卡下方（改前它在右列第 3 段）');
      // ③ 左列底边与右列底边对齐（内容区没留空带）。右列最后一格是聊天/
      //   记录那一排 —— 用它的底边当「右列底边」。
      //   ★ 施工单原文写的是 `priv.bottom == map.bottom`，但 `gpPlMap` 只是
      //     右列**上排**的一格，它的底边在整列 55.9% 处，与左列底边不可能
      //     相等。这里改用等价且可证伪的「与右列最后一排底边对齐」，
      //     并补一条 `priv.bottom > map.bottom` 正向守卫。
      expect(priv.bottom, moreOrLessEquals(chat.bottom, epsilon: 0.6),
          reason: 'P23 R2：左列底边必须与右列底边齐平（不许留空带）');
      expect(priv.bottom, moreOrLessEquals(log.bottom, epsilon: 0.6));
      expect(priv.bottom, greaterThan(map.bottom),
          reason: 'P23 R2：左列必须比右列上排更长（私密栏落在上排下方）');
      // ④ 角色卡确实变矮了：55% vs 私密栏 45%，且明显短于整列。
      expect(card.height, greaterThan(priv.height),
          reason: 'P23 R2：角色卡 55% > 私密栏 45%');
      expect(card.height, lessThan(priv.bottom - card.top - 1),
          reason: 'P23 R2：角色卡不再通高（必须把下半让给私密栏）');
      // ⑤ 素材图仍是最宽的那一格（老口径不许回退）+ 顶边对齐 + 列间距同一个 gap。
      expect(map.width, greaterThan(card.width * 1.5));
      expect(card.top, moreOrLessEquals(map.top, epsilon: 0.6));
      expect(map.left - card.right, moreOrLessEquals(gap, epsilon: 0.6));
      // ⑥ 聊天 / 记录：同高同宽，且高度明显 > 只占 26/93 时的水平
      //   （P23 R2 把私密栏让出的 15 全给了这一排）。
      expect(chat.width, moreOrLessEquals(log.width, epsilon: 0.6));
      expect(chat.height, moreOrLessEquals(log.height, epsilon: 0.6));
      expect(chat.height, greaterThan((priv.bottom - map.top) * 0.35),
          reason: 'P23 R2：聊天/记录排必须补满原私密栏的空隙');

      const Set<RoomSlot> absentInPlDock = <RoomSlot>{
        RoomSlot.gpPlCombat,
        RoomSlot.gpPlSketch,
        RoomSlot.gpPlNotes,
        RoomSlot.gpStatus,
      };
      for (final slot in RoomKeys.plSlots) {
        if (absentInPlDock.contains(slot)) {
          expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsNothing,
              reason: 'P20 需求3②③④：玩家 dock 已删 ${slot.name}');
          continue;
        }
        expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsOneWidget,
            reason: '缺容器 ${slot.name}');
      }
    });
  });

  group('S2.4 · 缩放', () {
    testWidgets('默认 100%；点百分比按钮循环到 60%；重置回 100%',
        (WidgetTester tester) async {
      final f = await _bootPage(tester, w: 360, h: 640);
      final local = f.localOf(kHostSeat);

      expect(local.zoom, 1.0);
      expect(_zoomOf(tester), 1.0);
      expect(find.text('100%'), findsOneWidget);

      await tester.tap(find.byKey(GpToolbarKeys.zoomPercent));
      await tester.pump();
      expect(local.zoom, 0.6, reason: '100% 之后循环到最小档');
      expect(_zoomOf(tester), 0.6);
      expect(find.text('60%'), findsOneWidget);

      await tester.tap(find.byKey(GpToolbarKeys.zoomPercent));
      await tester.pump();
      expect(local.zoom, 0.7);
      expect(_zoomOf(tester), 0.7);

      await tester.tap(find.byKey(RoomKeys.gpZoomReset));
      await tester.pump();
      expect(local.zoom, 1.0);
      expect(_zoomOf(tester), 1.0);
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('缩放夹取在 [0.6, 1.0]（超界值不进 Transform）',
        (WidgetTester tester) async {
      final f = await _bootPage(tester, w: 360, h: 640);
      final local = f.localOf(kHostSeat);

      local.setZoom(0.1);
      await tester.pump();
      expect(_zoomOf(tester), 0.6);

      local.setZoom(3.0);
      await tester.pump();
      expect(_zoomOf(tester), 1.0);
    });
  });

  group('S2.4 · ★ 结构断言：工具栏与顶栏在缩放容器之外', () {
    testWidgets('gpToolbar / gpTopbar 的祖先链上没有 Transform',
        (WidgetTester tester) async {
      await _bootPage(tester, w: 360, h: 640);

      // 反证：内容块确实在 Transform 里（否则下面的断言可能是「恰好为空」）
      expect(_hasTransformAncestor(tester, RoomKeys.keyOfSlot(RoomSlot.gpChat)),
          isTrue,
          reason: '内容区必须被缩放容器包着，否则结构断言是假绿');
      expect(
          _hasTransformAncestor(tester, RoomKeys.keyOfSlot(RoomSlot.gpPriv)),
          isTrue);

      // 正断言：工具栏 / 顶栏都不在缩放容器里
      expect(
          _hasTransformAncestor(tester, RoomKeys.keyOfSlot(RoomSlot.gpToolbar)),
          isFalse,
          reason: '旧版 transform:scale() 生成 containing block 导致工具条失效，'
              'P5 用结构（兄弟节点）排除这一整类问题');
      expect(
          _hasTransformAncestor(tester, RoomKeys.keyOfSlot(RoomSlot.gpTopbar)),
          isFalse);

      // 再补一层：工具栏与内容区是同一个 Column 的兄弟节点（P10-2B 从
      // Stack+Positioned 改成 Column 的最后一格，结构与「不遮挡」都更好守）。
      final barEl =
          tester.element(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpToolbar)));
      var hasColumn = false;
      barEl.visitAncestorElements((Element a) {
        if (a.widget is Column) {
          hasColumn = true;
          return false;
        }
        return true;
      });
      expect(hasColumn, isTrue);
      // 内容区底边不越过工具栏顶边（结构上不可能被盖住）
      final bar =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpToolbar)));
      final viewport = tester.getRect(
        find
            .ancestor(
              of: find.byKey(RoomGamePage.zoomKey),
              matching: find.byType(SingleChildScrollView),
            )
            .first,
      );
      expect(viewport.bottom, lessThanOrEqualTo(bar.top + 0.5));
      // ★ P10 第 3 期 B：只断言「底边 ≤ 栏顶」是单向判据 —— 内容区被
      //   压到 25dp（甚至 0）也照样全绿。补一条最小可用高度，让
      //   「内容区真的有视口」成为双向可证伪的断言。
      expect(viewport.height, greaterThan(120),
          reason: '内容区视口必须有可用高度，不许被压成一条缝还判通过');
    });

    testWidgets('缩放变化不影响工具栏位置（工具条不跟着缩）',
        (WidgetTester tester) async {
      final f = await _bootPage(tester, w: 360, h: 640);
      final before =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpToolbar)));
      f.localOf(kHostSeat).setZoom(0.6);
      await tester.pump();
      final after =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpToolbar)));
      expect(after.top, before.top);
      expect(after.height, before.height);
      expect(after.height, greaterThan(56),
          reason: 'P10-2B：工具栏加高到「按钮全显示」（旧版 56 高要横向拖动）');
    });
  });
}
