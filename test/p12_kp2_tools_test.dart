// ============================================================
// test/p12_kp2_tools_test.dart — P12 / 第 9 期 · KP-2a / 2b / 2c、R1
//
//   · 「放玩家」findsNothing；「清除标记」findsOneWidget（R1 不撞车）；
//     「清空标记层」findsOneWidget、旧文案 findsNothing；
//   · 二次确认后清 scene.strokes + scene.marks（笔迹/标点/单位标记三类），
//     scene.assets（公开素材）长度不变；
//   · 拖动：四层（底图 + 笔迹/标点）offset 同量同步、出站计划数量/键集不变、
//     state 与存档 JSON 无本机态、退出复位；
//   · mapZoom / mapPanOffset / panArmed 与页面整体 zoom 严格隔离；
//   · 固定尺寸新按钮 textScaler 1.3 / 1.5 / 2.0 不溢出。
// ============================================================

import 'dart:convert' show jsonEncode;

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap;
import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/ui/room/room_ui_local.dart' show RoomToolMode;
import 'package:dice_realm/ui/room/widgets/gp_kp_left.dart'
    show GpKpLeft, GpKpLeftKeys;
import 'package:dice_realm/ui/room/widgets/gp_kp_tools.dart'
    show GpKpTools, GpKpToolsKeys;
import 'package:dice_realm/ui/room/widgets/gp_map_stage.dart'
    show GpMapStage, GpMapStageKeys, MapStageControl;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show MatrixUtils, RenderBox;
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart'
    show RoomUiFixture, kFakePngDataUrl, useRoomScreen;

Widget _app(RoomUiFixture f, Widget child) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(body: f.scoped(kHostSeat, child: child)),
    );

Widget _stageApp(RoomUiFixture f, MapStageControl ctl) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 800,
            height: 450,
            child: f.scoped(kHostSeat, child: GpMapStage(controller: ctl)),
          ),
        ),
      ),
    );

/// 造一份「三类标记 + 一张公开素材」的场景。
void _seedScene(RoomUiFixture f) {
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
    'strokes': <Object?>[
      <String, Object?>{
        'color': '#00ff00',
        'width': 2,
        'pts': <Object?>[
          <String, Object?>{'x': 0.2, 'y': 0.2},
          <String, Object?>{'x': 0.8, 'y': 0.8},
        ],
      },
    ],
    'marks': <Object?>[
      <String, Object?>{
        'x': 0.3,
        'y': 0.3,
        'kind': 'dot',
        'label': '标点',
        'revealed': true,
      },
      <String, Object?>{
        'x': 0.7,
        'y': 0.7,
        'kind': 'actor',
        'label': '单位',
        'revealed': true,
      },
    ],
  };
}

Rect _paintedRect(WidgetTester tester, Finder finder) {
  final RenderBox box = tester.renderObject<RenderBox>(finder);
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

Finder _canvasPaint() => find.descendant(
      of: find.byKey(GpMapStageKeys.canvas),
      matching: find.byType(CustomPaint),
    ).first;

void main() {
  group('A · KP-2a / R1 文案', () {
    // ★ P13 MAP-1：地图 tab（含「清空标记层」按钮）整块删除（Q8 明确不补回）。
    //   核心不变量「工具窄栏清除标记 findsOneWidget」逐字保留，
    //   左栏断言按产品真变改为「地图 tab / 清空标记层 findsNothing」正向口径。
    testWidgets('放玩家 findsNothing；清除标记 findsOneWidget / 地图 tab 已删',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);

      await tester.pumpWidget(_app(f, const GpKpTools()));
      await tester.pump();
      expect(find.text('放玩家'), findsNothing,
          reason: '★ KP-2a：与「放单位」重复的按钮必须删掉');
      expect(find.text('清除标记'), findsOneWidget,
          reason: 'R1：工具窄栏新文案恰好一个');
      expect(find.text('清除笔迹'), findsNothing);
      expect(find.text('清除笔迹与标记'), findsNothing);
      expect(find.byKey(GpKpToolsKeys.placeActor), findsOneWidget,
          reason: '「放单位」及 map.mark 落点零回归');
      expect(find.byKey(GpKpToolsKeys.panTool), findsOneWidget,
          reason: '原位置新增「拖动素材」');

      await tester.pumpWidget(_app(f, const GpKpLeft()));
      await tester.pump();
      expect(find.text('地图'), findsNothing,
          reason: '★ MAP-1：地图 tab 必须删除');
      expect(find.text('清空标记层'), findsNothing,
          reason: '★ MAP-1：地图面板整块删除，按钮随之消失');
      expect(find.text('NPC·怪物'), findsOneWidget,
          reason: 'NPC tab 仍在（0=NPC·怪物）');
      expect(find.text('素材'), findsOneWidget,
          reason: '素材 tab 仍在（1=素材）');
      expect(find.text('清除笔迹与标记'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('B · KP-2c 二次确认 + 三类集合清零 / 素材不变', () {
    testWidgets('连点两次才发 map.clear{strokesOnly:false}，三类清零、素材保留',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      _seedScene(f);
      await tester.pumpWidget(_app(f, const GpKpTools()));
      await tester.pump();
      f.clearSent();

      final Finder clear = find.byKey(GpKpToolsKeys.clear);
      await tester.tap(clear);
      await tester.pump();
      expect(f.lastSent(action: 'map.clear'), isNull,
          reason: '★ 第一下只点亮二次确认，不发包');

      await tester.tap(clear);
      await tester.pump();
      final Map<String, Object?>? sent = f.lastSent(action: 'map.clear');
      expect(sent, isNotNull, reason: '第二下才真正下发');
      expect(asMap(sent!['p'])['strokesOnly'], false,
          reason: '★ strokesOnly:false 才等价于「笔迹 + 单位标记 + 标点」三类全清');

      final Map<String, Object?> scene = asMap(f.hostState()['scene']);
      expect(asList(scene['strokes']), isEmpty, reason: '笔迹集合必须清零');
      expect(asList(scene['marks']), isEmpty,
          reason: '标点 + 单位标记共用 marks，必须一起清零');
      expect(asList(scene['assets']).length, 1,
          reason: '★ 公开素材集合长度不变（Q5：清除不含素材图）');
      expect(tester.takeException(), isNull);
    });

    test('domain 直测：strokesOnly:false 清两类、true 只清笔迹（既有口径不动）',
        () async {
      final RoomUiFixture f = RoomUiFixture()..bootSync();
      _seedScene(f);
      await f.sessionOf(kHostSeat)
          .hostAction('map.clear', <String, Object?>{'strokesOnly': false});
      final Map<String, Object?> s = asMap(f.hostState()['scene']);
      expect(asList(s['strokes']), isEmpty);
      expect(asList(s['marks']), isEmpty);
      expect(asList(s['assets']).length, 1);

      _seedScene(f);
      await f.sessionOf(kHostSeat)
          .hostAction('map.clear', <String, Object?>{'strokesOnly': true});
      final Map<String, Object?> s2 = asMap(f.hostState()['scene']);
      expect(asList(s2['strokes']), isEmpty);
      expect(asList(s2['marks']).length, 2,
          reason: 'strokesOnly:true 的既有语义逐字不动');
      expect(asList(s2['assets']).length, 1);
    });
  });

  group('C · KP-2b 拖动：四层 offset 同步 / 出站零变化 / 退出复位', () {
    testWidgets('拖动只写 RoomUiLocal，四层同量位移，state/存档/出站不变',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      _seedScene(f);
      final MapStageControl ctl = MapStageControl();
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(_stageApp(f, ctl));
      await tester.pump();

      final Finder cover = find.byKey(GpMapStageKeys.coverLayer);
      final Finder paint = _canvasPaint();
      final Rect cover0 = _paintedRect(tester, cover);
      final Rect paint0 = _paintedRect(tester, paint);

      final String stateBefore = jsonEncode(f.hostState());
      final String saveBefore = jsonEncode(
          f.sessionOf(kHostSeat).exportSave() ?? <String, Object?>{});
      final int sentLenBefore = f.sent.length;
      final List<Set<Object?>> sentKeysBefore =
          f.sent.map((Map<String, Object?> e) => e.keys.toSet()).toList();

      final local = f.localOf(kHostSeat);
      local.setTool(RoomToolMode.pan);
      expect(local.panArmed, isTrue, reason: 'panArmed 必须是 toolMode 的派生 getter');
      expect(local.toolMode, RoomToolMode.pan);

      await tester.drag(
          find.byKey(GpMapStageKeys.canvas), const Offset(30, 20));
      await tester.pump();

      // tester.drag 会把 30/20 拆成多步下发，总 delta 取决于手势分步，
      // 所以**不写死总位移**：先证明拖动生效，再用实际本机态逐字断言
      // 两层渲染位移与之相等（比写死常量更强，也更贴近「四层同步」契约）。
      final Offset pan = local.mapPanOffset;
      expect(pan, isNot(Offset.zero), reason: '拖动量只写本机态且必须生效');
      expect(pan.dx, greaterThan(0));
      expect(pan.dy, greaterThan(0));
      // ① 底图与笔迹/标点层同量位移（同一 Transform.translate）。
      expect(_paintedRect(tester, cover).left - cover0.left, closeTo(pan.dx, 0.5),
          reason: '底图 offset 未同步');
      expect(_paintedRect(tester, paint).left - paint0.left, closeTo(pan.dx, 0.5),
          reason: '笔迹/标点层 offset 未同步');
      expect(_paintedRect(tester, cover).top - cover0.top, closeTo(pan.dy, 0.5));
      expect(_paintedRect(tester, paint).top - paint0.top, closeTo(pan.dy, 0.5));
      expect(_paintedRect(tester, cover).left - cover0.left,
          closeTo(_paintedRect(tester, paint).left - paint0.left, 0.5),
          reason: '两层 offset 必须严格同量');

      // ② 本机态绝不进 state / 存档 JSON / 出站 SendPlan。
      expect(jsonEncode(f.hostState()), stateBefore,
          reason: 'state 深比较必须相等');
      final String saveAfter = jsonEncode(
          f.sessionOf(kHostSeat).exportSave() ?? <String, Object?>{});
      expect(saveAfter, saveBefore, reason: '存档 JSON 零变化');
      for (final String key in <String>[
        'mapPanOffset',
        'mapFullscreen',
        'mapZoom',
        'panArmed',
      ]) {
        expect(saveAfter.contains(key), isFalse,
            reason: '存档不该出现本机态键 $key');
      }
      expect(f.sent.length, sentLenBefore,
          reason: '拖动前后出站计划数量不变');
      expect(
        f.sent.map((Map<String, Object?> e) => e.keys.toSet()).toList(),
        sentKeysBefore,
        reason: '拖动前后出站计划键集不变',
      );

      // ③ 切到其它工具：panArmed 熄灭但 offset 保留（§5.2 状态机）。
      local.setTool(RoomToolMode.draw);
      expect(local.panArmed, isFalse);
      expect(local.mapPanOffset, pan, reason: '切工具保留 offset（§5.2）');

      // ④ 退出全屏 / 切场景：一次性复位四项。
      local.setMapFullscreen(true);
      local.setMapZoom(2.0);
      local.resetMapView();
      expect(local.mapFullscreen, isFalse);
      expect(local.mapPanOffset, Offset.zero);
      expect(local.mapZoom, 1.0);
      expect(local.toolMode, RoomToolMode.none);
      expect(local.panArmed, isFalse);
      expect(tester.takeException(), isNull);
    });

    test('panArmed 是只读派生 getter；setPanArmed 与 setTool(pan) 等价', () {
      final RoomUiFixture f = RoomUiFixture()..bootSync();
      final local = f.localOf(kHostSeat);
      local.setPanArmed(true);
      expect(local.panArmed, isTrue);
      expect(local.toolMode, RoomToolMode.pan);
      local.setPanArmed(false);
      expect(local.panArmed, isFalse);
      expect(local.toolMode, RoomToolMode.none);
      local.setTool(RoomToolMode.mark);
      expect(local.panArmed, isFalse);
    });
  });

  group('D · 固定尺寸新按钮：textScaler 1.3 / 1.5 / 2.0 不溢出', () {
    for (final double scale in <double>[1.3, 1.5, 2.0]) {
      testWidgets('×$scale：工具窄栏 / 左窄栏新按钮零 RenderFlex overflow',
          (WidgetTester tester) async {
        final RoomUiFixture f = RoomUiFixture();
        await f.boot(inGame: true);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        useRoomScreen(tester, 1280, 800);

        await tester.pumpWidget(_app(f, const GpKpTools()));
        await tester.pump();
        expect(find.text('清除标记'), findsOneWidget);
        expect(find.text('拖动素材'), findsOneWidget);
        expect(tester.takeException(), isNull,
            reason: '×$scale 工具窄栏出现布局异常');

        await tester.pumpWidget(_app(f, const GpKpLeft()));
        await tester.pump();
        expect(find.text('地图'), findsNothing,
            reason: '×$scale MAP-1：地图 tab 已删');
        expect(find.text('NPC·怪物'), findsOneWidget);
        expect(find.text('素材'), findsOneWidget);
        expect(tester.takeException(), isNull,
            reason: '×$scale 左窄栏出现布局异常');
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
    }
  });
}
