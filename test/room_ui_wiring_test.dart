// ============================================================
// test/room_ui_wiring_test.dart — P5 接线验收（T02 页面 × T03/T04 真块）
//
// 这一轮只做一件事：把 `room_game_page.dart` 里剩下的 `PlaceholderBlock`
// 换成真块，并证明「接线确实接上了」——不是「看起来调用了」。
//
// 铁律：T1（全内存后端）、T5（房间页按真实档位 pump）、
//      T8（跨视角用夹具按 seat 建的会话）、T-K15（注入真页面再断言容器 key）。
//
// 五条硬断言（team-lead 指定）：
//   ① KP 侧 `PlaceholderBlock` == 0（12 个槽位全有真内容，K-01）
//   ② 玩家侧 `PlaceholderBlock` == 0（T05 五块接线后 K-01 两侧同时达成）
//   ③ `MapStageControl` 单实例：gpMap 与 gpKpTools 拿到的是 `identical` 的同一份
//   ④ `gpToolbar` 仍无 `Transform` 祖先（含新增的骰子条 / KP 入口 / 注入扩展）
//   ⑤ 12 / 13 个容器 key 仍各自 `findsOneWidget`（不因接线退化）
// ============================================================

import 'package:dice_realm/domain/room_types.dart';
import 'package:dice_realm/ui/room/room_game_page.dart';
import 'package:dice_realm/ui/room/room_keys.dart';
import 'package:dice_realm/ui/room/widgets/gp_combat_list.dart';
import 'package:dice_realm/ui/room/widgets/gp_feeds.dart';
import 'package:dice_realm/ui/room/widgets/gp_kp_left.dart';
import 'package:dice_realm/ui/room/widgets/gp_kp_players.dart';
import 'package:dice_realm/ui/room/widgets/gp_kp_tools.dart';
import 'package:dice_realm/ui/room/widgets/gp_map_stage.dart';
import 'package:dice_realm/ui/room/widgets/gp_pl_char_card.dart';
import 'package:dice_realm/ui/room/widgets/gp_pl_mates.dart';
import 'package:dice_realm/ui/room/widgets/gp_pl_notes.dart';
import 'package:dice_realm/ui/room/widgets/gp_pl_sketch.dart';
import 'package:dice_realm/ui/room/widgets/gp_privates.dart';
import 'package:dice_realm/ui/room/widgets/gp_scene_check_kp.dart';
import 'package:dice_realm/ui/room/widgets/gp_scene_check_pl.dart';
import 'package:dice_realm/ui/room/widgets/gp_status.dart';
import 'package:dice_realm/ui/room/widgets/gp_toolbar.dart' show GpToolbar;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

/// 用**默认**扩展装配真页面（不注入任何 PlaceholderBlock 探针）。
///
/// ★ 默认档位 = 平板横屏（1280×800）：P10 第 2 期 B 之后，只有这一档
///   会把 12 / 13 个槽位**全部**摊成真块；竖屏 / 手机档按用户口述收成方块，
///   本组「全槽位都有真块」的断言因此在这档做，语义不外移、强度不降。
Future<RoomUiFixture> _bootPage(
  WidgetTester tester, {
  String seat = kHostSeat,
  double w = 1280,
  double h = 800,
}) async {
  final f = RoomUiFixture();
  await f.boot();
  f.pageBuilder = (String s, String r) => const RoomGamePage();
  useRoomScreen(tester, w, h);
  await tester.pumpWidget(f.pageOf(seat));
  await tester.pump();
  return f;
}

/// 某个槽位子树里有没有某类型。
Finder _inSlot(RoomSlot slot, Type type) => find.descendant(
      of: find.byKey(RoomKeys.keyOfSlot(slot)),
      matching: find.byType(type),
    );

/// 该 key 是否落在**缩放容器**（`RoomGamePage.zoomKey`）的子树里。
///
/// ★ 不用「祖先里有任意 Transform」：Material 3 的拉伸回弹
///   （`StretchingOverscrollIndicator`）本身就在每个滚动视图里插了一个
///   Transform，那是框架 chrome，不是我们的缩放容器 —— 拿它做断言会误红。
///   真正要守的是「工具栏不进缩放容器」，所以直接按 zoomKey 反查祖先。
bool _inZoomHost(Key key) => find
    .ancestor(of: find.byKey(key), matching: find.byKey(RoomGamePage.zoomKey))
    .evaluate()
    .isNotEmpty;

void main() {
  group('接线 · 槽位 → 真块', () {
    testWidgets('★ K-01：KP 侧 dock 10 个槽位全部是真块，PlaceholderBlock == 0',
        (WidgetTester tester) async {
      await _bootPage(tester);
      expect(tester.takeException(), isNull);

      expect(find.byType(PlaceholderBlock), findsNothing,
          reason: '★ K-01：KP 侧不许再有占位块');
      expect(RoomKeys.kpSlots, hasLength(12),
          reason: 'kpSlots 声明表仍是 12 项（折叠档照旧 12 格）');

      // 逐块点名，避免「占位没了但换成别的空壳」
      expect(_inSlot(RoomSlot.gpKpLeft, GpKpLeft), findsOneWidget);
      expect(_inSlot(RoomSlot.gpKpTools, GpKpTools), findsOneWidget);
      expect(_inSlot(RoomSlot.gpMap, GpMapStage), findsOneWidget);
      expect(_inSlot(RoomSlot.gpScene, GpSceneCheckKp), findsOneWidget);
      expect(_inSlot(RoomSlot.gpPlayers, GpKpPlayers), findsOneWidget);
      expect(_inSlot(RoomSlot.gpChat, GpFeeds), findsOneWidget);
      expect(_inSlot(RoomSlot.gpLog, GpFeeds), findsOneWidget);
      expect(_inSlot(RoomSlot.gpPriv, GpPrivates), findsOneWidget);

      // ★ P16 KP-3 / KP-4②：dock 里这两格已不存在 —— 关键不是「换个空壳」，
      //   而是**整个槽位容器都不建**；战斗列表只在战斗态搬进 gpMap（下方用例
      //   `战斗态` 专门断言），待办条则彻底退出 KP 横屏。
      expect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpCombat)), findsNothing,
          reason: 'KP-4②：右列战斗格已移出 dock，容器不该再渲染');
      expect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpStatus)), findsNothing,
          reason: 'KP-3：待办状态条已移出 dock，容器不该再渲染');
      expect(find.byType(GpStatus), findsNothing,
          reason: 'KP dock 非战斗态下不该有任何待办条实体');
    });

    testWidgets('★ K-01：玩家 dock 9 个真块 + 4 个已删叶子，PlaceholderBlock == 0',
        (WidgetTester tester) async {
      await _bootPage(tester, seat: 'p1');
      expect(tester.takeException(), isNull);

      expect(find.byType(PlaceholderBlock), findsNothing,
          reason: '★ K-01：T05 收尾后玩家侧也不许再有占位块');
      // 枚举契约不变（plSlots 仍 13 项）；但 dock 只渲染 13-4=9 格。
      expect(RoomKeys.plSlots, hasLength(13));

      // 逐块点名（保留项），避免「占位没了但换成别的空壳」
      expect(_inSlot(RoomSlot.gpPlCharCard, GpPlCharCard), findsOneWidget);
      expect(_inSlot(RoomSlot.gpPlScene, GpSceneCheckPl), findsOneWidget);
      expect(_inSlot(RoomSlot.gpPlMates, GpPlMates), findsOneWidget);

      // 玩家侧的 T03 块已接上，且舞台是只读
      expect(_inSlot(RoomSlot.gpPlChat, GpFeeds), findsOneWidget);
      expect(_inSlot(RoomSlot.gpPlLog, GpFeeds), findsOneWidget);
      // ★ 新事实：`GpMapStage` 现在被 `_combatStageCell` 包着，只在
      //   「非战斗态 或 `plCombatPanelCollapsed == true`」时存在；
      //   本用例是非战斗 fixture，故该断言仍成立（战斗态由下方用例覆盖）。
      expect(_inSlot(RoomSlot.gpPlMap, GpMapStage), findsOneWidget);
      final stage = tester.widget<GpMapStage>(_inSlot(RoomSlot.gpPlMap, GpMapStage));
      expect(stage.readOnly, isTrue, reason: '玩家/旁观侧舞台必须只读');

      // ★ P20 需求 3②③④：4 个 dock 叶子已删（容器整个不建）
      for (final RoomSlot slot in <RoomSlot>[
        RoomSlot.gpPlCombat,
        RoomSlot.gpPlSketch,
        RoomSlot.gpPlNotes,
        RoomSlot.gpStatus,
      ]) {
        expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsNothing,
            reason: 'P20：玩家 dock 已删 ${slot.name} 容器');
      }
      // ★ P23 R2：「只给你看」搬进左列，紧跟角色卡**下方**（改前挂在右列
      //   第 3 段，与角色卡不同列）。这里用真几何断言「在左列内且紧邻卡下方」，
      //   比原来只数「容器各一个」更强。
      expect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPriv)), findsOneWidget,
          reason: 'P23 R2：私密栏在玩家 dock 只渲染一个容器');
      final Rect cardRect =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlCharCard)));
      final Rect privRect =
          tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPriv)));
      expect(privRect.left, moreOrLessEquals(cardRect.left, epsilon: 0.6),
          reason: 'P23 R2：私密栏与角色卡同一条左边（都在左列）');
      expect(privRect.right, moreOrLessEquals(cardRect.right, epsilon: 0.6),
          reason: 'P23 R2：私密栏与角色卡同宽（都在左列）');
      expect(privRect.top, greaterThanOrEqualTo(cardRect.bottom - 1),
          reason: 'P23 R2：私密栏必须在角色卡正下方');
      // ★ P23 R1：入口**从 `gpPlScene` 格顶行搬到了玩家工具栏**（用户原话：
      //   「笔记和手绘板按钮放到玩家工具栏」）。所以这里从「只要存在」升级成
      //   「存在 **且** 在 `GpToolbar` 子树内 **且** 不在场景格内」——
      //   更强、且能挡住「两个落点并存 ⇒ 双入口」这类回退。
      for (final Key key in <Key>[
        RoomGamePage.plSketchKey,
        RoomGamePage.plNotesKey,
      ]) {
        expect(find.byKey(key), findsOneWidget,
            reason: 'P23 R1：$key 入口必须仍在（只是落点换了）');
        expect(
          find.ancestor(of: find.byKey(key), matching: find.byType(GpToolbar)),
          findsOneWidget,
          reason: 'P23 R1：$key 必须落在工具栏子树内',
        );
        expect(
          find.descendant(
            of: find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlScene)),
            matching: find.byKey(key),
          ),
          findsNothing,
          reason: 'P23 R1：$key 已从 gpPlScene 格顶行搬走，格内不许残留（否则双入口）',
        );
      }
      // ★ P23 R1 正向：工具栏里的「笔记」按钮真的能打开本机笔记全屏
      //   （只在工具栏里挂个 key 是不够的，得证明接线没断）。
      await tester.ensureVisible(find.byKey(RoomGamePage.plNotesKey));
      await tester.pump();
      await tester.tap(find.byKey(RoomGamePage.plNotesKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(GpPlNotes), findsOneWidget,
          reason: 'P23 R1：工具栏「笔记」按钮必须打开 GpPlNotes 全屏');
      Navigator.of(tester.element(find.byType(GpPlNotes))).pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(GpPlNotes), findsNothing, reason: '全屏笔记必须真的关闭');
      // 手绘板按钮的反向守卫：未点击时画布不该常驻（纯按钮入口）。
      expect(find.byType(GpPlSketch), findsNothing,
          reason: 'P23 R1：手绘板仍是「按钮 → 全屏」入口，不在 dock 常驻');
    });

    testWidgets('★ 折叠档（360×640）：展开区是真块，方块点开全屏显示真块',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      f.pageBuilder = (String s, String r) => const RoomGamePage();
      useRoomScreen(tester, 360, 640);
      await tester.pumpWidget(f.pageOf(kHostSeat));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(PlaceholderBlock), findsNothing);

      // 展开区（口述白名单）必须是真块
      expect(_inSlot(RoomSlot.gpKpLeft, GpKpLeft), findsOneWidget);
      expect(_inSlot(RoomSlot.gpMap, GpMapStage), findsOneWidget);
      expect(_inSlot(RoomSlot.gpScene, GpSceneCheckKp), findsOneWidget);

      // 收起的「聊天」点开 → 全屏阅读器里是真 GpFeeds
      expect(find.byType(GpFeeds), findsNothing,
          reason: '折叠态下聊天块不常驻');
      final tile = find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpChat));
      await tester.ensureVisible(tile);
      await tester.pump();
      await tester.tap(tile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(GpFeeds), findsOneWidget,
          reason: '方块点开必须显示真块（走 showFullscreenReader，不裸 showDialog）');

      // 关掉全屏，回到折叠档（路由退场动画跑完才算真的关掉）
      Navigator.of(tester.element(find.byType(GpFeeds))).pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(GpFeeds), findsNothing);
      expect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpChat)), findsOneWidget);
    });

    testWidgets('旁观者走 PL 骨架：同样零占位、舞台只读',
        (WidgetTester tester) async {
      await _bootPage(tester, seat: 'sp1');
      expect(tester.takeException(), isNull);
      expect(find.byType(PlaceholderBlock), findsNothing);
      expect(_inSlot(RoomSlot.gpPlCharCard, GpPlCharCard), findsOneWidget);
      final stage =
          tester.widget<GpMapStage>(_inSlot(RoomSlot.gpPlMap, GpMapStage));
      expect(stage.readOnly, isTrue);
    });

    testWidgets('★ MapStageControl 单实例：gpMap 与 gpKpTools 是同一个对象',
        (WidgetTester tester) async {
      await _bootPage(tester);

      final stage =
          tester.widget<GpMapStage>(_inSlot(RoomSlot.gpMap, GpMapStage));
      final tools =
          tester.widget<GpKpTools>(_inSlot(RoomSlot.gpKpTools, GpKpTools));

      expect(tools.stage, isNotNull, reason: '工具窄栏必须拿到舞台控制面');
      expect(identical(stage.controller, tools.stage), isTrue,
          reason: '★ 块 3 与块 4 必须是同一份 controller（否则画笔改了没人收点）');
      expect(stage.controller, isA<MapStageControl>());
      // 同一实例的旁证：改工具态后舞台能读到
      stage.controller.beginMark(kind: 'pin', label: '门');
      await tester.pump();
      expect(tools.stage!.awaitingTap, isTrue);
      stage.controller.cancel();
    });
  });

  group('接线 · 工具栏', () {
    testWidgets('★ gpToolbar 仍无 Transform 祖先，且骰子条与 KP 入口都在里面',
        (WidgetTester tester) async {
      await _bootPage(tester);

      // 反证：内容区确实在缩放容器里（否则下面的断言是空转）
      expect(_inZoomHost(RoomKeys.keyOfSlot(RoomSlot.gpChat)), isTrue);

      expect(_inZoomHost(RoomKeys.keyOfSlot(RoomSlot.gpToolbar)), isFalse,
          reason: '★ 工具栏在 Stack 里是缩放容器的兄弟节点，新增内容也不许改变这一点');
      expect(_inZoomHost(RoomGamePage.kpPanelKey), isFalse,
          reason: 'KP 入口在工具栏里 → 同样不在缩放容器内');

      // 骰子条在工具栏内、且不在缩放容器内
      expect(find.byKey(RoomKeys.gpDiceBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpToolbar)),
          matching: find.byKey(RoomKeys.gpDiceBar),
        ),
        findsOneWidget,
      );
      expect(_inZoomHost(RoomKeys.gpDiceBar), isFalse);
    });

    testWidgets('KP 入口只在 KP 侧出现，点开是「KP 工具」弹层',
        (WidgetTester tester) async {
      final f = await _bootPage(tester);
      expect(find.byKey(RoomGamePage.kpPanelKey), findsOneWidget);

      // 工具条已改成多行 Wrap（无横向滚动），保险起见仍先滚进视口再点（T4）
      await tester.ensureVisible(find.byKey(RoomGamePage.kpPanelKey));
      await tester.pump();
      await tester.tap(find.byKey(RoomGamePage.kpPanelKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('KP 工具'), findsWidgets, reason: 'showKpPanel 已接线');
      expect(f.booted, isTrue);

      // 玩家侧没有这个入口
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _bootPage(tester, seat: 'p1');
      expect(find.byKey(RoomGamePage.kpPanelKey), findsNothing);
    });

    testWidgets('工具栏快捷按钮：P17 P-4 删除恒灰入口（接线后不回退）',
        (WidgetTester tester) async {
      final f = await _bootPage(tester);
      // 「可点性 == POLICY」的正向探针已由 `room_ui_permission_test.dart`
      // 的 KpPanel 分支覆盖（`round.next` 仍在 KP 工具）；这里守负向不变量。
      for (final entry in <String, String>{
        kHostSeat: RoomRole.kp,
        'p1': RoomRole.player,
        'sp1': RoomRole.spectator,
      }.entries) {
        await tester.pumpWidget(f.pageOf(entry.key));
        await tester.pump();
        for (final op in <String>['round.next', 'scene.mode']) {
          expect(find.byKey(RoomKeys.action(op)), findsNothing,
              reason: 'P17 P-4：${entry.value} 工具栏不渲染 $op');
        }
      }
    });
  });

  group('接线 · 容器 key 不退化', () {
    testWidgets('KP dock 10 个 / PL 9 个容器 key 各自 findsOneWidget',
        (WidgetTester tester) async {
      final f = await _bootPage(tester);
      // ★ P16：1280×800 是 KP dock 档，gpCombat / gpStatus 已移出网格；
      //   其余 10 个槽位必须各恰好一个容器。
      const Set<RoomSlot> retiredInDock = <RoomSlot>{
        RoomSlot.gpCombat,
        RoomSlot.gpStatus,
      };
      for (final slot in RoomKeys.kpSlots) {
        if (retiredInDock.contains(slot)) {
          expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsNothing,
              reason: 'KP dock 不该再渲染 ${slot.name}');
          continue;
        }
        expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsOneWidget,
            reason: 'KP 缺容器 ${slot.name}');
      }
      await tester.pumpWidget(f.pageOf('p1'));
      await tester.pump();
      // ★ P20 需求 3②③④：玩家 dock 也删了 4 个叶子 —— `gpPlCombat` 搬进
      //   `gpPlMap` 格、`gpPlSketch`/`gpPlNotes` 变成场景格内的全屏按钮、
      //   `gpStatus` 与 KP 同口径收起。剩余 9 个槽位各恰好一个容器。
      const Set<RoomSlot> retiredInDockPl = <RoomSlot>{
        RoomSlot.gpPlCombat,
        RoomSlot.gpPlSketch,
        RoomSlot.gpPlNotes,
        RoomSlot.gpStatus,
      };
      for (final slot in RoomKeys.plSlots) {
        if (retiredInDockPl.contains(slot)) {
          expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsNothing,
              reason: 'PL dock 不该再渲染 ${slot.name}');
          continue;
        }
        expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsOneWidget,
            reason: 'PL 缺容器 ${slot.name}');
      }
      expect(RoomKeys.plSlots.length, 13, reason: 'plSlots 常量本身不许改小');
      expect(RoomKeys.plSlots.length - retiredInDockPl.length, 9);
    });

    testWidgets('780×320 横屏同样能接线渲染且零异常',
        (WidgetTester tester) async {
      await _bootPage(tester, w: 780, h: 320);
      expect(tester.takeException(), isNull);
      for (final slot in RoomKeys.kpSlots) {
        expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsOneWidget);
      }
      expect(find.byType(PlaceholderBlock), findsNothing);
    });

    testWidgets('★ 玩家侧：360×640 竖屏与 780×320 横屏都零异常，13 容器不退化',
        (WidgetTester tester) async {
      for (final List<double> size in <List<double>>[
        <double>[360, 640],
        <double>[780, 320],
      ]) {
        final f = RoomUiFixture();
        await f.boot();
        f.pageBuilder = (String s, String r) => const RoomGamePage();
        useRoomScreen(tester, size[0], size[1]);
        await tester.pumpWidget(f.pageOf('p1'));
        await tester.pump();

        final label = '${size[0].toInt()}×${size[1].toInt()}';
        expect(tester.takeException(), isNull, reason: '玩家侧 $label 有异常');
        expect(find.byType(PlaceholderBlock), findsNothing);
        for (final slot in RoomKeys.plSlots) {
          expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsOneWidget,
              reason: 'PL 缺容器 ${slot.name}（$label）');
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  });
}
