// ============================================================
// test/p12_kp1_fullscreen_test.dart — P12 / 第 9 期 · KP-1b/1c、PL-3b/3c
//
// 真全屏素材舞台：
//   · 全屏态内 GpMapStageKeys.fullscreen 入口数 = 0（结构性不渲染）；
//   · 舞台 rect ≈ 视口（不再是半屏 showRoomSheet / 内嵌第二个 stage）；
//   · KP 有左侧工具窄栏且舞台非只读；玩家整条窄栏不渲染、舞台只读；
//   · 退出后 RoomGridSpec.of 与槽位 rect 前后一致（布局骨架零漂移）。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap;
import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/ui/room/map_fullscreen_page.dart'
    show MapFullscreenKeys, MapFullscreenPage;
import 'package:dice_realm/ui/room/room_game_page.dart' show RoomGamePage;
import 'package:dice_realm/ui/room/room_keys.dart' show RoomKeys, RoomSlot;
import 'package:dice_realm/ui/room/room_ui_local.dart' show RoomToolMode;
import 'package:dice_realm/ui/room/view/room_view.dart' show RoomGridSpec;
import 'package:dice_realm/ui/room/widgets/gp_map_stage.dart'
    show GpMapStage, GpMapStageKeys, MapStageControl, MapStageMode;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart'
    show RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart'
    show RoomUiFixture, kFakePngDataUrl, useRoomScreen;

Widget _fullscreenApp(
  RoomUiFixture f,
  String seat,
  MapStageControl ctl,
  bool isKp,
) =>
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: f.scoped(
        seat,
        child: MapFullscreenPage(stageControl: ctl, isKp: isKp),
      ),
    );

void main() {
  group('A · 全屏态内嵌入口数 = 0（KP-1b / PL-3b）', () {
    for (final bool isKp in <bool>[true, false]) {
      testWidgets('${isKp ? "KP" : "玩家"} 全屏态不渲染 fullscreen 键，改渲染退出',
          (WidgetTester tester) async {
        final RoomUiFixture f = RoomUiFixture();
        await f.boot(inGame: true);
        final MapStageControl ctl = MapStageControl();
        useRoomScreen(tester, 1280, 800);
        await tester.pumpWidget(
            _fullscreenApp(f, isKp ? kHostSeat : 'p1', ctl, isKp));
        await tester.pump();
        await tester.pump(); // postFrameCallback 里 setMapFullscreen(true)

        expect(find.byKey(GpMapStageKeys.fullscreen), findsNothing,
            reason: '★ 全屏里不该再有第二个「全屏」入口（嵌套根因）');
        expect(find.text('全屏查看素材'), findsNothing);
        expect(find.byKey(GpMapStageKeys.exitFullscreen), findsOneWidget,
            reason: '全屏态用「退出全屏」替代 fullscreen 入口');
        expect(find.byType(MapFullscreenPage), findsOneWidget);
        // 不是半屏弹层（改前 _openFullscreen 走 showRoomSheet）。
        expect(find.byType(BottomSheet), findsNothing,
            reason: '真全屏不能是半屏 bottomSheet');
        // 全屏态记在本机态。
        expect(f.localOf(isKp ? kHostSeat : 'p1').mapFullscreen, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('B · 舞台 rect ≈ 视口 + KP 窄栏 / 玩家只读', () {
    testWidgets('KP：左侧工具窄栏存在且可命中，舞台非只读',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      final MapStageControl ctl = MapStageControl();
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(
          _fullscreenApp(f, kHostSeat, ctl, true));
      await tester.pump();

      expect(find.byKey(MapFullscreenKeys.toolRail), findsOneWidget,
          reason: 'KP 全屏必须有左侧工具窄栏');
      expect(find.text('拖动素材'), findsOneWidget);
      expect(find.text('放单位'), findsOneWidget);
      expect(find.text('清除标记'), findsOneWidget);
      expect(find.text('放玩家'), findsNothing,
          reason: 'Q2：窄栏不含「放玩家」');
      expect(find.text('全屏'), findsNothing,
          reason: 'Q2：窄栏不含「全屏」入口');
      expect(tester.widget<GpMapStage>(find.byType(GpMapStage)).readOnly, isFalse,
          reason: '★ KP 全屏必须非只读（能在大画面上做标记）');
      expect(find.byKey(GpMapStageKeys.panTool), findsOneWidget);

      // 舞台 rect ≈ 视口（16:9 AspectRatio 居中，宽占满、高占 ≥80%）。
      final Rect root = tester.getRect(find.byKey(MapFullscreenKeys.root));
      final Rect stage = tester.getRect(find.byKey(GpMapStageKeys.stage));
      expect(stage.width, greaterThanOrEqualTo(root.width * 0.9),
          reason: '舞台宽 ${stage.width} / 视口宽 ${root.width}');
      expect(stage.height, greaterThanOrEqualTo(root.height * 0.8),
          reason: '舞台高 ${stage.height} / 视口高 ${root.height}');

      // 窄栏按钮可命中（tap 不抛异常）。
      await tester.tap(find.byKey(GpMapStageKeys.panTool));
      await tester.pump();
      expect(f.localOf(kHostSeat).panArmed, isTrue,
          reason: '窄栏「拖动素材」应切到 pan 工具态');
      expect(tester.takeException(), isNull);
    });

    testWidgets('玩家：整条窄栏不渲染、舞台只读、仅退出 + 缩放',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      final MapStageControl ctl = MapStageControl();
      useRoomScreen(tester, 412, 915); // 手机竖屏也算「非平板横屏」
      await tester.pumpWidget(_fullscreenApp(f, 'p1', ctl, false));
      await tester.pump();

      expect(find.byKey(MapFullscreenKeys.toolRail), findsNothing,
          reason: '★ PL-3c：玩家侧整条工具窄栏不渲染');
      for (final String label in <String>[
        '拖动素材',
        '放单位',
        '清除标记',
        '画笔',
        '标点',
      ]) {
        expect(find.text(label), findsNothing,
            reason: '玩家全屏不该有「$label」入口');
      }
      expect(tester.widget<GpMapStage>(find.byType(GpMapStage)).readOnly, isTrue,
          reason: '★ 玩家全屏舞台保持只读');
      expect(find.byKey(MapFullscreenKeys.exit), findsOneWidget,
          reason: '玩家侧保留唯一的退出入口');
      expect(find.byKey(GpMapStageKeys.zoomIn), findsOneWidget);
      expect(find.byKey(GpMapStageKeys.zoomOut), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ★ 2.37.0 / Q2：全屏窄栏补橡皮；缩放只留一个文字符号（不再 icon+label 双符号）。
  group('Q2 · 2.37.0 全屏窄栏橡皮 + 缩放单符号', () {
    testWidgets('KP：橡皮独立 key、tap 切 erase；缩放两按钮 icon==null 且只留 +/-',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      final MapStageControl ctl = MapStageControl();
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(
          _fullscreenApp(f, kHostSeat, ctl, true));
      await tester.pump();

      // ★ 橡皮：独立 ValueKey，不挂 act/ 锚点，与主页共用同一 stageControl。
      expect(find.byKey(MapFullscreenKeys.eraser), findsOneWidget);
      expect(find.text('橡皮'), findsOneWidget);
      expect(
        (MapFullscreenKeys.eraser as ValueKey<String>).value.startsWith('act/'),
        isFalse,
        reason: '★ 橡皮 key 必须独立，绝不挂 RoomKeys.action(...)（避 T-30 污染）',
      );
      expect(ctl.mode, MapStageMode.none, reason: '前置：默认无工具');
      await tester.tap(find.byKey(MapFullscreenKeys.eraser));
      await tester.pump();
      expect(ctl.mode, MapStageMode.erase,
          reason: '★ tap 橡皮必须切到 stageControl.erase（与主页同口径）');

      // ★ 缩放：RoomTap.icon 为 null，只留一个文字字符。
      final RoomTap zin =
          tester.widget<RoomTap>(find.byKey(MapFullscreenKeys.zoomIn));
      final RoomTap zout =
          tester.widget<RoomTap>(find.byKey(MapFullscreenKeys.zoomOut));
      expect(zin.icon, isNull, reason: '★ 放大不能再有 icon 造成第二符号');
      expect(zin.label, '+');
      expect(zout.icon, isNull, reason: '★ 缩小不能再有 icon 造成第二符号');
      expect(zout.label, '-');

      // tap 缩放仍真改舞台 mapZoom（只留文字不能丢了行为）。
      final double z0 = f.localOf(kHostSeat).mapZoom;
      await tester.tap(find.byKey(MapFullscreenKeys.zoomIn));
      await tester.pump();
      expect(f.localOf(kHostSeat).mapZoom, greaterThan(z0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('玩家：橡皮 findsNothing（只读侧不给擦除工具）',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      final MapStageControl ctl = MapStageControl();
      useRoomScreen(tester, 412, 915);
      await tester.pumpWidget(_fullscreenApp(f, 'p1', ctl, false));
      await tester.pump();

      expect(find.byKey(MapFullscreenKeys.eraser), findsNothing,
          reason: '★ 玩家全屏侧不该出现橡皮');
      expect(find.text('橡皮'), findsNothing);
      expect(ctl.mode, MapStageMode.none);
      expect(tester.takeException(), isNull);
    });

    for (final double scale in <double>[1.3, 1.5, 2.0]) {
      testWidgets('×$scale：KP 全屏橡皮/缩放按钮零溢出、钳制生效',
          (WidgetTester tester) async {
        final RoomUiFixture f = RoomUiFixture();
        await f.boot(inGame: true);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final MapStageControl ctl = MapStageControl();
        useRoomScreen(tester, 1280, 800);
        await tester.pumpWidget(_fullscreenApp(f, kHostSeat, ctl, true));
        await tester.pump();

        expect(find.byKey(MapFullscreenKeys.eraser), findsOneWidget);
        expect(find.byKey(MapFullscreenKeys.zoomIn), findsOneWidget);
        expect(find.byKey(MapFullscreenKeys.zoomOut), findsOneWidget);
        // clampBtnText 只包按钮子树：文字在放大系统字号下仍按 13dp 量，零溢出。
        for (final Key key in <Key>[
          MapFullscreenKeys.eraser,
          MapFullscreenKeys.zoomIn,
          MapFullscreenKeys.zoomOut,
        ]) {
          final BuildContext ctx = tester.element(find.byKey(key));
          expect(MediaQuery.of(ctx).textScaler.scale(13), closeTo(13, 0.01),
              reason: '$key 的按钮子树 textScaler 应被 clampBtnText 钳到 1.0');
        }
        expect(tester.takeException(), isNull,
            reason: '×$scale 全屏窄栏出现布局溢出');
      });
    }
  });

  group('D · 主理人裁决追查：玩家裁剪态公开素材可达（PL-3a/3b/3c 闭环）', () {
    testWidgets('玩家全屏态同样渲染公开素材底图（coverLayer findsOneWidget）',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      // 把公开素材写进权威态，再同步到玩家裁剪态（assets/strokes/marks
      // 是公开场景层，visibleToPlayers 只裁怪物 actors / 战斗槽）。
      f.hostState()['scene'] = <String, Object?>{
        'assets': <Object?>[
          <String, Object?>{
            'id': 'a1',
            'kind': 'map',
            'name': '底图',
            'data': kFakePngDataUrl,
            'revealed': true,
            'at': 1,
          },
        ],
        'strokes': <Object?>[],
        'marks': <Object?>[],
      };
      await f.kpSession.pullSync('p1');
      final Map<String, Object?> plScene = asMap(f.stateOf('p1')['scene']);
      expect(asList(plScene['assets']).length, greaterThanOrEqualTo(1),
          reason: '★ 玩家裁剪态必须含 scene.assets，否则玩家舞台永远空白');

      final MapStageControl ctl = MapStageControl();
      useRoomScreen(tester, 412, 915);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: f.scoped(
          'p1',
          child: MapFullscreenPage(stageControl: ctl, isKp: false),
        ),
      ));
      await tester.pump();
      expect(find.byKey(GpMapStageKeys.coverLayer), findsOneWidget,
          reason: '★ 玩家全屏舞台必须真的渲染出公开素材底图');
      expect(find.byKey(GpMapStageKeys.fullscreen), findsNothing,
          reason: '全屏态仍不该内嵌第二个「全屏」入口');
      expect(tester.takeException(), isNull);
    });

    // ★ 2.36.0 / Q6 裁决 4 硬要求：新增 KP 全屏态（isKp:true）端到端用例。
    //   原 group D 只有 isKp:false；KP 侧必须证明「公开一张有效素材 → 真全屏」
    //   不会复现白板：渲染树里 Image.memory 命中，且图层在 CustomPaint 之下。
    testWidgets('KP 全屏态（isKp:true）：coverLayer + Image.memory + 图层在笔迹层之下',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      f.hostState()['scene'] = <String, Object?>{
        'assets': <Object?>[
          <String, Object?>{
            'id': 'a1',
            'kind': 'map',
            'name': '底图',
            'data': kFakePngDataUrl,
            'revealed': true,
            'at': 1,
          },
        ],
        'strokes': <Object?>[],
        'marks': <Object?>[],
      };
      final MapStageControl ctl = MapStageControl();
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(_fullscreenApp(f, kHostSeat, ctl, true));
      await tester.pump();

      expect(find.byKey(GpMapStageKeys.coverLayer), findsOneWidget,
          reason: '★ 裁决 4：KP 真全屏必须真的渲染出公开素材底图');
      expect(
        find.byWidgetPredicate(
            (Widget w) => w is Image && w.image is MemoryImage),
        findsOneWidget,
        reason: '★ 裁决 4：渲染树里必须命中 Image.memory（不是只断言容器存在）',
      );
      final Finder innerStack = find
          .ancestor(
            of: find.byKey(GpMapStageKeys.coverLayer),
            matching: find.byType(Stack),
          )
          .first;
      final Stack sw = tester.widget<Stack>(innerStack);
      expect(sw.children.first.key, GpMapStageKeys.coverLayer,
          reason: '★ 图片在 inner Stack child0（Stack 按序绘制 ⇒ 最下层）');
      expect(sw.children.length, 2,
          reason: 'inner Stack 恰好「底图 + 手势/笔迹层」两层');
      expect(
        find.descendant(
          of: find.byWidgetPredicate(
              (Widget w) => identical(w, sw.children[1])),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
        reason: '★ 笔迹/标点 CustomPaint 在 child1 子树，绘制顺序必在图片之上',
      );
      expect(tester.widget<GpMapStage>(find.byType(GpMapStage)).readOnly,
          isFalse,
          reason: 'KP 全屏非只读（fullscreenMode 语义零改动）');
      expect(tester.takeException(), isNull);
    });
  });

  group('C · 退出复位 + 布局骨架零漂移', () {
    testWidgets('退出后本机态复位，RoomGridSpec.of 与槽位 rect 前后一致',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      final MapStageControl ctl = MapStageControl();
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(_fullscreenApp(f, kHostSeat, ctl, true));
      await tester.pump();

      final local = f.localOf(kHostSeat);
      local.setMapPanOffset(const Offset(20, 10));
      local.setMapZoom(1.5);
      local.setTool(RoomToolMode.pan);
      expect(local.panArmed, isTrue);
      expect(local.mapFullscreen, isTrue);

      final RoomGridSpec specBefore =
          RoomGridSpec.of(w: 1280, h: 800, landscape: true);

      await tester.tap(find.byKey(MapFullscreenKeys.exit));
      await tester.pump();

      expect(local.mapFullscreen, isFalse, reason: '退出应复位全屏态');
      expect(local.mapPanOffset, Offset.zero, reason: '退出应复位平移量');
      expect(local.mapZoom, 1.0, reason: '退出应复位舞台缩放');
      expect(local.panArmed, isFalse, reason: '退出应复位工具激活态');

      final RoomGridSpec specAfter =
          RoomGridSpec.of(w: 1280, h: 800, landscape: true);
      expect(specAfter.mode, specBefore.mode,
          reason: 'dock/folded 档位判定零漂移');
      // RoomGridSpec.of 是纯函数：同一入参两次调用必须逐字同结果。
      expect(RoomGridSpec.of(w: 1280, h: 800, landscape: true).mode,
          specBefore.mode,
          reason: 'RoomGridSpec.of 纯函数语义前后一致');

      // 回到真游戏页后，原槽位仍在且 Rect 未变（独立路由不卸载底层页面）。
      f.pageBuilder = (String s, String r) => const RoomGamePage();
      await tester.pumpWidget(f.pageOf(kHostSeat));
      await tester.pump();
      expect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpScene)), findsOneWidget);
      expect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlayers)), findsOneWidget);
      final Rect scene = tester.getRect(
          find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpScene)));
      final Rect players = tester.getRect(
          find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlayers)));
      expect(players.left, closeTo(scene.left, 0.6));
      expect(players.right, closeTo(scene.right, 0.6));
      expect(players.bottom, closeTo(scene.bottom, 0.6));
      expect(tester.takeException(), isNull);
    });
  });
}
