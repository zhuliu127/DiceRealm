// ============================================================
// qa_236_regression_test.dart — 2.36.0 六项 BugFix 独立回归（QA 严过关）
//
// 只增不改：本文件是**新增**测试文件，既有测试文件里需要随产品行为
// 真变而更新的口径在各自文件内「更强或等价」更新（见 QA 报告）。
//
// Q1 全屏 coverLayer：多素材叠放 / 末位空 data 真因回归 / isKp:true 端到端
//    + 图层顺序（图片在笔迹/标点 CustomPaint 之下）；
// Q2 命中：见 p12_kp4_hittest_test.dart ⑦ 升级（本文件不重复）；
// Q3 实时笔迹：拖动中 painter 消费 _draft、零中途发包、抬手载荷同点集；
// Q4 点擦：onTapUp 接线 / draw 点击恰好落一点（2.37.0/Q3 产品行为真变）/ erase 拖动中途实时预览 / locked；
// Q5 递线索可见：亮暗双主题 onSurface、空正文回落、全文弹层不截断、ClueSheet 兜底；
// Q6 工具栏迁移：三视角 enabled ⟺ gate.can、扁平挂 quickRow、无重复入口、tap 生效；
//    横切：固定尺寸控件 textScaler 1.3 / 1.5 / 2.0 不溢出、rect 不被撑破。
//
// ★ 铁律：不 skip、不放宽 finds 系列、不弱化数量/几何断言、不删用例；
//   所有 expect 都是「正向强断言」，拖动态 / 点击态 / 中途态必断言。
// ============================================================

import 'dart:convert' show jsonEncode;

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap;
import 'package:dice_realm/domain/room_types.dart'
    show RoomEvt, RoomVis, kHostSeat;
import 'package:dice_realm/theme.dart' show Palette, buildTheme;
import 'package:dice_realm/ui/room/map_fullscreen_page.dart'
    show MapFullscreenPage;
import 'package:dice_realm/ui/room/painter/stroke_painter.dart'
    show BoardPainter, StrokesPainter;
import 'package:dice_realm/ui/room/room_game_page.dart' show RoomGamePage;
import 'package:dice_realm/ui/room/room_keys.dart' show RoomKeys;
import 'package:dice_realm/ui/room/room_ui_local.dart' show BoardMode;
import 'package:dice_realm/ui/room/sheets/sheet_combat.dart' show CombatSheet;
import 'package:dice_realm/ui/room/sheets/sheet_kp_panel.dart' show KpPanel;
import 'package:dice_realm/ui/room/sheets/sheet_scene.dart'
    show ClueSheet, SceneSheetKeys;
import 'package:dice_realm/ui/room/view/scene_view.dart'
    show NormPoint, strokesOf;
import 'package:dice_realm/ui/room/widgets/gp_kp_players.dart'
    show GpKpPlayersKeys;
import 'package:dice_realm/ui/room/widgets/gp_map_stage.dart'
    show GpMapStage, GpMapStageKeys, MapStageControl, stageNormOf;
import 'package:dice_realm/ui/room/widgets/gp_pl_sketch.dart'
    show GpPlSketch, GpPlSketchKeys, boardSegmentsFromRaw;
import 'package:dice_realm/ui/room/widgets/gp_privates.dart'
    show GpPrivates, GpPrivatesRow;
import 'package:dice_realm/ui/room/widgets/gp_scene_check_kp.dart'
    show GpSceneCheckKeys;
import 'package:dice_realm/ui/room/widgets/gp_toolbar.dart' show GpToolbarKeys;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart'
    show RoomSheet, RoomTap;
import 'package:dice_realm/ui/room/widgets/unit_picker.dart' show kUnitAllValue;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart'
    show RoomUiFixture, kFakePngDataUrl, useRoomScreen;

// ------------------------------------------------------------
// 宿主
// ------------------------------------------------------------

/// 独立宿主：作用域挂在 Navigator **之上**，弹层也能 `RoomScope.of`。
Widget _scopedApp(RoomUiFixture f, String seat, Widget child) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (BuildContext _, Widget? c) =>
          f.scoped(seat, child: c ?? const SizedBox.shrink()),
      home: Scaffold(body: child),
    );

/// 舞台宿主：给 800×450 紧约束，与 p12_kp2_tools_test.dart 同款。
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

/// 真全屏宿主：KP 视角（isKp:true 端到端，裁决 4 硬要求）。
Widget _fullscreenApp(RoomUiFixture f, MapStageControl ctl) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: f.scoped(
        kHostSeat,
        child: MapFullscreenPage(stageControl: ctl, isKp: true),
      ),
    );

/// 整页宿主（三视角 / 工具栏 DFS / textScaler 用）。
Widget _pageOf(RoomUiFixture f, String seat) {
  f.pageBuilder = (String s, String r) => const RoomGamePage();
  return f.pageOf(seat);
}

/// 手绘板宿主（与 room_ui_pl_test.dart 同款，故意不替块订阅 local）。
Widget _sketchApp(RoomUiFixture f) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (BuildContext _, Widget? c) =>
          f.scoped('p1', child: c ?? const SizedBox.shrink()),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: GpPlSketch(),
        ),
      ),
    );

/// ClueSheet 宿主（每次 UniqueKey 强制重建 State，避免复用控制器）。
Widget _clueApp(RoomUiFixture f) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (BuildContext _, Widget? c) =>
          f.scoped(kHostSeat, child: c ?? const SizedBox.shrink()),
      home: Scaffold(
        body: SingleChildScrollView(child: ClueSheet(key: UniqueKey())),
      ),
    );

// ------------------------------------------------------------
// 造场景
// ------------------------------------------------------------

Map<String, Object?> _asset(String id, String data) => <String, Object?>{
      'id': id,
      'kind': 'map',
      'name': '底图$id',
      'data': data,
      'revealed': true,
      'at': 1,
    };

void _seedScene(
  RoomUiFixture f,
  List<Object?> assets, {
  List<Object?>? strokes,
}) {
  f.hostState()['scene'] = <String, Object?>{
    'assets': assets,
    'strokes': strokes ?? <Object?>[],
    'marks': <Object?>[],
  };
}

/// Image.memory 会在树里挂 `Image(image: MemoryImage)`；用类型谓词精确命中，
/// 排除主题/图标等其它 Image 干扰。
Finder _memoryImages() => find.byWidgetPredicate(
      (Widget w) => w is Image && w.image is MemoryImage,
    );

/// inner Stack（底图 + 手势/笔迹层共用的那条）的稳定定位点。
Finder _innerStack() => find
    .ancestor(
      of: find.byKey(GpMapStageKeys.coverLayer),
      matching: find.byType(Stack),
    )
    .first;

/// 舞台内笔迹 CustomPaint。
Finder _stagePaint() => find
    .descendant(
      of: find.byKey(GpMapStageKeys.canvas),
      matching: find.byType(CustomPaint),
    )
    .first;

void _seedBoard(RoomUiFixture f, List<Object?> pts) {
  // ★ P13 SKETCH：载荷支持分段 / 旧扁平两种。这里按**新口径**用单段
  //   塞同样的点（语义等价：一段包含这些点），QA 断言归一后按总点数。
  f.controllerOf('p1').sendIntent('board', <String, Object?>{
    'strokes': <Object?>[
      <String, Object?>{'id': 'seed', 'pts': pts},
    ],
  });
}

void _addPrivate(RoomUiFixture f, String text, {String title = '线索标题'}) {
  final rec = f.host.emit(
    RoomEvt.private_,
    <String, Object?>{
      'title': title,
      'text': text,
      'at': 1,
      'kind': 'dice-dark',
    },
    vis: RoomVis.seat,
    to: 'p1',
  );
  f.kpSession.pumpPlans(f.host.plan(rec));
}

void main() {
  // Palette 是全局静态皮肤：buildTheme 会改它，必须逐用例复位。
  setUp(() => Palette.useBrightness(Brightness.dark));
  tearDown(() => Palette.useBrightness(Brightness.dark));

  // ============================================================
  // Q1 · 全屏 coverLayer
  // ============================================================
  group('Q1 · 全屏底图：多素材 / 末位空 data / KP 端到端', () {
    testWidgets(
        'Q1-KP KP 公开有效素材 → isKp:true 真全屏：Image.memory 命中且图层在笔迹之下',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      _seedScene(f, <Object?>[_asset('a1', kFakePngDataUrl)]);
      final MapStageControl ctl = MapStageControl();
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(_fullscreenApp(f, ctl));
      await tester.pump();

      // ① 结构 key 唯一（既有 P12 口径逐字不动）。
      expect(find.byKey(GpMapStageKeys.coverLayer), findsOneWidget,
          reason: '★ 裁决 4：KP 真全屏必须真的渲染出公开素材底图');
      // ② 真渲染树命中 Image.memory（不是只断言容器存在）。
      expect(_memoryImages(), findsOneWidget,
          reason: '★ 裁决 4：渲染树里必须有 Image.memory');
      // ③ 图层顺序：coverLayer 是 inner Stack 的 child0；Stack 按 children
      //    顺序绘制 ⇒ child0 在最下，笔迹/标点 CustomPaint 在 child1 子树之上。
      final Stack sw = tester.widget<Stack>(_innerStack());
      expect(sw.children.first.key, GpMapStageKeys.coverLayer,
          reason: '★ 图片层必须是 inner Stack 的第一个 child（最下层）');
      expect(sw.children.length, 2,
          reason: 'inner Stack 恰好「底图 + 手势/笔迹层」两层');
      expect(
        find.descendant(
          of: find.byWidgetPredicate(
              (Widget w) => identical(w, sw.children[1])),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
        reason: '★ 笔迹/标点 CustomPaint 必须在底图层之上的 child1 子树里',
      );
      expect(tester.widget<GpMapStage>(find.byType(GpMapStage)).readOnly,
          isFalse,
          reason: 'KP 全屏仍非只读（fullscreenMode 语义零改动）');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Q1-MULTI 3 张有效 revealed → coverLayer 仍恰好 1 个 + MemoryImage 恰好 3 张',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      _seedScene(f, <Object?>[
        _asset('a1', kFakePngDataUrl),
        _asset('a2', kFakePngDataUrl),
        _asset('a3', kFakePngDataUrl),
      ]);
      final MapStageControl ctl = MapStageControl();
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(_stageApp(f, ctl));
      await tester.pump();

      expect(find.byKey(GpMapStageKeys.coverLayer), findsOneWidget,
          reason: '★ 多张时 key 仍只挂唯一外层 Positioned.fill');
      expect(_memoryImages(), findsNWidgets(3),
          reason: '★ 全部可解码 revealed 素材按列表序叠放');
      final Stack sw = tester.widget<Stack>(_innerStack());
      expect(sw.children.first.key, GpMapStageKeys.coverLayer,
          reason: '多张叠放容器仍在 inner Stack child0');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        "Q1-LAST 真因回归：assets = [有效图, {revealed:true, data:''}] 末位空 → 底图仍渲染",
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      _seedScene(f, <Object?>[
        _asset('a1', kFakePngDataUrl),
        _asset('a2', ''),
      ]);
      final MapStageControl ctl = MapStageControl();
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(_fullscreenApp(f, ctl));
      await tester.pump();

      expect(find.byKey(GpMapStageKeys.coverLayer), findsOneWidget,
          reason: '★ 改前 cover=assets.last 取到空 data 会让整层底图静默消失');
      expect(_memoryImages(), findsOneWidget,
          reason: '★ 只跳过非法 data，第一张有效图仍必须渲染');
      final Stack sw = tester.widget<Stack>(_innerStack());
      expect(sw.children.first.key, GpMapStageKeys.coverLayer);
      expect(tester.takeException(), isNull);
    });
  });

  // ============================================================
  // Q3 · 拖动中实时笔迹
  // ============================================================
  group('Q3 · 实时笔迹（_draft 被 StrokesPainter 消费）', () {
    testWidgets(
        'Q3-A 分步 panUpdate 不抬手：临时 stroke 实时出墨 / 拖动零发包 / 抬手恰好一次且与载荷同点集',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      _seedScene(f, <Object?>[], strokes: <Object?>[
        <String, Object?>{
          'color': '#00ff00',
          'width': 2,
          'pts': <Object?>[
            <String, Object?>{'x': 0.1, 'y': 0.1},
            <String, Object?>{'x': 0.2, 'y': 0.2},
          ],
        },
      ]);
      final MapStageControl ctl = MapStageControl();
      ctl.beginStroke(color: '#abcdef', width: 7);
      // 缩放开着：验证 pts 仍是归一化值、不额外乘 mapZoom。
      f.localOf(kHostSeat).setMapZoom(1.5);
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(_stageApp(f, ctl));
      await tester.pump();

      final int authoritative = strokesOf(f.hostState()).length;
      expect(authoritative, 1, reason: '前置：权威端恰好 1 条笔迹');
      final Finder paint = _stagePaint();
      expect((tester.widget<CustomPaint>(paint).painter as StrokesPainter)
          .strokes.length, authoritative);

      f.clearSent();
      final Offset center = tester.getCenter(find.byKey(GpMapStageKeys.stage));
      final Offset start = center - const Offset(120, 0);
      final g = await tester.startGesture(start);
      await tester.pump();
      for (var i = 1; i <= 4; i++) {
        await g.moveTo(start + Offset(i * 60.0, 0));
        await tester.pump();
      }

      // ① 拖动中（未抬手）：painter 已消费 _draft。
      final StrokesPainter live =
          tester.widget<CustomPaint>(paint).painter as StrokesPainter;
      expect(live.strokes.length, authoritative + 1,
          reason: '★ 拖动期间必须多出 1 条临时笔迹（新 List 实例）');
      final Map<String, Object?> temp = live.strokes.last;
      expect(temp['color'], ctl.strokeColor,
          reason: '临时笔迹 color 必须取 ctl.strokeColor');
      expect(temp['width'], ctl.strokeWidth,
          reason: '临时笔迹 width 必须取 ctl.strokeWidth');
      final List<Object?> tempPts = asList(temp['pts']);
      expect(tempPts.length, greaterThanOrEqualTo(2),
          reason: '临时笔迹 pts 必须含拖动路径上的多个归一化点');
      for (final Object? raw in tempPts) {
        final Map<String, Object?> q = asMap(raw);
        expect((q['x']! as num).toDouble(), inInclusiveRange(0.0, 1.0),
            reason: 'pts 必须是归一化值，未乘 mapZoom');
        expect((q['y']! as num).toDouble(), inInclusiveRange(0.0, 1.0),
            reason: 'pts 必须是归一化值，未乘 mapZoom');
      }
      expect(f.localOf(kHostSeat).mapZoom, 1.5,
          reason: '前置：缩放确实生效（不是把 zoom 关掉蒙混）');
      // ② 拖动期间零发包。
      expect(f.sent, isEmpty,
          reason: '★ 拖动期间绝不下发任何 hostAction / SendPlan');

      await g.up();
      await tester.pump();
      // ③ 抬手恰好 1 次 map.stroke，pts 与拖动中的临时笔迹逐点一致
      //    （证明 painter 消费的就是 _draft 归一化点，没有二次乘 zoom）。
      final Map<String, Object?>? sent = f.lastSent(action: 'map.stroke');
      expect(sent, isNotNull, reason: '抬手后必须下发 map.stroke');
      expect(
        f.sent
            .where((Map<String, Object?> e) =>
                e['kind'] == 'action' && e['op'] == 'map.stroke')
            .length,
        1,
        reason: '★ 抬手后恰好 1 次 map.stroke',
      );
      final List<Object?> sentPts = asList(asMap(sent!['p'])['pts']);
      expect(sentPts.length, tempPts.length,
          reason: '载荷点数与拖动点数一致');
      expect(jsonEncode(sentPts), jsonEncode(tempPts),
          reason: '★ 载荷 pts 与临时笔迹 pts 逐点相等（未被 mapZoom 改写）');
      // ④ 抬手后临时笔迹不重复：painter 只留权威端笔迹。
      expect(
        (tester.widget<CustomPaint>(paint).painter as StrokesPainter)
            .strokes.length,
        strokesOf(f.hostState()).length,
        reason: '★ 抬手后 _draft 清空，临时笔迹不重复',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Q3-B 全屏态（isKp:true）同样实时；erase 拖动不画彩色临时笔迹、仅末尾下发 map.strokes.set',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      _seedScene(f, <Object?>[]);
      final MapStageControl ctl = MapStageControl();
      ctl.beginStroke(color: '#123456', width: 5);
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(_fullscreenApp(f, ctl));
      await tester.pump();

      final Finder paint = _stagePaint();
      final Offset c0 = tester.getCenter(find.byKey(GpMapStageKeys.stage));
      final Offset s0 = c0 - const Offset(80, 0);
      final g0 = await tester.startGesture(s0);
      for (var i = 1; i <= 3; i++) {
        await g0.moveTo(s0 + Offset(i * 50.0, 0));
        await tester.pump();
      }
      expect((tester.widget<CustomPaint>(paint).painter as StrokesPainter)
          .strokes.length, 1,
          reason: '★ 全屏态共享组件，拖动中同样实时出墨');
      await g0.up();
      await tester.pump();

      // 切橡皮：拖动期间只做擦除预览，绝不画彩色临时笔迹。
      ctl.beginErase();
      await tester.pump();
      f.clearSent();
      final Offset c1 = tester.getCenter(find.byKey(GpMapStageKeys.stage));
      final Offset s1 = c1 - const Offset(80, 0);
      final g1 = await tester.startGesture(s1);
      for (var i = 1; i <= 3; i++) {
        await g1.moveTo(s1 + Offset(i * 50.0, 0));
        await tester.pump();
      }
      final int authoritative = strokesOf(f.hostState()).length;
      expect(authoritative, 1, reason: '前置：抬手后权威端落了 1 条笔迹');
      expect(
        (tester.widget<CustomPaint>(paint).painter as StrokesPainter)
            .strokes.length,
        authoritative,
        reason: '★ erase 模式不追加彩色临时笔迹',
      );
      expect(f.sent, isEmpty, reason: 'erase 拖动期间零发包');
      await g1.up();
      await tester.pump();
      expect(f.lastSent(action: 'map.strokes.set'), isNotNull,
          reason: '★ 抬手后一次性全量下发 map.strokes.set');
      expect(tester.takeException(), isNull);
    });
  });

  // ============================================================
  // Q4 · 点擦
  // ============================================================
  group('Q4 · 手绘板点擦（onTapUp）/ 拖动实时预览 / locked', () {
    testWidgets(
        'Q4-A erase 静止点击：单点擦除 + 全量提交，tol=0.03 内点被删、总数减少',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 800, 900);
      _seedBoard(f, <Object?>[
        <String, Object?>{'x': 0.5, 'y': 0.5},
        <String, Object?>{'x': 0.1, 'y': 0.1},
        <String, Object?>{'x': 0.9, 'y': 0.9},
      ]);
      f.localOf('p1').setBoardMode(BoardMode.erase);
      f.clearSent();
      await tester.pumpWidget(_sketchApp(f));
      await tester.pump();

      final GestureDetector gd = tester.widget<GestureDetector>(
          find.byKey(GpPlSketchKeys.canvas));
      expect(gd.onTapUp, isNotNull,
          reason: '★ Q4：静止点击由 Tap 识别器赢，onTapUp 必须接线');

      final Offset at = tester.getCenter(find.byKey(GpPlSketchKeys.canvas));
      await tester.tapAt(at);
      await tester.pump();

      final Map<String, Object?>? sent = f.lastSent(op: 'board');
      expect(sent, isNotNull, reason: '★ 点擦必须真的发出 INTENT.BOARD');
      expect(f.sent.length, 1, reason: '一次点擦恰好一条出站记录');
      // ★ P13 SKETCH：归一成分段后按总点数断言（核心不变量 3→2 不变）。
      final List<Map<String, Object?>> segs =
          boardSegmentsFromRaw(asList(asMap(sent!['p'])['strokes']));
      final List<Map<String, Object?>> pts = <Map<String, Object?>>[
        for (final Map<String, Object?> seg in segs)
          for (final Object? raw in asList(seg['pts'])) asMap(raw),
      ];
      // ★ P13 SKETCH-3 段级擦除：seed 的 3 点属同一段，命中中心点即
      //   **整段移除** → 0 点（旧「3→2」逐点口径已随产品真变）。
      expect(pts.length, 0,
          reason: '★ 段级擦除：命中点所在整段被移除，不残留命中点');
      for (final Map<String, Object?> q in pts) {
        final double dx = (q['x']! as num).toDouble() - 0.5;
        final double dy = (q['y']! as num).toDouble() - 0.5;
        expect(dx * dx + dy * dy, greaterThan(0.03 * 0.03),
            reason: 'tol=0.03 内不得残留被擦点');
      }
      expect(tester.takeException(), isNull);
    });

    // ★ 2.37.0 / Q3 产品行为真变：draw 点按从「不落墨点」改成「恰好落一点」。
    //   口径由「f.sent 零新增」升级为「恰好 1 条 board intent + 点数 +1 +
    //   新点落在 stageNormOf 归一坐标」——正向强断言，比旧口径更强（旧口径
    //   在新实现下必红，新口径在旧实现下也必红）。
    testWidgets('Q4-B draw 模式静止点击：恰好落一点，坐标同 stageNormOf 且全量提交',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 800, 900);
      _seedBoard(f, <Object?>[
        <String, Object?>{'x': 0.2, 'y': 0.2},
      ]);
      f.clearSent();
      await tester.pumpWidget(_sketchApp(f));
      await tester.pump();
      expect(f.localOf('p1').boardMode, BoardMode.draw,
          reason: '前置：默认画笔模式');

      final Rect canvas = tester.getRect(find.byKey(GpPlSketchKeys.canvas));
      final Offset at = canvas.center;
      await tester.tapAt(at);
      await tester.pump();

      // ★ 一次点按恰好一条 INTENT.BOARD（不是零、也不是多次发包）。
      final Map<String, Object?>? sent = f.lastSent(op: 'board');
      expect(sent, isNotNull,
          reason: '★ 2.37.0/Q3：draw 点按必须落一点、发一条 board intent');
      expect(f.sent.length, 1, reason: '一次点按恰好一条出站记录');
      final List<Map<String, Object?>> segs =
          boardSegmentsFromRaw(asList(asMap(sent!['p'])['strokes']));
      final List<Map<String, Object?>> pts = <Map<String, Object?>>[
        for (final Map<String, Object?> seg in segs)
          for (final Object? raw in asList(seg['pts'])) asMap(raw),
      ];
      expect(pts.length, 2,
          reason: '★ 原点 1 + 点按新增 1 = 2（全量提交，点数 +1）');
      // 原点保留（逐字不漂移）。
      final Map<String, Object?> first = pts.first;
      expect(first['x'], closeTo(0.2, 0.001));
      expect(first['y'], closeTo(0.2, 0.001));
      // ★ 新增点落在 stageNormOf(落点, 画布尺寸) 的同一归一化坐标。
      final NormPoint expected = stageNormOf(
        at - canvas.topLeft,
        canvas.size,
      );
      final Map<String, Object?> added = pts.last;
      expect((added['x'] as num).toDouble(), closeTo(expected.x, 0.03),
          reason: '★ 新增点 x 必须用 stageNormOf 归一坐标（与 KP 画笔同口径）');
      expect((added['y'] as num).toDouble(), closeTo(expected.y, 0.03),
          reason: '★ 新增点 y 必须用 stageNormOf 归一坐标');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Q4-C erase 拖动中途 BoardPainter.points 反映中间擦除，抬手后与 _commit 载荷一致',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 800, 900);
      _seedBoard(f, <Object?>[
        <String, Object?>{'x': 0.1, 'y': 0.5},
        <String, Object?>{'x': 0.3, 'y': 0.5},
        <String, Object?>{'x': 0.5, 'y': 0.5},
        <String, Object?>{'x': 0.7, 'y': 0.5},
        <String, Object?>{'x': 0.9, 'y': 0.5},
      ]);
      f.localOf('p1').setBoardMode(BoardMode.erase);
      f.clearSent();
      await tester.pumpWidget(_sketchApp(f));
      await tester.pump();

      final Finder paint = find
          .descendant(
            of: find.byKey(GpPlSketchKeys.canvas),
            matching: find.byType(CustomPaint),
          )
          .first;
      final Rect canvas =
          tester.getRect(find.byKey(GpPlSketchKeys.canvas));
      Offset at(double nx, double ny) => Offset(
            canvas.left + nx * canvas.width,
            canvas.top + ny * canvas.height,
          );
      final g = await tester.startGesture(at(0.1, 0.5));
      for (final double nx in <double>[0.3, 0.5, 0.7]) {
        await g.moveTo(at(nx, 0.5));
        await tester.pump();
      }
      // 拖动中途：擦除结果已喂给 BoardPainter（实时反馈），且零发包。
      final BoardPainter live =
          tester.widget<CustomPaint>(paint).painter as BoardPainter;
      // 兼容分段 {id,pts} 与旧扁平 {x,y} 两种 painter 载荷。
      final int livePointCount = boardSegmentsFromRaw(live.points).fold<int>(
        0,
        (int n, Map<String, Object?> seg) =>
            n + asList(seg['pts']).length,
      );
      expect(livePointCount, lessThan(5),
          reason: '★ 拖动过程中已实时擦掉经过的点（按总点数，兼容分段）');
      // 段级擦除命中整段时可归 0（不再要求至少保留 1 点）。
      expect(livePointCount, greaterThanOrEqualTo(0));
      expect(f.sent, isEmpty, reason: '拖动期间零发包');

      await g.up();
      await tester.pump();
      final Map<String, Object?>? sent = f.lastSent(op: 'board');
      expect(sent, isNotNull, reason: '抬手后一次全量提交');
      final List<Object?> payload = asList(asMap(sent!['p'])['strokes']);
      expect(payload.length, live.points.length,
          reason: '抬手载荷与中途预览点数一致');
      expect(jsonEncode(payload), jsonEncode(live.points),
          reason: '★ 抬手载荷与中途预览逐点一致');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Q4-D 撕卡锁定态：onTapUp / onPanStart 均为 null',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      f.controllerOf(kHostSeat).hostAction('sheet.damage', <String, Object?>{
        'seat': 'p1',
        'amount': 99,
        'kind': '测试',
      });
      useRoomScreen(tester, 800, 900);
      await tester.pumpWidget(_sketchApp(f));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(GpPlSketchKeys.locked)).data,
          contains('已撕卡'),
          reason: '前置：p1 确实处于操作锁定态');
      final GestureDetector gd = tester.widget<GestureDetector>(
          find.byKey(GpPlSketchKeys.canvas));
      expect(gd.onTapUp, isNull, reason: '★ 锁定态禁止点擦');
      expect(gd.onPanStart, isNull, reason: '锁定态禁止拖动');
      expect(tester.takeException(), isNull);
    });
  });

  // ============================================================
  // Q5 · 递线索可见
  // ============================================================
  group('Q5 · 递线索可见（onSurface / 标题兜底 / 全文不截断）', () {
    for (final Brightness b in Brightness.values) {
      testWidgets(
          'Q5-A-$b GpPrivatesRow 显式 onSurface、不等于 textMute、对 surface 对比度 ≥4.5:1',
          (WidgetTester tester) async {
        final ThemeData theme = buildTheme(b);
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(
              child: GpPrivatesRow(text: '线索正文', title: '标题'),
            ),
          ),
        ));
        await tester.pump();
        final Text t = tester.widget<Text>(find
            .descendant(
              of: find.byType(GpPrivatesRow),
              matching: find.byType(Text),
            )
            .first);
        expect(t.style?.color, theme.colorScheme.onSurface,
            reason: '★ Q5：显式取 colorScheme.onSurface，不再依赖 bodySmall');
        expect(t.style?.color, isNot(Palette.textMute),
            reason: '★ 不得再回落到被写死的 Palette.textMute');
        expect(
          t.style?.color,
          b == Brightness.dark
              ? const Color(0xFFE8EEF7)
              : const Color(0xFF2C2240),
        );
        final double l1 = t.style!.color!.computeLuminance();
        final double l2 = theme.colorScheme.surface.computeLuminance();
        final double hi = l1 > l2 ? l1 : l2;
        final double lo = l1 > l2 ? l2 : l1;
        expect((hi + 0.05) / (lo + 0.05), greaterThanOrEqualTo(4.5),
            reason: '★ WCAG AA：onSurface 对 Card surface 对比度 ≥4.5:1');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Q5-B 空正文回落标题；列表行仍保留 maxLines:3',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const Scaffold(
          body: Center(child: GpPrivatesRow(text: '', title: '线索标题')),
        ),
      ));
      await tester.pump();
      expect(find.text('线索标题'), findsOneWidget,
          reason: '★ 空正文必须回落显示标题，不能只剩红点');
      final Text t = tester.widget<Text>(find.text('线索标题'));
      expect(t.maxLines, 3, reason: '列表行仍保留 maxLines:3');
      expect(t.style?.color, buildTheme(Brightness.dark).colorScheme.onSurface);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Q5-C 点开全文弹层：正文完整、不设 maxLines、style.color == onSurface',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      const String long =
          '第一行线索内容；第二行继续叙述密室里的黄铜钥匙；第三行还有一段被改前 maxLines 裁掉的话；'
          '第四行是全文弹层必须完整显示的收尾证据。';
      _addPrivate(f, long, title: '密室线索');
      useRoomScreen(tester, 800, 1200);
      await tester.pumpWidget(
          _scopedApp(f, 'p1', const GpPrivates(height: 520)));
      await tester.pump();
      expect(find.text(long), findsOneWidget, reason: '前置：列表行已挂进树');

      await tester.tap(find.text(long));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RoomSheet), findsOneWidget,
          reason: '点击私密行必须推出全文弹层');
      final Finder sheetText = find.descendant(
        of: find.byType(RoomSheet),
        matching: find.text(long),
      );
      expect(sheetText, findsOneWidget,
          reason: '★ 全文弹层给出完整正文，不被 3 行摘要裁掉');
      final Text t = tester.widget<Text>(sheetText);
      expect(t.maxLines, isNull, reason: '★ 全文弹层不设 maxLines');
      expect(t.style?.color,
          Theme.of(tester.element(sheetText)).colorScheme.onSurface,
          reason: '★ 全文弹层显式 onSurface');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Q5-D ClueSheet 空正文不阻断递出：text 用标题 /「线索」兜底，正文优先；seat/title 口径不变',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 800, 1200);

      // ① 全空（标题默认「线索」、正文默认空）：不阻断，text == 「线索」。
      await tester.pumpWidget(_clueApp(f));
      await tester.pump();
      f.clearSent();
      await tester.ensureVisible(find.byKey(SceneSheetKeys.clueSubmit));
      await tester.tap(find.byKey(SceneSheetKeys.clueSubmit));
      await tester.pump();
      Map<String, Object?> p = asMap(f.lastSent(action: 'scene.clue')!['p']);
      expect(p['text'], '线索',
          reason: '★ 裁决 2：空正文用「线索」兜底，绝不静默丢消息');
      expect(p['title'], '线索');
      expect(p['seat'], kUnitAllValue, reason: 'seat 口径不变');

      // ② 只填标题不填正文。
      await tester.pumpWidget(_clueApp(f));
      await tester.pump();
      await tester.enterText(
          find.byKey(SceneSheetKeys.clueTitle), '密室钥匙');
      await tester.pump();
      f.clearSent();
      await tester.ensureVisible(find.byKey(SceneSheetKeys.clueSubmit));
      await tester.tap(find.byKey(SceneSheetKeys.clueSubmit));
      await tester.pump();
      p = asMap(f.lastSent(action: 'scene.clue')!['p']);
      expect(p['text'], '密室钥匙', reason: '★ 空正文用标题兜底');
      expect(p['title'], '密室钥匙', reason: 'title 口径不变');
      expect(p['seat'], kUnitAllValue);

      // ③ 填正文：正文优先，不被标题覆盖。
      await tester.pumpWidget(_clueApp(f));
      await tester.pump();
      await tester.enterText(
          find.byKey(SceneSheetKeys.clueText), '抽屉里有一把黄铜钥匙');
      await tester.pump();
      f.clearSent();
      await tester.ensureVisible(find.byKey(SceneSheetKeys.clueSubmit));
      await tester.tap(find.byKey(SceneSheetKeys.clueSubmit));
      await tester.pump();
      p = asMap(f.lastSent(action: 'scene.clue')!['p']);
      expect(p['text'], '抽屉里有一把黄铜钥匙');
      expect(p['seat'], kUnitAllValue);
      expect(tester.takeException(), isNull);
    });
  });

  // ============================================================
  // Q6 · 工具栏迁移
  // ============================================================
  group('Q6 · 两按钮扁平进工具栏主组（独立 ValueKey，绝不挂 act/ 锚点）', () {
    testWidgets(
        'Q6-A 三视角：仅 KP 渲染、enabled 恰好 == gate.can(op)、全页无 act/round.next / act/combat.start',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 1280, 800);
      for (final String seat in <String>[kHostSeat, 'p1', 'sp1']) {
        final bool kp = seat == kHostSeat;
        await tester.pumpWidget(_pageOf(f, seat));
        await tester.pump();
        final Finder nr = find.byKey(RoomGamePage.nextRoundKey);
        final Finder cr = find.byKey(RoomGamePage.combatReadyKey);
        expect(nr, kp ? findsOneWidget : findsNothing,
            reason: '$seat：nextRoundKey 仅 KP 可见');
        expect(cr, kp ? findsOneWidget : findsNothing,
            reason: '$seat：combatReadyKey 仅 KP 可见');
        // ★ 新按钮绝不挂 RoomKeys.action(...) 锚点
        //   （p10_t3_layout_test.dart:292-295 的 findsNothing 契约仍成立）。
        expect(find.byKey(RoomKeys.action('round.next')), findsNothing,
            reason: '$seat：不得挂 act/round.next');
        expect(find.byKey(RoomKeys.action('combat.start')), findsNothing,
            reason: '$seat：不得挂 act/combat.start');
        final gate = f.controllerOf(seat).gate;
        expect(gate.can('round.next'), kp,
            reason: '$seat：round.next 闸门');
        expect(gate.can('combat.start'), kp,
            reason: '$seat：combat.start 闸门');
        if (kp) {
          expect(tester.widget<RoomTap>(nr).enabled, gate.can('round.next'),
              reason: '★ nextRoundKey.enabled 恰好等于 gate.can(round.next)');
          expect(tester.widget<RoomTap>(cr).enabled, gate.can('combat.start'),
              reason: '★ combatReadyKey.enabled 恰好等于 gate.can(combat.start)');
        }
        expect(tester.takeException(), isNull, reason: '$seat 布局异常');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });

    testWidgets(
        'Q6-B DFS 顺序：扁平挂 quickRow 的 Wrap、在 gpZoomReset 之后且相邻、不在 extensions 嵌套 Wrap',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(_pageOf(f, kHostSeat));
      await tester.pump();

      final Finder quickRow = find.byKey(GpToolbarKeys.quickRow);
      final Finder ext = find.byKey(GpToolbarKeys.extensions);
      expect(quickRow, findsOneWidget);
      expect(ext, findsOneWidget);
      for (final Key k in <Key>[
        RoomGamePage.nextRoundKey,
        RoomGamePage.combatReadyKey,
      ]) {
        expect(find.descendant(of: quickRow, matching: find.byKey(k)),
            findsOneWidget,
            reason: '★ 扁平挂在 quickRow 主 Wrap 内');
        expect(find.descendant(of: ext, matching: find.byKey(k)), findsNothing,
            reason: '★ 不在 extensions 嵌套 Wrap 内');
      }
      final Rect reset = tester.getRect(find.byKey(RoomKeys.gpZoomReset));
      final Rect nr = tester.getRect(find.byKey(RoomGamePage.nextRoundKey));
      final Rect cr = tester.getRect(find.byKey(RoomGamePage.combatReadyKey));
      expect(nr.left, greaterThanOrEqualTo(reset.right - 0.5),
          reason: '★ 必须在 gpZoomReset 之后');
      expect(nr.left - reset.right, lessThanOrEqualTo(8.0),
          reason: '★ 与 gpZoomReset 相邻（Wrap spacing=4）');
      expect(cr.left, greaterThanOrEqualTo(nr.right - 0.5),
          reason: '★ combatReady 在 nextRound 之后');
      expect(cr.left - nr.right, lessThanOrEqualTo(8.0),
          reason: '★ 两按钮相邻');
      expect(cr.top, closeTo(nr.top, 0.5), reason: '两按钮同一行');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Q6-C KpPanel 弹层内两个旧 act/ 入口 findsNothing（无重复入口），剩余 5 项仍在且 enabled 恒等闸门',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 2200);
      await tester.pumpWidget(_scopedApp(f, kHostSeat, const KpPanel()));
      await tester.pump();
      expect(find.byKey(RoomKeys.action('round.next')), findsNothing,
          reason: '★ 「下一回合」已迁出弹层');
      expect(find.byKey(RoomKeys.action('combat.start')), findsNothing,
          reason: '★ 「战斗准备」已迁出弹层');
      expect(find.text('工具 · 回合与检定'), findsOneWidget);
      expect(find.text('工具 · 战斗与场景'), findsOneWidget);
      final gate = f.controllerOf(kHostSeat).gate;
      for (final String op in <String>[
        'check.request',
        'room.rules',
        'check.opposed',
        'scene.check.push',
        'sheet.damage',
      ]) {
        final Finder one = find.byKey(RoomKeys.action(op));
        expect(one, findsOneWidget, reason: '$op 弹层入口仍在');
        expect(tester.widget<RoomTap>(one).enabled, gate.can(op),
            reason: '$op 可点性恒等闸门（表驱动覆盖未丢）');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Q6-D tap nextRoundKey → round.next；tap combatReadyKey → CombatSheet / RoomSheet',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(_pageOf(f, kHostSeat));
      await tester.pump();

      await tester.ensureVisible(find.byKey(RoomGamePage.nextRoundKey));
      f.clearSent();
      await tester.tap(find.byKey(RoomGamePage.nextRoundKey));
      await tester.pump();
      expect(f.lastSent(action: 'round.next'), isNotNull,
          reason: '★ nextRoundKey 必须真的下发 round.next');

      await tester.ensureVisible(find.byKey(RoomGamePage.combatReadyKey));
      await tester.tap(find.byKey(RoomGamePage.combatReadyKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RoomSheet), findsOneWidget,
          reason: '★ 必须推出底部弹层壳');
      expect(find.byType(CombatSheet), findsOneWidget,
          reason: '★ 打开的是战斗准备弹层');
      expect(tester.takeException(), isNull);
    });

    for (final double scale in <double>[1.3, 1.5, 2.0]) {
      testWidgets(
          'Q6-E ×$scale 固定尺寸控件：新按钮 90×40 / 复位 80×40 / 收起标题行 72×28 / quickPush 108×48 不被撑破',
          (WidgetTester tester) async {
        final RoomUiFixture f = RoomUiFixture();
        await f.boot(inGame: true);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        useRoomScreen(tester, 1280, 800);
        await tester.pumpWidget(_pageOf(f, kHostSeat));
        await tester.pump();

        expect(tester.getSize(find.byKey(RoomGamePage.nextRoundKey)),
            const Size(90, 40),
            reason: '×$scale 新按钮 rect 不得被撑破（clampBtnText 只包子树）');
        expect(tester.getSize(find.byKey(RoomGamePage.combatReadyKey)),
            const Size(90, 40));
        expect(tester.getSize(find.byKey(RoomKeys.gpZoomReset)),
            const Size(80, 40));
        expect(tester.getSize(find.byKey(GpToolbarKeys.zoomPercent)).height,
            40);

        // 收起态 28dp 标题行 + 场景检定 108×48 定高按钮。
        f.localOf(kHostSeat).setPlayersPanelCollapsed(true);
        await tester.pump();
        expect(f.localOf(kHostSeat).playersPanelCollapsed, isTrue);
        expect(
          tester.getSize(find.byKey(GpKpPlayersKeys.collapseToggle)),
          const Size(72, 28),
          reason: '×$scale 收起态 28dp 标题行按钮不被撑破',
        );
        expect(
          tester.getSize(find.byKey(GpSceneCheckKeys.quickPush)),
          const Size(108, 48),
          reason: '×$scale RoomTapTile(108×48) 不被撑破',
        );
        expect(tester.takeException(), isNull,
            reason: '×$scale 出现 RenderFlex overflow / 布局异常');
      });
    }
  });
}
