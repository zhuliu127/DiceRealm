// ============================================================
// test/p12_kp1_stage_transform_test.dart — P12 / 第 9 期 · KP-1a / PL-3a
//
// 「+」「-」缩放时，公开素材底图与单位标记 / 笔迹 / 标点层必须**同量**变化。
//
// ★ Q-D 实测口径（设计 §0.1 / §8.2）：代码里只有 3 个集合
//   （scene.assets / scene.strokes / scene.marks），单位标记与标点共用
//   marks + 同一个 CustomPaint，所以只有 2 个可区分 RenderBox 图层：
//     底图 = GpMapStageKeys.coverLayer（Image）
//     笔迹/标点 = GpMapStageKeys.canvas 内的 CustomPaint
//   本文件按此写**两条**正向断言，不为凑「四层」去拆 painter（会改契约）。
// ★ 用 RenderBox.getTransformTo(null) + MatrixUtils.transformRect 量
//   **真实绘制矩形**（含祖先 Transform.scale），不依赖 WidgetTester.getRect
//   的实现细节；×1.25 / ÷1.25 用比值断言。
// ★ 反向证伪：把 _coverImage 移出 Transform，底图比值恒为 1.0 → 本文件真红。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/ui/room/widgets/gp_map_stage.dart'
    show GpMapStage, GpMapStageKeys, MapStageControl;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show MatrixUtils, RenderBox;
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart'
    show RoomUiFixture, kFakePngDataUrl, useRoomScreen;

/// 造一份带公开素材底图 + 笔迹 + 标点/单位标记的场景（三个集合，Q-D）。
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
        'color': '#ff0000',
        'width': 3,
        'pts': <Object?>[
          <String, Object?>{'x': 0.1, 'y': 0.1},
          <String, Object?>{'x': 0.5, 'y': 0.5},
        ],
      },
    ],
    'marks': <Object?>[
      <String, Object?>{
        'x': 0.3,
        'y': 0.4,
        'kind': 'dot',
        'label': '标点',
        'revealed': true,
      },
      <String, Object?>{
        'x': 0.6,
        'y': 0.6,
        'kind': 'actor',
        'label': '单位',
        'revealed': true,
      },
    ],
  };
}

Widget _stageApp(RoomUiFixture f, String seat, MapStageControl ctl) =>
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 800,
            height: 450,
            child: f.scoped(
              seat,
              child: GpMapStage(
                controller: ctl,
                readOnly: seat != kHostSeat,
              ),
            ),
          ),
        ),
      ),
    );

/// 真实绘制矩形（把祖先 Transform 一起算进去）。
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

/// ★ 主理人裁决追查项（PL-3a/3b/3c 是否闭环）：
///   `assets/strokes/marks` 是**公开**场景层，visibleToPlayers 只裁怪物
///   actors 与战斗槽，不应把 scene.assets 裁掉。pullSync 之后显式断言
///   玩家裁剪态确实拿得到公开素材，否则玩家舞台将永远空白（源码 Bug）。
void _assertPlayerSceneVisible(RoomUiFixture f, String seat) {
  final Map<String, Object?> scene = asMap(f.stateOf(seat)['scene']);
  final List<Object?> assets = asList(scene['assets']);
  expect(assets.length, greaterThanOrEqualTo(1),
      reason: '★ 玩家裁剪态必须含 scene.assets（公开素材层），'
          '否则 PL-3a 玩家舞台永远空白');
  expect(
    assets.any((Object? e) =>
        jsStr(asMap(e)['data']) == kFakePngDataUrl),
    isTrue,
    reason: '★ 玩家裁剪态的素材内容必须含 seed 的 dataURL，实测 '
        '${assets.map((Object? e) => asMap(e).keys.toList()).toList()}',
  );
  expect(asList(scene['strokes']).length, greaterThanOrEqualTo(1),
      reason: '★ 玩家裁剪态应能看到公开笔迹层');
  expect(asList(scene['marks']).length, greaterThanOrEqualTo(1),
      reason: '★ 玩家裁剪态应能看到公开标点/单位标记层');
}

void main() {
  for (final bool isKp in <bool>[true, false]) {
    final String seat = isKp ? kHostSeat : 'p1';
    final String who = isKp ? 'KP（平板横屏）' : '玩家（非平板横屏）';

    testWidgets('$who 底图 + 笔迹/标点层随 zoomIn ×1.25 同量变化（两条正向断言）',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      _seedScene(f);
      // ★ 玩家视角是裁剪态（独立 client state），必须把权威态同步过去，
      //   否则 state['scene'] 里看不到 assets、底图层不渲染。
      if (!isKp) {
        await f.kpSession.pullSync(seat);
        _assertPlayerSceneVisible(f, seat);
      }
      final MapStageControl ctl = MapStageControl();
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(_stageApp(f, seat, ctl));
      await tester.pump();

      final Finder cover = find.byKey(GpMapStageKeys.coverLayer);
      final Finder paint = _canvasPaint();
      expect(cover, findsOneWidget, reason: '公开素材底图层必须渲染');
      expect(paint, findsOneWidget, reason: '笔迹/标点 CustomPaint 层必须渲染');

      final Rect cover0 = _paintedRect(tester, cover);
      final Rect paint0 = _paintedRect(tester, paint);
      // ★ 主理人裁决：不放大容差，改用**比值断言**。2dp 差来自 Container
      //   边框/圆角（渲染几何，非产品不变量），比例才是契约。
      final double ratioW0 = cover0.width / paint0.width;
      final double ratioH0 = cover0.height / paint0.height;
      expect(ratioW0, closeTo(1.0, 0.01),
          reason: '底图宽 / 标记层宽 应≈1，实测 $ratioW0');
      expect(ratioH0, closeTo(1.0, 0.01),
          reason: '底图高 / 标记层高 应≈1，实测 $ratioH0');
      expect(f.localOf(seat).mapZoom, 1.0);

      await tester.tap(find.byKey(GpMapStageKeys.zoomIn));
      await tester.pump();
      expect(f.localOf(seat).mapZoom, 1.25, reason: 'zoomIn 必须写 RoomUiLocal.mapZoom');

      final Rect cover1 = _paintedRect(tester, cover);
      final Rect paint1 = _paintedRect(tester, paint);

      // ★ 断言 ①：底图 rect 按 ×1.25 变化（KP-1a 修复点，改前恒 1.0）。
      expect(cover1.width / cover0.width, closeTo(1.25, 0.02),
          reason: '底图宽未按 ×1.25 变化：${cover0.width} → ${cover1.width}');
      expect(cover1.height / cover0.height, closeTo(1.25, 0.02),
          reason: '底图高未按 ×1.25 变化：${cover0.height} → ${cover1.height}');

      // ★ 断言 ②：笔迹/标点层 rect 同量变化（同一条 Transform 链）。
      expect(paint1.width / paint0.width, closeTo(1.25, 0.02),
          reason: '笔迹/标点层宽未同量变化：${paint0.width} → ${paint1.width}');
      expect(paint1.height / paint0.height, closeTo(1.25, 0.02),
          reason: '笔迹/标点层高未同量变化：${paint0.height} → ${paint1.height}');

      // 两层仍严格同步（不允许二次变换 / 落点漂移，R11）：
      // 缩放后比例与缩放前一致，且两层各自的缩放倍率完全相等。
      expect(cover1.width / paint1.width, closeTo(ratioW0, 0.01),
          reason: '缩放后两层宽度比不应改变');
      expect(cover1.height / paint1.height, closeTo(ratioH0, 0.01),
          reason: '缩放后两层高度比不应改变');
      expect(cover1.width / cover0.width,
          closeTo(paint1.width / paint0.width, 0.01),
          reason: '★ 两层必须按同一 ×1.25 比例变化');
      expect(cover1.height / cover0.height,
          closeTo(paint1.height / paint0.height, 0.01),
          reason: '★ 两层必须按同一 ×1.25 比例变化（高）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('$who zoomOut ÷1.25 回原位、reset 同时清平移量',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      _seedScene(f);
      // ★ 玩家视角是裁剪态（独立 client state），必须把权威态同步过去，
      //   否则 state['scene'] 里看不到 assets、底图层不渲染。
      if (!isKp) {
        await f.kpSession.pullSync(seat);
        _assertPlayerSceneVisible(f, seat);
      }
      final MapStageControl ctl = MapStageControl();
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(_stageApp(f, seat, ctl));
      await tester.pump();

      final Finder cover = find.byKey(GpMapStageKeys.coverLayer);
      final Finder paint = _canvasPaint();
      final Rect cover0 = _paintedRect(tester, cover);
      final Rect paint0 = _paintedRect(tester, paint);

      await tester.tap(find.byKey(GpMapStageKeys.zoomIn));
      await tester.pump();
      await tester.tap(find.byKey(GpMapStageKeys.zoomOut));
      await tester.pump();

      expect(f.localOf(seat).mapZoom, 1.0);
      expect(_paintedRect(tester, cover).width, closeTo(cover0.width, 0.5));
      expect(_paintedRect(tester, paint).width, closeTo(paint0.width, 0.5));

      // reset 必须把本机平移量也归零（四层同步回原点）。
      f.localOf(seat).setMapPanOffset(const Offset(24, 18));
      await tester.pump();
      expect(_paintedRect(tester, cover).left,
          closeTo(cover0.left + 24, 0.5));
      expect(_paintedRect(tester, paint).left,
          closeTo(paint0.left + 24, 0.5));
      expect(_paintedRect(tester, cover).left - cover0.left,
          closeTo(_paintedRect(tester, paint).left - paint0.left, 0.5),
          reason: '两层 offset 必须同量');
      await tester.tap(find.byKey(GpMapStageKeys.reset));
      await tester.pump();
      expect(f.localOf(seat).mapPanOffset, Offset.zero);
      expect(_paintedRect(tester, cover).left, closeTo(cover0.left, 0.5));
      expect(_paintedRect(tester, paint).left, closeTo(paint0.left, 0.5));
      expect(tester.takeException(), isNull);
    });
  }

  test('本机态隔离：mapZoom 与页面整体 zoom 严格不互相赋值', () {
    final RoomUiFixture f = RoomUiFixture()..bootSync();
    final local = f.localOf(kHostSeat);
    local.setZoom(0.8);
    local.setMapZoom(2.0);
    expect(local.zoom, 0.8, reason: '舞台缩放不得改写页面整体缩放');
    expect(local.mapZoom, 2.0);
    local.setZoom(0.6);
    expect(local.mapZoom, 2.0);
    local.setMapZoom(0.5);
    expect(local.zoom, 0.6);
    local.resetMapView();
    expect(local.mapZoom, 1.0);
    expect(local.zoom, 0.6, reason: 'resetMapView 不得触碰既有 zoom');
  });
}
